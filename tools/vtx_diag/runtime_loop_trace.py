"""Identity-safe inspection of versioned native transport trace capsules."""

from __future__ import annotations

from collections import Counter
from typing import Any


SCOPE_FIELDS = (
    "documentHigh", "documentLow", "sourceGeneration", "transportEpoch", "sampleRateBits",
    "semanticVersion", "linearFrequencyMode", "order", "pattern", "firstRow", "lastRow",
)
BIRTH_FIELDS = ("sourceGeneration", "transportEpoch", "birthSequence", "birthEventIndex")
SUMMARY_FIELDS = (
    "attemptedOccurrences", "appliedOccurrences", "suppressedOccurrences", "failedOccurrences",
    "recordedOccurrences", "droppedOccurrences",
)
EXPLICIT_LOOP = "explicit_loop"
FINITE_SONG = "finite_song"
OCCURRENCE_ACTIONS = {"user_loop_native_occurrence", "ordinary_native_occurrence"}
SUMMARY_ACTIONS = {"user_loop_native_summary", "ordinary_native_summary"}


class ScopedLoopTraceError(ValueError):
    """A scoped native capsule is malformed or cannot use an unscoped oracle."""


def has_scoped_loop_data(event: dict[str, Any]) -> bool:
    """Identify scoped rows before legacy numeric-ID classification."""
    return (
        "loopOccurrence" in event or "loopOccurrenceSummary" in event
        or "nativeTransportKind" in event or event.get("schemaVersion", 1) != 1
        or event.get("runtimeAction") in OCCURRENCE_ACTIONS | SUMMARY_ACTIONS
    )


def native_transport_kind(event: dict[str, Any]) -> str:
    """Validate the versioned discriminator without a legacy-ID fallback."""
    version = event.get("schemaVersion", 1)
    if type(version) is not int:
        raise ScopedLoopTraceError("invalid native trace schemaVersion")
    if version == 1 and "nativeTransportKind" not in event and event.get("runtimeAction") not in {
        "ordinary_native_occurrence", "ordinary_native_summary"
    }:
        return EXPLICIT_LOOP
    if version != 2 or event.get("nativeTransportKind") != FINITE_SONG:
        raise ScopedLoopTraceError("unsupported native trace schemaVersion/nativeTransportKind")
    return FINITE_SONG


def exact_integer(value: Any, field: str, minimum: int = 0) -> int:
    """Validate an integer without losing native UInt64 identity precision."""
    # Never pass UInt64 document/rate identities through Float: values above 2**53
    # must remain exact when constructing an occurrence or source binding key.
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value < 2**64:
        raise ScopedLoopTraceError(f"invalid native Loop integer field: {field}")
    return value


def loop_observation(event: dict[str, Any]) -> dict[str, Any] | None:
    """Read one exact scoped occurrence and its independent source-birth bindings."""
    if "loopOccurrence" not in event:
        if has_scoped_loop_data(event):
            native_transport_kind(event)
            if event.get("runtimeAction") in OCCURRENCE_ACTIONS or "loopOccurrenceSummary" not in event:
                raise ScopedLoopTraceError("native occurrence has no scoped capsule")
        return None
    kind = native_transport_kind(event)
    capsule = event["loopOccurrence"]
    if not isinstance(capsule, dict) or not isinstance(capsule.get("scope"), dict):
        raise ScopedLoopTraceError("native Loop occurrence has invalid scope")
    raw_scope = capsule["scope"]
    if (kind == FINITE_SONG and raw_scope.get("transportKind") != FINITE_SONG) or (
        kind == EXPLICIT_LOOP and "transportKind" in raw_scope
    ):
        raise ScopedLoopTraceError("native scope transportKind disagrees with its versioned envelope")
    scope: dict[str, Any] = {}
    for field in SCOPE_FIELDS:
        if field == "linearFrequencyMode":
            if not isinstance(raw_scope.get(field), bool):
                raise ScopedLoopTraceError("invalid native Loop frequency mode")
            scope[field] = raw_scope[field]
        else:
            scope[field] = exact_integer(raw_scope.get(field), field)
    key = {
        "nativeTransportKind": kind,
        "scope": scope,
        "batchSequence": exact_integer(capsule.get("batchSequence"), "batchSequence", 1),
        "eventOrdinal": exact_integer(capsule.get("eventOrdinal"), "eventOrdinal"),
        "eventID": exact_integer(capsule.get("eventID"), "eventID"),
    }
    if kind == FINITE_SONG:
        scope["transportKind"] = kind
    top_id = event.get("plannedEventID")
    if top_id is not None and exact_integer(top_id, "plannedEventID") != key["eventID"]:
        raise ScopedLoopTraceError("native Loop numeric event ID disagrees with its capsule")
    bindings: dict[str, Any] = {}
    for name in ("targetBirth", "sourceBefore", "sourceAfter"):
        birth = capsule.get(name)
        if birth is None:
            bindings[name] = None
        elif isinstance(birth, dict):
            bindings[name] = {
                "documentHigh": scope["documentHigh"], "documentLow": scope["documentLow"],
                **{field: exact_integer(birth.get(field), f"{name}.{field}") for field in BIRTH_FIELDS},
            }
        else:
            raise ScopedLoopTraceError(f"invalid native Loop source binding: {name}")
    return {
        "key": key,
        "localSourceIndex": exact_integer(capsule.get("localSourceIndex"), "localSourceIndex", -1),
        "opcode": exact_integer(capsule.get("opcode"), "opcode"),
        "disposition": exact_integer(capsule.get("disposition"), "disposition"),
        "plannedRuntimeFrame": exact_integer(capsule.get("plannedRuntimeFrame"), "plannedRuntimeFrame"),
        "appliedRuntimeFrame": exact_integer(capsule.get("appliedRuntimeFrame"), "appliedRuntimeFrame"),
        **bindings,
    }


def scoped_loop_summary(events: list[dict[str, Any]], limit: int = 20, *,
                        transport_kind: str = EXPLICIT_LOOP) -> dict[str, Any] | None:
    """Report occurrence identities, dispositions and completeness separately."""
    if not any(has_scoped_loop_data(event) for event in events):
        return None
    observations = [value for event in events if (value := loop_observation(event)) is not None
                    and native_transport_kind(event) == transport_kind]
    keys = [(transport_kind,) + tuple(value["key"]["scope"][field] for field in SCOPE_FIELDS) + (
        value["key"]["batchSequence"], value["key"]["eventOrdinal"], value["key"]["eventID"],
    ) for value in observations]
    totals = []
    for event in events:
        if "loopOccurrenceSummary" not in event:
            if event.get("runtimeAction") in SUMMARY_ACTIONS:
                raise ScopedLoopTraceError("native Loop summary has no scalar capsule")
            continue
        if native_transport_kind(event) != transport_kind:
            continue
        raw = event["loopOccurrenceSummary"]
        if not isinstance(raw, dict):
            raise ScopedLoopTraceError("native Loop summary has invalid scalar capsule")
        totals.append({field: exact_integer(raw.get(field), field) for field in SUMMARY_FIELDS})
    if not observations and not totals:
        return None
    consistent = all(
        value["attemptedOccurrences"] == value["appliedOccurrences"] + value["suppressedOccurrences"] + value["failedOccurrences"]
        and value["attemptedOccurrences"] == value["recordedOccurrences"] + value["droppedOccurrences"]
        for value in totals
    )
    return {
        "identity_policy": "scoped_ordinary_occurrence_v2" if transport_kind == FINITE_SONG else "scoped_loop_occurrence_v1",
        "observed_occurrence_count": len(observations),
        "scoped_occurrence_key_count": len(set(keys)),
        "duplicate_scoped_key_count": len(keys) - len(set(keys)),
        "raw_numeric_id_count": len({value["key"]["eventID"] for value in observations}),
        "disposition_counts": dict(sorted(Counter(str(value["disposition"]) for value in observations).items())),
        "transport_totals": totals,
        "dropped_occurrence_count": sum(value["droppedOccurrences"] for value in totals),
        "scalar_counters_consistent": consistent,
        "complete_observed_trace": bool(totals) and consistent and not any(value["droppedOccurrences"] for value in totals)
            and sum(value["recordedOccurrences"] for value in totals) == len(observations),
        "examples": observations[:max(0, limit)],
    }


def scoped_finite_song_summary(events: list[dict[str, Any]], limit: int = 20) -> dict[str, Any] | None:
    """Keep ordinary v2 occurrences and totals separate from v1 explicit Loop."""
    return scoped_loop_summary(events, limit, transport_kind=FINITE_SONG)


def require_unscoped_offline_correlation(events: list[dict[str, Any]], provided: bool) -> None:
    """Refuse an unscoped identity oracle for native Loop occurrences."""
    if provided and any(has_scoped_loop_data(event) for event in events):
        raise ScopedLoopTraceError(
            "native scoped trace IDs are plan-local; unscoped offline diagnostics cannot be used "
            "as their identity/effect oracle. Use an explicitly scoped execution oracle; "
            "omit offline diagnostics for audio/frame-only window inspection."
        )

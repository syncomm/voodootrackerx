"""Identity-safe inspection of additive native user-Loop trace capsules."""

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


class ScopedLoopTraceError(ValueError):
    """A native Loop capsule is malformed or cannot be joined to an unscoped oracle."""


def has_scoped_loop_data(event: dict[str, Any]) -> bool:
    """Identify native Loop rows before legacy numeric-ID classification."""
    return (
        "loopOccurrence" in event or "loopOccurrenceSummary" in event
        or event.get("runtimeAction") in {"user_loop_native_occurrence", "user_loop_native_summary"}
    )


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
        if event.get("runtimeAction") == "user_loop_native_occurrence":
            raise ScopedLoopTraceError("native Loop occurrence has no scoped capsule")
        return None
    capsule = event["loopOccurrence"]
    if not isinstance(capsule, dict) or not isinstance(capsule.get("scope"), dict):
        raise ScopedLoopTraceError("native Loop occurrence has invalid scope")
    raw_scope = capsule["scope"]
    scope: dict[str, Any] = {}
    for field in SCOPE_FIELDS:
        if field == "linearFrequencyMode":
            if not isinstance(raw_scope.get(field), bool):
                raise ScopedLoopTraceError("invalid native Loop frequency mode")
            scope[field] = raw_scope[field]
        else:
            scope[field] = exact_integer(raw_scope.get(field), field)
    key = {
        "scope": scope,
        "batchSequence": exact_integer(capsule.get("batchSequence"), "batchSequence", 1),
        "eventOrdinal": exact_integer(capsule.get("eventOrdinal"), "eventOrdinal"),
        "eventID": exact_integer(capsule.get("eventID"), "eventID"),
    }
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


def scoped_loop_summary(events: list[dict[str, Any]], limit: int = 20) -> dict[str, Any] | None:
    """Report occurrence identities, dispositions and completeness separately."""
    if not any(has_scoped_loop_data(event) for event in events):
        return None
    observations = [value for event in events if (value := loop_observation(event)) is not None]
    keys = [tuple(value["key"]["scope"][field] for field in SCOPE_FIELDS) + (
        value["key"]["batchSequence"], value["key"]["eventOrdinal"], value["key"]["eventID"],
    ) for value in observations]
    totals = []
    for event in events:
        if "loopOccurrenceSummary" not in event:
            if event.get("runtimeAction") == "user_loop_native_summary":
                raise ScopedLoopTraceError("native Loop summary has no scalar capsule")
            continue
        raw = event["loopOccurrenceSummary"]
        if not isinstance(raw, dict):
            raise ScopedLoopTraceError("native Loop summary has invalid scalar capsule")
        totals.append({field: exact_integer(raw.get(field), field) for field in SUMMARY_FIELDS})
    consistent = all(
        value["attemptedOccurrences"] == value["appliedOccurrences"] + value["suppressedOccurrences"] + value["failedOccurrences"]
        and value["attemptedOccurrences"] == value["recordedOccurrences"] + value["droppedOccurrences"]
        for value in totals
    )
    return {
        "identity_policy": "scoped_loop_occurrence_v1",
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


def require_unscoped_offline_correlation(events: list[dict[str, Any]], provided: bool) -> None:
    """Refuse an unscoped identity oracle for native Loop occurrences."""
    if provided and any(has_scoped_loop_data(event) for event in events):
        raise ScopedLoopTraceError(
            "native user-Loop trace IDs are plan-local; unscoped offline diagnostics cannot be used "
            "as their identity/effect oracle. Use an explicitly scoped execution oracle; "
            "omit offline diagnostics for audio/frame-only window inspection."
        )

#!/usr/bin/env python3
"""Require full native qualification unless a complete PR changes only allowed prose."""

import json
import os
from pathlib import Path
import re
import subprocess
from urllib.request import Request, urlopen


def api_get(route):
    """Read public PR metadata/files with the workflow's read-only token."""
    repo, token = os.environ["GITHUB_REPOSITORY"], os.environ["GH_TOKEN"]
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or not token:
        raise ValueError("missing API identity")
    request = Request(f"https://api.github.com/repos/{repo}/{route}", headers={
        "Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28"})
    with urlopen(request, timeout=20) as response:
        return json.load(response)


def snapshot(data):
    """Retain the independently counted PR identity before and after pagination."""
    head, base, count = data["head"]["sha"], data["base"]["sha"], data["changed_files"]
    if not all(isinstance(v, str) and re.fullmatch(r"[0-9a-f]{40}", v) for v in (head, base)):
        raise ValueError("invalid PR commits")
    if type(count) is not int or not 0 < count <= 3000:
        raise ValueError("unverifiable file count")
    return head, base, count


def documentation(path):
    """Allow only canonical Markdown paths under docs/ and the root README."""
    if not isinstance(path, str) or "\\" in path or any(ord(c) < 32 for c in path):
        return False
    if any(part in ("", ".", "..") for part in path.split("/")):
        return False
    return path == "README.md" or (path.startswith("docs/") and path.endswith(".md"))


def classify(event_name, event, head, fetch=api_get):
    """Fail closed on missing, partial, raced, ambiguous or non-documentation input."""
    result = {"schema": 1, "event": event_name, "source_sha": head, "required": True,
              "status": "NATIVE_REQUIRED", "reason": "event-always-full",
              "files_complete": False, "immutable_diff_verified": False,
              "changed_file_count": None, "changed_files": []}
    if event_name != "pull_request":
        return result
    try:
        number = event["number"]
        if type(number) is not int or number <= 0 or event["pull_request"]["head"]["sha"] != head:
            raise ValueError("invalid event identity")
        route = f"pulls/{number}"
        before = snapshot(fetch(route))
        if before[:2] != (head, event["pull_request"]["base"]["sha"]):
            raise ValueError("PR identity moved")
        count = result["changed_file_count"] = before[2]
        rows = []
        for page in range(1, (count + 99) // 100 + 1):
            chunk = fetch(f"{route}/files?per_page=100&page={page}")
            if not isinstance(chunk, list) or len(chunk) != min(100, count - len(rows)):
                raise ValueError("partial file page")
            rows.extend(chunk)
        if snapshot(fetch(route)) != before:
            raise ValueError("PR changed during pagination")
        files, names, paths = [], set(), []
        for row in rows:
            name, status = row["filename"], row["status"]
            if not isinstance(name, str) or name in names or status not in ("added", "modified", "removed", "renamed"):
                raise ValueError("ambiguous file record")
            names.add(name)
            item = {"filename": name, "status": status}
            paths.append(name)
            if status == "renamed":
                old = item["previous_filename"] = row["previous_filename"]
                if not isinstance(old, str) or not old or old == name:
                    raise ValueError("missing rename origin")
                paths.append(old)
            elif "previous_filename" in row:
                raise ValueError("unexpected rename origin")
            files.append(item)
        result.update(files_complete=True, changed_files=files, reason="outside-documentation-allowlist")
        if all(documentation(path) for path in paths):
            # A live PR can move away and back between API reads. Bind any skip
            # to an immutable comparison too; truncation or a different base diff is full.
            if count > 300:
                raise ValueError("immutable comparison file limit")
            pinned = fetch(f"compare/{before[1]}...{head}")
            commits = pinned["commits"]
            if (pinned["base_commit"]["sha"] != before[1] or not isinstance(commits, list) or not commits
                    or type(pinned["total_commits"]) is not int or pinned["total_commits"] != len(commits)
                    or commits[-1]["sha"] != head):
                raise ValueError("incomplete immutable commit identity")
            pinned_files = [{k: row[k] for k in ("filename", "status", "previous_filename") if k in row}
                            for row in pinned["files"]]
            if sorted(pinned_files, key=lambda row: row["filename"]) != sorted(files, key=lambda row: row["filename"]):
                raise ValueError("live and immutable files disagree")
            result.update(required=False, status="NATIVE_NOT_REQUIRED", reason="verified-markdown-only",
                          immutable_diff_verified=True)
    except (KeyError, ValueError, TypeError, OSError) as error:
        result.update(reason="change-list-unavailable", error_type=type(error).__name__)
    return result


def main():
    """Publish a decision, required-step output and summary; publication errors fail the job."""
    head = os.environ["NATIVE_SOURCE_SHA"]
    if subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != head:
        raise ValueError("checkout changed before classification")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    result = classify(os.environ["GITHUB_EVENT_NAME"], event, head, api_get)
    text = json.dumps(result, sort_keys=True)
    (Path(os.environ["NATIVE_POLICY_DIR"]) / "classification.json").write_text(text + "\n")
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"required={str(result['required']).lower()}\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
        summary.write(f"### {result['status']}\n\nSource: `{head}`. Reason: `{result['reason']}`.\n\n")
        summary.write("Full native qualification required.\n" if result["required"] else
                      "No native tests executed by this decision; ordinary PR checks still apply.\n")
    print(text)


if __name__ == "__main__":
    main()

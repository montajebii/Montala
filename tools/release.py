#!/usr/bin/env python3
"""Version and changelog management for Montala.

    python3 tools/release.py check [--tag vX.Y.Z]
    python3 tools/release.py draft [--since TAG] [--all]
    python3 tools/release.py notes X.Y.Z
    python3 tools/release.py prepare --version X.Y.Z [--build N] [--date YYYY-MM-DD]
                                     [--no-commit] [--skip-tests]

`check` is the CI/release gate: pubspec, the in-app constants, the changelog
section and (optionally) the git tag must agree.

`prepare` promotes the `Unreleased` changelog body into a dated version
section, bumps `pubspec.yaml` and `lib/core/app_version.dart`, runs the test
suite, then commits and tags the release. Pushing is deliberately manual:

    git push origin main --follow-tags
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
APP_VERSION = ROOT / "lib/core/app_version.dart"
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.M)
HEADING_RE = re.compile(
    r"^## \[(?P<version>Unreleased|\d+\.\d+\.\d+)\](?: - (?P<date>\d{4}-\d{2}-\d{2}))?\s*$",
    re.M,
)
PERSIAN = str.maketrans("0123456789.", "۰۱۲۳۴۵۶۷۸۹٫")

def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, capture_output=True
    )
    if check and result.returncode != 0:
        fail(f"git {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def read_version() -> tuple[str, int]:
    match = VERSION_RE.search(PUBSPEC.read_text())
    if not match:
        fail("pubspec.yaml has no 'version: X.Y.Z+N' line")
    return match.group(1), int(match.group(2))


def semver(value: str) -> tuple[int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", value.lstrip("v"))
    if not match:
        fail(f"not a semantic version: {value!r}")
    return tuple(int(part) for part in match.groups())


def latest_tag() -> str | None:
    tags = git("tag", "-l", "v*", "--sort=-version:refname").splitlines()
    return tags[0] if tags else None


def persian_version(version: str) -> str:
    return version.translate(PERSIAN)


def changelog_sections(text: str) -> list[dict]:
    matches = list(HEADING_RE.finditer(text))
    sections = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.end():end]
        # The link-reference block belongs to the document, not the last section.
        link_block = re.search(r"(?m)^\[[^\]]+\]:[ ^\n]*$", body)
        if link_block and index + 1 == len(matches):
            body = body[: link_block.start()]
        sections.append(
            {
                "version": match.group("version"),
                "date": match.group("date"),
                "start": match.start(),
                "heading_end": match.end(),
                "end": end,
                "body": body,
            }
        )
    return sections


def section(text: str, version: str) -> dict | None:
    return next(
        (entry for entry in changelog_sections(text) if entry["version"] == version),
        None,
    )


def body_without_links(body: str) -> str:
    lines = [line for line in body.splitlines() if not re.match(r"^\[[^\]]+\]:", line)]
    return "\n".join(lines).strip()


def update_link_block(text: str, version: str, previous: str | None) -> str:
    unreleased = f"[Unreleased]: https://github.com/montajebii/Montala/compare/v{version}...HEAD"
    release = (
        f"[{version}]: https://github.com/montajebii/Montala/compare/"
        f"v{previous}...v{version}"
        if previous
        else f"[{version}]: https://github.com/montajebii/Montala/releases/tag/v{version}"
    )

    lines = text.rstrip().splitlines()
    if any(line.startswith("[Unreleased]:") for line in lines):
        lines = [
            unreleased if line.startswith("[Unreleased]:") else line for line in lines
        ]
    else:
        lines += ["", unreleased]

    existing = next(
        (i for i, line in enumerate(lines) if line.startswith(f"[{version}]:")), None
    )
    if existing is not None:
        lines[existing] = release
    else:
        anchor = next(
            i for i, line in enumerate(lines) if line.startswith("[Unreleased]:")
        )
        lines.insert(anchor + 1, release)

    return "\n".join(lines) + "\n"


def write_version(version: str, build: int) -> None:
    pubspec = PUBSPEC.read_text()
    PUBSPEC.write_text(
        VERSION_RE.sub(f"version: {version}+{build}", pubspec, count=1)
    )

    source = APP_VERSION.read_text()
    source = re.sub(
        r"const String kAppVersion = '[^']*';",
        f"const String kAppVersion = '{version}';",
        source,
    )
    source = re.sub(
        r"const String kAppVersionFa = '[^']*';",
        f"const String kAppVersionFa = '{persian_version(version)}';",
        source,
    )
    APP_VERSION.write_text(source)


def run(cmd: list[str]) -> None:
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=ROOT)
    if result.returncode != 0:
        fail(f"command failed: {' '.join(cmd)}")


def flutter_bin() -> str:
    local = ROOT / ".fvm/flutter_sdk/bin/flutter"
    if local.exists():
        return str(local)
    return "flutter"


def cmd_check(args: argparse.Namespace) -> None:
    version, build = read_version()
    source = APP_VERSION.read_text()
    app_match = re.search(r"const String kAppVersion = '([^']+)'", source)
    fa_match = re.search(r"const String kAppVersionFa = '([^']+)'", source)
    if not app_match or app_match.group(1) != version:
        fail(
            "lib/core/app_version.dart kAppVersion is "
            f"{app_match.group(1) if app_match else 'missing'}, expected {version}"
        )
    if not fa_match or fa_match.group(1) != persian_version(version):
        fail("lib/core/app_version.dart kAppVersionFa is out of sync")

    changelog = CHANGELOG.read_text()
    released = section(changelog, version)
    if released is None or not released["date"]:
        fail(f"CHANGELOG.md has no dated section for [{version}]")

    if args.tag:
        tag = args.tag.lstrip("v")
        if tag != version:
            fail(f"tag v{tag} does not match pubspec version {version}")

    latest = latest_tag()
    print(f"ok: version {version}+{build} (Android versionCode {build})")
    print(f"ok: changelog [{version}] - {released['date']}")
    if args.tag:
        print(f"ok: tag {args.tag}")
    elif latest:
        print(f"latest tag: {latest}")


def cmd_notes(args: argparse.Namespace) -> None:
    changelog = CHANGELOG.read_text()
    released = section(changelog, args.version.lstrip("v"))
    if released is None:
        fail(f"CHANGELOG.md has no section for [{args.version}]")
    body = body_without_links(released["body"])
    if not body:
        fail(f"changelog section [{args.version}] is empty")
    print(body)


COMMIT_SECTIONS = {
    "feat": "Added",
    "fix": "Fixed",
    "perf": "Changed",
    "refactor": "Changed",
    "change": "Changed",
    "data": "Changed",
    "revert": "Fixed",
    "build": "Build",
    "ci": "Build",
    "chore": "Build",
}
SKIP_TYPES = {"docs", "test", "style"}


def cmd_draft(args: argparse.Namespace) -> None:
    since = args.since or latest_tag()
    if not since:
        fail("no previous tag found; pass --since <ref>")
    log = git("log", "--no-merges", "--format=%s", f"{since}..HEAD").splitlines()
    buckets: dict[str, list[str]] = {}
    for subject in log:
        match = re.match(
            r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?!?:\s*(?P<text>.+)$", subject
        )
        if not match:
            continue
        kind = match.group("type")
        if kind in SKIP_TYPES or match.group("text").startswith("v"):
            continue
        heading = COMMIT_SECTIONS.get(kind)
        if not heading:
            continue
        text = match.group("text").strip()
        scope = match.group("scope")
        if scope:
            text = f"**{scope}:** {text}"
        text = text[0].upper() + text[1:]
        buckets.setdefault(heading, []).append(text)

    print(f"<!-- draft from {since}..HEAD; edit before releasing -->")
    if not buckets:
        print("\n(no user-facing commits)")
        return
    for heading in ("Added", "Changed", "Fixed", "Build"):
        if buckets.get(heading):
            print(f"\n### {heading}\n")
            for item in buckets[heading]:
                print(f"- {item}")
    print(
        "\n<!-- Review each line for accuracy; drop internal churn; "
        "then run tools/release.py prepare. -->"
    )


def cmd_prepare(args: argparse.Namespace) -> None:
    version = args.version.lstrip("v")
    new = semver(version)
    current, current_build = read_version()
    latest = latest_tag()
    if latest:
        previous_version = latest.lstrip("v")
        if new <= semver(previous_version):
            fail(f"{version} must be greater than the latest tag {latest}")
    else:
        previous_version = None

    if new < semver(current):
        fail(f"{version} is lower than the current pubspec version {current}")

    build = args.build if args.build is not None else current_build + 1
    if build <= current_build and version == current:
        fail(
            f"build number {build} must be greater than the current "
            f"{current_build} when re-releasing {version}"
        )
    if args.build is not None and args.build <= 0:
        fail("build number must be positive")

    text = CHANGELOG.read_text()
    unreleased = section(text, "Unreleased")
    if unreleased is None:
        fail("CHANGELOG.md has no [Unreleased] section")
    if section(text, version) is not None:
        fail(f"CHANGELOG.md already has a [{version}] section")

    body = body_without_links(unreleased["body"])
    if not body and not args.allow_empty:
        fail("the [Unreleased] section is empty; add entries first")
    if body and not re.search(r"(?m)^### ", body):
        fail("the [Unreleased] section needs at least one '### Added/Changed/...' heading")

    date = args.date or dt.date.today().isoformat()
    replacement = f"\n## [{version}] - {date}\n" + (f"\n{body}\n\n" if body else "\n")
    text = (
        text[: unreleased["heading_end"]]
        + replacement
        + text[unreleased["heading_end"]:].lstrip("\n")
    )
    text = update_link_block(text, version, previous_version)
    CHANGELOG.write_text(text)

    write_version(version, build)
    print(f"bumped to {version}+{build}")

    if not args.skip_tests:
        flutter = flutter_bin()
        run([flutter, "analyze", "--no-pub"])
        run([flutter, "test", "--no-pub"])

    if not args.no_commit:
        git("add", "-A")
        if git("status", "--porcelain"):
            git("commit", "-m", f"chore(release): v{version}", "-m", f"Release v{version} (build {build}).")
        tag = f"v{version}"
        if not git("tag", "-l", tag):
            git("tag", "-a", tag, "-m", f"Montala v{version}")
        print(f"committed and tagged {tag}")
        print("next: git push origin main --follow-tags")
    else:
        print("files updated; commit/tag skipped (--no-commit)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="validate version/tag/changelog consistency")
    check.add_argument("--tag", help="tag being released, e.g. v1.2.0")
    check.set_defaults(func=cmd_check)

    draft = sub.add_parser("draft", help="draft changelog entries from commits")
    draft.add_argument("--since", help="lower bound (default: latest tag)")
    draft.set_defaults(func=cmd_draft)

    notes = sub.add_parser("notes", help="print release notes for a version")
    notes.add_argument("version")
    notes.set_defaults(func=cmd_notes)

    prepare = sub.add_parser("prepare", help="promote changelog, bump, test, commit, tag")
    prepare.add_argument("--version", required=True)
    prepare.add_argument("--build", type=int)
    prepare.add_argument("--date")
    prepare.add_argument("--no-commit", action="store_true")
    prepare.add_argument("--skip-tests", action="store_true")
    prepare.add_argument("--allow-empty", action="store_true")
    prepare.set_defaults(func=cmd_prepare)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Reports per-file line coverage of the app target and fails below a minimum.

Usage:
  scripts/check-coverage.py path/to/Tests.xcresult [--minimum 80] [--report coverage.md]

The result bundle must come from `xcodebuild test -enableCodeCoverage YES`.
Writes a Markdown report (to --report, and to $GITHUB_STEP_SUMMARY when set) and exits 1
when the app target's line coverage is below --minimum percent.
"""

import argparse
import json
import os
import subprocess
import sys

APP_TARGET = "LF-Paper.app"


def load_report(result_bundle: str) -> dict:
    try:
        output = subprocess.run(
            ["xcrun", "xccov", "view", "--report", "--json", result_bundle],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except subprocess.CalledProcessError as error:
        sys.exit(f"xccov could not read {result_bundle}: {error.stderr.strip()}")
    return json.loads(output)


def app_target(report: dict) -> dict:
    for target in report.get("targets", []):
        if target.get("name") == APP_TARGET:
            return target
    sys.exit(f"No coverage for {APP_TARGET}; was the test run started with -enableCodeCoverage YES?")


def markdown(target: dict, minimum: float) -> str:
    percent = target["lineCoverage"] * 100
    verdict = "✅" if percent >= minimum else "❌"
    lines = [
        f"## Code coverage: {percent:.2f}% {verdict} (minimum {minimum:.0f}%)",
        "",
        f"{target['coveredLines']} of {target['executableLines']} lines in {APP_TARGET}.",
        "",
        "| Coverage | Lines | File |",
        "|---:|---:|---|",
    ]
    for file in sorted(target["files"], key=lambda f: (f["lineCoverage"], f["name"])):
        mark = " ⚠️" if file["lineCoverage"] * 100 < minimum else ""
        lines.append(
            f"| {file['lineCoverage'] * 100:.1f}%{mark} | {file['coveredLines']}/{file['executableLines']} | {file['name']} |"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("result_bundle")
    parser.add_argument("--minimum", type=float, default=80.0, help="minimum line coverage in percent")
    parser.add_argument("--report", help="also write the Markdown report to this file")
    args = parser.parse_args()

    if not os.path.isdir(args.result_bundle):
        sys.exit(f"Result bundle not found: {args.result_bundle}")

    target = app_target(load_report(args.result_bundle))
    report = markdown(target, args.minimum)
    print(report)
    for path in filter(None, [args.report, os.environ.get("GITHUB_STEP_SUMMARY")]):
        with open(path, "a", encoding="utf-8") as file:
            file.write(report)

    percent = target["lineCoverage"] * 100
    if percent < args.minimum:
        print(f"Coverage {percent:.2f}% is below the minimum of {args.minimum:.0f}%.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

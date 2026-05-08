#!/usr/bin/env python3
"""OmniScope v0.1.7 FFI/Unsafe Audit Runner"""
import json
import os
import sys
import subprocess
import glob

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(PROJECT, "outputs", "audit")
OMNISCOPE = os.path.join(PROJECT, "zig-out", "bin", "OmniScope")

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Find all .ll files
ll_files = (
    glob.glob(os.path.join(PROJECT, "corpus", "real_world", "other", "*.ll")) +
    glob.glob(os.path.join(PROJECT, "corpus", "real_world", "zkp", "*.ll"))
)

print("=" * 70)
print("  OmniScope v0.1.7 - FFI/Unsafe Boundary Security Audit")
print(f"  Output: {OUTPUT_DIR}")
print("=" * 70)
print()

results = []
total_issues = 0

for ll_file in sorted(ll_files):
    name = os.path.splitext(os.path.basename(ll_file))[0]
    json_out = os.path.join(OUTPUT_DIR, f"{name}.json")
    log_out = os.path.join(OUTPUT_DIR, f"{name}.log")

    # Run OmniScope
    proc = subprocess.run(
        [OMNISCOPE, "--json", "--debug", ll_file],
        capture_output=True,
        text=True,
    )

    if proc.returncode != 0:
        print(f"[FAIL] {name} (exit code {proc.returncode})")
        with open(log_out, "w") as lf:
            lf.write(proc.stderr)
        results.append({"name": name, "status": "fail", "issues": 0})
        continue

    # Save logs
    with open(log_out, "w") as lf:
        lf.write(proc.stderr)

    # Parse JSON output
    try:
        with open(json_out) as jf:
            data = json.load(jf)
        issues = data.get("issues", data.get("diagnostics", []))
        count = len(issues)
    except Exception as e:
        with open(json_out, "w") as jf:
            jf.write(proc.stdout)
        count = 0
        try:
            # Try parsing stdout as fallback
            data = json.loads(proc.stdout)
            issues = data.get("issues", data.get("diagnostics", []))
            count = len(issues)
        except:
            pass

    total_issues += count
    results.append({"name": name, "status": "ok", "issues": count})
    print(f"[OK]   {name:<25s} -> {count:>3d} issues")

print()
print("=" * 70)
passed = sum(1 for r in results if r["status"] == "ok")
failed = sum(1 for r in results if r["status"] == "fail")
print(f"  Summary: {passed}/{len(results)} passed, {failed} failed")
print(f"  Total Issues Found: {total_issues}")
print("=" * 70)

# Save summary
with open(os.path.join(OUTPUT_DIR, "_audit_summary.json"), "w") as sf:
    json.dump({
        "version": "0.1.7",
        "total_files": len(results),
        "passed": passed,
        "failed": failed,
        "total_issues": total_issues,
        "results": results,
    }, sf, indent=2)

print(f"\n  Summary saved to: outputs/audit/_audit_summary.json")

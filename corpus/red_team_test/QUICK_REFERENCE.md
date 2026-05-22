# Language Detection Fix - Quick Reference

## Run the Test

```bash
cd ~/code/zigcode/OmniScope
./zig-out/bin/OmniScope ./corpus/red_team_test/language_detection_fix_test_complete.bc
```

## Output Interpretation Guide

### 1. Function Loading
```
info: [INFO] Loaded: 27 functions
```
**What it means**: OmniScope loaded 27 functions from the bitcode file.

**What to check**: 
- Is the count correct? (should match your source)
- Are all your functions included?

### 2. Language Detection
```
info: [INFO] LANG-DETECT: module language = c, confidence = 57.7%, method = sampling
```
**What it means**: 
- Detected language: C
- Confidence: 57.7% (mixed language codebase)
- Method: Statistical sampling of function names

**What to check**:
- Is the detected language correct for your main code?
- Low confidence (< 70%) indicates mixed languages

### 3. Cross-Language Edges
```
info: [INFO] CallGraph: extracted 22 cross-language edges
```
**What it means**: Found 22 function calls across language boundaries.

**What to check**:
- These are FFI boundaries where violations can occur
- Each edge is a potential ownership mismatch

### 4. Memory Leaks
```
info: [INFO] PointerOwnership: Found 10 memory leaks
```
**What it means**: Detected 10 memory leaks.

**What to check**:
- Are these real leaks or intentional test patterns?
- Check the function names to locate source code

### 5. Zone Classification
```
info:   FFI zone (analyzed):         33
info:   Unknown zone:                36
```
**What it means**:
- FFI zone: Cross-language boundary functions (deeply analyzed)
- Unknown zone: User code requiring analysis

**What to check**:
- FFI zone functions are the most critical
- Unknown zone may need manual review

### 6. Issue Breakdown
```
info:       Memory leak:              10
```
**What it means**: Found 10 memory leak issues.

**What to check**:
- Review each issue's location
- Determine if it's a real bug or test pattern

### 7. Origin Breakdown
```
info:       ✅ User code:                 10 (ACTION NEEDED)
info:       📦 Third-party (FFI):          0
info:       📚 Stdlib (suppressed):       0
info:       🔧 Compiler (ignored):        0
```
**What it means**:
- ✅ User code: Issues in your code (fix these!)
- 📦 Third-party: Issues in FFI libraries
- 📚 Stdlib: Issues in standard library (suppressed)
- 🔧 Compiler: Issues in compiler-generated code (ignored)

**What to check**:
- Focus on "User code" issues
- Third-party issues may need library updates

### 8. Unchecked Return Values
```
info: [INFO] ReturnCheck: Analyzed functions, found 1 unchecked return values
```
**What it means**: Found 1 function that doesn't check a return value.

**What to check**:
- This is often a security risk (command injection, etc.)
- Check the function name and add error handling

### 9. Performance
```
info: [INFO] Time: 21ms
```
**What it means**: Analysis took 21 milliseconds.

**What to check**:
- Should be fast (< 100ms for small files)
- If slow, check for complex control flow

## Common Patterns

### Pattern 1: Cross-Language Ownership Violation
```
Issue: Memory leak in test_rust_alloc_c_free
```
**Meaning**: Rust allocated memory, C freed it (or vice versa).

**Fix**: Use consistent allocation/deallocation across languages.

### Pattern 2: Unchecked Dangerous Function
```
Issue: Unchecked return from 'system'
```
**Meaning**: Called `system()` without checking return value.

**Fix**: Add error handling:
```c
int result = system("ls");
if (result != 0) {
    // Handle error
}
```

### Pattern 3: False Positive (Should NOT Appear)
```
Issue: Dangerous pattern in 'register_user'
```
**Meaning**: Function name contains "register" or "batch".

**Status**: ✅ FIXED in v0.1.8 - these no longer appear!

## Locating Source Code

### Step 1: Get function name from report
```
location.function: "test_rust_alloc_c_free"
```

### Step 2: Find in source
```bash
grep -n "test_rust_alloc_c_free" corpus/red_team_test/language_detection_fix_test_complete.c
```

### Step 3: Open in editor
```bash
vim corpus/red_team_test/language_detection_fix_test_complete.c +95
```

## Quick Commands

```bash
# Run analysis
./zig-out/bin/OmniScope ./corpus/red_team_test/language_detection_fix_test_complete.bc

# Save to JSON
./zig-out/bin/OmniScope --json ./corpus/red_team_test/language_detection_fix_test_complete.bc > report.json

# View summary
jq '.summary' report.json

# View all issues
jq '.issues' report.json

# Count by severity
jq -r '.issues | group_by(.severity) | map({severity: .[0].severity, count: length}) | .[]' report.json

# Find high severity issues
jq '.issues[] | select(.severity == "high")' report.json
```

## Expected Results

For the language detection fix test, you should see:

- ✅ 27 functions loaded
- ✅ 22 cross-language edges
- ✅ 10 memory leaks detected
- ✅ 1 unchecked return value
- ✅ 11 total issues
- ✅ No false positives for register_user, batch_process
- ✅ True positive for dangerous_system_call
- ✅ Analysis time < 30ms

## Troubleshooting

### Issue: No issues found
**Cause**: Functions may be in safe zone or stdlib.
**Fix**: Check zone classification summary.

### Issue: Too many false positives
**Cause**: Using old version before v0.1.8.
**Fix**: Update to latest version.

### Issue: Missing functions
**Cause**: Functions optimized away or not in bitcode.
**Fix**: Compile with -O0 and -g flags.

### Issue: Slow analysis
**Cause**: Complex control flow or large file.
**Fix**: Use --focus-user-code to skip stdlib.

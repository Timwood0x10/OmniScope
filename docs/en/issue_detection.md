# Issue Detection Passes

## Overview

Multiple specialized passes for detecting security and code quality issues.

## Location

```text
src/pass/analysis/issue/
├── ffi_body_check.zig
├── ffi_unsafe.zig
├── free_validation.zig
├── integer_overflow.zig
├── malloc_check.zig
├── memory_safety.zig
└── return_check.zig
```

## FFIBodyCheckPass

Detects dangerous function calls inside FFI boundary functions.

```zig
pub const FFIBodyCheckPass = struct {
    pub const name = "ffi-body-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};
};
```

### Detection

- Unchecked malloc results
- Free on non-malloc pointers
- Double free
- Unknown FFI pointer usage
- Format string vulnerabilities
- Command injection

## FFIUnsafePass

Identifies unsafe FFI calls based on dangerous function patterns.

```zig
pub const FFIUnsafePass = struct {
    pub const name = "ffi-unsafe";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    const DangerousPatterns = &[_][]const u8{
        "system", "exec", "popen", "malloc", "free", "strcpy", "gets",
    };
};
```

### Dangerous Patterns

- `system`, `exec`, `popen` - Command injection
- `malloc`, `free` - Memory safety
- `strcpy`, `gets` - Buffer overflow

## FreeValidationPass

Detects calls to free() on non-malloc pointers.

```zig
pub const FreeValidationPass = struct {
    pub const name = "free-validation";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### Detection

- **invalid_free** - Free on non-malloc pointers

### Pointer Origins

- `from_malloc` - From malloc/calloc/realloc
- `from_param` - From function parameter
- `from_global` - From global variable
- `unknown` - Unknown origin

## IntegerOverflowPass

Detects potential integer overflow in arithmetic operations.

```zig
pub const IntegerOverflowPass = struct {
    pub const name = "integer-overflow";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### Operations Analyzed

- `add`, `sub`, `mul`

### Detection Conditions

- Non-constant values
- Small bit-width integers (i8, i16)
- Result may exceed type range

## MallocCheckPass

Detects malloc return values used without null check.

```zig
pub const MallocCheckPass = struct {
    pub const name = "malloc-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### Detection

- **malloc_unchecked** - Malloc used without null check

### Functions Checked

- `malloc`, `calloc`, `realloc`, `aligned_alloc`, `reallocarray`

## MemorySafetyPass

Detects memory safety issues (double free).

```zig
pub const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### Detection

- **double_free** - Same pointer freed twice

## ReturnCheckPass

Detects unchecked return values from dangerous functions.

```zig
pub const ReturnCheckPass = struct {
    pub const name = "return-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
};
```

### Dangerous Functions

- `malloc`, `open`, `system`, `fork`, `pthread_create`

### Detection

- **unchecked_return** - Return value not used

### Safe to Ignore

- `printf`, `fclose` - Output/close functions

## Severity Levels

- **low** - Low severity
- **medium** - Medium severity
- **high** - High severity
- **critical** - Critical severity

## Confidence Scores

- **0.0 - 0.3** - Low confidence
- **0.3 - 0.7** - Medium confidence
- **0.7 - 1.0** - High confidence

## Usage Example

```zig
var malloc_check = MallocCheckPass.init(ctx, diag, store, query);
defer malloc_check.deinit();

const result = try malloc_check.run(func_id);
for (result.issues) |issue| {
    std.debug.print("[{}] {} (confidence: {:.2})\n", .{
        issue.severity, issue.message, issue.confidence
    });
}
```

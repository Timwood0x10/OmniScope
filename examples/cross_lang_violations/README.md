# Cross-Language Ownership Violation Examples

This directory contains test cases for cross-language ownership violations detected by OmniScope.

## Test Cases

### 1. Rust Box -> C Free (`rust_box_c_free/`)

**Scenario**: Rust Box::into_raw transfers ownership to C, but C calls free() instead of returning ownership.

**Expected Detection**: `rust_freed_by_c` violation

```rust
// Rust side
let ptr = Box::into_raw(Box::new(42));
c_take_ownership(ptr);

// C side
void c_take_ownership(int* ptr) {
    free(ptr);  // WRONG! Should use Box::from_raw
}
```

### 2. C Malloc -> Rust Drop (`c_malloc_rust_drop/`)

**Scenario**: C malloc allocates memory, Rust takes ownership via Box::from_raw.

**Expected Detection**: `c_freed_by_rust` violation

```c
// C side
int* ptr = malloc(sizeof(int));
rust_take_ownership(ptr);

// Rust side
extern "C" fn rust_take_ownership(ptr: *mut i32) {
    unsafe { Box::from_raw(ptr) };  // WRONG! Should use free()
}
```

### 3. Borrow Escape (`borrow_escape/`)

**Scenario**: Rust borrows pointer via as_ptr(), C stores it globally.

**Expected Detection**: `borrow_escape` violation

```rust
// Rust side
let s = String::from("hello");
let ptr = s.as_ptr();
c_store_globally(ptr);
// s dropped here, ptr becomes dangling

// C side
static const char* stored;
void c_store_globally(const char* p) {
    stored = p;  // WRONG! Borrowed pointer escaped
}
```

### 4. Double Free Across FFI (`double_free_ffi/`)

**Scenario**: Memory freed by both Rust and C.

**Expected Detection**: `cross_lang_double_free` violation

```rust
// Rust side
let ptr = Box::into_raw(Box::new(42));
c_process(ptr);
// Forgot that C already freed it
let _ = unsafe { Box::from_raw(ptr) };  // Double free!

// C side
void c_process(int* ptr) {
    free(ptr);
}
```

## Running Tests

```bash
# Build all examples
make all

# Run OmniScope analysis
make run

# Expected output should show violations
```

## Architecture

These tests validate the 3-layer architecture:

```
Layer 1: LifetimeEngine (resource state machine)
Layer 2: SemanticMapper (IR -> semantic actions)
Layer 3: BoundaryAnalyzer (cross-language contract checker)
```

## Detection Rules

| Origin Lang | Action Lang | Action | Violation |
|-------------|-------------|--------|-----------|
| Rust | C | free | rust_freed_by_c |
| C | Rust | reclaim | c_freed_by_rust |
| Rust | C | borrow + escape | borrow_escape |
| Any | Any | double free | cross_lang_double_free |

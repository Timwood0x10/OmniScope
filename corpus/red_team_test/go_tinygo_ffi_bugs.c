// Go/TinyGo FFI Bug Corpus Test
// Based on TINYGO_IR_SPEC.md and GO_GC_IR_SPEC.md
//
// These are LLVM IR-level test cases that simulate TinyGo's output format.
// TinyGo compiles Go to LLVM IR, so these patterns represent what OmniScope
// would see when analyzing TinyGo-compiled bitcode.
//
// Test case matrix:
//   TC1: Go runtime.alloc → C free()          [BUG: CWE-763 cross-language free]
//   TC2: C malloc → Go runtime.free           [BUG: CWE-763 cross-language free]
//   TC3: Go runtime.alloc → Go runtime.free   [SAFE: same-language pair]
//   TC4: CGo bridge _Cgo_malloc → C free      [SAFE: legitimate CGo pattern]
//   TC5: runtime.alloc leak (no free)          [BUG: CWE-401 memory leak]
//   TC6: runtime.realloc → C free             [BUG: CWE-763 cross-language free]
//   TC7: C calloc → tinygo_free               [BUG: CWE-763 cross-language free]

#include <stddef.h>
#include <stdlib.h>

// External declarations for TinyGo runtime functions (as they appear in LLVM IR)
extern void* runtime_alloc(size_t size, size_t layout);
extern void  runtime_free(void* ptr);
extern void* runtime_realloc(void* ptr, size_t size);
extern void  runtime_trackPointer(void* ptr, void* stackChain);
extern void* tinygo_alloc(size_t size);
extern void  tinygo_free(void* ptr);

// External declarations for CGo bridge functions
extern void* _Cgo_malloc(size_t size);
extern void  _Cgo_free(void* ptr);

// ============================================================================
// TC1: Go runtime.alloc → C free()
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - Go-allocated memory freed by C's free()
// Rationale: runtime.alloc uses TinyGo's GC-managed heap; calling C free()
// on it bypasses GC and causes undefined behavior.
// ============================================================================
void tc1_go_alloc_c_free(void) {
    void* go_mem = runtime_alloc(1024, 0);  // Go heap allocation
    // ... use go_mem ...
    free(go_mem);  // ❌ BUG: Cross-language free (Go alloc → C free)
}

// ============================================================================
// TC2: C malloc → Go runtime.free
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - C-allocated memory freed by Go's runtime.free()
// Rationale: runtime.free expects GC-managed pointers; C malloc memory is
// not tracked by TinyGo's GC, causing double-free or corruption.
// ============================================================================
void tc2_c_malloc_go_free(void) {
    void* c_mem = malloc(2048);  // C heap allocation
    // ... use c_mem ...
    runtime_free(c_mem);  // ❌ BUG: Cross-language free (C alloc → Go free)
}

// ============================================================================
// TC3: Go runtime.alloc → Go runtime.free
// SAFE: Same-language allocation/deallocation pair
// Expected: No issue reported (correct pairing)
// Rationale: Both allocator and deallocator are from TinyGo runtime,
// maintaining GC consistency.
// ============================================================================
void tc3_go_alloc_go_free(void) {
    void* go_mem = runtime_alloc(512, 0);  // Go heap allocation
    // ... use go_mem ...
    runtime_free(go_mem);  // ✅ SAFE: Same-language pair
}

// ============================================================================
// TC4: CGo bridge pattern
// SAFE: Legitimate CGo interop
// Expected: No issue reported (CGo bridge handles translation correctly)
// Rationale: _Cgo_malloc is a CGo bridge function that properly wraps
// C malloc for Go-side use; freeing with C free() is correct here.
// ============================================================================
void tc4_cgo_bridge_safe(void) {
    void* cgo_mem = _Cgo_malloc(256);  // CGo bridge (wraps C malloc)
    // ... use cgo_mem ...
    free(cgo_mem);  // ✅ SAFE: CGo bridge manages the translation
}

// ============================================================================
// TC5: runtime.alloc memory leak
// BUG: Memory leak (CWE-401)
// Expected: HIGH - Allocated memory never freed
// Rationale: runtime_alloc returns heap memory that must be explicitly
// freed via runtime_free to avoid leaks in long-running programs.
// ============================================================================
void tc5_go_alloc_leak(void) {
    void* leaked = runtime_alloc(4096, 0);  // Go heap allocation
    // ... use leaked but forget to free ...
    // ❌ BUG: Memory leak (no corresponding runtime_free)
}

// ============================================================================
// TC6: runtime.realloc → C free()
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - Go-reallocated memory freed by C's free()
// Rationale: runtime_realloc returns GC-managed memory; C free() bypasses GC.
// ============================================================================
void tc6_go_realloc_c_free(void) {
    void* original = malloc(128);  // C allocation (for initial buffer)
    void* grown = runtime_realloc(original, 1024);  // Go reallocation
    // ... use grown ...
    free(grown);  // ❌ BUG: Cross-language free (Go realloc → C free)
}

// ============================================================================
// TC7: C calloc → tinygo_free
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - C-calloc'd memory freed by tinygo_free
// Rationale: tinygo_free expects TinyGo-allocated pointers; C calloc memory
// is not in TinyGo's heap space.
// ============================================================================
void tc7_c_calloc_tinygo_free(void) {
    void* zeroed = calloc(100, sizeof(int));  // C zeroed allocation
    // ... use zeroed ...
    tinygo_free(zeroed);  // ❌ BUG: Cross-language free (C alloc → Go free)
}

// ============================================================================
// TC8: Multiple allocations with mixed free patterns
// BUG: Mixed cross-language issues
// Expected: Multiple issues detected in single function
// Rationale: Complex FFI scenario with multiple allocation sources and
// incorrect deallocator choices.
// ============================================================================
void tc8_mixed_ffi_bugs(void) {
    void* go_ptr = runtime_alloc(256, 0);     // Go alloc
    void* c_ptr = malloc(512);                  // C alloc
    void* tg_ptr = tinygo_alloc(128);           // TinyGo alloc

    // Intentionally swapped deallocators (all bugs):
    free(go_ptr);        // ❌ BUG #1: Go → C
    runtime_free(c_ptr); // ❌ BUG #2: C → Go
    free(tg_ptr);        // ❌ BUG #3: TinyGo → C
}

// ============================================================================
// TC9: runtime.trackPointer usage (informational)
// SAFE: GC pointer registration (not an alloc/free issue)
// Expected: No memory safety issue (trackPointer is GC bookkeeping)
// Rationale: runtime_trackPointer registers a pointer with the GC for
// stack scanning; this is not an allocation or deallocation operation.
// ============================================================================
void tc9_gc_track_pointer(void* user_ptr) {
    void* go_mem = runtime_alloc(64, 0);  // Go allocation
    runtime_trackPointer(go_mem, NULL);   // Register with GC (safe)
    runtime_free(go_mem);                 // Proper cleanup ✅
}

// ============================================================================
// TC10: Nested FFI with correct pairing
// SAFE: Complex but correct FFI usage
// Expected: No issue reported (all pairs correctly matched)
// Rationale: Demonstrates correct multi-language memory management where
// each allocation is freed by its matching deallocator.
// ============================================================================
void tc10_correct_nested_ffi(void) {
    // Layer 1: Go allocations (managed by Go)
    void* go_data = runtime_alloc(1024, 0);
    void* go_buffer = runtime_alloc(4096, 0);

    // Layer 2: C allocations (managed by C)
    void* c_data = malloc(2048);
    void* c_temp = calloc(50, sizeof(double));

    // ... complex processing using all buffers ...

    // Correct cleanup (matched pairs):
    runtime_free(go_data);    // ✅ Go → Go
    runtime_free(go_buffer);  // ✅ Go → Go
    free(c_data);              // ✅ C → C
    free(c_temp);              // ✅ C → C
}

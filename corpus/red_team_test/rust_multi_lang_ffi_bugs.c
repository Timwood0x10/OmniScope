// Rust FFI Bug Test Cases (simulated via C)
//
// Simulates Rust code using FFI with C libraries, testing __rust_alloc/dealloc
// patterns and cross-language free detection with Rust↔C# (P5) and Rust↔Go (P6).
//
// Test case matrix:
//   TC1: __rust_alloc → free()              [BUG: CWE-763 cross-language]
//   TC2: malloc → __rust_dealloc           [BUG: CWE-763 cross-language]
//   TC3: __rust_alloc → Marshal.FreeHGlobal [BUG: CRITICAL - Rust→C#]
//   TC4: CoTaskMemAlloc → __rust_dealloc    [BUG: CRITICAL - C#→Rust]
//   TC5: __rust_alloc → __rust_dealloc     [SAFE: correct Rust pairing]
//   TC6: Box::leak pattern (intentional)    [SAFE: documented ownership transfer]
//   TC7: Triple-language chaos (Rust/C/C#)  [BUG: multiple cross-lang issues]

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// External declarations for Rust global allocator functions
extern void* __rust_alloc(size_t size, size_t align);
extern void  __rust_dealloc(void* ptr, size_t size, size_t align);
extern void* __rust_realloc(void* ptr, size_t old_size, size_t new_size, size_t align);

// External declarations for .NET runtime (for P5 Rust↔C# tests)
extern void* Marshal_AllocHGlobal(int size);
extern void  Marshal_FreeHGlobal(void* ptr);

// ============================================================================
// TC1: Rust alloc → C's free()
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - Rust-allocated memory freed by C's free()
// Rationale: __rust_alloc uses Rust's global allocator (may be jemalloc,
// mimalloc, or System allocator). C's free() uses CRT heap.
// Mismatch causes heap corruption.
// ============================================================================
void tc1_rust_alloc_c_free(void) {
    void* rust_mem = __rust_alloc(1024, 8);  // Rust allocation (aligned to 8)
    memset(rust_mem, 0xDE, 1024);

    // ... use rust_mem in Rust code, pass to C via FFI ...

    free(rust_mem);  // ❌ BUG: Cross-language free (Rust alloc → C free)
}

// ============================================================================
// TC2: Reverse - C malloc → Rust dealloc
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - C-allocated memory freed by Rust's deallocator
// Rationale: __rust_dealloc expects pointer from __rust_alloc with matching
// size/alignment metadata. C malloc doesn't provide this.
// ============================================================================
void tc2_c_malloc_rust_dealloc(void) {
    void* c_mem = malloc(2048);  // C standard allocation
    memset(c_mem, 0xAD, 2048);

    // ... pass to Rust code via extern "C" bridge ...

    __rust_dealloc(c_mem, 2048, 1);  // ❌ BUG: Cross-language free (C alloc → Rust free)
}

// ============================================================================
// TC3: Rust alloc → .NET FreeHGlobal (P5 addition)
// BUG: Cross-language free (CWE-763) - CRITICAL
// Expected: CRITICAL - Three-way language mismatch
// Rationale: Rust's global allocator and .NET's Marshal use completely different
// heap implementations. This is a real bug in complex systems code.
// ============================================================================
void tc3_rust_alloc_csharp_free(void) {
    void* rust_obj = __rust_alloc(4096, 16);  // Rust allocation
    memset(rust_obj, 0x42, 4096);

    // ... pass through multiple layers: Rust → C# interop ...

    Marshal_FreeHGlobal(rust_obj);  // ❌ BUG: CRITICAL (Rust → C# mismatch)
}

// ============================================================================
// TC4: .NET CoTaskMemAlloc → Rust dealloc (reverse P5)
// BUG: Cross-language free (CWE-763) - CRITICAL
// Expected: CRITICAL - COM memory passed to Rust deallocator
// Rationale: CoTaskMemAlloc uses COM task allocator. Passing this pointer
// to __rust_dealloc will corrupt Rust's internal bookkeeping.
// ============================================================================
void tc4_csharp_alloc_rust_free(void) {
    void* com_mem = Marshal_AllocHGlobal(8192);  // .NET allocation
    memset(com_mem, 0x77, 8192);

    // ... incorrectly pass COM/.NET memory to Rust for cleanup ...

    __rust_dealloc(com_mem, 8192, 16);  // ❌ BUG: CRITICAL (C# → Rust mismatch)
}

// ============================================================================
// TC5: Correct Rust memory management
// SAFE: Proper __rust_alloc/__rust_dealloc pairing
// Expected: No issue reported
// Rationale: Demonstrates safe Rust FFI pattern where allocation and
// deallocation both use Rust's global allocator API.
// ============================================================================
void tc5_correct_rust_memory(void) {
    // Standard Rust allocation pattern
    void* data = __rust_alloc(512, 8);
    memset(data, 'R', 512);

    // ... use data in Rust code ...

    __rust_dealloc(data, 512, 8);  // ✅ SAFE: Rust alloc → Rust dealloc

    // Aligned allocation (common for SIMD)
    void* aligned = __rust_alloc(1024, 32);  // 32-byte aligned
    memset(aligned, 0, 1024);

    __rust_dealloc(aligned, 1024, 32);  // ✅ SAFE: Correct alignment match
}

// ============================================================================
// TC6: Box::leak pattern (intentional ownership transfer)
// SAFE: Documented ownership transfer across FFI boundary
// Expected: No issue (or LOW severity informational)
// Rationale: In Rust FFI, it's common to "leak" a Box to obtain a raw pointer
// that can be passed to C code which takes ownership. The C code is then
// responsible for freeing with appropriate C allocator.
// ============================================================================
void tc6_box_leak_ownership_transfer(void) {
    // Simulate: Rust side does Box::new(...).leak().into_raw()
    // This transfers ownership to C side
    void* leaked = __rust_alloc(256, 8);  // Represents leaked Box<T>
    memset(leaked, 0xFF, 256);

    // C side takes ownership and frees correctly
    free(leaked);  // ✅ SAFE: Ownership was intentionally transferred
                   // (In real code, this would be documented in FFI contract)
}

// ============================================================================
// TC7: Triple-language chaos (Rust + C + C#)
// BUG: Multiple cross-language issues in realistic multi-language system
// Expected: Multiple CRITICAL/HIGH issues
// Rationale: Complex systems often involve Rust core + C bindings + C#/Go
// frontends. This test catches confusion when three+ languages interact.
// ============================================================================
void tc7_triple_lang_chaos(void) {
    // Layer 1: Rust core allocation (business logic)
    void* rust_core = __rust_alloc(16384, 16);

    // Layer 2: C intermediate buffer (POSIX I/O)
    void* c_io_buf = malloc(8192);

    // Layer 3: .NET UI buffer (WinForms/WPF interop)
    void* net_ui = Marshal_AllocHGlobal(4096);

    // Layer 4: Another Rust allocation (cache)
    void* rust_cache = __rust_alloc(32768, 64);

    // Initialize all buffers
    memset(rust_core, 0x11, 16384);
    memset(c_io_buf, 0x22, 8192);
    memset(net_ui, 0x33, 4096);
    memset(rust_cache, 0x44, 32768);

    // Complete chaos - all deallocations wrong:
    free(rust_core);              // ❌ BUG #1: Rust → C
    __rust_dealloc(c_io_buf, 8192, 1); // ❌ BUG #2: C → Rust
    __rust_dealloc(net_ui, 4096, 16);  // ❌ BUG #3: C# → Rust
    Marshal_FreeHGlobal(rust_cache);   // ❌ BUG #4: Rust → C#
}

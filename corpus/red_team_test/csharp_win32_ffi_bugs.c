// C#/.NET NativeAOT FFI Bug Test Cases
//
// Simulates .NET NativeAOT-compiled bitcode patterns for P/Invoke,
// COM interop, and Win32 API usage.
//
// Test case matrix:
//   TC1: Marshal.AllocHGlobal → free()          [BUG: CWE-763 cross-language free]
//   TC2: CoTaskMemAlloc → free()                [BUG: CWE-763 cross-language free]
//   TC3: malloc → Marshal.FreeHGlobal           [BUG: CWE-763 cross-language free]
//   TC4: HeapAlloc → LocalFree                  [BUG: invalid_free (wrong dealloc)]
//   TC5: Marshal.AllocHGlobal → FreeHGlobal     [SAFE: correct P/Invoke pair]
//   TC6: CoTaskMemAlloc leak                    [BUG: CWE-401 memory leak]
//   TC7: Mixed allocators in COM scenario       [BUG: multiple cross-lang issues]

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// External declarations for .NET NativeAOT runtime functions
extern void* Marshal_AllocHGlobal(int size);
extern void  Marshal_FreeHGlobal(void* ptr);
extern void* CoTaskMemAlloc(size_t size);
extern void  CoTaskMemFree(void* ptr);
extern void* LocalAlloc(unsigned int flags, size_t size);
extern void  LocalFree(void* ptr);
extern void* HeapAlloc(void* heap, unsigned int flags, size_t size);
extern void  HeapFree(void* heap, unsigned int flags, void* ptr);

// ============================================================================
// TC1: P/Invoke pattern - Marshal.AllocHGlobal freed by C's free()
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - .NET-allocated memory improperly freed by C runtime
// Rationale: Marshal.AllocHGlobal uses process heap; C free() expects
// malloc-allocated memory. This causes heap corruption.
// ============================================================================
void tc1_marshal_alloc_c_free(void) {
    void* net_mem = Marshal_AllocHGlobal(1024);  // .NET P/Invoke allocation
    memset(net_mem, 0, 1024);

    // ... use net_mem for unmanaged interop ...

    free(net_mem);  // ❌ BUG: Cross-language free (.NET alloc → C free)
}

// ============================================================================
// TC2: COM interop - CoTaskMemAlloc freed by C's free()
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - COM task memory improperly freed by C runtime
// Rationale: CoTaskMemAlloc uses COM task allocator, not CRT heap.
// Must use CoTaskMemFree for proper cleanup.
// ============================================================================
void tc2_com_alloc_c_free(void) {
    void* com_mem = CoTaskMemAlloc(2048);  // COM task allocation
    memset(com_mem, 0xFF, 2048);

    // ... use com_mem for COM object marshaling ...

    free(com_mem);  // ❌ BUG: Cross-language free (COM alloc → C free)
}

// ============================================================================
// TC3: Reverse pattern - C malloc freed by .NET's FreeHGlobal
// BUG: Cross-language free (CWE-763)
// Expected: CRITICAL - C-allocated memory improperly freed by .NET runtime
// Rationale: Marshal.FreeHGlobal expects GlobalAlloc/LocalAlloc handles,
// not malloc pointers. Undefined behavior.
// ============================================================================
void tc3_c_malloc_net_free(void) {
    void* c_mem = malloc(4096);  // C standard allocation
    memset(c_mem, 'A', 4096);

    // ... pass to managed code via P/Invoke ...

    Marshal_FreeHGlobal(c_mem);  // ❌ BUG: Cross-language free (C alloc → .NET free)
}

// ============================================================================
// TC4: Win32 API mismatch - HeapAlloc freed by LocalFree
// BUG: Invalid free (wrong deallocator within same language family)
// Expected: HIGH - Win32 heap handle freed with wrong API
// Rationale: HeapAlloc and LocalFree use different heap implementations.
// This is a subtle but real Windows API misuse.
// ============================================================================
void tc4_heapalloc_localfree(void) {
    void* heap_mem = HeapAlloc(NULL, 0, 8192);  // Win32 heap allocation
    memset(heap_mem, 0x42, 8192);

    // ... use heap_mem for large buffer operations ...

    LocalFree(heap_mem);  // ❌ BUG: Invalid free (HeapAlloc → LocalFree mismatch)
}

// ============================================================================
// TC5: Correct P/Invoke pattern
// SAFE: Proper .NET ↔ Unmanaged memory management
// Expected: No issue reported (correct pairing)
// Rationale: Demonstrates the safe way to use P/Invoke memory:
// allocate with Marshal.AllocHGlobal, free with Marshal.FreeHGlobal.
// ============================================================================
void tc5_correct_pinvoke(void) {
    void* buffer = Marshal_AllocHGlobal(512);  // Correct .NET allocation
    memset(buffer, 0, 512);

    // ... use buffer for safe P/Invoke call ...

    Marshal_FreeHGlobal(buffer);  // ✅ SAFE: Correct .NET pairing
}

// ============================================================================
// TC6: COM memory leak
// BUG: Memory leak (CWE-401)
// Expected: MEDIUM - CoTaskMemAlloc'd memory never released
// Rationale: COM allocations must be explicitly freed to avoid leaks,
// especially in long-running server applications.
// ============================================================================
void tc6_com_leak(void) {
    void* leaked = CoTaskMemAlloc(16384);  // Large COM allocation
    memset(leaked, 0xCC, 16384);

    // ... use leaked but forget to call CoTaskMemFree ...
    // ❌ MEMORY LEAK: No CoTaskMemFree call
}

// ============================================================================
// TC7: Complex multi-API scenario (multiple bugs)
// BUG: Multiple cross-language and mismatch issues in single function
// Expected: Multiple issues detected (comprehensive test)
// Rationale: Real-world COM + P/Invoke + Win32 mixed usage often has
// subtle allocator/deallocator mismatches.
// ============================================================================
void tc7_mixed_win32_com_pinvoke(void) {
    // Layer 1: P/Invoke allocation
    void* pinvoke_buf = Marshal_AllocHGlobal(256);

    // Layer 2: COM allocation
    void* com_obj = CoTaskMemAlloc(1024);

    // Layer 3: Win32 local heap
    void* local_buf = LocalAlloc(0, 512);

    // Layer 4: Standard C allocation
    void* std_buf = malloc(2048);

    // Use all buffers
    memset(pinvoke_buf, 1, 256);
    memset(com_obj, 2, 1024);
    memset(local_buf, 3, 512);
    memset(std_buf, 4, 2048);

    // Intentionally wrong deallocations:
    free(pinvoke_buf);        // ❌ BUG #1: .NET → C
    Marshal_FreeHGlobal(com_obj); // ❌ BUG #2: COM → .NET
    free(local_buf);          // ❌ BUG #3: Win32 → C
    CoTaskMemFree(std_buf);   // ❌ BUG #4: C → COM
}

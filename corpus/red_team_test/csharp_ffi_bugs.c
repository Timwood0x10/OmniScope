/**
 * C# / .NET FFI Boundary Bugs
 *
 * Tests cross-language issues at the C# (NativeAOT) <-> C boundary.
 * All bugs are FFI-specific: alloc/free mismatch, ownership transfer,
 * GCHandle leak, COM interop memory errors.
 *
 * Symbol naming follows .NET NativeAOT conventions:
 *   - Marshal_AllocHGlobal / Marshal_FreeHGlobal = P/Invoke unmanaged
 *   - CoTaskMemAlloc / CoTaskMemFree = COM interop
 *   - GC_* = GC interaction stubs
 *   - <Module>. = module-level static methods
 */

#include <stdlib.h>
#include <string.h>

/* Simulated .NET NativeAOT P/Invoke functions */
extern void* Marshal_AllocHGlobal(int cb);
extern void  Marshal_FreeHGlobal(void* hglobal);

/* Simulated .NET COM interop functions */
extern void* CoTaskMemAlloc(unsigned long cb);
extern void  CoTaskMemFree(void* pv);

/* Simulated Win32 API (called from C# side) */
extern void* HeapAlloc(void* heap, unsigned long flags, unsigned long bytes);
extern int   HeapFree(void* heap, unsigned long flags, void* mem);

/* Simulated .NET Runtime Helpers */
extern void* RhpNewFast(int size);

/* ============================================================
 * CS-01: C# AllocHGlobal → C free() (CWE-763)
 * C# allocates via P/Invoke, C frees with standard free().
 * Marshal.AllocHGlobal uses a different allocator than CRT malloc.
 *
 * Expected: cross_language_free (csharp alloc + c free)
 * ============================================================ */
void cs_01_csharp_alloc_c_free(void) {
    void* ptr = Marshal_AllocHGlobal(256);
    if (!ptr) return;

    /* Use the buffer */
    memset(ptr, 0xAB, 256);

    /* BUG: freeing with wrong deallocator */
    free(ptr); /* Should use Marshal.FreeHGlobal() */
}

/* ============================================================
 * CS-02: C malloc → C# FreeHGlobal (CWE-763)
 * C allocates, C# frees with P/Invoke. Mismatched deallocators.
 *
 * Expected: cross_language_free (c alloc + csharp free)
 * ============================================================ */
void cs_02_c_alloc_csharp_free(void) {
    void* ptr = malloc(1024);
    if (!ptr) return;

    /* Pass to C# side for processing */
    memcpy(ptr, "FFI data", 8);

    /* BUG: C# frees with Marshal.FreeHGlobal instead of free() */
    Marshal_FreeHGlobal(ptr); /* Wrong! Should be free() */
}

/* ============================================================
 * CS-03: CoTaskMemAlloc leak — no matching CoTaskMemFree (CWE-401)
 * COM interop allocation never freed.
 *
 * Expected: memory_leak (csharp COM alloc not freed)
 * ============================================================ */
void cs_03_com_alloc_leak(void) {
    /* Allocate COM interop memory */
    void* com_data = CoTaskMemAlloc(512);
    if (!com_data) return;

    /* Use it */
    memset(com_data, 0, 512);

    /* BUG: forgot CoTaskMemFree(com_data) before returning */
    /* Memory leaked back to COM allocator pool */
}

/* ============================================================
 * CS-04: Double FreeHGlobal (CWE-415)
 * C# allocated buffer freed twice.
 *
 * Expected: double_free or invalid_free
 * ============================================================ */
void cs_04_double_free_global(void) {
    void* buf = Marshal_AllocHGlobal(64);
    if (!buf) return;

    strcpy((char*)buf, "sensitive data");

    /* First free */
    Marshal_FreeHGlobal(buf);

    /* BUG: double free — UAF risk if memory is reused */
    Marshal_FreeHGlobal(buf);
}

/* ============================================================
 * CS-05: Cross-language: C# CoTaskMemAlloc → C free() (CWE-763)
 * COM interop memory freed by wrong runtime.
 *
 * Expected: cross_language_free (csharp COM alloc + c free)
 * ============================================================ */
void cs_05_com_alloc_c_free(void) {
    void* com_ptr = CoTaskMemAlloc(2048);
    if (!com_ptr) return;

    /* Process data */
    memset(com_ptr, 0xFF, 2048);

    /* BUG: using C's free() on COM-allocated memory */
    free(com_ptr); /* Should be CoTaskMemFree() */
}

/* ============================================================
 * CS-06: RhpNewFast (Runtime Helper) → free() (CWE-763)
 * .NET runtime internal allocator mismatch.
 *
 * Expected: cross_language_free (csharp runtime alloc + c free)
 * ============================================================ */
void cs_06_runtime_alloc_c_free(void) {
    void* obj = RhpNewFast(128);
    if (!obj) return;

    /* Use object */
    memset(obj, 0x42, 128);

    /* BUG: cannot free runtime-allocated objects with C free() */
    free(obj); /* Invalid: RhpNewFast memory managed by .NET runtime */
}

/* ============================================================
 * CS-07: Safe example — correct AllocHGlobal/FreeHGlobal pair
 *
 * Expected: no issue (correct pattern, should be suppressed)
 * ============================================================ */
void cs_safe_correct_pair(void) {
    void* buf = Marshal_AllocHGlobal(320);
    if (!buf) return;

    /* Correct usage */
    memcpy(buf, "test data", 9);
    Marshal_FreeHGlobal(buf); /* Correct: matching pair */
}

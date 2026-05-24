// Zig FFI Bug Test Cases (simulated via C)
//
// Simulates Zig's @cImport patterns where Zig code calls C functions
// via FFI. These test cases model what OmniScope sees when analyzing
// Zig-compiled bitcode.
//
// Test case matrix:
//   TC1: zig_alloc → free()                  [BUG: CWE-763 cross-language free]
//   TC2: malloc → __zig_dealloc              [BUG: CWE-763 cross-language free]
//   TC3: PageAllocator.alloc → free()        [BUG: HIGH - Zig heap → C free]
//   TC4: malloc → PageAllocator.free         [BUG: HIGH - C heap → Zig free]
//   TC5: zig_alloc → __zig_dealloc           [SAFE: correct Zig pairing]
//   TC6: ArenaAllocator leak                 [BUG: MEDIUM memory leak]
//   TC7: Multiple allocators mixed scenario  [BUG: multiple cross-lang issues]

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// External declarations for Zig runtime/allocator functions
extern void* zig_alloc(size_t size);
extern void  __zig_dealloc(void* ptr, size_t size);
extern void* PageAllocator_alloc(size_t size);
extern void  PageAllocator_free(void* ptr);
extern void* GeneralPoolAllocator_alloc(size_t size);
extern void  GeneralPoolAllocator_free(void* ptr, size_t size);
extern void* ArenaAllocator_alloc(void* arena, size_t size);
extern void  ArenaAllocator_free(void* arena, void* ptr);

// ============================================================================
// TC1: Zig allocator → C free()
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - Zig-allocated memory freed by C's free()
// Rationale: zig_alloc uses Zig's custom allocator (possibly GPA or page-based),
// not the C runtime heap. Calling free() on it causes undefined behavior.
// ============================================================================
void tc1_zig_alloc_c_free(void) {
    void* zig_mem = zig_alloc(1024);  // Zig allocation
    memset(zig_mem, 0xAB, 1024);

    // ... use zig_mem in Zig code ...

    free(zig_mem);  // ❌ BUG: Cross-language free (Zig alloc → C free)
}

// ============================================================================
// TC2: Reverse pattern - C malloc → Zig dealloc
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - C-allocated memory freed by Zig's deallocator
// Rationale: __zig_dealloc expects Zig-managed pointers. Passing a malloc
// pointer to it will corrupt Zig's internal bookkeeping.
// ============================================================================
void tc2_c_malloc_zig_dealloc(void) {
    void* c_mem = malloc(2048);  // C standard allocation
    memset(c_mem, 0xCD, 2048);

    // ... pass to Zig code via @cImport bridge ...

    __zig_dealloc(c_mem, 2048);  // ❌ BUG: Cross-language free (C alloc → Zig free)
}

// ============================================================================
// TC3: PageAllocator (Zig's mmap wrapper) → C free()
// BUG: High severity cross-language free
// Expected: CRITICAL if detected as page allocation
// Rationale: PageAllocator uses OS-level virtual memory (mmap/VirtualAlloc).
// C's free() cannot handle this. Must use PageAllocator.free or munmap.
// ============================================================================
void tc3_pagealloc_c_free(void) {
    void* page_mem = PageAllocator_alloc(4096);  // Page-aligned allocation
    memset(page_mem, 0xEF, 4096);

    // ... use page_mem for large buffer or shared memory ...

    free(page_mem);  // ❌ BUG: Cross-language free (PageAllocator → C free)
}

// ============================================================================
// TC4: C malloc → PageAllocator.free
// BUG: Reverse mismatch
// Expected: HIGH - C heap memory passed to Zig's page deallocator
// Rationale: PageAllocator.free expects page-aligned, page-sized allocations
// from its own pool. Regular malloc pointers don't match.
// ============================================================================
void tc4_c_malloc_pagefree(void) {
    void* c_mem = malloc(8192);  // Standard C allocation
    memset(c_mem, 0x12, 8192);

    // ... incorrectly assume this is page-allocated ...

    PageAllocator_free(c_mem);  // ❌ BUG: Cross-language free (C alloc → Zig PageAllocator)
}

// ============================================================================
// TC5: Correct Zig memory management
// SAFE: Proper Zig allocator/deallocator pairing
// Expected: No issue reported (correct usage pattern)
// Rationale: Demonstrates safe Zig memory management where allocation and
// deallocation use matching APIs from the same allocator.
// ============================================================================
void tc5_correct_zig_memory(void) {
    // Using general-purpose allocator (common in Zig)
    void* gpa_mem = GeneralPoolAllocator_alloc(512);
    memset(gpa_mem, 0x34, 512);

    // ... use gpa_mem ...

    GeneralPoolAllocator_free(gpa_mem, 512);  // ✅ SAFE: Correct Zig pairing

    // Using page allocator for large block
    void* page_mem = PageAllocator_alloc(16384);
    memset(page_mem, 0x56, 16384);

    PageAllocator_free(page_mem);  // ✅ SAFE: Correct PageAllocator pairing
}

// ============================================================================
// TC6: Arena Allocator memory leak
// BUG: Memory leak (CWE-401)
// Expected: MEDIUM - Arena-allocated memory never released
// Rationale: Arena allocations persist until the entire arena is destroyed.
// Forgetting to destroy the arena leaks all its contents.
// ============================================================================
void tc6_arena_leak(void) {
    void* arena = NULL;  // Simulated arena handle

    // Allocate from arena (common pattern in Zig)
    void* item1 = ArenaAllocator_alloc(arena, 256);
    void* item2 = ArenaAllocator_alloc(arena, 512);
    void* item3 = ArenaAllocator_alloc(arena, 1024);

    memset(item1, 0x78, 256);
    memset(item2, 0x79, 512);
    memset(item3, 0x7A, 1024);

    // Use items but forget to destroy arena
    // ❌ MEMORY LEAK: All arena allocations leaked
}

// ============================================================================
// TC7: Complex multi-allocator scenario
// BUG: Multiple cross-language issues in realistic Zig FFI code
// Expected: Multiple issues with varying severities
// Rationale: Real-world Zig systems code often mixes multiple allocators:
// GPA for general use, PageAllocator for large buffers, and C malloc for
// FFI bridges. This test catches confusion between them.
// ============================================================================
void tc7_mixed_allocator_chaos(void) {
    // Layer 1: Zig GPA allocation
    void* gpa_buf = GeneralPoolAllocator_alloc(1024);

    // Layer 2: C allocation (for FFI bridge)
    void* c_bridge = malloc(2048);

    // Layer 3: Page allocation (for shared memory)
    void* shm_buf = PageAllocator_alloc(4096);

    // Layer 4: Another Zig allocation
    void* zig_buf = zig_alloc(512);

    // Initialize all buffers
    memset(gpa_buf, 0xAA, 1024);
    memset(c_bridge, 0xBB, 2048);
    memset(shm_buf, 0xCC, 4096);
    memset(zig_buf, 0xDD, 512);

    // Intentionally scrambled deallocations:
    free(gpa_buf);              // ❌ BUG #1: Zig GPA → C
    PageAllocator_free(c_bridge); // ❌ BUG #2: C → Zig PageAllocator
    __zig_dealloc(shm_buf, 4096); // ❌ BUG #3: PageAllocator → Zig dealloc
    GeneralPoolAllocator_free(zig_buf, 512); // ❌ BUG #4: Zig alloc → GPA (wrong type!)
}

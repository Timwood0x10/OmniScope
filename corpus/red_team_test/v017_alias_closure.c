/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope v0.1.7 — Multi-Language Alias Closure Test Cases    ║
 * ║  Target: E2-2 — alias closure → FFI boundary severity boost      ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * This file demonstrates patterns where a pointer's ALIAS CHAIN
 * reaches an FFI boundary, making the issue MORE SEVERE than
 * a same-language memory safety bug.
 *
 * E2-2a: free_validation — invalid_free with FFI alias → .critical
 * E2-2b: memory_safety   — double_free / UAF with FFI alias → .critical
 * E2-2c: callback_escape  — indirect escape via alias closure → .high boost
 *
 * Intentional bugs: 5
 * Control cases: 1
 */

#include <stdlib.h>
#include <string.h>

// ================================================================
// Simulated FFI boundary functions (representing cross-language calls)
// ================================================================

extern void ffi_send_to_rust(void* data, size_t len);
extern void ffi_callback_register(void (*cb)(void*));
extern void* ffi_receive_from_zig(void);
extern void ffi_process_in_go(void* ptr);

// ================================================================
// BUG-MULTI-01: Free non-heap pointer that reached FFI boundary
//
// E2-2a: The pointer was passed to an FFI function (ffi_send_to_rust),
// creating an alias chain to Rust's memory space. Then we try to
// free it as if it were heap-allocated. With FFI alias, this should
// be upgraded from .high to .critical.
// ================================================================

void bugMulti01_InvalidFreeWithFFIAlias() {
    int stack_var = 42;
    void* ptr = &stack_var;

    // Pass stack address through FFI boundary — creates cross-lang alias
    ffi_send_to_rust(ptr, sizeof(int));

    // Now try to free it as heap pointer — invalid!
    // E2-2a: isOnDangerPathFull(ptr) == true → severity .critical (was .high)
    free(ptr); // BUG: freeing stack variable that crossed FFI boundary
}

// ================================================================
// BUG-MULTI-02: Double-free where first free is at FFI boundary
//
// E2-2b: Pointer allocated locally, freed once normally,
// then the FFI side also frees it (or we double-free after FFI use).
// The alias chain reaching FFI makes this .critical instead of .high.
// ================================================================

void bugMulti02_DoubleFreeWithFFIAlias() {
    char* buf = (char*)malloc(1024);
    memset(buf, 'X', 1024);

    // Send to FFI consumer — now both C and foreign code may reference it
    ffi_process_in_go(buf);

    // First free (correct)
    free(buf);

    // ... complex error path ...

    // Second free — DOUBLE FREE!
    // E2-2b: isOnDangerPathFull(ptr_val) == true → .critical (was .high)
    free(buf);
}

// ================================================================
// BUG-MULTI-03: UAF after FFI callback invalidates pointer
//
// E2-2b/c: Register a callback that receives our pointer.
// When the callback fires, it may have already freed or reallocated
// the memory. Accessing it afterwards is UAF with FFI involvement.
// ================================================================

static void* g_shared_ptr = NULL;

static void on_ffi_callback(void* data) {
    // Callback from foreign runtime — may free/realloc our data
    g_shared_ptr = data; // Store for later use
    // Foreign code might free(data) here...
}

void bugMulti03_UAFViaCallbackAlias() {
    g_shared_ptr = malloc(256);
    strcpy((char*)g_shared_ptr, "SENSITIVE_DATA");

    // Register callback — indirect escape through function pointer
    // E2-2c: callback_arg aliases reach FFI → indirect_escape = true
    ffi_callback_register(&on_ffi_callback);

    // Simulate callback firing
    on_ffi_callback(g_shared_ptr);

    // If foreign code freed g_shared_ptr in callback:
    printf("Data: %s\n", (char*)g_shared_ptr); // UAF! And at FFI boundary
}

// ================================================================
// BUG-MULTI-04: Suspicious free of FFI-received pointer
//
// Receive a pointer from Zig's FFI bridge (ffi_receive_from_zig).
// Try to free it with standard free() — ownership unclear.
// E2-2b: SuspiciousFree with FFI alias → confidence boost + .high
// ================================================================

void bugMulti04_SuspiciousForeignFree() {
    void* foreign_ptr = ffi_receive_from_zig();

    if (foreign_ptr != NULL) {
        // Use the received pointer
        memcpy(foreign_ptr, "test", 5);

        // Try to free it — but who owns this? Zig allocator? C?
        // E2-2b: isOnDangerPathFull(ptr_val) == true → confidence +10%
        free(foreign_ptr); // SUSPICIOUS: mismatched deallocator possible
    }
}

// ================================================================
// BUG-MULTI-05: Heap-to-global escape through FFI then UAF
//
// Allocate heap, pass through multiple FFI boundaries,
// store globally, then access after potential invalidation.
// The deep alias chain crossing FFI makes this maximally severe.
// ================================================================

static void* g_ffi_escaped_heap = NULL;

void bugMulti05_DeepFFIAliasUAF() {
    void* heap_buf = malloc(2048);
    memset(heap_buf, 0xFF, 2048);

    // Chain of FFI escapes:
    // 1. First FFI call (creates alias in foreign runtime)
    ffi_send_to_rust(heap_buf, 2048);

    // 2. Second FFI call (another alias created)
    ffi_process_in_go(heap_buf);

    // 3. Global store (third escape point)
    g_ffi_escaped_heap = heap_buf;

    // At this point, Rust AND Go may have references to heap_buf
    // Either could have freed it by now...

    // UAF access — and the pointer has deep FFI alias chain
    ((int*)g_ffi_escaped_heap)[0] = 0xDEAD; // Potential crash
}

// ================================================================
// CONTROL-MULTI-01: Correct pattern — no FFI interaction
// ================================================================

void controlMulti01_PureCNoFFI() {
    int* arr = (int*)malloc(16 * sizeof(int));
    if (!arr) return;

    for (int i = 0; i < 16; i++) {
        arr[i] = i * i;
    }

    free(arr); // Correct: matched alloc/free, no FFI involved
}

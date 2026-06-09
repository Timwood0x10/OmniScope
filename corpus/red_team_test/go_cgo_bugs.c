/**
 * Go → C (cgo) FFI Boundary Bugs
 *
 * Tests cross-language issues at the Go ↔ C boundary via cgo.
 * Go uses garbage collection; C uses manual memory management.
 * Bugs arise from conflicting memory management assumptions.
 *
 * Naming follows cgo conventions (_cgo_ prefix, _Cfunc_ prefix)
 * so the tool can detect language origins.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

/* Simulated Go runtime functions (cgo-generated) */
extern void* _cgo_allocate(int size);
extern void  _cgo_free(void* ptr);
extern void* _Cfunc_GoMalloc(int size);
extern void  _Cfunc_GoFree(void* ptr);

/* Go slice header */
typedef struct {
    void* data;
    int   len;
    int   cap;
} GoSlice;

/* Go string header */
typedef struct {
    const char* data;
    int         len;
} GoString;

/* ============================================================
 * GO-01: Go alloc → C free (CWE-763)
 * Go allocates via cgo runtime, C frees with free().
 * Go's GC heap != C heap.
 * Expected: cross_language_free
 * ============================================================ */
void go_01_go_alloc_c_free(void) {
    void* ptr = _cgo_allocate(128);
    strcpy((char*)ptr, "allocated by Go runtime");
    free(ptr);  /* BUG: C free() on Go GC-managed memory */
}

/* ============================================================
 * GO-02: C alloc → Go free (CWE-763)
 * C allocates with malloc, Go frees via _cgo_free.
 * Expected: cross_language_free
 * ============================================================ */
void go_02_c_alloc_go_free(void) {
    void* ptr = malloc(256);
    strcpy((char*)ptr, "allocated by C");
    _cgo_free(ptr);  /* BUG: Go free on C-heap memory */
}

/* ============================================================
 * GO-03: Go slice data escapes to C, Go GC collects (CWE-416)
 * Go passes slice.data to C. Go's GC moves/collects the backing
 * array. C's pointer becomes dangling.
 * Expected: use_after_free / pointer_escape
 * ============================================================ */
static void* g_go_slice_data = NULL;

void go_03_slice_escape(void) {
    GoSlice slice;
    slice.data = _cgo_allocate(1024);
    slice.len = 1024;
    slice.cap = 1024;

    /* Pass slice data pointer to C */
    g_go_slice_data = slice.data;

    /* Go GC may collect/move the backing array */
    _cgo_free(slice.data);

    /* BUG: C still holds dangling pointer */
    memset(g_go_slice_data, 0, 64);  /* UAF */
}

/* ============================================================
 * GO-04: Go goroutine + C thread data race (CWE-362)
 * Go goroutine writes to shared memory while C thread reads.
 * No synchronization across the FFI boundary.
 * Expected: data_race / concurrency_violation
 * ============================================================ */
static volatile int g_shared_counter = 0;

void* go_04_c_thread_func(void* arg) {
    /* C thread reads without synchronization */
    for (int i = 0; i < 1000; i++) {
        int val = g_shared_counter;  /* BUG: data race with Go goroutine */
        (void)val;
    }
    return NULL;
}

void go_04_race_test(void) {
    pthread_t tid;
    pthread_create(&tid, NULL, go_04_c_thread_func, NULL);

    /* Go goroutine writes concurrently */
    for (int i = 0; i < 1000; i++) {
        g_shared_counter++;  /* BUG: unsynchronized with C thread */
    }

    pthread_join(tid, NULL);
}

/* ============================================================
 * GO-05: C callback called after Go function returns (CWE-416)
 * Go registers a C callback. The Go closure is GC'd but C still
 * holds the function pointer.
 * Expected: use_after_free / callback_escape
 * ============================================================ */
typedef void (*GoCallback)(int);

static GoCallback g_stored_callback = NULL;

void go_05_register_callback(GoCallback cb) {
    g_stored_callback = cb;  /* C stores the callback */
}

void go_05_invoke_stored(void) {
    /* BUG: Go closure may have been GC'd, callback pointer dangling */
    if (g_stored_callback) {
        g_stored_callback(42);  /* potential UAF */
    }
}

/* ============================================================
 * GO-06: C frees Go-allocated cgo pointer (CWE-763 + CWE-415)
 * Go allocates via _Cfunc_GoMalloc, C frees with free().
 * Then Go also frees via _Cfunc_GoFree.
 * Expected: cross_language_free + double_free
 * ============================================================ */
void go_06_double_free_cgo(void) {
    void* ptr = _Cfunc_GoMalloc(128);
    strcpy((char*)ptr, "Go allocated via cgo");

    free(ptr);            /* BUG: C free on Go memory */
    _Cfunc_GoFree(ptr);   /* BUG: Go also frees — double free */
}

/* ============================================================
 * GO-07: Go string passed to C, C modifies it (CWE-787)
 * Go strings are immutable. C receives the data pointer and
 * writes to it, violating Go's string invariant.
 * Expected: write_to_immutable / undefined_behavior
 * ============================================================ */
void go_07_mutate_go_string(GoString* s) {
    /* BUG: Go strings are immutable, C is writing to the buffer */
    char* mutable = (char*)s->data;
    mutable[0] = 'X';  /* write violation */
}

/* ============================================================
 * GO-08: C pointer stored in Go struct, Go GC doesn't trace (CWE-401)
 * C allocates memory, stores pointer in a Go struct field.
 * Go's GC doesn't trace C pointers → leak if Go side drops ref.
 * Expected: memory_leak
 * ============================================================ */
void go_08_c_ptr_in_go_struct(void) {
    void* c_mem = malloc(4096);
    memset(c_mem, 0, 4096);

    /* Store in Go-managed struct (simulated) */
    GoSlice slice;
    slice.data = c_mem;
    slice.len = 4096;
    slice.cap = 4096;

    /* Go side drops the slice reference */
    slice.data = NULL;
    slice.len = 0;

    /* BUG: c_mem is leaked — Go GC can't free C pointers */
    /* C side has no reference to free it either */
}

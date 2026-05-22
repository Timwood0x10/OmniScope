/**
 * OmniScope Red Team — Go CGo Boundary Bug Test Cases
 *
 * Simulates bugs that occur at Go ↔ C FFI boundaries.
 * These patterns appear in real Go CGo code when:
 *   - C holds pointers to Go memory that gets GC'd
 *   - Go holds C pointers that get freed
 *   - Goroutine safety violations across FFI
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Simulated Go runtime functions */
typedef struct { void *data; int len; int cap; } GoSlice;
typedef struct { void *data; int len; } GoString;
typedef void* GoContext;

/* Simulated CGo bridge functions */
void _Cgo_register_callback(void (*cb)(void*, int), void *ctx);
void _Cgo_trigger_callback(void);
void* _Cgo_get_buffer(void);
void  _Cgo_release_buffer(void* buf);
int   _Cgo_process(GoSlice slice);

/* ================================================================
 * GO-CGO-01: Go slice pointer escapes to C, GC may collect it
 *
 * Go allocates a slice, passes raw pointer to C.
 * C stores the pointer. Go's GC doesn't know C holds it.
 * GC collects the backing array → C has dangling pointer.
 *
 * Expected: borrow_escape / use_after_free
 * ================================================================ */
static void* g_stored_go_ptr = NULL;

void go_cgo_01_gc_escape(void) {
    char *buf = (char*)malloc(256);  /* Simulates Go heap allocation */
    strcpy(buf, "Go GC managed memory");

    GoSlice slice = {buf, 20, 256};
    _Cgo_process(slice);  /* C function receives Go pointer */

    /* C stores the pointer globally — Go GC doesn't track this */
    g_stored_go_ptr = buf;

    /* In real Go, GC could collect buf here because Go doesn't
     * know C still holds a reference to it */
    free(buf);  /* Simulates GC collection */

    /* Later, C tries to use the stored pointer — UAF */
    printf("GO-CGO-01: stored data = %s\n", (char*)g_stored_go_ptr);
}

/* ================================================================
 * GO-CGO-02: C memory freed by Go code
 *
 * C allocates memory with malloc(). Go code receives the pointer
 * through CGo and mistakenly frees it with free().
 * Then C tries to use it.
 *
 * Expected: cross_language_free / use_after_free
 * ================================================================ */
void go_cgo_02_c_freed_by_go(void) {
    char *c_buffer = (char*)malloc(128);  /* C allocation */
    strcpy(c_buffer, "C allocated memory");

    /* Pass to "Go" (simulated CGo call) */
    GoSlice slice = {c_buffer, 18, 128};
    _Cgo_process(slice);

    /* "Go" code mistakenly frees C memory */
    free(c_buffer);  /* BUG: Go should not free C memory */

    /* C still thinks it owns this memory */
    printf("GO-CGO-02: %s\n", c_buffer);  /* UAF */
}

/* ================================================================
 * GO-CGO-03: Callback captures Go pointer, GC moves it
 *
 * Go registers a C callback that receives a Go pointer.
 * GC may move Go objects (stack copying GC).
 * The callback receives a stale pointer.
 *
 * Expected: borrow_escape
 * ================================================================ */
static void go_callback(void *ctx, int value) {
    /* ctx is supposed to point to Go memory,
     * but GC may have moved it */
    char *data = (char*)ctx;
    printf("GO-CGO-03 callback: %s (value=%d)\n", data, value);
}

void go_cgo_03_callback_gc_move(void) {
    char *go_obj = (char*)malloc(64);
    strcpy(go_obj, "Go object that may move");

    /* Register callback with Go pointer as context */
    _Cgo_register_callback(go_callback, go_obj);

    /* Simulate: GC stack copying moves go_obj to new address.
     * The callback still has the old address. */
    char *new_location = (char*)malloc(64);
    memcpy(new_location, go_obj, 64);
    free(go_obj);  /* GC "moved" the object */
    go_obj = new_location;

    /* Callback fires with stale pointer */
    _Cgo_trigger_callback();  /* go_callback gets old address */

    free(go_obj);
}

/* ================================================================
 * GO-CGO-04: Go string to C — C stores pointer beyond call
 *
 * Go passes a GoString to C. The GoString.data pointer is only
 * valid for the duration of the call. C stores it.
 *
 * Expected: borrow_escape
 * ================================================================ */
static char* g_stored_go_string = NULL;

void go_cgo_04_string_escape(void) {
    char *str = (char*)malloc(64);
    strcpy(str, "temporary Go string");

    GoString gs = {str, 19};

    /* C function receives GoString and stores the data pointer */
    g_stored_go_string = gs.data;

    /* In real Go, the string data could be collected */
    free(str);

    /* C tries to use the stored string later */
    printf("GO-CGO-04: %s\n", g_stored_go_string);  /* UAF */
}

/* ================================================================
 * GO-CGO-05: Goroutine data race on shared C pointer
 *
 * Two goroutines (simulated as threads) access the same C-allocated
 * buffer without synchronization.
 *
 * Expected: data_race / thread_safety
 * ================================================================ */
static int* g_shared_c_ptr = NULL;

void go_cgo_05_goroutine_race(void) {
    g_shared_c_ptr = (int*)malloc(sizeof(int) * 100);

    /* Simulate: two goroutines writing to same buffer */
    for (int i = 0; i < 100; i++) {
        g_shared_c_ptr[i] = i;  /* Goroutine 1 writes */
        /* Goroutine 2 could be reading here — data race */
    }

    /* No synchronization before read */
    printf("GO-CGO-05: g_shared_c_ptr[50] = %d\n", g_shared_c_ptr[50]);

    free(g_shared_c_ptr);
}

/* ================================================================
 * Entry point
 * ================================================================ */
int main(void) {
    go_cgo_01_gc_escape();
    go_cgo_02_c_freed_by_go();
    go_cgo_03_callback_gc_move();
    go_cgo_04_string_escape();
    go_cgo_05_goroutine_race();
    return 0;
}

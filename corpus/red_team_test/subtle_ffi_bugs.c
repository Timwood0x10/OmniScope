/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope Red Team v2 — Subtle FFI/Unsafe Bug Test Cases     ║
 * ║  Design: Bugs that survive FIRST PASS code review              ║
 * ║  Focus: unsafe/FFI boundary, lifetime, ownership issues       ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * Each bug has:
 * - A realistic-looking "correct" implementation pattern
 * - One subtle mistake that's easy to miss in review
 * - Expected: OmniScope SHOULD detect these (they're real bugs)
 *
 * Compile: clang -S -emit-llvm -O0 -g -fno-discard-value-names
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

/* ================================================================
 * SUBTLE-01: Partial struct init + error path leak
 *
 * Pattern: Function allocates multiple struct members, initializes
 * them one by one, but an early return on intermediate error leaks
 * the already-allocated members. The cleanup code LOOKS complete
 * because it frees all fields — but only on the success path.
 *
 * Why subtle: Each individual free() call is present. The reviewer
 * sees "oh, they free a->name, a->data, and a->meta" and assumes
 * it's correct. They don't notice that error paths between allocations
 * jump to cleanup WITHOUT setting the not-yet-allocated fields to NULL.
 * ================================================================ */

typedef struct {
    char* name;
    char* data;
    void* meta;
    size_t data_len;
} ResourceCtx;

int subtle_01_partial_init_leak(const char* input_name, size_t len) {
    ResourceCtx* ctx = (ResourceCtx*)malloc(sizeof(ResourceCtx));
    if (!ctx) return -1;
    memset(ctx, 0, sizeof(ResourceCtx));

    ctx->name = strdup(input_name);
    if (!ctx->name) goto cleanup;         /* name allocated */

    ctx->data = (char*)malloc(len);
    if (!ctx->data) goto cleanup;          /* data allocated, name exists */
    memcpy(ctx->data, "hello", 6);

    ctx->meta = malloc(256);               /* BUG: if this fails... */
    if (!ctx->meta) goto cleanup;          /* ...jump to cleanup: frees name/data/meta */
                                         /* BUT meta was never assigned!        */
                                         /* Actually meta IS NULL here so free(NULL) is no-op */
                                         /* The REAL bug: data_len=0 means caller   */
                                         /* might double-free based on data_len   */
    ctx->data_len = len;

    /* ... do work ... */
    free(ctx->meta);
    free(ctx->data);
    free(ctx->name);
    free(ctx);
    return 0;

cleanup:
    /* Looks complete, BUT: if we jumped here after data allocation,
     * meta is still NULL (which is OK for free), BUT what if the
     * CALLER checks data_len to decide whether to free? */
    free(ctx->meta);     /* safe: NULL or valid */
    free(ctx->data);     /* safe: NULL or valid */
    free(ctx->name);     /* safe: always valid here */
    free(ctx);
    return -1;
}

/* ================================================================
 * SUBTLE-02: Callback registration with dangling stack pointer
 *
 * Pattern: A function registers a callback with a pointer to a
 * local variable. The callback is invoked asynchronously (e.g.,
 * via event loop, timer, or another thread). By the time the
 * callback fires, the stack frame is gone.
 *
 * Why subtle: The registration looks normal. The callback type
 * matches. There's no obvious use-after-free in the same function.
 * The bug is temporal — the pointer is valid NOW but won't be LATER.
 * ================================================================ */

typedef void (*event_callback_t)(void* user_data);

static event_callback_t g_callback = NULL;
static void* g_user_data = NULL;

/* Forward declaration for callback */
void subtle_02_helper_fn(void* user_data);

void subtle_02_stack_escape_via_callback(int value) {
    int buffer[4];
    buffer[0] = value;
    buffer[1] = value * 2;
    buffer[2] = value * 3;
    buffer[3] = 0;  /* null terminator for int array */

    /* Register callback with stack-local data */
    g_callback = &subtle_02_helper_fn;
    g_user_data = (void*)buffer;  /* BUG: buffer is on stack! */
                                   /* When g_callback fires later, buffer is gone */
    (void)g_user_data;
}

void subtle_02_helper_fn(void* user_data) {
    int* data = (int*)user_data;
    printf("value: %d\n", data[0]);  /* UAF when called asynchronously */
}

/* Helper to trigger the callback (simulates async invocation) */
void subtle_02_trigger(void) {
    if (g_callback) {
        g_callback(g_user_data);  /* BUG: uses escaped stack pointer */
    }
}

/* ================================================================
 * SUBTLE-03: realloc antipattern — lost original on failure
 *
 * Pattern: Classic `ptr = realloc(ptr, new_size)` without temp.
 * If realloc fails, ptr is NULL but original memory is leaked.
 *
 * Why subtle: This is one of THE most common real-world bugs.
 * It looks completely idiomatic. Many experienced programmers
 * make this mistake. Static analyzers should catch it.
 * ================================================================ */

char* subtle_03_realloc_lost_original(const char* src) {
    size_t len = strlen(src);
    char* buf = (char*)malloc(len + 1);
    if (!buf) return NULL;
    strcpy(buf, src);

    /* Append more data — need to grow */
    buf = (char*)realloc(buf, len + 1024);  /* BUG: if realloc returns NULL,
                                              * original buf is leaked!
                                              * Correct: tmp = realloc(...); if(tmp) buf=tmp;
                                              */
    if (!buf) return NULL;  /* original buf leaked here! */

    memset(buf + len, 'A', 1024);
    buf[len + 1024] = '\0';
    return buf;
}

/* ================================================================
 * SUBTLE-04: FFI boundary — size_t truncation
 *
 * Pattern: Rust/Go side passes a usize/u64 length parameter.
 * C side receives it as `int` (32-bit on some platforms).
 * Large values silently truncate, causing buffer under-allocation
 * followed by out-of-bounds write.
 *
 * Why subtle: The C code looks correct — it uses the `len` parameter
 * properly. The type mismatch is invisible at the C level. Only
 * cross-language analysis can catch this.
 * ================================================================ */

extern void rust_provides_buffer(void* c_buf, int c_capacity);

void subtle_04_size_truncation_write(void* foreign_buf, int len) {
    /* Caller (e.g., Rust) passes len as usize which could be > INT_MAX.
     * On 32-bit int truncation: len could become negative or small positive.
     * Either way, the actual buffer access is wrong. */
    char* dest = (char*)foreign_buf;
    for (int i = 0; i < len; i++) {      /* if len truncated to small value */
        dest[i] = (char)(i & 0xFF);     /* only writes partial buffer */
    }
    /* If len was actually huge (truncated from u64), we're supposed to
     * write much more than we did → info leak / partial init */
}

void subtle_04_size_truncation_copy(void* src, void* dst, int count) {
    /* Similar: count came from FFI as u64, truncated to int.
     * If count wraps negative, the loop doesn't execute at all
     * (silently dropping data). If count wraps to smaller positive,
     * we get a partial copy. */
    memcpy(dst, src, (size_t)count);  /* cast back hides the truncation */
}

/* ================================================================
 * SUBTLE-05: Double-close through fd aliasing
 *
 * Pattern: Two variables (or struct fields) hold the same file descriptor.
 * Both get closed. Second close operates on a recycled fd.
 *
 * Why subtle: Each close() is individually justified — "I'm done with
 * this resource." The aliasing isn't obvious unless you trace the
 * full data flow. In large codebases, the aliasing can span functions.
 * ================================================================ */

/* Simulated POSIX functions for compilation without full headers */
static int fake_open(const char* path, int flags) { (void)path; (void)flags; return 3; }
static ssize_t fake_read(int fd, void* buf, size_t count) { (void)fd; (void)buf; (void)count; return 0; }
static int fake_close(int fd) { (void)fd; return 0; }

typedef struct {
    int primary_fd;
    int shadow_fd;
} FdPair;

int subtle_05_double_close(const char* path) {
    FdPair pair;
    pair.primary_fd = fake_open(path, 0);  /* 0 instead of O_RDONLY */
    if (pair.primary_fd < 0) return -1;

    pair.shadow_fd = pair.primary_fd;

    char buf[256];
    ssize_t n = fake_read(pair.primary_fd, buf, sizeof(buf));
    (void)n;

    fake_close(pair.primary_fd);
    fake_close(pair.shadow_fd);

    return 0;
}

/* ================================================================
 * SUBTLE-06: Static buffer TOCTOU — returning internal state
 *
 * Pattern: Function returns a pointer to a static/internal buffer.
 * Caller stores the pointer. On next call, the buffer content changes.
 * This is a classic time-of-check-time-of-use / reentrancy issue.
 *
 * Why subtle: No explicit malloc/free. No obvious UAF. The function
 * "works correctly" when called once. The bug only manifests under
 * concurrency or repeated calls. Code reviewers rarely spot this.
 * ================================================================ */

const char* subtle_06_static_buffer_toctou(int id) {
    static char result[64];
    snprintf(result, sizeof(result), "entity_%d_metadata", id);
    return result;  /* BUG: returned pointer invalidated on next call */
}

void subtle_06_consumer(void) {
    const char* a = subtle_06_static_buffer_toctou(1);  /* -> "entity_1_metadata" */
    const char* b = subtle_06_static_buffer_toctou(2);  /* OVERWRITES a's buffer! */
    printf("a=%s b=%s\n", a, b);  /* a and b point to SAME buffer with "entity_2..." */
}

/* ================================================================
 * SUBTLE-07: FFI — borrowed pointer stored past borrow scope
 *
 * Pattern: C function receives a borrowed pointer from FFI caller
 * (e.g., Rust &str reference). C stores it in a global/cache for
 * later use. The borrowed reference is only valid during the FFI call.
 *
 * Why subtle: The C code just does `global_ptr = param`. Looks like
 * a harmless assignment. The lifetime constraint is entirely on the
 * FFI caller's side and invisible in C source.
 * ================================================================ */

static const char* borrowed_cache = NULL;
static size_t borrowed_cache_len = 0;

void subtle_07_store_borrowed_ptr(const char* borrowed_data, size_t len) {
    /* borrowed_data is valid ONLY during this call (it's a &str from Rust)
     * Storing it globally makes it a dangling pointer after return. */
    borrowed_cache = borrowed_data;     /* BUG: escaping borrowed reference */
    borrowed_cache_len = len;
}

const char* subtle_07_use_cached_later(void) {
    if (borrowed_cache) {
        return borrowed_cache;  /* May be dangling if Rust freed the original */
    }
    return "(no cache)";
}

/* ================================================================
 * SUBTLE-08: Integer overflow in allocation size
 *
 * Pattern: `calloc(count, sizeof(T))` where count comes from external input.
 * If count * sizeof(T) overflows size_t, a small buffer is allocated
 * but subsequent writes go out of bounds.
 *
 * Why subtle: calloc is used (good practice!). The multiplication is
 * implicit. No visible overflow in source. Only triggers with very
 * large count values.
 * ================================================================ */

typedef struct { int id; char data[64]; } Row;

Row* subtle_08_alloc_overflow(unsigned int count) {
    /* If count > SIZE_MAX/sizeof(Row), count*sizeof(Row) overflows.
     * calloc sees a small size, allocates small buffer.
     * Then the loop below writes past the end. */
    Row* rows = (Row*)calloc(count, sizeof(Row));  /* potential overflow */
    if (!rows) return NULL;

    for (unsigned int i = 0; i < count; i++) {
        rows[i].id = (int)i;           /* OOB write if overflow occurred */
        memset(rows[i].data, 0, 64);   /* OOB write if overflow occurred */
    }

    return rows;
}

/* ================================================================
 * SUBTLE-09: Uninitialized field in partially zeroed struct
 *
 * Pattern: Struct is allocated with calloc (zeroed), then SOME fields
 * are explicitly set. But a conditional path leaves a critical field
 * at its zeroed default, which happens to be a valid but WRONG
 * value for the logic that consumes it.
 *
 * Why subtle: No uninitialized memory in the traditional sense (calloc
 * zeroed everything). The bug is LOGICAL — the zero value is treated
 * as "not set" by the consumer, but nobody told the consumer that this
 * particular field might legitimately be zero.
 * ================================================================ */

typedef struct {
    int mode;
    void* impl;
    int initialized;
} Handler;

int subtle_09_calloc_logical_init(int mode_val) {
    Handler* h = (Handler*)calloc(1, sizeof(Handler));
    if (!h) return -1;

    h->mode = mode_val;
    h->initialized = 1;

    if (mode_val == 42) {
        h->impl = malloc(128);  /* Special mode needs extra allocation */
        if (!h->impl) {
            free(h);
            return -1;
        }
    }
    /* For mode != 42: h->impl remains NULL (from calloc)
     * Consumer checks h->impl != NULL before using it.
     * But what if consumer treats mode==0 specially and accesses
     * h->impl without checking? That's the subtle bug. */

    return 0;  /* Caller must eventually free(h->impl) and free(h) */
}

/* ================================================================
 * SUBTLE-10: FFI — enum value used as array index without bounds check
 *
 * Pattern: C function receives an enum-like int from FFI caller.
 * Uses it directly as index into a fixed-size array. No bounds check.
 * If the caller sends an invalid/out-of-range value → OOB read/write.
 *
 * Why subtle: Array indexing is the most common operation in C. Adding
 * bounds checks to every array access is impractical. The bug is only
 * visible when you know the index crosses an FFI boundary.
 * ================================================================ */

#define MAX_HANDLERS 8
static void* handler_table[MAX_HANDLERS];

void* subtle_10_enum_as_index(int handler_id) {
    /* handler_id comes from FFI (Rust enum cast to c_int).
     * If handler_id >= MAX_HANDLERS or < 0 → OOB access.
     * No bounds check here. */
    return handler_table[handler_id];  /* Potential OOB read */
}

void subtle_10_set_handler(int handler_id, void* fn) {
    /* Same pattern on write side */
    handler_table[handler_id] = fn;  /* Potential OOB write */
}

/* ================================================================
 * SUBTLE-11: Free of non-heap pointer via complex control flow
 *
 * Pattern: Through a series of conditionals and pointer arithmetic,
 * the code ends up calling free() on a pointer that wasn't returned
 * by malloc (could be stack address, mmap'd region, or even a
 * literal offset into a large allocation).
 *
 * Why subtle: The free() call is there. It looks responsible. But
 * tracing the origin of the pointer reveals it's not a malloc result.
 * Requires interprocedural or intra-procedural value tracking.
 * ================================================================ */

void subtle_11_free_non_heap(int flag) {
    char stack_buf[128];
    char* heap_buf = (char*)malloc(256);
    void* target;

    if (flag == 1) {
        target = heap_buf;  /* heap — OK to free */
    } else if (flag == 2) {
        target = stack_buf;  /* STACK — NOT OK to free! */
    } else {
        target = (char*)heap_buf + 64;  /* MID-OBJECT POINTER — NOT OK to free! */
    }

    /* ... use target ... */
    (void)target;

    /* BUG: frees stack or mid-object depending on flag */
    if (flag == 1 || flag == 2) {
        free(target);  /* flag==2: free(stack_buf) — undefined behavior! */
    } else {
        free(heap_buf);  /* flag==3: frees original, but target (=heap+64) leaked conceptually */
    }
}

/* ================================================================
 * SUBTLE-12: Use-after-free via cached pointer in global
 *
 * Pattern: Function A allocates and stores pointer in global.
 * Function B frees the global. Function C uses the global
 * without checking if it was already freed.
 *
 * Why subtle: Each function looks correct in isolation.
 * Function A: "allocate and store" — fine.
 * Function B: "free the resource" — fine.
 * Function C: "use the resource" — fine.
 * The bug is the SEQUENCE: B runs between A and C.
 * This requires interprocedural analysis.
 * ================================================================ */

static void* global_resource = NULL;

void subtle_12_allocate(void) {
    global_resource = malloc(4096);
}

void subtle_12_cleanup(void) {
    free(global_resource);  /* Sets global_resource to... nothing (forgot NULL!) */
    /* BUG: global_resource not set to NULL after free */
}

int subtle_12_use_after_cleanup(void) {
    subtle_12_allocate();
    subtle_12_cleanup();
    subtle_12_cleanup();  /* Double free of global_resource! */

    if (global_resource) {  /* Always true because not NULLed after free */
        *(int*)global_resource = 42;  /* Use-after-free / double-free victim */
        return 0;
    }
    return -1;
}

/* ================================================================
 * main — invoke all test functions
 * ================================================================ */

int main(void) {
    printf("=== Subtle Red Team Test v2 ===\n");

    subtle_01_partial_init_leak("test", 100);
    subtle_02_stack_escape_via_callback(42);
    subtle_02_trigger();
    char* r3 = subtle_03_realloc_lost_original("hello world");
    free(r3);

    char dummy[16] = {};
    subtle_04_size_truncation_write(dummy, 16);
    subtle_04_size_truncation_copy(dummy, dummy, 16);

    subtle_05_double_close("/dev/null");

    subtle_06_consumer();

    subtle_07_store_borrowed_ptr("sensitive_data", 14);
    printf("cached: %s\n", subtle_07_use_cached_later());

    Row* rows = subtle_08_alloc_overflow(10);
    free(rows);

    subtle_09_calloc_logical_init(0);
    subtle_09_calloc_logical_init(42);

    subtle_10_set_handler(0, (void*)&subtle_02_helper_fn);
    void* h = subtle_10_enum_as_index(0);
    (void)h;

    subtle_11_free_non_heap(2);
    subtle_11_free_non_heap(3);

    subtle_12_use_after_cleanup();

    printf("=== All subtle tests executed ===\n");
    return 0;
}

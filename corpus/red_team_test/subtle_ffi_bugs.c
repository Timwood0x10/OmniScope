/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope Red Team v3 — Pure FFI Boundary Bug Test Cases     ║
 * ║  Rule: ≥95% bugs are at FFI/unsafe boundary                   ║
 * ║  Each bug involves extern "C" or cross-language interaction   ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * All "extern" functions below simulate calls FROM foreign language
 * (Rust, Go, Python, etc.) INTO this C library.
 * All bugs occur AT the FFI boundary.
 */

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

/* ================================================================
 * Simulated FFI declarations — these come from FOREIGN code
 * (Rust's extern "C", Go's cgo, Python's ctypes, etc.)
 * ================================================================ */

/* Foreign allocator/deallocator */
extern void*  ffi_alloc(size_t size);
extern void   ffi_free(void* ptr);

/* Foreign callbacks — WE register these, THEY call back */
typedef void (*ffi_callback_t)(void* user_data, int event);
extern void  ffi_register_callback(ffi_callback_t cb, void* ctx);
extern void  ffi_trigger_event(int event_id);

/* Foreign data access */
extern int    ffi_process_buffer(void* buf, int len);  /* returns bytes written */
extern char*  ffi_get_string(void);                     /* returns foreign-owned string */
extern void*  ffi_get_raw_pointer(int id);              /* returns foreign-managed ptr */
extern size_t ffi_get_size_hint(void);                  /* untrusted size from foreign */

/* Foreign ownership transfer */
extern void   ffi_take_ownership(void* ptr);             /* claims ownership of our allocation */
extern void*  ffi_borrow_resource(int id);              /* lends us a borrowed pointer */

/* Foreign error reporting */
extern int    ffi_init_context(void** out_ctx);         /* 0=ok, -1=failure, fills *out_ctx */
extern int    ffi_write_data(void* ctx, const void* data, size_t len);

/* ================================================================
 * FFI-01: Borrowed pointer from FFI stored past call boundary
 *
 * Foreign code lends us a pointer via ffi_borrow_resource().
 * It's valid ONLY during this call. We store it globally.
 * When foreign code reclaims it, our global becomes dangling.
 *
 * Why subtle: The function signature doesn't say "borrowed". Reviewer
 * sees "store for later use" and thinks it's fine. Only the
 * temporal contract (valid during call only) reveals the bug.
 * ================================================================ */

static void* g_borrowed = NULL;

void ffi_01_store_borrowed_ptr(int resource_id) {
    void* borrowed = ffi_borrow_resource(resource_id);  /* ← FFI boundary: borrowed ref */
    g_borrowed = borrowed;                              /* BUG: escaping borrowed ref past FFI call */
}

int ffi_01_use_later(void) {
    if (g_borrowed) {
        *(int*)g_borrowed = 42;  /* UAF if foreign side reclaimed */
        return 0;
    }
    return -1;
}

/* ================================================================
 * FFI-02: Size truncation — foreign usize → local int
 *
 * Foreign code (e.g., Rust) passes length as 64-bit unsigned.
 * We receive it as `int` (32-bit signed). Large values truncate.
 *
 * Why subtle: The local code looks correct — it uses `len` properly.
 * The type mismatch is invisible at C level. Only cross-language
 * analysis can catch this.
 * ================================================================ */

void ffi_02_size_truncation_copy(const void* src, void* dst, int len) {
    /* len came from FFI as u64, truncated to int here.
     * If original was > INT_MAX: len wraps negative → memcpy does nothing
     * If original was between INT_MAX+1 and UINT_MAX: len wraps small positive
     *   → partial copy, information loss */
    memcpy(dst, src, (size_t)len);  /* cast hides the truncation */
}

void ffi_02_size_truncation_alloc(int requested) {
    /* Same pattern: foreign sends large size, int truncates,
     * we allocate too small, then OOB write happens */
    char* buf = (char*)malloc((size_t)requested);  /* may be tiny due to truncation */
    if (buf) {
        memset(buf, 0xAB, (size_t)requested);      /* OOB if truncated */
        free(buf);
    }
}

/* ================================================================
 * FFI-03: Stack-local address passed to FFI callback registration
 *
 * Register a callback with context pointing to stack variable.
 * FFI side stores the callback + ctx. When callback fires later
 * (async/timer/thread), stack frame is gone.
 *
 * Why subtle: Registration looks normal. The async nature of
 * callback invocation is not visible at the registration site.
 * ================================================================ */

static int g_event_count = 0;

void ffi_03_stack_ctx_callback(void* ctx, int event) {
    int* counter = (int*)ctx;  /* BUG: ctx was stack address, now dangling */
    *counter = event;          /* Write to potentially-freed stack */
    g_event_count++;
}

void ffi_03_register_with_stack_ctx(void) {
    int local_counter = 0;
    /* Pass stack address to FFI callback registry */
    ffi_register_callback(ffi_03_stack_ctx_callback, &local_counter);  /* BUG: &local_counter dies when we return */
    /* When ffi_trigger_event fires later, local_counter is gone */
}

/* ================================================================
 * FFI-04: Double-free via FFI ownership transfer confusion
 *
 * We allocate memory, pass it to FFI which takes ownership
 * (ffi_take_ownership). But we ALSO free it ourselves because
 * nobody documented who owns what.
 *
 * Why subtle: Each side looks correct in isolation.
 * - Our side: "I allocated it, I should clean up"
 * - FFI side: "You gave it to me via take_ownership, I'll free it"
 * The double-free happens unpredictably depending on timing.
 * ================================================================ */

void ffi_04_double_free_via_ownership(void) {
    void* data = malloc(256);
    if (!data) return;
    memset(data, 'X', 256);

    ffi_take_ownership(data);  /* FFI now owns data */

    /* ... time passes, we forget we gave it away ... */
    free(data);  /* BUG: double-free! FFI will also try to free this */
}

/* ================================================================
 * FFI-05: Using FFI-returned string after foreign invalidation
 *
 * ffi_get_string() returns a pointer to foreign-managed memory.
 * It's valid until the next FFI call (common C API pattern).
 * We store it, make another FFI call, then use the stale pointer.
 *
 * Why subtle: Classic C string API pattern (like getenv/strerror).
 * The invalidation rule is implicit and easy to forget.
 * ================================================================ */

const char* ffi_05_stale_string_ref(void) {
    const char* s1 = ffi_get_string();  /* valid now */
    /* Make another FFI call that might invalidate s1's backing store */
    const char* s2 = ffi_get_string();  /* s1 may be invalidated here */
    (void)s2;
    return s1;  /* BUG: returning potentially-invalidated pointer */
}

void ffi_05_use_stale(void) {
    const char* val = ffi_05_stale_string_ref();
    if (val && val[0]) {  /* Read from possibly-freed/reused memory */
        printf("value: %s\n", val);
    }
}

/* ================================================================
 * FFI-06: Untrusted size from FFI used for allocation + write
 *
 * ffi_get_size_hint() returns an untrusted size from foreign code.
 * We use it directly for malloc + memset without validation.
 * Foreign can send SIZE_MAX → overflow, or 0 → null deref, or
 * a huge number → OOM/VLA issues.
 *
 * Why subtle: Using a "hint" from FFI seems reasonable.
 * The lack of upper-bound validation is the bug.
 * ================================================================ */

void ffi_06_untrusted_size_alloc(void) {
    size_t hint = ffi_get_size_hint();
    /* No validation: hint could be 0, SIZE_MAX, or maliciously large */
    void* buf = malloc(hint);
    if (!buf) return;
    /* If hint was crafted to cause integer overflow in our allocator... */
    memset(buf, 0, hint);  /* May write way past actual allocation */
    free(buf);
}

/* ================================================================
 * FFI-07: FFI init returns error but output pointer still used
 *
 * ffi_init_context() returns error code AND fills *out_ctx on failure.
 * Some C APIs set *out_ctx = NULL on failure, others leave it garbage.
 * We don't check the return code before using *out_ctx.
 *
 * Why subtle: Two-output-pattern APIs are common in C FFI.
 * Forgetting to check return code while using the output param is
 * a classic FFI boundary mistake.
 * ================================================================ */

void ffi_07_null_deref_on_error(void) {
    void* ctx = NULL;
    int ret = ffi_init_context(&ctx);  /* ret=-1 means failure, ctx may be NULL/garbage */

    /* BUG: not checking ret before using ctx */
    ffi_write_data(ctx, "hello", 5);  /* Potential NULL deref / use-of-uninitialized */
}

/* ================================================================
 * FFI-08: FFI callback fires after our cleanup
 *
 * We register a callback with heap-allocated context.
 * Then we free the context. Later, FFI triggers the callback
 * which tries to use the freed context.
 *
 * Why subtle: Registration and cleanup are in different functions.
 * The lifecycle ordering bug only visible when tracing full execution.
 * ================================================================ */

/* Forward declarations for callbacks */
void ffi_08_cb_handler(void* ud, int ev);
void ffi_12_race_callback(void* ud, int ev);
void ffi_17_reentrant_cb(void* ud, int ev);

typedef struct { char* name; int id; } FfiCtx;

void ffi_08_cb_handler(void* ud, int ev) {
    FfiCtx* fc = (FfiCtx*)ud;
    printf("event %d for %s\n", ev, fc->name);  /* UAF: fc may be freed */
}

void ffi_08_register_then_cleanup(void) {
    FfiCtx* fc = (FfiCtx*)malloc(sizeof(FfiCtx));
    if (!fc) return;
    fc->name = strdup("test_ctx");
    fc->id = 42;

    ffi_register_callback(ffi_08_cb_handler, fc);  /* FFI stores fc pointer */

    free(fc);           /* BUG: freeing context that FFI still references */
    fc->name = NULL;    /* Use-after-free: writing to freed memory */
    free(fc);           /* Double-free! */
}

/* ================================================================
 * FFI-09: FFI provides raw pointer, we cast to wrong struct type
 *
 * ffi_get_raw_pointer(id) returns void* from foreign memory.
 * We cast it to our struct type without verifying the actual layout
 * matches. If foreign side changed its struct layout (version mismatch),
 * we read/write wrong offsets.
 *
 * Why subtle: Pointer casting between languages is standard FFI practice.
 * Layout mismatches are silent — no crash, just data corruption.
 * ================================================================ */

typedef struct { int x; double y; char tag[8]; } LocalStruct;

int ffi_09_wrong_layout_cast(int id) {
    void* raw = ffi_get_raw_pointer(id);
    if (!raw) return -1;

    LocalStruct* ls = (LocalStruct*)raw;  /* BUG: assuming foreign layout matches ours */
    /* If foreign struct has different field sizes/ordering:
     * - ls->x reads wrong offset
     * - ls->y reads misaligned (UB on some platforms)
     * - ls->tag overreads into adjacent memory */
    return ls->x + (int)ls->y;
}

/* ================================================================
 * FFI-10: FFI process_buffer — we don't validate returned byte count
 *
 * ffi_process_buffer(buf, len) writes into buf and returns bytes written.
 * If it returns > len, it means it wrote past our buffer (OOB by FFI).
 * Or if it returns negative (error), buf contents are undefined.
 * We trust the return value blindly.
 *
 * Why subtle: Trusting FFI return values is standard practice.
 * The bug is not checking bounds contract.
 * ================================================================ */

void ffi_10_unchecked_ffi_write(void) {
    char buf[64];
    int written = ffi_process_buffer(buf, sizeof(buf));  /* FFI writes into our buffer */

    /* BUG: not checking if written > sizeof(buf) (OOB) or written < 0 (error) */
    printf("processed %d bytes: %.32s\n", written, buf);  /* May read uninitialized/OOB data */
}

/* ================================================================
 * FFI-11: Allocating with our malloc, passing to FFI which frees
 * with ITS free (cross-deallocator mismatch)
 *
 * We malloc(), pass to FFI. FFI internally frees with ffi_free()
 * (which might be a different allocator — e.g., Rust's deallocator).
 * Then we also free() it. Or worse: FFI's free() crashes because
 * it wasn't allocated by ffi_alloc().
 *
 * Why subtle: Allocator mismatch across FFI boundary is a real problem
 * in mixed-language programs. Each side assumes its own allocator.
 * ================================================================ */

void ffi_11_allocator_mismatch(void) {
    void* data = malloc(1024);  /* Our allocator (system malloc) */
    if (!data) return;
    memset(data, 0, 1024);

    /* FFI internally might: ffi_free(data) to reclaim it.
     * Or FFI stores it and later its cleanup calls ffi_free(data).
     * Meanwhile we also call free(data). */
    ffi_take_ownership(data);  /* FFI promises to manage it (with its own free?) */

    /* If FFI uses a different allocator than system malloc:
     * their free(data) is undefined behavior.
     * If they use the same allocator: potential double-free. */
}

/* ================================================================
 * FFI-12: FFI callback with user_data that gets freed by another thread
 *
 * Multi-threaded scenario: Thread A registers callback with heap ctx.
 * Thread B (or FFI internal thread) frees the ctx.
 * Thread A's callback fires → UAF.
 *
 * Why subtle: Thread safety at FFI boundary is notoriously hard.
 * The race condition is not visible in single-threaded review.
 * ================================================================ */

static void* g_shared_ctx = NULL;

void ffi_12_race_callback(void* ud, int ev) {
    void* ctx = *(void**)ud;  /* dereference user_data as indirect pointer */
    if (ctx) {
        *(int*)ctx = ev;  /* UAF if another thread freed ctx */
    }
}

void ffi_12_thread_race_setup(void) {
    g_shared_ctx = malloc(64);
    ffi_register_callback(ffi_12_race_callback, &g_shared_ctx);
    /* Another thread could: free(g_shared_ctx); g_shared_ctx = NULL;
     * Then callback fires here → UAF through &g_shared_ctx → NULL deref */
}

/* ================================================================
 * FFI-13: FFI returns pointer to foreign stack/internal buffer
 *
 * Some FFI functions return pointers to their internal buffers
 * (not heap-allocated). Caller assumes heap-allocated and calls free().
 *
 * Why subtle: Common in C APIs (e.g., getenv returns static storage).
 * Freeing non-heap pointer is UB. Hard to distinguish without docs.
 * ================================================================ */

void ffi_13_free_foreign_internal_buf(void) {
    void* ptr = ffi_get_raw_pointer(99);  /* Might point to foreign static/stack buf */
    if (ptr) {
        free(ptr);  /* BUG: freeing foreign-internal memory! */
    }
}

/* ================================================================
 * FFI-14: FFI buffer — we pass undersized buffer, FFI writes past end
 *
 * We tell FFI our buffer is N bytes, but it's actually smaller.
 * Or: FFI's documentation says "buffer must be at least X bytes"
 * but we provide less. FFI trusts our size and writes X bytes.
 *
 * This is the REVERSE of FFI-10 — WE lie to FFI about buffer size.
 * ================================================================ */

void ffi_14_undersized_buffer_to_ffi(void) {
    char small[16];
    int result = ffi_process_buffer(small, 256);  /* Claim 256 bytes, only have 16! */
    /* FFI wrote up to 256 bytes into 16-byte stack buffer → STACK BUFFER OVERFLOW */
    (void)result;
}

/* ================================================================
 * FFI-15: FFI provides function pointer, we call with wrong args
 *
 * Foreign code gives us a function pointer via FFI. We cast it
 * to our expected signature and call it. If signatures don't match
 * (wrong arg count, wrong types), behavior is undefined.
 *
 * Why subtle: Function pointer casting across FFI is common.
 * Signature mismatch causes silent corruption.
 * ================================================================ */

typedef int (*ffi_op_fn)(void* ctx, int a, int b);

int ffi_15_wrong_sig_call(void* fn_ptr) {
    ffi_op_fn op = (ffi_op_fn)fn_ptr;  /* Cast without verifying signature */
    int tmp;
    return op(&tmp, 1, 2);  /* If actual func expects different args → UB */
}

/* ================================================================
 * FFI-16: FFI borrow — we modify data through borrowed pointer
 *
 * Foreign lends us read-only access (const pointer). We cast away
 * const and modify. Foreign side doesn't expect modification.
 *
 * Why subtle: const-correctness violation at FFI boundary.
 * May break foreign invariants silently.
 * ================================================================ */

void ffi_16_cast_away_const(const void* readonly_data) {
    /* FFI contract: readonly_data is borrowed, DO NOT MODIFY */
    char* mutable = (char*)readonly_data;  /* BUG: casting away const at FFI boundary */
    mutable[0] = '!';  /* Violating FFI contract — corrupts foreign data */
    mutable[1] = '\0';
}

/* ================================================================
 * FFI-17: Circular FFI dependency — A calls B calls A with stale state
 *
 * We call FFI function F. F calls our callback C. C accesses state
 * that was modified by F before calling C. If F's modifications
 * invalidated C's expected state → subtle consistency bug.
 *
 * Why subtle: Control flow crosses FFI boundary twice.
 * State mutations between entry and callback are hard to track.
 * ================================================================ */

static int g_state_version = 0;

void ffi_17_reentrant_cb(void* ud, int ev) {
    (void)ev;
    int* ver = (int*)ud;
    /* BUG: g_state_version might have been incremented by ffi_do_work
     * between when we saved it and when this callback fires */
    if (*ver != g_state_version) {
        /* Stale version detected — but we use it anyway */
        printf("version mismatch: %d vs %d\n", *ver, g_state_version);
    }
}

extern void ffi_do_work(ffi_callback_t cb, void* ud);

void ffi_17_circular_dependency(void) {
    int snapshot = g_state_version;
    ffi_do_work(ffi_17_reentrant_cb, &snapshot);
    /* ffi_do_work might increment g_state_version, then call our cb
     * with &snapshot which is now stale */
}

/* ================================================================
 * FFI-18: FFI provides array of pointers, we assume all non-NULL
 *
 * FFI returns an array of N pointers. We iterate assuming none are NULL.
 * Foreign side might put NULL entries for "no data" semantics.
 *
 * Why subtle: Null-checking every array element is tedious.
 * Easy to skip in review. FFI contract might not document null policy.
 * ================================================================ */

void ffi_18_ffo_array_no_null_check(void** arr, int count) {
    for (int i = 0; i < count; i++) {
        printf("item %d: %s\n", i, (char*)arr[i]);  /* BUG: arr[i] could be NULL → UB in printf %s */
    }
}

/* ================================================================
 * FFI-19: FFI error code mapped incorrectly to our enum
 *
 * FFI returns error codes as integers. We map them to our enum.
 * If FFI adds new error codes we don't know about, they fall into
 * default/wrong case. Or if FFI changes error code meanings.
 *
 * Why subtle: Error code mapping is maintenance burden.
 * New FFI versions can silently break our handling.
 * ================================================================ */

enum { FFI_OK = 0, FFI_ERR_IO = -1, FFI_ERR_MEM = -2, FFI_ERR_ARG = -3 };

void ffi_19_error_code_mismatch(int ffi_err) {
    switch (ffi_err) {
        case FFI_OK:     printf("ok\n"); break;
        case FFI_ERR_IO:  printf("io error\n"); break;
        case FFI_ERR_MEM: printf("oom\n"); break;
        case FFI_ERR_ARG: printf("bad arg\n"); break;
        default:
            /* BUG: FFI added ERR_BUSY=-4 but we don't handle it.
             * Falls here and we treat unknown error as success-ish */
            printf("unknown error %d, continuing...\n", ffi_err);
            break;
    }
}

/* ================================================================
 * FFI-20: FFI setjmp/longjmp across boundary — cleanup skipped
 *
 * FFI function uses setjmp/longjmp for error handling.
 * When it longjmps back, our locally allocated resources leak
 * because the cleanup code is bypassed.
 *
 * Why subtle: Non-local control flow at FFI boundary skips destructors.
 * In C there are no destructors — manual cleanup gets bypassed.
 * ================================================================ */

void ffi_20_longjmp_bypasses_cleanup(int input) {
    void* res1 = malloc(128);
    void* res2 = malloc(256);
    if (!res1 || !res2) goto done;

    /* Call FFI that might longjmp on error */
    int ret = ffi_process_buffer(res1, input);  /* Might longjmp, skipping cleanup below */

    memcpy(res2, res1, 128);  /* Normal path */

done:
    /* This cleanup only reached on NORMAL return.
     * If ffi_process_buffer longjmp'd here, res1 and res2 LEAK. */
    free(res2);
    free(res1);
}

/* ================================================================
 * CONTROL-01 (≤5% noise): Simple general memory leak — NOT an FFI bug
 *
 * This is the ONE allowed non-FFI bug. Should NOT be caught by
 * OmniScope's FFI-specific passes (or if caught, it's a bonus).
 * ================================================================ */

void control_01_general_leak(void) {
    void* p = malloc(42);
    (void)p;
    /* Missing: free(p) — pure C leak, nothing to do with FFI */
}

/* ================================================================
 * main
 * ================================================================ */

int main(void) {
    printf("=== Red Team v3: Pure FFI Boundary Bugs ===\n");

    ffi_01_store_borrowed_ptr(0);
    ffi_01_use_later();

    ffi_02_size_truncation_copy(NULL, NULL, 0x100000001ULL);
    ffi_02_size_truncation_alloc(0x100000001);

    ffi_03_register_with_stack_ctx();

    ffi_04_double_free_via_ownership();

    ffi_05_use_stale();

    ffi_06_untrusted_size_alloc();

    ffi_07_null_deref_on_error();

    ffi_08_register_then_cleanup();

    ffi_09_wrong_layout_cast(0);

    ffi_10_unchecked_ffi_write();

    ffi_11_allocator_mismatch();

    ffi_12_thread_race_setup();

    ffi_13_free_foreign_internal_buf();

    ffi_14_undersized_buffer_to_ffi();

    ffi_15_wrong_sig_call(NULL);

    { const char dummy[] = "readonly"; ffi_16_cast_away_const(dummy); }

    ffi_17_circular_dependency();

    { void* arr[] = {"a", "b", NULL, "d"}; ffi_18_ffo_array_no_null_check(arr, 4); }

    ffi_19_error_code_mismatch(-4);

    ffi_20_longjmp_bypasses_cleanup(99);

    control_01_general_leak();

    printf("=== Done: 20 FFI bugs + 1 control ===\n");
    return 0;
}

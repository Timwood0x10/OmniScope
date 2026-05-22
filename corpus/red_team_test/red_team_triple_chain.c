/**
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║  OmniScope Red Team — Triple Language Chain: Go → C → Rust          ║
 * ║  Memory flows across THREE language boundaries.                      ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 *
 * Architecture:
 *
 *   ┌─────────────┐     CGo FFI      ┌─────────────┐    extern "C"    ┌─────────────┐
 *   │  Go Code    │ ───────────────→  │  C Bridge   │ ──────────────→  │  Rust Code  │
 *   │  (GC)       │ ←───────────────  │  (Manual)   │ ←──────────────  │  (Ownership)│
 *   └─────────────┘     CGo FFI      └─────────────┘    extern "C"    └─────────────┘
 *
 * Each boundary has different memory safety models:
 *   - Go:   Garbage collector, goroutine-safe
 *   - C:    Manual malloc/free, no safety
 *   - Rust: Ownership + borrow checker, Drop trait
 *
 * Bugs occur when memory management assumptions conflict across boundaries.
 *
 * Expected issues per section:
 *   CHAIN-01: cross_language_free (Go alloc → C free)
 *   CHAIN-02: cross_language_free (Rust alloc → C free)
 *   CHAIN-03: borrow_escape (Rust ref → C stores it)
 *   CHAIN-04: memory_leak (ownership lost across 3 languages)
 *   CHAIN-05: use_after_free (dangling pointer through chain)
 *   CHAIN-06: double_free (free in both Go and Rust)
 *   CHAIN-07: data_race (goroutine + C + Rust thread)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* ══════════════════════════════════════════════════════════════════════
 * Simulated Go runtime functions (what CGo generates)
 * ══════════════════════════════════════════════════════════════════════ */

typedef struct { void *data; int len; int cap; } GoSlice;
typedef struct { void *data; int len; }           GoString;
typedef void* GoContext;

/* Go's GC-tracked allocation (simulated) */
static void* go_alloc(int size) {
    /* In real Go, this is runtime.mallocgc */
    void* p = malloc(size);
    printf("[Go] runtime.alloc(%d) → %p\n", size, p);
    return p;
}

static void go_free(void* p) {
    /* In real Go, this is GC collection (implicit) */
    printf("[Go] GC collect %p\n", p);
    free(p);
}

/* ══════════════════════════════════════════════════════════════════════
 * Simulated Rust FFI functions (extern "C" exports from Rust)
 * ══════════════════════════════════════════════════════════════════════ */

static void* rust_alloc(int size) {
    /* In real Rust, this is __rust_alloc */
    void* p = malloc(size);
    printf("[Rust] __rust_alloc(%d) → %p\n", size, p);
    return p;
}

static void rust_dealloc(void* p, int size) {
    /* In real Rust, this is __rust_dealloc */
    printf("[Rust] __rust_dealloc(%p, %d)\n", p, size);
    free(p);
}

static void* rust_box_new(int size) {
    /* Simulates Box::new — Rust owns this memory */
    return rust_alloc(size);
}

static void rust_box_drop(void* p, int size) {
    /* Simulates Box::drop — Rust's Drop trait */
    printf("[Rust] Drop::drop(%p)\n", p);
    rust_dealloc(p, size);
}

/* ══════════════════════════════════════════════════════════════════════
 * C bridge functions — the middle layer
 * ══════════════════════════════════════════════════════════════════════ */

/* C receives Go memory and forwards to Rust */
static int c_bridge_process_go_data(GoSlice go_data) {
    printf("[C] Received Go slice: data=%p, len=%d\n", go_data.data, go_data.len);

    /* Forward to Rust for processing */
    /* Rust extern "C" fn process_buffer(buf: *const u8, len: usize) -> i32 */
    int result = go_data.len;  /* Simulated Rust processing */
    printf("[C] Rust returned: %d\n", result);
    return result;
}

/* C receives Rust Box and forwards to Go */
static void* c_bridge_pass_rust_to_go(void* rust_ptr) {
    printf("[C] Forwarding Rust ptr %p to Go\n", rust_ptr);
    return rust_ptr;  /* Just pass through */
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-01: Go allocates → C frees → Go GC tries to collect
 *
 * Go allocates memory via runtime.alloc. C receives it through
 * CGo, then mistakenly calls free() on it. Go's GC still tracks
 * the pointer and tries to collect it later → double free.
 *
 * Flow: Go(runtime.alloc) → C(CGo) → C(free) ← Go(GC also frees)
 *
 * Expected: cross_language_free (CWE-763)
 * ══════════════════════════════════════════════════════════════════════ */
void chain_01_go_alloc_c_free(void) {
    printf("\n=== CHAIN-01: Go alloc → C free ===\n");

    /* Go allocates (simulated CGo call) */
    void* go_ptr = go_alloc(256);
    strcpy((char*)go_ptr, "Go-managed data");

    /* Pass to C through CGo */
    GoSlice slice = {go_ptr, 15, 256};
    c_bridge_process_go_data(slice);

    /* [BUG] C frees Go-managed memory */
    free(go_ptr);  /* C should NOT free Go memory */

    /* Go's GC still thinks it owns this pointer.
     * When GC runs, it will try to free go_ptr again → double free */
    go_free(go_ptr);  /* GC collection attempt on already-freed memory */
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-02: Rust Box → C takes ownership → Go code frees
 *
 * Rust creates a Box (ownership semantics). C receives the raw
 * pointer through FFI. Go code then frees it through CGo.
 * Rust's Drop runs later → double free.
 *
 * Flow: Rust(Box::new) → C(extern "C") → Go(CGo free) ← Rust(Drop)
 *
 * Expected: cross_language_free (CWE-763)
 * ══════════════════════════════════════════════════════════════════════ */
void chain_02_rust_alloc_go_free(void) {
    printf("\n=== CHAIN-02: Rust Box → Go free ===\n");

    /* Rust allocates via Box (simulated) */
    void* rust_box = rust_box_new(128);
    strcpy((char*)rust_box, "Rust-owned Box data");

    /* Pass through C bridge to Go */
    void* go_received = c_bridge_pass_rust_to_go(rust_box);
    printf("[Go] Received from C: %p\n", go_received);

    /* [BUG] Go frees Rust-owned memory */
    go_free(go_received);  /* Go should NOT free Rust Box */

    /* Rust Drop trait still runs → tries to dealloc again */
    rust_box_drop(rust_box, 128);  /* Double free */
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-03: Rust &mut ref → C stores pointer → Rust ref still active
 *
 * Rust lends a mutable reference to C. C stores the raw pointer.
 * Rust's borrow checker doesn't know C holds it. Rust uses the
 * reference again → aliasing violation.
 *
 * Flow: Rust(&mut T) → C(CGo) → C(stores ptr) → Rust(uses &mut T again)
 *
 * Expected: borrow_escape (CWE-562)
 * ══════════════════════════════════════════════════════════════════════ */
static void* g_c_stored_rust_ref = NULL;

/* C function that receives Rust &mut reference */
void c_takes_rust_ref(void* rust_ref) {
    printf("[C] Received Rust &mut ref: %p\n", rust_ref);
    /* [BUG] C stores the reference — escapes Rust's borrow scope */
    g_c_stored_rust_ref = rust_ref;
}

void chain_03_rust_ref_escape(void) {
    printf("\n=== CHAIN-03: Rust &mut ref → C stores ===\n");

    /* Rust allocates and creates mutable reference */
    void* rust_data = rust_alloc(64);
    strcpy((char*)rust_data, "Rust mutable ref data");

    /* Pass &mut to C (simulated extern "C" call) */
    c_takes_rust_ref(rust_data);

    /* Rust still thinks it exclusively owns rust_data.
     * Uses it again — but C also has a pointer to it. */
    printf("[Rust] Still using: %s\n", (char*)rust_data);

    /* Meanwhile, C could be writing to g_c_stored_rust_ref */
    strcpy((char*)g_c_stored_rust_ref, "C wrote this!");  /* Aliasing! */

    printf("[Rust] Data changed unexpectedly: %s\n", (char*)rust_data);

    rust_dealloc(rust_data, 64);
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-04: Ownership lost across 3 languages — memory leak
 *
 * Go passes ownership to C, C passes to Rust. Rust expects Go
 * to free (it's Go's memory). Go expects Rust to free (Rust has
 * it now). Nobody frees → leak.
 *
 * Flow: Go(alloc) → C(bridge) → Rust(receives, expects Go to free)
 *        Go(expects Rust to free) → nobody frees
 *
 * Expected: memory_leak (CWE-401)
 * ══════════════════════════════════════════════════════════════════════ */
void chain_04_ownership_lost(void) {
    printf("\n=== CHAIN-04: Ownership lost across 3 languages ===\n");

    /* Go allocates */
    void* go_mem = go_alloc(512);
    strcpy((char*)go_mem, "Ownership chain data");

    /* Go passes to C (simulated CGo call) */
    GoSlice slice = {go_mem, 18, 512};
    c_bridge_process_go_data(slice);

    /* C passes to Rust (simulated extern "C" call) */
    void* rust_received = c_bridge_pass_rust_to_go(go_mem);
    printf("[Rust] Received: %p\n", rust_received);

    /* [BUG] Nobody frees:
     * - Go thinks Rust will free (Rust took ownership)
     * - Rust thinks Go will free (Go allocated, Go's GC responsibility)
     * - C just passes through, doesn't own anything
     * → Memory leaks
     */
    printf("[CHAIN-04] Memory at %p leaked — no language claims ownership\n", go_mem);
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-05: Dangling pointer through 3-language chain
 *
 * Rust allocates, passes to C, C passes to Go.
 * Rust frees (Drop). C and Go still hold dangling pointers.
 *
 * Flow: Rust(alloc) → C(bridge) → Go(receives) → Rust(Drop frees)
 *        Go(still holds dangling ptr) → UAF
 *
 * Expected: use_after_free (CWE-416)
 * ══════════════════════════════════════════════════════════════════════ */
void chain_05_dangling_through_chain(void) {
    printf("\n=== CHAIN-05: Dangling pointer through chain ===\n");

    /* Rust allocates */
    void* rust_mem = rust_alloc(128);
    strcpy((char*)rust_mem, "data that will dangle");

    /* Rust → C → Go chain */
    void* c_holds = c_bridge_pass_rust_to_go(rust_mem);
    void* go_holds = c_holds;  /* Go receives the same pointer */

    /* [BUG] Rust drops the data (ownership semantics) */
    rust_box_drop(rust_mem, 128);  /* Rust frees it */

    /* C still has pointer */
    printf("[C] C still holds: %s\n", (char*)c_holds);  /* UAF */

    /* Go still has pointer */
    printf("[Go] Go still holds: %s\n", (char*)go_holds);  /* UAF */
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-06: Double free — freed in both Go and Rust
 *
 * Memory is allocated in C, passed to both Go and Rust through
 * different paths. Both think they own it and both free it.
 *
 * Expected: double_free (CWE-415)
 * ══════════════════════════════════════════════════════════════════════ */
void chain_06_double_free_two_langs(void) {
    printf("\n=== CHAIN-06: Double free in Go and Rust ===\n");

    /* C allocates */
    void* shared = malloc(128);
    strcpy((char*)shared, "shared ownership data");
    printf("[C] Allocated: %p\n", shared);

    /* C passes to Go (path 1) */
    void* go_ref = shared;
    printf("[Go] Got pointer from C path 1: %p\n", go_ref);

    /* C passes to Rust (path 2) */
    void* rust_ref = c_bridge_pass_rust_to_go(shared);
    printf("[Rust] Got pointer from C path 2: %p\n", rust_ref);

    /* [BUG] Go frees it */
    go_free(go_ref);
    printf("[Go] Freed %p\n", go_ref);

    /* [BUG] Rust also frees it — double free! */
    rust_dealloc(rust_ref, 128);
    printf("[Rust] Also freed %p — DOUBLE FREE\n", rust_ref);
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-07: Data race — Go goroutine + Rust thread via C
 *
 * Go spawns a goroutine that writes to shared memory.
 * Rust spawns a thread (through C) that reads the same memory.
 * No synchronization → data race.
 *
 * Expected: data_race / thread_safety
 * ══════════════════════════════════════════════════════════════════════ */
static int* g_shared_race_buffer = NULL;
static int  g_race_running = 1;

void* rust_thread_func(void* arg) {
    /* Simulated Rust thread reading shared buffer */
    for (int i = 0; i < 100 && g_race_running; i++) {
        int val = g_shared_race_buffer[0];  /* [BUG] No lock — data race */
        printf("[Rust thread] read: %d\n", val);
    }
    return NULL;
}

void chain_07_data_race(void) {
    printf("\n=== CHAIN-07: Data race Go ↔ Rust via C ===\n");

    g_shared_race_buffer = (int*)malloc(sizeof(int) * 10);
    g_shared_race_buffer[0] = 0;

    /* Spawn "Rust thread" through C bridge */
    pthread_t thread;
    pthread_create(&thread, NULL, rust_thread_func, NULL);

    /* "Go goroutine" writes to shared buffer */
    for (int i = 0; i < 100; i++) {
        g_shared_race_buffer[0] = i;  /* [BUG] No lock — data race */
    }

    g_race_running = 0;
    pthread_join(thread, NULL);

    free(g_shared_race_buffer);
}

/* ══════════════════════════════════════════════════════════════════════
 * CHAIN-08: Full chain — Go → C → Rust → C → Go with 3 bugs
 *
 * Complex: Go allocates → C wraps → Rust processes → C returns → Go frees
 * But Rust keeps a copy, C modifies original, Go frees → 3 bugs.
 *
 * Expected: borrow_escape + use_after_free + cross_language_free
 * ══════════════════════════════════════════════════════════════════════ */
static void* g_rust_kept_copy = NULL;

void chain_08_full_chain_triple_bug(void) {
    printf("\n=== CHAIN-08: Full Go→C→Rust→C→Go chain ===\n");

    /* Step 1: Go allocates */
    void* go_data = go_alloc(256);
    strcpy((char*)go_data, "Go data through the chain");
    printf("[Go] Allocated: %p\n", go_data);

    /* Step 2: Go → C (CGo) */
    GoSlice go_slice = {go_data, 25, 256};
    c_bridge_process_go_data(go_slice);
    printf("[C] Received from Go: %p\n", go_data);

    /* Step 3: C → Rust (extern "C") */
    /* Rust processes the data but keeps a reference */
    g_rust_kept_copy = go_data;  /* [BUG-1] Rust keeps reference */
    printf("[Rust] Processing, but kept copy at %p\n", g_rust_kept_copy);

    /* Step 4: Rust → C (returns result) */
    int result = 42;  /* Simulated Rust result */
    printf("[C] Rust result: %d\n", result);

    /* Step 5: C modifies the data (doesn't know Rust has a copy) */
    strcpy((char*)go_data, "C modified!");  /* [BUG-2] Rust still reads */
    printf("[C] Modified data: %s\n", (char*)go_data);

    /* Step 6: C → Go (returns) */
    printf("[Go] Got back: %s\n", (char*)go_data);

    /* Step 7: Go frees (GC) */
    go_free(go_data);  /* [BUG-3] Rust still holds g_rust_kept_copy */

    /* Rust later tries to use its copy — UAF */
    printf("[Rust] Trying to read kept copy: %s\n",
           (char*)g_rust_kept_copy);  /* UAF */
}

/* ══════════════════════════════════════════════════════════════════════
 * Entry point
 * ══════════════════════════════════════════════════════════════════════ */
int main(void) {
    printf("╔══════════════════════════════════════════════════════════╗\n");
    printf("║  OmniScope Red Team — Triple Language Chain Test Suite   ║\n");
    printf("║  Go ↔ C ↔ Rust boundary bugs                            ║\n");
    printf("╚══════════════════════════════════════════════════════════╝\n");

    chain_01_go_alloc_c_free();
    chain_02_rust_alloc_go_free();
    chain_03_rust_ref_escape();
    chain_04_ownership_lost();
    chain_05_dangling_through_chain();
    chain_06_double_free_two_langs();
    chain_07_data_race();
    chain_08_full_chain_triple_bug();

    printf("\n══════════════════════════════════════════════════════════\n");
    printf("All chain tests completed. Expected OmniScope findings:\n");
    printf("  - 4 cross_language_free\n");
    printf("  - 2 borrow_escape\n");
    printf("  - 3 use_after_free\n");
    printf("  - 1 memory_leak\n");
    printf("  - 1 data_race\n");
    printf("  - 1 double_free\n");
    printf("Total: ~12 issues across 8 test cases\n");
    printf("══════════════════════════════════════════════════════════\n");

    return 0;
}

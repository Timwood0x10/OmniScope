/**
 * Rust → C FFI Boundary Bugs
 *
 * Tests cross-language issues at the Rust ↔ C boundary.
 * All bugs are FFI-specific: alloc/free mismatch, ownership transfer,
 * lifetime escape, borrow violation across the FFI boundary.
 *
 * Naming follows Rust mangling conventions (_R prefix) so the tool
 * can detect language origins.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* Simulated Rust allocator (uses _R prefix per RFC 2603 v0 mangling) */
extern void* _RZN4alloc5alloc17h_allocate(size_t size);
extern void  _RZN4alloc5alloc17h_deallocate(void* ptr);

/* Simulated Rust Box::into_raw / Box::from_raw */
extern void* _RZN3std3box8into_rawE(void* ptr);
extern void* _RZN3std3box8from_rawE(void* ptr);

/* Simulated Rust String into_raw */
extern void* _RZN3std3string10into_rawEv(void* ptr);

/* ============================================================
 * RUST-01: Rust alloc → C free (CWE-763)
 * Rust allocates via its allocator, C frees with free().
 * Rust's allocator may use a different heap than C.
 * Expected: cross_language_free
 * ============================================================ */
void rust_01_alloc_c_free(void) {
    void* ptr = _RZN4alloc5alloc17h_allocate(128);
    strcpy((char*)ptr, "allocated in Rust");
    free(ptr);  /* BUG: C free() on Rust-allocated memory */
}

/* ============================================================
 * RUST-02: C alloc → Rust free (CWE-763)
 * C allocates with malloc, Rust frees with its deallocator.
 * Expected: cross_language_free
 * ============================================================ */
void rust_02_c_alloc_rust_free(void) {
    void* ptr = malloc(256);
    strcpy((char*)ptr, "allocated in C");
    _RZN4alloc5alloc17h_deallocate(ptr);  /* BUG: Rust free on C memory */
}

/* ============================================================
 * RUST-03: Box::into_raw then C free (CWE-763)
 * Common pattern: Rust Box converted to raw pointer, passed to C.
 * C incorrectly frees with free() instead of Box::from_raw.
 * Expected: cross_language_free
 * ============================================================ */
void rust_03_box_raw_c_free(void) {
    void* boxed = _RZN3std3box8into_rawE(NULL);
    /* C side receives the raw pointer and mistakenly frees it */
    free(boxed);  /* BUG: should use Box::from_raw to reclaim */
}

/* ============================================================
 * RUST-04: C stores Rust reference, Rust drops (CWE-416)
 * Rust passes a reference to C. C stores it in a global.
 * Rust drops the original, C's global becomes dangling.
 * Expected: use_after_free / borrow_escape
 * ============================================================ */
static void* g_stored_rust_ref = NULL;

void rust_04_store_rust_ref(void) {
    void* rust_obj = _RZN4alloc5alloc17h_allocate(64);
    g_stored_rust_ref = rust_obj;  /* C stores reference */

    /* Rust side drops the object */
    _RZN4alloc5alloc17h_deallocate(rust_obj);

    /* BUG: g_stored_rust_ref is now dangling */
    /* Later access would be use-after-free */
    memset(g_stored_rust_ref, 0, 64);  /* UAF */
}

/* ============================================================
 * RUST-05: Rust String ownership lost across FFI (CWE-401)
 * Rust passes an owned String as raw pointer to C.
 * Neither side frees → memory leak.
 * Expected: memory_leak
 * ============================================================ */
void rust_05_string_leak(void) {
    void* rust_string = _RZN3std3string10into_rawEv(NULL);
    /* C receives the pointer but doesn't know how to free Rust String */
    printf("string at %p\n", rust_string);
    /* BUG: nobody frees — Rust thinks C owns it, C doesn't know how */
}

/* ============================================================
 * RUST-06: Double free across FFI boundary (CWE-415)
 * Rust frees its object, then C also frees the same pointer.
 * Expected: double_free
 * ============================================================ */
void rust_06_double_free_cross(void) {
    void* ptr = _RZN4alloc5alloc17h_allocate(64);
    _RZN4alloc5alloc17h_deallocate(ptr);  /* Rust frees */
    free(ptr);  /* BUG: C also frees — double free */
}

/* ============================================================
 * RUST-07: Mutable reference aliasing across FFI (CWE-362)
 * Rust passes &mut to C. C creates a second pointer to same data.
 * Both are used, violating Rust's aliasing rules.
 * Expected: borrow_escape / undefined_behavior
 * ============================================================ */
void rust_07_mut_alias_escape(void) {
    void* rust_mut_ref = _RZN4alloc5alloc17h_allocate(128);
    void* alias = rust_mut_ref;  /* C creates alias */

    /* Both pointers used simultaneously — violates Rust borrow rules */
    strcpy((char*)rust_mut_ref, "via original");
    strcpy((char*)alias, "via alias");  /* BUG: aliased mutable access */

    _RZN4alloc5alloc17h_deallocate(rust_mut_ref);
}

/* ============================================================
 * RUST-08: Realloc across language boundary (CWE-763)
 * Rust allocates, C reallocs with C's realloc, then Rust frees.
 * The pointer may have moved to C's heap.
 * Expected: cross_language_free
 * ============================================================ */
void rust_08_realloc_cross(void) {
    void* ptr = _RZN4alloc5alloc17h_allocate(64);
    strcpy((char*)ptr, "small");

    /* C reallocs — may move to C's heap */
    ptr = realloc(ptr, 4096);
    strcat((char*)ptr, " extended");

    /* BUG: Rust free on potentially C-allocated memory */
    _RZN4alloc5alloc17h_deallocate(ptr);
}

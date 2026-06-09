/*
 * Large FFI Stress Test
 * Tests scalability of FFI/unsafe boundary analysis with many FFI patterns
 * Expected Issues: 50+
 * - Multiple FFI boundary crossings
 * - Complex ownership transfer chains
 * - Deep nested FFI calls
 * - Large-scale data flow analysis
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// External FFI functions with realistic naming patterns
// Use libc standard functions for C
void* malloc(size_t size);
void free(void* ptr);

// Simulated Rust functions with realistic naming
// Rust mangled names start with _R (RFC 2603)
// Or contain alloc::, core::, std:: patterns
void _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(void** ptr);
void _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(void* ptr);

// Real Rust allocator intrinsic (recognized by allocation_classifier)
void* __rust_alloc(size_t size, size_t align);
void __rust_dealloc(void* ptr, size_t size, size_t align);

// Simulated Zig allocator functions
// Zig allocator patterns: Allocator., allocImpl
void zig_allocator_allocImpl(void** ptr, size_t size);
void zig_allocator_freeImpl(void* ptr);

// Simulated Go cgo functions
// Go cgo uses C.malloc, C.free patterns
void _cgo_allocate(void** ptr, size_t size);
void _cgo_free(void* ptr);

// Stress test: Generate 20 FFI allocation functions
#define GEN_FFI_ALLOC_FUNC(n) \
    void ffi_alloc_##n(void) { \
        void* ptr; \
        _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr); \
        /* Leak: never call rust_consume_and_free */ \
    }

// Cross-lang mismatch: Rust __rust_alloc freed by C free()
// This SHOULD trigger detectCrossLangAllocMismatch
void rust_alloc_c_free_mismatch(void) {
    void* ptr = __rust_alloc(128, 8);
    // BUG: Rust allocator freed by C free() — allocator mismatch
    free(ptr);
}

// Cross-lang mismatch: C malloc freed by Rust __rust_dealloc
void c_malloc_rust_dealloc_mismatch(void) {
    void* ptr = malloc(128);
    // BUG: C allocator freed by Rust dealloc — allocator mismatch
    __rust_dealloc(ptr, 128, 8);
}

// Stress test: Generate 20 FFI free mismatch functions
#define GEN_FFI_MISMATCH_FUNC(n) \
    void ffi_mismatch_##n(void) { \
        void* ptr = malloc(64); \
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr); \
        /* Mismatch: C alloc, Rust free */ \
    }

// Manual test functions with proper language naming patterns
// C++ caller (starts with _Z) calling Rust allocator, freed with C free
void _Z12cpp_rust_mismatchv(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    // Mismatch: Rust alloc, C free
    if (ptr != NULL) {
        free(ptr);
    }
}

// Rust caller (starts with _R) calling C malloc, freed with Rust drop
void _RZN12rust_c_mismatch17hba3a1b2c3d4e5f6g(void) {
    void* ptr = malloc(64);
    // Mismatch: C alloc, Rust free
    if (ptr != NULL) {
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
    }
}

// Zig caller (contains allocImpl) calling C malloc, freed with Zig free
void zig_allocImpl_c_mismatch(void) {
    void* ptr = malloc(64);
    // Mismatch: C alloc, Zig free
    if (ptr != NULL) {
        zig_allocator_freeImpl(ptr);
    }
}

// C caller calling Zig allocator, freed with C free
void c_zig_mismatch(void) {
    void* ptr;
    zig_allocator_allocImpl(&ptr, 64);
    // Mismatch: Zig alloc, C free
    if (ptr != NULL) {
        free(ptr);
    }
}

// Stress test: Generate 20 FFI ownership transfer chains
#define GEN_FFI_CHAIN_FUNC(n) \
    void ffi_chain_##n(void) { \
        void* ptr1, *ptr2, *ptr3; \
        _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr1); \
        zig_allocator_allocImpl(&ptr2, 64); \
        _cgo_allocate(&ptr3, 64); \
        /* Leak: all three pointers lost */ \
    }

// Generate stress test functions
GEN_FFI_ALLOC_FUNC(01) GEN_FFI_ALLOC_FUNC(02) GEN_FFI_ALLOC_FUNC(03) GEN_FFI_ALLOC_FUNC(04) GEN_FFI_ALLOC_FUNC(05)
GEN_FFI_ALLOC_FUNC(06) GEN_FFI_ALLOC_FUNC(07) GEN_FFI_ALLOC_FUNC(08) GEN_FFI_ALLOC_FUNC(09) GEN_FFI_ALLOC_FUNC(10)
GEN_FFI_ALLOC_FUNC(11) GEN_FFI_ALLOC_FUNC(12) GEN_FFI_ALLOC_FUNC(13) GEN_FFI_ALLOC_FUNC(14) GEN_FFI_ALLOC_FUNC(15)
GEN_FFI_ALLOC_FUNC(16) GEN_FFI_ALLOC_FUNC(17) GEN_FFI_ALLOC_FUNC(18) GEN_FFI_ALLOC_FUNC(19) GEN_FFI_ALLOC_FUNC(20)

GEN_FFI_MISMATCH_FUNC(01) GEN_FFI_MISMATCH_FUNC(02) GEN_FFI_MISMATCH_FUNC(03) GEN_FFI_MISMATCH_FUNC(04) GEN_FFI_MISMATCH_FUNC(05)
GEN_FFI_MISMATCH_FUNC(06) GEN_FFI_MISMATCH_FUNC(07) GEN_FFI_MISMATCH_FUNC(08) GEN_FFI_MISMATCH_FUNC(09) GEN_FFI_MISMATCH_FUNC(10)
GEN_FFI_MISMATCH_FUNC(11) GEN_FFI_MISMATCH_FUNC(12) GEN_FFI_MISMATCH_FUNC(13) GEN_FFI_MISMATCH_FUNC(14) GEN_FFI_MISMATCH_FUNC(15)
GEN_FFI_MISMATCH_FUNC(16) GEN_FFI_MISMATCH_FUNC(17) GEN_FFI_MISMATCH_FUNC(18) GEN_FFI_MISMATCH_FUNC(19) GEN_FFI_MISMATCH_FUNC(20)

GEN_FFI_CHAIN_FUNC(01) GEN_FFI_CHAIN_FUNC(02) GEN_FFI_CHAIN_FUNC(03) GEN_FFI_CHAIN_FUNC(04) GEN_FFI_CHAIN_FUNC(05)
GEN_FFI_CHAIN_FUNC(06) GEN_FFI_CHAIN_FUNC(07) GEN_FFI_CHAIN_FUNC(08) GEN_FFI_CHAIN_FUNC(09) GEN_FFI_CHAIN_FUNC(10)
GEN_FFI_CHAIN_FUNC(11) GEN_FFI_CHAIN_FUNC(12) GEN_FFI_CHAIN_FUNC(13) GEN_FFI_CHAIN_FUNC(14) GEN_FFI_CHAIN_FUNC(15)
GEN_FFI_CHAIN_FUNC(16) GEN_FFI_CHAIN_FUNC(17) GEN_FFI_CHAIN_FUNC(18) GEN_FFI_CHAIN_FUNC(19) GEN_FFI_CHAIN_FUNC(20)

// Complex nested FFI structure
typedef struct {
    void* rust_ptr;
    void* zig_ptr;
    void* go_ptr;
    void* c_ptr;
} FFIPointerBundle;

FFIPointerBundle* create_ffi_bundle(void) {
    FFIPointerBundle* bundle = (FFIPointerBundle*)malloc(sizeof(FFIPointerBundle));
    if (bundle == NULL) return NULL;

    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&bundle->rust_ptr);
    zig_allocator_allocImpl(&bundle->zig_ptr, 128);
    _cgo_allocate(&bundle->go_ptr, 128);
    bundle->c_ptr = malloc(128);

    // Leak: bundle not freed if any allocation fails
    if (bundle->rust_ptr == NULL || bundle->zig_ptr == NULL ||
        bundle->go_ptr == NULL || bundle->c_ptr == NULL) {
        if (bundle->rust_ptr) _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(bundle->rust_ptr);
        if (bundle->zig_ptr) zig_allocator_freeImpl(bundle->zig_ptr);
        if (bundle->go_ptr) _cgo_free(bundle->go_ptr);
        if (bundle->c_ptr) free(bundle->c_ptr);
        return NULL;  // bundle leaked
    }

    return bundle;
}

// Cross-language ownership transfer
void cross_lang_transfer(void** ptr_out) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    *ptr_out = ptr;
    // Ownership transferred to caller
}

// Recursive FFI allocation
void recursive_ffi_alloc(int depth) {
    if (depth <= 0) return;

    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    // Leak: ptr never freed

    recursive_ffi_alloc(depth - 1);
}

// Loop FFI allocation
void loop_ffi_alloc(int iterations) {
    for (int i = 0; i < iterations; i++) {
        void* ptr;
        zig_allocator_allocImpl(&ptr, 64);
        // Leak: ptr never freed in loop
    }
}

// FFI data flow through complex structure
typedef struct {
    FFIPointerBundle* bundle;
    char* data;
    void** ptr_array;
    size_t count;
} ComplexFFIStruct;

ComplexFFIStruct* create_complex_ffi_struct(size_t count) {
    ComplexFFIStruct* cfs = (ComplexFFIStruct*)malloc(sizeof(ComplexFFIStruct));
    if (cfs == NULL) return NULL;

    cfs->bundle = create_ffi_bundle();
    cfs->data = (char*)malloc(256);
    cfs->ptr_array = (void**)malloc(count * sizeof(void*));
    cfs->count = count;

    for (size_t i = 0; i < count; i++) {
        _cgo_allocate(&cfs->ptr_array[i], 64);
    }

    // Complex leak scenario
    if (cfs->bundle == NULL || cfs->data == NULL || cfs->ptr_array == NULL) {
        // Incomplete cleanup
        if (cfs->data) free(cfs->data);
        if (cfs->ptr_array) free(cfs->ptr_array);
        return NULL;  // cfs leaked, FFI pointers leaked
    }

    return cfs;
}

// FFI boundary crossing stress
void ffi_boundary_stress(void) {
    void* ptr1, *ptr2, *ptr3, *ptr4, *ptr5;

    // Chain of FFI allocations
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr1);
    zig_allocator_allocImpl(&ptr2, 64);
    _cgo_allocate(&ptr3, 64);
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr4);
    zig_allocator_allocImpl(&ptr5, 128);

    // All leaked
}

int main() {
    // Call manual test functions with proper language naming patterns
    _Z12cpp_rust_mismatchv();
    _RZN12rust_c_mismatch17hba3a1b2c3d4e5f6g();
    zig_allocImpl_c_mismatch();
    c_zig_mismatch();

    // Cross-lang mismatch tests (should trigger detectCrossLangAllocMismatch)
    rust_alloc_c_free_mismatch();
    c_malloc_rust_dealloc_mismatch();

    // Call stress test functions
    ffi_alloc_01(); ffi_alloc_02(); ffi_alloc_03(); ffi_alloc_04(); ffi_alloc_05();
    ffi_alloc_06(); ffi_alloc_07(); ffi_alloc_08(); ffi_alloc_09(); ffi_alloc_10();
    ffi_mismatch_01(); ffi_mismatch_02(); ffi_mismatch_03(); ffi_mismatch_04(); ffi_mismatch_05();
    ffi_chain_01(); ffi_chain_02(); ffi_chain_03(); ffi_chain_04(); ffi_chain_05();
    ffi_alloc_11(); ffi_alloc_12(); ffi_alloc_13(); ffi_alloc_14(); ffi_alloc_15();
    ffi_alloc_16(); ffi_alloc_17(); ffi_alloc_18(); ffi_alloc_19(); ffi_alloc_20();
    ffi_mismatch_06(); ffi_mismatch_07(); ffi_mismatch_08(); ffi_mismatch_09(); ffi_mismatch_10();
    ffi_mismatch_11(); ffi_mismatch_12(); ffi_mismatch_13(); ffi_mismatch_14(); ffi_mismatch_15();
    ffi_mismatch_16(); ffi_mismatch_17(); ffi_mismatch_18(); ffi_mismatch_19(); ffi_mismatch_20();
    ffi_chain_06(); ffi_chain_07(); ffi_chain_08(); ffi_chain_09(); ffi_chain_10();
    ffi_chain_11(); ffi_chain_12(); ffi_chain_13(); ffi_chain_14(); ffi_chain_15();
    ffi_chain_16(); ffi_chain_17(); ffi_chain_18(); ffi_chain_19(); ffi_chain_20();

    create_ffi_bundle();
    void* ptr;
    cross_lang_transfer(&ptr);
    recursive_ffi_alloc(10);
    loop_ffi_alloc(100);
    create_complex_ffi_struct(50);
    ffi_boundary_stress();

    return 0;
}

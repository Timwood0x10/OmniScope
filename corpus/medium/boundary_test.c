/*
 * Medium FFI Boundary Test
 * Tests edge cases and boundary conditions for FFI/unsafe analysis
 * Expected Issues: 20+
 * - Null pointer handling at FFI boundaries
 * - Extreme allocation sizes
 * - Boundary overflow/underflow conditions
 * - Circular ownership references
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>

// External FFI functions with realistic naming patterns
// Use libc standard functions for C
void* malloc(size_t size);
void free(void* ptr);

// Simulated Rust functions with realistic naming
// Rust mangled names start with _R (RFC 2603)
void _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(void** ptr);
void _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(void* ptr);

// Simulated Zig allocator functions
// Zig allocator patterns: Allocator., allocImpl
void zig_allocator_allocImpl(void** ptr, size_t size);
void zig_allocator_freeImpl(void* ptr);

// Simulated Go cgo functions
void _cgo_allocate(void** ptr, size_t size);
void _cgo_free(void* ptr);

// Boundary Test 1: Null pointer at FFI boundary
void null_ptr_ffi_boundary(void) {
    void* ptr = NULL;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    // If ptr is NULL, this is a boundary error
    if (ptr != NULL) {
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
    }
}

// Boundary Test 2: Zero size allocation
void zero_size_alloc(void) {
    void* ptr;
    zig_allocator_allocImpl(&ptr, 0);
    // Zero-size allocation is a boundary case
    if (ptr != NULL) {
        zig_allocator_freeImpl(ptr);
    }
}

// Boundary Test 3: Maximum size allocation
void max_size_alloc(void) {
    void* ptr;
    size_t max_size = SIZE_MAX;
    zig_allocator_allocImpl(&ptr, max_size);
    // Maximum size allocation is a boundary case
    if (ptr != NULL) {
        zig_allocator_freeImpl(ptr);
    }
}

// Boundary Test 4: Negative size (cast to size_t)
void negative_size_alloc(void) {
    void* ptr;
    zig_allocator_allocImpl(&ptr, (size_t)-1);
    // Negative size cast to size_t is a boundary error
    if (ptr != NULL) {
        zig_allocator_freeImpl(ptr);
    }
}

// Boundary Test 5: Buffer just before overflow
void buffer_near_overflow(void) {
    char* buffer = (char*)malloc(100);
    if (buffer == NULL) return;

    strcpy(buffer, "safe string");  // Safe
    strncpy(buffer, "a", 99);       // Safe (null terminator)
    buffer[99] = '\0';              // Safe

    free(buffer);
}

// Boundary Test 6: Buffer exactly at overflow
void buffer_at_overflow(void) {
    char* buffer = (char*)malloc(100);
    if (buffer == NULL) return;

    char long_str[101];
    memset(long_str, 'A', 100);
    long_str[100] = '\0';
    strcpy(buffer, long_str);  // Overflow at boundary

    free(buffer);
}

// Boundary Test 7: Circular ownership reference
typedef struct Node {
    struct Node* next;
    void* ffi_ptr;
} Node;

Node* create_circular_ownership(void) {
    Node* node1 = (Node*)malloc(sizeof(Node));
    Node* node2 = (Node*)malloc(sizeof(Node));
    
    if (node1 == NULL || node2 == NULL) {
        if (node1) free(node1);
        if (node2) free(node2);
        return NULL;
    }

    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&node1->ffi_ptr);
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&node2->ffi_ptr);

    node1->next = node2;
    node2->next = node1;  // Circular reference

    return node1;
    // Leak: circular reference, both nodes and FFI pointers leaked
}

// Boundary Test 8: Double free at FFI boundary
void ffi_double_free(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    if (ptr != NULL) {
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);  // Double free
    }
}

// Boundary Test 8: Use after free at FFI boundary
void ffi_use_after_free(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    if (ptr != NULL) {
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
        // Using ptr after free
        void* ptr2 = ptr;  // Use after free
        (void)ptr2;
    }
}

// Boundary Test 9: Ownership transfer to NULL
void ownership_transfer_to_null(void) {
    void* ptr;
    void** null_ptr = NULL;
    
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(null_ptr);  // Transfer to NULL pointer
}

// Boundary Test 10: FFI in error path
int ffi_in_error_path(int error_condition) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    if (error_condition) {
        return -1;  // ptr leaked on error path
    }
    
    _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
    return 0;
}

// Boundary Test 11: Nested FFI allocations with partial cleanup
void nested_ffi_partial_cleanup(void) {
    void* ptr1, *ptr2, *ptr3;
    
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr1);
    zig_allocator_allocImpl(&ptr2, 64);
    _cgo_allocate(&ptr3, 64);
    
    // Only free one of three
    if (ptr1 != NULL) {
        _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr1);
    }
    // ptr2 and ptr3 leaked
}

// Boundary Test 12: FFI allocation in loop with early exit
void ffi_loop_early_exit(int iterations, int exit_at) {
    for (int i = 0; i < iterations; i++) {
        void* ptr;
        _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
        
        if (i == exit_at) {
            return;  // All previous allocations leaked
        }
        
        if (ptr != NULL) {
            _RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr);
        }
    }
}

// Boundary Test 13: Mixed allocation sources
void mixed_allocation_sources(void) {
    void* rust_ptr;
    void* zig_ptr;
    void* go_ptr;
    void* c_ptr;
    
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&rust_ptr);
    zig_allocator_allocImpl(&zig_ptr, 64);
    _cgo_allocate(&go_ptr, 64);
    c_ptr = malloc(64);
    
    // All leaked - mixed allocation sources
}

// Boundary Test 14: FFI with format string
void ffi_format_string(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    char* user_input = (char*)ptr;  // Treat as string
    printf(user_input);  // Format string vulnerability
}

// Boundary Test 15: FFI with buffer overflow
void ffi_buffer_overflow(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    char* buffer = (char*)ptr;
    if (buffer != NULL) {
        strcpy(buffer, "very long string that might overflow");  // Potential overflow
    }
}

// Boundary Test 16: Allocation size overflow
void allocation_size_overflow(void) {
    size_t count = SIZE_MAX / sizeof(int);
    int* array = (int*)malloc(count * sizeof(int));
    // Size overflow
    if (array != NULL) {
        free(array);
    }
}

// Boundary Test 17: Realloc on FFI pointer
void ffi_realloc(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    
    if (ptr != NULL) {
        void* new_ptr = realloc(ptr, 128);
        // Realloc on FFI-allocated memory - unsafe
        (void)new_ptr;
    }
}

// Boundary Test 18: FFI pointer escape through return
void* ffi_ptr_escape(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    return ptr;  // Ownership unclear
}

// Boundary Test 19: FFI pointer stored in global
void* global_ffi_ptr = NULL;

void store_ffi_ptr_global(void) {
    void* ptr;
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr);
    global_ffi_ptr = ptr;
    // Global ownership unclear
}

// Boundary Test 20: Concurrent FFI allocations (simulated)
void concurrent_ffi_allocs(void) {
    void* ptr1, *ptr2, *ptr3;
    
    _RZN4alloc5alloc17hba3a1b2c3d4e5f6g(&ptr1);
    zig_allocator_allocImpl(&ptr2, 64);
    _cgo_allocate(&ptr3, 64);
    
    // Simulate concurrent access - all leaked
}

int main() {
    // Run all boundary tests
    null_ptr_ffi_boundary();
    zero_size_alloc();
    max_size_alloc();
    negative_size_alloc();
    buffer_near_overflow();
    buffer_at_overflow();
    
    Node* circular = create_circular_ownership();
    if (circular) free(circular);  // Incomplete cleanup
    
    ffi_double_free();
    ffi_use_after_free();
    ownership_transfer_to_null();
    ffi_in_error_path(1);
    nested_ffi_partial_cleanup();
    ffi_loop_early_exit(10, 5);
    mixed_allocation_sources();
    ffi_format_string();
    ffi_buffer_overflow();
    allocation_size_overflow();
    ffi_realloc();
    ffi_ptr_escape();
    store_ffi_ptr_global();
    concurrent_ffi_allocs();
    
    return 0;
}

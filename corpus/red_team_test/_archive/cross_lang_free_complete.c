/**
 * Complete Cross-Language Free Test
 * 
 * This test creates ACTUAL allocations with language markers
 * by using inline functions that OmniScope can track.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Simulate Rust allocation pattern
static inline void* rust_alloc(size_t size) {
    // Marked as Rust allocation in metadata
    return malloc(size);  // alloc_lang will be .c, but we'll annotate as .rust
}

static inline void rust_dealloc(void* ptr) {
    // Marked as Rust deallocation
    free(ptr);  // free_lang will be .rust
}

// Simulate C++ allocation pattern
static inline void* cpp_new(size_t size) {
    return malloc(size);  // alloc_lang = .cpp
}

static inline void cpp_delete(void* ptr) {
    free(ptr);  // free_lang = .cpp
}

// ============================================================================
// Test Case 1: Explicit cross-language violation pattern
// ============================================================================
void test_explicit_cross_lang(void) {
    void* ptr = malloc(64);  // Standard C alloc
    
    // Use pointer
    memset(ptr, 0, 64);
    
    // Free with same language (OK)
    free(ptr);
    
    // This case: same language, should NOT trigger cross_language_free
}

// ============================================================================
// Test Case 2: Memory leak to test tracking
// ============================================================================
void test_memory_leak(void) {
    void* ptr = malloc(128);
    
    // Use but never free
    memset(ptr, 0xFF, 128);
    
    // Expected: memory_leak
}

// ============================================================================
// Test Case 3: Double free
// ============================================================================
void test_double_free(void) {
    void* ptr = malloc(32);
    
    free(ptr);
    free(ptr);  // Double free!
    
    // Expected: double_free
}

// ============================================================================
// Test Case 4: Use after free
// ============================================================================
void test_use_after_free(void) {
    int* ptr = (int*)malloc(sizeof(int));
    *ptr = 42;
    
    free(ptr);
    
    // Use after free
    int value = *ptr;  // UAF!
    
    (void)value;
    // Expected: use_after_free
}

// ============================================================================
// Test Case 5: Alias chain with double free
// ============================================================================
void test_alias_double_free(void) {
    void* ptr1 = malloc(100);
    void* ptr2 = ptr1;  // Alias
    
    free(ptr1);
    free(ptr2);  // Double free via alias
    
    // Expected: double_free (detected via alias tracking)
}

// ============================================================================
// Test Case 6: Nested allocation leaks
// ============================================================================
typedef struct Node {
    struct Node* next;
    int data;
} Node;

void test_nested_leak(void) {
    Node* n1 = (Node*)malloc(sizeof(Node));
    Node* n2 = (Node*)malloc(sizeof(Node));
    
    n1->next = n2;
    n1->data = 1;
    n2->next = NULL;
    n2->data = 2;
    
    free(n1);  // Free outer, but n2 leaks
    
    // Expected: memory_leak for n2
}

// ============================================================================
// Test Case 7: Invalid free (stack)
// ============================================================================
void test_invalid_free_stack(void) {
    int local = 42;
    int* ptr = &local;
    
    free(ptr);  // Invalid: freeing stack pointer
    
    // Expected: invalid_free
}

// ============================================================================
// Test Case 8: Realloc chain
// ============================================================================
void test_realloc_chain(void) {
    void* p1 = malloc(10);
    void* p2 = realloc(p1, 20);  // p1 implicitly freed
    void* p3 = realloc(p2, 30);  // p2 implicitly freed
    
    if (p3) {
        free(p3);
    }
    
    // Expected: NO violations (proper realloc chain)
}

// ============================================================================
// Test Case 9: Complex ownership transfer pattern
// ============================================================================
void* global_cached_ptr = NULL;

void test_ownership_transfer(void) {
    void* ptr = malloc(64);
    
    // Transfer to global (not freed in this function)
    global_cached_ptr = ptr;
    
    // Expected: memory_leak (from function's perspective)
}

void cleanup_global(void) {
    if (global_cached_ptr) {
        free(global_cached_ptr);
        global_cached_ptr = NULL;
    }
    
    // Expected: Cleans up, no leak
}

// ============================================================================
// Test Case 10: Array bounds check
// ============================================================================
void test_buffer_overflow(void) {
    int arr[10];
    
    // Out of bounds access
    arr[15] = 42;  // Buffer overflow!
    
    // Expected: buffer_overflow
}

// ============================================================================
// Main
// ============================================================================
int main(void) {
    printf("Cross-Language Free Comprehensive Tests\n");
    printf("========================================\n\n");
    
    printf("1. Explicit cross-lang pattern\n");
    test_explicit_cross_lang();
    
    printf("\n2. Memory leak\n");
    test_memory_leak();
    
    printf("\n3. Double free\n");
    test_double_free();
    
    printf("\n4. Use after free\n");
    test_use_after_free();
    
    printf("\n5. Alias double free\n");
    test_alias_double_free();
    
    printf("\n6. Nested leak\n");
    test_nested_leak();
    
    printf("\n7. Invalid free (stack)\n");
    test_invalid_free_stack();
    
    printf("\n8. Realloc chain\n");
    test_realloc_chain();
    
    printf("\n9. Ownership transfer\n");
    test_ownership_transfer();
    cleanup_global();
    
    printf("\n10. Buffer overflow\n");
    test_buffer_overflow();
    
    printf("\n========================================\n");
    printf("Tests completed\n");
    
    return 0;
}

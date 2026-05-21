/**
 * Language Detection Fix Test - Complete Version
 * 
 * This file includes actual function definitions (not just declarations)
 * to demonstrate language detection fixes.
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ============================================
// Test Case 1: Simulated Rust Functions with _ZN
// ============================================

// Simulate Rust core::ptr::drop_in_place
// This should be detected as Rust due to:
// 1. "core" namespace
// 2. Hash suffix "17habc123E"
void _ZN4core3ptr13drop_in_place17habc123E(void* ptr) {
    // Simulated Rust drop logic
    if (ptr) {
        // Rust would call the destructor here
    }
}

// Simulate Rust std::mem::forget
// Should be detected as Rust due to "std" namespace + hash suffix
void _ZN3std3mem6forget17hdef456E(void* ptr) {
    // Simulated Rust forget - prevents destructor call
    (void)ptr;
}

// Simulate Rust alloc::alloc::dealloc
// Should be detected as Rust due to "alloc" namespace + hash suffix
void _ZN5alloc5alloc8dealloc17hghi789E(void* ptr, size_t size, size_t align) {
    // Simulated Rust deallocator
    if (ptr && size > 0) {
        free(ptr);
    }
    (void)align;
}

// ============================================
// Test Case 2: Simulated C++ Functions with _ZN
// ============================================

// Simulate C++ absl::Cord constructor
// Should be detected as C++ (no Rust markers)
void _ZN4absl4CordC2Ev(void* this) {
    // Simulated C++ constructor
    memset(this, 0, 100);
}

// Simulate C++ std::string destructor
// Should be detected as C++ (St = std namespace)
void _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev(void* this) {
    // Simulated C++ destructor
    free(this);
}

// ============================================
// Test Case 3: Simulated Rust Functions with _R
// ============================================

// Simulate Rust v0 mangling: _RNv...
// Should be detected as Rust v0 mangling
void _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(size_t size, size_t align) {
    // Simulated Rust allocator
    malloc(size);
    (void)align;
}

// Simulate Rust v0 mangling: _RINv...
// Should be detected as Rust v0 mangling
void _RINvC1a4main(void) {
    // Simulated Rust main function
    printf("Rust v0 mangling test\n");
}

// ============================================
// Test Case 4: Cross-Language Ownership Violations
// ============================================

// Rust allocates, C frees (VIOLATION)
void test_rust_alloc_c_free() {
    void* ptr = malloc(100);  // Simulated Rust allocation
    
    // This should trigger: rust_freed_by_c violation
    free(ptr);  // C freeing Rust memory
}

// C allocates, Rust frees (VIOLATION)
void test_c_alloc_rust_free() {
    void* ptr = malloc(100);  // C allocation
    
    // This should trigger: c_freed_by_rust violation
    _ZN5alloc5alloc8dealloc17hghi789E(ptr, 100, 8);
}

// C++ allocates, C frees (VIOLATION)
void test_cpp_alloc_c_free() {
    void* ptr = malloc(100);  // Simulated C++ allocation
    
    // This should trigger: cpp_freed_by_c violation
    free(ptr);  // C freeing C++ memory
}

// Rust allocates, C++ frees (VIOLATION)
void test_rust_alloc_cpp_free() {
    void* ptr = malloc(100);  // Simulated Rust allocation
    
    // This should trigger: rust_freed_by_cpp violation
    _ZN4absl4CordC2Ev(ptr);  // C++ destructor
}

// ============================================
// Test Case 5: False Positive Reduction
// ============================================

// These should NOT be flagged as dangerous
void register_user(const char* username) {
    printf("Registering user: %s\n", username);
}

void batch_process(int count) {
    printf("Processing batch of %d items\n", count);
}

void user_register_handler(int id) {
    printf("Handler for user %d\n", id);
}

void batch_size_calculator(int size) {
    printf("Batch size: %d\n", size);
}

// ============================================
// Test Case 6: Actual Dangerous Functions
// ============================================

void dangerous_system_call() {
    // This SHOULD be flagged as dangerous
    system("ls");
}

void dangerous_exec_call() {
    // This SHOULD be flagged as dangerous
    // exec family functions are dangerous
    printf("Would call exec here\n");
}

// ============================================
// Test Case 7: Language-Specific Patterns
// ============================================

// Test Rust-specific markers
void test_rust_markers() {
    void* ptr1 = malloc(50);
    _ZN4core3ptr13drop_in_place17habc123E(ptr1);  // Rust drop
    
    void* ptr2 = malloc(50);
    _ZN3std3mem6forget17hdef456E(ptr2);  // Rust forget
}

// Test C++-specific patterns
void test_cpp_patterns() {
    void* obj = malloc(100);
    _ZN4absl4CordC2Ev(obj);  // C++ constructor
    _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev(obj);  // C++ destructor
}

// Test Rust v0 mangling
void test_rust_v0_mangling() {
    _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(100, 8);  // Rust v0 alloc
    _RINvC1a4main();  // Rust v0 main
}

// ============================================
// Main Test Runner
// ============================================

int main() {
    printf("=== Language Detection Fix Test ===\n\n");
    
    // Test cross-language violations
    printf("Test 1: Cross-language violations\n");
    test_rust_alloc_c_free();
    test_c_alloc_rust_free();
    test_cpp_alloc_c_free();
    test_rust_alloc_cpp_free();
    
    // Test false positive reduction
    printf("\nTest 2: False positive reduction\n");
    register_user("test");
    batch_process(10);
    user_register_handler(1);
    batch_size_calculator(100);
    
    // Test actual dangerous functions
    printf("\nTest 3: Dangerous functions\n");
    dangerous_system_call();
    dangerous_exec_call();
    
    // Test language-specific patterns
    printf("\nTest 4: Language-specific patterns\n");
    test_rust_markers();
    test_cpp_patterns();
    test_rust_v0_mangling();
    
    printf("\n=== Test Complete ===\n");
    return 0;
}

/**
 * Language Detection Fix Test
 *
 * This file tests the fixes for language detection issues:
 * 1. _ZN prefix disambiguation between Rust and C++
 * 2. _R prefix detection for Rust v0 mangling
 * 3. Cross-language boundary violation detection
 * 4. Reduced false positives from overly broad patterns
 *
 * Expected detections:
 * - Rust functions with _ZN prefix should be correctly identified
 * - C++ functions with _ZN prefix should not be misclassified as Rust
 * - Rust functions with _R prefix should be detected
 * - Cross-language ownership violations should be reported
 */

#include <stdlib.h>
#include <string.h>

// ============================================
// Test Case 1: Rust _ZN Functions (should be detected as Rust)
// ============================================

// Simulate Rust core::ptr::drop_in_place function
// Mangled name: _ZN4core3ptr13drop_in_place17habc123E
extern void _ZN4core3ptr13drop_in_place17habc123E(void* ptr);

// Simulate Rust std::mem::forget function
// Mangled name: _ZN3std3mem6forget17hdef456E
extern void _ZN3std3mem6forget17hdef456E(void* ptr);

// Simulate Rust alloc::alloc::dealloc function
// Mangled name: _ZN5alloc5alloc8dealloc17hghi789E
extern void _ZN5alloc5alloc8dealloc17hghi789E(void* ptr, size_t size, size_t align);

// ============================================
// Test Case 2: C++ _ZN Functions (should be detected as C++)
// ============================================

// Simulate C++ absl::Cord function
// Mangled name: _ZN4absl4CordC2Ev
extern void _ZN4absl4CordC2Ev(void* this);

// Simulate C++ std::string function
// Mangled name: _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev
extern void _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev(void* this);

// ============================================
// Test Case 3: Rust _R Functions (should be detected as Rust)
// ============================================

// Simulate Rust v0 mangling: _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc
extern void _RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(size_t size, size_t align);

// Simulate Rust v0 mangling: _RINvC1a4main
extern void _RINvC1a4main(void);

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
    // Simulated Rust deallocation
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
    // Simulated C++ delete
    _ZN4absl4CordC2Ev(ptr);
}

// ============================================
// Test Case 5: False Positive Reduction
// ============================================

// These should NOT be flagged as dangerous (previously were false positives)
void register_user(const char* username) {
    // Normal function, should not be flagged
    // Previously incorrectly flagged due to "register" pattern
}

void batch_process(int count) {
    // Normal function, should not be flagged
    // Previously incorrectly flagged due to "batch" pattern
}

void user_register_handler(int id) {
    // Normal function, should not be flagged
    // Previously incorrectly flagged due to "register" pattern
}

void batch_size_calculator(int size) {
    // Normal function, should not be flagged
    // Previously incorrectly flagged due to "batch" pattern
}

// ============================================
// Test Case 6: Actual Dangerous Functions (should be flagged)
// ============================================

void dangerous_system_call() {
    // This SHOULD be flagged as dangerous
    system("ls");  // Command injection risk
}

void dangerous_exec_call() {
    // This SHOULD be flagged as dangerous
    // exec family functions are dangerous
}

// ============================================
// Main Test Runner
// ============================================

int main() {
    // Test cross-language violations
    test_rust_alloc_c_free();
    test_c_alloc_rust_free();
    test_cpp_alloc_c_free();
    test_rust_alloc_cpp_free();

    // Test false positive reduction
    register_user("test");
    batch_process(10);
    user_register_handler(1);
    batch_size_calculator(100);

    // Test actual dangerous functions
    dangerous_system_call();
    dangerous_exec_call();

    return 0;
}

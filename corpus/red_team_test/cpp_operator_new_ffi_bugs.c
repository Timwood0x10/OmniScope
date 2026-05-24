// C++ Operator New/Delete FFI Bug Test Cases
//
// Simulates C++ code using operator new/delete with cross-language FFI.
// Tests P2: C++ internal leak detection bypass (danger path gate relaxation)
// and C++ ↔ other languages free mismatches.
//
// Test case matrix:
//   TC1: new → free()                        [BUG: CWE-763 cross-language]
//   TC2: malloc → delete                     [BUG: CWE-763 cross-language]
//   TC3: new[] → delete (scalar)             [BUG: invalid_free (array→scalar)]
//   TC4: new (scalar) → delete[]             [BUG: invalid_free (scalar→array)]
//   TC5: new → delete                        [SAFE: correct C++ pairing]
//   TC6: Internal leak (not on danger path)   [BUG: MEDIUM - P2 bypass catches this]

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

// External declarations for C++ runtime functions (mangled names demangled for clarity)
extern void* operator_new(size_t size);       // _Znwm / _Znw
extern void* operator_new_array(size_t size); // _Znam / _Zna
extern void  operator_delete(void* ptr);      // _ZdlPv / _Zdl
extern void  operator_delete_array(void* ptr); // _ZdaPv / _Zda

// ============================================================================
// TC1: C++ operator new → C's free()
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - C++-allocated memory freed by C's free()
// Rationale: operator new uses C++ heap (may be custom allocator),
// while free() uses C runtime heap. Mismatch causes undefined behavior.
// ============================================================================
void tc1_cpp_new_c_free(void) {
    void* cpp_obj = operator_new(sizeof(int) * 100);  // C++ allocation
    memset(cpp_obj, 0, sizeof(int) * 100);

    // ... use cpp_obj as C++ object ...

    free(cpp_obj);  // ❌ BUG: Cross-language free (C++ new → C free)
}

// ============================================================================
// TC2: Reverse - C malloc → C++ delete
// BUG: Cross-language free (CWE-763)
// Expected: HIGH - C-allocated memory freed by C++'s delete
// Rationale: delete expects pointer from new (with possible vtable/metadata).
// malloc doesn't provide this metadata.
// ============================================================================
void tc2_c_malloc_cpp_delete(void) {
    void* c_mem = malloc(2048);  // C allocation
    memset(c_mem, 'X', 2048);

    // ... pass to C++ code via extern "C" bridge ...

    operator_delete(c_mem);  // ❌ BUG: Cross-language free (C malloc → C++ delete)
}

// ============================================================================
// TC3: Array new → Scalar delete (type mismatch within C++)
// BUG: Invalid free (wrong delete variant)
// Expected: CRITICAL if detected as array/size mismatch
// Rationale: new[] allocates with hidden size/count metadata.
// Scalar delete doesn't call destructors for array elements and may
// not free the correct amount of memory.
// ============================================================================
void tc3_array_new_scalar_delete(void) {
    void* arr = operator_new_array(sizeof(double) * 50);  // Array allocation
    memset(arr, 0, sizeof(double) * 50);

    // ... use arr as double[50] ...

    operator_delete(arr);  // ❌ BUG: Array alloc → scalar delete (memory corruption)
}

// ============================================================================
// TC4: Scalar new → Array delete (reverse mismatch)
// BUG: Invalid free (wrong delete variant)
// Expected: HIGH - May read out-of-bounds looking for array size
// Rationale: delete[] expects array metadata that scalar new didn't create.
// This can cause heap corruption or crash.
// ============================================================================
void tc4_scalar_new_array_delete(void) {
    void* scalar = operator_new(256);  // Scalar allocation
    memset(scalar, 0xAB, 256);

    // ... use scalar as single object ...

    operator_delete_array(scalar);  // ❌ BUG: Scalar new → array delete (UB)
}

// ============================================================================
// TC5: Correct C++ pairing
// SAFE: Proper new/delete usage
// Expected: No issue reported
// Rationale: Demonstrates safe C++ memory management with matching alloc/free.
// ============================================================================
void tc5_correct_cpp_memory(void) {
    // Correct scalar allocation/deallocation
    void* obj = operator_new(512);
    memset(obj, 1, 512);
    operator_delete(obj);  // ✅ SAFE: new → delete

    // Correct array allocation/deallocation
    void* arr = operator_new_array(sizeof(float) * 100);
    memset(arr, 0, sizeof(float) * 100);
    operator_delete_array(arr);  // ✅ SAFE: new[] → delete[]
}

// ============================================================================
// TC6: Internal C++ leak (P2 bypass scenario)
// BUG: Memory leak (CWE-401)
// Expected: MEDIUM - P2's danger path bypass should catch this
// Rationale: In C++ modules not on the main FFI danger path,
// internal leaks should still be detected at lower severity.
// This tests the P2 improvement that relaxes the danger path gate.
// ============================================================================
void tc6_internal_cpp_leak(void) {
    // Simulate internal C++ class method that leaks
    void* cache = operator_new(4096);  // Internal cache allocation
    memset(cache, 0xCC, 4096);

    // Use cache but forget to delete it
    // Function returns, cache leaked
    // ❌ MEMORY LEAK: No corresponding delete
}

// ============================================================================
// TC7: Mixed C/C++ multi-layer scenario
// BUG: Multiple cross-language issues in complex C++ FFI code
// Expected: Multiple issues with varying severities
// Rationale: Real-world C++ systems often mix malloc/new and free/delete,
// especially when interfacing with C libraries via extern "C".
// ============================================================================
void tc7_mixed_ccpp_ffi(void) {
    // Layer 1: C++ object creation
    void* cpp_obj = operator_new(1024);

    // Layer 2: C buffer for FFI
    void* c_buf = malloc(2048);

    // Layer 3: C++ array for data processing
    void* cpp_arr = operator_new_array(sizeof(int) * 200);

    // Layer 4: Another C allocation
    void* c_tmp = calloc(50, sizeof(char));

    // Initialize all
    memset(cpp_obj, 0xAA, 1024);
    memset(c_buf, 0xBB, 2048);
    memset(cpp_arr, 0, sizeof(int) * 200);
    // calloc already zeroed c_tmp

    // Intentionally wrong deallocations:
    free(cpp_obj);           // ❌ BUG #1: C++ new → C free
    operator_delete(c_buf);  // ❌ BUG #2: C malloc → C++ delete
    free(cpp_arr);           // ❌ BUG #3: C++ new[] → C free
    operator_delete_array(c_tmp); // ❌ BUG #4: C calloc → C++ delete[]
}

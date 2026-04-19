/*
 * C++ FFI Simple Test
 * Tests real C++→C FFI patterns for unsafe boundary analysis
 * 
 * Expected Issues: 3
 * - C++ new, C free (cross-language mismatch)
 * - RAII object escape across FFI boundary
 * - C++ object passed to C without ownership transfer
 */

#include <stdlib.h>
#include <string.h>

extern "C" {
    void c_process_string(char* ptr);
    void c_free_string(char* ptr);
}

// Test 1: C++ new, C free - cross-language mismatch
extern "C" void cpp_new_c_free() {
    char* ptr = new char[100];  // C++ allocation
    c_process_string(ptr);
    free(ptr);  // C free on C++ new - MISMATCH!
}

// Test 2: C++ malloc, C++ delete - mismatch
extern "C" void cpp_malloc_cpp_delete() {
    char* ptr = (char*)malloc(100);  // C allocation
    c_process_string(ptr);
    delete[] ptr;  // C++ delete on C malloc - MISMATCH!
}

// Test 3: RAII object escape - destructor not called
extern "C" char* raii_escape() {
    char* ptr = new char[100];
    strcpy(ptr, "hello");
    return ptr;  // Escape: RAII object escapes, destructor not called
}

// Test 4: Correct pattern - C++ new, C++ delete
extern "C" void correct_cpp_new_delete() {
    char* ptr = new char[100];
    strcpy(ptr, "hello");
    delete[] ptr;  // Correct: C++ delete
}

// Test 5: Correct pattern - C malloc, C free
extern "C" void correct_c_malloc_free() {
    char* ptr = (char*)malloc(100);
    if (ptr) {
        strcpy(ptr, "hello");
        free(ptr);  // Correct: C free
    }
}

int main() {
    cpp_new_c_free();
    cpp_malloc_cpp_delete();
    char* escaped = raii_escape();
    if (escaped) {
        // Need to free the escaped pointer
        free(escaped);
    }
    correct_cpp_new_delete();
    correct_c_malloc_free();
    return 0;
}

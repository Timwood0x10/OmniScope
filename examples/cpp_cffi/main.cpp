/**
 * @file main.cpp
 * @brief C++ code that calls C library via FFI
 * 
 * Demonstrates C++ → C FFI boundary crossing.
 * OmniScope should detect:
 * 1. Ownership transfer across C++/C boundary
 * 2. Dangerous C functions called from C++
 * 3. Memory management mismatches
 */

#include "math_ops.h"
#include <iostream>
#include <string>
#include <vector>

class Calculator {
public:
    // Safe FFI call - no memory involved
    int add(int a, int b) {
        return c_add(a, b);  // C++ → C FFI boundary
    }
    
    int multiply(int a, int b) {
        return c_multiply(a, b);  // C++ → C FFI boundary
    }
    
    // Ownership transfer: C++ allocates, C fills, C++ frees
    void processArray(size_t size) {
        int* arr = c_create_array(size);  // C allocates, ownership to C++
        if (arr) {
            c_fill_array(arr, size, 42);  // C borrows
            // Use array in C++
            for (size_t i = 0; i < size; i++) {
                std::cout << arr[i] << " ";
            }
            std::cout << std::endl;
            c_free_array(arr);  // C++ returns ownership to C for free
        }
    }
    
    // Dangerous: C++ passes data to vulnerable C function
    void unsafeCopy(const std::string& data) {
        char buffer[64];
        c_unsafe_copy(buffer, data.c_str());  // Line 47: FFI boundary + HIGH risk
        std::cout << "Copied: " << buffer << std::endl;
    }
    
    // Memory management across boundary
    void concatStrings(const std::string& a, const std::string& b) {
        char* result = c_unsafe_concat(a.c_str(), b.c_str());  // Line 53: FFI + ownership transfer
        if (result) {
            std::cout << "Concat: " << result << std::endl;
            // VULNERABILITY: Should free but using C++ delete instead of C free!
            // This is a potential mismatch
            free(result);  // Line 58: Correct - using C free
        }
    }
    
    // Command injection vulnerability
    void executeCommand(const std::string& userInput) {
        c_process_command(userInput.c_str());  // Line 64: FFI + CRITICAL risk
    }
};

int main() {
    Calculator calc;
    
    // Safe operations
    std::cout << "Add: " << calc.add(10, 20) << std::endl;
    std::cout << "Multiply: " << calc.multiply(10, 20) << std::endl;
    
    // Array operations with ownership transfer
    calc.processArray(5);
    
    // Dangerous operations
    calc.unsafeCopy("Hello from C++");
    calc.concatStrings("Hello ", "World");
    
    // Command injection test
    calc.executeCommand("test");
    
    return 0;
}

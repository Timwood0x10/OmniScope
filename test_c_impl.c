#include <stdio.h>

// C function that Rust calls
int c_function_that_rust_calls(int x) {
    printf("C function called with: %d\n", x);
    return x * 2;
}

// Shared function
int shared_c_function(int x) {
    printf("Shared C function called with: %d\n", x);
    return x * 3;
}

// Additional C function that doesn't have Rust declaration
void c_only_function() {
    printf("C only function\n");
}
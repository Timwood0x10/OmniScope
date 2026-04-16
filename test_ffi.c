#include <stdio.h>
#include <stdlib.h>

// C external function declarations
extern int rust_external_function(int x);
extern int zig_ffi_call(int y);

void test_rust_ffi() {
    int result = rust_external_function(42);
    printf("Rust FFI result: %d\n", result);
}

void test_zig_ffi() {
    int result = zig_ffi_call(24);
    printf("Zig FFI result: %d\n", result);
}

void test_libc_call() {
    int result = printf("Hello\n");
    // This is libc, not FFI boundary
}

int main() {
    test_rust_ffi();
    test_zig_ffi();
    test_libc_call();
    return 0;
}
#include <stdlib.h>

/// Takes ownership of a pointer from Rust Box::into_raw.
/// BUG: Uses free() instead of returning ownership to Rust.
void c_take_ownership(int* ptr) {
    // WRONG! This memory was allocated by Rust Box,
    // should not be freed by C free()
    free(ptr);
}

/// Correct way: return ownership to Rust.
void c_return_ownership(int* ptr) {
    // Do some processing...
    *ptr = 100;
    // Return ownership to Rust (Rust will call Box::from_raw)
    // Do NOT free here!
}

/// Another bug: storing borrowed pointer globally.
static int* global_ptr = 0;

void c_store_borrowed(int* ptr) {
    // BUG: This is a borrowed pointer from Rust,
    // storing it globally causes use-after-free
    global_ptr = ptr;
}

int* get_stored_ptr() {
    return global_ptr;
}

// Rust FFI declarations
extern "C" {
    fn c_function_that_rust_calls(x: i32) -> i32;
    fn shared_c_function(x: i32) -> i32;
}

pub fn rust_main() {
    unsafe {
        let result = c_function_that_rust_calls(42);
        println!("Result: {}", result);
    }
}

pub fn rust_shared() {
    unsafe {
        let result = shared_c_function(24);
        println!("Shared result: {}", result);
    }
}
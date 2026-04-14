// Rust test: Simple patterns for IR generation
// Using libcore for basic functionality

#[no_mangle]
pub extern "C" fn factorial(n: i32) -> i32 {
    if n <= 1 { 1 } else { n * factorial(n - 1) }
}

#[no_mangle]
pub extern "C" fn fibonacci(n: i32) -> i32 {
    if n <= 1 { n } else { fibonacci(n - 1) + fibonacci(n - 2) }
}

#[no_mangle]
pub extern "C" fn rust_entry() -> i32 {
    factorial(5) + fibonacci(10)
}

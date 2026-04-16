// FFI Benchmark Test - Rust Implementation
// This file calls C functions via FFI

#[link(name = "test_ffi_benchmark")]
extern "C" {
    // SAFE: Normal C function
    fn safe_function_c();

    // VULNERABLE: Calls vulnerable_system_command
    fn vulnerable_system_command(user_input: *const i8);

    // VULNERABLE: Calls vulnerable_buffer_overflow
    fn vulnerable_buffer_overflow(input: *const i8);

    // VULNERABLE: Calls vulnerable_format_string
    fn vulnerable_format_string(user_input: *const i8);

    // SAFE: Calls safe_with_length_check
    fn safe_with_length_check(input: *const i8);

    // VULNERABLE: Calls potential_use_after_free
    fn potential_use_after_free();

    // SAFE: Calls safe_memory_management
    fn safe_memory_management();

    // VULNERABLE: Calls potential_integer_overflow
    fn potential_integer_overflow(size: i32);

    // SAFE: Calls safe_external_call
    fn safe_external_call();
}

fn main() {
    println!("FFI Benchmark Test - Rust Side");

    unsafe {
        // Test 1: Safe FFI call
        safe_function_c();

        // Test 2: Vulnerable - command injection
        let user_input = std::ffi::CString::new("; rm -rf /").unwrap();
        vulnerable_system_command(user_input.as_ptr());

        // Test 3: Vulnerable - buffer overflow
        let large_input = std::ffi::CString::new("this_is_way_too_long").unwrap();
        vulnerable_buffer_overflow(large_input.as_ptr());

        // Test 4: Vulnerable - format string
        let format_input = std::ffi::CString::new("%s%s%s%s%s").unwrap();
        vulnerable_format_string(format_input.as_ptr());

        // Test 5: Safe FFI call
        let safe_input = std::ffi::CString::new("test").unwrap();
        safe_with_length_check(safe_input.as_ptr());

        // Test 6: Vulnerable - potential use after free
        potential_use_after_free();

        // Test 7: Safe FFI call
        safe_memory_management();

        // Test 8: Vulnerable - integer overflow
        potential_integer_overflow(0x7fffffff); // Large number that could overflow

        // Test 9: Safe FFI call
        safe_external_call();
    }
}

// Additional test: Rust-only function (no FFI)
fn rust_only_function() {
    println!("This is a pure Rust function, no FFI");
}

// Additional test: Rust function that will be called from C
#[no_mangle]
pub extern "C" fn c_calls_rust(input: *const i8) {
    unsafe {
        if !input.is_null() {
            let c_str = std::ffi::CStr::from_ptr(input);
            let r_str = c_str.to_str().unwrap_or("invalid");
            println!("C called Rust with: {}", r_str);
        }
    }
}
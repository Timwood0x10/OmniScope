//! Rust FFI Demo Library
//!
//! This demonstrates a common security pitfall:
//! - Rust code performs "sanitization" (removes semicolons)
//! - But the C library still has vulnerabilities
//! - OmniScope should detect this cross-language security issue

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// External C function declaration
/// This function is implemented in c_lib/dangerous.c
#[link(name = "dangerous")]
extern "C" {
    fn dangerous_process(input: *const c_char);
    fn dangerous_copy(dest: *mut c_char, src: *const c_char);
}

/// Process user input with "sanitization"
///
/// SECURITY FLAW: The sanitization is ineffective!
/// - We only remove semicolons
/// - But C code uses strcpy() and system()
/// - Attacker can use && or || to chain commands
///
/// This is the kind of bug OmniScope is designed to detect:
/// Rust thinks it's safe, C assumes input is validated.
pub fn process_input(input: &str) -> Result<(), String> {
    // "Sanitization" - removes semicolons
    // This is INEFFECTIVE! Attacker can use:
    //   ls && rm -rf /
    //   ls || cat /etc/passwd
    let sanitized: String = input.chars().filter(|&c| c != ';').collect();

    // Convert to C string
    let c_str = CString::new(sanitized.as_str())
        .map_err(|e| format!("Invalid string: {}", e))?;

    // Call into C - this is where the vulnerability is triggered
    // OmniScope should detect:
    // 1. User input flows from Rust to C
    // 2. C code calls system() with unsanitized input
    unsafe {
        dangerous_process(c_str.as_ptr());
    }

    Ok(())
}

/// Another vulnerability: buffer overflow
///
/// SECURITY FLAW:
/// - Rust allocates a fixed-size buffer
/// - C uses strcpy() without bounds checking
/// - Attacker can overflow the buffer
pub fn copy_data(input: &str) -> Result<(), String> {
    // Fixed-size buffer - VULNERABLE!
    let mut buffer = [0u8; 64];

    let c_str = CString::new(input)
        .map_err(|e| format!("Invalid string: {}", e))?;

    // C code will use strcpy() - no bounds checking!
    unsafe {
        dangerous_copy(buffer.as_mut_ptr() as *mut c_char, c_str.as_ptr());
    }

    println!("Copied: {}", String::from_utf8_lossy(&buffer));

    Ok(())
}

/// Demonstrate cross-language memory issue
///
/// SECURITY FLAW:
/// - Rust allocates memory
/// - C code might free it incorrectly
pub fn memory_transfer() -> Result<(), String> {
    // Allocate in Rust
    let data = CString::new("Rust allocated data").unwrap();

    // Pass to C - if C tries to free() this, it's UB!
    // (This example doesn't actually free it, but demonstrates the pattern)
    unsafe {
        dangerous_process(data.as_ptr());
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitization_removes_semicolons() {
        let input = "ls; rm -rf /";
        let sanitized: String = input.chars().filter(|&c| c != ';').collect();
        assert_eq!(sanitized, "ls rm -rf /");
    }

    #[test]
    fn test_sanitization_bypass() {
        // Attacker can bypass with && or ||
        let input = "ls && rm -rf /";
        let sanitized: String = input.chars().filter(|&c| c != ';').collect();
        // Still dangerous! Semicolon filter doesn't help
        assert!(sanitized.contains("&&"));
    }
}

/*
 * Rust FFI Simple Test
 * Tests real Rust→C FFI patterns for unsafe boundary analysis
 * 
 * Expected Issues: 4
 * - Box::into_raw without Box::from_raw (ownership leak)
 * - CString::into_raw without CString::from_raw (ownership leak)
 * - &str.as_ptr escape (borrow escape)
 * - Rust alloc, C free (cross-language mismatch)
 */

use std::ffi::{CString, CStr};
use std::os::raw::{c_char, c_int};

extern "C" {
    fn c_process_string(ptr: *mut c_char);
    fn c_free_string(ptr: *mut c_char);
}

// Test 1: Box::into_raw without Box::from_raw - ownership leak
#[no_mangle]
pub extern "C" fn box_into_raw_leak() -> *mut c_int {
    let boxed = Box::new(42);
    Box::into_raw(boxed) as *mut c_int  // Ownership transferred to C
    // Leak: C never calls Box::from_raw to reclaim
}

// Test 2: CString::into_raw without CString::from_raw - ownership leak
#[no_mangle]
pub extern "C" fn cstring_into_raw_leak() -> *mut c_char {
    let cstring = CString::new("hello").unwrap();
    CString::into_raw(cstring)  // Ownership transferred to C
    // Leak: C never calls CString::from_raw to reclaim
}

// Test 3: &str.as_ptr escape - borrow escape
#[no_mangle]
pub extern "C" fn str_as_ptr_escape() -> *const c_char {
    let s = String::from("hello");
    s.as_ptr()  // Borrow escapes - String dropped, pointer invalid
}

// Test 4: Rust alloc, C free - cross-language mismatch
#[no_mangle]
pub extern "C" fn rust_alloc_c_free() {
    let ptr = Box::into_raw(Box::new(42)) as *mut c_char;
    unsafe {
        c_free_string(ptr);  // C free on Rust alloc - MISMATCH!
    }
}

// Test 5: Correct pattern - Box::into_raw + Box::from_raw
#[no_mangle]
pub extern "C" fn correct_box_transfer(ptr: *mut c_int) {
    unsafe {
        let _boxed = Box::from_raw(ptr);  // Reclaim ownership
    }
}

// Test 6: Correct pattern - CString::into_raw + CString::from_raw
#[no_mangle]
pub extern "C" fn correct_cstring_transfer(ptr: *mut c_char) {
    unsafe {
        let _cstring = CString::from_raw(ptr);  // Reclaim ownership
    }
}

fn main() {
    // Test functions
    let _ = box_into_raw_leak();
    let _ = cstring_into_raw_leak();
    let _ = str_as_ptr_escape();
    rust_alloc_c_free();
}

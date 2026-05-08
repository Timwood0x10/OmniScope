// Cross-Language Free Violation Tests (Rust Side)
// 
// Tests Rust-specific FFI boundary violations:
// 1. Box::into_raw() + C free (classic bug)
// 2. CString::into_raw() + C free (string case)
// 3. Vec::as_ptr() misuse with C deallocation
// 4. Proper Rust→C ownership transfer (should NOT trigger)

use std::ffi::{CString, CStr};
use std::os::raw::c_int;

// Mock C function declarations
extern "C" {
    fn c_allocator(size: usize) -> *mut u8;  // C malloc
    fn c_deallocator(ptr: *mut u8);          // C free
    fn c_processor(ptr: *mut i32);           // C function that might free
}

// ============================================================================
// Case 1: Box::into_raw() → C free (CRITICAL BUG)
// ============================================================================
pub fn bug_box_into_raw_c_free() {
    let boxed = Box::new(42);
    let ptr = Box::into_raw(boxed);  // alloc_lang = .rust
    
    unsafe {
        // BUG: Passing Rust-allocated pointer to C's free
        c_deallocator(ptr);  // free_lang = .c  → SHOULD DETECT
    }
    
    // Expected: cross_language_free
}

// ============================================================================
// Case 2: CString::into_raw() → C free (CRITICAL BUG)
// ============================================================================
pub fn bug_cstring_into_raw_c_free() {
    let s = CString::new("hello").unwrap();
    let ptr = s.into_raw();  // alloc_lang = .rust
    
    unsafe {
        // BUG: C free on Rust CString
        c_deallocator(ptr as *mut u8);  // free_lang = .c  → SHOULD DETECT
    }
    
    // Expected: cross_language_free
}

// ============================================================================
// Case 3: Vec::as_ptr() misuse with C deallocation
// ============================================================================
pub fn bug_vec_as_ptr_c_free() {
    let v = vec![1, 2, 3, 4, 5];
    let ptr = v.as_ptr();  // alloc_lang = .rust (but v still owns)
    
    // BUG: Attempting to free borrowed pointer
    unsafe {
        c_deallocator(ptr as *mut u8);  // free_lang = .c
    }
    
    // Expected: cross_language_free + use_after_free (double violation)
}

// ============================================================================
// Case 4: Proper Rust→C ownership transfer (SHOULD NOT TRIGGER)
// ============================================================================
pub fn safe_rust_to_c_ownership() {
    let boxed = Box::new(100);
    let ptr = Box::into_raw(boxed);  // alloc_lang = .rust
    
    // SAFETY: C code takes ownership and will call from_raw later
    unsafe {
        c_processor(ptr);  // C code uses but doesn't free
        // Rust takes ownership back
        let _ = Box::from_raw(ptr);  // free_lang = .rust
    }
    
    // Expected: NO VIOLATION (proper ownership transfer)
}

// ============================================================================
// Case 5: C alloc → Rust Box::from_raw → Rust drop (CRITICAL BUG)
// ============================================================================
pub fn bug_c_alloc_rust_drop() {
    unsafe {
        let ptr = c_allocator(64) as *mut i32;  // alloc_lang = .c
        
        // BUG: Wrapping C memory in Rust Box
        let boxed = Box::from_raw(ptr);  // Takes ownership
        
        // When boxed is dropped, Rust will call its allocator!
    }  // free_lang = .rust  → SHOULD DETECT
    
    // Expected: cross_language_free
}

// ============================================================================
// Case 6: Repeated cross-language transfers
// ============================================================================
pub fn bug_repeated_cross_lang() {
    let ptr1 = Box::into_raw(Box::new(1));  // alloc_lang = .rust
    
    unsafe {
        c_deallocator(ptr1);  // free_lang = .c  → SHOULD DETECT
    }
    
    let ptr2 = Box::into_raw(Box::new(2));  // Another Rust allocation
    
    unsafe {
        c_deallocator(ptr2);  // Another violation  → SHOULD DETECT
    }
    
    // Expected: TWO cross_language_free reports
}

// ============================================================================
// Case 7: Nested structures with cross-lang pointers
// ============================================================================
pub struct NestedContainer {
    data: *mut i32,
    metadata: i32,
}

pub fn bug_nested_struct_cross_lang() {
    let inner = Box::new(42);
    let inner_ptr = Box::into_raw(inner);  // alloc_lang = .rust
    
    let container = NestedContainer {
        data: inner_ptr,
        metadata: 100,
    };
    
    // BUG: Freeing nested pointer via C
    unsafe {
        c_deallocator(container.data as *mut u8);  // free_lang = .c  → SHOULD DETECT
    }
    
    // Expected: cross_language_free on inner_ptr
}

// ============================================================================
// Case 8: Array slice passed to C
// ============================================================================
pub fn bug_array_slice_c_free() {
    let arr: [i32; 10] = [0; 10];
    let ptr = arr.as_ptr();  // Stack-allocated array!
    
    // BUG: Freeing stack pointer via C
    unsafe {
        c_deallocator(ptr as *mut u8);  // Invalid free (not cross-language)
    }
    
    // Expected: invalid_free (stack), NOT cross_language_free
}

// ============================================================================
// Case 9: Proper C→Rust→C chain
// ============================================================================
pub fn safe_c_rust_c_chain() {
    unsafe {
        let ptr = c_allocator(128);  // alloc_lang = .c
        
        // Rust uses the memory (doesn't take ownership)
        let slice = std::slice::from_raw_parts_mut(ptr as *mut u8, 128);
        slice[0] = 42;
        
        // C deallocates
        c_deallocator(ptr);  // free_lang = .c
        
        // Expected: NO VIOLATION (proper C lifecycle)
    }
}

// ============================================================================
// Case 10: Double free with cross-language
// ============================================================================
pub fn bug_double_free_cross_lang() {
    let ptr = Box::into_raw(Box::new(999));  // alloc_lang = .rust
    
    unsafe {
        c_deallocator(ptr);  // free_lang = .c  → First free (cross-lang)
        c_deallocator(ptr);  // free_lang = .c  → Second free (double-free)
    }
    
    // Expected: cross_language_free + double_free
}

// ============================================================================
// Main test runner
// ============================================================================
fn main() {
    println!("Cross-Language Free Tests (Rust)");
    println!("=================================\n");
    
    println!("Test 1: Box::into_raw → C free");
    bug_box_into_raw_c_free();
    
    println!("\nTest 2: CString::into_raw → C free");
    bug_cstring_into_raw_c_free();
    
    println!("\nTest 3: Vec::as_ptr misuse");
    bug_vec_as_ptr_c_free();
    
    println!("\nTest 4: Safe Rust→C ownership");
    safe_rust_to_c_ownership();
    
    println!("\nTest 5: C alloc → Rust drop");
    bug_c_alloc_rust_drop();
    
    println!("\nTest 6: Repeated cross-lang");
    bug_repeated_cross_lang();
    
    println!("\nTest 7: Nested struct");
    bug_nested_struct_cross_lang();
    
    println!("\nTest 8: Array slice");
    bug_array_slice_c_free();
    
    println!("\nTest 9: C→Rust→C chain");
    safe_c_rust_c_chain();
    
    println!("\nTest 10: Double free cross-lang");
    bug_double_free_cross_lang();
    
    println!("\n=================================");
    println!("Tests completed");
}

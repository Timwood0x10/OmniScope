use std::os::raw::c_int;

extern "C" {
    fn c_take_ownership(ptr: *mut c_int);
    fn c_return_ownership(ptr: *mut c_int);
    fn c_store_borrowed(ptr: *mut c_int);
}

/// BUG: Transfers ownership to C, but C frees it incorrectly.
pub fn bug_rust_box_c_free() {
    let boxed = Box::new(42_i32);
    let ptr = Box::into_raw(boxed);
    unsafe {
        c_take_ownership(ptr);
    }
}

/// CORRECT: Transfers ownership to C, C returns it.
pub fn correct_ownership_transfer() {
    let boxed = Box::new(42_i32);
    let ptr = Box::into_raw(boxed);
    unsafe {
        c_return_ownership(ptr);
        let _ = Box::from_raw(ptr);
    }
}

/// BUG: Borrows pointer to C, C stores it globally.
pub fn bug_borrow_escape() {
    let s = Box::new(100_i32);
    let ptr = &*s as *const i32 as *mut i32;
    unsafe {
        c_store_borrowed(ptr);
    }
}

/// BUG: Double free across FFI.
pub fn bug_double_free() {
    let boxed = Box::new(42_i32);
    let ptr = Box::into_raw(boxed);
    unsafe {
        c_take_ownership(ptr);
        let _ = Box::from_raw(ptr);
    }
}

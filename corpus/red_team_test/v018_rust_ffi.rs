// OmniScope v0.1.8 — Rust FFI Red Team Test
// Intentional Rust cross-language FFI vulnerabilities
//
// Bugs: 8 | Controls: 2
// Requires: #![feature(ffi_unwind)] if using catch_unwind across FFI

#![allow(unused)]
#![allow(deref_nullptr)]

use std::sync::{Arc, Mutex};
use std::mem;
use std::ptr;

extern "C" {
    fn c_free(p: *mut std::ffi::c_void);
    fn c_take_ptr(p: *mut std::ffi::c_void);
    fn c_register_callback(cb: Option<unsafe extern "C" fn(*mut std::ffi::c_void)>, ctx: *mut std::ffi::c_void);
    fn c_malloc(n: usize) -> *mut std::ffi::c_void;
    fn c_process_buffer(buf: *mut u8, len: usize);
}

// BUG-RS-01: Box::into_raw freed by C free — cross-lang free mismatch
fn bug_rs_01_box_into_raw_to_c_free() {
    let b = Box::new(42u64);
    let raw = Box::into_raw(b);
    unsafe { c_free(raw as *mut std::ffi::c_void); }  // Rust alloc → C free
}

// BUG-RS-02: CString::into_raw never freed
fn bug_rs_02_cstring_into_raw_leak() {
    let s = std::ffi::CString::new("hello").unwrap();
    let raw = s.into_raw();  // Ownership transferred to caller
    unsafe { c_take_ptr(raw as *mut std::ffi::c_void); }
    // Never freed with CString::from_raw + drop
}

// BUG-RS-03: Arc pointer passed to C without lifetime guarantee
fn bug_rs_03_arc_to_c_escape() {
    let data = Arc::new(42u64);
    let raw = Arc::into_raw(data) as *mut std::ffi::c_void;
    unsafe { c_register_callback(None, raw); }
    // Arc dropped after scope, callback holds dangling pointer
}

// BUG-RS-04: Mutex guard pointer escapes to C
fn bug_rs_04_mutex_guard_to_c() {
    let mtx = Arc::new(Mutex::new(42u64));
    let guard = mtx.lock().unwrap();
    let ptr = &*guard as *const u64 as *mut std::ffi::c_void;
    unsafe { c_take_ptr(ptr); }
    // After guard drop, pointer dangles
}

// BUG-RS-05: Stack reference escapes to C FFI
fn bug_rs_05_stack_ref_to_c() {
    let val: u64 = 42;
    let ptr = &val as *const u64 as *mut std::ffi::c_void;
    unsafe { c_take_ptr(ptr); }  // Stack address escapes to C
}

// BUG-RS-06: Vec::as_mut_ptr passed to C, lifetime ambiguous
fn bug_rs_06_vec_ptr_to_c() {
    let mut v = vec![1u8, 2, 3, 4];
    let ptr = v.as_mut_ptr();
    unsafe { c_process_buffer(ptr, v.len()); }
    // C may hold ref past v's lifetime
}

// BUG-RS-07: ManuallyDrop + C free — ownership confusion
fn bug_rs_07_manually_drop_to_c_free() {
    let b = Box::new(42u64);
    let raw = Box::into_raw(b);
    unsafe {
        let _md = mem::ManuallyDrop::new(Box::from_raw(raw));
        c_free(raw as *mut std::ffi::c_void);
    }
    // ManuallyDrop prevents Rust drop, C free frees it
}

// BUG-RS-08: String::as_ptr passed to C, string dropped
fn bug_rs_08_string_as_ptr_to_c() {
    let s = String::from("secret_data");
    let ptr = s.as_ptr() as *mut std::ffi::c_void;
    drop(s);  // String freed, pointer dangles
    unsafe { c_take_ptr(ptr); }  // UAF
}

// CONTROL-01: Correct Box::into_raw + Box::from_raw
fn control_01_box_into_raw_from_raw() {
    let b = Box::new(42u64);
    let raw = Box::into_raw(b);
    unsafe {
        let _b2 = Box::from_raw(raw);  // Correct: returned to Rust ownership
    }
}

// CONTROL-02: Correct Arc with proper scope
fn control_02_arc_proper_scope() {
    let data = Arc::new(42u64);
    let ptr = Arc::as_ptr(&data) as *mut std::ffi::c_void;
    unsafe { c_take_ptr(ptr); }
    // Arc drop at scope end is correct
}

fn main() {
    bug_rs_01_box_into_raw_to_c_free();
    bug_rs_02_cstring_into_raw_leak();
    bug_rs_03_arc_to_c_escape();
    bug_rs_04_mutex_guard_to_c();
    bug_rs_05_stack_ref_to_c();
    bug_rs_06_vec_ptr_to_c();
    bug_rs_07_manually_drop_to_c_free();
    bug_rs_08_string_as_ptr_to_c();
    control_01_box_into_raw_from_raw();
    control_02_arc_proper_scope();
}

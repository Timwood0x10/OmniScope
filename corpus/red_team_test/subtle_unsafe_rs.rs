//! OmniScope Red Team v2 — Subtle Rust Unsafe/FFI Bug Test Cases

#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_unsafe)]
#![allow(unused_assignments)]

use std::ffi::{c_void, CString, CStr};
use std::ptr::{self, null, null_mut};
use std::mem;
use std::slice;

extern "C" {
    fn c_process_data(buf: *mut u8, len: i32) -> i32;
    fn c_register_callback(cb: extern "C" fn(*mut c_void), ctx: *mut c_void);
    fn c_store_pointer(p: *const u8);
    fn c_retrieve_pointer() -> *mut u8;
    fn malloc(size: usize) -> *mut c_void;
    fn free(p: *mut c_void);
}

// ================================================================
// SUBTLE-RS-01: transmute to extend lifetime behind safe facade
// ================================================================

struct SecretData { data: Vec<u8> }

impl SecretData {
    pub fn as_static_str(&self) -> &'static str {
        let s: String = String::from_utf8(self.data.clone()).unwrap_or_default();
        let leaked: &'static str = unsafe {
            mem::transmute::<&str, &'static str>(s.as_str())
        };
        leaked
    }
}

fn subtle_rs_01_lifetime_extension() -> &'static str {
    let secret = SecretData { data: b"password123".to_vec() };
    let leaked = secret.as_static_str();
    drop(secret);
    leaked
}

// ================================================================
// SUBTLE-RS-02: Raw pointer arithmetic crosses allocation boundary
// ================================================================

fn subtle_rs_02_oob_via_raw_arithmetic(count: usize) {
    let mut buf = vec![0u32; count];
    if count > 0 {
        let base = buf.as_ptr() as *mut u8;
        unsafe {
            let start = base.add(4);
            for i in 0..count {
                ptr::write(start.add(i * 4), 0xAB_u8);
                ptr::write(start.add(i * 4 + 1), 0xCD_u8);
                ptr::write(start.add(i * 4 + 2), 0xEF_u8);
                ptr::write(start.add(i * 4 + 3), 0xBA_u8);
            }
        }
    }
}

// ================================================================
// SUBTLE-RS-03: Unaligned pointer dereference via cast
// ================================================================

#[repr(C, packed(1))]
struct PackedHeader { flags: u8, offset: u32, length: u16 }

fn subtle_rs_03_unaligned_cast(raw: *const u8) -> u32 {
    unsafe {
        let p = raw as *const u32;
        ptr::read(p)
    }
}

fn subtle_rs_03_trigger() {
    let header = PackedHeader { flags: 0x01, offset: 0xDEADBEEF, length: 100 };
    let raw = &header as *const PackedHeader as *const u8;
    unsafe {
        let val = subtle_rs_03_unaligned_cast(raw.add(1));
        println!("read unaligned: {:#X}", val);
    }
}

// ================================================================
// SUBTLE-RS-04: Sending owned Box across FFI, double-free risk
// ================================================================

static mut GLOBAL_C_PTR: *mut c_void = null_mut();

fn subtle_rs_04_send_box_to_c(data: Box<[u8]>) {
    let raw = Box::into_raw(data) as *mut c_void;
    unsafe {
        GLOBAL_C_PTR = raw;
        c_store_pointer(raw as *const u8);
    }
}

fn subtle_rs_04_double_free() {
    unsafe {
        if !GLOBAL_C_PTR.is_null() {
            free(GLOBAL_C_PTR);
            GLOBAL_C_PTR = null_mut();
        }
    }
}

// ================================================================
// SUBTLE-RS-05: Creating mutable alias to shared reference
// ================================================================

struct SharedCounter { value: std::cell::Cell<i32> }

impl SharedCounter {
    fn subtle_alias(&self) -> *mut i32 {
        unsafe {
            let raw = self as *const Self as *mut Self;
            let cell_ptr = &(*raw).value as *const std::cell::Cell<i32> as *mut std::cell::Cell<i32>;
            (*cell_ptr).as_ptr()
        }
    }

    fn correct_way(&self) -> i32 {
        self.value.get()
    }
}

fn subtle_rs_05_mutable_alias() {
    let counter = SharedCounter { value: std::cell::Cell::new(0) };
    let _shared_ref = &counter;
    let aliased = counter.subtle_alias();
    unsafe { *aliased = 42; }
}

// ================================================================
// SUBTLE-RS-06: CString::into_raw sent to C, then used after C frees it
// ================================================================

extern "C" {
    fn c_take_string_ownership(s: *const i8);
    fn c_do_work();
    fn c_get_stored_string() -> *const i8;
}

fn subtle_rs_06_cstring_use_after_free() {
    let cs = CString::new("important_secret_data").unwrap();
    let ptr = cs.into_raw();

    unsafe {
        c_take_string_ownership(ptr);
        c_do_work();
        let retrieved = c_get_stored_string();
        if !retrieved.is_null() {
            let s = CStr::from_ptr(retrieved);
            println!("got: {:?}", s);
        }
    }
}

// ================================================================
// SUBTLE-RS-07: Slice from raw parts with wrong length
// ================================================================

unsafe fn subtle_rs_07_slice_length_mismatch(ptr: *const u8, reported_len: usize) -> &'static [u8] {
    slice::from_raw_parts(ptr, reported_len)
}

fn subtle_rs_07_trigger() {
    let small_alloc = vec![0xABu8; 16];
    unsafe {
        let oversliced = subtle_rs_07_slice_length_mismatch(small_alloc.as_ptr(), 1024);
        for i in 0..oversliced.len().min(100) {
            print!("{:02X} ", oversliced[i]);
        }
    }
    println!();
}

// ================================================================
// SUBTLE-RS-08: Callback closure captures raw pointer that outlives
// ================================================================

struct CallbackCtx { user_data: *mut u8, len: usize }

extern "C" fn subtle_rs_08_cb_wrapper(ctx: *mut c_void) {
    let cb_ctx = ctx as *mut CallbackCtx;
    unsafe {
        if !(*cb_ctx).user_data.is_null() {
            ptr::write((*cb_ctx).user_data, 0xFF);
        }
    }
}

fn subtle_rs_08_dangling_closure() {
    let data = vec![0x42u8; 256];
    let mut ctx = CallbackCtx {
        user_data: data.as_ptr() as *mut u8,
        len: data.len(),
    };

    unsafe {
        c_register_callback(subtle_rs_08_cb_wrapper, &mut ctx as *mut _ as *mut c_void);
    }
    drop(data);

    unsafe {
        let mut fake_ctx = CallbackCtx { user_data: 1 as *mut u8, len: 256 };
        subtle_rs_08_cb_wrapper(&mut fake_ctx as *mut _ as *mut c_void);
    }
}

// ================================================================
// SUBTLE-RS-09: Mutex deadlock via unsafe re-entry
// ================================================================

use std::sync::Mutex;

static GLOBAL_MUTEX: Mutex<()> = Mutex::new(());

fn subtle_rs_09_deadlock_in_lock(callback: extern "C" fn()) {
    let _guard = GLOBAL_MUTEX.lock().unwrap();
    unsafe { callback(); }
}

extern "C" fn dummy_callback() {}

// ================================================================
// SUBTLE-RS-10: Exposing &self from &mut self method through raw ptr
// ================================================================

struct StateMachine { state: i32 }

impl StateMachine {
    unsafe fn expose_from_mut(&self) -> *const StateMachine {
        self as *const StateMachine
    }

    fn register_self_handler(&mut self) {
        unsafe {
            let self_ptr = self.expose_from_mut();
            c_store_pointer(self_ptr as *const u8);
        }
    }
}

fn subtle_rs_10_expose_mut_as_shared() {
    let mut sm = StateMachine { state: 0 };
    sm.register_self_handler();
    sm.state = 42;
}

// ================================================================
// main
// ================================================================

#[no_mangle]
pub extern "C" fn main_redteam_rust() {
    println!("=== Subtle Red Team v2 - Rust Unsafe/FFI ===");

    let dangling = subtle_rs_01_lifetime_extension();
    println!("RS-01 dangling ref: {}", if dangling.len() > 0 { "non-empty" } else { "empty" });

    subtle_rs_02_oob_via_raw_arithmetic(64);
    subtle_rs_03_trigger();

    let boxed: Box<[u8]> = Box::new([1, 2, 3, 4]);
    subtle_rs_04_send_box_to_c(boxed);
    subtle_rs_04_double_free();

    subtle_rs_05_mutable_alias();
    subtle_rs_06_cstring_use_after_free();
    subtle_rs_07_trigger();
    subtle_rs_08_dangling_closure();
    subtle_rs_09_deadlock_in_lock(dummy_callback);
    subtle_rs_10_expose_mut_as_shared();

    println!("=== All subtle Rust tests executed ===");
}

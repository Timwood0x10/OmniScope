//! OmniScope Red Team v3 — Pure Unsafe+FFI Boundary Bug Test Cases (Rust)
//!
//! Rule: ≥95% bugs are at unsafe + extern "C" FFI boundary
//! Every bug involves either:
//!   - An `extern "C" fn` declaration (calling into C)
//!   - A `#[no_mangle] pub extern "C" fn` (C calling into us)
//!   - An `unsafe` block that interacts with FFI data
//!   - Ownership/lifetime crossing the FFI boundary

#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_unsafe)]
#![allow(unused_assignments)]

use std::ffi::{c_void, CString, CStr};
use std::ptr::{self, null, null_mut};
use std::mem;
use std::slice;

// ================================================================
// FFI declarations — these are C functions we call
// ================================================================

extern "C" {
    fn c_ffi_alloc(size: usize) -> *mut c_void;
    fn c_ffi_free(ptr: *mut c_void);
    fn c_ffi_register_callback(cb: extern "C" fn(*mut c_void, i32), ctx: *mut c_void);
    fn c_ffi_trigger_callback();
    fn c_ffi_store_pointer(p: *const u8);
    fn c_ffi_retrieve_pointer() -> *mut u8;
    fn c_ffi_get_size_hint() -> usize;
    fn c_ffi_process_buffer(buf: *mut u8, len: i32) -> i32;
    fn c_ffi_init_context(out_ctx: *mut *mut c_void) -> i32;
    fn c_ffi_write_data(ctx: *mut c_void, data: *const u8, len: usize) -> i32;
    fn c_ffi_take_ownership(ptr: *mut c_void);
    fn c_ffi_borrow_resource(id: i32) -> *const u8;
    fn c_ffi_get_string() -> *const i8;
    fn c_ffi_do_work_with_callback(cb: extern "C" fn(*mut c_void, i32), ud: *mut c_void);
}

// ================================================================
// RS-FFI-01: Box::into_raw → double-free across FFI boundary
//
// We Box::into_raw() and pass to C via c_ffi_take_ownership.
// C now owns it. But we ALSO free it ourselves later.
// Double-free: C's cleanup + our free().
// ================================================================

static mut RS01_GLOBAL_PTR: *mut c_void = null_mut();

fn rs_ffi_01_double_free_box() {
    let data: Box<[u8]> = Box::new([1, 2, 3, 4, 5, 6, 7, 8]);
    let raw = Box::into_raw(data) as *mut c_void;

    unsafe {
        RS01_GLOBAL_PTR = raw;
        c_ffi_take_ownership(raw);  /* C claims ownership */
        /* ... later ... */
        if !RS01_GLOBAL_PTR.is_null() {
            libc::free(RS01_GLOBAL_PTR);  /* BUG: double-free! C also frees it */
            RS01_GLOBAL_PTR = null_mut();
        }
    }
}

// ================================================================
// RS-FFI-02: CString::into_raw → C uses → C frees → Rust reads stale
//
// Classic pattern: into_raw transfers ownership to C.
// C stores and eventually frees it. Rust side still has the raw ptr
// and tries to use it after C freed it.
// ================================================================

extern "C" {
    fn c_ffi_take_string(s: *const i8);
    fn c_ffi_do_string_work();
    fn c_ffi_get_stored_string() -> *const i8;
}

fn rs_ffi_02_cstring_uaf_across_ffi() {
    let cs = CString::new("sensitive_password_data").unwrap();
    let raw = cs.into_raw();

    unsafe {
        c_ffi_take_string(raw);      /* C owns raw now */
        c_ffi_do_string_work();       /* C might free raw here */

        let retrieved = c_ffi_get_stored_string();  /* Might be same memory, already freed */
        if !retrieved.is_null() {
            let s = CStr::from_ptr(retrieved);     /* BUG: UAF if C freed it */
            println!("got: {:?}", s);
        }
    }
}

// ================================================================
// RS-FFI-03: &str → *const u8 to C, C stores globally, Rust drops original
//
// Convert &str to *const u8, pass to C for storage.
// The &str's backing buffer is owned by Rust. When the String/str
// is dropped, C's stored pointer becomes dangling.
// This is the borrowed-pointer-escapes-across-FFI pattern.
// ================================================================

static mut RS03_CACHED_PTR: *const u8 = null();

fn rs_ffi_03_borrowed_str_escapes_to_c(input: &str) {
    unsafe {
        let bytes = input.as_ptr();
        RS03_CACHED_PTR = bytes;          /* Store pointer from &str */
        c_ffi_store_pointer(bytes);        /* Tell C about it too */
    }
    // 'input' dies here, its backing memory may be reused
}

fn rs_ffi_03_use_dangling_later() {
    unsafe {
        if !RS03_CACHED_PTR.is_null() {
            let byte = *RS03_CACHED_PTR;  /* UAF: original &str may be dropped */
            println!("dangling byte: {}", byte);
        }
    }
}

// ================================================================
// RS-FFI-04: Vec::as_ptr() captured in callback ctx, Vec dropped before fire
//
// Create Vec, take as_ptr(), put into callback context struct,
// register with C. Drop the Vec. When C fires callback later,
// the as_ptr() is dangling.
// ================================================================

struct RsCallbackCtx { data_ptr: *const u8, len: usize }

extern "C" fn rs_ffi_04_cb_handler(ctx: *mut c_void, _event: i32) {
    unsafe {
        let cb_ctx = &*(ctx as *const RsCallbackCtx);
        if !cb_ctx.data_ptr.is_null() && cb_ctx.len > 0 {
            ptr::write(cb_ctx.data_ptr as *mut u8, 0xFF);  /* Write through dangling ptr */
        }
    }
}

fn rs_ffi_04_vec_dropped_before_callback() {
    let data = vec![0x42u8; 256];
    let mut ctx = RsCallbackCtx {
        data_ptr: data.as_ptr(),
        len: data.len(),
    };

    unsafe {
        c_ffi_register_callback(rs_ffi_04_cb_handler, &mut ctx as *mut _ as *mut c_void);
    }
    drop(data);  /* Frees the Vec, but ctx.data_ptr still points into it */

    unsafe {
        c_ffi_trigger_callback();  /* Callback fires → writes to freed memory */
    }
}

// ================================================================
// RS-FFI-05: Untrusted size from FFI used for slice::from_raw_parts
//
// c_ffi_get_size_hint() returns untrusted size from C.
// We use it as length for slice::from_raw_parts on a small allocation.
// If size > actual allocation → OOB when accessing slice.
// ================================================================

unsafe fn rs_ffi_05_oversliced_from_ffi(ptr: *const u8) -> &'static [u8] {
    let reported_len = unsafe { c_ffi_get_size_hint() };  /* Untrusted! */
    slice::from_raw_parts(ptr, reported_len)  /* BUG: may way overstate actual valid region */
}

fn rs_ffi_05_trigger_overslice() {
    let small = vec![0xABu8; 16];
    unsafe {
        let oversliced = rs_ffi_05_oversliced_from_ffi(small.as_ptr());
        for i in 0..oversliced.len().min(50) {
            print!("{:02X} ", oversliced[i]);  /* OOB read past index 15 */
        }
    }
    println!();
}

// ================================================================
// RS-FFI-06: transmute extending lifetime of FFI-received pointer
//
// C returns a *const u8 that's valid only during this call.
// We transmute the resulting slice to 'static so it outlives
// the call. After return, C may reclaim the memory.
// ================================================================

fn rs_ffi_06_transmute_ffi_ptr_to_static() -> &'static [u8] {
    let ptr = unsafe { c_ffi_borrow_resource(0) };  /* Valid only during this call */
    let len = 64;
    unsafe {
        let slice = slice::from_raw_parts(ptr, len);  /* Temporary borrow from FFI */
        /* BUG: extends lifetime beyond FFI contract */
        type StaticSlice = &'static [u8];
        mem::transmute::<&[u8], StaticSlice>(slice)
    }
}

fn rs_ffi_06_use_after_ffi_invalidates() {
    let leaked = rs_ffi_06_transmute_ffi_ptr_to_static();
    /* Between here and usage, C might call c_ffi_borrow_resource again,
     * invalidating the previous pointer */
    let _second_call = unsafe { c_ffi_borrow_resource(1) };  /* May invalidate first ptr */
    unsafe { libc::free(_second_call as *mut c_void) };

    if !leaked.is_empty() {
        println!("leaked[0] = {:02X}", leaked[0]);  /* UAF if C reclaimed */
    }
}

// ================================================================
// RS-FFI-07: &self → raw ptr → sent to C via FFI, then self mutated concurrently
//
// Method takes &self, extracts raw *const Self, sends to C via
// c_ffi_store_pointer. Meanwhile caller continues to use &mut self.
// If C writes through the stored pointer → data race / aliasing violation.
// ================================================================

struct RsState { value: std::cell::Cell<i32> }

impl RsState {
    unsafe fn expose_to_ffi(&self) -> *const RsState {
        self as *const Self
    }

    fn register_self_with_ffi(&mut self) {
        unsafe {
            let self_ptr = self.expose_to_ffi() as *const u8;
            c_ffi_store_pointer(self_ptr);  /* C gets *const to our state */
        }
        /* Now both we (via &mut self) AND C (via stored pointer) can access */
        self.value.set(42);  /* Normal mutation */
        /* C could simultaneously write → data race */
    }
}

fn rs_ffi_07_expose_mut_via_ffi() {
    let mut st = RsState { value: std::cell::Cell::new(0) };
    st.register_self_with_ffi();
}

// ================================================================
// RS-FFI-08: FFI init returns error but output pointer used anyway
//
// c_ffi_init_context returns error code + fills *out_ctx.
// On error, *out_ctx may be NULL or garbage. We don't check
// return code before using the context.
// ================================================================

fn rs_ffi_08_null_ctx_from_failed_init() {
    unsafe {
        let mut ctx: *mut c_void = null_mut();
        let ret = c_ffi_init_context(&mut ctx);  /* ret=-1 on failure */

        /* BUG: not checking ret before using ctx */
        let data = b"hello";
        c_ffi_write_data(ctx, data.as_ptr(), data.len());  /* Potential NULL deref */
    }
}

// ================================================================
// RS-FFI-09: FFI provides *const, we cast to *mut and modify (contract violation)
//
// C lends us a *const pointer (read-only). We cast away const
// and write through it. C doesn't expect modification.
// ================================================================

fn rs_ffi_09_cast_away_const_from_ffi() {
    let ptr = unsafe { c_ffi_borrow_resource(5) };  /* Read-only borrowed from C */
    unsafe {
        let writable = ptr as *mut u8;  /* BUG: casting away const at FFI boundary */
        if !writable.is_null() {
            ptr::write(writable, 0xDE);  /* Violating C's read-only contract */
            ptr::write(writable.add(1), 0xAD);
        }
    }
}

// ================================================================
// RS-FFI-10: Reentrant FFI — C calls our callback while we hold &mut self
//
// We call c_ffi_do_work_with_callback which calls our callback
// synchronously. Our callback receives user_data that aliases
// with a &mut we're holding. Data race within same thread.
// ================================================================

static mut RS10_VERSION: i32 = 0;

extern "C" fn rs_ffi_10_reentrant_cb(ud: *mut c_void, _ev: i32) {
    unsafe {
        let ver = &*(ud as *const i32);
        /* C (via do_work) incremented RS10_VERSION before calling us.
         * *ver was snapshotted before the call → stale */
        if *ver != RS10_VERSION {
            println!("stale version {} vs current {}", *ver, RS10_VERSION);
            /* BUG: using stale snapshot despite detecting mismatch */
        }
    }
}

fn rs_ffi_10_reentrant_state_bug() {
    unsafe {
        let mut snapshot = RS10_VERSION;
        c_ffi_do_work_with_callback(rs_ffi_10_reentrant_cb, &mut snapshot as *mut _ as *mut c_void);
        /* do_work increments RS10_VERSION, then calls our cb with &snapshot */
    }
}

// ================================================================
// RS-FFI-11: Sending &local_var pointer to C via FFI
//
// Take address of local variable, pass to C for storage.
// Function returns, stack frame gone. C's stored pointer dangles.
// ================================================================

fn rs_ffi_11_stack_ref_to_c() {
    let local_value: i32 = 0xDEAD;
    unsafe {
        c_ffi_store_pointer(&local_value as *const i32 as *const u8);  /* Stack addr to C! */
    }
    /* local_value dies here. C's stored pointer is dangling. */
}

// ================================================================
// RS-FFI-12: FFI returns NULL, we don't check in unsafe block
//
// c_ffi_retrieve_pointer() can return NULL (e.g., resource not found).
// We dereference without null check in an unsafe block.
// ================================================================

fn rs_ffi_12_null_deref_from_ffi() {
    unsafe {
        let ptr = c_ffi_retrieve_pointer();  /* Could be NULL */
        let val = *ptr;  /* BUG: NULL dereference if resource not found */
        println!("retrieved: {}", val);
    }
}

// ================================================================
// RS-FFI-13: Multiple FFI calls — second invalidates first's result
//
// Call c_ffi_get_string() twice. First result invalidated by second.
// Use first result after second call → stale/dangling.
// ================================================================

fn rs_ffi_13_stale_between_ffi_calls() -> *const i8 {
    unsafe {
        let s1 = c_ffi_get_string();  /* Valid now */
        let _s2 = c_ffi_get_string();  /* May invalidate s1's backing store */
        s1  /* BUG: returning potentially-invalidated pointer */
    }
}

fn rs_ffi_13_use_stale() {
    let ptr = rs_ffi_13_stale_between_ffi_calls();
    unsafe {
        if !ptr.is_null() {
            let s = CStr::from_ptr(ptr);  /* May read freed/reused memory */
            println!("stale: {:?}", s);
        }
    }
}

// ================================================================
// RS-FFI-14: Raw pointer from FFI used to create reference, then FFI frees it
//
// Get raw pointer from FFI, construct &T reference from it.
// Later FFI frees the underlying memory. Reference is now dangling.
// This is especially dangerous because Rust's type system thinks
// the reference is valid (no unsafe in the use site).
// ================================================================

struct ForeignResource { id: i32 }

static mut RS14_FOREIGN_PTR: *mut ForeignResource = null_mut();

fn rs_ffi_14_ref_from_ffi_raw() -> Option<&'static ForeignResource> {
    unsafe {
        let raw = c_ffi_borrow_resource(10) as *const ForeignResource;
        RS14_FOREIGN_PTR = raw as *mut ForeignResource;
        Some(&*raw)  /* Create & reference from FFI raw ptr */
    }
}

fn rs_ffi_14_use_then_ffi_frees() {
    let ref_ = rs_ffi_14_ref_from_ffi_raw().unwrap();
    println!("resource id: {}", ref_.id);  /* OK for now */

    unsafe {
        c_ffi_take_ffi_resource(10);  /* Hypothetical: C reclaims resource 10 */
        /* Now RS14_FOREIGN_PTR and ref_ are dangling */
    }

    println!("resource id again: {}", unsafe { (*RS14_FOREIGN_PTR).id });  /* UAF! */
}

extern "C" {
    fn c_ffi_take_ffi_resource(id: i32);
}

// ================================================================
// RS-FFI-15: FFI callback registered, then context manually freed, then callback fires
//
// Similar to RS-FFI-04 but explicit manual free between registration
// and callback invocation. Demonstrates ordering bug at FFI boundary.
// ================================================================

struct HeapCtx { name: CString, value: i32 }

extern "C" fn rs_ffi_15_cb(ctx: *mut c_void, _ev: i32) {
    unsafe {
        let hc = &*(ctx as *const HeapCtx);
        println!("callback: name={} value={}", hc.name.to_str().unwrap_or("?"), hc.value);
    }
}

fn rs_ffi_15_free_before_fire() {
    let ctx = Box::new(HeapCtx {
        name: CString::new("leaky_ctx").unwrap(),
        value: 99,
    });

    unsafe {
        c_ffi_register_callback(rs_ffi_15_cb, Box::into_raw(ctx) as *mut c_void);
    }
    // ctx is moved (into_raw), but we didn't save the raw ptr to prevent double-free issue
    // Actually into_raw consumed the Box, so C owns it now.

    // Simulate: something else frees the memory C is holding
    unsafe {
        let fake_free = c_ffi_retrieve_pointer();
        if !fake_free.is_null() {
            libc::free(fake_free as *mut c_void);  /* Free what C was holding */
        }
    }

    unsafe { c_ffi_trigger_callback(); }  /* UAF: callback uses freed context */
}

// ================================================================
// RS-FFI-16: Static mut accessed from FFI callback without synchronization
//
// FFI callback writes to static mut. Main thread also writes.
// No synchronization → data race.
// ================================================================

static mut RS16_SHARED_COUNTER: i32 = 0;

extern "C" fn rs_ffi_16_racey_cb(_ud: *mut c_void, val: i32) {
    unsafe {
        RS16_SHARED_COUNTER += val;  /* Unsynchronized write from FFI callback */
    }
}

fn rs_ffi_16_static_mut_race() {
    unsafe {
        c_ffi_register_callback(rs_ffi_16_racey_cb, null_mut());
        RS16_SHARED_COUNTER = 100;  /* Race: main thread writes, callback might fire */
        c_ffi_trigger_callback();  /* Callback writes to same static mut */
        println!("counter: {}", RS16_SHARED_COUNTER);  /* Indeterminate value */
    }
}

// ================================================================
// RS-FFI-17: FFI process_buffer — returned count exceeds our buffer size
//
// We give c_ffi_process_buffer a buffer of N bytes. It returns
// bytes_written which could be > N (FFI bug or contract violation).
// We trust the count and read past our buffer.
// ================================================================

fn rs_ffi_17_ffi_oob_write() {
    let mut buf = [0u8; 32];
    unsafe {
        let written = c_ffi_process_buffer(buf.as_mut_ptr(), 2048);  /* Claim 2048, only have 32! */
        /* BUG: FFI might have written up to 2048 bytes into 32-byte stack buffer */
        if written > 0 {
            let display_len = (written as usize).min(buf.len());
            println!("written={}, data={:?}", written, &buf[..display_len]);
        }
    }
}

// ================================================================
// RS-FFI-18: FFI allocator mismatch — malloc on Rust side, ffi_free on C side
//
// We allocate with Rust's global alloc (or Box::new). Pass to C.
// C frees with c_ffi_free which might use a different allocator.
// Or vice versa: C allocates with c_ffi_alloc, we free with Box::from_raw+drop.
// ================================================================

fn rs_ffi_18_allocator_mismatch_rust_alloc_c_free() {
    let data = Box::new([0u8; 1024]);
    let raw = Box::into_raw(data) as *mut c_void;

    unsafe {
        c_ffi_take_ownership(raw);  /* C will try to free with its own allocator */
        /* If C's free != Rust's global_alloc's free → crash or corruption */
        /* Also: we lost ownership, can't properly clean up */
    }
}

fn rs_ffi_18_allocator_mismatch_c_alloc_rust_free() {
    let raw = unsafe { c_ffi_alloc(512) };  /* C allocated with its allocator */

    unsafe {
        /* Treat C's allocation as if it were a Box → will try to free with Rust's allocator */
        let slice = slice::from_raw_parts_mut(raw as *mut u8, 512);
        libc::free(raw);  /* Actually we just free with wrong allocator to demonstrate mismatch */
        /* The real bug: if we had Box::from_raw here, drop would use Rust's deallocator
         * on C-allocated memory → UB. Using explicit free() to simulate the same effect. */
        let _ = slice;
    }
}

// ================================================================
// RS-FFI-19: FFI error code not exhaustively matched — new error falls through
//
// C returns error codes. We match on known ones but miss new codes
// added in newer C library versions. Fallthrough = silent wrong behavior.
// ================================================================

#[repr(i32)]
enum FfiError { Ok = 0, Io = -1, Mem = -2, Arg = -3 }

fn rs_ffi_19_incomplete_error_handling(code: i32) {
    match FfiError::try_from(code) {
        Ok(FfiError::Ok) => println!("ok"),
        Ok(FfiError::Io) => println!("io error"),
        Ok(FfiError::Mem) => println!("oom"),
        Ok(FfiError::Arg) => println!("bad arg"),
        Err(_) => {
            /* BUG: C added Busy=-4, Timeout=-5 in newer version.
             * We don't know about them, fall through to "ignore" */
            println!("unknown error {}, continuing...", code);
        }
    }
}

impl TryFrom<i32> for FfiError {
    type Error = ();
    fn try_from(v: i32) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(FfiError::Ok),
            -1 => Ok(FfiError::Io),
            -2 => Ok(FfiError::Mem),
            -3 => Ok(FfiError::Arg),
            _ => Err(()),
        }
    }
}

// ================================================================
// RS-FFI-20: panic across FFI boundary (in unsafe block calling FFI)
//
// In an unsafe block, we call an FFI function. Before FFI returns,
// a Rust panic occurs (e.g., from a closure or Drop that runs during
// unwinding). FFI's internal state is now inconsistent because
// unwinding skipped FFI's cleanup.
// ================================================================

struct PanicOnDrop { msg: String }

impl Drop for PanicOnDrop {
    fn drop(&mut self) {
        panic!("intentional panic during drop across FFI");
    }
}

fn rs_ffi_20_panic_across_ffi() {
    let _guard = PanicOnDrop { msg: "ffi_boundary_test".into() };
    unsafe {
        /* If this FFI call triggers Drop somehow (e.g., through a callback
         * that panics), or if unwinding reaches here before FFI returns... */
        let mut ctx: *mut c_void = null_mut();
        let _ret = c_ffi_init_context(&mut ctx);
        /* If _guard drops here (due to panic or early return) while
         * FFI holds internal locks/state → inconsistent state */
        let _ = _ret;
        let _ = ctx;
    }
}

// ================================================================
// CONTROL-RS-01 (≤5% noise): Pure Rust unsafe bug, no FFI involved
//
// Creating a raw pointer to a local, returning it. No FFI.
// This should NOT be OmniScope's primary detection target.
// ================================================================

fn control_rs_01_pure_unsafe_no_ffi() -> *const i32 {
    let x = 42;
    &x as *const i32  /* Returns pointer to stack-local. Pure Rust unsafe bug. */
}

// ================================================================
// main
// ================================================================

#[no_mangle]
pub extern "C" fn main_redteam_v3() {
    println!("=== Red Team v3: Pure Unsafe+FFI Boundary Bugs ===");

    rs_ffi_01_double_free_box();
    rs_ffi_02_cstring_uaf_across_ffi();
    rs_ffi_03_borrowed_str_escapes_to_c("borrow_me");
    rs_ffi_03_use_dangling_later();
    rs_ffi_04_vec_dropped_before_callback();
    rs_ffi_05_trigger_overslice();
    rs_ffi_06_use_after_ffi_invalidates();
    rs_ffi_07_expose_mut_via_ffi();
    rs_ffi_08_null_ctx_from_failed_init();
    rs_ffi_09_cast_away_const_from_ffi();
    rs_ffi_10_reentrant_state_bug();
    rs_ffi_11_stack_ref_to_c();
    rs_ffi_12_null_deref_from_ffi();
    rs_ffi_13_use_stale();
    rs_ffi_14_use_then_ffi_frees();
    rs_ffi_15_free_before_fire();
    rs_ffi_16_static_mut_race();
    rs_ffi_17_ffi_oob_write();
    rs_ffi_18_allocator_mismatch_rust_alloc_c_free();
    rs_ffi_19_incomplete_error_handling(-4);
    rs_ffi_20_panic_across_ffi();

    let _dangling = control_rs_01_pure_unsafe_no_ffi();
    unsafe { let _ = *_dangling; }

    println!("=== Done: 20 FFI+unsafe bugs + 1 control ===");
}

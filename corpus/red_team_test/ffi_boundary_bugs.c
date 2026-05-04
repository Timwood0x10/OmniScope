/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope FFI Boundary Adversarial Tests                  ║
 * ║  Written to match OmniScope's naming conventions           ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * OmniScope classifies functions by LLVM linkage + language patterns:
 * - Rust: _ZN4core, _ZN5alloc, _ZN3std, _R, $u20$, $LT$
 * - Go:   runtime., main., C.
 * - Zig:  std., @ptrCast, @cImport
 * - C++:  _Z prefix, std::
 *
 * This file uses C naming (OmniScope will classify as C/FFI).
 * The key is: functions must CALL unsafe functions OmniScope recognizes.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/mman.h>

typedef void (*callback_t)(int);

/* ================================================================
 * dlopen / dlsym FFI Issues
 * ================================================================ */

void FFI_01_dlopen_null_check(void) {
    void* handle = dlopen("libfoo.so", RTLD_NOW);
    void* sym = dlsym(handle, "process_data");
    // BUG: No NULL check on sym
    typedef void (*fn_t)(char*);
    fn_t fn = (fn_t)sym;
    fn("input");  // Crash if sym==NULL
}

void FFI_02_dlclose_while_held(void) {
    void* handle = dlopen("libfoo.so", RTLD_NOW);
    void* sym = dlsym(handle, "get_buffer");
    typedef char* (*buf_fn_t)(void);
    char* buf = ((buf_fn_t)sym)();
    dlclose(handle);  // BUG: close while buf still used
    printf("%s\n", buf);  // Use after close
}

void FFI_03_dlsym_leak_handle(void) {
    void* h1 = dlopen("libcrypto.so", RTLD_NOW);
    void* sym = dlsym(h1, "malloc");
    dlclose(h1);
    typedef void* (*malloc_fn_t)(size_t);
    ((malloc_fn_t)sym)(256);  // Use after dlclose
}

/* ================================================================
 * malloc/free mismatches in FFI context
 * ================================================================ */

void FFI_04_c_alloc_go_free(void* go_ctx) {
    void* p = malloc(256);
    // Simulate: Go runtime expects Go_free(p)
    // BUG: calling free(p) directly may not match Go allocator
    free(p);
}

void FFI_05_ownership_leak(void* ctx, void* data, int len) {
    void* saved = malloc(len);
    memcpy(saved, data, len);
    // BUG: saved never freed, go_ctx holds reference
    printf("leaked %d bytes\n", len);
}

void FFI_06_double_free_ffi(void* p) {
    free(p);  // Go may also free p on GC
    // BUG: double free!
}

void FFI_07_rust_vec_to_c_array(void* vec_ptr, int* out_len) {
    // Rust returns pointer to Vec internal buffer
    // C treats as owned array
    int* data = (int*)vec_ptr;
    *out_len = 100;
    // BUG: Rust Vec never freed - leak!
    printf("vec data: %d\n", data[0]);
}

/* ================================================================
 * Callback / Function Pointer Issues
 * ================================================================ */

void FFI_08_callback_to_freed(void) {
    void* obj = malloc(64);
    // register_callback(obj); -- simulate registration
    free(obj);
    // trigger_events(); -- BUG: callback uses freed obj
}

void FFI_09_fp_to_unloaded_code(void) {
    void* code = dlopen("./plugin.so", RTLD_NOW);
    if (code) {
        void (*fn)(int) = dlsym(code, "run_plugin");
        dlclose(code);  // BUG: close before use
        fn(10);  // SIGSEGV
    }
}

void FFI_10_stack_ptr_callback(void) {
    int local_data = 100;
    typedef void (*cb_t)(int*);
    cb_t callback = NULL;  // Would be set by FFI

    if (callback) {
        callback(&local_data);  // BUG: pass stack ptr to external
        // External may store and use after this func returns
    }
}

/* ================================================================
 * String / Buffer FFI Issues
 * ================================================================ */

void FFI_11_go_string_race(char* go_str) {
    // Go passes string, may free concurrently
    // BUG: printf may read freed memory
    printf("%s\n", go_str);
}

void FFI_12_unterminated_cstring(char* buf, int len) {
    // C creates buffer, Go expects null-terminated
    // BUG: buf may not be null-terminated for Go
    typedef char* (*to_go_t)(char*, int);
}

void FFI_13_buffer_size_mismatch(void* ptr, int rust_len, int c_cap) {
    char* buf = (char*)ptr;
    // BUG: rust_len vs c_cap may not match
    for (int i = 0; i < rust_len && i < c_cap; i++) {
        buf[i] = (char)(i % 26 + 'A');
    }
}

/* ================================================================
 * Python C Extension Style Issues
 * ================================================================ */

void FFI_14_py_decref_dangle(void* py_obj) {
    typedef void (*dec_t)(void*);
    dec_t dec = (dec_t)dlsym(RTLD_DEFAULT, "Py_DECREF");
    if (dec) {
        dec(py_obj);  // May free object
        // BUG: py_obj may still be used
        printf("%d\n", *(int*)py_obj);  // UAF!
    }
}

void FFI_15_py_refcount_leak(void* py_obj, int is_owned) {
    typedef void (*inc_t)(void*);
    typedef void (*dec_t)(void*);
    inc_t incref = (inc_t)dlsym(RTLD_DEFAULT, "Py_INCREF");
    dec_t decref = (dec_t)dlsym(RTLD_DEFAULT, "Py_DECREF");

    if (!is_owned && incref) incref(py_obj);  // BUG: wrong refcount
    if (decref) decref(py_obj);  // May be premature
}

/* ================================================================
 * System Call / IPC FFI Issues
 * ================================================================ */

void FFI_16_fork_fd_leak(void) {
    int pipes[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, pipes);

    pid_t pid = fork();
    if (pid == 0) {
        close(pipes[0]);
        execvp("ls", (char*[]){ "ls", NULL });
    }
    // BUG: pipes[1] leaked in parent
}

void FFI_17_mmap_cross_lang(void* ctx, size_t size) {
    void* mem = mmap(NULL, size, 3, 0x01, -1, 0);  // PROT_RW, MAP_ANON
    // Other language may munmap(mem) while C uses it
    char* c = (char*)mem;
    c[0] = 'A';
    printf("mmap: %p\n", mem);
}

void FFI_18_execvp_injection(char* user_path) {
    // BUG: user_path passed directly to execvp
    // Attacker can pass "; rm -rf /" or similar
    char* args[] = { user_path, NULL };
    execvp(user_path, args);  // Command injection!
}

/* ================================================================
 * Integer / Type Safety Across FFI
 * ================================================================ */

void FFI_19_sizet_int_mismatch(void* ptr, int len) {
    char* buf = (char*)ptr;
    // BUG: len is int, Rust interprets as usize
    // Negative len becomes huge positive!
    for (int i = 0; i < len; i++) {
        buf[i] = 0;  // Buffer overflow!
    }
}

void FFI_20_enum_ffi_mismatch(void* ctx, int raw_mode) {
    // C passes raw int, Rust interprets as enum
    // BUG: raw_mode may be invalid enum variant
    switch (raw_mode) {
    case 0: break;
    case 1: break;
    case 2: break;
    default: break;  // Invalid variant!
    }
}

/* ================================================================
 * Pointer lifetime FFI Issues
 * ================================================================ */

void FFI_21_stack_ptr_return(void) {
    char buf[64];
    snprintf(buf, sizeof(buf), "temp-%d", 12345);
    // BUG: returning stack pointer
    printf("%s\n", buf);
}

void FFI_22_cgo_pointer_leak(void* p) {
    void* saved = malloc(128);
    memcpy(saved, p, 64);
    // BUG: saved never freed, p may be Go-managed
    printf("leaked cgo pointer\n");
}

/* ================================================================
 * main()
 * ================================================================ */

int main(int argc, char** argv) {
    printf("=== OmniScope FFI Red Team Tests v2 ===\n");

    FFI_01_dlopen_null_check();
    FFI_02_dlclose_while_held();
    FFI_03_dlsym_leak_handle();
    FFI_04_c_alloc_go_free(NULL);
    FFI_05_ownership_leak(NULL, NULL, 0);
    FFI_06_double_free_ffi(NULL);
    FFI_07_rust_vec_to_c_array(NULL, NULL);
    FFI_08_callback_to_freed();
    FFI_09_fp_to_unloaded_code();
    FFI_10_stack_ptr_callback();
    FFI_11_go_string_race(NULL);
    FFI_12_unterminated_cstring(NULL, 0);
    FFI_13_buffer_size_mismatch(NULL, 0, 0);
    FFI_14_py_decref_dangle(NULL);
    FFI_15_py_refcount_leak(NULL, 0);
    FFI_16_fork_fd_leak();
    FFI_17_mmap_cross_lang(NULL, 4096);
    FFI_18_execvp_injection("ls");
    FFI_19_sizet_int_mismatch(NULL, -1);
    FFI_20_enum_ffi_mismatch(NULL, 999);
    FFI_21_stack_ptr_return();
    FFI_22_cgo_pointer_leak(NULL);

    printf("=== All FFI tests done ===\n");
    return 0;
}

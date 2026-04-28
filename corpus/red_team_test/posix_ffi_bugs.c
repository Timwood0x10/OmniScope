/**
 * POSIX FFI Bug Test Cases
 *
 * Tests for POSIX API FFI boundary issues:
 * - dlopen/dlsym/dlclose lifecycle issues
 * - mmap/munmap pairing issues
 * - pthread_create callback lifetime issues
 * - signal handler async-safety issues
 * - fork/exec resource handling
 */

#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef void (*handler_t)(int);
typedef void* (*thread_fn)(void*);

/* POSIX-01: dlopen return value not checked */
void* POSIX_01_dlopen_Null_Check(const char* path) {
    void* handle = dlopen(path, RTLD_NOW);
    // BUG: dlopen returns NULL on error, should check
    void* sym = dlsym(handle, "init_function");
    // Crash if handle is NULL
    return sym;
}

/* POSIX-02: dlsym return value not checked */
void* POSIX_02_dlsym_Null_Check(void* handle, const char* name) {
    void* sym = dlsym(handle, name);
    // BUG: dlsym returns NULL if symbol not found
    // Using sym without check causes crash
    typedef int (*init_fn)(void);
    init_fn fn = (init_fn)sym;
    return (void*)(intptr_t)fn();
}

/* POSIX-03: dlclose while derived pointers in use */
void* cached_sym = NULL;
void* handle_g = NULL;

void POSIX_03_dlclose_While_Pointers_Active(const char* path) {
    handle_g = dlopen(path, RTLD_NOW);
    cached_sym = dlsym(handle_g, "get_buffer");
    dlclose(handle_g);
    // BUG: handle closed but cached_sym still points to library memory
    // Accessing cached_sym is use-after-close
}

/* POSIX-04: mmap returns MAP_FAILED not checked */
void* POSIX_04_mmap_MAPEAILED_Not_Checked(size_t size) {
    void* addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    // BUG: mmap returns MAP_FAILED ((void*)-1) on error
    // Not checking leads to operating on invalid memory
    memset(addr, 0, size);
    return addr;
}

/* POSIX-05: munmap while pointer still in use */
void* mapped_region = NULL;

void* POSIX_05_munmap_While_In_Use(size_t size) {
    mapped_region = mmap(NULL, size, PROT_READ | PROT_WRITE,
                        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapped_region == MAP_FAILED) return NULL;
    return mapped_region;
}

void POSIX_05_cleanup(void) {
    if (mapped_region != NULL) {
        munmap(mapped_region, 0);
        mapped_region = NULL;
    }
}

void POSIX_05_use_after_munmap(void) {
    if (mapped_region != NULL) {
        munmap(mapped_region, 0);
        // BUG: Using mapped_region after munmap - memory may be reused
        strcpy(mapped_region, "use after munmap");
    }
}

/* POSIX-06: pthread_create with dangling callback argument */
void* pthread_arg_global = NULL;

void* POSIX_06_thread_callback(void* arg) {
    char* buf = (char*)arg;
    // BUG: arg points to stack-local in caller
    // If caller returns before thread runs, arg is dangling
    return (void*)(intptr_t)strlen(buf);
}

void POSIX_06_create_Thread_Dangling_Arg(void) {
    char local_buf[256];
    strcpy(local_buf, "thread argument");
    pthread_t tid;
    pthread_create(&tid, NULL, POSIX_06_thread_callback, local_buf);
    pthread_detach(tid);
    // BUG: local_buf goes out of scope but thread may still access it
}

/* POSIX-07: signal handler calls non-async-signal-safe function */
volatile sig_atomic_t signal_count = 0;

void POSIX_07_signal_Handler_Non_Async_Safe(int sig) {
    signal_count++;
    // BUG: printf is NOT async-signal-safe
    // Should only call async-signal-safe functions (write, _exit, etc.)
    printf("Signal %d received, count: %d\n", sig, signal_count);
}

void POSIX_07_register_Handler(void) {
    struct sigaction sa;
    sa.sa_handler = POSIX_07_signal_Handler_Non_Async_Safe;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
}

/* POSIX-08: fork without exec in multi-threaded program */
int global_resource;

void POSIX_08_fork_MultiThread_Danger(void) {
    // BUG: fork() in multi-threaded program is dangerous
    // Only one thread is duplicated, others are killed
    // But atexit handlers, locked mutexes, etc. are in undefined state
    pid_t pid = fork();
    if (pid == 0) {
        global_resource = 42;
        _exit(0);
    }
}

/* POSIX-09: socket fd not closed on error path */
int POSIX_09_socket_Leak_On_Error(void) {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(9999);

    int ret = bind(sock, (struct sockaddr*)&addr, sizeof(addr));
    if (ret < 0) {
        // BUG: sock leaked - should close(sock) before returning
        return -1;
    }

    close(sock);
    return 0;
}

/* POSIX-10: close(sock) then use sock */
void POSIX_10_close_Then_Use(int sock) {
    close(sock);
    // BUG: sock may be reused by OS for next socket
    // Using closed fd leads to undefined behavior
    char buf[1024];
    ssize_t n = recv(sock, buf, sizeof(buf), 0);
    (void)n;
}

/* POSIX-11: pthread_mutex_lock after pthread_detach */
pthread_mutex_t global_mutex = PTHREAD_MUTEX_INITIALIZER;
void* global_data = NULL;

void* POSIX_11_mutex_After_Detach(void* arg) {
    pthread_mutex_lock(&global_mutex);
    global_data = arg;
    pthread_mutex_unlock(&global_mutex);
    return NULL;
}

void POSIX_11_use_After_Detach(void* arg) {
    pthread_t tid;
    pthread_create(&tid, NULL, POSIX_11_mutex_After_Detach, arg);
    pthread_detach(tid);
    // BUG: pthread_detach may have completed before thread accesses mutex
    // This is actually safe, but shows the pattern to detect
}

/* POSIX-12: mprotect on pointer not from mmap */
void POSIX_12_mprotect_Invalid_Pointer(void* ptr) {
    // BUG: mprotect requires ptr to be page-aligned
    // ptr from malloc may not be page-aligned
    // This will fail with EINVAL
    mprotect(ptr, 4096, PROT_READ);
}

/* POSIX-13: getaddrinfo memory leak */
void POSIX_13_getaddrinfo_Leak(void) {
    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    int ret = getaddrinfo("example.com", "80", &hints, &res);
    if (ret != 0) return;

    // BUG: res allocated by getaddrinfo must be freed with freeaddrinfo
    // Forgetting to call freeaddrinfo is a memory leak
    // close(socket_fd); // forgot to close
}

/* POSIX-14: setjmp/longjmp in signal handler danger */
#include <setjmp.h>
static jmp_buf jump_buffer;
volatile sig_atomic_t in_signal = 0;

void POSIX_14_signal_Handler(int sig) {
    if (in_signal) {
        // BUG: longjmp from signal handler is undefined behavior
        // unless signal was raised by raise(), abort(), or kill()
        longjmp(jump_buffer, 1);
    }
}

void POSIX_14_setjmp_longjmp_Signal(void) {
    struct sigaction sa;
    sa.sa_handler = POSIX_14_signal_Handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGALRM, &sa, NULL);

    if (setjmp(jump_buffer) == 0) {
        in_signal = 1;
        alarm(1);
        pause();
    }
    in_signal = 0;
}

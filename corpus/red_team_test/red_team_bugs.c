/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║  OmniScope Red Team Adversarial Test - Intentionally Buggy Code ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * This file intentionally contains various types of known security
 * vulnerabilities to verify OmniScope's detection capabilities.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// ============================================================
// BUG-01: Memory Leak - malloc without free
// Expected: MEMORY_LEAK
// ============================================================
void bug_memory_leak(void) {
    char *buffer = (char *)malloc(1024);  // [BUG] Allocate 1024 bytes
    strcpy(buffer, "This will never be freed!");
    printf("Leaked: %s\n", buffer);
    // [BUG] Forgot free(buffer) -- memory leak!
    return;
}

// ============================================================
// BUG-02: Use-After-Free - usage after deallocation
// Expected: USE_AFTER_FREE (Critical)
// ============================================================
void bug_use_after_free(void) {
    int *data = (int *)malloc(sizeof(int) * 10);
    for (int i = 0; i < 10; i++) {
        data[i] = i * i;
    }
    free(data);           // First free

    // [BUG] UAF! data is already freed but still being used
    printf("UAF: %d\n", data[5]);     // Read freed memory
    data[3] = 999;                     // Write to freed memory!
}

// ============================================================
// BUG-03: Double Free - freeing the same pointer twice
// Expected: DOUBLE_FREE / USE_AFTER_FREE
// ============================================================
void bug_double_free(void) {
    char *s = strdup("double trouble");
    free(s);
    free(s);  // [BUG] Double Free! Second free of same pointer
}

// ============================================================
// BUG-04: NULL Pointer Dereference - unchecked malloc return value
// Expected: NULL_DEREFERENCE
// ============================================================
void bug_null_deref(void) {
    int *big = (int *)malloc(0x7FFFFFFFFF);  // May return NULL
    // [BUG] Dereference without checking for NULL
    big[0] = 42;  // If malloc fails, this crashes
    free(big);
}

// ============================================================
// BUG-05: FFI RISK - dangerous system() call
// Expected: FFI_RISK (CRITICAL)
// ============================================================
void bug_dangerous_system(void) {
    char user_input[256];
    fgets(user_input, sizeof(user_input), stdin);
    // [BUG] Passing user input directly to system() -- command injection!
    char cmd[512];
    sprintf(cmd, "echo %s", user_input);  // Also format string vulnerability
    system(cmd);  // [CRITICAL] Command injection risk
}

// ============================================================
// BUG-06: Buffer Overflow - stack buffer overflow
// Expected: BUFFER_OVERFLOW (if supported)
// ============================================================
void bug_buffer_overflow(void) {
    char small[8];
    char *large = "AAAAAAAAAAAAAAAAAAAAAAAAAAAA";  // 28 chars
    // [BUG] Copying 28 bytes into 8-byte buffer -- stack overflow!
    strcpy(small, large);
    printf("Overflowed: %s\n", small);
}

// ============================================================
// BUG-07: Format String Vulnerability
// Expected: FFI_RISK / FORMAT_STRING
// ============================================================
void bug_format_string(char *user_data) {
    // [BUG] user_data used as format string directly in printf
    // Attacker can pass "%s%s%s%s" to read stack contents
    printf(user_data);  // Should be: printf("%s", user_data);
}

// ============================================================
// BUG-08: File Handle Leak - fopen without fclose
// Expected: RESOURCE_LEAK
// ============================================================
void bug_file_handle_leak(void) {
    FILE *f = fopen("/tmp/test.txt", "w");
    if (f != NULL) {
        fprintf(f, "Hello World\n");
        // [BUG] Forgot fclose(f) -- file handle leak
    }
    return;  // f is leaked
}

// ============================================================
// BUG-09: Realloc mishandling (original pointer invalidated)
// Expected: USE_AFTER_FREE / MEMORY_LEAK
// ============================================================
void bug_realloc_mishandle(void) {
    char *buf = (char *)malloc(64);
    strcpy(buf, "original");
    // [BUG] On failure realloc returns NULL, but original buf leaks
    // Correct approach: char *tmp = realloc(buf, 128); if(tmp) buf=tmp;
    buf = (char *)realloc(buf, 128);  // If fails, original memory leaked
    strcat(buf, " extended");
    free(buf);
}

// ============================================================
// BUG-10: Uninitialized Variable Usage
// Expected: UNINITIALIZED_VALUE
// ============================================================
void bug_uninitialized_var(void) {
    int secret;
    int *ptr = &secret;
    // [BUG] secret used before initialization, value is undefined
    if (*ptr > 1000000) {  // Undefined behavior
        printf("Secret: %d\n", secret);  // Output garbage value
    }
}

// ============================================================
// BUG-11: C++ new[] / delete mismatch
// Expected: MEMORY_LEAK / CORRUPTION
// ============================================================
#ifdef __cplusplus
void bug_new_delete_mismatch(void) {
    int *arr = new int[100];   // Using new[]
    delete arr;                // [BUG] Should use delete[]!
    // This causes destructor to be called only once, memory corruption
}
#endif

// ============================================================
// BUG-12: Dangerous popen() call - command execution
// Expected: FFI_RISK (CRITICAL)
// ============================================================
void bug_popen_risk(void) {
    char input[128];
    fgets(input, sizeof(input), stdin);
    // [BUG] User input passed directly to popen -- command injection
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "cat %s", input);  // Relatively safer but still risky
    FILE *pipe = popen(cmd, "r");
    if (pipe) {
        char line[256];
        while (fgets(line, sizeof(line), pipe)) {
            printf("%s", line);
        }
        pclose(pipe);
    }
}

// ============================================================
// BUG-13: Out-of-Bounds Array Access
// Expected: OUT_OF_BOUNDS
// ============================================================
void bug_out_of_bounds_access(void) {
    int arr[5] = {1, 2, 3, 4, 5};
    // [BUG] Accessing arr[10], out of bounds!
    int val = arr[10];   // Read out of bounds
    arr[15] = 42;        // Write out of bounds! More dangerous
    printf("OOB: %d\n", val);
}

// ============================================================
// BUG-14: Multi-pointer Leak - struct member leak
// Expected: MEMORY_LEAK (Complex)
// ============================================================
typedef struct {
    char *name;
    char *data;
    int count;
} ComplexStruct;

void bug_struct_member_leak(void) {
    ComplexStruct *cs = (ComplexStruct *)malloc(sizeof(ComplexStruct));
    cs->name = strdup("test_name");      // Allocation 1
    cs->data = (char *)malloc(4096);     // Allocation 2
    cs->count = 42;

    free(cs->name);  // Freed name
    // [BUG] Forgot free(cs->data) -- member leak
    // [BUG] Also forgot free(cs) -- struct itself leaked
}

// ============================================================
// BUG-15: Loop-internal repeated allocation without free
// Expected: MEMORY_LEAK (Loop)
// ============================================================
void bug_loop_leak(int iterations) {
    for (int i = 0; i < iterations; i++) {
        char *chunk = (char *)malloc(1024);
        chunk[0] = 'A';
        // [BUG] Each iteration allocates 1024 bytes but never frees
        // After 'iterations' loops, leaks iterations*1024 bytes
    }
}

// ============================================================
// BUG-16: Conditional Branch Leak
// Expected: MEMORY_LEAK (Path-sensitive)
// ============================================================
void bug_conditional_leak(int flag) {
    void *resource = malloc(2048);
    if (flag > 0) {
        free(resource);
        return;
    }
    // [BUG] When flag <= 0, resource is not freed
    printf("Resource still alive: %p\n", resource);
}

// ============================================================
// BUG-17: exec family function calls
// Expected: FFI_RISK (CRITICAL)
// ============================================================
void bug_exec_call(void) {
    char *args[] = {"ls", "-la", NULL};
    // [BUG] execvp replaces current process -- high risk in FFI context
    execvp("ls", args);
}

// ============================================================

int main(int argc, char **argv) {
    printf("=== OmniScope Red Team Test ===\n");

    bug_memory_leak();           // BUG-01: Memory leak
    bug_use_after_free();        // BUG-02: Use-After-Free
    bug_double_free();           // BUG-03: Double Free
    bug_null_deref();            // BUG-04: NULL dereference
    // bug_dangerous_system();   // BUG-05: system() - too dangerous, commented out
    bug_buffer_overflow();       // BUG-06: Buffer overflow
    bug_format_string(argv[1]);  // BUG-07: Format string
    bug_file_handle_leak();      // BUG-08: File handle leak
    bug_realloc_mishandle();     // BUG-09: Realloc misuse
    bug_uninitialized_var();     // BUG-10: Uninitialized variable
    bug_popen_risk();            // BUG-12: popen command injection
    bug_out_of_bounds_access();  // BUG-13: Array OOB
    bug_struct_member_leak();    // BUG-14: Struct member leak
    bug_loop_leak(10);           // BUG-15: Loop leak
    bug_conditional_leak(-1);    // BUG-16: Conditional leak
    bug_exec_call();             // BUG-17: exec call

#ifdef __cplusplus
    bug_new_delete_mismatch();   // BUG-11: new[]/delete mismatch
#endif

    printf("=== All bugs executed ===\n");
    return 0;
}

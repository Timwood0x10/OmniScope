// OmniScope v0.1.7 — CRITICAL Pattern Corpus
// Contains patterns that trigger [OMI-CRITICAL] reporters:
//   - Stack escape: alloca result passed to extern function
//   - Stack-to-global: local address stored in global variable
//   - Resource UAF: FILE* used after fclose
//   - Use-after-free: malloc'd ptr used after free

#include <stdlib.h>
#include <string.h>

// External function that retains the pointer (FFI boundary)
extern void ffi_retain_ptr(void *ptr);
extern void ffi_process_data(char *buf, int len);
extern void c_callback_register(void (*cb)(void *));
static char *g_stolen_stack_addr = NULL;

// BUG-CRIT-01: Stack address passed to FFI retaining function
// Expected: [OMI-CRITICAL] [STACK-ESCAPE]
void bugCrit01_StackEscapeToFFI() {
    char secret[32];
    memset(secret, 'A', sizeof(secret));
    // alloca result passed to external function — becomes dangling when func returns
    ffi_retain_ptr(secret);
}

// BUG-CRIT-02: Stack address stored in global
// Expected: [OMI-CRITICAL] [STACK-TO-GLOBAL]
void bugCrit02_StackToGlobal() {
    int local_value = 0xDEAD;
    g_stolen_stack_addr = (char *)&local_value;
    // g_stolen_stack_addr now points to dead stack frame
}

// BUG-CRIT-03: Return address of local variable
// Expected: [OMI-CRITICAL] [RETURN-STACK]
char *bugCrit03_ReturnStackAddr() {
    char buffer[64];
    memset(buffer, 'B', sizeof(buffer));
    return buffer; // returns address of stack-local
}

// BUG-CRIT-04: Use-after-free on heap
// Expected: [OMI-HIGH] [UAF-RISK]
void bugCrit04_UseAfterFree() {
    char *data = malloc(256);
    if (!data) return;
    strcpy(data, "sensitive data");
    free(data);
    // data is now freed but still used
    size_t len = strlen(data); // UAF!
    (void)len;
}

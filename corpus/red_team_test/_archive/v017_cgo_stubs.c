// OmniScope v0.1.7 — CGO Stub Implementations
//
// Provides dummy implementations for all C functions declared
// in v017_go_cgo_chain.go's CGO preamble. These are corpus/test
// stubs — real logic is in the LLVM IR analysis.

#include <stdlib.h>
#include <string.h>

void* cgo_malloc(size_t n) { return malloc(n); }
void  cgo_free(void* p) { free(p); }
int   cgo_process_data(void* buf, int len) { (void)buf; (void)len; return 0; }
char* cgo_get_string(void) { return strdup("cgo_string"); }
void* cgo_get_raw(int id) { (void)id; return malloc(64); }
char* cgo_process_string(char* str) { (void)str; return NULL; }
void  cgo_register_callback(void* cb_fn, void* ctx) { (void)cb_fn; (void)ctx; }

void* _cgo_allocate(size_t size, int flags) { (void)flags; return malloc(size); }
int   _cgo_expact_call(void* fn, void* arg) { (void)fn; (void)arg; return 0; }
void  _Cfunc_process(void* ctx) { (void)ctx; }

void* sim_crosscall2(void* fn, void* arg) { (void)fn; (void)arg; return NULL; }
void  sim_runtime_cgocall(void* fn, int arg) { (void)fn; (void)arg; }

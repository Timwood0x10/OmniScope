//! C++ Bridge for LLVM IR parsing
//!
//! Uses llvm::parseIRFile (C++ API) to parse text IR (.ll) files directly,
//! avoiding both the segfault in LLVMParseIRInContext (C API, LLVM 22 bug)
//! and the external llvm-as dependency.
//!
//! LLVM 22's C API LLVMParseIRInContext segfaults at address 0x8 on text IR.
//! Root cause: target/machine init missing from the C API context path.
//! The C++ API llvm::parseIRFile handles this correctly.

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm-c/Types.h"
#include <cstdlib>
#include <cstring>

extern "C" {

/// Parse an LLVM IR file (.ll) using llvm::parseIRFile (C++ API).
///
/// Returns 0 on success, non-zero on failure.
/// On success, *module_out is set to the parsed module (caller owns it).
/// On failure, *module_out is null and *error_out (if non-null) is set to
/// an error message string that must be freed with omni_free_string.
int omni_parse_ir_file(const char* path, void* context, void** module_out, char** error_out) noexcept {
    if (!path || !context || !module_out) return 1;
    *module_out = nullptr;
    if (error_out) *error_out = nullptr;

    llvm::SMDiagnostic diag;
    auto* ctx = llvm::unwrap(reinterpret_cast<LLVMContextRef>(context));
    auto mod = llvm::parseIRFile(path, diag, *ctx);

    if (!mod) {
        if (error_out) {
            std::string msg = diag.getMessage().str();
            *error_out = strdup(msg.c_str());
            // caller handles nullptr (OOM case)
        }
        return 1;
    }

    *module_out = mod.release();
    return 0;
}

/// Free a string allocated by this bridge (must use free() since strdup was used).
void omni_free_string(char* str) noexcept {
    if (str) free(str);
}

} // extern "C"
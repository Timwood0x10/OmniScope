//! C++ Bridge for LLVM IR parsing
//!
//! Supports both .ll (text IR) and .bc (bitcode) files:
//!   - .ll  → llvm::parseIRFile (C++ API, avoids LLVM 22 C API segfault)
//!   - .bc  → llvm::parseBitcodeFile (C++ API, avoids LLVM 22 C API issues)

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Error.h"
#include "llvm-c/Types.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C" {

/// Parse an LLVM IR file (.ll or .bc) using the appropriate C++ API.
///
/// Auto-detects the file format by extension:
///   - .bc  → llvm::parseBitcodeFile (via MemoryBuffer)
///   - .ll  → llvm::parseIRFile (via SMDiagnostic)
///
/// Returns 0 on success, non-zero on failure.
/// On success, *module_out is set to the parsed module (caller owns it).
/// On failure, *module_out is null and *error_out (if non-null) is set to
/// an error message string that must be freed with omni_free_string.
int omni_parse_ir_file(const char* path, void* context, void** module_out, char** error_out) noexcept {
    if (!path || !context || !module_out) return 1;
    *module_out = nullptr;
    if (error_out) *error_out = nullptr;

    auto* ctx = llvm::unwrap(reinterpret_cast<LLVMContextRef>(context));

    // Auto-detect file format by extension
    const char* ext = std::strrchr(path, '.');
    const bool is_bc = ext && std::strcmp(ext, ".bc") == 0;

    if (is_bc) {
        // ── Bitcode (.bc) path ──
        // Read file using C I/O then wrap in a MemoryBuffer via getMemBufferCopy.
        // This avoids calling llvm::MemoryBuffer::getFile (which has
        // std::optional<Align> in its LLVM 22 signature), which causes
        // an ABI mismatch / undefined symbol error on Linux CI where the
        // LLVM library was compiled with a different C++ standard library.
        FILE* fp = fopen(path, "rb");
        if (!fp) {
            if (error_out) *error_out = strdup("Failed to open bitcode file");
            return 1;
        }

        fseek(fp, 0, SEEK_END);
        long file_size = ftell(fp);
        if (file_size < 0) {
            fclose(fp);
            if (error_out) *error_out = strdup("Failed to determine bitcode file size");
            return 1;
        }
        rewind(fp);

        std::string data;
        data.resize(static_cast<size_t>(file_size));
        if (file_size > 0) {
            size_t nread = fread(&data[0], 1, static_cast<size_t>(file_size), fp);
            if (nread != static_cast<size_t>(file_size)) {
                fclose(fp);
                if (error_out) *error_out = strdup("Failed to read bitcode file");
                return 1;
            }
        }
        fclose(fp);

        auto memBuffer = llvm::MemoryBuffer::getMemBufferCopy(data, path);
        auto modOrErr = llvm::parseBitcodeFile(memBuffer->getMemBufferRef(), *ctx);
        if (!modOrErr) {
            if (error_out) {
                std::string msg;
                llvm::handleAllErrors(modOrErr.takeError(), [&](const llvm::ErrorInfoBase& E) {
                    msg = E.message();
                });
                *error_out = strdup(msg.c_str());
            }
            return 1;
        }

        *module_out = modOrErr->release();
        return 0;
    }

    // ── Text IR (.ll) path ──
    // Use llvm::parseIRFile which handles target/machine init correctly
    // (avoids LLVM 22 C API LLVMParseIRInContext segfault at address 0x8).
    llvm::SMDiagnostic diag;
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
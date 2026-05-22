#!/usr/bin/env python3
"""Update config/languages/c.json with C/C++ filtering rules from C_CPP_IR_SPEC.md."""
import json

with open('config/languages/c.json', 'r') as f:
    config = json.load(f)

# Add C/C++ stdlib prefixes - from IR SPEC §9.2 and §1.2
config['stdlib_prefixes'] = [
    # libc++ (macOS default)
    "_ZNSt3__1",       # std::__1 namespace (libc++)
    "_ZSt",            # std template instantiations
    "_ZNSt",           # std namespace mangled
    # libstdc++ (Linux default)
    "_ZNS_",           # std:: substitution
    # GNU C++ library
    "__gnu_cxx",       # __gnu_cxx namespace
    "__cxa_",          # C++ ABI runtime functions
    # C standard library checked variants
    "__sprintf_chk",
    "__strcpy_chk",
    "__printf_chk",
    "__fprintf_chk",
    "__vsnprintf_chk",
    "__memcpy_chk",
    "__memmove_chk",
    "__memset_chk",
]

# Add noise prefixes - compiler/runtime noise to filter out
config['noise_prefixes'] = [
    # C++ ABI runtime (IR SPEC §9.2)
    "_ZTVN10__cxxabiv1",  # __cxxabiv1 vtable
    "_ZTIN10__cxxabiv1",  # __cxxabiv1 typeinfo
    # Exception handling infrastructure (IR SPEC §4)
    "__gxx_personality_v0",
    "__cxa_throw",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_rethrow",
    "__cxa_allocate_exception",
    "__cxa_free_exception",
    "__cxa_guard_acquire",
    "__cxa_guard_release",
    "__cxa_guard_abort",
    "_Unwind_",
    # C++ compiler generated (IR SPEC §8)
    "__clang_call_terminate",
    "__cxa_pure_virtual",
    "__cxa_deleted_virtual",
    # C runtime internals
    "__stack_chk_fail",
    "__stack_chk_guard",
    "__libc_start_main",
    "_init",
    "_fini",
    "__cxa_atexit",
    "atexit",
    "__dso_handle",
    "_GLOBAL__",
    "__cxx_global_var_init",
    "__tls_init",
    # Thread-local and guard (IR SPEC §8.3)
    "_ZGV",           # Guard variable prefix
    # Thunks (IR SPEC §8.2)
    "_ZTh",           # Adjustor thunk (non-virtual)
    "_ZTv",           # Virtual thunk
    # MSVC mangling (IR SPEC §1.3)
    "?",              # MSVC mangled name start
    # C checked library functions
    "__builtin_",
    "__asm_",
]

# Add compiler reserved symbols - from IR SPEC §1.2.4, §5, §6
config['compiler_reserved'] = [
    # VTable and RTTI (IR SPEC §5)
    "_ZTV",           # Virtual table
    "_ZTI",           # Typeinfo object
    "_ZTS",           # Typeinfo name string
    "_ZTT",           # VTT (Virtual Table Table)
    # Operator new/delete (IR SPEC §3.2)
    "_Znwm",          # operator new(unsigned long)
    "_ZdlPv",         # operator delete(void*)
    "_ZdlPvm",        # operator delete(void*, unsigned long)
    "_ZnwmSt11align_val_t",    # operator new with alignment
    "_ZdlPvmSt11align_val_t",  # operator delete with alignment
    "_Znam",          # operator new[](unsigned long)
    "_ZdaPv",         # operator delete[](void*)
    # Guard variables (IR SPEC §8.3)
    "_ZGV",           # Guard variable for thread-safe statics
    # Thunks (IR SPEC §8.2)
    "_ZTh",           # Adjustor thunk
    "_ZTv",           # Virtual call thunk
    # C runtime/compiler helpers
    "__stack_chk_fail",
    "__stack_chk_guard",
    "__libc_start_main",
    "_GLOBAL__",
    "__cxx_global_var_init",
    "__cxa_atexit",
    "__dso_handle",
    "_init",
    "_fini",
    "__tls_init",
]

# Add C++ specific RAII/destructor patterns (like Rust's drop_glue_patterns)
config['cpp_raii_patterns'] = [
    # Destructor patterns (IR SPEC §1.2.3)
    "D0Ev",           # Deleting destructor
    "D1Ev",           # Complete object destructor
    "D2Ev",           # Base object destructor
    # Constructor patterns (IR SPEC §1.2.3)
    "C1Ev",           # Complete constructor
    "C2Ev",           # Base constructor
    # Landing pad cleanup (IR SPEC §4.5)
    "landingpad",
    "cleanup",
]

# Add runtime reserved - C/C++ runtime functions to suppress
config['runtime_reserved'] = [
    # C++ exception handling runtime (IR SPEC §4)
    "__gxx_personality_v0",
    "__cxa_throw",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_rethrow",
    "__cxa_allocate_exception",
    "__cxa_free_exception",
    "__cxa_guard_acquire",
    "__cxa_guard_release",
    "__cxa_guard_abort",
    "__cxa_pure_virtual",
    "__cxa_deleted_virtual",
    "__clang_call_terminate",
    # Unwind infrastructure
    "_Unwind_Resume",
    "_Unwind_DeleteException",
    "_Unwind_RaiseException",
    # C runtime
    "__libc_start_main",
    "__cxa_atexit",
    "atexit",
    "__dso_handle",
]

# Add FFI boundary markers for C/C++ (IR SPEC §2.3, §9.4)
config['ffi_boundary_patterns'] = [
    # extern "C" in C++ compilation units (IR SPEC §1.4)
    "c_free",
    "c_take_ptr",
    "c_malloc",
    "c_register_callback",
    # Cross-language allocation mismatches (IR SPEC §3.5)
    "malloc",
    "free",
    "_Znwm",
    "_ZdlPv",
    "_Znam",
    "_ZdaPv",
    # Common C FFI libraries
    "sqlite3_",
    "inflate",
    "deflate",
    "EVP_",
    "RSA_",
    "BIO_",
    "SSL_",
    "X509_",
    "PEM_",
]

# Add FP suppression rules (IR SPEC §9.2)
config['fp_suppression'] = [
    {"pattern": "_ZTVN10__cxxabiv1", "match_type": "prefix", "reason": "C++ ABI runtime vtable - compiler infrastructure (IR SPEC §5.6)"},
    {"pattern": "_ZTIN10__cxxabiv1", "match_type": "prefix", "reason": "C++ ABI runtime typeinfo - compiler infrastructure (IR SPEC §5.6)"},
    {"pattern": "_ZNSt3__1", "match_type": "prefix", "reason": "libc++ standard library - suppress noise (IR SPEC §9.2)"},
    {"pattern": "_ZSt", "match_type": "prefix", "reason": "std template instantiations - standard library (IR SPEC §9.2)"},
    {"pattern": "__cxa_", "match_type": "prefix", "reason": "C++ ABI runtime function - compiler infrastructure (IR SPEC §4.4)"},
    {"pattern": "__gxx_personality", "match_type": "prefix", "reason": "C++ exception personality function - compiler infrastructure (IR SPEC §4.1)"},
    {"pattern": "_Unwind_", "match_type": "prefix", "reason": "Itanium EH ABI unwind - compiler infrastructure (IR SPEC §4.4)"},
    {"pattern": "_ZGV", "match_type": "prefix", "reason": "Guard variable for thread-safe statics - compiler generated (IR SPEC §8.3)"},
    {"pattern": "_ZTh", "match_type": "prefix", "reason": "Adjustor thunk - compiler generated for multiple inheritance (IR SPEC §8.2)"},
    {"pattern": "_ZTv", "match_type": "prefix", "reason": "Virtual thunk - compiler generated (IR SPEC §8.2)"},
    {"pattern": "_GLOBAL__", "match_type": "prefix", "reason": "Global constructor/destructor - compiler generated"},
    {"pattern": "__cxx_global_var_init", "match_type": "prefix", "reason": "Global variable initializer - compiler generated"},
    {"pattern": "__clang_call_terminate", "match_type": "exact", "reason": "Clang terminate handler - compiler generated (IR SPEC §4)"},
    {"pattern": "D0Ev", "match_type": "suffix", "reason": "Deleting destructor - compiler generated (IR SPEC §1.2.3)"},
    {"pattern": "D1Ev", "match_type": "suffix", "reason": "Complete destructor - compiler generated (IR SPEC §1.2.3)"},
    {"pattern": "D2Ev", "match_type": "suffix", "reason": "Base destructor - compiler generated (IR SPEC §1.2.3)"},
    {"pattern": "__chk", "match_type": "suffix", "reason": "Fortified library function - compiler injected safety check (IR SPEC §1.1)"},
]

# Add cross-language memory bug patterns (IR SPEC §3.5, §9.3)
config['cross_lang_memory_bugs'] = [
    {"allocator": "malloc", "deallocator": "_ZdlPv", "severity": "high", "description": "C malloc + C++ delete (IR SPEC §3.5)"},
    {"allocator": "_Znwm", "deallocator": "free", "severity": "high", "description": "C++ new + C free (IR SPEC §3.5)"},
    {"allocator": "_Znwm", "deallocator": "_ZdaPv", "severity": "high", "description": "C++ new + delete[] mismatch (IR SPEC §9.3)"},
    {"allocator": "_Znam", "deallocator": "_ZdlPv", "severity": "high", "description": "C++ new[] + delete mismatch (IR SPEC §9.3)"},
]

# Update description to mention the IR SPEC
config['description'] = "C/C++ language FFI boundary patterns - memory, I/O, threading, dynamic loading, security-sensitive functions (ref: C_CPP_IR_SPEC.md)"

with open('config/languages/c.json', 'w') as f:
    json.dump(config, f, indent=2)

print("c.json updated successfully")
new_keys = [k for k in config.keys() if k not in ['language', 'version', 'description', 'functions', 'escape_patterns', 'retaining_functions']]
print(f"New keys added: {new_keys}")
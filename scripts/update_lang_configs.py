#!/usr/bin/env python3
"""Update config/languages/*.json with filtering rules from IR SPEC docs."""
import json
import os

CONFIG_DIR = "config/languages"

def load_json(path):
    with open(path, "r") as f:
        return json.load(f)

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

# ============================================================================
# Go GC - Ref: docs/GO_GC_IR_SPEC.md
# ============================================================================
go = load_json(f"{CONFIG_DIR}/go.json")

go["stdlib_prefixes"] = [
    "runtime.",            # ~150 runtime functions (IR SPEC §1.2, §3)
    "internal/runtime/",   # runtime internals (IR SPEC §1.2)
    "internal/",           # internal packages
    "reflect.",            # reflection
    "sync.",               # sync primitives
]

go["noise_prefixes"] = [
    # Compiler-reserved symbols (IR SPEC §1.2)
    "go:",                 # Reserved prefix for go:map etc.
    "type:",               # Reserved prefix for type descriptors
    ".inittask",           # Init task (IR SPEC §9)
    # CGo bridge (IR SPEC §4)
    "_Cgo_",               # CGo helper functions
    "__cgo_",              # CGo static references
    "crosscall2",          # CGo crosscall
    # Write barrier (IR SPEC §6)
    "runtime.writeBarrier",
    "gcWriteBarrier",
    # Memory safety internals (IR SPEC §10)
    "runtime.memmove",
    "runtime.memclr",
    "runtime.gopanic",
    # Type descriptors (IR SPEC §7)
    "type:.hash",
    "type:.eq",
    "type:.kind",
    # Init functions (IR SPEC §9)
    "init.",
]

go["compiler_reserved"] = [
    # Reserved prefixes (IR SPEC §1.2)
    "go:",
    "type:",
    ".inittask",
    # SSA intrinsics (IR SPEC §5)
    "runtime.memhash",
    "runtime.noescape",
    "runtime.KeepAlive",
    "runtime.KeepAliveNoexec",
    # Compiler intrinsics (IR SPEC §5)
    "runtime.cmpstring",
    "runtime.int64string",
    "runtime.slicebytetostring",
    "runtime.slicerunetostring",
    # Write barrier (IR SPEC §6)
    "runtime.writeBarrier",
    "gcWriteBarrier",
    "gcWriteBarrier2",
]

go["runtime_reserved"] = [
    # Core runtime (IR SPEC §3)
    "runtime.mallocgc",
    "runtime.growslice",
    "runtime.gopanic",
    "runtime.gorecover",
    "runtime.goexit",
    "runtime.gosched",
    "runtime.GC",
    "runtime.memmove",
    "runtime.memclrNoHeapPointers",
    "runtime.memclrHasPointers",
    # Channel operations (IR SPEC §10)
    "runtime.chanrecv1",
    "runtime.chanrecv2",
    "runtime.chansend1",
    "runtime.makechan",
    "runtime.closechan",
    # Map operations
    "runtime.mapaccess1",
    "runtime.mapaccess2",
    "runtime.mapassign",
    "runtime.mapdelete",
    # Interface/type (IR SPEC §7)
    "runtime.assertI2I",
    "runtime.convI2I",
    "runtime.convT2E",
    "runtime.convT2I",
    # Race detector
    "runtime.raceread",
    "runtime.racewrite",
    "runtime.racereadrange",
    "runtime.racewriterange",
]

go["ffi_boundary_patterns"] = [
    # CGo import directives (IR SPEC §4)
    "runtime.cgocall",
    "runtime.cgo_yield",
    "runtime.cgo_notify",
    # CGo generated (IR SPEC §4)
    "_Cfunc_",
    "_Cgo_",
    "__cgo_",
    "crosscall2",
    # Exported Go functions for C (IR SPEC §4)
    "_cgo_",
]

go["memory_safety_patterns"] = [
    # GC-related memory concerns (IR SPEC §6, §10)
    {"pattern": "runtime.mallocgc", "kind": "heap_alloc", "severity": "medium", "description": "Heap allocation - escape analysis target (IR SPEC §10)"},
    {"pattern": "runtime.growslice", "kind": "realloc", "severity": "medium", "description": "Slice growth may reallocate (IR SPEC §10)"},
    {"pattern": "runtime.writeBarrier", "kind": "gc_barrier", "severity": "low", "description": "GC write barrier (IR SPEC §6)"},
    {"pattern": "runtime.memmove", "kind": "raw_mem", "severity": "low", "description": "Raw memory operation (IR SPEC §10)"},
]

go["fp_suppression"] = [
    {"pattern": "runtime.", "match_type": "prefix", "reason": "Go runtime - compiler infrastructure (IR SPEC §1.2, §3)"},
    {"pattern": "internal/runtime/", "match_type": "prefix", "reason": "Go runtime internals (IR SPEC §1.2)"},
    {"pattern": "type:", "match_type": "prefix", "reason": "Go type descriptor - compiler generated (IR SPEC §1.2)"},
    {"pattern": "go:", "match_type": "prefix", "reason": "Go reserved prefix (IR SPEC §1.2)"},
    {"pattern": ".inittask", "match_type": "suffix", "reason": "Go init task - compiler generated (IR SPEC §9)"},
    {"pattern": "init.", "match_type": "prefix", "reason": "Go init function - compiler generated (IR SPEC §9)"},
]

go["description"] = "Go language FFI boundary patterns - cgo allocator, pointer escape, runtime safety (ref: GO_GC_IR_SPEC.md)"
save_json(f"{CONFIG_DIR}/go.json", go)
print("go.json updated")

# ============================================================================
# Java/JDK - Ref: docs/JDK_IR_SPEC.md
# ============================================================================
java = load_json(f"{CONFIG_DIR}/java.json")

java["stdlib_prefixes"] = [
    "JVM_",                      # JVM internal functions (IR SPEC §8)
    "java_lang_",                # Java lang native methods
    "jdk_internal_misc_Unsafe",  # Unsafe access (IR SPEC §8)
    "sun_misc_",                 # Legacy sun.misc
]

java["noise_prefixes"] = [
    "JVM_",                  # JVM runtime (IR SPEC §8)
    "java_lang_Object",      # Object native methods
    "java_lang_String",      # String native methods
    "java_lang_Class",       # Class native methods
    "jdk_internal_misc_",    # JDK internals
    "sun_misc_Unsafe",       # Legacy Unsafe
    "JVM_Register",          # JVM registration functions
]

java["compiler_reserved"] = [
    # VM Intrinsics (IR SPEC §9)
    "JVM_I2D",
    "JVM_F2I",
    "JVM_D2L",
    "JVM_L2D",
    "JVM_ArrayCopy",
    "JVM_CurrentThread",
    "JVM_GetArrayLength",
    # GC barrier nodes (IR SPEC §8)
    "Shenandoah",
    "MemBar",
    "Opaque1",
    "OpaqueLoopInit",
    "OpaqueLoopStride",
]

java["runtime_reserved"] = [
    # JVM core (IR SPEC §8)
    "JVM_FindClassFromCaller",
    "JVM_GetCallerClass",
    "JVM_CurrentThread",
    "JVM_ArrayCopy",
    "JVM_GetArrayLength",
    "JVM_NewArray",
    "JVM_NewMultiArray",
    "JVM_GetComponentType",
    # Memory barriers
    "MemBarAcquire",
    "MemBarRelease",
    "MemBarVolatile",
    "MemBarCPUOrder",
]

java["ffi_boundary_patterns"] = [
    # JNI (IR SPEC §8)
    "Java_",
    "JNI_",
    # Panama FFM (IR SPEC §8)
    "_downcall_stub_",
    "_upcall_stub_",
    # Unsafe memory (IR SPEC §8)
    "copyMemory0",
    "setMemory0",
    "allocateInstance",
    # JVM registration
    "JVM_RegisterJDKInternalMiscUnsafeMethods",
    "JVM_RegisterMethodHandleMethods",
]

java["unsafe_memory_patterns"] = [
    # Unsafe operations (IR SPEC §8) - already partially defined, extend
    "_getReference",
    "_getInt",
    "_putReference",
    "_putInt",
    "_getReferenceVolatile",
    "_getIntVolatile",
    "_putReferenceVolatile",
    "_putIntVolatile",
    "_getReferenceOpaque",
    "_getIntOpaque",
    "_putReferenceOpaque",
    "_putIntOpaque",
    "_getReferenceAcquire",
    "_putReferenceRelease",
    "_compareAndSetReference",
    "_compareAndExchangeReference",
    "_compareAndSetInt",
    "_copyMemory0",
    "_setMemory0",
    "_allocateInstance",
    "_allocateUninitializedArray",
]

java["fp_suppression"] = [
    {"pattern": "JVM_", "match_type": "prefix", "reason": "JVM runtime - compiler infrastructure (IR SPEC §8)"},
    {"pattern": "java_lang_", "match_type": "prefix", "reason": "Java lang native - standard library (IR SPEC §8)"},
    {"pattern": "jdk_internal_misc_Unsafe", "match_type": "prefix", "reason": "JDK Unsafe internals (IR SPEC §8)"},
    {"pattern": "sun_misc_", "match_type": "prefix", "reason": "Legacy sun.misc (IR SPEC §8)"},
    {"pattern": "MemBar", "match_type": "prefix", "reason": "Memory barrier node - compiler infrastructure (IR SPEC §8)"},
    {"pattern": "Shenandoah", "match_type": "prefix", "reason": "Shenandoah GC barrier - compiler infrastructure (IR SPEC §8)"},
    {"pattern": "Opaque", "match_type": "prefix", "reason": "Opaque node - compiler optimization control (IR SPEC §8)"},
]

java["description"] = "Java/JDK FFI boundary patterns - JNI, Panama FFM, Unsafe memory access (ref: JDK_IR_SPEC.md)"
save_json(f"{CONFIG_DIR}/java.json", java)
print("java.json updated")

# ============================================================================
# Python - Ref: docs/PYTHON_IR_SPEC.md
# ============================================================================
python_config = {
    "language": "python",
    "version": "1.0",
    "description": "Python/C extension FFI boundary patterns - reference counting, GC, buffer protocol, PyCapsule (ref: PYTHON_IR_SPEC.md)",
    "functions": [
        {"pattern": "Py_INCREF", "match_type": "exact", "kind": "refcount_inc", "severity": "medium", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Increment reference count (IR SPEC §1.2)"},
        {"pattern": "Py_DECREF", "match_type": "exact", "kind": "refcount_dec", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Decrement reference count - consumes ownership (IR SPEC §1.2)"},
        {"pattern": "Py_XDECREF", "match_type": "exact", "kind": "refcount_dec", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "NULL-safe decref - consumes ownership (IR SPEC §1.2)"},
        {"pattern": "Py_XINCREF", "match_type": "exact", "kind": "refcount_inc", "severity": "low", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "NULL-safe incref (IR SPEC §1.2)"},
        {"pattern": "Py_NewRef", "match_type": "exact", "kind": "allocator", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Create new owned reference (IR SPEC §1.2)"},
        {"pattern": "Py_CLEAR", "match_type": "exact", "kind": "refcount_dec", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Clear reference - sets NULL then decref (IR SPEC §1.2)"},
        {"pattern": "PyObject_New", "match_type": "prefix", "kind": "allocator", "severity": "high", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Allocate Python object (IR SPEC §3)"},
        {"pattern": "PyObject_GC_New", "match_type": "prefix", "kind": "allocator", "severity": "high", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Allocate GC-tracked Python object (IR SPEC §3)"},
        {"pattern": "PyInit_", "match_type": "prefix", "kind": "module_init", "severity": "medium", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "C extension module init function (IR SPEC §5)"},
        {"pattern": "PyArg_ParseTuple", "match_type": "prefix", "kind": "arg_parse", "severity": "medium", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": True, "description": "Parse Python args in C extension (IR SPEC §5)"},
        {"pattern": "Py_BuildValue", "match_type": "prefix", "kind": "value_build", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Build Python value from C (IR SPEC §5)"},
        {"pattern": "PyCapsule_", "match_type": "prefix", "kind": "capsule", "severity": "high", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "PyCapsule opaque pointer wrapping (IR SPEC §7)"},
        {"pattern": "PyObject_GetBuffer", "match_type": "exact", "kind": "buffer", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Get buffer view - must PyBuffer_Release (IR SPEC §6)"},
        {"pattern": "PyBuffer_Release", "match_type": "exact", "kind": "buffer", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Release buffer view (IR SPEC §6)"},
    ],
    "stdlib_prefixes": [
        "Py",       # Public Python C API
        "_Py",      # Internal Python C API (IR SPEC §10)
    ],
    "noise_prefixes": [
        # CPython internal runtime (IR SPEC §8, §10)
        "_PyRuntime",
        "_PyInterpreter",
        "_PyThread",
        "_PyStackRef",
        "_Py_CODEUNIT",
        "_Py_IDENTIFIER",
        "_Py_static_string",
        # GC internals (IR SPEC §4)
        "update_refs",
        "subtract_refs",
        "move_unreachable",
        "_PyObject_ClearFreeLists",
        "_PyRuntimeState_Init",
        "_PyGC_Init",
        # Dealloc internals (IR SPEC §11)
        "_Py_Dealloc",
        "_PyTrash_",
        "_Py_ForgetReference",
        "_PyReftracerTrack",
    ],
    "compiler_reserved": [
        # Internal API (IR SPEC §8, §10)
        "_Py_",
        "_PyRuntime",
        "_PyRuntimeState",
        "_PyInterpreterState",
        "_PyThreadState",
        "_PyStackRef",
        "_Py_CODEUNIT",
        "_Py_Dealloc",
        "_PyTrash_thread_deposit_object",
        "_PyTrash_thread_destroy_chain",
        # Immortal object checks
        "_Py_IsImmortal",
        "_Py_IsStaticImmortal",
        "_Py_IMMORTAL",
    ],
    "ffi_boundary_patterns": [
        # Reference count boundary (IR SPEC §10)
        "Py_INCREF",
        "Py_DECREF",
        "Py_XDECREF",
        "Py_XINCREF",
        "Py_NewRef",
        "Py_CLEAR",
        # Allocation boundary (IR SPEC §3)
        "PyObject_New",
        "PyObject_GC_New",
        "PyObject_Malloc",
        "PyObject_Free",
        # Buffer protocol (IR SPEC §6)
        "PyObject_GetBuffer",
        "PyBuffer_Release",
        # Capsule (IR SPEC §7)
        "PyCapsule_New",
        "PyCapsule_GetPointer",
        "PyCapsule_SetDestructor",
        # Module init (IR SPEC §5)
        "PyInit_",
        # Argument parsing
        "PyArg_ParseTuple",
        "Py_BuildValue",
    ],
    "refcount_bug_patterns": [
        {"bug": "double_decref", "description": "Py_DECREF twice without intervening Py_INCREF (IR SPEC §10)"},
        {"bug": "missing_decref", "description": "Owning reference not Py_DECREF'd before return (IR SPEC §10)"},
        {"bug": "borrowed_escape", "description": "Returning/storing borrowed reference beyond lifetime (IR SPEC §10)"},
        {"bug": "stolen_misuse", "description": "Py_DECREF on reference already stolen by PyTuple_SetItem (IR SPEC §10)"},
        {"bug": "null_deref", "description": "Not checking NULL from allocation/API functions (IR SPEC §10)"},
        {"bug": "use_after_decref", "description": "Accessing object after Py_DECREF when refcount may reach 0 (IR SPEC §10)"},
        {"bug": "missing_gc_visit", "description": "Failing to visit all objects in tp_traverse (IR SPEC §10)"},
        {"bug": "buffer_release_omission", "description": "Failing to call PyBuffer_Release after PyObject_GetBuffer (IR SPEC §10)"},
    ],
    "fp_suppression": [
        {"pattern": "_Py_Dealloc", "match_type": "prefix", "reason": "CPython dealloc plumbing - runtime infrastructure (IR SPEC §10)"},
        {"pattern": "_PyStackRef", "match_type": "prefix", "reason": "Eval loop internals - runtime infrastructure (IR SPEC §10)"},
        {"pattern": "_PyRuntime", "match_type": "prefix", "reason": "Runtime state management (IR SPEC §8)"},
        {"pattern": "_PyInterpreter", "match_type": "prefix", "reason": "Interpreter state management (IR SPEC §8)"},
        {"pattern": "_PyTrash_", "match_type": "prefix", "reason": "Trashcan mechanism - runtime plumbing (IR SPEC §9.2)"},
        {"pattern": "_Py_ForgetReference", "match_type": "prefix", "reason": "Reference tracking - debug infrastructure (IR SPEC §11)"},
        {"pattern": "_Py_IsImmortal", "match_type": "prefix", "reason": "Immortal object check - optimization (IR SPEC §1.3)"},
        {"pattern": "_PyObject_ClearFreeLists", "match_type": "prefix", "reason": "Free list management - allocator internals (IR SPEC §10)"},
    ],
    "escape_patterns": [
        "Py_INCREF",
        "Py_DECREF",
        "Py_XDECREF",
        "Py_NewRef",
        "Py_CLEAR",
        "PyObject_GetBuffer",
        "PyCapsule_New",
        "PyInit_",
    ],
}
save_json(f"{CONFIG_DIR}/python.json", python_config)
print("python.json created")

# ============================================================================
# Swift - Ref: docs/SWIFT_IR_SPEC.md
# ============================================================================
swift_config = {
    "language": "swift",
    "version": "1.0",
    "description": "Swift language FFI boundary patterns - ARC, ObjC interop, metadata, concurrency (ref: SWIFT_IR_SPEC.md)",
    "functions": [
        # ARC operations (IR SPEC §2)
        {"pattern": "swift_retain", "match_type": "prefix", "kind": "arc_retain", "severity": "medium", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Swift ARC retain - increment refcount (IR SPEC §2.1)"},
        {"pattern": "swift_release", "match_type": "prefix", "kind": "arc_release", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Swift ARC release - decrement refcount (IR SPEC §2.1)"},
        {"pattern": "swift_allocObject", "match_type": "prefix", "kind": "allocator", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Swift heap allocation (IR SPEC §2.6)"},
        {"pattern": "swift_deallocObject", "match_type": "prefix", "kind": "deallocator", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "Swift heap deallocation (IR SPEC §2.6)"},
        # ObjC interop (IR SPEC §9)
        {"pattern": "objc_msgSend", "match_type": "prefix", "kind": "objc_msg", "severity": "medium", "consumes_ownership": False, "transfers_ownership": False, "requires_null_check": True, "requires_taint_check": False, "description": "Objective-C message dispatch (IR SPEC §9.1)"},
        {"pattern": "objc_allocWithZone", "match_type": "exact", "kind": "allocator", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "Objective-C allocation (IR SPEC §9.1)"},
        {"pattern": "_Block_copy", "match_type": "exact", "kind": "block_copy", "severity": "medium", "consumes_ownership": False, "transfers_ownership": True, "requires_null_check": True, "requires_taint_check": False, "description": "ObjC block copy (IR SPEC §9.2)"},
        {"pattern": "_Block_release", "match_type": "exact", "kind": "block_release", "severity": "high", "consumes_ownership": True, "transfers_ownership": False, "requires_null_check": False, "requires_taint_check": False, "description": "ObjC block release (IR SPEC §9.2)"},
    ],
    "stdlib_prefixes": [
        # Swift stdlib module (IR SPEC §1.4)
        "$sSq",        # Optional<...>
        "$ss5NeverO",  # Never type
        "$sSa",        # Array
        "$sSb",        # Bool
        "$sSi",        # Int
        "$sSd",        # Double
        "$sSS",        # String
    ],
    "noise_prefixes": [
        # ARC runtime (IR SPEC §2, §14)
        "swift_retain",
        "swift_release",
        "swift_nonatomic_retain",
        "swift_nonatomic_release",
        "swift_unknownObjectRetain",
        "swift_unknownObjectRelease",
        "swift_bridgeObjectRetain",
        "swift_bridgeObjectRelease",
        "swift_errorRetain",
        "swift_errorRelease",
        "swift_weak",
        "swift_unowned",
        # Metadata (IR SPEC §4)
        "swift_get",
        "swift_init",
        "swift_checkMetadata",
        "swift_allocateGeneric",
        # Casting (IR SPEC §3)
        "swift_dynamicCast",
        "swift_conformsToProtocol",
        # Witness tables (IR SPEC §5, §6)
        "swift_getWitnessTable",
        "swift_getAssociatedTypeWitness",
        "swift_cvw_",
        # Enum (IR SPEC §7)
        "swift_getEnumTag",
        "swift_storeEnumTag",
        # Concurrency (IR SPEC §11)
        "swift_task",
        "swift_defaultActor",
        "swift_continuation",
        "swift_taskGroup",
        "swift_asyncLet",
        # Exclusivity (IR SPEC §12)
        "swift_beginAccess",
        "swift_endAccess",
        # Registration (IR SPEC §13)
        "swift_once",
        "swift_register",
        # Array ops (IR SPEC §2.8)
        "swift_arrayInit",
        "swift_arrayAssign",
        "swift_arrayDestroy",
        # COW (IR SPEC §2.7)
        "swift_isUniquelyReferenced",
        "swift_isEscapingClosure",
    ],
    "compiler_reserved": [
        # Swift mangling prefixes (IR SPEC §1.1)
        "$s",         # Swift 5+ mangled
        "_$s",        # Swift 5+ mangled (underscore)
        "$S",         # Swift 4.x mangled
        "_$S",        # Swift 4.x mangled (underscore)
        "_T0",        # Swift 4 mangled
        "$e",         # Embedded Swift mangled
        "_$e",        # Embedded Swift mangled (underscore)
        "@__swiftmacro_",  # Swift macro (IR SPEC §1.1)
        # Allocation (IR SPEC §2.6)
        "swift_slowAlloc",
        "swift_slowDealloc",
        "swift_initStackObject",
        "swift_initStaticObject",
        "swift_allocBox",
        "swift_deallocBox",
        "swift_projectBox",
        "swift_allocEmptyBox",
    ],
    "runtime_reserved": [
        # ARC (IR SPEC §2)
        "swift_retain",
        "swift_release",
        "swift_allocObject",
        "swift_deallocObject",
        "swift_deallocClassInstance",
        "swift_deallocPartialClassInstance",
        "swift_deallocUninitializedObject",
        # Metadata (IR SPEC §4)
        "swift_getTypeByMangledNameInContextInMetadataState",
        "swift_getMetadataAccessReport",
        "swift_initClassMetadata",
        "swift_initStructMetadata",
        "swift_initEnumMetadata",
        "swift_allocateGenericClassMetadata",
        "swift_allocateGenericStructMetadata",
        "swift_allocateGenericEnumMetadata",
        # Casting (IR SPEC §3)
        "swift_dynamicCast",
        "swift_dynamicCastObjCClass",
        "swift_conformsToProtocol",
        # Witness (IR SPEC §5, §6)
        "swift_getWitnessTable",
        "swift_getAssociatedTypeWitness",
        "swift_getAssociatedConformanceWitness",
        # Error (IR SPEC §8)
        "swift_allocError",
        "swift_deallocError",
        "swift_willThrow",
        "swift_errorRetain",
        "swift_errorRelease",
        # Concurrency (IR SPEC §11)
        "swift_task_create",
        "swift_task_switch",
        "swift_task_destroy",
        # Exclusivity (IR SPEC §12)
        "swift_beginAccess",
        "swift_endAccess",
    ],
    "ffi_boundary_patterns": [
        # ObjC runtime (IR SPEC §9.1)
        "objc_msgSend",
        "objc_allocWithZone",
        "objc_getClass",
        "object_getClass",
        "sel_registerName",
        "class_",
        "protocol_",
        # Bridge (IR SPEC §9.3)
        "swift_bridgeObjectRetain",
        "swift_bridgeObjectRelease",
        "swift_unknownObjectRetain",
        "swift_unknownObjectRelease",
        # Blocks (IR SPEC §9.2)
        "_Block_copy",
        "_Block_release",
        # C interop
        "malloc",
        "free",
    ],
    "arc_safety_patterns": [
        {"bug": "retain_release_imbalance", "description": "swift_retain without matching swift_release on all paths (IR SPEC §14)"},
        {"bug": "retain_cycle", "description": "Strong reference cycle especially closures capturing self (IR SPEC §14)"},
        {"bug": "use_after_release", "description": "Access after swift_release when refcount reaches 0 (IR SPEC §14)"},
        {"bug": "weak_null_deref", "description": "swift_weakLoadStrong returns null; must handle nil (IR SPEC §14)"},
        {"bug": "unowned_use_after_free", "description": "Accessing unowned ref after deallocation is UB (IR SPEC §14)"},
        {"bug": "bridge_object_lifecycle", "description": "Bridge objects have dual refcounting (Swift + ObjC) (IR SPEC §14)"},
    ],
    "fp_suppression": [
        {"pattern": "swift_retain", "match_type": "prefix", "reason": "ARC runtime - compiler infrastructure (IR SPEC §2)"},
        {"pattern": "swift_release", "match_type": "prefix", "reason": "ARC runtime - compiler infrastructure (IR SPEC §2)"},
        {"pattern": "swift_get", "match_type": "prefix", "reason": "Swift metadata/casting - compiler infrastructure (IR SPEC §3, §4)"},
        {"pattern": "swift_init", "match_type": "prefix", "reason": "Swift metadata init - compiler infrastructure (IR SPEC §4)"},
        {"pattern": "swift_cvw_", "match_type": "prefix", "reason": "Value witness - compiler infrastructure (IR SPEC §6)"},
        {"pattern": "swift_getWitnessTable", "match_type": "prefix", "reason": "Witness table - compiler infrastructure (IR SPEC §5)"},
        {"pattern": "swift_getEnumTag", "match_type": "prefix", "reason": "Enum tag operation - compiler infrastructure (IR SPEC §7)"},
        {"pattern": "swift_storeEnumTag", "match_type": "prefix", "reason": "Enum tag operation - compiler infrastructure (IR SPEC §7)"},
        {"pattern": "swift_task", "match_type": "prefix", "reason": "Swift concurrency runtime - compiler infrastructure (IR SPEC §11)"},
        {"pattern": "swift_beginAccess", "match_type": "prefix", "reason": "Exclusivity check - compiler infrastructure (IR SPEC §12)"},
        {"pattern": "swift_endAccess", "match_type": "prefix", "reason": "Exclusivity check - compiler infrastructure (IR SPEC §12)"},
        {"pattern": "swift_once", "match_type": "prefix", "reason": "One-time init - compiler infrastructure (IR SPEC §13)"},
        {"pattern": "swift_register", "match_type": "prefix", "reason": "Runtime registration - compiler infrastructure (IR SPEC §13)"},
        {"pattern": "swift_arrayInit", "match_type": "prefix", "reason": "Array value ops - compiler infrastructure (IR SPEC §2.8)"},
        {"pattern": "swift_arrayAssign", "match_type": "prefix", "reason": "Array value ops - compiler infrastructure (IR SPEC §2.8)"},
        {"pattern": "swift_arrayDestroy", "match_type": "exact", "reason": "Array destroy - compiler infrastructure (IR SPEC §2.8)"},
        {"pattern": "swift_isUniquelyReferenced", "match_type": "prefix", "reason": "COW check - compiler infrastructure (IR SPEC §2.7)"},
    ],
    "escape_patterns": [
        "objc_msgSend",
        "objc_allocWithZone",
        "_Block_copy",
        "_Block_release",
        "swift_bridgeObjectRetain",
        "swift_bridgeObjectRelease",
        "swift_allocObject",
        "swift_deallocObject",
    ],
}
save_json(f"{CONFIG_DIR}/swift.json", swift_config)
print("swift.json created")

print("\nAll language configs updated successfully!")
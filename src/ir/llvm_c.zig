//! LLVM-C API bindings for OmniScope
//!
//! This file contains extern declarations for LLVM-C API functions.
//! Only the minimal set needed for the first phase is included.

const std = @import("std");

// LLVM opaque types
pub const LLVMContextRef = *opaque {};
pub const LLVMModuleRef = *opaque {};
pub const LLVMValueRef = *opaque {};
pub const LLVMBasicBlockRef = *opaque {};
pub const LLVMBuilderRef = *opaque {};
pub const LLVMMemoryBufferRef = *opaque {};

// LLVM-C API declarations
// Context
pub extern fn LLVMContextCreate() LLVMContextRef;
pub extern fn LLVMContextDispose(ctx: LLVMContextRef) void;

// Module
pub extern fn LLVMParseIRInContext(
    ctx: LLVMContextRef,
    mem_buf: LLVMMemoryBufferRef,
    out_msg: *[*:0]u8,
) LLVMModuleRef;
pub extern fn LLVMParseBitcodeInContext2(
    ctx: LLVMContextRef,
    mem_buf: LLVMMemoryBufferRef,
    out_module: *LLVMModuleRef,
) c_int;
pub extern fn LLVMDisposeModule(module: LLVMModuleRef) void;

// Memory buffer
pub extern fn LLVMCreateMemoryBufferWithContentsOfFile(
    path: [*:0]const u8,
    out_mem_buf: *LLVMMemoryBufferRef,
    out_msg: *[*:0]u8,
) c_int;
pub extern fn LLVMDisposeMemoryBuffer(mem_buf: LLVMMemoryBufferRef) void;

// Value operations
pub extern fn LLVMGetValueName(value: LLVMValueRef) [*:0]const u8;
pub extern fn LLVMGetInstructionOpcode(inst: LLVMValueRef) c_uint;
pub extern fn LLVMGetNextInstruction(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetPreviousInstruction(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMGetInstructionParent(inst: LLVMValueRef) LLVMBasicBlockRef;

// Basic block operations
pub extern fn LLVMGetBasicBlocks(function: LLVMValueRef) *LLVMBasicBlockRef;
pub extern fn LLVMGetNextBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
pub extern fn LLVMGetPreviousBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
pub extern fn LLVMGetBasicBlockName(bb: LLVMBasicBlockRef) [*:0]const u8;
pub extern fn LLVMGetFirstBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;
pub extern fn LLVMGetLastBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;
pub extern fn LLVMGetFirstInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
pub extern fn LLVMGetLastInstruction(bb: LLVMBasicBlockRef) LLVMValueRef;
pub extern fn LLVMGetBasicBlockTerminator(bb: LLVMBasicBlockRef) LLVMValueRef;

// Function operations
pub extern fn LLVMGetFirstFunction(module: LLVMModuleRef) LLVMValueRef;
pub extern fn LLVMGetNextFunction(func: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMIsAFunction(val: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMCountBasicBlocks(func_val: LLVMValueRef) c_uint;

// Instruction operations
pub extern fn LLVMGetOperand(inst: LLVMValueRef, index: c_uint) LLVMValueRef;
pub extern fn LLVMGetNumOperands(inst: LLVMValueRef) c_uint;
pub extern fn LLVMIsAPHINode(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMIsACallInst(inst: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMCountIncoming(phi: LLVMValueRef) c_uint;
pub extern fn LLVMGetIncomingValue(phi: LLVMValueRef, index: c_uint) LLVMValueRef;
pub extern fn LLVMGetIncomingBlock(phi: LLVMValueRef, index: c_uint) LLVMBasicBlockRef;
pub extern fn LLVMGetNumSuccessors(term: LLVMValueRef) c_uint;
pub extern fn LLVMGetSuccessor(term: LLVMValueRef, index: c_uint) LLVMBasicBlockRef;

// Instruction opcodes
pub const LLVMOpcode = enum(c_uint) {
    Ret = 1,
    Br = 2,
    Switch = 3,
    IndirectBr = 4,
    Invoke = 5,
    Call = 6,
    CallBr = 66,
    Alloca = 7,
    Load = 8,
    Store = 9,
    GetElementPtr = 10,
    Fence = 11,
    AtomicCmpXchg = 12,
    AtomicRMW = 13,
    BitCast = 34,
    AddrSpaceCast = 60,
};

// Type operations
pub const LLVMTypeRef = *opaque {};
pub extern fn LLVMTypeOf(val: LLVMValueRef) LLVMTypeRef;
pub extern fn LLVMGetElementType(ptr_type: LLVMTypeRef) LLVMTypeRef;
pub extern fn LLVMGetPointerAddressSpace(ptr_type: LLVMTypeRef) c_uint;
pub extern fn LLVMGetTypeKind(ty: LLVMTypeRef) LLVMTypeKind;

// Type kind enumeration
pub const LLVMTypeKind = enum(c_uint) {
    Void = 0,
    Half = 1,
    Float = 2,
    Double = 3,
    X86_FP80 = 4,
    FP128 = 5,
    PPC_FP128 = 6,
    Label = 7,
    Integer = 8,
    Function = 9,
    Struct = 10,
    Array = 11,
    Pointer = 12,
    Vector = 13,
    Metadata = 14,
    X86_MMX = 15,
    Token = 16,
    ScalableVector = 17,
    BFloat = 18,
    X86_AMX = 19,
};

// Metadata operations
pub const LLVMMetadataRef = *opaque {};
pub extern fn LLVMGetMDKindIDInContext(ctx: LLVMContextRef, name: [*:0]const u8, slen: c_uint) c_uint;
pub extern fn LLVMGetMetadata(val: LLVMValueRef, kind_id: c_uint) LLVMMetadataRef;
pub extern fn LLVMGetInstructionDebugLoc(inst: LLVMValueRef) LLVMMetadataRef;
pub extern fn LLVMGetMDNodeNumOperands(md: LLVMMetadataRef) c_uint;
pub extern fn LLVMGetMDNodeOperands(md: LLVMMetadataRef, dest: [*]LLVMMetadataRef) void;
pub extern fn LLVMGetCalledValue(call: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMIsDeclaration(func: LLVMValueRef) c_uint;

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
extern fn LLVMContextCreate() LLVMContextRef;
extern fn LLVMContextDispose(ctx: LLVMContextRef) void;

// Module
extern fn LLVMParseIRInContext(
    ctx: LLVMContextRef,
    mem_buf: LLVMMemoryBufferRef,
    out_msg: *[*:0]u8,
) LLVMModuleRef;
extern fn LLVMDisposeModule(module: LLVMModuleRef) void;

// Memory buffer
extern fn LLVMCreateMemoryBufferWithContentsOfFile(
    path: [*:0]const u8,
    out_mem_buf: *LLVMMemoryBufferRef,
    out_msg: *[*:0]u8,
) c_int;
extern fn LLVMDisposeMemoryBuffer(mem_buf: LLVMMemoryBufferRef) void;

// Value operations
extern fn LLVMGetValueName(value: LLVMValueRef) [*:0]const u8;
extern fn LLVMGetInstructionOpcode(inst: LLVMValueRef) c_uint;
extern fn LLVMGetNextInstruction(inst: LLVMValueRef) LLVMValueRef;
extern fn LLVMGetPreviousInstruction(inst: LLVMValueRef) LLVMValueRef;
extern fn LLVMGetInstructionParent(inst: LLVMValueRef) LLVMBasicBlockRef;

// Basic block operations
extern fn LLVMGetBasicBlocks(function: LLVMValueRef) *LLVMBasicBlockRef;
extern fn LLVMGetNextBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
extern fn LLVMGetPreviousBasicBlock(bb: LLVMBasicBlockRef) LLVMBasicBlockRef;
extern fn LLVMGetBasicBlockName(bb: LLVMBasicBlockRef) [*:0]const u8;
extern fn LLVMGetFirstBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;
extern fn LLVMGetLastBasicBlock(function: LLVMValueRef) LLVMBasicBlockRef;

// Function operations
extern fn LLVMGetFirstFunction(module: LLVMModuleRef) LLVMValueRef;
extern fn LLVMGetNextFunction(func: LLVMValueRef) LLVMValueRef;
extern fn LLVMIsAFunction(val: LLVMValueRef) LLVMValueRef;
extern fn LLVMCountBasicBlocks(func_val: LLVMValueRef) c_uint;

// Instruction operations
extern fn LLVMGetOperand(inst: LLVMValueRef, index: c_uint) LLVMValueRef;
extern fn LLVMGetNumOperands(inst: LLVMValueRef) c_uint;
extern fn LLVMIsAPHINode(inst: LLVMValueRef) LLVMValueRef;
extern fn LLVMCountIncoming(phi: LLVMValueRef) c_uint;
extern fn LLVMGetIncomingValue(phi: LLVMValueRef, index: c_uint) LLVMValueRef;
extern fn LLVMGetIncomingBlock(phi: LLVMValueRef, index: c_uint) LLVMBasicBlockRef;

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

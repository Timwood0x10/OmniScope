//! Temporary compatibility layer for gradual migration from hand-written bindings
//! 
//! This file provides compatibility while migrating to @cImport-based bindings.
//! Eventually this will be removed.

const std = @import("std");
const c = @import("llvm_raw.zig").c;

// Re-export commonly used types for compatibility
pub const LLVMContextRef = c.LLVMContextRef;
pub const LLVMModuleRef = c.LLVMModuleRef;
pub const LLVMValueRef = c.LLVMValueRef;
pub const LLVMBasicBlockRef = c.LLVMBasicBlockRef;
pub const LLVMBuilderRef = c.LLVMBuilderRef;
pub const LLVMMemoryBufferRef = c.LLVMMemoryBufferRef;
pub const LLVMTypeRef = c.LLVMTypeRef;
pub const LLVMMetadataRef = c.LLVMMetadataRef;
pub const LLVMDIBuilderRef = c.LLVMDIBuilderRef;

// Re-export functions from c namespace
pub const LLVMContextCreate = c.LLVMContextCreate;
pub const LLVMContextDispose = c.LLVMContextDispose;
pub const LLVMParseIRInContext = c.LLVMParseIRInContext;
pub const LLVMParseBitcodeInContext2 = c.LLVMParseBitcodeInContext2;
pub const LLVMDisposeModule = c.LLVMDisposeModule;
pub const LLVMCreateMemoryBufferWithContentsOfFile = c.LLVMCreateMemoryBufferWithContentsOfFile;
pub const LLVMDisposeMemoryBuffer = c.LLVMDisposeMemoryBuffer;
pub const LLVMDisposeMessage = c.LLVMDisposeMessage;
pub const LLVMGetValueName = c.LLVMGetValueName;
pub const LLVMGetInstructionOpcode = c.LLVMGetInstructionOpcode;
pub const LLVMGetNextInstruction = c.LLVMGetNextInstruction;
pub const LLVMGetPreviousInstruction = c.LLVMGetPreviousInstruction;
pub const LLVMGetInstructionParent = c.LLVMGetInstructionParent;
pub const LLVMGetBasicBlocks = c.LLVMGetBasicBlocks;
pub const LLVMGetNextBasicBlock = c.LLVMGetNextBasicBlock;
pub const LLVMGetPreviousBasicBlock = c.LLVMGetPreviousBasicBlock;
pub const LLVMGetBasicBlockName = c.LLVMGetBasicBlockName;
pub const LLVMGetFirstBasicBlock = c.LLVMGetFirstBasicBlock;
pub const LLVMGetLastBasicBlock = c.LLVMGetLastBasicBlock;
pub const LLVMGetFirstInstruction = c.LLVMGetFirstInstruction;
pub const LLVMGetLastInstruction = c.LLVMGetLastInstruction;
pub const LLVMGetBasicBlockTerminator = c.LLVMGetBasicBlockTerminator;
pub const LLVMGetFirstFunction = c.LLVMGetFirstFunction;
pub const LLVMGetNextFunction = c.LLVMGetNextFunction;
pub const LLVMIsAFunction = c.LLVMIsAFunction;
pub const LLVMCountBasicBlocks = c.LLVMCountBasicBlocks;
pub const LLVMGetOperand = c.LLVMGetOperand;
pub const LLVMGetNumOperands = c.LLVMGetNumOperands;
pub const LLVMIsAPHINode = c.LLVMIsAPHINode;
pub const LLVMIsACallInst = c.LLVMIsACallInst;
pub const LLVMCountIncoming = c.LLVMCountIncoming;
pub const LLVMGetIncomingValue = c.LLVMGetIncomingValue;
pub const LLVMGetIncomingBlock = c.LLVMGetIncomingBlock;
pub const LLVMGetNumSuccessors = c.LLVMGetNumSuccessors;
pub const LLVMGetSuccessor = c.LLVMGetSuccessor;
pub const LLVMTypeOf = c.LLVMTypeOf;
pub const LLVMGetElementType = c.LLVMGetElementType;
pub const LLVMGetPointerAddressSpace = c.LLVMGetPointerAddressSpace;
pub const LLVMGetTypeKind = c.LLVMGetTypeKind;
pub const LLVMGetMDKindIDInContext = c.LLVMGetMDKindIDInContext;
pub const LLVMGetMetadata = c.LLVMGetMetadata;
pub const LLVMGetInstructionDebugLoc = c.LLVMGetInstructionDebugLoc;
pub const LLVMGetMDNodeNumOperands = c.LLVMGetMDNodeOperands;
pub const LLVMGetMDNodeOperands = c.LLVMGetMDNodeOperands;
pub const LLVMGetCalledValue = c.LLVMGetCalledValue;
pub const LLVMIsDeclaration = c.LLVMIsDeclaration;

// Re-export enums
pub const LLVMOpcode = c.LLVMOpcode;
pub const LLVMTypeKind = c.LLVMTypeKind;


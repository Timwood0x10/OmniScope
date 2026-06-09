const c = @import("../ir/llvm_raw.zig").c;

pub const OwnershipTransfer = enum(u8) {
    none,
    to_callee,
    to_caller,
};

pub const FFICallSite = struct {
    caller_func: c.LLVMValueRef,
    call_inst: c.LLVMValueRef,
    callee_name: []const u8,
    result_used: bool,
    has_null_guard: bool,
    ownership_transfer: OwnershipTransfer,

    pub fn init(
        caller_func: c.LLVMValueRef,
        call_inst: c.LLVMValueRef,
        callee_name: []const u8,
    ) FFICallSite {
        return .{
            .caller_func = caller_func,
            .call_inst = call_inst,
            .callee_name = callee_name,
            .result_used = false,
            .has_null_guard = false,
            .ownership_transfer = .none,
        };
    }
};

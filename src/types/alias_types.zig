const c = @import("../ir/llvm_raw.zig").c;

pub const PointerInfo = struct {
    value: c.LLVMValueRef,
    type_id: u32,
    inst_id: u32,
};

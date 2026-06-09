const std = @import("std");

pub const TypeGuard = struct {
    pub fn isLLVMIntrinsic(func_name: []const u8) bool {
        const intrinsic_prefixes = [_][]const u8{
            "llvm.",
            "core::arch::",
            "simd_",
            "__builtin_",
            "_mm_",
            "__v",
            "vec_",
        };
        for (intrinsic_prefixes) |prefix| {
            if (startsWith(func_name, prefix)) return true;
        }
        return false;
    }

    pub fn isPointerLikeType(type_name: ?[]const u8) bool {
        if (type_name == null) return true;
        const tn = type_name.?;
        const non_pointer_patterns = [_][]const u8{
            "i32",  "i64",      "i16",    "i8",
            "u32",  "u64",      "u16",    "u8",
            "int",  "unsigned", "long",   "short",
            "char", "float",    "double", "bool",
            "void", "struct ",  "<",
        };
        for (non_pointer_patterns) |pat| {
            if (std.mem.indexOf(u8, tn, pat) != null) return false;
        }
        const pointer_patterns = [_][]const u8{
            "*",   "ptr",   "pointer", "ref", "handle",
            "i8*", "void*", "char*",
        };
        for (pointer_patterns) |pat| {
            if (std.mem.indexOf(u8, tn, pat) != null) return true;
        }
        return true;
    }
};

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}

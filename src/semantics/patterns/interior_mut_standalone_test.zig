//! Standalone test runner for interior_mut.zig pure functions
//!
//! This file duplicates the pure functions from interior_mut.zig
//! to enable testing without LLVM dependencies.
//! Run: zig test interior_mut_standalone_test.zig

const std = @import("std");

/// DI type name prefixes that indicate interior mutability (copied from interior_mut.zig)
const INTERIOR_MUT_PREFIXES = [_][]const u8{
    "UnsafeCell<",
    "core::cell::UnsafeCell<",
    "std::cell::UnsafeCell<",
};

/// Check if a DI type name indicates interior mutability (copied from interior_mut.zig)
fn isInteriorMutDIName(name: []const u8) bool {
    for (INTERIOR_MUT_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    if (std.mem.indexOf(u8, name, "UnsafeCell<") != null) return true;
    return false;
}

/// Recursively check DI type chain for UnsafeCell (copied from interior_mut.zig)
fn isInteriorMutableThroughChain(di_type_name: []const u8) bool {
    return isInteriorMutDIName(di_type_name);
}

// ============================================================
// Test Group A: Direct matches (currently supported)
// ============================================================

test "A.1: UnsafeCell<i32> — direct prefix match" {
    try std.testing.expectEqual(true, isInteriorMutDIName("UnsafeCell<i32>"));
}

test "A.2: core::cell::UnsafeCell<String> — qualified path" {
    try std.testing.expectEqual(true, isInteriorMutDIName("core::cell::UnsafeCell<String>"));
}

test "A.3: std::cell::UnsafeCell<Vec<u8>> — std path" {
    try std.testing.expectEqual(true, isInteriorMutDIName("std::cell::UnsafeCell<Vec<u8>>"));
}

test "A.4: RefCell<UnsafeCell<i32>> — contains match" {
    try std.testing.expectEqual(true, isInteriorMutDIName("RefCell<UnsafeCell<i32>>"));
}

test "A.5: isInteriorMutableThroughChain with direct UnsafeCell" {
    try std.testing.expectEqual(true, isInteriorMutableThroughChain("UnsafeCell<bool>"));
}

// ============================================================
// Test Group B: Common wrapper types [🔴 KNOWN BUGS]
// ============================================================

test "B.1: Cell<i32> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Cell<i32>"));
}

test "B.2: RefCell<String> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("RefCell<String>"));
}

test "B.3: Mutex<i32> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Mutex<i32>"));
}

test "B.4: RwLock<Vec<i32>> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("RwLock<Vec<i32>>"));
}

test "B.5: AtomicUsize — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("AtomicUsize"));
}

test "B.6: OnceLock<String> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("OnceLock<String>"));
}

test "B.7: LazyLock<MyStruct> — [🔴 BUG] should be true, currently false" {
    try std.testing.expectEqual(false, isInteriorMutDIName("LazyLock<MyStruct>"));
}

test "B.8: isInteriorMutableThroughChain with Cell — [🔴 BUG]" {
    try std.testing.expectEqual(false, isInteriorMutableThroughChain("Cell<i32>"));
}

// ============================================================
// Test Group C: Nested types
// ============================================================

test "C.1: Mutex<RefCell<UnsafeCell<i32>>> — triple nesting" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Mutex<RefCell<UnsafeCell<i32>>>"));
}

test "C.2: Vec<Cell<i32>> — [⚠️ TRICKY] Vec of interior-mutable elements" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Vec<Cell<i32>>"));
}

test "C.3: Option<UnsafeCell<bool>> — Option wrapping UnsafeCell" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Option<UnsafeCell<bool>>"));
}

test "C.4: Result<UnsafeCell<u8>, Error> — Result with UnsafeCell" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Result<UnsafeCell<u8>, Error>"));
}

test "C.5: Arc<Mutex<UnsafeCell<Data>>> — complex nesting" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Arc<Mutex<UnsafeCell<Data>>>"));
}

test "C.6: Box<RefCell<UnsafeCell<String>>> — Box + double wrapper" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Box<RefCell<UnsafeCell<String>>>"));
}

test "C.7: Vec<UnsafeCell<i32>> — Vec directly containing UnsafeCell" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Vec<UnsafeCell<i32>>"));
}

// ============================================================
// Test Group D: Non-interior-mutable types (should return false)
// ============================================================

test "D.1: String" {
    try std.testing.expectEqual(false, isInteriorMutDIName("String"));
}
test "D.2: Vec<i32>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Vec<i32>"));
}
test "D.3: Box<MyStruct>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Box<MyStruct>"));
}
test "D.4: &str" {
    try std.testing.expectEqual(false, isInteriorMutDIName("&str"));
}
test "D.5: HashMap<K, V>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("HashMap<K, V>"));
}
test "D.6: Option<String>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Option<String>"));
}
test "D.7: Result<u64, Error>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("Result<u64, Error>"));
}
test "D.8: [i32; 10]" {
    try std.testing.expectEqual(false, isInteriorMutDIName("[i32; 10]"));
}
test "D.9: MyCustomStruct" {
    try std.testing.expectEqual(false, isInteriorMutDIName("MyCustomStruct"));
}
test "D.10: ()" {
    try std.testing.expectEqual(false, isInteriorMutDIName("()"));
}

// ============================================================
// Test Group E: Edge cases and boundary conditions
// ============================================================

test "E.1: empty string" {
    try std.testing.expectEqual(false, isInteriorMutDIName(""));
}
test "E.2: UnsafeCell without <>" {
    try std.testing.expectEqual(false, isInteriorMutDIName("UnsafeCell"));
}
test "E.3: lowercase unsafecell" {
    try std.testing.expectEqual(false, isInteriorMutDIName("unsafecell<i32>"));
}
test "E.4: UNSAFECELL uppercase" {
    try std.testing.expectEqual(false, isInteriorMutDIName("UNSAFECELL<i32>"));
}
test "E.5: space before < [⚠️]" {
    try std.testing.expectEqual(false, isInteriorMutDIName("UnsafeCell <i32>"));
}
test "E.6: very long nested type" {
    try std.testing.expectEqual(true, isInteriorMutDIName("Arc<RwLock<HashMap<String, Box<RefCell<UnsafeCell<Vec<u8>>>>>>>"));
}
test "E.7: Wrapper<UnsafeCell<i32>> — [⚠️ FALSE POSITIVE PATTERN]" {
    // Documents that contains-match works on any occurrence of "UnsafeCell<"
    // In real DI metadata, this is usually correct behavior
    const name = "Wrapper<UnsafeCell<i32>>";
    try std.testing.expectEqual(true, isInteriorMutDIName(name));
}
test "E.8: isInteriorMutableThroughChain empty string" {
    try std.testing.expectEqual(false, isInteriorMutableThroughChain(""));
}
test "E.9: Unicode in type name" {
    try std.testing.expectEqual(true, isInteriorMutDIName("UnsafeCell<字符串>"));
}

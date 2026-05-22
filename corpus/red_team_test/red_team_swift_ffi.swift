import Foundation

// OmniScope Red Team — Swift FFI Boundary Bug Test Cases
//
// Simulates bugs that occur at Swift ↔ C/Objective-C FFI boundaries.
// Based on patterns from SWIFT_IR_SPEC.md:
//   - ARC retain/release imbalances
//   - Unowned/weak reference misuse
//   - @objc interop memory issues
//   - Protocol witness table corruption
//   - UnsafeMutableRawPointer misuse

// ================================================================
// FFI declarations — C functions Swift calls
// ================================================================

@_silgenName("c_ffi_alloc")
func c_ffi_alloc(_ size: Int) -> UnsafeMutableRawPointer?

@_silgenName("c_ffi_free")
func c_ffi_free(_ ptr: UnsafeMutableRawPointer)

@_silgenName("c_ffi_store_pointer")
func c_ffi_store_pointer(_ ptr: UnsafePointer<UInt8>)

@_silgenName("c_ffi_retrieve_pointer")
func c_ffi_retrieve_pointer() -> UnsafeMutablePointer<UInt8>

@_silgenName("c_ffi_register_callback")
func c_ffi_register_callback(_ cb: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void, _ ctx: UnsafeMutableRawPointer?)

// ================================================================
// SWIFT-BUG-01: Unowned reference to deallocated object
//
// Swift uses unowned references that don't keep objects alive.
// If the referenced object is deallocated, accessing unowned
// causes a crash (trap).
//
// Expected: use_after_free (CWE-416)
// ================================================================

class SwiftObject {
    var value: Int = 42
    deinit {
        print("SwiftObject deallocated")
    }
}

func swift_bug_01_unowned_uaf() {
    var obj: SwiftObject? = SwiftObject()
    unowned let unownedRef = obj!  // unowned reference

    obj = nil  // Deallocate the object

    // [BUG] Access unowned reference after deallocation
    // Swift runtime will trap (EXC_BAD_ACCESS)
    print("SWIFT-BUG-01: \(unownedRef.value)")
}

// ================================================================
// SWIFT-BUG-02: Weak reference race condition
//
// Weak reference becomes nil between the nil-check and use.
// In concurrent code, another thread may deallocate the object.
//
// Expected: use_after_free / race_condition
// ================================================================

func swift_bug_02_weak_race() {
    var obj: SwiftObject? = SwiftObject()
    weak var weakRef = obj

    // Another thread could set obj = nil here
    if let strong = weakRef {
        // [BUG] By the time we use 'strong', another thread
        // may have deallocated the original object
        print("SWIFT-BUG-02: \(strong.value)")
    }

    obj = nil
}

// ================================================================
// SWIFT-BUG-03: UnsafeMutableRawPointer use after deallocation
//
// Swift's unsafe pointers bypass ARC. Manual memory management
// errors (use-after-free, double-free) are possible.
//
// Expected: use_after_free (CWE-416)
// ================================================================

func swift_bug_03_raw_ptr_uaf() {
    let ptr = c_ffi_alloc(128)!

    // Write data
    let buf = ptr.bindMemory(to: UInt8.self, capacity: 128)
    buf[0] = 0x41

    // Free via C
    c_ffi_free(ptr)

    // [BUG] Use after C freed it
    let data = ptr.load(as: UInt8.self)  // UAF
    print("SWIFT-BUG-03: \(data)")
}

// ================================================================
// SWIFT-BUG-04: Bridged object over-release
//
// Bridging between Swift and Objective-C can cause over-release
// if ownership transfer is mismanaged.
//
// Expected: use_after_free / double_free
// ================================================================

func swift_bug_04_bridge_over_release() {
    // Simulate: NSString bridged to Swift String
    let nsStr: NSString = "bridged string"
    let swiftStr = nsStr as String

    // [BUG] Manually releasing bridged reference
    // ARC already manages the bridged reference
    // This is like calling CFRelease on a managed object
    let unmanaged = Unmanaged.passUnretained(nsStr as AnyObject)
    // Simulated over-release would happen here

    print("SWIFT-BUG-04: \(swiftStr)")
}

// ================================================================
// SWIFT-BUG-05: withUnsafePointer escaping
//
// withUnsafePointer provides a pointer valid only within the
// closure. Escaping it causes a dangling pointer.
//
// Expected: borrow_escape (CWE-562)
// ================================================================

var g_escaped_ptr: UnsafePointer<UInt8>?

func swift_bug_05_pointer_escape() {
    var data: [UInt8] = [1, 2, 3, 4, 5]

    withUnsafePointer(to: &data) { ptr in
        // [BUG] Escape the pointer beyond the closure
        g_escaped_ptr = UnsafePointer(OpaquePointer(ptr))
    }

    // g_escaped_ptr is now dangling — 'data' may have moved
    // In real Swift, stack may be reused
    print("SWIFT-BUG-05: \(g_escaped_ptr!.pointee)")
}

// ================================================================
// SWIFT-BUG-06: @objc callback captures Swift object incorrectly
//
// @convention(c) callbacks cannot capture Swift context.
// Using unsafeBitCast to pass Swift object as void* context
// bypasses ARC.
//
// Expected: use_after_free
// ================================================================

func swift_bug_06_objc_callback() {
    let obj = SwiftObject()

    // Pass Swift object as void* context to C callback
    let ctx = Unmanaged.passUnretained(obj).toOpaque()

    // [BUG] If obj is deallocated before callback fires,
    // ctx is a dangling pointer
    c_ffi_register_callback({ (context, value) in
        let recovered = Unmanaged<SwiftObject>.fromOpaque(context!).takeUnretainedValue()
        print("callback: \(recovered.value)")
    }, ctx)

    // obj may be deallocated here if no strong reference remains
}

// ================================================================
// SWIFT-BUG-07: Array.withUnsafeBufferPointer escape
//
// The buffer pointer is only valid within the closure.
//
// Expected: borrow_escape
// ================================================================

var g_array_buffer: UnsafeBufferPointer<UInt8>?

func swift_bug_07_array_escape() {
    let arr: [UInt8] = [10, 20, 30, 40, 50]

    arr.withUnsafeBufferPointer { buffer in
        // [BUG] Escape the buffer pointer
        g_array_buffer = buffer
    }

    // g_array_buffer is dangling
    print("SWIFT-BUG-07: \(g_array_buffer![0])")
}

// ================================================================
// Entry point
// ================================================================

func main() {
    swift_bug_01_unowned_uaf()
    swift_bug_02_weak_race()
    swift_bug_03_raw_ptr_uaf()
    swift_bug_04_bridge_over_release()
    swift_bug_05_pointer_escape()
    swift_bug_06_objc_callback()
    swift_bug_07_array_escape()
}

main()

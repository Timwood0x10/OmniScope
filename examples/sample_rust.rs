// Rust example - memory semantics differ from C
// Rust's ownership system prevents most C-style memory bugs

fn stack_vs_heap() -> i32 {
    let x = 5;        // Stack allocated
    let y = x + 1;   // y is copy of x
    y                 // x and y go out of scope, no leak
}

fn heap_allocation() -> Box<i32> {
    let b = Box::new(42); // Heap allocated
    b                         // Ownership transferred out
}

fn slice_reference(v: &[i32]) -> i32 {
    v[0] // Safe: slice is borrow, lifetime enforced
}

fn dangling_pointer_simulation() -> *const i32 {
    let x = 10;
    &x as *const i32 // Warning: returns pointer to stack
    // x dropped here, pointer becomes dangling
}

fn main() {
    let _stack = stack_vs_heap();
    let _heap = heap_allocation();

    let arr = [1, 2, 3];
    let _first = slice_reference(&arr);

    // This would be unsafe in unsafe{} block:
    let ptr = dangling_pointer_simulation();
    println!("Dangling ptr value: {}", unsafe { *ptr });
}

//! Build script for Rust FFI Demo
//!
//! Compiles the C library and links it with Rust

fn main() {
    // Compile C library
    cc::Build::new()
        .file("c_lib/dangerous.c")
        .include("c_lib")
        .compile("dangerous");

    // Tell cargo to invalidate the built crate whenever the C code changes
    println!("cargo:rerun-if-changed=c_lib/dangerous.c");
    println!("cargo:rerun-if-changed=c_lib/dangerous.h");
}

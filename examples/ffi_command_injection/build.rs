// Build script to compile C crypto library
fn main() {
    // Compile the C library
    cc::Build::new()
        .file("src/c_crypto_lib.c")
        .flag("-O0")  // No optimization for easier debugging
        .flag("-g")   // Include debug symbols
        .compile("crypto_lib");
    
    println!("cargo:rerun-if-changed=src/c_crypto_lib.c");
}
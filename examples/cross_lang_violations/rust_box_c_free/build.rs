fn main() {
    cc::Build::new()
        .file("c_side.c")
        .compile("c_side");
}

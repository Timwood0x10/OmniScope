# Cross-Language Ownership Violation Tests

.PHONY: all clean rust-box-c-free run

all: rust-box-c-free

rust-box-c-free:
	cd rust_box_c_free && cargo build --release

clean:
	cd rust_box_c_free && cargo clean
	rm -f *.ll *.bc

run: all
	../../zig-out/bin/OmniScope rust_box_c_free/target/release/librust_box_c_free.rlib

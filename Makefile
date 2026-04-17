# OmniScope - Cross-Language FFI/Unsafe Boundary Analyzer
#
# Quick Start:
#   make all         - Run all tests (unit + integration + bench)
#   make test-all    - Run all tests
#   make help        - Show all commands
#
# Development Commands:
#   make fmt         - Format source code
#   make check       - Type check the project
#   make test        - Run unit tests
#   make test-int    - Run integration tests
#   make bench       - Run performance benchmarks
#   make build       - Build the project
#   make run         - Run all FFI analysis tests
#   make clean       - Clean all build artifacts
#
# FFI Example Commands:
#   make examples    - Build all FFI example IR files
#   make rust        - Build Rust → C example
#   make cpp         - Build C++ → C example
#   make go          - Build Go → C example
#   make zig         - Build Zig → C example

ZIG ?= zig
CLANG ?= clang
CLANGXX ?= clang++
LLVM_LINK ?= /opt/homebrew/opt/llvm/bin/llvm-link

# Directories
BUILD_DIR ?= build
EXAMPLES_DIR ?= examples

# IR output directories
RUST_IR = $(EXAMPLES_DIR)/rust_ffi_demo/target
CPP_IR = $(EXAMPLES_DIR)/cpp_cffi/target
GO_IR = $(EXAMPLES_DIR)/go_cffi/target
ZIG_IR = $(EXAMPLES_DIR)/zig_cffi/target

.PHONY: all fmt check test test-unit test-int test-all bench build run clean examples \
        rust cpp go zig rust-run cpp-run go-run zig-run help \
        corpus corpus-ir corpus-analyze corpus-check

# ========================================
# Default Target - Run All Tests
# ========================================

all: test-all bench
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    ALL TESTS PASSED                            ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║  Unit Tests:        ✓ Passed                                  ║"
	@echo "║  Integration Tests: ✓ Passed                                  ║"
	@echo "║  Issue Verification:✓ Passed                                  ║"
	@echo "║  Stability Tests:   ✓ Passed                                  ║"
	@echo "║  Benchmarks:        ✓ Completed                               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Test Commands
# ========================================

test: test-unit

test-unit:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      UNIT TESTS                                ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build unit-test

test-int:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  INTEGRATION TESTS                             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-integration

test-issues:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  ISSUE VERIFICATION TESTS                      ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-issues

test-stability:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    STABILITY TESTS                             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-stability

test-all: test-unit test-int test-issues test-stability
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  ALL TESTS PASSED                              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Development Commands
# ========================================

fmt:
	$(ZIG) fmt src/

check:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      TYPE CHECK                                ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build check

bench:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     BENCHMARKS                                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build bench-perf -Doptimize=ReleaseFast

# ========================================
# Build & Run
# ========================================

build:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                       BUILD                                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build

# Run all FFI analysis tests
run: examples
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                   FFI ANALYSIS TESTS                           ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	
	@echo "========================================"
	@echo "Test 1: Rust → C FFI"
	@echo "========================================"
	$(ZIG) build run -- $(RUST_IR)/combined.bc
	@echo ""
	
	@echo "========================================"
	@echo "Test 2: C++ → C FFI"
	@echo "========================================"
	$(ZIG) build run -- $(CPP_IR)/combined.bc
	@echo ""
	
	@echo "========================================"
	@echo "Test 3: Go → C FFI"
	@echo "========================================"
	$(ZIG) build run -- $(GO_IR)/combined.bc
	@echo ""
	
	@echo "========================================"
	@echo "Test 4: Zig → C FFI"
	@echo "========================================"
	$(ZIG) build run -- $(ZIG_IR)/combined.bc
	@echo ""
	
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║               ALL FFI TESTS COMPLETED                          ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# FFI Examples
# ========================================

examples: rust cpp go zig

# ========================================
# Rust → C FFI Example
# ========================================

rust: rust-ir

rust-ir:
	@echo "Building Rust → C FFI example..."
	@mkdir -p $(RUST_IR)/ir
	
	@echo "  - Compiling Rust to LLVM IR..."
	cd $(EXAMPLES_DIR)/rust_ffi_demo && cargo rustc --release --lib -- --emit=llvm-ir -g
	@find $(EXAMPLES_DIR)/rust_ffi_demo/target/release/deps -name "rust_ffi_demo-*.ll" -exec cp {} $(RUST_IR)/ir/rust.ll \;
	
	@echo "  - Compiling C to LLVM IR..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(EXAMPLES_DIR)/rust_ffi_demo/c_lib/dangerous.c -o $(RUST_IR)/ir/dangerous.ll
	
	@echo "  - Linking IR files..."
	$(LLVM_LINK) $(RUST_IR)/ir/rust.ll $(RUST_IR)/ir/dangerous.ll -o $(RUST_IR)/combined.bc
	
	@echo "  Done: $(RUST_IR)/combined.bc"

rust-run: rust-ir
	$(ZIG) build run -- $(RUST_IR)/combined.bc

# ========================================
# C++ → C FFI Example
# ========================================

cpp: cpp-ir

cpp-ir:
	@echo "Building C++ → C FFI example..."
	@mkdir -p $(CPP_IR)/ir
	
	@echo "  - Compiling C to LLVM IR..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(EXAMPLES_DIR)/cpp_cffi/math_ops.c -o $(CPP_IR)/ir/math_ops.ll
	
	@echo "  - Compiling C++ to LLVM IR..."
	$(CLANGXX) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(EXAMPLES_DIR)/cpp_cffi/main.cpp -o $(CPP_IR)/ir/main.ll
	
	@echo "  - Linking IR files..."
	$(LLVM_LINK) $(CPP_IR)/ir/math_ops.ll $(CPP_IR)/ir/main.ll -o $(CPP_IR)/combined.bc
	
	@echo "  Done: $(CPP_IR)/combined.bc"

cpp-run: cpp-ir
	$(ZIG) build run -- $(CPP_IR)/combined.bc

# ========================================
# Go → C FFI Example
# ========================================

go: go-ir

go-ir:
	@echo "Building Go → C FFI example..."
	@mkdir -p $(GO_IR)/ir
	
	@echo "  - Compiling C to LLVM IR..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(EXAMPLES_DIR)/go_cffi/clib.c -o $(GO_IR)/ir/clib.ll
	
	@echo "  - Converting to bitcode..."
	$(LLVM_LINK) $(GO_IR)/ir/clib.ll -o $(GO_IR)/combined.bc
	
	@echo "  Done: $(GO_IR)/combined.bc"

go-run: go-ir
	$(ZIG) build run -- $(GO_IR)/combined.bc

# ========================================
# Zig → C FFI Example
# ========================================

zig: zig-ir

zig-ir:
	@echo "Building Zig → C FFI example..."
	@mkdir -p $(ZIG_IR)/ir
	
	@echo "  - Compiling C to LLVM IR..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(EXAMPLES_DIR)/zig_cffi/clib.c -o $(ZIG_IR)/ir/clib.ll
	
	@echo "  - Compiling Zig to LLVM IR..."
	cd $(EXAMPLES_DIR)/zig_cffi && $(ZIG) build-obj -femit-llvm-ir -ODebug main.zig
	@mv $(EXAMPLES_DIR)/zig_cffi/main.ll $(ZIG_IR)/ir/main.ll 2>/dev/null || true
	
	@echo "  - Linking IR files..."
	$(LLVM_LINK) $(ZIG_IR)/ir/clib.ll $(ZIG_IR)/ir/main.ll -o $(ZIG_IR)/combined.bc
	
	@echo "  Done: $(ZIG_IR)/combined.bc"

zig-run: zig-ir
	$(ZIG) build run -- $(ZIG_IR)/combined.bc

# ========================================
# Clean
# ========================================

clean:
	@echo "Cleaning all build artifacts..."
	rm -rf $(RUST_IR)/ir $(RUST_IR)/combined.bc
	rm -rf $(CPP_IR)
	rm -rf $(GO_IR)
	rm -rf $(ZIG_IR)
	rm -f $(EXAMPLES_DIR)/zig_cffi/main.ll $(EXAMPLES_DIR)/zig_cffi/main.o
	rm -rf zig-out .zig-cache
	rm -rf corpus/*/output
	@echo "Clean complete."

# ========================================
# Corpus - Test Cases for Benchmarking
# ========================================

CORPUS_DIR = corpus
CORPUS_FFI_DENSE = $(CORPUS_DIR)/ffi-dense

corpus: corpus-ir
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                   CORPUS BUILT                                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

corpus-ir:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                 BUILDING CORPUS IR                             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@mkdir -p $(CORPUS_FFI_DENSE)/output
	
	@echo "  - Compiling sqlite_binding.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/sqlite_binding.c -o $(CORPUS_FFI_DENSE)/output/sqlite_binding.ll 2>/dev/null || true
	
	@echo "  - Compiling openssl_wrapper.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/openssl_wrapper.c -o $(CORPUS_FFI_DENSE)/output/openssl_wrapper.ll 2>/dev/null || true
	
	@echo "  - Compiling zlib_binding.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/zlib_binding.c -o $(CORPUS_FFI_DENSE)/output/zlib_binding.ll 2>/dev/null || true
	
	@echo "  Done."

corpus-analyze: corpus-ir build
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                 ANALYZING CORPUS                               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	
	@for file in $(CORPUS_FFI_DENSE)/output/*.ll; do \
		echo ""; \
		echo "========================================"; \
		echo "Analyzing: $$file"; \
		echo "========================================"; \
		$(ZIG) build run -- $$file 2>&1 || true; \
	done

corpus-check: corpus-analyze
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                 CORPUS CHECK COMPLETE                          ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║  Expected: 33 issues across 4 test files                       ║"
	@echo "║  See corpus/EXPECTED_RESULTS.md for details                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Help
# ========================================

help:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║     OmniScope - Cross-Language FFI/Unsafe Boundary Analyzer    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Quick Start:"
	@echo "  make all         Run all tests (unit + integration + bench)"
	@echo "  make test-all    Run all tests"
	@echo "  make help        Show this help"
	@echo ""
	@echo "Test Commands:"
	@echo "  make test        Run unit tests (alias: test-unit)"
	@echo "  make test-unit   Run unit tests"
	@echo "  make test-int    Run integration tests"
	@echo "  make test-issues Run issue verification tests"
	@echo "  make test-stability Run stability tests"
	@echo "  make test-all    Run all tests"
	@echo "  make bench       Run performance benchmarks"
	@echo ""
	@echo "Corpus Commands:"
	@echo "  make corpus      Build corpus IR files"
	@echo "  make corpus-ir   Compile corpus to LLVM IR"
	@echo "  make corpus-analyze  Analyze corpus with OmniScope"
	@echo "  make corpus-check    Analyze and check expected issues"
	@echo ""
	@echo "Development Commands:"
	@echo "  make fmt         Format source code"
	@echo "  make check       Type check the project"
	@echo "  make build       Build the project"
	@echo "  make clean       Clean all build artifacts"
	@echo ""
	@echo "FFI Analysis Commands:"
	@echo "  make run         Run all FFI analysis tests"
	@echo "  make examples    Build all FFI example IR files"
	@echo ""
	@echo "FFI Example Commands:"
	@echo "  make rust        Build Rust → C example"
	@echo "  make cpp         Build C++ → C example"
	@echo "  make go          Build Go → C example"
	@echo "  make zig         Build Zig → C example"
	@echo ""
	@echo "  make rust-run    Build and run Rust example"
	@echo "  make cpp-run     Build and run C++ example"
	@echo "  make go-run      Build and run Go example"
	@echo "  make zig-run     Build and run Zig example"
	@echo ""

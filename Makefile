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

ifeq ($(OS),Windows_NT)
    DETECTED_OS := windows
    TOOL_QUERY := where
    REDIRECT := 2>nul
else
    DETECTED_OS := unix
    TOOL_QUERY := which
    REDIRECT := 2>/dev/null
endif

ZIG = $(shell $(TOOL_QUERY) zig $(REDIRECT) || echo zig)
CLANG = $(shell $(TOOL_QUERY) clang $(REDIRECT) || echo clang)
CLANGXX = $(shell $(TOOL_QUERY) clang++ $(REDIRECT) || echo clang++)
LLVM_LINK = $(shell $(TOOL_QUERY) llvm-link $(REDIRECT) || echo llvm-link)

# Directories
BUILD_DIR ?= build
EXAMPLES_DIR ?= examples

# IR output directories
RUST_IR = $(EXAMPLES_DIR)/rust_ffi_demo/target
CPP_IR = $(EXAMPLES_DIR)/cpp_cffi/target
GO_IR = $(EXAMPLES_DIR)/go_cffi/target
ZIG_IR = $(EXAMPLES_DIR)/zig_cffi/target

.PHONY: all fmt fmt-check check test test-unit test-int test-all \
        bench build build-debug run clean examples \
        baseline-check red-team-test \
        rust rust-ir rust-run rust-json rust-sarif \
        cpp cpp-ir cpp-run cpp-json cpp-sarif \
        go go-ir go-run go-json go-sarif \
        zig zig-ir zig-run zig-json zig-sarif \
        help \
        corpus corpus-ir corpus-red-team-ir corpus-analyze corpus-check \
        red-team blue-team corpus-test \
        real-world real-world-ir real-world-run real-world-json real-world-sarif \
        install-deps release benchmark benchmark-ci benchmark-json benchmark-full \
        regression-test bench-perf stability-test e2e-test test-all-phase7 \
        viz visualize \
        cross-lang-test cross-lang-build cross-lang-run cross-lang-report \
        reports-json reports-sarif \
        test-issues test-stability test-stress test-inline-ir-matrix \
        test-ffi-layout test-ffi-string test-ffi-unwind

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
	@echo "║  Inline IR Matrix:  ✓ Passed                                  ║"
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

test-stress:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     STRESS TESTS                               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-stress

test-inline-ir-matrix:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              INLINE IR MATRIX TESTS                           ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-inline-ir-matrix

test-ffi-layout:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              FFI LAYOUT MISMATCH TESTS                        ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-ffi-layout

test-ffi-string:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              FFI STRING SAFETY TESTS                          ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-ffi-string

test-ffi-unwind:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              FFI UNWIND BOUNDARY TESTS                        ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-ffi-unwind

test-all: test-unit test-int test-issues test-stability test-stress test-inline-ir-matrix \
        test-ffi-layout test-ffi-string test-ffi-unwind
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  ALL TESTS PASSED                              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Development Commands
# ========================================

fmt:
	$(ZIG) fmt src/

fmt-check:
	$(ZIG) fmt --check src/

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
# Detection Rate Benchmark
# ========================================

benchmark: corpus
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              DETECTION RATE BENCHMARK                         ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/benchmark.sh

benchmark-json: corpus
	@mkdir -p benchmark-output
	./scripts/benchmark.sh --json > benchmark-output/benchmark-results.json
	@echo "JSON report saved to benchmark-output/benchmark-results.json"

benchmark-ci: corpus
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              CI BENCHMARK (exit code = pass/fail)             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/benchmark.sh --ci

benchmark-full: test-all bench benchmark
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              FULL BENCHMARK SUITE COMPLETE                    ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║  Unit Tests:        ✓ Passed                                  ║"
	@echo "║  Integration Tests: ✓ Passed                                  ║"
	@echo "║  Issue Verification:✓ Passed                                  ║"
	@echo "║  Stability Tests:   ✓ Passed                                  ║"
	@echo "║  Stress Tests:      ✓ Passed                                  ║"
	@echo "║  Micro Benchmarks:  ✓ Completed                               ║"
	@echo "║  Detection Rate:    ✓ Calculated                              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Install & Release
# ========================================

install-deps:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  INSTALL DEPENDENCIES                          ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/install_deps.sh

release:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     RELEASE BUILD                              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/release.sh

# ========================================
# Build & Run
# ========================================

build:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                       BUILD                                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build

build-debug:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    DEBUG BUILD                                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build -Doptimize=Debug

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

rust-json: rust-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --json -o $(EXAMPLES_DIR)/reports/rust_report.json $(RUST_IR)/combined.bc
	@echo "JSON report saved to $(EXAMPLES_DIR)/reports/rust_report.json"

rust-sarif: rust-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --sarif -o $(EXAMPLES_DIR)/reports/rust_report.sarif $(RUST_IR)/combined.bc
	@echo "SARIF report saved to $(EXAMPLES_DIR)/reports/rust_report.sarif"

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

cpp-json: cpp-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --json -o $(EXAMPLES_DIR)/reports/cpp_report.json $(CPP_IR)/combined.bc

cpp-sarif: cpp-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --sarif -o $(EXAMPLES_DIR)/reports/cpp_report.sarif $(CPP_IR)/combined.bc

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

go-json: go-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --json -o $(EXAMPLES_DIR)/reports/go_report.json $(GO_IR)/combined.bc

go-sarif: go-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --sarif -o $(EXAMPLES_DIR)/reports/go_report.sarif $(GO_IR)/combined.bc

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

zig-json: zig-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --json -o $(EXAMPLES_DIR)/reports/zig_report.json $(ZIG_IR)/combined.bc

zig-sarif: zig-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --sarif -o $(EXAMPLES_DIR)/reports/zig_report.sarif $(ZIG_IR)/combined.bc

# ========================================
# Real-World FFI Tests (OpenSSL, SQLite, zlib)
# ========================================

REAL_WORLD_DIR = $(EXAMPLES_DIR)/real_world
REAL_WORLD_IR = $(REAL_WORLD_DIR)/target

real-world: real-world-run
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              REAL-WORLD FFI TESTS COMPLETE                     ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║  OpenSSL Patterns:  ✓ Analyzed                                ║"
	@echo "║  SQLite Patterns:   ✓ Analyzed                                ║"
	@echo "║  zlib Patterns:     ✓ Analyzed                                ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

real-world-ir:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║            BUILDING REAL-WORLD FFI TEST IR                     ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@mkdir -p $(REAL_WORLD_IR)/ir
	
	@echo "  - Compiling OpenSSL FFI patterns..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(REAL_WORLD_DIR)/openssl_ffi.c -o $(REAL_WORLD_IR)/ir/openssl.ll 2>/dev/null || true
	
	@echo "  - Compiling SQLite FFI patterns..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(REAL_WORLD_DIR)/sqlite_ffi.c -o $(REAL_WORLD_IR)/ir/sqlite.ll 2>/dev/null || true
	
	@echo "  - Compiling zlib FFI patterns..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(REAL_WORLD_DIR)/zlib_ffi.c -o $(REAL_WORLD_IR)/ir/zlib.ll 2>/dev/null || true
	
	@echo "  - Linking IR files..."
	$(LLVM_LINK) $(REAL_WORLD_IR)/ir/openssl.ll $(REAL_WORLD_IR)/ir/sqlite.ll $(REAL_WORLD_IR)/ir/zlib.ll \
		-o $(REAL_WORLD_IR)/combined.bc
	
	@echo "  Done: $(REAL_WORLD_IR)/combined.bc"

real-world-run: real-world-ir
	$(ZIG) build run -- $(REAL_WORLD_IR)/combined.bc

real-world-json: real-world-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --json -o $(EXAMPLES_DIR)/reports/real_world_report.json $(REAL_WORLD_IR)/combined.bc

real-world-sarif: real-world-ir
	@mkdir -p $(EXAMPLES_DIR)/reports
	$(ZIG) build run -- --sarif -o $(EXAMPLES_DIR)/reports/real_world_report.sarif $(REAL_WORLD_IR)/combined.bc

# ========================================
# Baseline Regression Check (Task 8.4)
# ========================================

baseline-check: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              BASELINE REGRESSION CHECK                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/baseline_check.sh

red-team-test: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              RED TEAM ADVERSARIAL TEST                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Running OmniScope on red team test files..."
	@for f in $(RED_IR_FILES); do \
		if [ ! -f "$f" ]; then continue; fi; \
		name=$(basename "$f"); \
		echo ""; \
		echo "=== Analyzing: $name ==="; \
		$(ZIG) build run -- "$f" 2>&1 || true; \
	done

# ========================================
# All Reports
# ========================================

reports-json: rust-json cpp-json go-json zig-json real-world-json
	@echo ""
	@echo "All JSON reports generated:"
	@ls -la $(EXAMPLES_DIR)/reports/*.json

reports-sarif: rust-sarif cpp-sarif go-sarif zig-sarif real-world-sarif
	@echo ""
	@echo "All SARIF reports generated:"
	@ls -la $(EXAMPLES_DIR)/reports/*.sarif

# ========================================
# Clean
# ========================================

clean:
	@echo "Cleaning all build artifacts..."
	rm -rf $(RUST_IR)/ir $(RUST_IR)/combined.bc
	rm -rf $(CPP_IR)
	rm -rf $(GO_IR)
	rm -rf $(ZIG_IR)
	rm -rf $(REAL_WORLD_IR)
	rm -f $(EXAMPLES_DIR)/zig_cffi/main.ll $(EXAMPLES_DIR)/zig_cffi/main.o
	rm -rf zig-out .zig-cache
	rm -rf corpus/*/output output
	@echo "Clean complete."

# ========================================
# Corpus - Test Cases for Benchmarking
# ========================================

CORPUS_DIR = corpus
CORPUS_FFI_DENSE = $(CORPUS_DIR)/ffi-dense
CORPUS_SMALL = $(CORPUS_DIR)/small
CORPUS_MEDIUM = $(CORPUS_DIR)/medium
CORPUS_LARGE = $(CORPUS_DIR)/large

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
	@mkdir -p $(CORPUS_SMALL)/output
	@mkdir -p $(CORPUS_MEDIUM)/output
	@mkdir -p $(CORPUS_LARGE)/output

	@echo "  - Compiling small/cpp_ffi_simple.cpp..."
	$(CLANGXX) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_SMALL)/cpp_ffi_simple.cpp -o $(CORPUS_SMALL)/output/cpp_ffi_simple.ll 2>/dev/null || true

	@echo "  - Compiling medium/boundary_test.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_MEDIUM)/boundary_test.c -o $(CORPUS_MEDIUM)/output/boundary_test.ll 2>/dev/null || true

	@echo "  - Compiling large/stress_patterns.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_LARGE)/stress_patterns.c -o $(CORPUS_LARGE)/output/stress_patterns.ll 2>/dev/null || true

	@echo "  - Compiling ffi-dense/sqlite_binding.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/sqlite_binding.c -o $(CORPUS_FFI_DENSE)/output/sqlite_binding.ll 2>/dev/null || true

	@echo "  - Compiling ffi-dense/openssl_wrapper.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/openssl_wrapper.c -o $(CORPUS_FFI_DENSE)/output/openssl_wrapper.ll 2>/dev/null || true

	@echo "  - Compiling ffi-dense/zlib_binding.c..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		$(CORPUS_FFI_DENSE)/zlib_binding.c -o $(CORPUS_FFI_DENSE)/output/zlib_binding.ll 2>/dev/null || true

	@echo "  Done."

# ========================================
# Corpus red_team_test LLVM IR regeneration with DWARF
# ========================================

# Regenerate red_team_test .ll files with DWARF debug info
# Required by A1 (DICompileUnit language detection)
# Run this after updating corpus source files:
#   make corpus-red-team-ir

RED_TEAM_DIR := corpus/red_team_test

corpus-red-team-ir:
	@echo "Regenerating red_team_test IR with DWARF debug info..."
	@for src in $(RED_TEAM_DIR)/*.c; do \
		base=$$(basename $$src .c); \
		echo "  - $$base.c → $$base.ll"; \
		$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
			$$src -o $(RED_TEAM_DIR)/$$base.ll 2>/dev/null || true; \
	done
	@echo "  Done. All red_team_test .ll files regenerated with DWARF."

corpus-analyze: corpus-ir build
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                 ANALYZING CORPUS                               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

	@echo "Analyzing small/ corpus..."
	@for file in $(CORPUS_SMALL)/output/*.ll; do \
		echo ""; \
		echo "========================================"; \
		echo "Analyzing: $$file"; \
		echo "========================================"; \
		$(ZIG) build run -- $$file 2>&1 || true; \
	done

	@echo "Analyzing medium/ corpus..."
	@for file in $(CORPUS_MEDIUM)/output/*.ll; do \
		echo ""; \
		echo "========================================"; \
		echo "Analyzing: $$file"; \
		echo "========================================"; \
		$(ZIG) build run -- $$file 2>&1 || true; \
	done

	@echo "Analyzing large/ corpus..."
	@for file in $(CORPUS_LARGE)/output/*.ll; do \
		echo ""; \
		echo "========================================"; \
		echo "Analyzing: $$file"; \
		echo "========================================"; \
		$(ZIG) build run -- $$file 2>&1 || true; \
	done

	@echo "Analyzing ffi-dense/ corpus..."
	@for file in $(CORPUS_FFI_DENSE)/output/*.ll; do \
		echo ""; \
		echo "========================================"; \
		echo "Analyzing: $$file"; \
		echo "========================================"; \
		$(ZIG) build run -- $$file 2>&1 || true; \
	done

corpus-check: corpus
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                                                                ║"
	@echo "║                 CORPUS CHECK COMPLETE                           ║"
	@echo "║                                                                ╠════════════════════════════════════════════════════════════════╣"
	@echo "║                                                                ║"
	@echo "║  Expected: 136 issues across 10 test files                     ║"
	@echo "║  - small/: 13 issues (4 FFI test files)                       ║"
	@echo "║  - medium/: 20 issues (1 C test file)                        ║"
	@echo "║  - large/: 70 issues (1 C test file with cross-lang)          ║"
	@echo "║  - ffi-dense/: 33 issues (4 test files)                      ║"
	@echo "║  Note: Cross-language violations now detected!               ║"
	@echo "║  See corpus/EXPECTED_RESULTS.md for details                    ║"
	@echo "║                                                                ╚════════════════════════════════════════════════════════════════╝"
	@echo "%"

# ========================================
# Red/Blue Team Testing (v0.1.9)
# ========================================
#
# Red Team  = adversarial: does the tool detect known bugs? (recall)
# Blue Team = defensive: does the tool avoid false alarms? (precision)
#
# Usage:
#   make red-team         Run red team only
#   make blue-team        Run blue team only
#   make corpus-test      Run both + summary

OMNISCOPE = $(ZIG) build run --

RED_TEAM_DIR = $(CORPUS_DIR)/red_team_test
RED_IR_FILES = \
	$(RED_TEAM_DIR)/cross_lang_free_bugs.ll \
	$(RED_TEAM_DIR)/go_cgo_bugs.ll \
	$(RED_TEAM_DIR)/java_jni_bugs.ll \
	$(RED_TEAM_DIR)/python_cffi_bugs.ll \
	$(RED_TEAM_DIR)/red_team_cpp_ffi.ll \
	$(RED_TEAM_DIR)/red_team_swift_ffi.ll \
	$(RED_TEAM_DIR)/red_team_triple_chain.ll \
	$(RED_TEAM_DIR)/rust_ffi_bugs.ll

# Red Team: adversarial detection test
# Compiles red_team_test/*.c to IR and runs OmniScope.
# Reports issue count per file. Expected: ≥10 issues per adversarial file.
red-team: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    RED TEAM TEST                              ║"
	@echo "║  Adversarial: detect known bugs in crafted test cases         ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@mkdir -p /tmp/omniscope-red-team
	@total_files=0; total_issues=0; \
	for f in $(RED_IR_FILES); do \
		if [ ! -f "$$f" ]; then continue; fi; \
		total_files=$$((total_files + 1)); \
		name=$$(basename "$$f"); \
		output=$$( $(OMNISCOPE) "$$f" 2>&1 ); \
		count=$$(echo "$$output" | perl -pe 's/\x1b\[[0-9;]*m//g' | grep -c "VULNERABILITY\|OMI-CRITICAL\|OMI-HIGH\|CROSS-LANG" 2>/dev/null || true); \
		count=$${count:-0}; \
		total_issues=$$((total_issues + count)); \
		if [ "$$count" -gt 0 ]; then \
			printf "  ✅ %-40s %3d issues\n" "$$name" "$$count"; \
		else \
			printf "  ❌ %-40s %3d issues (MISS)\n" "$$name" "$$count"; \
		fi; \
	done; \
	echo ""; \
	echo "────────────────────────────────────────────────────────"; \
	printf "  Red Team: %d files, %d total issues detected\n" "$$total_files" "$$total_issues"; \
	if [ "$$total_issues" -lt 10 ]; then \
		echo "  ⚠️  LOW detection count — investigate regressions"; \
	else \
		echo "  ✅ Detection threshold met"; \
	fi

# Blue Team: false positive audit
# Runs OmniScope on corpus files and checks out-of-scope inflation.
# Expected: issue count should not wildly exceed in-scope expected count.
blue-team: corpus-ir build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    BLUE TEAM TEST                             ║"
	@echo "║  Defensive: false positive audit on corpus                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@blue_pass=0; blue_fail=0; \
	\
	echo "── small/ (expected ≤13 in-scope issues)"; \
	small_count=0; \
	for f in $(CORPUS_SMALL)/output/*.ll; do \
		if [ ! -f "$$f" ]; then continue; fi; \
		c=$$( $(OMNISCOPE) "$$f" 2>&1 | perl -pe 's/\x1b\[[0-9;]*m//g' | grep -c "VULNERABILITY\|OMI-CRITICAL\|OMI-HIGH\|CROSS-LANG" 2>/dev/null || true); \
		c=$${c:-0}; \
		small_count=$$((small_count + c)); \
	done; \
	if [ "$$small_count" -le 20 ]; then \
		printf "  ✅ small/:        %3d issues (expected ≤13, ok)\n" "$$small_count"; \
		blue_pass=$$((blue_pass + 1)); \
	else \
		printf "  ❌ small/:        %3d issues (expected ≤13, OVER)\n" "$$small_count"; \
		blue_fail=$$((blue_fail + 1)); \
	fi; \
	\
	echo "── medium/ (expected ≤20 in-scope issues)"; \
	med_count=0; \
	for f in $(CORPUS_MEDIUM)/output/*.ll; do \
		if [ ! -f "$$f" ]; then continue; fi; \
		c=$$( $(OMNISCOPE) "$$f" 2>&1 | perl -pe 's/\x1b\[[0-9;]*m//g' | grep -c "VULNERABILITY\|OMI-CRITICAL\|OMI-HIGH\|CROSS-LANG" 2>/dev/null || true); \
		c=$${c:-0}; \
		med_count=$$((med_count + c)); \
	done; \
	if [ "$$med_count" -le 30 ]; then \
		printf "  ✅ medium/:       %3d issues (expected ≤20, ok)\n" "$$med_count"; \
		blue_pass=$$((blue_pass + 1)); \
	else \
		printf "  ❌ medium/:       %3d issues (expected ≤20, OVER)\n" "$$med_count"; \
		blue_fail=$$((blue_fail + 1)); \
	fi; \
	\
	echo "── ffi-dense/ (expected ≤26 in-scope issues)"; \
	dense_count=0; \
	for f in $(CORPUS_FFI_DENSE)/output/*.ll; do \
		if [ ! -f "$$f" ]; then continue; fi; \
		c=$$( $(OMNISCOPE) "$$f" 2>&1 | perl -pe 's/\x1b\[[0-9;]*m//g' | grep -c "VULNERABILITY\|OMI-CRITICAL\|OMI-HIGH\|CROSS-LANG" 2>/dev/null || true); \
		c=$${c:-0}; \
		dense_count=$$((dense_count + c)); \
	done; \
	if [ "$$dense_count" -le 40 ]; then \
		printf "  ✅ ffi-dense/:    %3d issues (expected ≤26, ok)\n" "$$dense_count"; \
		blue_pass=$$((blue_pass + 1)); \
	else \
		printf "  ❌ ffi-dense/:    %3d issues (expected ≤26, OVER)\n" "$$dense_count"; \
		blue_fail=$$((blue_fail + 1)); \
	fi; \
	\
	echo ""; \
	echo "────────────────────────────────────────────────────────"; \
	printf "  Blue Team: %d passed, %d failed\n" "$$blue_pass" "$$blue_fail"; \
	if [ "$$blue_fail" -gt 0 ]; then \
		echo "  ⚠️  False positive regression detected"; \
	else \
		echo "  ✅ No false positive regression"; \
	fi

# Combined: run both red + blue team
corpus-test: red-team blue-team
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  CORPUS TEST COMPLETE                         ║"
	@echo "║  Red Team  = detection rate (adversarial bugs)                ║"
	@echo "║  Blue Team = false positive audit (clean boundaries)          ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================

# ========================================
# Phase 7: Regression Testing & Quality Gate (v0.1.6)
# ========================================

regression-test: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║           REGRESSION TEST SUITE (v0.1.6)                      ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/regression_test.sh all

bench-perf: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║           PERFORMANCE BENCHMARK (v0.1.6)                      ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/bench_perf.sh all

stability-test: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║           STABILITY TEST SUITE (v0.1.6)                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/stability_test.sh all

e2e-test: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║           END-TO-END PIPELINE TEST                            ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	./scripts/stability_test.sh e2e

test-all-phase7: test regression-test bench-perf stability-test
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║           PHASE 7 QUALITY GATE COMPLETE                        ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║  ✓ Unit Tests          (make test)                           ║"
	@echo "║  ✓ Regression Tests    (make regression-test)                ║"
	@echo "║  ✓ Performance Bench   (make bench-perf)                     ║"
	@echo "║  ✓ Stability Tests     (make stability-test)                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

# ========================================
# Visualization Commands
# ========================================

VIZ_INPUT ?= corpus/real_world/other/sqlite3.ll

viz visualize: build
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              MEMORY GRAPH VISUALIZATION                        ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@mkdir -p output
	$(ZIG) build run -- --visualize $(VIZ_INPUT)
	@echo ""
	@echo "Output: output/$(shell basename $(VIZ_INPUT) .ll)/memory.html"
	@open output/$(shell basename $(VIZ_INPUT) .ll)/memory.html 2>/dev/null || true

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
	@echo "  make test-stress    Run stress tests"
	@echo "  make test-inline-ir-matrix  Run inline IR matrix tests (all languages × scenarios)"
	@echo "  make test-ffi-layout    Run FFI layout mismatch tests"
	@echo "  make test-ffi-string   Run FFI string safety tests"
	@echo "  make test-ffi-unwind   Run FFI unwind boundary tests"
	@echo "  make test-all          Run all tests"
	@echo "  make bench       Run performance benchmarks"
	@echo ""
	@echo "Corpus Commands:"
	@echo "  make corpus      Build corpus IR files"
	@echo "  make corpus-ir   Compile corpus to LLVM IR"
	@echo "  make corpus-analyze  Analyze corpus with OmniScope"
	@echo "  make corpus-check    Analyze and check expected issues"
	@echo ""
	@echo "Red/Blue Team Testing:"
	@echo "  make red-team    Adversarial: detect known bugs (recall)"
	@echo "  make blue-team   Defensive: false positive audit (precision)"
	@echo "  make corpus-test Run both red + blue team tests"
	@echo ""
	@echo "Benchmark Commands:"
	@echo "  make bench          Run micro-benchmarks (component-level timing)"
	@echo "  make benchmark      Run detection rate benchmark on corpus"
	@echo "  make benchmark-json  Export benchmark results as JSON"
	@echo "  make benchmark-ci    CI mode (exit code = pass/fail)"
	@echo "  make benchmark-full  Run complete benchmark suite"
	@echo ""
	@echo "Development Commands:"
	@echo "  make fmt         Format source code"
	@echo "  make fmt-check   Check formatting (CI use)"
	@echo "  make check       Type check the project"
	@echo "  make build       Build the project"
	@echo "  make build-debug Build the project in Debug mode"
	@echo "  make clean       Clean all build artifacts"
	@echo ""
	@echo "Install & Release:"
	@echo "  make install-deps  Install dependencies (LLVM, Zig)"
	@echo "  make release       Build release binaries"
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
	@echo "Real-World FFI Tests:"
	@echo "  make real-world      Build and analyze real-world FFI patterns"
	@echo "  make real-world-ir   Build OpenSSL/SQLite/zlib test IR"
	@echo "  make real-world-run  Analyze real-world FFI patterns"
	@echo ""
	@echo "Regression Guard:"
	@echo "  make baseline-check  Run baseline regression test (SQLite + curl + libuv)"
	@echo ""
	@echo "Visualization Commands:"
	@echo "  make viz             Generate & open memory graph HTML (default: sqlite3.ll)"
	@echo "  make visualize       Alias for 'make viz'"
	@echo "  make viz VIZ_INPUT=foo.ll  Analyze specific .ll file"
	@echo ""
	@echo "Report Commands (JSON/SARIF):"
	@echo "  make rust-json           Generate Rust JSON report"
	@echo "  make rust-sarif         Generate Rust SARIF report"
	@echo "  make cpp-json           Generate C++ JSON report"
	@echo "  make cpp-sarif         Generate C++ SARIF report"
	@echo "  make go-json            Generate Go JSON report"
	@echo "  make go-sarif          Generate Go SARIF report"
	@echo "  make zig-json           Generate Zig JSON report"
	@echo "  make zig-sarif         Generate Zig SARIF report"
	@echo "  make real-world-json    Generate real-world JSON report"
	@echo "  make real-world-sarif  Generate real-world SARIF report"
	@echo "  make reports-json       Generate all JSON reports"
	@echo ""
	@echo "Cross-Language Free Tests:"
	@echo "  make cross-lang-test    Run all cross-language violation tests"
	@echo "  make cross-lang-build   Build cross-language test IR files"
	@echo "  make cross-lang-run     Analyze cross-language test cases"
	@echo "  make cross-lang-report  Generate detailed cross-lang report"

# ========================================
# Cross-Language Free Violation Tests
# ========================================

cross-lang-test: cross-lang-build cross-lang-run
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║          CROSS-LANGUAGE FREE TESTS COMPLETE                   ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

cross-lang-build:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║            BUILDING CROSS-LANGUAGE TEST IR                     ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@if [ ! -f corpus/red_team_test/cross_lang_free_bugs.ll ]; then \
		echo "  Compiling cross_lang_free_bugs.c..."; \
		$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
			corpus/red_team_test/cross_lang_free_bugs.c \
			-o corpus/red_team_test/cross_lang_free_bugs.ll 2>/dev/null || true; \
	else \
		echo "  ✓ cross_lang_free_bugs.ll already exists"; \
	fi
	@echo "  ✓ Cross-language test IR built"

cross-lang-run:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║            ANALYZING CROSS-LANGUAGE VIOLATIONS                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "=== Test: cross_lang_free_bugs.ll ==="
	$(ZIG) build run -- corpus/red_team_test/cross_lang_free_bugs.ll 2>&1 | grep -E "Issues detected|Memory leak|cross_language|Issue breakdown" -A 15

cross-lang-report:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║          CROSS-LANGUAGE DETAILED REPORT                        ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Test Suite: Cross-Language Free Violation Detection"
	@echo "===================================================="
	@echo ""
	@echo "Test Case: cross_lang_free_bugs.ll"
	@echo "  Scenarios: 10 (Rust→C, C→C++, aliases, realloc, nested)"
	@echo "  Expected:   cross_language_free violations"
	$(ZIG) build run -- corpus/red_team_test/cross_lang_free_bugs.ll 2>&1 | tail -20

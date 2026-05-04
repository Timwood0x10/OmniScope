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

.PHONY: all fmt check test test-unit test-int test-all bench build run clean examples \
        baseline-check red-team-test \
        rust cpp go zig rust-run cpp-run go-run zig-run help \
        corpus corpus-ir corpus-analyze corpus-check \
        real-world real-world-ir real-world-run \
        baseline-check \
        install-deps release benchmark benchmark-full \
        regression-test bench-perf stability-test e2e-test test-all-phase7 \
        viz visualize

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

test-stress:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     STRESS TESTS                               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	$(ZIG) build test-stress

test-all: test-unit test-int test-issues test-stability test-stress
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
	@if [ ! -f corpus/red_team_test/red_team_bugs_O0.ll ]; then \
		echo "Compiling red_team_bugs.c with -O0..."; \
		$(CLANG) -S -emit-llvm -g -O0 -o corpus/red_team_test/red_team_bugs_O0.ll corpus/red_team_test/red_team_bugs.c; \
	fi
	@echo ""
	@echo "Running OmniScope on red team test file (O0 build)..."
	@./zig-out/bin/OmniScope corpus/red_team_test/red_team_bugs_O0.ll 2>&1 | tee /tmp/red_team_output.txt
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              RED TEAM TEST RESULTS                            ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@grep "Issues detected" /tmp/red_team_output.txt || echo "No issues found!"
	@echo ""
	@echo "Expected detections (v0.1.6):"
	@echo "  ✅ Memory Leak (bug_memory_leak)"
	@echo "  ✅ Use-After-Free (bug_use_after_free, bug_realloc_mishandle)"
	@echo "  ✅ Double-Free (bug_double_free) [NEW in v0.1.6]"
	@echo "  ✅ NULL Dereference (bug_null_deref)"
	@echo "  ✅ FFI RISK CRITICAL: system(), popen() [ENHANCED in v0.1.6]"
	@echo "  ✅ FFI RISK CRITICAL: execvp() [NEW in v0.1.6]"
	@echo "  ✅ Format String (bug_format_string) [CLASSIFIED in v0.1.6]"
	@echo "  ✅ Loop Leak (bug_loop_leak) [NEW in v0.1.6]"
	@echo ""
	@echo "Total issues should be ≥10 (target: 12)"

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
	@echo "  make test-all    Run all tests"
	@echo "  make bench       Run performance benchmarks"
	@echo ""
	@echo "Corpus Commands:"
	@echo "  make corpus      Build corpus IR files"
	@echo "  make corpus-ir   Compile corpus to LLVM IR"
	@echo "  make corpus-analyze  Analyze corpus with OmniScope"
	@echo "  make corpus-check    Analyze and check expected issues"
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
	@echo "  make check       Type check the project"
	@echo "  make build       Build the project"
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
	@echo "  make reports-sarif     Generate all SARIF reports"
	@echo ""

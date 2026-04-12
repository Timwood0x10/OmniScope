# LLVMScope Makefile
# Build system for LLVMScope V2

# ============================================================================
# Configuration
# ============================================================================
PROJECT_NAME := OmniSope
BUILD_DIR := zig-out
CACHE_DIR := zig-cache

# Compiler and tools
ZIG := zig
ZIG_BUILD := $(ZIG) build
ZIG_FMT := $(ZIG) fmt
ZIG_TEST := $(ZIG) build test

# ============================================================================
# Build Targets
# ============================================================================

.PHONY: all build dev release release-fast release-small test run clean fmt check help

# Default target
all: build

# Development build (default)
build:
	@echo "Building $(PROJECT_NAME) (dev mode)..."
	$(ZIG_BUILD)

# Release build with LTO
release:
	@echo "Building $(PROJECT_NAME) (release mode with LTO)..."
	$(ZIG_BUILD) -Doptimize=ReleaseFast -Denable-lto

# ReleaseFast build (optimize for speed)
release-fast:
	@echo "Building $(PROJECT_NAME) (ReleaseFast)..."
	$(ZIG_BUILD) -Doptimize=ReleaseFast

# ReleaseSmall build (optimize for size)
release-small:
	@echo "Building $(PROJECT_NAME) (ReleaseSmall)..."
	$(ZIG_BUILD) -Doptimize=ReleaseSmall

# Debug build (default)
debug:
	@echo "Building $(PROJECT_NAME) (debug mode)..."
	$(ZIG_BUILD) -Doptimize=Debug

# ============================================================================
# Test Targets
# ============================================================================

# Run all tests
test:
	@echo "Running tests..."
	$(ZIG_TEST)

# Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	$(ZIG_TEST) --summary all

# Run a specific test file
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file FILE=path/to/test.zig"; \
		exit 1; \
	fi
	@echo "Running test file: $(FILE)..."
	$(ZIG) test $(FILE)

# ============================================================================
# Run Targets
# ============================================================================

# Run the application
run: build
	@echo "Running $(PROJECT_NAME)..."
	$(BUILD_DIR)/bin/$(PROJECT_NAME)

# Run with arguments
run-args: build
	@echo "Running $(PROJECT_NAME) with args: $(ARGS)..."
	$(BUILD_DIR)/bin/$(PROJECT_NAME) $(ARGS)

# ============================================================================
# Code Quality Targets
# ============================================================================

# Format all Zig code
fmt:
	@echo "Formatting Zig code..."
	$(ZIG_FMT) .

# Check code (must have 0 errors - acceptance criteria)
check:
	@echo "Checking code for errors..."
	@ERRORS=$$($(ZIG_BUILD) 2>&1 | grep -c "error:" || true); \
	if [ "$$ERRORS" -ne 0 ]; then \
		echo "❌ Check failed: $$ERRORS error(s) found"; \
		exit 1; \
	else \
		echo "✅ Check passed: 0 errors"; \
	fi

# Check format (without formatting)
check-fmt:
	@echo "Checking code format..."
	@$(ZIG_FMT) --check . || { echo "❌ Format check failed"; exit 1; }
	@echo "✅ Format check passed"

# Check format and fix
fix-fmt:
	@echo "Fixing code format..."
	$(ZIG_FMT) .

# Lint check (warnings are allowed, errors are not)
lint:
	@echo "Running linter (errors only)..."
	@$(ZIG_BUILD) 2>&1 | grep "error:" && exit 1 || echo "✅ No errors found"

# Full check (format + build)
check-all: check-fmt check
	@echo "✅ All checks passed"

# ============================================================================
# Clean Targets
# ============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR) $(CACHE_DIR)

# Clean only cache (keep binaries)
clean-cache:
	@echo "Cleaning cache only..."
	rm -rf $(CACHE_DIR)

# Clean only binaries (keep cache)
clean-bin:
	@echo "Cleaning binaries only..."
	rm -rf $(BUILD_DIR)

# Deep clean (including .zig-cache in subdirectories)
clean-all:
	@echo "Deep cleaning all artifacts..."
	find . -type d -name ".zig-cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "zig-out" -exec rm -rf {} + 2>/dev/null || true

# ============================================================================
# Development Helpers
# ============================================================================

# Watch and rebuild on file changes (requires fswatch)
watch:
	@echo "Watching for changes... (requires fswatch)"
	@which fswatch >/dev/null 2>&1 || { echo "❌ fswatch not installed"; exit 1; }
	@fswatch -o . -r -e "zig-cache|zig-out" | xargs -n1 -I{} make build

# Generate documentation
docs:
	@echo "Generating documentation..."
	$(ZIG) build-exe src/lib.zig --emit-docs -femit-docs=$(BUILD_DIR)/docs

# Install dependencies
deps:
	@echo "Installing dependencies..."
	$(ZIG) fetch

# Update dependencies
deps-update:
	@echo "Updating dependencies..."
	$(ZIG) fetch --save

# ============================================================================
# Help Target
# ============================================================================

help:
	@echo "LLVMScope Build System"
	@echo ""
	@echo "Build Targets:"
	@echo "  make build         - Build in dev mode (default)"
	@echo "  make release       - Build in release mode with LTO"
	@echo "  make release-fast  - Build optimized for speed"
	@echo "  make release-small - Build optimized for size"
	@echo "  make debug         - Build in debug mode"
	@echo ""
	@echo "Test Targets:"
	@echo "  make test          - Run all tests"
	@echo "  make test-verbose  - Run tests with verbose output"
	@echo "  make test-file     - Run specific test (FILE=path/to/test.zig)"
	@echo ""
	@echo "Run Targets:"
	@echo "  make run           - Build and run the application"
	@echo "  make run-args      - Run with args (ARGS=\"arg1 arg2\")"
	@echo ""
	@echo "Code Quality Targets:"
	@echo "  make fmt           - Format all Zig code"
	@echo "  make check         - Check for errors (0 errors = pass)"
	@echo "  make check-fmt     - Check code format without fixing"
	@echo "  make fix-fmt       - Fix code format"
	@echo "  make lint          - Run linter (errors only)"
	@echo "  make check-all     - Run all checks (format + build)"
	@echo ""
	@echo "Clean Targets:"
	@echo "  make clean         - Clean build artifacts"
	@echo "  make clean-cache   - Clean cache only"
	@echo "  make clean-bin     - Clean binaries only"
	@echo "  make clean-all     - Deep clean all artifacts"
	@echo ""
	@echo "Development Helpers:"
	@echo "  make watch         - Watch and rebuild (requires fswatch)"
	@echo "  make docs          - Generate documentation"
	@echo "  make deps          - Install dependencies"
	@echo "  make deps-update   - Update dependencies"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make build && make run"
	@echo "  make release && make test"
	@echo "  make check-all"
	@echo ""

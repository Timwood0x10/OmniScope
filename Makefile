.PHONY: all build test check fmt clean help release release-fast release-small

# Default target
all: build

# Build the project
build:
	@echo "Building OmniSope (dev mode)..."
	@zig build

# Release builds
release:
	@echo "Building OmniSope (ReleaseSafe)..."
	@zig build -Doptimize=ReleaseSafe

release-fast:
	@echo "Building OmniSope (ReleaseFast with LTO)..."
	@zig build -Doptimize=ReleaseFast -Denable-lto

release-small:
	@echo "Building OmniSope (ReleaseSmall with LTO)..."
	@zig build -Doptimize=ReleaseSmall -Denable-lto

# Run tests (uses zig build test for proper LLVM linking)
test:
	@echo "Running tests..."
	@zig build test

# Run tests via build system (alias for 'test')
test-build:
	@echo "Running tests via build system..."
	@zig build test

# Check for errors (acceptance criteria: 0 errors)
check:
	@echo "Checking code for errors..."
	@if zig build 2>&1 | grep -q "error:"; then \
		echo "❌ Check failed: errors found"; \
		exit 1; \
	else \
		echo "✅ Check passed: 0 errors"; \
	fi

# Format code
fmt:
	@echo "Formatting Zig code..."
	@zig fmt .

# Check formatting
check-fmt:
	@echo "Checking code formatting..."
	@zig fmt --check .

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf zig-cache zig-out

# Clean everything including test files
clean-all:
	@echo "Cleaning everything..."
	@rm -rf zig-cache zig-out test_* *.zig.bak

# Build runtime library
rt:
	@echo "Building runtime library..."
	@zig build rt

# Run the application
run:
	@echo "Running OmniSope..."
	@zig build run

# Help message
help:
	@echo "Available targets:"
	@echo "  make build          - Build the project (dev mode)"
	@echo "  make release        - Build with ReleaseSafe optimization"
	@echo "  make release-fast   - Build with ReleaseFast + LTO"
	@echo "  make release-small  - Build with ReleaseSmall + LTO"
	@echo "  make test           - Run tests (direct, shows output)"
	@echo "  make test-build     - Run tests via build system"
	@echo "  make check          - Check for compilation errors"
	@echo "  make fmt            - Format code"
	@echo "  make check-fmt      - Check code formatting"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make clean-all      - Clean everything including test files"
	@echo "  make rt             - Build runtime library"
	@echo "  make run            - Run the application"
	@echo "  make help           - Show this help message"

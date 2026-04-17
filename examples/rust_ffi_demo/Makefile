# Makefile for OmniScope Killer Demo
#
# This builds the Rust + C demo and generates LLVM IR for analysis

.PHONY: all clean demo run ir analyze

# Directories
ROOT_DIR := ../..
BUILD_DIR := target
IR_DIR := $(BUILD_DIR)/ir

# Tools
CARGO := cargo
CLANG := clang
LLVM_LINK := /opt/homebrew/opt/llvm/bin/llvm-link
OMNISCOPE := $(ROOT_DIR)/zig-out/bin/OmniSope

# Output files
RUST_IR := $(IR_DIR)/rust.ll
C_IR := $(IR_DIR)/dangerous.ll
COMBINED_BC := $(BUILD_DIR)/combined.bc

# Default target
all: demo

# Build the demo (Rust + C)
demo:
	@echo "Building Rust + C demo..."
	$(CARGO) build --release

# Run the interactive demo
run: demo
	@echo "Running interactive demo..."
	$(CARGO) run --release

# Generate LLVM IR files
ir: $(IR_DIR)
	@echo "Generating LLVM IR..."
	
	# Generate Rust IR with debug info
	@echo "  - Compiling Rust to LLVM IR (with debug info)..."
	$(CARGO) rustc --release --lib -- --emit=llvm-ir -g
	@# Find and copy the generated Rust IR file from deps directory
	@find $(BUILD_DIR)/release/deps -name "rust_ffi_demo-*.ll" -exec cp {} $(RUST_IR) \;
	
	# Generate C IR with debug info
	@echo "  - Compiling C to LLVM IR (with debug info)..."
	$(CLANG) -S -emit-llvm -O0 -fno-discard-value-names -g \
		c_lib/dangerous.c -o $(C_IR)
	
	# Link IR files
	@echo "  - Linking IR files..."
	$(LLVM_LINK) $(RUST_IR) $(C_IR) -o $(COMBINED_BC)
	
	@echo "IR files generated in $(IR_DIR)/"
	@ls -la $(IR_DIR)/

# Run OmniScope analysis
analyze: ir
	@echo "Running OmniScope analysis..."
	$(OMNISCOPE) $(COMBINED_BC)

# Create IR directory
$(IR_DIR):
	mkdir -p $(IR_DIR)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	$(CARGO) clean
	rm -rf $(BUILD_DIR)

# Full pipeline: build, generate IR, analyze
full: clean demo ir analyze

# Help
help:
	@echo "OmniScope Killer Demo - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the demo (default)"
	@echo "  demo     - Build Rust + C demo"
	@echo "  run      - Run interactive demo"
	@echo "  ir       - Generate LLVM IR files"
	@echo "  analyze  - Run OmniScope analysis"
	@echo "  full     - Clean, build, generate IR, analyze"
	@echo "  clean    - Remove build artifacts"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Example:"
	@echo "  make full    # Complete pipeline"
	@echo "  make analyze # Just run analysis"

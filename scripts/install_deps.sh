#!/bin/bash
# OmniScope Dependencies Installer
# Supports: macOS (Homebrew) and Linux (apt-get)
# Usage: ./scripts/install_deps.sh [--llvm-version=22]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LLVM_VERSION=22
ZIG_VERSION="0.15.0"

for arg in "$@"; do
    case $arg in
        --llvm-version=*)
            LLVM_VERSION="${arg#*=}"
            shift
            ;;
        --zig-version=*)
            ZIG_VERSION="${arg#*=}"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --llvm-version=N    LLVM version to install (default: 22)"
            echo "  --zig-version=N     Zig version to install (default: 0.15.0)"
            echo "  --help              Show this help message"
            exit 0
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_step() { echo -e "${GREEN}[INSTALL]${NC} $1"; }
echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_header() { echo -e "${BLUE}========================================${NC}"; }

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "redhat"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo_header
echo_step "Detected OS: $OS"
echo_step "LLVM version: $LLVM_VERSION"
echo_step "Zig version: $ZIG_VERSION"
echo_header

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    fi
    return 1
}

install_macos() {
    echo_step "Installing dependencies for macOS..."
    
    if ! check_command brew; then
        echo_error "Homebrew not found. Please install Homebrew first:"
        echo_info "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    echo_step "Updating Homebrew..."
    brew update
    
    echo_step "Installing LLVM $LLVM_VERSION..."
    if ! brew list "llvm@$LLVM_VERSION" &> /dev/null; then
        brew install "llvm@$LLVM_VERSION"
    else
        echo_info "LLVM $LLVM_VERSION already installed"
    fi
    
    echo_step "Installing Zig..."
    if ! check_command zig; then
        brew install zig
    else
        echo_info "Zig already installed: $(zig version)"
    fi
    
    echo_step "Installing additional tools..."
    brew install cmake || true
    
    echo_step "Configuring LLVM paths..."
    LLVM_PREFIX="/opt/homebrew/opt/llvm@$LLVM_VERSION"
    if [[ -d "$LLVM_PREFIX" ]]; then
        echo_info "LLVM installed at: $LLVM_PREFIX"
        echo_info "Add to your shell config:"
        echo_info "  export LLVM_PREFIX=$LLVM_PREFIX"
        echo_info "  export PATH=\"\$LLVM_PREFIX/bin:\$PATH\""
    fi
}

install_debian() {
    echo_step "Installing dependencies for Debian/Ubuntu..."
    
    if ! check_command sudo; then
        echo_error "sudo not found. Please run as root or install sudo."
        exit 1
    fi
    
    echo_step "Updating package lists..."
    sudo apt-get update
    
    echo_step "Installing build essentials..."
    sudo apt-get install -y build-essential cmake
    
    echo_step "Installing LLVM $LLVM_VERSION..."
    sudo apt-get install -y \
        "llvm-$LLVM_VERSION-dev" \
        "libllvm$LLVM_VERSION" \
        "clang-$LLVM_VERSION" \
        "libclang-$LLVM_VERSION-dev" \
        "libpolly-$LLVM_VERSION-dev" || {
        echo_error "LLVM $LLVM_VERSION not found in apt. Trying to add LLVM apt repo..."
        
        wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
        sudo add-apt-repository -y "deb http://apt.llvm.org/$(lsb_release -sc)/ llvm-toolchain-$(lsb_release -sc)-$LLVM_VERSION main" || true
        sudo apt-get update
        sudo apt-get install -y "llvm-$LLVM_VERSION-dev" "libllvm$LLVM_VERSION" "clang-$LLVM_VERSION"
    }
    
    echo_step "Installing Zig..."
    if ! check_command zig; then
        ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/zig-linux-x86_64-$ZIG_VERSION.tar.xz"
        echo_info "Downloading Zig from $ZIG_URL"
        cd /tmp
        wget -q "$ZIG_URL" -O zig.tar.xz
        sudo tar -xf zig.tar.xz -C /usr/local --strip-components=1
        rm zig.tar.xz
        cd "$PROJECT_ROOT"
    else
        echo_info "Zig already installed: $(zig version)"
    fi
    
    echo_step "Configuring LLVM paths..."
    LLVM_PREFIX="/usr/lib/llvm-$LLVM_VERSION"
    if [[ -d "$LLVM_PREFIX" ]]; then
        echo_info "LLVM installed at: $LLVM_PREFIX"
        echo_info "Add to your shell config:"
        echo_info "  export LLVM_PREFIX=$LLVM_PREFIX"
        echo_info "  export PATH=\"\$LLVM_PREFIX/bin:\$PATH\""
    fi
}

install_redhat() {
    echo_step "Installing dependencies for RedHat/Fedora..."
    
    echo_step "Installing build essentials..."
    sudo dnf install -y gcc cmake make || sudo yum install -y gcc cmake make
    
    echo_step "Installing LLVM $LLVM_VERSION..."
    sudo dnf install -y "llvm$LLVM_VERSION-devel" "clang$LLVM_VERSION-devel" || \
    sudo yum install -y "llvm$LLVM_VERSION-devel" "clang$LLVM_VERSION-devel" || {
        echo_error "LLVM $LLVM_VERSION not found. Please install manually."
    }
    
    echo_step "Installing Zig..."
    if ! check_command zig; then
        ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/zig-linux-x86_64-$ZIG_VERSION.tar.xz"
        echo_info "Downloading Zig from $ZIG_URL"
        cd /tmp
        curl -L "$ZIG_URL" -o zig.tar.xz
        sudo tar -xf zig.tar.xz -C /usr/local --strip-components=1
        rm zig.tar.xz
        cd "$PROJECT_ROOT"
    fi
}

verify_installation() {
    echo_header
    echo_step "Verifying installation..."
    
    echo_info "Zig version: $(zig version 2>/dev/null || echo 'NOT FOUND')"
    
    if check_command llvm-config; then
        echo_info "LLVM version: $(llvm-config --version)"
        echo_info "LLVM prefix: $(llvm-config --prefix)"
    else
        echo_info "LLVM: checking alternative paths..."
        if [[ "$OS" == "macos" ]]; then
            LLVM_CONFIG="/opt/homebrew/opt/llvm@$LLVM_VERSION/bin/llvm-config"
            if [[ -x "$LLVM_CONFIG" ]]; then
                echo_info "LLVM version: $($LLVM_CONFIG --version)"
                echo_info "LLVM prefix: $($LLVM_CONFIG --prefix)"
            fi
        fi
    fi
    
    echo_header
    echo_step "Installation complete!"
    echo_info "Run 'make build' to build OmniScope"
}

case "$OS" in
    macos)
        install_macos
        ;;
    debian)
        install_debian
        ;;
    redhat)
        install_redhat
        ;;
    *)
        echo_error "Unsupported OS: $OS"
        echo_info "Supported: macOS, Debian/Ubuntu, RedHat/Fedora"
        exit 1
        ;;
esac

verify_installation

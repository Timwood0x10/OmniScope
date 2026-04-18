#!/bin/bash
# OmniScope Release Script
# Builds release binaries for multiple platforms
# Usage: ./scripts/release.sh [--version=X.Y.Z]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"

VERSION=""
VERSION_FILE="$PROJECT_ROOT/VERSION"

for arg in "$@"; do
    case $arg in
        --version=*)
            VERSION="${arg#*=}"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --version=X.Y.Z   Version tag for release (default: from VERSION file)"
            echo "  --help            Show this help message"
            exit 0
            ;;
    esac
done

if [[ -z "$VERSION" ]] && [[ -f "$VERSION_FILE" ]]; then
    VERSION=$(cat "$VERSION_FILE")
fi

if [[ -z "$VERSION" ]]; then
    VERSION="0.2.0"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_step() { echo -e "${GREEN}[RELEASE]${NC} $1"; }
echo_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_header() { echo -e "${BLUE}========================================${NC}"; }

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
ARCH=$(uname -m)

echo_header
echo_step "OmniScope Release Build"
echo_step "Version: $VERSION"
echo_step "OS: $OS"
echo_step "Architecture: $ARCH"
echo_header

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

build_release() {
    local target="$1"
    local output_name="$2"
    
    echo_step "Building for $target..."
    
    cd "$PROJECT_ROOT"
    
    if [[ "$target" == "native" ]]; then
        zig build -Doptimize=ReleaseFast -Dtarget=native
    else
        zig build -Doptimize=ReleaseFast -Dtarget="$target"
    fi
    
    local bin_path="zig-out/bin/OmniScope"
    if [[ -f "$bin_path" ]]; then
        cp "$bin_path" "$DIST_DIR/$output_name"
        chmod +x "$DIST_DIR/$output_name"
        echo_info "Created: $DIST_DIR/$output_name"
    else
        echo_error "Binary not found: $bin_path"
        return 1
    fi
}

create_archive() {
    local archive_name="$1"
    local binary_name="$2"
    
    echo_step "Creating archive: $archive_name..."
    
    cd "$DIST_DIR"
    
    if [[ "$OS" == "macos" ]]; then
        tar -czf "$archive_name.tar.gz" "$binary_name"
    else
        tar -czf "$archive_name.tar.gz" "$binary_name"
    fi
    
    echo_info "Created: $DIST_DIR/$archive_name.tar.gz"
}

generate_checksums() {
    echo_step "Generating checksums..."
    
    cd "$DIST_DIR"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum *.tar.gz > checksums.sha256
    else
        shasum -a 256 *.tar.gz > checksums.sha256
    fi
    
    echo_info "Created: $DIST_DIR/checksums.sha256"
}

generate_release_notes() {
    local notes_file="$DIST_DIR/RELEASE_NOTES.md"
    
    echo_step "Generating release notes..."
    
    cat > "$notes_file" << EOF
# OmniScope v$VERSION

## Download

| Platform | Architecture | Download |
|----------|--------------|----------|
| macOS | x86_64 | OmniScope-$VERSION-macos-x86_64.tar.gz |
| macOS | aarch64 | OmniScope-$VERSION-macos-aarch64.tar.gz |
| Linux | x86_64 | OmniScope-$VERSION-linux-x86_64.tar.gz |
| Linux | aarch64 | OmniScope-$VERSION-linux-aarch64.tar.gz |

## Requirements

- LLVM 21+
- Zig 0.15.2+

## Installation

\`\`\`bash
# Download and extract
tar -xzf OmniScope-$VERSION-<platform>-<arch>.tar.gz

# Run
./OmniScope --help
\`\`\`

## Changes

See [CHANGELOG.md](../CHANGELOG.md) for details.
EOF
    
    echo_info "Created: $notes_file"
}

case "$OS-$ARCH" in
    macos-arm64|macos-aarch64)
        build_release "native" "OmniScope-$VERSION-macos-aarch64"
        create_archive "OmniScope-$VERSION-macos-aarch64" "OmniScope-$VERSION-macos-aarch64"
        ;;
    macos-x86_64)
        build_release "native" "OmniScope-$VERSION-macos-x86_64"
        create_archive "OmniScope-$VERSION-macos-x86_64" "OmniScope-$VERSION-macos-x86_64"
        ;;
    linux-x86_64)
        build_release "native" "OmniScope-$VERSION-linux-x86_64"
        create_archive "OmniScope-$VERSION-linux-x86_64" "OmniScope-$VERSION-linux-x86_64"
        ;;
    linux-aarch64)
        build_release "native" "OmniScope-$VERSION-linux-aarch64"
        create_archive "OmniScope-$VERSION-linux-aarch64" "OmniScope-$VERSION-linux-aarch64"
        ;;
    *)
        echo_error "Unsupported platform: $OS-$ARCH"
        echo_info "Building native target..."
        build_release "native" "OmniScope-$VERSION-$OS-$ARCH"
        create_archive "OmniScope-$VERSION-$OS-$ARCH" "OmniScope-$VERSION-$OS-$ARCH"
        ;;
esac

generate_checksums
generate_release_notes

echo_header
echo_step "Release build complete!"
echo_info "Artifacts in: $DIST_DIR"
ls -la "$DIST_DIR"
echo_header

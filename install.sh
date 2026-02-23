#!/bin/bash
set -e

# orca installer for macOS
# Usage: curl -fsSL https://raw.githubusercontent.com/rasca/orca/main/install.sh | bash
#    or: ./install.sh

ORCA_REPO="https://github.com/rasca/orca.git"
ORCA_DIR="${ORCA_INSTALL_DIR:-$HOME/Dev/orchestrator}"
ORCA_BIN_LINK="/usr/local/bin/orca"

echo "╔══════════════════════════════════════════════╗"
echo "║  orca — Docker-isolated session orchestrator ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ─── Check macOS ────────────────────────────────────────────────────────────

if [ "$(uname)" != "Darwin" ]; then
    echo "Error: This installer is for macOS only"
    exit 1
fi

# ─── Check and install dependencies ─────────────────────────────────────────

check_dep() {
    local name="$1"
    local check_cmd="$2"
    local install_msg="$3"

    if eval "$check_cmd" > /dev/null 2>&1; then
        local version
        version=$($4 2>&1 | head -1)
        echo "  [ok] $name — $version"
        return 0
    else
        echo "  [missing] $name"
        return 1
    fi
}

echo "Checking dependencies..."
echo ""

missing=()

if command -v docker > /dev/null 2>&1; then
    echo "  [ok] Docker — $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    echo "  [MISSING] Docker Desktop"
    echo "           Install from: https://www.docker.com/products/docker-desktop/"
    missing+=("docker")
fi

if command -v tmux > /dev/null 2>&1; then
    echo "  [ok] tmux — $(tmux -V)"
else
    echo "  [missing] tmux"
    missing+=("tmux")
fi

if command -v git > /dev/null 2>&1; then
    echo "  [ok] git — $(git --version | cut -d' ' -f3)"
else
    echo "  [missing] git"
    missing+=("git")
fi

if command -v gh > /dev/null 2>&1; then
    echo "  [ok] gh — $(gh --version | head -1 | cut -d' ' -f3)"
else
    echo "  [missing] gh (GitHub CLI)"
    missing+=("gh")
fi

if command -v jq > /dev/null 2>&1; then
    echo "  [ok] jq — $(jq --version)"
else
    echo "  [missing] jq"
    missing+=("jq")
fi

if command -v yq > /dev/null 2>&1; then
    echo "  [ok] yq — $(yq --version | head -1)"
else
    echo "  [missing] yq"
    missing+=("yq")
fi

echo ""

# Install missing brew packages
brew_packages=()
for dep in "${missing[@]}"; do
    case "$dep" in
        docker)
            echo "Error: Docker Desktop must be installed manually."
            echo "Download from: https://www.docker.com/products/docker-desktop/"
            exit 1
            ;;
        tmux|git|gh|jq|yq)
            brew_packages+=("$dep")
            ;;
    esac
done

if [ ${#brew_packages[@]} -gt 0 ]; then
    if ! command -v brew > /dev/null 2>&1; then
        echo "Error: Homebrew is required to install missing dependencies."
        echo "Install from: https://brew.sh"
        exit 1
    fi

    echo "Installing missing packages via Homebrew: ${brew_packages[*]}"
    brew install "${brew_packages[@]}"
    echo ""
    echo "Dependencies installed."
    echo ""
fi

# ─── Install orca ───────────────────────────────────────────────────────────

if [ -d "$ORCA_DIR/.git" ]; then
    echo "orca source found at $ORCA_DIR"
    echo "Pulling latest..."
    git -C "$ORCA_DIR" pull --ff-only 2>/dev/null || echo "  (already up to date or local changes)"
else
    echo "Cloning orca to $ORCA_DIR..."
    mkdir -p "$(dirname "$ORCA_DIR")"
    git clone "$ORCA_REPO" "$ORCA_DIR"
fi

echo ""

# Make executable
chmod +x "$ORCA_DIR/bin/orca"

# Create symlink
if [ -L "$ORCA_BIN_LINK" ]; then
    echo "Updating symlink: $ORCA_BIN_LINK"
    rm "$ORCA_BIN_LINK"
elif [ -f "$ORCA_BIN_LINK" ]; then
    echo "Warning: $ORCA_BIN_LINK already exists and is not a symlink. Skipping."
    echo "You can manually link: ln -sf $ORCA_DIR/bin/orca $ORCA_BIN_LINK"
    ORCA_BIN_LINK=""
fi

if [ -n "$ORCA_BIN_LINK" ]; then
    if [ -w "$(dirname "$ORCA_BIN_LINK")" ]; then
        ln -sf "$ORCA_DIR/bin/orca" "$ORCA_BIN_LINK"
        echo "Linked: $ORCA_BIN_LINK -> $ORCA_DIR/bin/orca"
    else
        echo "Creating symlink (requires sudo)..."
        sudo ln -sf "$ORCA_DIR/bin/orca" "$ORCA_BIN_LINK"
        echo "Linked: $ORCA_BIN_LINK -> $ORCA_DIR/bin/orca"
    fi
fi

echo ""

# ─── Build Docker image ────────────────────────────────────────────────────

echo "Checking if Docker is running..."
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Start Docker Desktop and re-run:"
    echo "  orca build"
    echo ""
    echo "orca is installed but the Docker image needs to be built."
    echo ""
    echo "Once Docker is running:"
    echo "  orca build"
    echo ""
    exit 0
fi

echo ""
read -p "Build the orca base Docker image now? This takes a few minutes. (y/n) [y]: " build_choice
build_choice=${build_choice:-y}

if [ "$build_choice" = "y" ] || [ "$build_choice" = "Y" ]; then
    echo ""
    "$ORCA_DIR/bin/orca" build
else
    echo ""
    echo "Skipped image build. Run 'orca build' when ready."
fi

# ─── Done ───────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  orca installed successfully!                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Get started:"
echo "  cd ~/Dev/myproject"
echo "  orca init                  # Generate orchestrator.yml"
echo "  orca add my-feature        # Create sandboxed session"
echo "  orca attach my-feature     # Attach to tmux"
echo ""
echo "Claude Code plugin:"
echo "  claude plugin install $ORCA_DIR"
echo ""
echo "Full docs: https://github.com/rasca/orca"

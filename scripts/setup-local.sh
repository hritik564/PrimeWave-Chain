#!/usr/bin/env bash
# PrimeWave Chain — Local Environment Setup
# ==========================================
# ENVIRONMENT: LOCAL DEVELOPMENT ONLY
# NOT FOR TESTNET. NOT FOR MAINNET.
#
# What this script does:
#   1. Creates required directories
#   2. Downloads AvalancheGo v1.14.2 (pinned, exact version)
#   3. Downloads Avalanche CLI v1.9.5 (pinned, exact version)
#   4. Creates the PrimeWave dev blockchain configuration
#
# Usage: bash scripts/setup-local.sh
# Idempotent: safe to run multiple times.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# ── Architecture detection ────────────────────────────────────────────────────
ARCH="$(uname -m)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    arm64)   ARCH_SUFFIX="arm64" ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        log_error "Supported: x86_64 (amd64), aarch64/arm64"
        exit 1
        ;;
esac

case "$OS" in
    linux)   OS_SUFFIX="linux" ;;
    darwin)  OS_SUFFIX="darwin" ;;
    *)
        log_error "Unsupported OS: $OS"
        log_error "Supported: linux, darwin"
        exit 1
        ;;
esac

log_section "PrimeWave Chain — Local Setup"
echo -e "  ${BOLD}ENVIRONMENT:${NC}    LOCAL DEVELOPMENT ONLY"
echo -e "  ${BOLD}AvalancheGo:${NC}    $AVALANCHEGO_VERSION  (pinned)"
echo -e "  ${BOLD}Avalanche CLI:${NC}  $AVALANCHE_CLI_VERSION (pinned)"
echo -e "  ${BOLD}Platform:${NC}       $OS / $ARCH_SUFFIX"
echo -e "  ${BOLD}Chain ID:${NC}       $PRIMEWAVE_DEV_CHAIN_ID (DEV ONLY)"
echo -e "  ${BOLD}Token:${NC}          $PRIMEWAVE_TOKEN_SYMBOL ($PRIMEWAVE_TOKEN_NAME)"
echo ""

# ── Create directories ────────────────────────────────────────────────────────
log_section "Creating directories"
mkdir -p "$LOCAL_BIN_DIR"
mkdir -p "$LOCAL_DATA_DIR"
log_ok "Directory structure ready"

# ── Download AvalancheGo ──────────────────────────────────────────────────────
log_section "AvalancheGo $AVALANCHEGO_VERSION"

AVALANCHEGO_ARCHIVE="avalanchego-${OS_SUFFIX}-${ARCH_SUFFIX}-${AVALANCHEGO_VERSION}.tar.gz"
AVALANCHEGO_URL="https://github.com/ava-labs/avalanchego/releases/download/${AVALANCHEGO_VERSION}/${AVALANCHEGO_ARCHIVE}"
AVALANCHEGO_ARCHIVE_PATH="$LOCAL_BIN_DIR/$AVALANCHEGO_ARCHIVE"

if [[ -x "$AVALANCHEGO_BIN" ]]; then
    # AvalancheGo --version format: "avalanchego/1.14.2 [database=v1.4.5, ...]"
    INSTALLED_VER="v$("$AVALANCHEGO_BIN" --version 2>&1 | grep -oP 'avalanchego/\K[\d]+\.[\d]+\.[\d]+' | head -1 || echo unknown)"
    log_ok "AvalancheGo already installed: $INSTALLED_VER"
    if [[ "$INSTALLED_VER" != "$AVALANCHEGO_VERSION" ]]; then
        log_warn "Installed version ($INSTALLED_VER) differs from pinned ($AVALANCHEGO_VERSION)."
        log_warn "Delete $AVALANCHEGO_BIN and re-run this script to get the pinned version."
        log_warn "DO NOT use a different version — see PW-C00 FINAL GATE."
    fi
else
    log_info "Downloading: $AVALANCHEGO_URL"
    curl -fSL --progress-bar "$AVALANCHEGO_URL" -o "$AVALANCHEGO_ARCHIVE_PATH"

    log_info "Extracting AvalancheGo..."
    # AvalancheGo archive extracts to: avalanchego-v1.14.2/avalanchego
    tar -xzf "$AVALANCHEGO_ARCHIVE_PATH" -C "$LOCAL_BIN_DIR"
    # Find the extracted binary
    AVALANCHEGO_EXTRACTED=$(find "$LOCAL_BIN_DIR" -name "avalanchego" -type f | head -1)
    if [[ -z "$AVALANCHEGO_EXTRACTED" ]]; then
        log_error "Could not find avalanchego binary after extraction."
        log_error "Archive contents:"
        tar -tzf "$AVALANCHEGO_ARCHIVE_PATH" | head -20
        exit 1
    fi
    cp "$AVALANCHEGO_EXTRACTED" "$AVALANCHEGO_BIN"
    chmod +x "$AVALANCHEGO_BIN"
    rm -f "$AVALANCHEGO_ARCHIVE_PATH"

    # AvalancheGo --version format: "avalanchego/1.14.2 [database=v1.4.5, ...]"
    # The main version does NOT have a "v" prefix; extract it specifically.
    INSTALLED_VER="v$("$AVALANCHEGO_BIN" --version 2>&1 | grep -oP 'avalanchego/\K[\d]+\.[\d]+\.[\d]+' | head -1 || echo unknown)"
    log_ok "AvalancheGo installed: $INSTALLED_VER"

    if [[ "$INSTALLED_VER" != "$AVALANCHEGO_VERSION" ]]; then
        log_error "STOP: Installed version ($INSTALLED_VER) does not match pinned version ($AVALANCHEGO_VERSION)."
        log_error "This is a version incompatibility. Per PW-C01 failure policy: do not silently substitute."
        log_error "Investigate the GitHub release and update AVALANCHEGO_VERSION in _common.sh if approved."
        exit 1
    fi
fi

# ── Download Avalanche CLI ────────────────────────────────────────────────────
log_section "Avalanche CLI $AVALANCHE_CLI_VERSION"

# Avalanche CLI archive naming differs between versions:
# v1.9.5 uses: avalanche-cli_1.9.5_linux_amd64.tar.gz
CLI_VER_STRIPPED="${AVALANCHE_CLI_VERSION#v}"
AVALANCHE_CLI_ARCHIVE="avalanche-cli_${CLI_VER_STRIPPED}_${OS_SUFFIX}_${ARCH_SUFFIX}.tar.gz"
AVALANCHE_CLI_URL="https://github.com/ava-labs/avalanche-cli/releases/download/${AVALANCHE_CLI_VERSION}/${AVALANCHE_CLI_ARCHIVE}"
AVALANCHE_CLI_ARCHIVE_PATH="$LOCAL_BIN_DIR/$AVALANCHE_CLI_ARCHIVE"

if [[ -x "$AVALANCHE_CLI_BIN" ]]; then
    CLI_VER="$("$AVALANCHE_CLI_BIN" --version 2>&1 | grep -oP 'v[\d]+\.[\d]+\.[\d]+' | head -1 || echo unknown)"
    log_ok "Avalanche CLI already installed: $CLI_VER"
else
    log_info "Downloading: $AVALANCHE_CLI_URL"
    curl -fSL --progress-bar "$AVALANCHE_CLI_URL" -o "$AVALANCHE_CLI_ARCHIVE_PATH"

    log_info "Extracting Avalanche CLI..."
    # Extract to a temp dir to avoid self-copy (CLI archive has binary at root level)
    CLI_TMP_DIR="$(mktemp -d)"
    tar -xzf "$AVALANCHE_CLI_ARCHIVE_PATH" -C "$CLI_TMP_DIR"
    # CLI binary is named 'avalanche' in the archive
    AVALANCHE_CLI_EXTRACTED=$(find "$CLI_TMP_DIR" -name "avalanche" -type f | head -1)
    if [[ -z "$AVALANCHE_CLI_EXTRACTED" ]]; then
        log_error "Could not find avalanche binary after extraction."
        log_error "Archive contents:"
        tar -tzf "$AVALANCHE_CLI_ARCHIVE_PATH" | head -20
        rm -rf "$CLI_TMP_DIR"
        exit 1
    fi
    cp "$AVALANCHE_CLI_EXTRACTED" "$AVALANCHE_CLI_BIN"
    chmod +x "$AVALANCHE_CLI_BIN"
    rm -rf "$CLI_TMP_DIR"
    rm -f "$AVALANCHE_CLI_ARCHIVE_PATH"

    CLI_VER="$("$AVALANCHE_CLI_BIN" --version 2>&1 | grep -oP 'v[\d]+\.[\d]+\.[\d]+' | head -1 || echo unknown)"
    log_ok "Avalanche CLI installed: $CLI_VER"
fi

# ── Download subnet-evm plugin binary ────────────────────────────────────────
log_section "subnet-evm VM Plugin $AVALANCHEGO_VERSION"
# subnet-evm is now released alongside AvalancheGo (since v1.14.x grafting).
# It must match the AvalancheGo version exactly (rpcchainvm protocol must match).
SUBNET_EVM_BIN="$LOCAL_BIN_DIR/subnet-evm"
SUBNET_EVM_ARCHIVE="subnet-evm-${OS_SUFFIX}-${ARCH_SUFFIX}-${AVALANCHEGO_VERSION}.tar.gz"
SUBNET_EVM_URL="https://github.com/ava-labs/avalanchego/releases/download/${AVALANCHEGO_VERSION}/${SUBNET_EVM_ARCHIVE}"

if [[ -x "$SUBNET_EVM_BIN" ]]; then
    SEVM_VER="$("$SUBNET_EVM_BIN" --version 2>&1 | grep -oP 'Subnet-EVM/\K[^\s]+' | head -1 || echo unknown)"
    log_ok "subnet-evm already installed: $SEVM_VER"
    SEVM_RPC="$("$SUBNET_EVM_BIN" --version 2>&1 | grep -oP 'rpcchainvm=\K\d+' | head -1 || echo unknown)"
    log_info "  rpcchainvm: $SEVM_RPC (must match AvalancheGo's rpcchainvm)"
else
    log_info "Downloading: $SUBNET_EVM_URL"
    SUBNET_EVM_ARCHIVE_PATH="$LOCAL_BIN_DIR/$SUBNET_EVM_ARCHIVE"
    curl -fSL --progress-bar "$SUBNET_EVM_URL" -o "$SUBNET_EVM_ARCHIVE_PATH"

    log_info "Extracting subnet-evm..."
    SEVM_TMP_DIR="$(mktemp -d)"
    tar -xzf "$SUBNET_EVM_ARCHIVE_PATH" -C "$SEVM_TMP_DIR"

    # Binary is inside a versioned subdirectory: subnet-evm-v1.14.2/subnet-evm
    SEVM_EXTRACTED=$(find "$SEVM_TMP_DIR" -name "subnet-evm" -type f -not -name "._*" | head -1)
    if [[ -z "$SEVM_EXTRACTED" ]]; then
        log_error "Could not find subnet-evm binary after extraction."
        tar -tzf "$SUBNET_EVM_ARCHIVE_PATH" | head -20
        rm -rf "$SEVM_TMP_DIR"
        exit 1
    fi
    cp "$SEVM_EXTRACTED" "$SUBNET_EVM_BIN"
    chmod +x "$SUBNET_EVM_BIN"
    rm -rf "$SEVM_TMP_DIR"
    rm -f "$SUBNET_EVM_ARCHIVE_PATH"

    SEVM_VER="$("$SUBNET_EVM_BIN" --version 2>&1 | head -1 || echo unknown)"
    log_ok "subnet-evm installed: $SEVM_VER"
fi

# ── Version compatibility check ───────────────────────────────────────────────
log_section "Dependency Version Check"

echo -e "  AvalancheGo binary:  $("$AVALANCHEGO_BIN" --version 2>&1 | head -1)"
echo -e "  Avalanche CLI:       $("$AVALANCHE_CLI_BIN" --version 2>&1 | head -1)"
echo ""
log_info "AvalancheGo v1.14.2 is the pinned version (PW-C00 FINAL GATE)."
log_info "Avalanche CLI v1.9.5 uses avalanche-network-runner internally."
log_info "CLI will be invoked with --avalanchego-path flag to enforce exact binary."
log_warn "KNOWN LIMITATION: Avalanche CLI v1.9.5 entered maintenance mode Dec 2025."
log_warn "  It was built before AvalancheGo v1.14.2 (Mar 2026)."
log_warn "  The --avalanchego-path flag ensures CLI uses our exact pinned binary."
log_warn "  If --avalanchego-path is unsupported, see docs/PW-C01-LOCAL-DEVELOPMENT.md."

# ── Create blockchain configuration ──────────────────────────────────────────
log_section "PrimeWave Dev Blockchain Configuration"

CLI_SUBNET_DIR="$HOME/.avalanche-cli/subnets/$PRIMEWAVE_CHAIN_NAME"

if [[ -d "$CLI_SUBNET_DIR" ]] && [[ -f "$CLI_SUBNET_DIR/sidecar.json" ]]; then
    log_ok "Blockchain configuration already exists: $CLI_SUBNET_DIR"
    log_info "Run 'bash scripts/reset-local.sh' to recreate from scratch."
else
    log_info "Creating blockchain config: $PRIMEWAVE_CHAIN_NAME"
    log_info "  Chain ID: $PRIMEWAVE_DEV_CHAIN_ID (DEV ONLY)"
    log_info "  Token:    $PRIMEWAVE_TOKEN_SYMBOL ($PRIMEWAVE_TOKEN_NAME)"
    log_info "  Genesis:  $CHAIN_DIR/genesis/dev-genesis.json"
    log_info ""
    log_info "APPROACH: Direct config file creation (bypasses interactive wizard)."
    log_info "  Reason: Avalanche CLI v$AVALANCHE_CLI_VERSION uses an interactive terminal"
    log_info "  wizard (survey/bubbletea library) that fails in non-TTY environments."
    log_info "  We create the genesis.json and sidecar.json directly, matching the"
    log_info "  format that the CLI writes after a successful interactive create."

    mkdir -p "$CLI_SUBNET_DIR"

    # ── Genesis file ────────────────────────────────────────────────────────
    cp "$CHAIN_DIR/genesis/dev-genesis.json" "$CLI_SUBNET_DIR/genesis.json"
    log_ok "  Genesis installed: $CLI_SUBNET_DIR/genesis.json"

    # ── Sidecar file ────────────────────────────────────────────────────────
    # VM type: "subnet-evm" (from binary string table in avalanche CLI binary)
    # RPCVersion: 45 (from 'avalanchego --version' → rpcchainvm=45)
    # ValidatorManagement: "Proof Of Authority" (from binary string table)
    # Sovereign: true (ACP-77 L1 — local deploy default)
    cat > "$CLI_SUBNET_DIR/sidecar.json" <<SIDECAR_EOF
{
  "Name": "$PRIMEWAVE_CHAIN_NAME",
  "VM": "subnet-evm",
  "VMVersion": "",
  "RPCVersion": 45,
  "Subnet": "$PRIMEWAVE_CHAIN_NAME",
  "ExternalToken": false,
  "TokenName": "$PRIMEWAVE_TOKEN_NAME",
  "TokenSymbol": "$PRIMEWAVE_TOKEN_SYMBOL",
  "ChainID": "$PRIMEWAVE_DEV_CHAIN_ID",
  "Version": "",
  "Networks": {},
  "ImportedFromAPM": false,
  "ImportedVMID": "",
  "CustomVMRepoURL": "",
  "CustomVMBranch": "",
  "CustomVMBuildScript": "",
  "TeleporterReady": false,
  "TeleporterKey": "",
  "TeleporterVersion": "",
  "RunRelayer": false,
  "SubnetEVMMainnetChainID": 0,
  "ValidatorManagement": "Proof Of Authority",
  "ValidatorManagerOwner": "",
  "ProxyContractOwner": "",
  "Sovereign": true,
  "UseACP99": false
}
SIDECAR_EOF
    log_ok "  Sidecar installed: $CLI_SUBNET_DIR/sidecar.json"

    # ── Verify describe works ───────────────────────────────────────────────
    log_info "Verifying blockchain description..."
    "$AVALANCHE_CLI_BIN" blockchain describe "$PRIMEWAVE_CHAIN_NAME" \
        --skip-update-check 2>&1 | grep -E "Name|Token|Validation" || {
        log_error "blockchain describe failed after config creation."
        log_error "Sidecar format may be wrong. Check:"
        log_error "  $CLI_SUBNET_DIR/sidecar.json"
        exit 1
    }

    log_ok "Blockchain configuration created and verified."
fi

# ── Record setup state ────────────────────────────────────────────────────────
cat > "$LOCAL_DATA_DIR/setup-complete.env" <<EOF
SETUP_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AVALANCHEGO_VERSION_INSTALLED="$("$AVALANCHEGO_BIN" --version 2>&1 | head -1 | tr -d '\n')"
AVALANCHE_CLI_VERSION_INSTALLED="$("$AVALANCHE_CLI_BIN" --version 2>&1 | head -1 | tr -d '\n')"
PLATFORM="${OS_SUFFIX}/${ARCH_SUFFIX}"
CHAIN_NAME="$PRIMEWAVE_CHAIN_NAME"
CHAIN_ID="$PRIMEWAVE_DEV_CHAIN_ID"
EOF

# ── Done ──────────────────────────────────────────────────────────────────────
log_section "Setup Complete"
echo ""
echo -e "  ${GREEN}✓${NC} AvalancheGo $AVALANCHEGO_VERSION ready at: $AVALANCHEGO_BIN"
echo -e "  ${GREEN}✓${NC} Avalanche CLI $AVALANCHE_CLI_VERSION ready at: $AVALANCHE_CLI_BIN"
echo -e "  ${GREEN}✓${NC} Blockchain config: $PRIMEWAVE_CHAIN_NAME"
echo ""
echo -e "  ${BOLD}Next step:${NC}"
echo -e "    bash scripts/start-local.sh    — Start the local PrimeWave network"
echo ""
echo -e "  ${YELLOW}⚠ REMINDER: LOCAL DEVELOPMENT ONLY${NC}"
echo -e "    Chain ID $PRIMEWAVE_DEV_CHAIN_ID and all dev keys are for local use only."
echo ""

#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║              🏛️  ATLAS PLATFORM — Bootstrap Installer       ║
# ║              Infrastructure Provisioning System             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/leonidastcejorp/atlas-platform/main/install.sh)
#
# This script downloads and executes the main setup.sh deployment script.
# Run as root on a fresh Ubuntu 24.04 system.

set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              🏛️  ATLAS PLATFORM                               ║"
echo "║              Infrastructure Provisioning                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Downloading deployment script..."
echo ""

SCRIPT_URL="https://raw.githubusercontent.com/leonidastcejorp/atlas-platform/main/setup.sh"

if curl -sfL "$SCRIPT_URL" -o /tmp/atlas-setup.sh 2>/dev/null; then
    chmod +x /tmp/atlas-setup.sh
    echo "  ✅ Downloaded successfully."
    echo "  🚀 Launching ATLAS PLATFORM deployment..."
    echo ""
    exec bash /tmp/atlas-setup.sh
else
    echo ""
    echo "  ❌ Could not download setup.sh."
    echo ""
    echo "  Troubleshooting:"
    echo "    • Check your internet connection"
    echo "    • Verify GitHub is accessible from this server"
    echo "    • Try: curl -I $SCRIPT_URL"
    echo ""
    exit 1
fi

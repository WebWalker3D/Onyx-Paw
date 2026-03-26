#!/usr/bin/env bash
#
# Onyx Paw — Installation Script
#
# Installs the Onyx Paw agent on a remote machine so it can
# push project content to your central Onyx server.
#
# Usage:
#   git clone https://github.com/WebWalker3D/onyx-paw.git
#   cd onyx-paw
#   bash install.sh
#
# Environment variables (set before running, or you'll be prompted):
#   ONYX_SERVER      - Onyx server URL (e.g. https://www.onyxthedog.com)
#   ONYX_API_KEY     - API key for the Onyx server
#   ONYX_PAW_NAME    - Display name for this Paw (defaults to hostname)
#
set -euo pipefail

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
info()  { echo "[*] $*"; }
warn()  { echo "[!] $*" >&2; }
fatal() { echo "[FATAL] $*" >&2; exit 1; }

prompt() {
    local var_name="$1" prompt_text="$2" default="${3:-}"
    if [ -z "${!var_name:-}" ]; then
        if [ -n "$default" ]; then
            read -rp "$prompt_text [$default]: " value
            value="${value:-$default}"
        else
            read -rp "$prompt_text: " value
        fi
        if [ -z "$value" ]; then
            fatal "$var_name cannot be empty"
        fi
        eval "$var_name=\$value"
    fi
}

prompt_secret() {
    local var_name="$1" prompt_text="$2"
    if [ -z "${!var_name:-}" ]; then
        read -rsp "$prompt_text: " value
        echo
        if [ -z "$value" ]; then
            fatal "$var_name cannot be empty"
        fi
        eval "$var_name=\$value"
    fi
}

# -------------------------------------------------------------------
# Preflight
# -------------------------------------------------------------------
info "Onyx Paw installation starting..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify package is present
if [ ! -f "$SCRIPT_DIR/pyproject.toml" ] || [ ! -d "$SCRIPT_DIR/src/onyx_paw" ]; then
    fatal "Missing package files. Make sure you're running this from the onyx-paw repo root."
fi

# Check for Python
if ! command -v python3 &>/dev/null; then
    fatal "Python 3 is required. Install it first: apt install python3 python3-pip"
fi

if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
    fatal "pip is required. Install it first: apt install python3-pip"
fi

# Collect config
prompt ONYX_SERVER "Onyx server URL (e.g. https://www.onyxthedog.com)"
prompt_secret ONYX_API_KEY "Onyx API key"
prompt ONYX_PAW_NAME "Name for this Paw agent" "$(hostname)"

# -------------------------------------------------------------------
# 1. Install onyx-paw
# -------------------------------------------------------------------
info "Installing onyx-paw..."
pip3 install --quiet --break-system-packages "$SCRIPT_DIR"

# Verify
if ! command -v onyx-paw &>/dev/null; then
    fatal "onyx-paw command not found after install"
fi

info "onyx-paw installed: $(which onyx-paw)"

# -------------------------------------------------------------------
# 2. Register Paw with Onyx server
# -------------------------------------------------------------------
info "Registering Paw with Onyx server..."

REGISTER_RESPONSE=$(curl -sf -X POST "${ONYX_SERVER}/api/paws/register" \
    -H "Authorization: Bearer ${ONYX_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${ONYX_PAW_NAME}\", \"api_key\": \"${ONYX_API_KEY}\"}" 2>&1) || {
    fatal "Failed to register Paw with server. Check your ONYX_SERVER and ONYX_API_KEY.\nResponse: ${REGISTER_RESPONSE}"
}

PAW_ID=$(echo "$REGISTER_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

if [ -z "$PAW_ID" ]; then
    fatal "Failed to parse Paw ID from server response: ${REGISTER_RESPONSE}"
fi

info "Registered as Paw ID: ${PAW_ID}"

# -------------------------------------------------------------------
# 3. Initialize Paw config
# -------------------------------------------------------------------
info "Configuring onyx-paw..."
onyx-paw init --server "$ONYX_SERVER" --key "$ONYX_API_KEY" --paw-id "$PAW_ID"

# -------------------------------------------------------------------
# 4. Add projects (interactive)
# -------------------------------------------------------------------
echo ""
info "Paw is installed and registered. Now add projects to index."
echo ""

while true; do
    read -rp "Add a project? (y/n): " yn
    case "$yn" in
        [Yy]*)
            read -rp "  Path to project: " proj_path
            if [ ! -d "$proj_path" ]; then
                warn "  Directory not found: $proj_path"
                continue
            fi
            default_name=$(basename "$proj_path")
            read -rp "  Project name [$default_name]: " proj_name
            proj_name="${proj_name:-$default_name}"
            read -rp "  Type (repo/website/service/database) [repo]: " proj_type
            proj_type="${proj_type:-repo}"

            onyx-paw add "$proj_path" --name "$proj_name" --type "$proj_type"
            info "  Added: $proj_name"
            ;;
        *)
            break
            ;;
    esac
done

# -------------------------------------------------------------------
# 5. Initial push
# -------------------------------------------------------------------
echo ""
read -rp "Push all projects to Onyx now? (y/n): " do_push
if [[ "$do_push" =~ ^[Yy] ]]; then
    info "Pushing projects..."
    onyx-paw run
    info "Push complete."
fi

# -------------------------------------------------------------------
# 6. Cron setup (optional)
# -------------------------------------------------------------------
echo ""
read -rp "Set up automatic indexing via cron? (y/n): " do_cron
if [[ "$do_cron" =~ ^[Yy] ]]; then
    read -rp "Interval in hours [2]: " cron_hours
    cron_hours="${cron_hours:-2}"

    ONYX_PAW_BIN=$(which onyx-paw)
    CRON_LINE="0 */${cron_hours} * * * ${ONYX_PAW_BIN} run >> /var/log/onyx-paw.log 2>&1"

    # Add to crontab (avoid duplicates)
    (crontab -l 2>/dev/null | grep -v "onyx-paw run"; echo "$CRON_LINE") | crontab -

    info "Cron job added: every ${cron_hours} hours"
    info "Logs: /var/log/onyx-paw.log"
fi

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo ""
echo "============================================"
echo "  Onyx Paw installed successfully"
echo "============================================"
echo ""
echo "  Paw Name:    ${ONYX_PAW_NAME}"
echo "  Paw ID:      ${PAW_ID}"
echo "  Server:      ${ONYX_SERVER}"
echo "  Config:      ~/.onyx-paw.yaml"
echo ""
echo "  Commands:"
echo "    onyx-paw status       Show config and registered projects"
echo "    onyx-paw add <path>   Register a project to index"
echo "    onyx-paw run          Push all projects to Onyx now"
echo ""
echo "============================================"

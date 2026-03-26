#!/usr/bin/env bash
#
# Onyx Paw — Installer & Manager
#
# Fresh install:  git clone https://github.com/WebWalker3D/Onyx-Paw.git && cd Onyx-Paw && bash install.sh
# Manage:         bash install.sh   (detects existing installation)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.onyx-paw.yaml"

# -------------------------------------------------------------------
# Detect existing installation
# -------------------------------------------------------------------
if command -v onyx-paw &>/dev/null && [ -f "$CONFIG_FILE" ]; then
    # ---------------------------------------------------------------
    # MANAGEMENT MODE
    # ---------------------------------------------------------------
    echo ""
    echo "============================================"
    echo "  Onyx Paw — already installed"
    echo "============================================"
    echo ""
    onyx-paw status
    echo ""
    echo "  What would you like to do?"
    echo ""
    echo "    1) Update onyx-paw to latest version"
    echo "    2) Add a project"
    echo "    3) Remove a project"
    echo "    4) Push all projects now"
    echo "    5) Reconfigure cron schedule"
    echo "    6) Uninstall onyx-paw"
    echo "    7) Exit"
    echo ""

    while true; do
        read -rp "Choose [1-7]: " choice
        case "$choice" in
            1)
                info "Updating onyx-paw..."
                if [ -f "$SCRIPT_DIR/pyproject.toml" ] && [ -d "$SCRIPT_DIR/src/onyx_paw" ]; then
                    pip3 install --quiet --break-system-packages --upgrade "$SCRIPT_DIR"
                    info "Updated to latest version."
                else
                    fatal "Missing package files. Run from the Onyx-Paw repo directory."
                fi
                ;;
            2)
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
            3)
                # List projects with numbers
                echo ""
                PROJECTS=$(python3 -c "
import yaml
config = yaml.safe_load(open('$CONFIG_FILE'))
for i, p in enumerate(config.get('projects', [])):
    print(f\"  {i+1}) {p['name']}  ({p['path']})\")
if not config.get('projects'):
    print('  No projects configured.')
")
                echo "$PROJECTS"
                echo ""
                read -rp "  Project number to remove (or 0 to cancel): " proj_num
                if [ "$proj_num" != "0" ] && [ -n "$proj_num" ]; then
                    python3 -c "
import yaml
config = yaml.safe_load(open('$CONFIG_FILE'))
projects = config.get('projects', [])
idx = int('$proj_num') - 1
if 0 <= idx < len(projects):
    removed = projects.pop(idx)
    with open('$CONFIG_FILE', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    print(f'  Removed: {removed[\"name\"]}')
else:
    print('  Invalid selection.')
"
                fi
                ;;
            4)
                info "Pushing projects..."
                onyx-paw run
                info "Push complete."
                ;;
            5)
                read -rp "Interval in hours [2]: " cron_hours
                cron_hours="${cron_hours:-2}"
                ONYX_PAW_BIN=$(which onyx-paw)
                CRON_LINE="0 */${cron_hours} * * * ${ONYX_PAW_BIN} run >> /var/log/onyx-paw.log 2>&1"
                (crontab -l 2>/dev/null | grep -v "onyx-paw run"; echo "$CRON_LINE") | crontab -
                info "Cron updated: every ${cron_hours} hours"
                ;;
            6)
                echo ""
                warn "This will unregister this paw from the Onyx server,"
                warn "delete all its projects/documents, remove the local"
                warn "config, cron job, and uninstall the package."
                read -rp "Are you sure? (yes/no): " confirm
                if [ "$confirm" = "yes" ]; then
                    # Unregister from Onyx server
                    PAW_ID=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('paw_id',''))" 2>/dev/null || true)
                    SERVER=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('server',''))" 2>/dev/null || true)
                    API_KEY=$(python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE')).get('api_key',''))" 2>/dev/null || true)

                    if [ -n "$PAW_ID" ] && [ -n "$SERVER" ] && [ -n "$API_KEY" ]; then
                        info "Unregistering paw and deleting projects from server..."
                        if curl -sf -X DELETE "${SERVER}/api/paws/${PAW_ID}" \
                            -H "Authorization: Bearer ${API_KEY}" >/dev/null 2>&1; then
                            info "Paw and all projects removed from server."
                        else
                            warn "Could not reach server — paw may still be registered."
                            warn "You can remove it manually from the dashboard."
                        fi
                    fi

                    info "Removing cron job..."
                    (crontab -l 2>/dev/null | grep -v "onyx-paw run") | crontab - 2>/dev/null || true

                    info "Uninstalling onyx-paw package..."
                    pip3 uninstall -y onyx-paw --break-system-packages 2>/dev/null || true

                    info "Removing config..."
                    rm -f "$CONFIG_FILE"

                    echo ""
                    echo "============================================"
                    echo "  Onyx Paw has been uninstalled."
                    echo "============================================"
                    exit 0
                else
                    info "Uninstall cancelled."
                fi
                ;;
            7)
                exit 0
                ;;
            *)
                warn "Invalid choice."
                ;;
        esac
        echo ""
        read -rp "Do something else? (y/n): " again
        [[ "$again" =~ ^[Yy] ]] || break
    done
    exit 0
fi

# -------------------------------------------------------------------
# FRESH INSTALL MODE
# -------------------------------------------------------------------
info "Onyx Paw installation starting..."

# Verify package is present
if [ ! -f "$SCRIPT_DIR/pyproject.toml" ] || [ ! -d "$SCRIPT_DIR/src/onyx_paw" ]; then
    fatal "Missing package files. Make sure you're running this from the Onyx-Paw repo root."
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
echo "    bash install.sh       Manage installation"
echo ""
echo "============================================"

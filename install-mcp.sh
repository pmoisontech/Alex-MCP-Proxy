#!/bin/bash
#
# Alex MCP Proxy Installer for Linux/macOS/WSL
# Configures GitHub Copilot (VS Code) and/or Claude Desktop
#
# Usage:
#   Interactive mode:  ./install-mcp.sh
#   Automated mode:    ./install-mcp.sh --url URL --username USER --password PASS [--vscode] [--claude]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_API_URL="https://alex.api.pmats.ai"
SETUP_VSCODE=false
SETUP_CLAUDE=false
INTERACTIVE=true
EXPIRATION_DATE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --url)
      API_URL="$2"
      INTERACTIVE=false
      shift 2
      ;;
    --username)
      USERNAME="$2"
      INTERACTIVE=false
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      INTERACTIVE=false
      shift 2
      ;;
    --expiration-date)
      EXPIRATION_DATE="$2"
      shift 2
      ;;
    --vscode)
      SETUP_VSCODE=true
      shift
      ;;
    --claude)
      SETUP_CLAUDE=true
      shift
      ;;
    --help|-h)
      echo "Alex MCP Proxy Installer"
      echo ""
      echo "Usage:"
      echo "  Interactive mode:  ./install-mcp.sh"
      echo "  Automated mode:    ./install-mcp.sh --url URL --username USER --password PASS [--vscode] [--claude]"
      echo ""
      echo "Options:"
      echo "  --url URL           Backend API URL (default: https://alex.api.pmats.ai)"
      echo "  --username USER     Alex username"
      echo "  --password PASS     Alex password"
      echo "  --expiration-date   API key expiration date (ISO 8601 UTC, default: +3 months)"
      echo "  --vscode            Setup VS Code (GitHub Copilot)"
      echo "  --claude            Setup Claude Desktop"
      echo "  --help, -h          Show this help"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Banner
VERSION=$(cat "$SCRIPT_DIR/VERSION.txt" 2>/dev/null || echo "unknown")
echo -e "${BLUE}"
echo "   ___   _                "
echo "  / _ \ | |               "
echo " | |_| || |  ___  __  __ "
echo " |  _  || | / _ \/ \/ / "
echo " |_| |_||_||\___|_/\_\  "
echo -e "${NC}"

# Dynamic box with centered text
TEXT1="MCP Proxy Installer v${VERSION}"
TEXT2="Linux / macOS / WSL"
BOX_WIDTH=48

# Center text in box
center_text() {
  local text="$1"
  local width=$2
  local text_len=${#text}
  local padding=$(( (width - text_len) / 2 ))
  printf "%*s%s%*s" $padding "" "$text" $((width - text_len - padding)) ""
}

LINE1=$(center_text "$TEXT1" $BOX_WIDTH)
LINE2=$(center_text "$TEXT2" $BOX_WIDTH)

echo -e "${BLUE}╔$(printf '═%.0s' $(seq 1 $BOX_WIDTH))╗${NC}"
echo -e "${BLUE}║${LINE1}║${NC}"
echo -e "${BLUE}║${LINE2}║${NC}"
echo -e "${BLUE}╚$(printf '═%.0s' $(seq 1 $BOX_WIDTH))╝${NC}"
echo ""

# Preliminary checks
echo -e "${BLUE}[0/7]${NC} Preliminary checks..."

# Check required files
REQUIRED_FILES=("VERSION.txt" "package.json" "package-lock.json" "mcp-proxy-client.js")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$SCRIPT_DIR/$file" ]; then
    MISSING_FILES+=("$file")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo -e "${RED}✗ Missing required files:${NC}"
  for file in "${MISSING_FILES[@]}"; do
    echo -e "${RED}  - $file${NC}"
  done
  echo ""
  echo -e "${YELLOW}Please make sure you have cloned the complete repository:${NC}"
  echo -e "${YELLOW}  git clone https://github.com/pmoisontech/Alex-MCP-Proxy.git${NC}"
  exit 1
fi

echo -e "${GREEN}✓ All required files present${NC}"

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}ⓘ Not running as root${NC}"
  echo -e "${YELLOW}  (Root/sudo may be needed if Node.js installation is required)${NC}"
fi

echo ""

# Step 1: Check Node.js
echo -e "${BLUE}[1/7]${NC} Checking Node.js installation..."

# Function to install Node.js
install_nodejs() {
  local install_cmd=""
  local pkg_manager=""
  
  # Detect package manager
  if command -v apt &> /dev/null; then
    pkg_manager="apt"
    install_cmd="sudo apt update && sudo apt install -y nodejs npm"
  elif command -v dnf &> /dev/null; then
    pkg_manager="dnf"
    install_cmd="sudo dnf install -y nodejs npm"
  elif command -v yum &> /dev/null; then
    pkg_manager="yum"
    install_cmd="sudo yum install -y nodejs npm"
  elif command -v brew &> /dev/null; then
    pkg_manager="brew"
    install_cmd="brew install node"
  elif command -v pacman &> /dev/null; then
    pkg_manager="pacman"
    install_cmd="sudo pacman -S --noconfirm nodejs npm"
  fi
  
  if [ -n "$install_cmd" ]; then
    echo ""
    echo -e "${YELLOW}Node.js can be installed automatically using ${pkg_manager}${NC}"
    echo "Command: ${install_cmd}"
    echo ""
    
    if [ "$INTERACTIVE" = true ]; then
      read -p "Install Node.js now? [y/N]: " install_confirm
      if [[ "$install_confirm" =~ ^[Yy]$ ]]; then        # Check if sudo is required and available
        if [[ "$install_cmd" == sudo* ]]; then
          if ! command -v sudo &> /dev/null; then
            echo -e "${RED}✗ sudo is not available but required for installation${NC}"
            echo ""
            echo -e "${YELLOW}Please install Node.js manually or install sudo first${NC}"
            return 1
          fi
          
          # Check if we can use sudo
          if ! sudo -n true 2>/dev/null; then
            echo -e "${YELLOW}ⓘ You may be prompted for your password (sudo required)${NC}"
          fi
        fi
                echo "Installing Node.js..."
        eval "$install_cmd"
        
        # Verify installation
        if command -v node &> /dev/null; then
          echo -e "${GREEN}✓ Node.js $(node --version) installed successfully${NC}"
          return 0
        else
          echo -e "${RED}✗ Installation failed${NC}"
          return 1
        fi
      fi
    fi
  fi
  
  echo ""
  echo "Please install Node.js 18 or higher manually:"
  echo "  Download: https://nodejs.org/"
  return 1
}

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  echo -e "${RED}✗ Node.js is not installed${NC}"
  
  if install_nodejs; then
    # Installation successful, continue
    :
  else
    exit 1
  fi
fi

# Check Node.js version
NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo -e "${RED}✗ Node.js version $NODE_VERSION is too old (need ≥18)${NC}"
  echo -e "${YELLOW}Current version: $(node --version)${NC}"
  echo ""
  
  if install_nodejs; then
    # Check new version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
      echo -e "${RED}✗ Installed version is still too old${NC}"
      exit 1
    fi
  else
    exit 1
  fi
fi

echo -e "${GREEN}✓ Node.js $(node --version) detected${NC}"

# Step 2: Install npm dependencies
echo ""
echo -e "${BLUE}[2/7]${NC} Installing npm dependencies..."
cd "$SCRIPT_DIR"
if npm install --quiet; then
  echo -e "${GREEN}✓ Dependencies installed${NC}"
else
  echo -e "${RED}✗ npm install failed${NC}"
  exit 1
fi

# Step 3: Interactive configuration
if [ "$INTERACTIVE" = true ]; then
  echo ""
  echo -e "${BLUE}[3/7]${NC} Configuration"
  echo ""
  
  # API URL
  read -p "Backend API URL [${DEFAULT_API_URL}]: " API_URL
  API_URL=${API_URL:-$DEFAULT_API_URL}
  
  # Credentials
  read -p "Username: " USERNAME
  read -sp "Password: " PASSWORD
  echo ""
  
  # Setup choices
  echo ""
  read -p "Setup VS Code (GitHub Copilot)? [y/N]: " setup_vscode
  [[ "$setup_vscode" =~ ^[Yy]$ ]] && SETUP_VSCODE=true
  
  read -p "Setup Claude Desktop? [y/N]: " setup_claude
  [[ "$setup_claude" =~ ^[Yy]$ ]] && SETUP_CLAUDE=true
  
  if [ "$SETUP_VSCODE" = false ] && [ "$SETUP_CLAUDE" = false ]; then
    echo -e "${YELLOW}⚠ No setup selected. You must choose at least one.${NC}"
    exit 1
  fi
else
  echo ""
  echo -e "${BLUE}[3/7]${NC} Using provided configuration"
  API_URL=${API_URL:-$DEFAULT_API_URL}
  
  if [ "$SETUP_VSCODE" = false ] && [ "$SETUP_CLAUDE" = false ]; then
    echo -e "${YELLOW}⚠ No setup selected (--vscode or --claude required)${NC}"
    exit 1
  fi
fi

# Step 4: Login to backend and get JWT token
echo ""
echo -e "${BLUE}[4/7]${NC} Authenticating with Alex backend..."

LOGIN_RESPONSE=$(curl -s -X POST "${API_URL}/api/user/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}")

if echo "$LOGIN_RESPONSE" | grep -q "token"; then
  # Extract JWT token
  JWT_TOKEN=$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  echo -e "${GREEN}✓ Login successful${NC}"
  
  # Calculate expiration date (3 months from now or use provided date)
  if [ -z "$EXPIRATION_DATE" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS date command
      EXPIRATION_DATE=$(date -u -v+3m '+%Y-%m-%dT%H:%M:%SZ')
    else
      # Linux date command
      EXPIRATION_DATE=$(date -u -d '+3 months' '+%Y-%m-%dT%H:%M:%SZ')
    fi
  fi
  
  # Create API key via /api/user/api-keys
  echo -e "${BLUE}     ${NC} Generating MCP API key (expires: ${EXPIRATION_DATE})..."
  
  APIKEY_RESPONSE=$(curl -s -X POST "${API_URL}/api/user/api-keys" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${JWT_TOKEN}" \
    -d "{\"name\":\"MCP Server\",\"expires_at\":\"${EXPIRATION_DATE}\"}")
  
  # Check if API key generation succeeded
  SUCCESS=$(echo "$APIKEY_RESPONSE" | sed -n 's/.*"success"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p')
  
  if echo "$SUCCESS" | grep -qi "true"; then
    # Extract API key from nested object: api_key.key
    ALEX_API_KEY=$(echo "$APIKEY_RESPONSE" | sed -n 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    echo -e "${GREEN}✓ API key generated${NC}"
    echo "   API Key: $ALEX_API_KEY"
    echo -e "${YELLOW}   [i] Save this key securely - it won't be shown again${NC}"
    
    # Check for warning
    WARNING=$(echo "$APIKEY_RESPONSE" | sed -n 's/.*"warning"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$WARNING" ]; then
      echo -e "${YELLOW}   ⚠ Warning: $WARNING${NC}"
    fi
  else
    echo -e "${RED}✗ API key generation failed${NC}"
    ERROR=$(echo "$APIKEY_RESPONSE" | sed -n 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$ERROR" ]; then
      echo "Error: $ERROR"
    else
      echo "Response: $APIKEY_RESPONSE"
    fi
    exit 1
  fi
else
  echo -e "${RED}✗ Login failed${NC}"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi

# Detect OS for config paths
detect_os_paths() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    VSCODE_CONFIG_DIR="$HOME/Library/Application Support/Code/User"
    CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
  elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    # WSL - use Windows paths
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    VSCODE_CONFIG_DIR="/mnt/c/Users/${WIN_USER}/AppData/Roaming/Code/User"
    CLAUDE_CONFIG_DIR="/mnt/c/Users/${WIN_USER}/AppData/Roaming/Claude"
  else
    # Linux
    VSCODE_CONFIG_DIR="$HOME/.config/Code/User"
    CLAUDE_CONFIG_DIR="$HOME/.config/Claude"
  fi
}

detect_os_paths

# Step 5: Setup VS Code (GitHub Copilot)
if [ "$SETUP_VSCODE" = true ]; then
  echo ""
  echo -e "${BLUE}[5/7]${NC} Configuring VS Code (GitHub Copilot)..."
  
  mkdir -p "$VSCODE_CONFIG_DIR"
  MCP_JSON="$VSCODE_CONFIG_DIR/mcp.json"
  
  # Read existing config or create new
  if [ -f "$MCP_JSON" ]; then
    BACKUP_FILE="${MCP_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$MCP_JSON" "$BACKUP_FILE"
    echo -e "${YELLOW}   [i] Backup created: $BACKUP_FILE${NC}"
    
    # Check if jq is available for merging
    if command -v jq &> /dev/null; then
      # Merge alex server into existing config
      jq --arg url "$API_URL" --arg key "$ALEX_API_KEY" --arg proxy "${SCRIPT_DIR}/mcp-proxy-client.js" \
        '.servers.alex = {"command": "node", "args": [$proxy], "env": {"ALEX_API_URL": $url, "ALEX_API_KEY": $key, "MCP_CLIENT_NAME": "github_copilot"}}' \
        "$MCP_JSON" > "${MCP_JSON}.tmp" && mv "${MCP_JSON}.tmp" "$MCP_JSON"
      echo -e "${GREEN}   [OK] Merged alex server into existing configuration${NC}"
    else
      echo -e "${YELLOW}   [!] jq not found - will overwrite existing config${NC}"
      cat > "$MCP_JSON" << EOF
{
  "servers": {
    "alex": {
      "command": "node",
      "args": [
        "${SCRIPT_DIR}/mcp-proxy-client.js"
      ],
      "env": {
        "ALEX_API_URL": "${API_URL}",
        "ALEX_API_KEY": "${ALEX_API_KEY}",
        "MCP_CLIENT_NAME": "github_copilot"
      }
    }
  }
}
EOF
    fi
  else
    # Create new config
    cat > "$MCP_JSON" << EOF
{
  "servers": {
    "alex": {
      "command": "node",
      "args": [
        "${SCRIPT_DIR}/mcp-proxy-client.js"
      ],
      "env": {
        "ALEX_API_URL": "${API_URL}",
        "ALEX_API_KEY": "${ALEX_API_KEY}",
        "MCP_CLIENT_NAME": "github_copilot"
      }
    }
  }
}
EOF
  fi
  
  echo -e "${GREEN}[OK] VS Code configured: $MCP_JSON${NC}"
else
  echo ""
  echo -e "${BLUE}[5/7]${NC} Skipping VS Code setup"
fi

# Step 6: Setup Claude Desktop
if [ "$SETUP_CLAUDE" = true ]; then
  echo ""
  echo -e "${BLUE}[6/7]${NC} Configuring Claude Desktop..."
  
  mkdir -p "$CLAUDE_CONFIG_DIR"
  CLAUDE_JSON="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"
  
  # Backup existing config
  if [ -f "$CLAUDE_JSON" ]; then
    cp "$CLAUDE_JSON" "$CLAUDE_JSON.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}   ⓘ Backup created: $CLAUDE_JSON.backup.*${NC}"
  fi
  
  # Detect command for Claude (bash vs wsl.exe)
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    # WSL - use wsl.exe
    CLAUDE_CMD="wsl.exe"
    CLAUDE_ARGS='["-e", "bash", "-c", "cd '"${SCRIPT_DIR}"' && ALEX_API_URL='"${API_URL}"' ALEX_API_KEY='"${ALEX_API_KEY}"' MCP_CLIENT_NAME=claude_desktop node mcp-proxy-client.js"]'
  else
    # Linux/macOS - use bash
    CLAUDE_CMD="bash"
    CLAUDE_ARGS='["-c", "cd '"${SCRIPT_DIR}"' && ALEX_API_URL='"${API_URL}"' ALEX_API_KEY='"${ALEX_API_KEY}"' MCP_CLIENT_NAME=claude_desktop node mcp-proxy-client.js"]'
  fi
  
  # Read existing config or create new
  if [ -f "$CLAUDE_JSON" ]; then
    # Check if jq is available for merging
    if command -v jq &> /dev/null; then
      # Merge alex server into existing config
      jq --arg cmd "$CLAUDE_CMD" --argjson args "$CLAUDE_ARGS" \
        '.mcpServers.alex = {"command": $cmd, "args": $args}' \
        "$CLAUDE_JSON" > "${CLAUDE_JSON}.tmp" && mv "${CLAUDE_JSON}.tmp" "$CLAUDE_JSON"
      echo -e "${GREEN}   [OK] Merged alex server into existing configuration${NC}"
    else
      echo -e "${YELLOW}   [!] jq not found - will overwrite existing config${NC}"
      printf '%s\n' '{
  "mcpServers": {
    "alex": {
      "command": "'"${CLAUDE_CMD}"'",
      "args": '"${CLAUDE_ARGS}"'
    }
  }
}' > "$CLAUDE_JSON"
    fi
  else
    # Create new config
    printf '%s\n' '{
  "mcpServers": {
    "alex": {
      "command": "'"${CLAUDE_CMD}"'",
      "args": '"${CLAUDE_ARGS}"'
    }
  }
}' > "$CLAUDE_JSON"
  fi
  
  echo -e "${GREEN}✓ Claude Desktop configured: $CLAUDE_JSON${NC}"
else
  echo ""
  echo -e "${BLUE}[6/7]${NC} Skipping Claude Desktop setup"
fi

# Step 7: Test connection
echo ""
echo -e "${BLUE}[7/7]${NC} Testing connection to backend..."

TEST_RESPONSE=$(curl -s "${API_URL}/api/health" || echo "ERROR")
if echo "$TEST_RESPONSE" | grep -q "status"; then
  echo -e "${GREEN}✓ Backend connection successful${NC}"
else
  echo -e "${YELLOW}⚠ Could not reach backend at ${API_URL}${NC}"
  echo "   Make sure the backend is running before using the MCP proxy"
fi

# Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║           Installation Complete! 🎉            ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo ""

if [ "$SETUP_VSCODE" = true ]; then
  echo -e "${BLUE}VS Code (GitHub Copilot):${NC}"
  echo "  1. Restart VS Code"
  echo "  2. Open Copilot Chat"
  echo "  3. Use MCP tools: #mcp_alex_alex_al_query or #mcp_alex_alex_al_comparison"
  echo "  4. Example: Use #mcp_alex_alex_al_query to ask: How do I create a table in Business Central?"
  echo ""
fi

if [ "$SETUP_CLAUDE" = true ]; then
  echo -e "${BLUE}Claude Desktop:${NC}"
  echo "  1. Completely restart Claude Desktop (close all windows)"
  echo "  2. Open Settings → All connectors"
  echo "  3. Find 'alex' with 2 tools (alex_al_query, alex_al_comparison)"
  echo "  4. Click 'Blocked' dropdown → Select 'Always allow'"
  echo "  5. Both tools should show ✅ (authorized)"
  echo "  6. Ask: How do I create a table in Business Central?"
  echo ""
fi

echo "Configuration files:"
[ "$SETUP_VSCODE" = true ] && echo "  • VS Code: $MCP_JSON"
[ "$SETUP_CLAUDE" = true ] && echo "  • Claude:  $CLAUDE_JSON"
echo ""
echo "Backend: $API_URL"
echo "Proxy:   $SCRIPT_DIR/mcp-proxy-client.js"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"

#
# Alex MCP Proxy Installer for Windows PowerShell
# Configures GitHub Copilot (VS Code) and/or Claude Desktop
#
# Usage:
#   Interactive mode:  .\install-mcp.ps1
#   Automated mode:    .\install-mcp.ps1 -Url URL -Username USER -Password PASS [-VSCode] [-Claude]
#

param(
    [string]$Url = "",
    [string]$Username = "",
    [string]$Password = "",
    [string]$ExpirationDate = "",
    [switch]$VSCode = $false,
    [switch]$Claude = $false,
    [switch]$Help = $false
)

# Show help
if ($Help) {
    Write-Host "Alex MCP Proxy Installer"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  Interactive mode:  .\install-mcp.ps1"
    Write-Host "  Automated mode:    .\install-mcp.ps1 -Url URL -Username USER -Password PASS [-VSCode] [-Claude]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Url URL           Backend API URL (default: https://alex.api.pmats.ai)"
    Write-Host "  -Username USER     Alex username"
    Write-Host "  -Password PASS     Alex password"
    Write-Host "  -ExpirationDate    API key expiration date (ISO 8601 UTC, default: +3 months)"
    Write-Host "  -VSCode            Setup VS Code (GitHub Copilot)"
    Write-Host "  -Claude            Setup Claude Desktop"
    Write-Host "  -Help              Show this help"
    exit 0
}

$DefaultApiUrl = "https://alex.api.pmats.ai"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Interactive = [string]::IsNullOrEmpty($Url) -or [string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password)

# Banner
try {
    $Version = Get-Content "$ScriptDir\VERSION.txt" -ErrorAction Stop
} catch {
    $Version = "unknown"
}

Write-Host ""
Write-Host "           _           " -ForegroundColor Cyan
Write-Host "     /\   | |          " -ForegroundColor Cyan
Write-Host "    /  \  | | _____  __" -ForegroundColor Cyan
Write-Host "   / /\ \ | |/ _ \ \/ /" -ForegroundColor Cyan
Write-Host "  / ____ \| |  __/>  < " -ForegroundColor Cyan
Write-Host " /_/    \_\_|\___/_/\_\" -ForegroundColor Cyan
Write-Host "                       " -ForegroundColor Cyan
Write-Host "                       " -ForegroundColor Cyan
Write-Host "" 

# Dynamic box with centered text
$Text1 = "MCP Proxy Installer v$Version"
$Text2 = "Windows PowerShell"
$BoxWidth = 48

# Center text in box
function Center-Text($text, $width) {
    $textLen = $text.Length
    $padding = [Math]::Floor(($width - $textLen) / 2)
    $text.PadLeft($textLen + $padding).PadRight($width)
}

$Line1 = Center-Text $Text1 $BoxWidth
$Line2 = Center-Text $Text2 $BoxWidth
$Border = "═" * $BoxWidth

Write-Host "╔$Border╗" -ForegroundColor Cyan
Write-Host "║$Line1║" -ForegroundColor Cyan
Write-Host "║$Line2║" -ForegroundColor Cyan
Write-Host "╚$Border╝" -ForegroundColor Cyan
Write-Host ""

# Preliminary checks
Write-Host "[0/7] Preliminary checks..." -ForegroundColor Cyan

# Check required files
$RequiredFiles = @(
    "VERSION.txt",
    "package.json",
    "package-lock.json",
    "mcp-proxy-client.js"
)

$MissingFiles = @()
foreach ($file in $RequiredFiles) {
    $filePath = Join-Path $ScriptDir $file
    if (-not (Test-Path $filePath)) {
        $MissingFiles += $file
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Host "[X] Missing required files:" -ForegroundColor Red
    foreach ($file in $MissingFiles) {
        Write-Host "  - $file" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Please make sure you have cloned the complete repository:" -ForegroundColor Yellow
    Write-Host "  git clone https://github.com/pmoisontech/Alex-MCP-Proxy.git" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] All required files present" -ForegroundColor Green

# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "[i] Not running as administrator" -ForegroundColor Yellow
    Write-Host "  (Administrator rights may be needed if Node.js installation is required)" -ForegroundColor Yellow
}

Write-Host ""

# Step 1: Check Node.js
Write-Host "[1/7] Checking Node.js installation..." -ForegroundColor Cyan

# Function to install Node.js
function Install-NodeJS {
    $installCmd = $null
    $pkgManager = $null
    
    # Check for winget (Windows 10/11 built-in)
    try {
        winget --version | Out-Null
        $pkgManager = "winget"
        $installCmd = "winget install OpenJS.NodeJS --silent"
    } catch {
        # Check for Chocolatey
        try {
            choco --version | Out-Null
            $pkgManager = "chocolatey"
            $installCmd = "choco install nodejs -y"
        } catch {
            # No package manager available
        }
    }
    
    if ($installCmd) {
        Write-Host ""
        Write-Host "Node.js can be installed automatically using $pkgManager" -ForegroundColor Yellow
        Write-Host "Command: $installCmd"
        Write-Host ""
        
        if ($Interactive) {
            $installConfirm = Read-Host "Install Node.js now? [y/N]"
            if ($installConfirm -match '^[Yy]$') {
                # Check if we have admin rights
                $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                
                if (-not $IsAdmin) {
                    Write-Host "[X] Administrator rights required to install Node.js" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Please:" -ForegroundColor Yellow
                    Write-Host "  1. Close this PowerShell window" -ForegroundColor Yellow
                    Write-Host "  2. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
                    Write-Host "  3. Run this script again" -ForegroundColor Yellow
                    return $false
                }
                
                Write-Host "Installing Node.js..." -ForegroundColor Cyan
                
                try {
                    Invoke-Expression $installCmd
                    
                    # Refresh PATH
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    
                    # Verify installation
                    try {
                        $NewVersion = (node --version) -replace 'v', ''
                        Write-Host "[OK] Node.js v$NewVersion installed successfully" -ForegroundColor Green
                        return $true
                    } catch {
                        Write-Host "[X] Installation failed or PATH not updated" -ForegroundColor Red
                        Write-Host "   Please restart PowerShell and run this script again" -ForegroundColor Yellow
                        return $false
                    }
                } catch {
                    Write-Host "[X] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
                    return $false
                }
            }
        }
    }
    
    Write-Host ""
    Write-Host "Please install Node.js 18 or higher manually:"
    Write-Host "  Download: https://nodejs.org/"
    return $false
}

# Check if Node.js is installed
try {
    $NodeVersion = (node --version) -replace 'v', ''
    $NodeMajor = [int]($NodeVersion -split '\.')[0]
    
    if ($NodeMajor -lt 18) {
        Write-Host "[X] Node.js version $NodeVersion is too old (need ≥18)" -ForegroundColor Red
        Write-Host "Current version: v$NodeVersion" -ForegroundColor Yellow
        Write-Host ""
        
        if (Install-NodeJS) {
            # Check new version
            $NodeVersion = (node --version) -replace 'v', ''
            $NodeMajor = [int]($NodeVersion -split '\.')[0]
            
            if ($NodeMajor -lt 18) {
                Write-Host "[X] Installed version is still too old" -ForegroundColor Red
                exit 1
            }
        } else {
            exit 1
        }
    }
    
    Write-Host "[OK] Node.js v$NodeVersion detected" -ForegroundColor Green
} catch {
    Write-Host "[X] Node.js is not installed" -ForegroundColor Red
    
    if (Install-NodeJS) {
        # Installation successful, continue
    } else {
        exit 1
    }
}

# Step 2: Install npm dependencies
Write-Host ""
Write-Host "[2/7] Installing npm dependencies..." -ForegroundColor Cyan
Set-Location $ScriptDir

$npmOutput = npm install 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Dependencies installed" -ForegroundColor Green
} else {
    Write-Host "[X] npm install failed" -ForegroundColor Red
    Write-Host $npmOutput
    exit 1
}

# Step 3: Interactive configuration
if ($Interactive) {
    Write-Host ""
    Write-Host "[3/7] Configuration" -ForegroundColor Cyan
    Write-Host ""
    
    # API URL
    $InputUrl = Read-Host "Backend API URL [$DefaultApiUrl]"
    $Url = if ([string]::IsNullOrEmpty($InputUrl)) { $DefaultApiUrl } else { $InputUrl }
    
    # Credentials
    $Username = Read-Host "Username"
    $SecurePassword = Read-Host "Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    # Setup choices
    Write-Host ""
    $SetupVSCodeInput = Read-Host "Setup VS Code (GitHub Copilot)? [y/N]"
    $VSCode = $SetupVSCodeInput -match '^[Yy]$'
    
    $SetupClaudeInput = Read-Host "Setup Claude Desktop? [y/N]"
    $Claude = $SetupClaudeInput -match '^[Yy]$'
    
    if (-not $VSCode -and -not $Claude) {
        Write-Host "[!] No setup selected. You must choose at least one." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "[3/7] Using provided configuration" -ForegroundColor Cyan
    
    if ([string]::IsNullOrEmpty($Url)) { $Url = $DefaultApiUrl }
    
    if (-not $VSCode -and -not $Claude) {
        Write-Host "[!] No setup selected (-VSCode or -Claude required)" -ForegroundColor Yellow
        exit 1
    }
}

# Step 4: Login to backend and get JWT token
Write-Host ""
Write-Host "[4/7] Authenticating with Alex backend..." -ForegroundColor Cyan

$LoginBody = @{
    username = $Username
    password = $Password
} | ConvertTo-Json

try {
    $LoginResponse = Invoke-RestMethod -Uri "$Url/api/user/login" -Method Post -Body $LoginBody -ContentType "application/json"
    $JwtToken = $LoginResponse.token
    
    Write-Host "[OK] Login successful" -ForegroundColor Green
    
    # Calculate expiration date (3 months from now or use provided date)
    if ([string]::IsNullOrEmpty($ExpirationDate)) {
        $ExpirationDate = (Get-Date).AddMonths(3).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Write-Host "     Generating MCP API key (expires: $ExpirationDate)..." -ForegroundColor Cyan
    } else {
        Write-Host "     Generating MCP API key (expires: $ExpirationDate)..." -ForegroundColor Cyan
    }
    
    $ApiKeyBody = @{
        name = "MCP Server"
        expires_at = $ExpirationDate
    } | ConvertTo-Json
    
    $Headers = @{
        "Authorization" = "Bearer $JwtToken"
    }
    
    $ApiKeyResponse = Invoke-RestMethod -Uri "$Url/api/user/api-keys" -Method Post -Body $ApiKeyBody -ContentType "application/json" -Headers $Headers
    
    if ($ApiKeyResponse.success) {
        $ApiKey = $ApiKeyResponse.api_key.key
        
        Write-Host "[OK] API key generated" -ForegroundColor Green
        Write-Host "   API Key: $ApiKey" -ForegroundColor Cyan
        Write-Host "   [i] Save this key securely - it won't be shown again" -ForegroundColor Yellow
        
        if ($ApiKeyResponse.warning) {
            Write-Host "   [!] Warning: $($ApiKeyResponse.warning)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[X] API key generation failed" -ForegroundColor Red
        if ($ApiKeyResponse.error) {
            Write-Host "Error: $($ApiKeyResponse.error)" -ForegroundColor Red
        }
        exit 1
    }
} catch {
    Write-Host "[X] Authentication or API key generation failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

# Config paths for Windows
$VSCodeConfigDir = "$env:APPDATA\Code\User"
$ClaudeConfigDir = "$env:APPDATA\Claude"

# Step 5: Setup VS Code (GitHub Copilot)
if ($VSCode) {
    Write-Host ""
    Write-Host "[5/7] Configuring VS Code (GitHub Copilot)..." -ForegroundColor Cyan
    
    New-Item -ItemType Directory -Force -Path $VSCodeConfigDir | Out-Null
    $McpJson = "$VSCodeConfigDir\mcp.json"
    
    # Escape backslashes for JSON
    $ProxyPath = ($ScriptDir -replace '\\', '\\') + "\\mcp-proxy-client.js"
    
    # Read existing config or create new
    if (Test-Path $McpJson) {
        $BackupFile = "$McpJson.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $McpJson $BackupFile
        Write-Host "   [i] Backup created: $BackupFile" -ForegroundColor Yellow
        
        $ExistingConfig = Get-Content $McpJson -Raw | ConvertFrom-Json
        if (-not $ExistingConfig.servers) {
            $ExistingConfig | Add-Member -MemberType NoteProperty -Name "servers" -Value @{} -Force
        }
    } else {
        $ExistingConfig = @{ servers = @{} }
    }
    
    # Add or update alex server
    $AlexServer = @{
        command = "node"
        args = @($ProxyPath)
        env = @{
            ALEX_API_URL = $Url
            ALEX_API_KEY = $ApiKey
            MCP_CLIENT_NAME = "github_copilot"
        }
    }
    
    if ($ExistingConfig.servers -is [System.Collections.Hashtable]) {
        $ExistingConfig.servers["alex"] = $AlexServer
    } else {
        $ExistingConfig.servers | Add-Member -MemberType NoteProperty -Name "alex" -Value $AlexServer -Force
    }
    
    $ExistingConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $McpJson -Encoding UTF8
    
    Write-Host "[OK] VS Code configured: $McpJson" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[5/7] Skipping VS Code setup" -ForegroundColor Cyan
}

# Step 6: Setup Claude Desktop
if ($Claude) {
    Write-Host ""
    Write-Host "[6/7] Configuring Claude Desktop..." -ForegroundColor Cyan
    
    New-Item -ItemType Directory -Force -Path $ClaudeConfigDir | Out-Null
    $ClaudeJson = "$ClaudeConfigDir\claude_desktop_config.json"
    
    # Backup existing config
    if (Test-Path $ClaudeJson) {
        $BackupFile = "$ClaudeJson.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $ClaudeJson $BackupFile
        Write-Host "   [i] Backup created: $BackupFile" -ForegroundColor Yellow
    }
    
    # Create or update claude_desktop_config.json
    $ClaudeConfig = @{
        mcpServers = @{
            alex = @{
                command = "node"
                args = @(
                    "$ScriptDir\mcp-proxy-client.js"
                )
                env = @{
                    ALEX_API_URL = $Url
                    ALEX_API_KEY = $ApiKey
                    MCP_CLIENT_NAME = "claude_desktop"
                }
            }
        }
    }
    
    # Convert to JSON and save with UTF8 without BOM
    $JsonContent = $ClaudeConfig | ConvertTo-Json -Depth 10
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::WriteAllLines($ClaudeJson, $JsonContent, $Utf8NoBomEncoding)
    
    Write-Host "[OK] Claude Desktop configured: $ClaudeJson" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[6/7] Skipping Claude Desktop setup" -ForegroundColor Cyan
}

# Step 7: Test connection
Write-Host ""
Write-Host "[7/7] Testing connection to backend..." -ForegroundColor Cyan

try {
    $TestResponse = Invoke-RestMethod -Uri "$Url/api/health" -Method Get -ErrorAction Stop
    Write-Host "[OK] Backend connection successful" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not reach backend at $Url" -ForegroundColor Yellow
    Write-Host "   Make sure the backend is running before using the MCP proxy"
}

# Final instructions
Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                ║" -ForegroundColor Green
Write-Host "║         Installation Complete! [SUCCESS]       ║" -ForegroundColor Green
Write-Host "║                                                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host ""

if ($VSCode) {
    Write-Host "VS Code (GitHub Copilot):" -ForegroundColor Cyan
    Write-Host "  1. Restart VS Code"
    Write-Host "  2. Open Copilot Chat"
    Write-Host "  3. Use MCP tools: #mcp_alex_alex_al_query or #mcp_alex_alex_al_comparison"
    Write-Host "  4. Example: Use #mcp_alex_alex_al_query to ask: How do I create a table in Business Central?"
    Write-Host ""
}

if ($Claude) {
    Write-Host "Claude Desktop:" -ForegroundColor Cyan
    Write-Host "  1. Completely restart Claude Desktop (close all windows)"
    Write-Host "  2. Open Settings → All connectors"
    Write-Host "  3. Find 'alex' with 2 tools (alex_al_query, alex_al_comparison)"
    Write-Host "  4. Click 'Blocked' dropdown → Select 'Always allow'"
    Write-Host "  5. Both tools should show ✅ (authorized)"
    Write-Host "  6. Ask: How do I create a table in Business Central?"
    Write-Host ""
}

Write-Host "Configuration files:"
if ($VSCode) { Write-Host "  • VS Code: $VSCodeConfigDir\mcp.json" }
if ($Claude) { Write-Host "  • Claude:  $ClaudeConfigDir\claude_desktop_config.json" }
Write-Host ""
Write-Host "Backend: $Url"
Write-Host "Proxy:   $ScriptDir\mcp-proxy-client.js"
Write-Host ""
Write-Host "Happy coding!" -ForegroundColor Green

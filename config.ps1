# ==============================================================================
# RobinTrader GOLD - Centralized Fleet Configuration
# ==============================================================================
# Portable, path-agnostic configuration for all 6 bots.
# Supports both automatic zero-config registration AND existing AI4Trade accounts
# (just copy `.credentials.example` to `.credentials` and fill in your details).
# ==============================================================================

# --- API Endpoint ---
$global:BASE_URL = "https://ai4trade.ai/api"

# --- Trading & Risk Parameters (Tunable) ---
$global:TARGET_MIN     = 0.02    # Trailing stop activation threshold (+2.0%)
$global:TARGET_MAX     = 0.05    # Hard take-profit threshold (+5.0%)
$global:TRAIL_BUFFER   = 0.005   # Trailing stop drop buffer (0.5%)
$global:RESERVE        = 1000    # Minimum cash reserve to always keep available ($)
$global:BUY_AMOUNT     = 5000    # Capital allocated per automated entry ($)
$global:MIN_PNL_TRADER = -0.05   # Guardian blacklist threshold (-5.0% trader PnL)
$global:ENABLE_SOUNDS  = $true   # Set to $false to disable console audio alerts

# --- Local Session Files (Excluded from Git via .gitignore) ---
$global:TOKEN_FILE = Join-Path $PSScriptRoot ".token"
$global:CRED_FILE  = Join-Path $PSScriptRoot ".credentials"

# --- Dynamic Runtime Paths (Logs & Inter-Bot Data) ---
$global:PATH_LOG_MONITOR   = Join-Path $PSScriptRoot "log_monitor.txt"
$global:PATH_LOG_JOURNAL   = Join-Path $PSScriptRoot "log_journal.txt"
$global:PATH_LOG_VALIDATOR = Join-Path $PSScriptRoot "log_validator.txt"
$global:PATH_LOG_HEARTBEAT = Join-Path $PSScriptRoot "log_heartbeat.txt"

$global:PATH_DATA_STRATEGY = Join-Path $PSScriptRoot "data_strategies.json"
$global:PATH_DATA_INTEL    = Join-Path $PSScriptRoot "data_intelligence.json"
$global:PATH_DATA_MARKET   = Join-Path $PSScriptRoot "data_market.json"
$global:PATH_DATA_BANS     = Join-Path $PSScriptRoot "data_blacklist.json"
$global:PATH_RAW_REPORTS   = Join-Path $PSScriptRoot "data_raw_reports.txt"

# --- Audio Feedback Helper ---
function Invoke-Alert {
    param(
        [int]$freq = 800,
        [int]$dur  = 200
    )
    if (-not $global:ENABLE_SOUNDS) { return }
    try { [Console]::Beep($freq, $dur) } catch {}
}

# --- Realistic Random Identity Generator (6 letters + 2 digits) ---
function Get-RealisticName {
    $letters = "abcdefghijklmnopqrstuvwxyz"
    $nums    = "0123456789"
    $lStr    = -join ($letters.ToCharArray() | Get-Random -Count 6)
    $nStr    = -join ($nums.ToCharArray() | Get-Random -Count 2)
    return "Trader_$($lStr)$($nStr)"
}

# --- Session Refresh using .credentials ---
function Update-Session {
    if (Test-Path $global:CRED_FILE) {
        try {
            $creds = Get-Content -Path $global:CRED_FILE -Raw -Encoding utf8 | ConvertFrom-Json
            $body  = @{
                name     = $creds.name
                email    = $creds.email
                password = $creds.password
            } | ConvertTo-Json
            $res = Invoke-RestMethod -Uri "$($global:BASE_URL)/claw/agents/login" -Method Post -Body $body -ContentType "application/json"
            if ($res.token) {
                $res.token | Out-File -FilePath $global:TOKEN_FILE -NoNewline -Encoding utf8
                $global:TOKEN = $res.token.Trim()
                Write-Host "[AUTH] Session token refreshed." -ForegroundColor Green
                return $global:TOKEN
            }
        } catch {
            Write-Host "[AUTH] Login refresh failed: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    return $null
}

# --- Automatic Session Initialization ---
function Invoke-AutoInit {
    # 1. Restore existing session token if available
    if (Test-Path $global:TOKEN_FILE) {
        try {
            $existingToken = (Get-Content -Path $global:TOKEN_FILE -Raw -Encoding utf8).Trim()
            if ($existingToken) {
                Write-Host "[AUTH] Session restored from .token." -ForegroundColor Green
                return $existingToken
            }
        } catch {}
    }

    # 2. If user provided custom .credentials, log in with them
    if (Test-Path $global:CRED_FILE) {
        Write-Host "[AUTH] Found .credentials file. Logging in..." -ForegroundColor Cyan
        $loginToken = Update-Session
        if ($loginToken) { return $loginToken }
    }

    # 3. Otherwise auto-register a fresh AI4Trade agent identity
    Write-Host "[INIT] No local session found. Registering new AI4Trade agent identity..." -ForegroundColor Cyan
    $name  = Get-RealisticName
    $email = "$name@ai4trade.local"
    $pass  = "Gold_$(Get-Random -Minimum 100000 -Maximum 999999)!"

    $regBody = @{
        name     = $name
        email    = $email
        password = $pass
    } | ConvertTo-Json

    try {
        $res = Invoke-RestMethod -Uri "$($global:BASE_URL)/claw/agents/selfRegister" -Method Post -Body $regBody -ContentType "application/json"
        if ($res.token) {
            $res.token | Out-File -FilePath $global:TOKEN_FILE -NoNewline -Encoding utf8
            $regBody   | Out-File -FilePath $global:CRED_FILE  -Encoding utf8
            Write-Host "[SUCCESS] New agent registered: $name (saved to .credentials)" -ForegroundColor Green
            return $res.token.Trim()
        }
    } catch {
        Write-Host "[ERROR] Auto-registration failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    return $null
}

# --- Initialize Global Token ---
if (-not $global:TOKEN) {
    $global:TOKEN = Invoke-AutoInit
}

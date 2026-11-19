# ==============================================================================
# RobinTrader GOLD - Live Account & Portfolio Status Checker
# ==============================================================================

. "$PSScriptRoot\config.ps1"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "     ROBIN TRADER GOLD - ACCOUNT STATUS          " -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Cyan

# 1. Local Agent Identity (never prints password)
if (Test-Path $global:CRED_FILE) {
    try {
        $creds = Get-Content -Path $global:CRED_FILE -Raw -Encoding utf8 | ConvertFrom-Json
        Write-Host "Agent Name  : $($creds.name)" -ForegroundColor Yellow
        Write-Host "Agent Email : $($creds.email)" -ForegroundColor Yellow
    } catch {}
}

# 2. Running Bots Count
$runningBots = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "bot_[1-6]_[a-z]+\.ps1" })
Write-Host "Active Bots : $($runningBots.Count) / 6" -ForegroundColor Cyan

# 3. Portfolio & Cash Balance
function Get-Portfolio {
    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    return Invoke-RestMethod -Uri "$($global:BASE_URL)/positions" -Method Get -Headers $headers
}

try {
    try {
        $res = Get-Portfolio
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            $global:TOKEN = Update-Session
            $res = Get-Portfolio
        } else {
            throw
        }
    }

    Write-Host "Cash Balance: `$$($res.cash)" -ForegroundColor Green
    Write-Host "`n--- OPEN POSITIONS ---" -ForegroundColor Cyan
    if ($res.positions -and @($res.positions).Count -gt 0) {
        @($res.positions) | Select-Object symbol, market, quantity, entry_price, current_price, pnl | Format-Table -AutoSize
    } else {
        Write-Host "No open positions at the moment." -ForegroundColor Gray
    }
} catch {
    Write-Host "[ERROR] Could not fetch account status: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Ensure you have internet access and run start_fleet.ps1 first." -ForegroundColor DarkYellow
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

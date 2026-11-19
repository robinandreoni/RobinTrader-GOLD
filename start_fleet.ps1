# ==============================================================================
# RobinTrader GOLD - Fleet Startup Orchestrator
# ==============================================================================
# Usage:
#   .\start_fleet.ps1           (starts all 6 bots minimized with 7s stagger)
#   .\start_fleet.ps1 -Visible  (starts all 6 bots in visible console windows)
# ==============================================================================

param(
    [switch]$Visible
)

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   ROBIN TRADER GOLD - MULTI-AGENT FLEET LAUNCH  " -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Cyan

# 1. Stop any previously running fleet instances cleanly
& "$PSScriptRoot\stop_fleet.ps1" -Quiet
Start-Sleep -Seconds 2

# 2. Initialize / verify session token once before spawning child bots
. "$PSScriptRoot\config.ps1"

if (-not $global:TOKEN) {
    Write-Host "[ERROR] Failed to initialize AI4Trade session token. Check your internet connection or .credentials file." -ForegroundColor Red
    exit 1
}

# 3. Sequential Startup Sequence (7s stagger for API stability)
$bots = @(
    @{ name = "Bot 4 - Guardian";     file = "bot_4_guardian.ps1" },
    @{ name = "Bot 3 - Intelligence"; file = "bot_3_intelligence.ps1" },
    @{ name = "Bot 2 - Analyst";      file = "bot_2_analyst.ps1" },
    @{ name = "Bot 5 - Heartbeat";    file = "bot_5_heartbeat.ps1" },
    @{ name = "Bot 6 - Strategist";   file = "bot_6_strategist.ps1" },
    @{ name = "Bot 1 - Executor";     file = "bot_1_executor.ps1" }
)

$winStyle = if ($Visible) { "Normal" } else { "Minimized" }

foreach ($bot in $bots) {
    $scriptPath = Join-Path $PSScriptRoot $bot.file
    Write-Host ">> Starting $($bot.name)..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle $winStyle
    Start-Sleep -Seconds 7
}

Write-Host ""
Write-Host "FLEET ONLINE! All 6 agents are running ($winStyle)." -ForegroundColor Green
Write-Host "Monitor Executor logs : Get-Content `"$PSScriptRoot\log_monitor.txt`" -Wait" -ForegroundColor Gray
Write-Host "Check account status  : .\check_status.ps1" -ForegroundColor Gray
Write-Host "Stop entire fleet     : .\stop_fleet.ps1" -ForegroundColor Gray

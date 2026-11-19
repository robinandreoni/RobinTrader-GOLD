# ==============================================================================
# RobinTrader GOLD - Fleet Shutdown Utility
# ==============================================================================
# Cleanly terminates all running RobinTrader GOLD bot processes.
# ==============================================================================

param(
    [switch]$Quiet
)

if (-not $Quiet) {
    Write-Host "--- STOPPING ROBIN TRADER GOLD FLEET ---" -ForegroundColor Yellow
}

$procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "bot_[1-6]_[a-z]+\.ps1" }

$stopped = 0
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        $stopped++
        if (-not $Quiet) {
            Write-Host "  [STOPPED] PID $($p.ProcessId)" -ForegroundColor DarkGray
        }
    } catch {}
}

if (-not $Quiet) {
    if ($stopped -gt 0) {
        Write-Host "Fleet stopped ($stopped bot process(es) terminated)." -ForegroundColor Green
    } else {
        Write-Host "No active fleet bots found." -ForegroundColor Gray
    }
}

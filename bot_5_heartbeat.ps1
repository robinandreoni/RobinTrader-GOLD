# ==============================================================================
# BOT 5: HEARTBEAT MONITOR
# ==============================================================================
# Maintains 24/7 connectivity with AI4Trade, refreshes expired sessions,
# processes incoming platform notifications/tasks, and rotates logs cleanly.
# ==============================================================================

. "$PSScriptRoot\config.ps1"

$script:pulseCount = 0

function Write-HeartbeatLog {
    param(
        [string]$msg,
        [string]$color = "DarkCyan"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [HEARTBEAT] $msg"
    Write-Host "[HEARTBEAT] $msg" -ForegroundColor $color

    $logPath = if ($global:PATH_LOG_HEARTBEAT) { $global:PATH_LOG_HEARTBEAT } else { Join-Path $PSScriptRoot "log_heartbeat.txt" }
    try {
        if ($script:pulseCount -ge 50) {
            $line | Out-File -FilePath $logPath -Encoding utf8
            $script:pulseCount = 0
        } else {
            $line | Out-File -FilePath $logPath -Append -Encoding utf8
        }
    } catch {}
}

function Invoke-Pulse {
    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    try {
        $res = Invoke-RestMethod -Uri "$($global:BASE_URL)/claw/agents/heartbeat" -Method Post -Headers $headers
        $script:pulseCount++
        Invoke-Alert -freq 200 -dur 80

        if ($null -ne $res.messages -and @($res.messages).Count -gt 0) {
            Invoke-Alert -freq 1000 -dur 100
            Invoke-Alert -freq 1200 -dur 100
            foreach ($m in @($res.messages)) {
                Write-HeartbeatLog -msg "ALERT [$($m.type)]: $($m.content)" -color "Green"
            }
        }

        if ($null -ne $res.tasks -and @($res.tasks).Count -gt 0) {
            foreach ($t in @($res.tasks)) {
                Write-HeartbeatLog -msg "TASK: $($t.type)" -color "Yellow"
            }
        }

        $interval = if ($res.recommended_poll_interval_seconds) { [int]$res.recommended_poll_interval_seconds } else { 30 }
        Write-HeartbeatLog -msg "Pulse OK. Next poll in ${interval}s" -color "Gray"
        return $interval
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            Write-HeartbeatLog -msg "Session expired (401). Refreshing token..." -color "Yellow"
            $global:TOKEN = Update-Session
            return 5
        }
        Write-HeartbeatLog -msg "Connection warning: $($_.Exception.Message)" -color "Red"
        return 60
    }
}

Write-Host "Bot 5 (Heartbeat) ONLINE" -ForegroundColor DarkCyan
while ($true) {
    $waitSeconds = Invoke-Pulse
    if ($null -eq $waitSeconds -or $waitSeconds -lt 5) { $waitSeconds = 30 }
    Start-Sleep -Seconds $waitSeconds
}

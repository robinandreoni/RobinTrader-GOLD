# ==============================================================================
# BOT 4: THE GUARDIAN
# ==============================================================================
# Security & validation core:
#   1. Maintains dynamic blacklist of underperforming agents.
#   2. Cross-validates Bot 3 (Intelligence) signals against live platform feed.
#   3. Cross-validates Bot 6 (Strategist) signals against live platform feed.
# ==============================================================================

. "$PSScriptRoot\config.ps1"

function Write-GuardianLog {
    param([string]$msg, [string]$color = "Gray")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] [GUARDIAN] $msg"
    Write-Host $line -ForegroundColor $color
    try { $line | Out-File -FilePath $global:PATH_LOG_VALIDATOR -Append -Encoding utf8 } catch {}
}

function Test-InsightsFile {
    param(
        [string]$filePath,
        [string]$label,
        [hashtable]$headers
    )
    if (-not (Test-Path $filePath)) { return }
    try {
        $items = @(Get-Content -Path $filePath -Raw -Encoding utf8 | ConvertFrom-Json)
        if ($items.Count -eq 0) { return }

        $valid = @()
        foreach ($item in $items) {
            if (-not $item.symbol) { continue }
            try {
                $feed = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/feed?symbol=$($item.symbol)&limit=1" -Method Get -Headers $headers
                if ($feed -and @($feed.signals).Count -gt 0) {
                    $valid += $item
                } else {
                    Write-GuardianLog -msg "Discarded unverified $label signal: $($item.symbol) (no live feed)" -color "Yellow"
                }
            } catch {
                # Keep item if transient network error occurs
                $valid += $item
            }
        }

        if ($valid.Count -lt $items.Count) {
            $valid | ConvertTo-Json -Depth 4 | Out-File -FilePath $filePath -Encoding utf8
        }
    } catch {}
}

function Invoke-SecurityPatrol {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Running security patrol & validation..." -ForegroundColor Red
    $headers = @{ Authorization = "Bearer $global:TOKEN" }

    try {
        # 1. Dynamic Blacklist
        $res  = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/grouped?limit=100" -Method Get -Headers $headers
        $bans = @(@($res.agents) | Where-Object { $_.position_pnl -lt $global:MIN_PNL_TRADER } | ForEach-Object {
            @{
                agent_id  = $_.agent_id
                name      = $_.agent_name
                banned_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                reason    = "PnL below threshold ($($global:MIN_PNL_TRADER))"
            }
        })

        $prevCount = 0
        if (Test-Path $global:PATH_DATA_BANS) {
            try { $prevCount = @(Get-Content -Path $global:PATH_DATA_BANS -Raw -Encoding utf8 | ConvertFrom-Json).Count } catch {}
        }

        $bans | ConvertTo-Json -Depth 4 | Out-File -FilePath $global:PATH_DATA_BANS -Encoding utf8
        Write-Host "  > Blacklist updated ($($bans.Count) flagged agents)." -ForegroundColor Gray
        if ($bans.Count -gt $prevCount) { Invoke-Alert -freq 400 -dur 250 }

        # 2. Validate Intelligence (Bot 3)
        Test-InsightsFile -filePath $global:PATH_DATA_INTEL -label "Intelligence" -headers $headers

        # 3. Validate Strategist (Bot 6)
        Test-InsightsFile -filePath $global:PATH_DATA_STRATEGY -label "Strategist" -headers $headers
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            $global:TOKEN = Update-Session
        }
        Write-GuardianLog -msg "Patrol error: $($_.Exception.Message)" -color "Red"
    }
}

Write-Host "Bot 4 (Guardian) ONLINE - Active protection enabled." -ForegroundColor Red
while ($true) {
    Invoke-SecurityPatrol
    Start-Sleep -Seconds (Get-Random -Minimum 30 -Maximum 60)
}

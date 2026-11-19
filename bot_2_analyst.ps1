# ==============================================================================
# BOT 2: THE ANALYST
# ==============================================================================
# Scans top-performing agents on AI4Trade, filters out Guardian-blacklisted
# traders, and cross-references positions with Bot 3 Intelligence trends.
# ==============================================================================

. "$PSScriptRoot\config.ps1"

function Invoke-MarketScan {
    Write-Host "`n[ANALYSIS] Scanning market leaders... ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
    $headers = @{ Authorization = "Bearer $global:TOKEN" }

    $trends = @()
    if (Test-Path $global:PATH_DATA_INTEL) {
        try {
            $trends = @(Get-Content -Path $global:PATH_DATA_INTEL -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object { $_.symbol })
        } catch {}
    }

    $bans = @()
    if (Test-Path $global:PATH_DATA_BANS) {
        try {
            $bans = @(Get-Content -Path $global:PATH_DATA_BANS -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object { $_.agent_id })
        } catch {}
    }

    try {
        $res = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/grouped?limit=30" -Method Get -Headers $headers
        $insights = @()

        foreach ($agent in @($res.agents)) {
            if ($bans -contains $agent.agent_id) {
                Write-Host "  > Skipped $($agent.agent_name) (Blacklisted by Guardian)" -ForegroundColor DarkGray
                continue
            }

            $agentSymbols = if ($null -ne $agent.positions) { @($agent.positions | ForEach-Object { $_.symbol }) } else { @() }
            $isTrending   = @($agentSymbols | Where-Object { $trends -contains $_ }).Count -gt 0

            if ($agent.position_pnl -gt 0 -or $isTrending) {
                $statusStr = if ($isTrending) { "Trend Follower" } else { "Top Performer" }
                Write-Host "  > Leader: $($agent.agent_name) [$statusStr | PnL: $($agent.position_pnl)]" -ForegroundColor White

                $topAssets = @()
                if ($null -ne $agent.positions) {
                    $topAssets = @($agent.positions | Select-Object -First 3 | ForEach-Object {
                        @{ symbol = $_.symbol; market = $_.market; pnl = $_.pnl }
                    })
                }

                $insights += @{
                    agent_id   = $agent.agent_id
                    name       = $agent.agent_name
                    pnl        = $agent.position_pnl
                    status     = $statusStr
                    top_assets = $topAssets
                }
            }
        }

        $insights | ConvertTo-Json -Depth 5 | Out-File -FilePath $global:PATH_DATA_MARKET -Encoding utf8
        Invoke-Alert -freq 400 -dur 200
        Write-Host "[SUCCESS] Market Insights updated ($($insights.Count) leaders saved)." -ForegroundColor Green
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            $global:TOKEN = Update-Session
        }
        Write-Host "[ERROR] Analyst scan failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Bot 2 (Analyst) ONLINE" -ForegroundColor Yellow
while ($true) {
    Invoke-MarketScan
    Start-Sleep -Seconds 60
}

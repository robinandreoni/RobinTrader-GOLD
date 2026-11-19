# ==============================================================================
# BOT 6: THE STRATEGIST
# ==============================================================================
# Regex-powered consensus analyzer that parses plain-text strategy reports
# (`data_raw_reports.txt`) to extract high-conviction ticker recommendations.
# ==============================================================================

. "$PSScriptRoot\config.ps1"

$STOPWORDS = @(
    "THE", "AND", "FOR", "BUY", "SELL", "HOLD", "NONE", "DATE", "TIME",
    "EURO", "USDT", "LAST", "DAY", "SCAN", "POS", "WATCH", "SIDE",
    "TITLE", "MODE", "RISK", "LONG", "SHORT", "OPEN", "CLOSE", "HIGH",
    "LOW", "NOTE", "PLAN", "TASK", "FROM", "WITH", "THIS", "THAT"
)

function Invoke-StrategyAnalysis {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Analyzing raw reports for market consensus..." -ForegroundColor Magenta

    $rawPath   = if ($global:PATH_RAW_REPORTS)   { $global:PATH_RAW_REPORTS }   else { Join-Path $PSScriptRoot "data_raw_reports.txt" }
    $stratPath = if ($global:PATH_DATA_STRATEGY) { $global:PATH_DATA_STRATEGY } else { Join-Path $PSScriptRoot "data_strategies.json" }

    if (-not (Test-Path $rawPath)) {
        Write-Host "  > Waiting for strategy reports (create data_raw_reports.txt to enable)." -ForegroundColor DarkGray
        return
    }

    try {
        $content      = Get-Content -Path $rawPath -Raw -Encoding utf8
        $symbolsFound = @{}

        $allMatches = [regex]::Matches($content, "\b[A-Z]{3,5}\b")
        foreach ($m in $allMatches) {
            $sym = $m.Value
            if ($sym -notin $STOPWORDS) {
                if (-not $symbolsFound.ContainsKey($sym)) {
                    $symbolsFound[$sym] = @{ count = 0 }
                }
                $symbolsFound[$sym].count++
            }
        }

        $topPicks = @($symbolsFound.GetEnumerator() | Where-Object { $_.Value.count -ge 2 } | ForEach-Object {
            $conf = [Math]::Min(0.99, 0.80 + ($_.Value.count * 0.02))
            @{
                symbol     = $_.Key
                count      = $_.Value.count
                market     = if ($_.Key -match "^(BTC|ETH|SOL|NEAR|XRP|DOGE|ADA|AVAX|LINK|BNB)$") { "crypto" } else { "us-stock" }
                reason     = "Strategic consensus: detected across $($_.Value.count) report mentions."
                confidence = [Math]::Round($conf, 2)
            }
        } | Sort-Object count -Descending)

        if ($topPicks.Count -gt 0) {
            $topPicks | ConvertTo-Json -Depth 4 | Out-File -FilePath $stratPath -Encoding utf8
            Write-Host "  > SUCCESS: Strategy insights updated ($($topPicks.Count) consensus assets)." -ForegroundColor Green
        } else {
            Write-Host "  > No multi-mention consensus found yet." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERROR] Strategist analysis failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Bot 6 (Strategist) ONLINE" -ForegroundColor Magenta
while ($true) {
    Invoke-StrategyAnalysis
    Start-Sleep -Seconds 300
}

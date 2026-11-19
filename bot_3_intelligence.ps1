# ==============================================================================
# BOT 3: GLOBAL INTELLIGENCE
# ==============================================================================
# Scans real-time platform feeds and latest news to rank trending assets
# using a confidence-based scoring system (0.80 Feed Trend / 0.95 Trend + News).
# ==============================================================================

. "$PSScriptRoot\config.ps1"

function Get-NewsKeywords {
    $headers  = @{ Authorization = "Bearer $global:TOKEN" }
    $keywords = @()
    try {
        $news = Invoke-RestMethod -Uri "$($global:BASE_URL)/news/latest?limit=20" -Method Get -Headers $headers
        if ($news -and $news.news) {
            foreach ($item in @($news.news)) {
                if ($item.content) {
                    $matchesFound = [regex]::Matches($item.content, "\b[A-Z]{2,6}\b")
                    foreach ($m in $matchesFound) { $keywords += $m.Value }
                }
            }
        }
    } catch {}
    return @($keywords | Select-Object -Unique)
}

function Invoke-IntelScan {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Scanning global intelligence..." -ForegroundColor Cyan
    $headers = @{ Authorization = "Bearer $global:TOKEN" }

    try {
        $keywords = Get-NewsKeywords
        $feed     = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/feed?limit=50" -Method Get -Headers $headers
        $signals  = @($feed.signals | Where-Object { $null -ne $_.symbol -and $_.symbol -ne "" })

        $trends = @($signals | Group-Object symbol | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
            $sym    = $_.Name
            $market = $_.Group[0].market
            $inNews = ($keywords -contains $sym)

            @{
                symbol        = $sym
                market        = $market
                source        = if ($inNews) { "Trend + News" } else { "Market Trend" }
                confidence    = if ($inNews) { 0.95 } else { 0.80 }
                discovered_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                reason        = "Market consensus: $($_.Count) active signals in live feed."
            }
        })

        $trends | ConvertTo-Json -Depth 4 | Out-File -FilePath $global:PATH_DATA_INTEL -Encoding utf8
        Write-Host "  > Intelligence updated ($($trends.Count) trending assets)." -ForegroundColor Green
        return $trends.Count
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            $global:TOKEN = Update-Session
        }
        Write-Host "[ERROR] Intelligence scan failed: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
}

Write-Host "Bot 3 (Intelligence) ONLINE" -ForegroundColor Cyan
while ($true) {
    $count = Invoke-IntelScan
    $sleep = if ($count -gt 0) { Get-Random -Minimum 30 -Maximum 60 } else { Get-Random -Minimum 60 -Maximum 120 }
    Write-Host "  > Next scan in ${sleep}s..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $sleep
}

# ==============================================================================
# BOT 1: THE EXECUTOR
# ==============================================================================
# Monitors open positions, manages dynamic trailing stops & hard take-profit,
# records trades in log_journal.txt, and executes consensus-driven entries.
# ==============================================================================

. "$PSScriptRoot\config.ps1"

$script:peakPnl   = @{}
$script:scanCount = 0

function Write-Log {
    param(
        [string]$msg,
        [string]$color = "White"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $msg"
    Write-Host $line -ForegroundColor $color

    $logPath = if ($global:PATH_LOG_MONITOR) { $global:PATH_LOG_MONITOR } else { Join-Path $PSScriptRoot "log_monitor.txt" }
    try {
        if ($msg -eq "--- Scan ---" -and $script:scanCount -ge 50) {
            $line | Out-File -FilePath $logPath -Encoding utf8
            $script:scanCount = 0
        } else {
            $line | Out-File -FilePath $logPath -Append -Encoding utf8
        }
    } catch {}
}

function Write-Journal {
    param(
        [string]$action,
        [string]$symbol,
        [double]$qty,
        [double]$price,
        [double]$pnl = 0
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    if ($action -eq "BUY") {
        $line = "[$timestamp] [BUY]  $symbol | Qty: $qty | Price: $price"
    } else {
        $pnlPct    = "{0:P2}" -f $pnl
        $profitVal = [Math]::Round(($price * $qty) * $pnl, 2)
        $line      = "[$timestamp] [SELL] $symbol | Qty: $qty | Price: $price | PnL: $pnlPct | Est. Profit: `$$profitVal"
    }
    try { $line | Out-File -FilePath $global:PATH_LOG_JOURNAL -Append -Encoding utf8 } catch {}
}

function Get-Positions {
    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    try {
        return Invoke-RestMethod -Uri "$($global:BASE_URL)/positions" -Method Get -Headers $headers
    } catch {
        if ($null -ne $_.Exception.Response -and $_.Exception.Response.StatusCode -eq "Unauthorized") {
            $global:TOKEN = Update-Session
        }
        return $null
    }
}

function Get-AssetPrice {
    param([string]$symbol)
    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    try {
        $resP = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/realtime?symbol=$symbol" -Method Get -Headers $headers
        if ($resP -and $resP.price -gt 0) { return [double]$resP.price }
    } catch {}

    try {
        $feed  = Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/feed?limit=20" -Method Get -Headers $headers
        $match = @($feed.signals) | Where-Object { $_.symbol -eq $symbol } | Select-Object -First 1
        if ($match) {
            if ($match.current_price -gt 0) { return [double]$match.current_price }
            if ($match.entry_price -gt 0)   { return [double]$match.entry_price }
        }
    } catch {}

    return 0
}

function Invoke-TradeSell {
    param(
        [string]$symbol,
        [string]$market,
        [double]$qty,
        [double]$price,
        [double]$pnl
    )
    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    $body = @{
        market      = $market
        action      = "sell"
        symbol      = $symbol
        price       = $null
        quantity    = $qty
        executed_at = "now"
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/realtime" -Method Post -Body $body -Headers $headers -ContentType "application/json" | Out-Null
        $pnlPct = "{0:P2}" -f $pnl
        Write-Log -msg "EXIT: Sold $qty $symbol at $price (PnL: $pnlPct)" -color "Yellow"
        Write-Journal -action "SELL" -symbol $symbol -qty $qty -price $price -pnl $pnl
        $script:peakPnl.Remove($symbol)
        Invoke-Alert -freq 1200 -dur 150
        Start-Sleep -Milliseconds 100
        Invoke-Alert -freq 1600 -dur 200
    } catch {
        Write-Log -msg "ERROR: Failed to sell $symbol - $($_.Exception.Message)" -color "Red"
    }
}

function Invoke-TradeBuy {
    param(
        [object]$target,
        [string]$sourceLabel
    )
    $s = $target.symbol
    $m = if ($target.market) { $target.market } else { "crypto" }
    $price = Get-AssetPrice -symbol $s

    if ($price -le 0) {
        Write-Log -msg "SKIP: Unable to resolve live price for $s" -color "DarkYellow"
        return $false
    }

    $qty = if ($m -match "stock") { [Math]::Floor($global:BUY_AMOUNT / $price) } else { [Math]::Round($global:BUY_AMOUNT / $price, 2) }
    if ($qty -le 0) { return $false }

    $headers = @{ Authorization = "Bearer $global:TOKEN" }
    $body = @{
        market      = $m
        action      = "buy"
        symbol      = $s
        price       = $null
        quantity    = $qty
        executed_at = "now"
    } | ConvertTo-Json

    Write-Log -msg "[$sourceLabel] Buying $qty $s @ ~$price ($m)" -color "Cyan"
    Invoke-Alert -freq 1500 -dur 60
    try {
        Invoke-RestMethod -Uri "$($global:BASE_URL)/signals/realtime" -Method Post -Body $body -Headers $headers -ContentType "application/json" | Out-Null
        Write-Log -msg "SUCCESS: Order placed for $qty $s" -color "Green"
        Write-Journal -action "BUY" -symbol $s -qty $qty -price $price
        return $true
    } catch {
        Write-Log -msg "TRADE ERROR ($s): $($_.Exception.Message)" -color "Red"
        return $false
    }
}

# === MAIN LOOP ===
Write-Log -msg "Bot 1 (Executor) ONLINE | Target: $($global:TARGET_MIN * 100)%-$($global:TARGET_MAX * 100)% | Trail: $($global:TRAIL_BUFFER * 100)%" -color "Yellow"

while ($true) {
    try {
        $script:scanCount++
        Write-Log -msg "--- Scan ---" -color "Gray"
        $data = Get-Positions

        # 1. Monitor Open Positions & Trailing Stop
        if ($data -and $data.positions) {
            foreach ($pos in @($data.positions)) {
                $symbol  = $pos.symbol
                $entry   = [double]$pos.entry_price
                $current = [double]$pos.current_price
                $qty     = [double]$pos.quantity

                if ($entry -gt 0 -and $qty -gt 0) {
                    if ($current -le 0) {
                        $current = Get-AssetPrice -symbol $symbol
                    }
                    if ($current -gt 0) {
                        $pnl    = ($current - $entry) / $entry
                        $pnlPct = "{0:P2}" -f $pnl
                        Write-Log -msg "  $symbol : $pnlPct (Entry: $entry | Now: $current)" -color "White"

                        if (-not $script:peakPnl.ContainsKey($symbol) -or $pnl -gt $script:peakPnl[$symbol]) {
                            $script:peakPnl[$symbol] = $pnl
                        }

                        if ($pnl -ge $global:TARGET_MAX) {
                            Invoke-TradeSell -symbol $symbol -market $pos.market -qty $qty -price $current -pnl $pnl
                        } elseif ($pnl -ge $global:TARGET_MIN) {
                            $peak = $script:peakPnl[$symbol]
                            $drop = $peak - $pnl
                            if ($drop -ge $global:TRAIL_BUFFER) {
                                Invoke-TradeSell -symbol $symbol -market $pos.market -qty $qty -price $current -pnl $pnl
                            }
                        }
                    }
                }
            }
        }

        # 2. Auto-Invest Hierarchy (Priority 1: Strategist, Priority 2: Intelligence)
        $portfolio = Get-Positions
        if ($portfolio -and ($portfolio.cash -gt ($global:RESERVE + $global:BUY_AMOUNT))) {
            $openSymbols = @($portfolio.positions | ForEach-Object { $_.symbol })
            $target      = $null
            $sourceLabel = ""

            # Priority 1: Strategist Consensus (Bot 6)
            if (Test-Path $global:PATH_DATA_STRATEGY) {
                try {
                    $strats = @(Get-Content -Path $global:PATH_DATA_STRATEGY -Raw -Encoding utf8 | ConvertFrom-Json)
                    $bestS  = $strats | Sort-Object confidence -Descending | Where-Object { $_.symbol -and ($openSymbols -notcontains $_.symbol) } | Select-Object -First 1
                    if ($bestS -and $bestS.confidence -ge 0.75) {
                        $target      = $bestS
                        $sourceLabel = "STRATEGY-BUY"
                    }
                } catch {}
            }

            # Priority 2: Global Intelligence (Bot 3)
            if ($null -eq $target -and (Test-Path $global:PATH_DATA_INTEL)) {
                try {
                    $intel = @(Get-Content -Path $global:PATH_DATA_INTEL -Raw -Encoding utf8 | ConvertFrom-Json)
                    $bestI = $intel | Sort-Object confidence -Descending | Where-Object { $_.symbol -and ($openSymbols -notcontains $_.symbol) } | Select-Object -First 1
                    if ($bestI -and $bestI.confidence -ge 0.80) {
                        $target      = $bestI
                        $sourceLabel = "INTEL-BUY"
                    }
                } catch {}
            }

            if ($target -and $target.symbol) {
                Invoke-TradeBuy -target $target -sourceLabel $sourceLabel | Out-Null
            }
        }

        Write-Log -msg "--- OK ---" -color "Gray"
    } catch {
        Write-Log -msg "CYCLE WARNING: $($_.Exception.Message)" -color "Red"
    }

    Invoke-Alert -freq 800 -dur 120
    Start-Sleep -Seconds 15
}

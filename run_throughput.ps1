param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("debian", "alpine", "vm")]
    [string]$Setup,
    [int]$Runs = 3
)

New-Item -ItemType Directory -Force -Path results | Out-Null

if ($Setup -eq "vm") { $url = "http://127.0.0.1:8080" } else { $url = "http://127.0.0.1:8081" }

function Wait-ForApp($url) {
    for ($n = 0; $n -lt 60; $n++) {
        $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 $url
        if ($code -eq "200") { return }
        Start-Sleep -Milliseconds 500
    }
    throw "App did not answer at $url (last HTTP code: $code)"
}

$summaryFile = "results\summary.csv"
if (-not (Test-Path $summaryFile)) {
    "setup,run,req_per_s,avg_latency_ms,failed_pct" | Out-File $summaryFile -Encoding ascii
}

try {
    if ($Setup -ne "vm") {
        docker run -d --cpus 2 --memory 2g -p 127.0.0.1:8081:8080 --name "$Setup-app" "app-$Setup" | Out-Null
    }
    Wait-ForApp $url

    Write-Host "Warm-up run (not recorded)..."
    k6 run --vus 20 --duration 30s -e TARGET=$url loadtest.js | Out-Null

    for ($i = 1; $i -le $Runs; $i++) {
        Write-Host "Recorded run $i of $Runs..."
        k6 run --vus 20 --duration 30s -e TARGET=$url loadtest.js | Tee-Object -Variable k6out
        $text = $k6out -join "`n"
        $text | Out-File "results\${Setup}_run$i.txt" -Encoding utf8

        $rps = [regex]::Match($text, 'http_reqs\.+:\s+\d+\s+([\d.]+)/s').Groups[1].Value
        $lat = [regex]::Match($text, 'http_req_duration\.+:\s+avg=([\d.]+)(\S+)')
        $latVal = [double]$lat.Groups[1].Value
        switch ($lat.Groups[2].Value) {
            "s"  { $latVal = $latVal * 1000 }
            "ms" { }
            default { $latVal = $latVal / 1000 }
        }
        $failed = [regex]::Match($text, 'http_req_failed\.+:\s+([\d.]+)%').Groups[1].Value
        "$Setup,$i,$rps,$latVal,$failed" | Out-File $summaryFile -Append -Encoding ascii

        Start-Sleep -Seconds 10
    }
}
finally {
    if ($Setup -ne "vm") {
        docker stop "$Setup-app" | Out-Null
        docker rm "$Setup-app" | Out-Null
    }
}
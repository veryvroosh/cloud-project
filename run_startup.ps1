param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("debian", "alpine", "vm")]
    [string]$Setup,
    [int]$Runs = 3
)

New-Item -ItemType Directory -Force -Path results | Out-Null
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$vmName = "ubuntu-vm"

if ($Setup -eq "vm") { $url = "http://127.0.0.1:8080" } else { $url = "http://127.0.0.1:8081" }

function Test-App($url) {
    $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 1 $url
    return ($code -eq "200")
}

function Measure-Startup {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Setup -eq "vm") {
        & $vbox startvm $vmName --type gui | Out-Null
    } else {
        docker run -d --cpus 2 --memory 2g -p 127.0.0.1:8081:8080 --name "$Setup-app" "app-$Setup" | Out-Null
    }
    while (-not (Test-App $url)) {
        if ($sw.Elapsed.TotalSeconds -gt 300) { throw "App did not answer within 300 seconds" }
        Start-Sleep -Milliseconds 50
    }
    $sw.Stop()
    return $sw.Elapsed.TotalSeconds
}

function Stop-Setup([int]$SettleSeconds = 0) {
    if ($Setup -eq "vm") {
        $running = (& $vbox list runningvms) -match [regex]::Escape($vmName)
        if (-not $running) { return }
        if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
        & $vbox controlvm $vmName acpipowerbutton 2>$null | Out-Null
        for ($n = 0; $n -lt 120; $n++) {
            Start-Sleep -Seconds 1
            if (-not ((& $vbox list runningvms) -match [regex]::Escape($vmName))) { break }
        }
        Start-Sleep -Seconds 5
    } else {
        docker stop "$Setup-app" 2>$null | Out-Null
        docker rm "$Setup-app" 2>$null | Out-Null
    }
}

$csv = "results\startup.csv"
if (-not (Test-Path $csv)) { "setup,run,startup_seconds" | Out-File $csv -Encoding ascii }

try {
    Stop-Setup
    Start-Sleep -Seconds 5

    Write-Host "Warm-up start (not recorded)..."
    Measure-Startup | Out-Null
    Stop-Setup 90
    Start-Sleep -Seconds 10

    for ($i = 1; $i -le $Runs; $i++) {
        $t = [math]::Round((Measure-Startup), 2)
        Write-Host "Run ${i}: $t seconds"
        "$Setup,$i,$t" | Out-File $csv -Append -Encoding ascii
        Stop-Setup 90
        Start-Sleep -Seconds 10
    }
}
finally {
    Stop-Setup
}
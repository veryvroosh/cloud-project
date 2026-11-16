param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("debian", "alpine", "vm")]
    [string]$Setup,
    [int]$Samples = 3
)

New-Item -ItemType Directory -Force -Path results | Out-Null
$csv = "results\memory.csv"
if (-not (Test-Path $csv)) { "setup,sample,memory_mb" | Out-File $csv -Encoding ascii }

function Wait-ForApp($url) {
    for ($n = 0; $n -lt 60; $n++) {
        $code = curl.exe -s -o NUL -w "%{http_code}" --max-time 2 $url
        if ($code -eq "200") { return }
        Start-Sleep -Milliseconds 500
    }
    throw "App did not answer at $url"
}

function Get-ContainerMemoryMB($name) {
    $raw = docker stats --no-stream --format "{{.MemUsage}}" $name
    $m = [regex]::Match($raw, '^([\d.]+)\s*(KiB|MiB|GiB)')
    $v = [double]$m.Groups[1].Value
    switch ($m.Groups[2].Value) {
        "KiB" { return $v / 1024 }
        "GiB" { return $v * 1024 }
        default { return $v }
    }
}

function Get-VmMemoryMB {
    $procs = Get-Process -Name VirtualBoxVM, VBoxHeadless -ErrorAction SilentlyContinue
    if (-not $procs) { throw "No running VirtualBox VM process found" }
    return ($procs | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB
}

try {
    if ($Setup -eq "vm") {
        Wait-ForApp "http://127.0.0.1:8080"
    } else {
        docker run -d --cpus 2 --memory 2g -p 127.0.0.1:8081:8080 --name "$Setup-app" "app-$Setup" | Out-Null
        Wait-ForApp "http://127.0.0.1:8081"
    }

    Write-Host "Idling for 60 seconds..."
    Start-Sleep -Seconds 60

    for ($i = 1; $i -le $Samples; $i++) {
        if ($Setup -eq "vm") { $mb = Get-VmMemoryMB } else { $mb = Get-ContainerMemoryMB "$Setup-app" }
        $mb = [math]::Round($mb, 1)
        Write-Host "Sample ${i}: $mb MB"
        "$Setup,$i,$mb" | Out-File $csv -Append -Encoding ascii
        Start-Sleep -Seconds 10
    }
}
finally {
    if ($Setup -ne "vm") {
        docker stop "$Setup-app" 2>$null | Out-Null
        docker rm "$Setup-app" 2>$null | Out-Null
    }
}
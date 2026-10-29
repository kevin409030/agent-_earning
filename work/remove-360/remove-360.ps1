param([switch]$Elevate)

$ErrorActionPreference = 'Stop'
$taskRoot = 'C:\Users\24135\agent learning\work\remove-360'
$logPath = Join-Path $taskRoot 'cleanup.log'
$statusPath = Join-Path $taskRoot 'result.json'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not $Elevate) { throw 'Administrator access is required to remove the system service.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
    Write-Output 'UAC_REQUESTED'
    exit
}

$errors = New-Object 'System.Collections.Generic.List[string]'
function Run-Step([string]$label, [scriptblock]$action) {
    try {
        & $action
        Add-Content -LiteralPath $logPath -Value ('OK: ' + $label) -Encoding UTF8
    } catch {
        $message = $label + ': ' + $_.Exception.Message
        $errors.Add($message)
        Add-Content -LiteralPath $logPath -Value ('FAILED: ' + $message) -Encoding UTF8
    }
}

# Only explicitly identified 360 product folders and their installers are removed.
$targets = @(
    'C:\Users\24135\AppData\Roaming\360browser',
    'C:\Users\24135\AppData\Roaming\360huabao',
    'C:\Users\24135\AppData\Roaming\kaixinhuabao',
    'C:\Users\24135\AppData\Roaming\360Login',
    'C:\Users\24135\AppData\Roaming\360Safe',
    'C:\Users\24135\AppData\Roaming\360se6',
    'C:\Users\24135\AppData\Roaming\greencore',
    'C:\Users\24135\AppData\Roaming\GreenCore7z',
    'C:\Users\24135\AppData\Local\Temp\360hb_tmp',
    'C:\Users\24135\AppData\Local\Temp\360UnPackTmp',
    'C:\Users\24135\AppData\Local\Temp\360se16.0.6018.0.exe',
    'C:\Users\24135\AppData\Local\Temp\360se16.0.6018.0.cab',
    'C:\ProgramData\360SD',
    'C:\Program Files (x86)\360',
    'C:\Users\24135\Desktop\360安全浏览器.lnk',
    'C:\Users\Public\Desktop\360安全浏览器.lnk',
    'C:\Users\24135\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\360安全浏览器',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\360安全浏览器'
)
$allowed = @{}
foreach ($target in $targets) {
    $full = [IO.Path]::GetFullPath($target).TrimEnd('\')
    if ($full -ne $target.TrimEnd('\') -or $full.Length -lt 20) { throw ('Unsafe target: ' + $target) }
    $allowed[$full.ToLowerInvariant()] = $true
}
$targets | Set-Content -LiteralPath (Join-Path $taskRoot 'approved-targets.txt') -Encoding UTF8
Set-Content -LiteralPath $logPath -Value ('Started: ' + (Get-Date -Format o)) -Encoding UTF8

$productPattern = '(?i)\\(?:360se6|360huabao|kaixinhuabao|360browser|360Safe|360Login|greencore|GreenCore7z)\\|\\Program Files \(x86\)\\360\\'

Run-Step 'Remove 360 scheduled tasks' {
    $tasks = Get-ScheduledTask | Where-Object {
        $_.TaskName -match '^(360|Qihoo)' -or ($_.Actions.Execute -join ' ') -match $productPattern
    }
    foreach ($task in $tasks) {
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
    }
}

Run-Step 'Remove 360 startup entries' {
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($keyPath in $runKeys) {
        if (Test-Path $keyPath) {
            $key = Get-Item $keyPath
            foreach ($name in $key.GetValueNames()) {
                if ($name -match '^(360huabao|kaixinbizhi|sesvc)$' -or [string]$key.GetValue($name) -match $productPattern) {
                    Remove-ItemProperty -LiteralPath $keyPath -Name $name
                }
            }
        }
    }
}

Run-Step 'Stop and remove 360 services' {
    $services = Get-CimInstance Win32_Service | Where-Object { $_.Name -eq '360bpsvc' -or $_.PathName -match $productPattern }
    foreach ($service in $services) {
        if ($service.State -ne 'Stopped') { Stop-Service -Name $service.Name -Force }
        & "$env:SystemRoot\System32\sc.exe" delete $service.Name | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('sc delete failed: ' + $service.Name + ' code ' + $LASTEXITCODE) }
    }
}

Run-Step 'Stop 360 processes' {
    $processes = Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -match $productPattern -or $_.Name -match '^(360se|360secore|360bpsvc|360huabao|sesvc|seup|360chromeup)\.exe$'
    }
    foreach ($process in $processes) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
}

foreach ($target in $targets) {
    Run-Step ('Remove ' + $target) {
        if (Test-Path -LiteralPath $target) {
            $resolved = (Resolve-Path -LiteralPath $target).ProviderPath.TrimEnd('\')
            if (-not $allowed.ContainsKey($resolved.ToLowerInvariant())) { throw ('Target outside exact allowlist: ' + $resolved) }
            $item = Get-Item -LiteralPath $resolved -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point target requires manual inspection.' }
            if ($item.PSIsContainer) {
                $links = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
                if ($links.Count -gt 0) { throw 'Folder contains reparse points; skipped for inspection.' }
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

Run-Step 'Remove 360 installation and application registry entries' {
    $registryTargets = @(
        'HKCU:\Software\360', 'HKCU:\Software\360se6',
        'HKLM:\Software\360', 'HKLM:\Software\WOW6432Node\360',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\360se6'
    )
    $entryRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths',
        'HKCU:\Software\Clients\StartMenuInternet',
        'HKLM:\Software\Clients\StartMenuInternet',
        'HKLM:\Software\WOW6432Node\Clients\StartMenuInternet',
        'HKCU:\Software\Classes', 'HKLM:\Software\Classes'
    )
    foreach ($root in $entryRoots) {
        if (Test-Path $root) {
            foreach ($entry in Get-ChildItem -LiteralPath $root) {
                $properties = Get-ItemProperty -LiteralPath $entry.PSPath
                if ($entry.PSChildName -match '^(360|Qihoo)' -or $properties.InstallLocation -match $productPattern -or $properties.UninstallString -match $productPattern) {
                    $registryTargets += $entry.PSPath
                }
            }
        }
    }
    foreach ($entry in ($registryTargets | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $entry) { Remove-Item -LiteralPath $entry -Recurse -Force }
    }
    foreach ($appRoot in @('HKCU:\Software\RegisteredApplications','HKLM:\Software\RegisteredApplications')) {
        if (Test-Path $appRoot) {
            $key = Get-Item $appRoot
            foreach ($name in $key.GetValueNames()) {
                if ($name -match '^(360|Qihoo)' -or [string]$key.GetValue($name) -match '(?i)Software\\360\\|360se6|360huabao') {
                    Remove-ItemProperty -LiteralPath $appRoot -Name $name
                }
            }
        }
    }
}

$remainingPaths = @($targets | Where-Object { Test-Path -LiteralPath $_ })
$remainingProcesses = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match $productPattern -or $_.Name -match '^(360se|360secore|360bpsvc|360huabao|sesvc)\.exe$' } | Select-Object Name,ProcessId,ExecutablePath)
$remainingServices = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -eq '360bpsvc' -or $_.PathName -match $productPattern } | Select-Object Name,State,PathName)
[pscustomobject]@{
    Completed = (Get-Date -Format o)
    RemainingPaths = $remainingPaths
    RemainingProcesses = $remainingProcesses
    RemainingServices = $remainingServices
    Errors = @($errors.ToArray())
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statusPath -Encoding UTF8
Get-Content -LiteralPath $statusPath

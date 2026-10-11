param(
    [Parameter(Mandatory)][ValidateSet('clean','upgrade')][string]$Scenario,
    [Parameter(Mandatory)][string]$CurrentDirectory,
    [Parameter(Mandatory)][string]$BaselineDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
# This script installs software and is intentionally restricted to hosted CI VMs.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Installer QA may run only in a disposable GitHub-hosted runner.'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$installDirectory = Join-Path $env:ProgramFiles 'MiuAI'
$currentMsi = Join-Path ([IO.Path]::GetFullPath($CurrentDirectory)) 'miu-ai-test-x64.msi'
$baselineMsi = Join-Path ([IO.Path]::GetFullPath($BaselineDirectory)) 'miu-ai-test-x64.msi'
$blockName = 'Miu QA isolation'
$productCode = ''
$installed = $false
$systemPolicy = [Collections.Generic.List[object]]::new()

function Check([string]$Name, [bool]$Passed, [string]$Detail, [string]$FailureStatus = 'FAIL') {
    $status = if ($Passed) {'PASS'} else {$FailureStatus}
    $checks.Add([pscustomobject]@{name=$Name;status=$status;detail=$Detail})
    Write-Output "$status $Name : $Detail"
}
function Read-Property([string]$Msi, [string]$Name) {
    $database = (New-Object -ComObject WindowsInstaller.Installer).OpenDatabase($Msi, 0)
    $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$Name'")
    $view.Execute()
    try { return $view.Fetch().StringData(1) } finally { $view.Close() }
}
function Record-SystemPolicy([string]$Stage) {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $value = Get-ItemPropertyValue -LiteralPath $key -Name 'SoftwareSASGeneration' -ErrorAction SilentlyContinue
    $systemPolicy.Add([pscustomobject]@{stage=$Stage;name='SoftwareSASGeneration';present=($null -ne $value);value=$value})
}
function Run-Msi([string]$Package, [string]$Operation, [string]$Label) {
    $log = Join-Path $output "$Label-msi.log"
    $args = @($Operation, ('"' + $Package + '"'), '/qn', '/norestart', 'REBOOT=ReallySuppress', '/l*v', ('"' + $log + '"'))
    $process = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(300000)) { throw "MSI timed out: $Label" }
    Check "$Label exit" ($process.ExitCode -in 0,3010) "ExitCode=$($process.ExitCode)"
    if ($process.ExitCode -notin 0,3010) { throw "MSI failed: $Label" }
}
function Shortcuts {
    $roots = @([Environment]::GetFolderPath('CommonStartMenu'), [Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('DesktopDirectory')) | Select-Object -Unique
    $shell = New-Object -ComObject WScript.Shell
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue) {
            if ($file.Name -notmatch 'Miu') { continue }
            $shortcut = $shell.CreateShortcut($file.FullName)
            [pscustomobject]@{path=$file.FullName;target=$shortcut.TargetPath;arguments=$shortcut.Arguments}
        }
    }
}
function Verify-Installation([string]$Label, [string]$ExpectedCommit, [bool]$WithBoot) {
    $service = Get-Service -Name MiuAI -ErrorAction SilentlyContinue
    if ($service) {
        try { $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30)) } catch {}
    }
    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='MiuAI'"
    Check "$Label service" ($null -ne $serviceInfo -and $serviceInfo.State -eq 'Running' -and $serviceInfo.StartMode -eq 'Auto') ($serviceInfo | Select-Object Name,State,StartMode,PathName | ConvertTo-Json -Compress)
    Check "$Label source" ((Get-Content -LiteralPath (Join-Path $installDirectory 'SOURCE.txt') -Raw) -match $ExpectedCommit) $ExpectedCommit
    $links = @(Shortcuts)
    $links | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $output "$Label-shortcuts.json")
    Check "$Label Start menu" (@($links | Where-Object { $_.target -eq (Join-Path $installDirectory 'MiuAI.exe') -and $_.path -notmatch '\\Startup\\' -and $_.path -match '\\Start Menu\\' }).Count -ge 1) 'MiuAI entry exists'
    Check "$Label no desktop shortcut" (@($links | Where-Object { $_.path -match '\\Desktop\\' }).Count -eq 0) 'No Miu shortcut on desktop'
    $petLink = @($links | Where-Object { $_.path -match '\\Startup\\' -and $_.path -like '*Miu AI Pet.lnk' })
    $argsExpected = if ($WithBoot) {'--cm --miu-login'} else {'--cm'}
    Check "$Label login shortcut" ($petLink.Count -eq 1 -and $petLink[0].arguments -eq $argsExpected) ($petLink | ConvertTo-Json -Compress)
    if ($WithBoot) {
        $boot = Join-Path $installDirectory 'MiuBoot\MiuBoot.exe'
        Check "$Label boot file" (Test-Path -LiteralPath $boot) $boot
        if (Test-Path -LiteralPath $boot) {
            $probe = Start-Process -FilePath $boot -ArgumentList '--check' -WindowStyle Hidden -PassThru
            if (-not $probe.WaitForExit(10000)) { $probe.Kill(); Check "$Label runtime probe" $false 'Timed out' }
            else { Check "$Label runtime probe" ($probe.ExitCode -eq 0) "ExitCode=$($probe.ExitCode); WebView2 availability on this VM" 'UNVERIFIED' }
        }
    }
}

try {
    $environment = [ordered]@{scenario=$Scenario;os=(Get-CimInstance Win32_OperatingSystem).Caption;runner=$env:ImageVersion;isolation='Program-specific outbound firewall block; no remote sessions; no API key';login='Process-launch simulation only; no Windows sign out/reboot'}
    $environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'environment.json')
    Record-SystemPolicy 'before-install'
    $expectedHash = '3014EE7F607DBF8A691877C8D1E6F43B0147F55B13196F32180253F1D63B7355'
    if ((Get-FileHash -LiteralPath $currentMsi).Hash -ne $expectedHash) { throw 'Run25 MSI SHA-256 does not match delivered package' }
    Check 'Run25 package identity' $true $expectedHash
    $expectedZipHash = '7A56A38968B9B9BC860C109A992F386FD805ED7A0630366073C5B730E565E33D'
    if ((Get-FileHash -LiteralPath (Join-Path $CurrentDirectory 'miu-ai-test-x64-portable.zip')).Hash -ne $expectedZipHash) { throw 'Run25 portable SHA-256 does not match delivered package' }
    Check 'Run25 portable identity' $true $expectedZipHash
    $productCode = Read-Property $currentMsi 'ProductCode'
    if (Get-Service -Name MiuAI -ErrorAction SilentlyContinue) { throw 'Runner is not clean: MiuAI already installed' }
    New-NetFirewallRule -DisplayName $blockName -Direction Outbound -Action Block -Program (Join-Path $installDirectory 'MiuAI.exe') -Profile Any | Out-Null
    Check 'Network isolation' (@(Get-NetFirewallRule -DisplayName $blockName | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' }).Count -eq 1) 'MiuAI.exe blocked before installation'

    if ($Scenario -eq 'upgrade') {
        $baselineHash = '84B2335327A9A2A80E7F5E618E0D77055780F95829F4B0803192C74CCE65577D'
        if ((Get-FileHash -LiteralPath $baselineMsi).Hash -ne $baselineHash) { throw 'Baseline MSI SHA-256 does not match delivered Run17' }
        $baselineProduct = Read-Property $baselineMsi 'ProductCode'
        Run-Msi $baselineMsi '/i' 'baseline-install'
        $installed = $true
        Verify-Installation 'baseline' 'e1fb4ea4202ace92bcdbbce18d9fb0ba99a30196' $false
        $configDirectory = Join-Path $env:APPDATA 'MiuAI\config'
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
        $sentinel = Join-Path $configDirectory 'qa-preserve.txt'
        Set-Content -LiteralPath $sentinel -Value 'Miu isolated installer upgrade marker'
    }

    Run-Msi $currentMsi '/i' 'current-install'
    $installed = $true
    Verify-Installation 'current' 'e23268d5eaf0e5eb0476b7f23719881cbc12cd6c' $true
    Record-SystemPolicy 'after-current-install'
    if ($Scenario -eq 'upgrade') {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        Check 'Old product removed' ($installer.ProductState($baselineProduct) -eq -1) "Previous ProductCode=$baselineProduct"
        Check 'User configuration directory preserved' ((Get-Content -LiteralPath $sentinel -Raw).Trim() -eq 'Miu isolated installer upgrade marker') 'Synthetic marker retained; does not assert real AI key migration'
    }

    $portableDirectory = Join-Path $output 'expected-payload'
    Expand-Archive -LiteralPath (Join-Path $CurrentDirectory 'miu-ai-test-x64-portable.zip') -DestinationPath $portableDirectory
    $payloadCount = 0
    $mismatches = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $portableDirectory -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($portableDirectory, $file.FullName)
        $actual = Join-Path $installDirectory $relative
        if (-not (Test-Path -LiteralPath $actual) -or (Get-FileHash -LiteralPath $actual).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { $mismatches.Add($relative) }
        $payloadCount++
    }
    Check 'Installed payload matches portable ZIP' ($mismatches.Count -eq 0) "Files=$payloadCount; mismatches=$($mismatches -join ', ')"
    # Only this known extraction directory is removed; never the installed app tree.
    $resolvedPayload = (Resolve-Path -LiteralPath $portableDirectory).Path
    if (-not $resolvedPayload.StartsWith($output + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid extraction cleanup path' }
    Remove-Item -LiteralPath $resolvedPayload -Recurse -Force

    $loginProcess = Start-Process -FilePath (Join-Path $installDirectory 'MiuAI.exe') -ArgumentList '--cm','--miu-login' -WindowStyle Hidden -PassThru
    $bootObserved = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Get-Process -Name MiuBoot -ErrorAction SilentlyContinue) { $bootObserved = $true; break }
        Start-Sleep -Milliseconds 250
    }
    Check 'Login command launches welcome player' $bootObserved 'Invoked installed MiuAI.exe --cm --miu-login; no Windows relogin; hosted runner desktop may differ' 'UNVERIFIED'
    if ($bootObserved) {
        for ($i = 0; $i -lt 100; $i++) {
            if (-not (Get-Process -Name MiuBoot -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 250
        }
        Check 'Welcome player exits' (-not (Get-Process -Name MiuBoot -ErrorAction SilentlyContinue)) 'Player exited within 25 seconds of observation'
    }
    Get-CimInstance Win32_Process | Where-Object Name -match '^Miu' | Select-Object Name,ProcessId,ParentProcessId,CommandLine | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'processes-before-uninstall.json')
    Run-Msi $productCode '/x' 'current-uninstall'
    $installed = $false
    Record-SystemPolicy 'after-current-uninstall'
    Start-Sleep -Seconds 2
    Check 'Service removed' (-not (Get-Service -Name MiuAI -ErrorAction SilentlyContinue)) 'MiuAI service absent'
    Check 'Program executable removed' (-not (Test-Path -LiteralPath (Join-Path $installDirectory 'MiuAI.exe'))) 'MiuAI.exe absent'
    Check 'Welcome executable removed' (-not (Test-Path -LiteralPath (Join-Path $installDirectory 'MiuBoot\MiuBoot.exe'))) 'MiuBoot.exe absent'
    $leftLinks = @(Shortcuts)
    Check 'Shortcuts removed' ($leftLinks.Count -eq 0) ($leftLinks | ConvertTo-Json -Compress)
    Check 'Product registration removed' ((New-Object -ComObject WindowsInstaller.Installer).ProductState($productCode) -eq -1) $productCode
    $leftFiles = @(Get-ChildItem -LiteralPath $installDirectory -Recurse -File -ErrorAction SilentlyContinue | Select-Object FullName,Length)
    $leftFiles | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'uninstall-residual-files.json')
    Check 'No installation payload remains' ($leftFiles.Count -eq 0) "Remaining files=$($leftFiles.Count)" 'WARN'
    $miuRules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'MiuAI' })
    Check 'Product firewall rules removed' ($miuRules.Count -eq 0) (($miuRules | Select-Object DisplayName,Direction,Action) | ConvertTo-Json -Compress)
} catch {
    Check 'QA execution' $false $_.Exception.Message
} finally {
    if ($installed -and $productCode) {
        try { Run-Msi $productCode '/x' 'cleanup-uninstall' } catch { Check 'Cleanup uninstall' $false $_.Exception.Message }
    }
    Remove-NetFirewallRule -DisplayName $blockName -ErrorAction SilentlyContinue
    $systemPolicy | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $output 'system-policy-observations.json')
    $checks | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'checks.json')
    $checks | Format-Table -Wrap | Out-String -Width 220 | Set-Content -LiteralPath (Join-Path $output 'summary.txt')
}
if (@($checks | Where-Object status -eq 'FAIL').Count -gt 0) { exit 1 }

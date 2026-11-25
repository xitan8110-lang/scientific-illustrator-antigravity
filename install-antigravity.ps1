<#
.SYNOPSIS
    One-click installer for scientific-illustrator-agent on Windows Antigravity.
.DESCRIPTION
    1. Installs the skill into %USERPROFILE%\.gemini\config\skills\scientific-illustrator-agent
       (or installs in-place if this repo was already cloned there).
    2. Creates a clean Python 3.9+ virtual environment (.venv) and installs requirements.txt
       using uv (preferred) or system Python (python / py -3).
    3. Installs bundled agent-desktop.exe (v1.3.1) into %USERPROFILE%\.local\bin\ and merges
       it into %USERPROFILE%\.gemini\config\mcp_config.json without overwriting other MCP servers.
    4. Runs offline validation checks (and optional live Illustrator COM check with -TestIllustrator).
#>
[CmdletBinding()]
param(
    [switch]$TestIllustrator,
    [switch]$ForceVenv
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $PSScriptRoot).Path
$SkillName = "scientific-illustrator-agent"
$GeminiConfigDir = Join-Path $env:USERPROFILE ".gemini\config"
$TargetSkillDir = Join-Path $GeminiConfigDir "skills\$SkillName"
$LocalBinDir = Join-Path $env:USERPROFILE ".local\bin"
$AgentDesktopTarget = Join-Path $LocalBinDir "agent-desktop.exe"
$AgentDesktopSource = Join-Path $RepoRoot "vendor\agent-desktop\agent-desktop.exe"
$McpConfigPath = Join-Path $GeminiConfigDir "mcp_config.json"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Scientific Illustrator Agent - Antigravity Windows Installer" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Install or detect in-place skill directory
$normalizedRepo = $RepoRoot.TrimEnd('\').ToLowerInvariant()
$normalizedTarget = $TargetSkillDir.TrimEnd('\').ToLowerInvariant()

if ($normalizedRepo -eq $normalizedTarget) {
    Write-Host "[1/4] Detected in-place clone at: $TargetSkillDir" -ForegroundColor Green
} else {
    Write-Host "[1/4] Copying skill files to: $TargetSkillDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $TargetSkillDir -Force | Out-Null
    $excludeNames = @(".git", ".venv", "__pycache__", "vendor", "outputs", "logs", "demos", "private")
    Get-ChildItem -Path $RepoRoot -Force | Where-Object { $excludeNames -notcontains $_.Name } | ForEach-Object {
        $destPath = Join-Path $TargetSkillDir $_.Name
        Copy-Item -Path $_.FullName -Destination $destPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $TargetSkillDir "logs") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TargetSkillDir "outputs") -Force | Out-Null
    Write-Host "      Skill files installed." -ForegroundColor Green
}

# 2. Create .venv and install Python dependencies
$VenvDir = Join-Path $TargetSkillDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$RequirementsFile = Join-Path $TargetSkillDir "requirements.txt"

if ($ForceVenv -and (Test-Path $VenvDir)) {
    Write-Host "      Removing existing .venv (-ForceVenv)..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $VenvDir
}

function Find-Uv {
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Find-SystemPython {
    foreach ($candidate in @("python", "py")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        if ($cmd.Source -like "*WindowsApps*") { continue }
        try {
            if ($candidate -eq "py") {
                $ver = & $cmd.Source -3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            } else {
                $ver = & $cmd.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            }
            if ($ver -and [version]$ver -ge [version]"3.9") {
                return @{ Exe = $cmd.Source; IsPyLauncher = ($candidate -eq "py"); Version = $ver.Trim() }
            }
        } catch {
            continue
        }
    }
    return $null
}

Write-Host "[2/4] Setting up Python virtual environment (.venv)..." -ForegroundColor Yellow
$uvExe = Find-Uv
if ($uvExe) {
    Write-Host "      Using uv: $uvExe" -ForegroundColor Gray
    if (-not (Test-Path $VenvPython)) {
        & $uvExe venv --python 3.12 $VenvDir
        if ($LASTEXITCODE -ne 0) { throw "uv venv creation failed." }
    }
    & $uvExe pip install --python $VenvPython -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) { throw "uv pip install failed." }
} else {
    $sysPy = Find-SystemPython
    if (-not $sysPy) {
        Write-Host ""
        Write-Host "ERROR: Neither Python 3.9+ nor uv was found on this PC." -ForegroundColor Red
        Write-Host "Recommended: install uv (it auto-manages Python 3.12) by running:" -ForegroundColor Yellow
        Write-Host '  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"' -ForegroundColor White
        Write-Host "Then reopen PowerShell and run .\install-antigravity.ps1 again." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "      Using Python $($sysPy.Version): $($sysPy.Exe)" -ForegroundColor Gray
    if (-not (Test-Path $VenvPython)) {
        if ($sysPy.IsPyLauncher) {
            & $sysPy.Exe -3 -m venv $VenvDir
        } else {
            & $sysPy.Exe -m venv $VenvDir
        }
        if ($LASTEXITCODE -ne 0) { throw "python -m venv failed." }
    }
    & $VenvPython -m pip install --upgrade pip
    & $VenvPython -m pip install -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) { throw "pip install failed." }
}
Write-Host "      Python environment ready: $VenvPython" -ForegroundColor Green

# 3. Install agent-desktop.exe and merge mcp_config.json
Write-Host "[3/4] Installing agent-desktop MCP server..." -ForegroundColor Yellow
if (-not (Test-Path $AgentDesktopSource)) {
    throw "Bundled agent-desktop.exe not found at: $AgentDesktopSource"
}
New-Item -ItemType Directory -Path $LocalBinDir -Force | Out-Null
Copy-Item -Path $AgentDesktopSource -Destination $AgentDesktopTarget -Force

New-Item -ItemType Directory -Path $GeminiConfigDir -Force | Out-Null
$mcpObj = $null
if (Test-Path $McpConfigPath) {
    $rawJson = Get-Content -Path $McpConfigPath -Raw -Encoding UTF8
    if ($rawJson.Trim().Length -gt 0) {
        $mcpObj = $rawJson | ConvertFrom-Json
    }
}
if (-not $mcpObj) {
    $mcpObj = [PSCustomObject]@{}
}
if (-not ($mcpObj.PSObject.Properties.Name -contains "mcpServers") -or -not $mcpObj.mcpServers) {
    $mcpObj | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{}) -Force
}

$agentDesktopEntry = [PSCustomObject]@{
    command = $AgentDesktopTarget
    args    = @("mcp")
}
$mcpObj.mcpServers | Add-Member -MemberType NoteProperty -Name "agent-desktop" -Value $agentDesktopEntry -Force

$jsonOut = $mcpObj | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($McpConfigPath, $jsonOut + "`n", $utf8NoBom)
Write-Host "      Installed: $AgentDesktopTarget" -ForegroundColor Green
Write-Host "      Updated:   $McpConfigPath" -ForegroundColor Green

# 4. Verify installation
Write-Host "[4/4] Verifying installation..." -ForegroundColor Yellow
$adVer = & $AgentDesktopTarget --version 2>&1
Write-Host "      agent-desktop: $adVer" -ForegroundColor Gray

$pyVer = & $VenvPython --version 2>&1
Write-Host "      venv python:   $pyVer" -ForegroundColor Gray

$validateScript = Join-Path $TargetSkillDir "examples\render_spec.py"
$sampleSpec = Join-Path $TargetSkillDir "examples\specs\pm25_workflow.json"
& $VenvPython $validateScript $sampleSpec --validate-only
if ($LASTEXITCODE -ne 0) { throw "Offline spec validation failed." }

if ($TestIllustrator) {
    Write-Host "      Testing live Adobe Illustrator COM connection..." -ForegroundColor Yellow
    $helloScript = Join-Path $TargetSkillDir "examples\hello_illustrator.py"
    & $VenvPython $helloScript --connect-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      WARNING: Illustrator COM check failed. Ensure Adobe Illustrator is installed and activated." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Installation complete!" -ForegroundColor Green
Write-Host " Next steps:" -ForegroundColor Green
Write-Host "   1. Make sure Adobe Illustrator is installed on this PC." -ForegroundColor White
Write-Host "   2. Fully restart Antigravity so it loads the skill and" -ForegroundColor White
Write-Host "      the agent-desktop MCP server." -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green

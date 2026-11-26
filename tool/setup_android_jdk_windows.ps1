[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$JdkHome,

    [Parameter(Mandatory = $false)]
    [switch]$InstallIfMissing
)

$ErrorActionPreference = 'Stop'

function Add-Candidate([System.Collections.Generic.List[string]]$List, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $candidate = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        if ([IO.Path]::GetFileName($candidate) -ieq 'java.exe') {
            $candidate = Split-Path -Parent (Split-Path -Parent $candidate)
        }
    }
    if ((Test-Path -LiteralPath $candidate -PathType Container) -and -not $List.Contains($candidate)) {
        $List.Add($candidate)
    }
}

function Get-Jdk17Candidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    Add-Candidate $candidates $JdkHome
    Add-Candidate $candidates $env:JAVA_HOME

    $patterns = @()
    if ($env:ProgramFiles) {
        $patterns += @(
            (Join-Path $env:ProgramFiles 'Eclipse Adoptium\jdk-17*'),
            (Join-Path $env:ProgramFiles 'Microsoft\jdk-17*'),
            (Join-Path $env:ProgramFiles 'Java\jdk-17*')
        )
    }
    if ($env:LOCALAPPDATA) {
        $patterns += (Join-Path $env:LOCALAPPDATA 'Programs\Eclipse Adoptium\jdk-17*')
    }

    foreach ($pattern in $patterns) {
        Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Property Name -Descending |
            ForEach-Object { Add-Candidate $candidates $_.FullName }
    }

    $javaCommands = Get-Command java.exe -All -ErrorAction SilentlyContinue
    foreach ($command in $javaCommands) {
        Add-Candidate $candidates $command.Source
    }
    return $candidates
}

function Get-JavaMajor([string]$Home) {
    $java = Join-Path $Home 'bin\java.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf)) { return $null }
    $versionOutput = (& $java -version 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { return $null }
    $match = [regex]::Match(
        $versionOutput,
        '(?im)^\s*(?:openjdk|java)\s+(?:version\s+)?["'']?(?<major>\d+)\.'
    )
    if (-not $match.Success) { return $null }
    return [int]$match.Groups['major'].Value
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand) {
    throw 'Flutter was not found in PATH. Install Flutter and reopen the terminal before running this script.'
}

$selectedJdk = $null
foreach ($candidate in (Get-Jdk17Candidates)) {
    if ((Get-JavaMajor $candidate) -eq 17) {
        $selectedJdk = $candidate
        break
    }
}

if (-not $selectedJdk -and $InstallIfMissing) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'No JDK 17 was found and winget is unavailable. Install a JDK 17 distribution, then rerun this script.'
    }
    Write-Host 'Installing Eclipse Temurin JDK 17 through Windows Package Manager...'
    & $winget.Source install --id EclipseAdoptium.Temurin.17.JDK --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install JDK 17 (exit code $LASTEXITCODE). Install JDK 17 manually and rerun this script."
    }
    $selectedJdk = $null
    foreach ($candidate in (Get-Jdk17Candidates)) {
        if ((Get-JavaMajor $candidate) -eq 17) {
            $selectedJdk = $candidate
            break
        }
    }
}

if (-not $selectedJdk) {
    throw @'
A compatible JDK 17 installation was not found.
Install it with:
  winget install --id EclipseAdoptium.Temurin.17.JDK -e
Then rerun:
  powershell -NoProfile -ExecutionPolicy Bypass -File tool\setup_android_jdk_windows.ps1
'@
}

Write-Host "Selected JDK 17: $selectedJdk"
& $flutterCommand.Source config "--jdk-dir=$selectedJdk"
if ($LASTEXITCODE -ne 0) {
    throw "Flutter could not save the JDK selection (exit code $LASTEXITCODE)."
}

$doctorOutput = (& $flutterCommand.Source doctor -v 2>&1 | Out-String)
$doctorExitCode = $LASTEXITCODE
Write-Host $doctorOutput
$doctorJava = [regex]::Match($doctorOutput, '(?im)Java version[^\r\n]*?\b(?<major>\d+)\.\d+')
if (-not $doctorJava.Success -or [int]$doctorJava.Groups['major'].Value -ne 17) {
    throw 'Flutter doctor did not confirm Java 17. Check the Android Studio Gradle JDK selection and rerun flutter doctor -v.'
}
if ($doctorExitCode -ne 0) {
    Write-Warning 'flutter doctor reported other environment issues. The Java selection is verified, but resolve any Android SDK/toolchain errors it reports.'
}

Write-Host ''
Write-Host 'SUCCESS: Flutter is configured to use JDK 17 for Android builds.' -ForegroundColor Green
Write-Host 'Next run from the project root:' -ForegroundColor Cyan
Write-Host '  flutter clean'
Write-Host '  flutter pub get'
Write-Host '  flutter run -t lib/AmitarGalleryPlayer.dart'

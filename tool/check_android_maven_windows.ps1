[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$agpVersion = '8.13.2'
$officialBase = 'https://dl.google.com/dl/android/maven2'
$artifacts = @(
    @{
        Name = 'AGP implementation POM (required after direct-module mapping)'
        RelativePath = "com/android/tools/build/gradle/$agpVersion/gradle-$agpVersion.pom"
        Required = $true
    },
    @{
        Name = 'AGP plugin-marker POM (informational; project no longer depends on it)'
        RelativePath = "com/android/application/com.android.application.gradle.plugin/$agpVersion/com.android.application.gradle.plugin-$agpVersion.pom"
        Required = $false
    }
)

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # Newer PowerShell/.NET versions may not expose this setter; use their defaults.
}

function Test-MavenPom {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][int]$Timeout,
        [Parameter(Mandatory = $true)][bool]$Required
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $Timeout -UseBasicParsing -MaximumRedirection 8
        if ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300) {
            Write-Host "[OK] $Name ($($response.StatusCode))" -ForegroundColor Green
            return $true
        }
        Write-Host "[FAIL] $Name (HTTP $($response.StatusCode))" -ForegroundColor Red
        return (-not $Required)
    } catch {
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        $detail = if ($status) { "HTTP $status" } else { $_.Exception.Message }
        $prefix = if ($Required) { '[FAIL]' } else { '[INFO]' }
        $color = if ($Required) { 'Red' } else { 'Yellow' }
        Write-Host "$prefix $Name ($detail)" -ForegroundColor $color
        return (-not $Required)
    }
}

Write-Host "Checking Android Gradle Plugin $agpVersion repository access..." -ForegroundColor Cyan
$mirror = [Environment]::GetEnvironmentVariable('AMITAR_GOOGLE_MAVEN_MIRROR')
if (-not [string]::IsNullOrWhiteSpace($mirror) -and
    -not $mirror.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host '[FAIL] AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS.' -ForegroundColor Red
    exit 2
}
$officialModulePassed = $false
foreach ($artifact in $artifacts) {
    $url = "$officialBase/$($artifact.RelativePath)"
    $ok = Test-MavenPom -Name $artifact.Name -Url $url -Timeout $TimeoutSeconds -Required $artifact.Required
    if ($artifact.Required) { $officialModulePassed = $ok }
}

$repositoryPassed = $officialModulePassed
if (-not $officialModulePassed -and -not [string]::IsNullOrWhiteSpace($mirror)) {
    if (-not $mirror.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host '[FAIL] AMITAR_GOOGLE_MAVEN_MIRROR must use HTTPS.' -ForegroundColor Red
        exit 2
    }
    $mirrorBase = $mirror.TrimEnd('/')
    $mirrorUrl = "$mirrorBase/com/android/tools/build/gradle/$agpVersion/gradle-$agpVersion.pom"
    $repositoryPassed = Test-MavenPom -Name 'Configured trusted mirror: AGP implementation POM' -Url $mirrorUrl -Timeout $TimeoutSeconds -Required $true
}

if (-not $repositoryPassed) {
    Write-Host ''
    Write-Host 'The AGP implementation artifact is not reachable from this Windows environment.' -ForegroundColor Red
    Write-Host 'Check DNS, firewall, TLS inspection, proxy settings, and access to dl.google.com.'
    Write-Host 'If your organization provides a trusted HTTPS Google Maven mirror, set AMITAR_GOOGLE_MAVEN_MIRROR before running Gradle.'
    Write-Host 'Do not switch to an untrusted repository or downgrade/upgrade AGP just to hide a repository outage.'
    exit 1
}

Write-Host ''
Write-Host 'The AGP implementation POM is reachable. The project settings map com.android.application directly to com.android.tools.build:gradle.' -ForegroundColor Green
Write-Host 'Refresh Gradle metadata once, then run the app:'
Write-Host '  cd android'
Write-Host '  .\gradlew.bat --stop'
Write-Host '  .\gradlew.bat --refresh-dependencies :app:assembleDebug'
Write-Host '  cd ..'
Write-Host '  flutter run -t lib/AmitarGalleryPlayer.dart'
exit 0

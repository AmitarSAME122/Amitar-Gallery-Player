$ErrorActionPreference = 'Stop'

function Invoke-GitChecked {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($repoRoot -join ''))) {
    throw 'Run this script from inside your Amitar-Gallery-Player Git repository.'
}
$repoRoot = ($repoRoot | Select-Object -First 1).Trim()
Push-Location $repoRoot
try {
    $localProperties = 'android/local.properties'
    $localPropertiesFullPath = Join-Path $repoRoot $localProperties
    $localPropertiesExisted = Test-Path -LiteralPath $localPropertiesFullPath

    # The ignore rule already exists. This checks the rule itself, not just file presence.
    & git check-ignore --quiet --no-index -- $localProperties
    if ($LASTEXITCODE -ne 0) {
        throw '.gitignore does not currently ignore android/local.properties; refusing to continue.'
    }

    # The CI failure is caused by this file still being in the Git index.
    # --cached removes only the index entry and deliberately keeps the local file on disk.
    & git ls-files --error-unmatch -- $localProperties *> $null
    $trackedExit = $LASTEXITCODE
    if ($trackedExit -eq 0) {
        Invoke-GitChecked @('rm', '--cached', '--ignore-unmatch', '--', $localProperties)
        Write-Host 'Removed android/local.properties from the Git index; the local file is preserved.' -ForegroundColor Green
    } elseif ($trackedExit -ne 1) {
        throw "Could not inspect Git tracking state for $localProperties."
    } else {
        Write-Host 'android/local.properties is already untracked.' -ForegroundColor Green
    }

    if ($localPropertiesExisted -and -not (Test-Path -LiteralPath $localPropertiesFullPath)) {
        throw 'The local Android properties file unexpectedly disappeared; stopping.'
    }

    # If a local Flutter run changed .metadata, keep a backup before restoring
    # the repository-managed version that the source checksum manifest expects.
    & git diff --quiet -- .metadata
    $metadataDiffExit = $LASTEXITCODE
    if ($metadataDiffExit -eq 1) {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("AmitarGalleryPlayer-metadata-{0}.bak" -f [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $repoRoot '.metadata') -Destination $backupPath -Force
        Invoke-GitChecked @('restore', '--source=HEAD', '--worktree', '--', '.metadata')
        Write-Host "Restored tracked .metadata. A backup of the local version is at: $backupPath" -ForegroundColor Yellow
    } elseif ($metadataDiffExit -ne 0) {
        throw 'Could not inspect .metadata working-tree state.'
    }

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pythonLauncher) {
        & py -3 tool/update_source_checksums.py
    } else {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if ($null -eq $pythonCommand) {
            throw 'Python 3 was not found. Install Python 3 or the Windows Python launcher, then rerun this script.'
        }
        & python tool/update_source_checksums.py
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not regenerate SHA256SUMS.txt.'
    }

    Invoke-GitChecked @('add', '--', '.github/workflows/build.yml', 'tool/bootstrap_platforms.py', 'tool/test_bootstrap_platforms.py', 'tool/test_project_invariants.py', 'SHA256SUMS.txt')
    Invoke-GitChecked @('diff', '--cached', '--check')

    Write-Host ''
    Write-Host 'Staged CI fix summary:' -ForegroundColor Green
    & git status --short
    if ($LASTEXITCODE -ne 0) { throw 'Could not display Git status.' }
    Write-Host ''
    Write-Host 'Review the staged changes, then commit and push them. The script did not create a commit.' -ForegroundColor Cyan
} finally {
    Pop-Location
}

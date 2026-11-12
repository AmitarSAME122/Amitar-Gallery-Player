$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($repoRoot -join ''))) {
    throw 'Run this script from inside the Amitar-Gallery-Player Git repository.'
}
$repoRoot = ($repoRoot | Select-Object -First 1).Trim()
Push-Location $repoRoot
try {
    foreach ($required in @(
        'tool/update_source_checksums.py',
        'tool/test_project_invariants.py',
        'tool/requirements-branding.txt',
        'SHA256SUMS.txt'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $required) -PathType Leaf)) {
            throw "Required project file is missing: $required. Extract the overlay ZIP at the repository root first."
        }
    }

    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pythonLauncher) {
        $pythonExe = $pythonLauncher.Source
        $pythonPrefix = @('-3')
    } else {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if ($null -eq $pythonCommand) {
            throw 'Python 3 was not found. Install Python 3, then rerun this script.'
        }
        $pythonExe = $pythonCommand.Source
        $pythonPrefix = @()
    }

    # The full Python regression suite imports Pillow/NumPy/ReportLab for branding checks.
    # Install the repository-declared tooling dependencies before running it.
    Invoke-Checked $pythonExe ($pythonPrefix + @('-m', 'pip', 'install', '-r', 'tool/requirements-branding.txt'))

    # Rebuild the manifest from tracked files using one canonical LF policy.
    Invoke-Checked $pythonExe ($pythonPrefix + @('tool/update_source_checksums.py'))

    # Validate syntax and the full regression suite before staging anything.
    Invoke-Checked $pythonExe ($pythonPrefix + @('-m', 'py_compile', 'tool/update_source_checksums.py', 'tool/test_project_invariants.py'))
    Invoke-Checked $pythonExe ($pythonPrefix + @('-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_*.py', '-v'))
    Invoke-Checked $pythonExe ($pythonPrefix + @('tool/check_release_version.py'))

    Invoke-Checked 'git' @('add', '--', 'tool/update_source_checksums.py', 'tool/test_project_invariants.py', 'SHA256SUMS.txt')
    Invoke-Checked 'git' @('diff', '--cached', '--check')

    Write-Host ''
    Write-Host 'Checksum normalization fix is validated and staged.' -ForegroundColor Green
    git status --short
    if ($LASTEXITCODE -ne 0) { throw 'Could not display Git status.' }
    Write-Host ''
    Write-Host 'Review the staged changes, then commit and push them. This script does not commit or push automatically.' -ForegroundColor Cyan
} finally {
    Pop-Location
}

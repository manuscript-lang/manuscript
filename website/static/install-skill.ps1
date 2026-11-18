# Installs the Manuscript agent skill without the compiler, on Windows.
#
#   irm https://manuscript-lang.github.io/manuscript/install-skill.ps1 | iex
#
# It downloads manuscript-skill.tar.gz from a release, checks its SHA-256 and unpacks the
# `manuscript` folder into each parent directory in $env:MS_SKILL_DIRS, separated by `;`
# (default: .claude\skills and .agents\skills). An existing `manuscript` folder is never
# overwritten. Settings, all optional:
#   $env:MS_VERSION      a release such as 2026.11.0 (default: the latest release)
#   $env:MS_SKILL_DIRS   parent directories, separated by ;
#   $env:MS_RELEASE_URL  a directory URL that holds the archive (default: GitHub releases)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = 'manuscript-lang/manuscript'
$version = if ($env:MS_VERSION) { $env:MS_VERSION.TrimStart('v') } else { 'latest' }
$parents = if ($env:MS_SKILL_DIRS) { $env:MS_SKILL_DIRS -split ';' } else { @('.claude\skills', '.agents\skills') }

if ($env:MS_RELEASE_URL) { $base = $env:MS_RELEASE_URL }
elseif ($version -eq 'latest') { $base = "https://github.com/$repo/releases/latest/download" }
else { $base = "https://github.com/$repo/releases/download/v$version" }

$name = 'manuscript-skill'
$work = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Invoke-WebRequest "$base/$name.tar.gz" -OutFile "$work\$name.tar.gz"
    Invoke-WebRequest "$base/$name.tar.gz.sha256" -OutFile "$work\$name.tar.gz.sha256"

    $expected = ((Get-Content "$work\$name.tar.gz.sha256" -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash "$work\$name.tar.gz" -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "install-skill: checksum mismatch: expected $expected, got $actual" }

    # tar.exe ships with Windows 10 and later. Unpack from inside the folder with relative names:
    # GNU tar (Git for Windows) reads a drive letter such as C: as a remote host.
    Push-Location $work
    try { tar -xzf "$name.tar.gz" } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw 'install-skill: tar failed to unpack the archive' }
    if (-not (Test-Path "$work\manuscript\SKILL.md")) { throw 'install-skill: the archive has no manuscript\SKILL.md' }

    foreach ($parent in $parents) {
        if (Test-Path "$parent\manuscript") {
            throw "install-skill: $parent\manuscript exists; existing skill files are never overwritten; remove it or choose another directory"
        }
    }
    foreach ($parent in $parents) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item "$work\manuscript" "$parent\manuscript" -Recurse
        Write-Host "Wrote the Manuscript agent skill to $parent\manuscript"
    }
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

param(
    [string]$BuildId = "",
    [string]$Channel = "dev",
    [string]$CommitSha = "",
    [switch]$Reset
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$metadataPath = Join-Path $project "build_metadata.json"

if ($Reset) {
    Remove-Item -LiteralPath $metadataPath -Force -ErrorAction SilentlyContinue
    Write-Output "[BUILD] Removed generated build metadata; local builds use 'dev'."
    exit 0
}

if ($CommitSha -eq "") {
    Push-Location $project
    try {
        $CommitSha = (& git rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "git rev-parse HEAD failed."
        }
    }
    finally {
        Pop-Location
    }
}

if ($CommitSha -notmatch "^[0-9a-fA-F]{7,64}$") {
    throw "CommitSha must contain 7-64 hexadecimal characters."
}
if ($Channel -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$") {
    throw "Channel must use only letters, digits, dots, underscores, or hyphens."
}
if ($BuildId -eq "") {
    $BuildId = "$Channel-$($CommitSha.Substring(0, 7).ToLowerInvariant())"
}
if ($BuildId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
    throw "BuildId must be 1-64 characters using only letters, digits, dots, underscores, or hyphens."
}

$metadata = [ordered]@{
    build_id = $BuildId
    commit_sha = $CommitSha.ToLowerInvariant()
}
$json = $metadata | ConvertTo-Json -Compress
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($metadataPath, $json + [Environment]::NewLine, $utf8NoBom)
Write-Output "[BUILD] Stamped $BuildId ($CommitSha) -> $metadataPath"

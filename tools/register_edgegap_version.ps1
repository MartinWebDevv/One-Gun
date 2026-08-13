param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationName,

    [Parameter(Mandatory = $true)]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [string]$DockerImage,

    [Parameter(Mandatory = $true)]
    [string]$DockerTag,

    [string]$DockerRepository = "ghcr.io",
    [int]$CpuUnits = 512,
    [int]$MemoryMb = 1024,
    [int]$MaxDurationMinutes = 60,
    [int]$TimeToDeploySeconds = 300,
    [int]$GamePort = 24545
)

$ErrorActionPreference = "Stop"

$apiToken = $env:EDGEGAP_API_TOKEN
$registryUsername = $env:EDGEGAP_GHCR_USERNAME
$registryToken = $env:EDGEGAP_GHCR_TOKEN

if ([string]::IsNullOrWhiteSpace($apiToken)) {
    throw "EDGEGAP_API_TOKEN is required. Store it as a GitHub Actions repository secret."
}
if ([string]::IsNullOrWhiteSpace($registryUsername)) {
    throw "EDGEGAP_GHCR_USERNAME is required."
}
if ([string]::IsNullOrWhiteSpace($registryToken)) {
    throw "EDGEGAP_GHCR_TOKEN is required. Store a read:packages token as a GitHub Actions repository secret."
}
if ($ApplicationName -notmatch "^[a-z0-9][a-z0-9-]{0,63}$") {
    throw "ApplicationName must use lowercase letters, digits, and dashes."
}
if ($VersionName -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
    throw "VersionName must be 1-64 tag-safe characters."
}
if ($DockerImage -notmatch "^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)+$") {
    throw "DockerImage must be a lowercase namespace/image path without the registry or tag."
}
if ($DockerTag -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$") {
    throw "DockerTag is not a valid immutable container tag."
}
if ($CpuUnits -lt 100 -or $MemoryMb -lt 100 -or $MemoryMb -gt (2 * $CpuUnits)) {
    throw "Edgegap resources are invalid: memory must be at least 100 MB and at most twice the CPU units."
}
if ($GamePort -lt 1 -or $GamePort -gt 65535) {
    throw "GamePort must be between 1 and 65535."
}

$escapedApp = [Uri]::EscapeDataString($ApplicationName)
$escapedVersion = [Uri]::EscapeDataString($VersionName)
$versionUri = "https://api.edgegap.com/v1/app/$escapedApp/version/$escapedVersion"
$versionsUri = "https://api.edgegap.com/v1/app/$escapedApp/version"
$headers = @{
    Authorization = "token $apiToken"
    Accept = "application/json"
}

$payload = [ordered]@{
    name = $VersionName
    is_active = $true
    docker_repository = $DockerRepository
    docker_image = $DockerImage
    docker_tag = $DockerTag
    private_username = $registryUsername
    private_token = $registryToken
    req_cpu = $CpuUnits
    req_memory = $MemoryMb
    max_duration = $MaxDurationMinutes
    force_cache = $false
    time_to_deploy = $TimeToDeploySeconds
    ports = @(
        [ordered]@{
            port = $GamePort
            protocol = "UDP"
            to_check = $true
            tls_upgrade = $false
            name = "gameport"
        }
    )
    verify_image = $true
    termination_grace_period_seconds = 10
    will_deploy_in_mainland_china = $false
}
$json = $payload | ConvertTo-Json -Depth 8 -Compress

$existing = $null
try {
    $existing = Invoke-RestMethod -Method Get -Uri $versionUri -Headers $headers
}
catch {
    $statusCode = 0
    if ($null -ne $_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -ne 404) {
        throw
    }
}

$requestMethod = "Post"
$requestUri = $versionsUri
if ($null -ne $existing) {
    if (
        $existing.docker_repository -eq $DockerRepository -and
        $existing.docker_image -eq $DockerImage -and
        $existing.docker_tag -eq $DockerTag
    ) {
        Write-Output ("[EDGEGAP] Version '{0}/{1}' already references {2}/{3}:{4}." -f $ApplicationName, $VersionName, $DockerRepository, $DockerImage, $DockerTag)
        exit 0
    }
    $requestMethod = "Patch"
    $requestUri = $versionUri
}

Write-Output ("[EDGEGAP] {0} development version '{1}/{2}' -> {3}/{4}:{5}" -f $requestMethod, $ApplicationName, $VersionName, $DockerRepository, $DockerImage, $DockerTag)
$request = @{
    Method = $requestMethod
    Uri = $requestUri
    Headers = $headers
    ContentType = "application/json"
    Body = $json
}
$result = Invoke-RestMethod @request

$version = $result
if ($null -ne $result.version) {
    $version = $result.version
}
if ($version.name -ne $VersionName) {
    throw "Edgegap returned an unexpected application version after $requestMethod."
}

Write-Output "[EDGEGAP] Registered '$ApplicationName/$VersionName' with immutable image tag '$DockerTag'."
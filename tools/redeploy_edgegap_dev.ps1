param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationName,

    [Parameter(Mandatory = $true)]
    [string]$VersionName,

    [Parameter(Mandatory = $true)]
    [string]$BuildId,

    [ValidateSet("Replace", "Stop", "Deploy")]
    [string]$Mode = "Replace",

    [string]$ManagedTag = "onegun-dev-ci",
    [double]$Latitude = 37.5485,
    [double]$Longitude = -121.9886,
    [int]$GamePort = 24545,
    [int]$StopTimeoutSeconds = 180,
    [int]$ReadyTimeoutSeconds = 300,
    [int]$PollSeconds = 5
)

$ErrorActionPreference = "Stop"

$apiToken = $env:EDGEGAP_API_TOKEN
if ([string]::IsNullOrWhiteSpace($apiToken)) {
    throw "EDGEGAP_API_TOKEN is required. Store it as a GitHub Actions repository secret."
}
if ($ApplicationName -notmatch "^[a-z0-9][a-z0-9-]{0,63}$") {
    throw "ApplicationName must use lowercase letters, digits, and dashes."
}
if ($VersionName -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
    throw "VersionName must be 1-64 tag-safe characters."
}
if ($BuildId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$") {
    throw "BuildId must be 1-20 tag-safe characters so Edgegap can use it as a deployment tag."
}
if ($ManagedTag -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$") {
    throw "ManagedTag must be 1-20 tag-safe characters."
}
if ($Latitude -lt -90 -or $Latitude -gt 90) {
    throw "Latitude must be between -90 and 90."
}
if ($Longitude -lt -180 -or $Longitude -gt 180) {
    throw "Longitude must be between -180 and 180."
}
if ($GamePort -lt 1 -or $GamePort -gt 65535) {
    throw "GamePort must be between 1 and 65535."
}
if ($StopTimeoutSeconds -lt 30 -or $ReadyTimeoutSeconds -lt 30 -or $PollSeconds -lt 1) {
    throw "Timeouts must be at least 30 seconds and PollSeconds must be positive."
}

$headers = @{
    Authorization = "token $apiToken"
    Accept = "application/json"
}

function Get-HttpStatusCode {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    if ($null -eq $ErrorRecord.Exception.Response) {
        return 0
    }
    return [int]$ErrorRecord.Exception.Response.StatusCode
}

function Get-DeploymentState {
    param([Parameter(Mandatory = $true)]$Deployment)

    foreach ($propertyName in @("current_status", "status")) {
        $property = $Deployment.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $state = ([string]$property.Value).Trim().ToUpperInvariant()
            $separator = $state.LastIndexOf(".")
            if ($separator -ge 0 -and $separator -lt ($state.Length - 1)) {
                $state = $state.Substring($separator + 1)
            }
            return $state
        }
    }
    return "UNKNOWN"
}

function Get-DeploymentRequestId {
    param([Parameter(Mandatory = $true)]$Deployment)

    foreach ($propertyName in @("request_id", "requestId")) {
        $property = $Deployment.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }
    throw "Edgegap returned a deployment without a request ID."
}

function Test-IsTargetDevelopmentDeployment {
    param([Parameter(Mandatory = $true)]$Status)

    # Edgegap's deployment-list items contain the request ID, but not a trusted
    # application/version identity. Verify that identity from /v1/status before
    # allowing any deployment to be stopped. This intentionally includes manual
    # deployments of the exact development alias so they cannot consume the
    # free tier's only slot and block CI.
    $applicationProperty = $Status.PSObject.Properties["app_name"]
    $versionProperty = $Status.PSObject.Properties["app_version"]
    if ($null -eq $applicationProperty -or $null -eq $versionProperty) {
        return $false
    }

    return (
        [string]$applicationProperty.Value -ceq $ApplicationName -and
        [string]$versionProperty.Value -ceq $VersionName
    )
}

function Get-DeploymentStatus {
    param([Parameter(Mandatory = $true)][string]$RequestId)

    $escapedRequestId = [Uri]::EscapeDataString($RequestId)
    return Invoke-RestMethod -Method Get -Uri "https://api.edgegap.com/v1/status/$escapedRequestId" -Headers $headers
}

function Wait-DeploymentTerminated {
    param([Parameter(Mandatory = $true)][string]$RequestId)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($StopTimeoutSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        try {
            $status = Get-DeploymentStatus -RequestId $RequestId
            $state = Get-DeploymentState -Deployment $status
            Write-Output "[EDGEGAP] Waiting for '$RequestId' to stop; state=$state"
            if ($state -in @("TERMINATED", "STOPPED")) {
                return
            }
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
            if ($statusCode -in @(404, 410)) {
                Write-Output "[EDGEGAP] Deployment '$RequestId' is no longer active."
                return
            }
            throw
        }
        Start-Sleep -Seconds $PollSeconds
    }
    throw "Timed out after $StopTimeoutSeconds seconds waiting for Edgegap deployment '$RequestId' to terminate."
}

function Find-ExternalGamePort {
    param([Parameter(Mandatory = $true)]$Deployment)

    $portsProperty = $Deployment.PSObject.Properties["ports"]
    if ($null -eq $portsProperty -or $null -eq $portsProperty.Value) {
        return $null
    }

    $ports = $portsProperty.Value
    if ($ports -is [System.Collections.IDictionary]) {
        $candidates = @($ports.Values)
    }
    elseif ($ports -is [System.Array]) {
        $candidates = @($ports)
    }
    else {
        $namedGamePort = $ports.PSObject.Properties["gameport"]
        if ($null -ne $namedGamePort) {
            $candidates = @($namedGamePort.Value)
        }
        else {
            $candidates = @($ports.PSObject.Properties | ForEach-Object { $_.Value })
        }
    }

    foreach ($candidate in $candidates) {
        if ($null -eq $candidate) {
            continue
        }
        $internal = $candidate.PSObject.Properties["internal"]
        $name = $candidate.PSObject.Properties["name"]
        $protocol = $candidate.PSObject.Properties["protocol"]
        $matchesPort = $null -ne $internal -and [int]$internal.Value -eq $GamePort
        $matchesName = $null -ne $name -and [string]$name.Value -eq "gameport"
        $matchesProtocol = $null -eq $protocol -or [string]$protocol.Value -eq "UDP"
        if (($matchesPort -or $matchesName) -and $matchesProtocol) {
            $external = $candidate.PSObject.Properties["external"]
            if ($null -ne $external) {
                return [int]$external.Value
            }
        }
    }
    return $null
}

if ($Mode -ne "Deploy") {
    $query = [ordered]@{
        filters = @(
            [ordered]@{ field = "application"; operator = "eq"; value = $ApplicationName }
            [ordered]@{ field = "version"; operator = "eq"; value = $VersionName }
        )
        order_by = @(
            [ordered]@{ field = "created_at"; order = "desc" }
        )
    }
    $queryJson = $query | ConvertTo-Json -Depth 6 -Compress
    $listUri = "https://api.edgegap.com/v1/deployments?query=$([Uri]::EscapeDataString($queryJson))"
    $listResult = Invoke-RestMethod -Method Get -Uri $listUri -Headers $headers

    $dataProperty = $listResult.PSObject.Properties["data"]
    if ($null -eq $dataProperty) {
        throw "Edgegap deployment-list response did not contain 'data'; refusing to stop any deployment."
    }
    $developmentDeployments = @($dataProperty.Value)
    Write-Output "[EDGEGAP] Found $($developmentDeployments.Count) candidate deployment(s) for exact development target '$ApplicationName/$VersionName'."

    foreach ($deployment in $developmentDeployments) {
        $requestId = Get-DeploymentRequestId -Deployment $deployment
        try {
            $status = Get-DeploymentStatus -RequestId $requestId
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
            if ($statusCode -in @(404, 410)) {
                Write-Output "[EDGEGAP] Candidate deployment '$requestId' is no longer active."
                continue
            }
            throw
        }

        if (-not (Test-IsTargetDevelopmentDeployment -Status $status)) {
            Write-Warning "Skipping deployment '$requestId' because its returned identity did not exactly match development target '$ApplicationName/$VersionName'."
            continue
        }
        $state = Get-DeploymentState -Deployment $status
        if ($state -in @("TERMINATED", "STOPPED")) {
            continue
        }

        Write-Output "[EDGEGAP] Stopping development deployment '$requestId' (state=$state)."
        $escapedRequestId = [Uri]::EscapeDataString($requestId)
        try {
            Invoke-RestMethod -Method Delete -Uri "https://api.edgegap.com/v1/stop/$escapedRequestId" -Headers $headers | Out-Null
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
            if ($statusCode -notin @(404, 410)) {
                throw
            }
        }
        Wait-DeploymentTerminated -RequestId $requestId
    }
}

if ($Mode -eq "Stop") {
    Write-Output "[EDGEGAP] Development deployments for '$ApplicationName/$VersionName' are stopped."
    exit 0
}
$deployPayload = [ordered]@{
    application = $ApplicationName
    version = $VersionName
    require_cached_locations = $false
    users = @(
        [ordered]@{
            user_type = "geo_coordinates"
            user_data = [ordered]@{
                latitude = $Latitude
                longitude = $Longitude
            }
        }
    )
    tags = @($ManagedTag, $BuildId)
}
$deployJson = $deployPayload | ConvertTo-Json -Depth 8 -Compress
Write-Output "[EDGEGAP] Deploying '$ApplicationName/$VersionName' for build '$BuildId'."
$created = Invoke-RestMethod -Method Post -Uri "https://api.edgegap.com/v2/deployments" -Headers $headers -ContentType "application/json" -Body $deployJson
$newRequestId = Get-DeploymentRequestId -Deployment $created
Write-Output "[EDGEGAP] Deployment request accepted: $newRequestId"

$readyDeployment = $null
$readyDeadline = [DateTimeOffset]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
while ([DateTimeOffset]::UtcNow -lt $readyDeadline) {
    Start-Sleep -Seconds $PollSeconds
    $status = Get-DeploymentStatus -RequestId $newRequestId
    $state = Get-DeploymentState -Deployment $status
    Write-Output "[EDGEGAP] Deployment '$newRequestId' state=$state"
    if ($state -eq "READY") {
        $readyDeployment = $status
        break
    }
    if ($state -in @("ERROR", "TERMINATED", "STOPPED")) {
        $details = $status | ConvertTo-Json -Depth 8 -Compress
        throw "Edgegap deployment '$newRequestId' entered terminal state '$state': $details"
    }
}
if ($null -eq $readyDeployment) {
    throw "Timed out after $ReadyTimeoutSeconds seconds waiting for Edgegap deployment '$newRequestId' to become READY."
}

$fqdnProperty = $readyDeployment.PSObject.Properties["fqdn"]
if ($null -eq $fqdnProperty -or [string]::IsNullOrWhiteSpace([string]$fqdnProperty.Value)) {
    throw "Edgegap deployment '$newRequestId' is READY but did not return an FQDN."
}
$fqdn = [string]$fqdnProperty.Value
$externalPort = Find-ExternalGamePort -Deployment $readyDeployment
if ($null -eq $externalPort) {
    throw "Edgegap deployment '$newRequestId' is READY but did not return the external UDP mapping for internal port $GamePort."
}
$endpoint = "${fqdn}:$externalPort"

Write-Output "[EDGEGAP] READY: $endpoint"
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "request_id=$newRequestId"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "fqdn=$fqdn"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "external_port=$externalPort"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "endpoint=$endpoint"
}

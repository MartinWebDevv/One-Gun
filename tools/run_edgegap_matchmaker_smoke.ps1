param(
    [Parameter(Mandatory = $true)]
    [string]$ApiUrl,

    [string]$Profile = "simple-example",
    [int]$TicketCount = 2,
    [int]$GamePort = 24545,
    [int]$ReadyTimeoutSeconds = 300,
    [int]$PollSeconds = 3,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

if ($ApiUrl -notmatch "^https://[A-Za-z0-9.-]+$") {
    throw "ApiUrl must be an HTTPS origin without a path."
}
$ApiUrl = $ApiUrl.TrimEnd("/")
if ($Profile -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") {
    throw "Profile must be 1-64 identifier-safe characters."
}
if ($TicketCount -lt 1 -or $TicketCount -gt 10) {
    throw "TicketCount must be between 1 and 10."
}
if ($GamePort -lt 1 -or $GamePort -gt 65535) {
    throw "GamePort must be between 1 and 65535."
}
if ($ReadyTimeoutSeconds -lt 30 -or $PollSeconds -lt 1) {
    throw "ReadyTimeoutSeconds must be at least 30 and PollSeconds must be positive."
}

function New-TicketPayload {
    return [ordered]@{
        player_ip = $null
        profile = $Profile
        attributes = [ordered]@{
            beacons = [ordered]@{
                Montreal = 12.3
                Toronto = 45.6
                Quebec = 78.9
            }
        }
    }
}

function Get-AssignmentEndpoint {
    param([Parameter(Mandatory = $true)]$Ticket)

    $assignment = $Ticket.PSObject.Properties["assignment"]
    if ($null -eq $assignment -or $null -eq $assignment.Value) {
        throw "HOST_ASSIGNED ticket '$($Ticket.id)' did not include an assignment."
    }
    $fqdnProperty = $assignment.Value.PSObject.Properties["fqdn"]
    if ($null -eq $fqdnProperty -or [string]::IsNullOrWhiteSpace([string]$fqdnProperty.Value)) {
        throw "Ticket '$($Ticket.id)' assignment did not include an FQDN."
    }
    $portsProperty = $assignment.Value.PSObject.Properties["ports"]
    if ($null -eq $portsProperty -or $null -eq $portsProperty.Value) {
        throw "Ticket '$($Ticket.id)' assignment did not include ports."
    }

    $candidate = $null
    $named = $portsProperty.Value.PSObject.Properties["gameport"]
    if ($null -ne $named) {
        $candidate = $named.Value
    }
    else {
        foreach ($portProperty in $portsProperty.Value.PSObject.Properties) {
            $port = $portProperty.Value
            $internal = $port.PSObject.Properties["internal"]
            $protocol = $port.PSObject.Properties["protocol"]
            if ($null -ne $internal -and [int]$internal.Value -eq $GamePort -and
                    ($null -eq $protocol -or [string]$protocol.Value -eq "UDP")) {
                $candidate = $port
                break
            }
        }
    }
    if ($null -eq $candidate) {
        throw "Ticket '$($Ticket.id)' assignment did not include gameport/internal UDP $GamePort."
    }

    $internalProperty = $candidate.PSObject.Properties["internal"]
    $externalProperty = $candidate.PSObject.Properties["external"]
    $protocolProperty = $candidate.PSObject.Properties["protocol"]
    if ($null -eq $internalProperty -or [int]$internalProperty.Value -ne $GamePort) {
        throw "Assigned gameport internal port does not equal $GamePort."
    }
    if ($null -eq $externalProperty -or [int]$externalProperty.Value -lt 1 -or
            [int]$externalProperty.Value -gt 65535) {
        throw "Assigned gameport has an invalid external port."
    }
    if ($null -eq $protocolProperty -or [string]$protocolProperty.Value -ne "UDP") {
        throw "Assigned gameport is not UDP."
    }

    return [ordered]@{
        fqdn = [string]$fqdnProperty.Value
        external_port = [int]$externalProperty.Value
        internal_port = [int]$internalProperty.Value
        protocol = [string]$protocolProperty.Value
        address = "$($fqdnProperty.Value):$($externalProperty.Value)"
    }
}

if ($ValidateOnly) {
    $payload = New-TicketPayload
    $payloadJson = $payload | ConvertTo-Json -Depth 8 -Compress
    if ($payloadJson -match "(?i)edgegap.*token|authorization|password|secret") {
        throw "Ticket payload unexpectedly contains credential-like data."
    }
    $sampleTicket = [pscustomobject]@{
        id = "validation-ticket"
        status = "HOST_ASSIGNED"
        assignment = [pscustomobject]@{
            fqdn = "validation.pr.edgegap.net"
            ports = [pscustomobject]@{
                gameport = [pscustomobject]@{
                    internal = $GamePort
                    external = 30937
                    protocol = "UDP"
                }
            }
        }
    }
    $sampleEndpoint = Get-AssignmentEndpoint -Ticket $sampleTicket
    if ($sampleEndpoint.address -ne "validation.pr.edgegap.net:30937") {
        throw "Assignment endpoint validation failed."
    }
    Write-Output "EDGEGAP MATCHMAKER CONTRACT: PASS"
    exit 0
}

$authToken = $env:ONEGUN_MATCHMAKER_TOKEN
if ([string]::IsNullOrWhiteSpace($authToken)) {
    throw "ONEGUN_MATCHMAKER_TOKEN is required. Set it only in the current shell and remove it after the test."
}

$headers = @{
    Authorization = $authToken
    Accept = "application/json"
}
$ticketIds = [System.Collections.Generic.List[string]]::new()
$succeeded = $false

function Remove-PendingTickets {
    foreach ($ticketId in $ticketIds) {
        try {
            $escaped = [Uri]::EscapeDataString($ticketId)
            Invoke-RestMethod -Method Delete -Uri "$ApiUrl/tickets/$escaped" -Headers $headers | Out-Null
            Write-Output "[MATCHMAKER] Cancelled ticket $ticketId"
        }
        catch {
            Write-Warning "Could not cancel ticket '$ticketId': $($_.Exception.Message)"
        }
    }
}

try {
    $monitor = Invoke-RestMethod -Method Get -Uri "$ApiUrl/monitor" -Headers $headers
    Write-Output "[MATCHMAKER] API is responding at $ApiUrl"

    $payloadJson = (New-TicketPayload) | ConvertTo-Json -Depth 8 -Compress
    for ($index = 1; $index -le $TicketCount; $index++) {
        $ticket = Invoke-RestMethod -Method Post -Uri "$ApiUrl/tickets" -Headers $headers `
            -ContentType "application/json" -Body $payloadJson
        if ([string]::IsNullOrWhiteSpace([string]$ticket.id)) {
            throw "Matchmaker created ticket $index without an ID."
        }
        $ticketIds.Add([string]$ticket.id)
        Write-Output "[MATCHMAKER] Created ticket $index/${TicketCount}: $($ticket.id)"
    }

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($ReadyTimeoutSeconds)
    $lastStates = @{}
    $readyTickets = @{}
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        foreach ($ticketId in $ticketIds) {
            if ($readyTickets.ContainsKey($ticketId)) {
                continue
            }
            $escaped = [Uri]::EscapeDataString($ticketId)
            $ticket = Invoke-RestMethod -Method Get -Uri "$ApiUrl/tickets/$escaped" -Headers $headers
            $state = ([string]$ticket.status).Trim().ToUpperInvariant()
            if ($lastStates[$ticketId] -ne $state) {
                Write-Output "[MATCHMAKER] Ticket $ticketId state=$state"
                $lastStates[$ticketId] = $state
            }
            if ($state -eq "HOST_ASSIGNED") {
                $readyTickets[$ticketId] = $ticket
            }
            elseif ($state -eq "CANCELLED") {
                throw "Matchmaker cancelled ticket '$ticketId'."
            }
        }
        if ($readyTickets.Count -eq $ticketIds.Count) {
            break
        }
        Start-Sleep -Seconds $PollSeconds
    }
    if ($readyTickets.Count -ne $ticketIds.Count) {
        throw "Timed out after $ReadyTimeoutSeconds seconds; $($readyTickets.Count)/$TicketCount tickets reached HOST_ASSIGNED."
    }

    $expectedAddress = ""
    foreach ($ticketId in $ticketIds) {
        $endpoint = Get-AssignmentEndpoint -Ticket $readyTickets[$ticketId]
        if ($expectedAddress -eq "") {
            $expectedAddress = $endpoint.address
        }
        elseif ($endpoint.address -ne $expectedAddress) {
            throw "Matched tickets received different endpoints: '$expectedAddress' and '$($endpoint.address)'."
        }
    }

    $succeeded = $true
    Write-Output "[MATCHMAKER] HOST_ASSIGNED: $expectedAddress"
    Write-Output "[MATCHMAKER] Internal game port: $GamePort/UDP"
    Write-Output "EDGEGAP MATCHMAKER SMOKE: PASS"
}
finally {
    if (-not $succeeded -and $ticketIds.Count -gt 0) {
        Remove-PendingTickets
    }
}

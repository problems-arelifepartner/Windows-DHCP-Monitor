<#
Module: DhcpMonitor
Provides functions:
 - Load-DhcpMonitorConfig
 - Get-DhcpScopes
 - Get-DhcpScopeLeaseCount
 - Evaluate-ScopeAgainstMax
 - Send-DhcpAlert
 - Load/Save-MonitorState
#>

function Load-DhcpMonitorConfig {
    param(
        [string] $Path
    )
    if (-not (Test-Path $Path)) { throw "Config file not found: $Path" }
    $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
    return $json
}

function Get-DhcpScopes {
    param(
        [string] $Server = $env:COMPUTERNAME
    )
    # Returns objects with ScopeId (string) and Name
    Import-Module DhcpServer -ErrorAction Stop
    # Prefer newer statistics cmdlet if available
    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $Server -ErrorAction Stop
    } catch {
        throw "Failed to enumerate DHCP scopes on $Server: $_"
    }
    return $scopes | Select-Object @{Name='ScopeId';Expression={$_.ScopeId}}, Name
}

function Get-DhcpScopeLeaseCount {
    param(
        [string] $ScopeId,
        [string] $Server = $env:COMPUTERNAME
    )
    Import-Module DhcpServer -ErrorAction Stop
    try {
        # Use the lease cmdlet; fall back to statistics where available
        if (Get-Command Get-DhcpServerv4Lease -ErrorAction SilentlyContinue) {
            $leases = Get-DhcpServerv4Lease -ScopeId $ScopeId -ComputerName $Server -ErrorAction Stop
            return ($leases | Measure-Object).Count
        } elseif (Get-Command Get-DhcpServerv4ScopeStatistics -ErrorAction SilentlyContinue) {
            $stat = Get-DhcpServerv4ScopeStatistics -ScopeId $ScopeId -ComputerName $Server -ErrorAction Stop
            return [int]$stat.InUse
        } else {
            throw "No DHCP lease/statistics cmdlet available on this host."
        }
    } catch {
        Write-Warning "Failed to read leases for scope $ScopeId: $_"
        return 0
    }
}

function Evaluate-ScopeAgainstMax {
    param(
        [string] $ScopeId,
        [int] $Count,
        [pscustomobject] $Config
    )
    # Attempt to match PerScope keys exactly or by CIDR/ScopeId formatting
    $perScopeValue = $null
    if ($Config.PerScope) {
        foreach ($prop in $Config.PerScope.PSObject.Properties) {
            if ($prop.Name -eq $ScopeId -or $prop.Name -like "*$ScopeId*" -or $ScopeId -like "*$($prop.Name)*") {
                $perScopeValue = [int]$prop.Value
                break
            }
        }
    }
    $max = if ($perScopeValue) { $perScopeValue } else { [int]$Config.GlobalMaxLeases }
    return [pscustomobject]@{
        ScopeId = $ScopeId
        Count = $Count
        Max = $max
        IsBreach = ($Count -gt $max)
    }
}

function Load-MonitorState {
    param(
        [string] $Path
    )
    if (-not (Test-Path $Path)) { return @{} }
    try {
        return Get-Content -Raw -Path $Path | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to load state from $Path: $_"
        return @{}
    }
}

function Save-MonitorState {
    param(
        [string] $Path,
        [psobject] $State
    )
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Force
}

function Send-DhcpAlert {
    param(
        [pscustomobject] $ScopeEvaluation,
        [pscustomobject] $Config,
        [switch] $Recovered
    )

    $payloadObj = [ordered]@{
        scope = $ScopeEvaluation.ScopeId
        count = $ScopeEvaluation.Count
        max = $ScopeEvaluation.Max
        when = (Get-Date).ToString("o")
        status = if ($Recovered) { 'recovered' } else { 'breach' }
    }
    $payload = $payloadObj | ConvertTo-Json

    if ($Config.Alerting.Webhook.Enabled -and $Config.Alerting.Webhook.Url) {
        try {
            $headers = @{}
            if ($Config.Alerting.Webhook.Headers) {
                foreach ($h in $Config.Alerting.Webhook.Headers.PSObject.Properties) {
                    $headers[$h.Name] = $h.Value
                }
            }
            Invoke-RestMethod -Uri $Config.Alerting.Webhook.Url -Method Post -Body $payload -ContentType 'application/json' -Headers $headers -ErrorAction Stop
            Write-Host "[Alert] Webhook sent for scope $($ScopeEvaluation.ScopeId) status=$($payloadObj.status)"
        } catch {
            Write-Warning "Webhook alert failed: $_"
        }
    }

    if ($Config.Alerting.Email.Enabled) {
        try {
            $smtp = $Config.Alerting.Email.SmtpServer
            $from = $Config.Alerting.Email.From
            $to = $Config.Alerting.Email.To -join ","
            $subject = if ($Recovered) { "DHCP scope recovered: $($ScopeEvaluation.ScopeId)" } else { "DHCP scope breach: $($ScopeEvaluation.ScopeId) ($($ScopeEvaluation.Count)/$($ScopeEvaluation.Max))" }
            $body = "Scope $($ScopeEvaluation.ScopeId) has $($ScopeEvaluation.Count) leases (maximum $($ScopeEvaluation.Max)). Time: $(Get-Date -Format 'u')`nStatus: $($payloadObj.status)"
            Send-MailMessage -SmtpServer $smtp -From $from -To $to -Subject $subject -Body $body -ErrorAction Stop
            Write-Host "[Alert] Email sent for scope $($ScopeEvaluation.ScopeId)"
        } catch {
            Write-Warning "Email alert failed: $_"
        }
    }
}

Export-ModuleMember -Function Load-DhcpMonitorConfig, Get-DhcpScopes, Get-DhcpScopeLeaseCount, Evaluate-ScopeAgainstMax, Load-MonitorState, Save-MonitorState, Send-DhcpAlert

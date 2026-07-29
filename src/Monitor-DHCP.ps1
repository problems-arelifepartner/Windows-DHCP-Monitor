<#
Main runner script. Example usage:
  - Run once: .\Monitor-DHCP.ps1 -ConfigPath ".\config\dhcp-monitor-config.json"
  - Schedule via Task Scheduler to run every minute.
#>

param(
    [string] $ConfigPath = "$(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..\config\dhcp-monitor-config.json'))",
    [string] $StatePath = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\..\state\dhcp-monitor-state.json",
    [string] $Server = $env:COMPUTERNAME,
    [switch] $NoExitOnError
)

# Normalize paths
try {
    $ConfigPath = (Resolve-Path $ConfigPath -ErrorAction Stop).ProviderPath
} catch {
    Write-Error "Config path not found: $ConfigPath"
    if (-not $NoExitOnError) { exit 1 }
}

if (-not (Test-Path $StatePath)) {
    $stateDir = Split-Path $StatePath -Parent
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    "{}" | Set-Content -Path $StatePath -Force
}

# Ensure module loaded
$modulePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'DhcpMonitor.psm1'
if (-not (Test-Path $modulePath)) {
    Write-Error "Module not found at $modulePath"
    if (-not $NoExitOnError) { exit 2 }
}
Import-Module -Name $modulePath -Force -ErrorAction Stop

$config = Load-DhcpMonitorConfig -Path $ConfigPath

# Prepare state
$state = Load-MonitorState -Path $StatePath
if (-not $state) { $state = @{} }

try {
    $scopes = Get-DhcpScopes -Server $Server
} catch {
    Write-Error "Failed to enumerate scopes on server $Server. Ensure DhcpServer module installed and you have privileges. $_"
    if (-not $NoExitOnError) { exit 2 }
}

foreach ($s in $scopes) {
    $scopeId = $s.ScopeId.ToString()
    $count = Get-DhcpScopeLeaseCount -ScopeId $scopeId -Server $Server
    $eval = Evaluate-ScopeAgainstMax -ScopeId $scopeId -Count $count -Config $config

    # Ensure state entry
    if (-not $state.PSObject.Properties.Name -contains $scopeId) {
        $state | Add-Member -MemberType NoteProperty -Name $scopeId -Value @{ LastAlerted = $null; BreachActive = $false } -Force
    }

    $last = if ($state.$scopeId.LastAlerted) { [datetime]$state.$scopeId.LastAlerted } else { $null }
    $debounceMins = [int]$config.DebounceMinutes
    $now = Get-Date

    if ($eval.IsBreach) {
        $shouldAlert = $false
        if (-not $last) { $shouldAlert = $true } else { $elapsed = ($now - $last).TotalMinutes; if ($elapsed -ge $debounceMins) { $shouldAlert = $true } }
        if ($shouldAlert) {
            Send-DhcpAlert -ScopeEvaluation $eval -Config $config
            $state.$scopeId.LastAlerted = $now.ToString("o")
            $state.$scopeId.BreachActive = $true
        } else {
            Write-Host "Breach detected for $scopeId but debounced (last alerted at $last)."
        }
    } else {
        if ($state.$scopeId.BreachActive) {
            # Send recovery
            Send-DhcpAlert -ScopeEvaluation $eval -Config $config -Recovered
            Write-Host "Scope $scopeId recovered from breach."
            $state.$scopeId.BreachActive = $false
            $state.$scopeId.LastAlerted = $null
        } else {
            Write-Host "Scope $scopeId OK ($count/$($eval.Max))"
        }
    }
}

Save-MonitorState -Path $StatePath -State $state
Write-Host "DHCP monitor run completed at $(Get-Date -Format o)"

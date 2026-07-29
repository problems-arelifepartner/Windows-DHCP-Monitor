<#
.SYNOPSIS
    Monitors Windows Server DHCP scope usage and sends alerts via Webhook.
.DESCRIPTION
    This script queries the local Windows DHCP server for IPv4 scope statistics.
    If any scope's utilization exceeds the defined threshold, it pushes an alert
    to a Slack or Microsoft Teams webhook.
.NOTES
    Author: [Your Name/Team]
    Requires: Windows Server with DHCP Server Role, PowerShell 5.1+
#>

# --- CONFIGURATION ---
$ThresholdPercentage = 90  # Alert if a scope is >= 90% full
$WebhookUrl = "https://hooks.slack.com/services/YOUR/WEBHOOK/HERE"
$ServerName = $env:COMPUTERNAME

# --- SCRIPT LOGIC ---
try {
    $Scopes = Get-DhcpServerv4ScopeStatistics -ComputerName $ServerName -ErrorAction Stop

    foreach ($Scope in $Scopes) {
        $PercentUsed = [math]::Round($Scope.PercentageInUse, 2)

        if ($PercentUsed -ge $ThresholdPercentage) {
            $AlertMessage = "🚨 *DHCP Scope Exhaustion Warning* 🚨`n" +
                            "**Server:** $ServerName`n" +
                            "**Scope ID:** $($Scope.ScopeId)`n" +
                            "**Capacity:** $PercentUsed% In Use`n" +
                            "**Free Addresses:** $($Scope.Free)`n" +
                            "**Total Addresses:** $($Scope.InUse + $Scope.Free)"

            $Payload = @{ text = $AlertMessage } | ConvertTo-Json -Depth 2
            Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $Payload -ContentType "application/json"
            
            Write-Host "Alert sent for Scope $($Scope.ScopeId) ($PercentUsed% full)" -ForegroundColor Yellow
        }
        else {
            Write-Host "Scope $($Scope.ScopeId) is healthy ($PercentUsed% full)." -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "Failed to query DHCP statistics. Run as Administrator." -ForegroundColor Red
    Write-Error $_
}


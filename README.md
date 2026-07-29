# Windows-DHCP-Monitor
Specially created for IT support agents 


# Windows DHCP Scope Monitor

A lightweight PowerShell script designed to run directly on a Windows DHCP Server. It monitors IPv4 scope exhaustion and pushes proactive alerts to Slack or Microsoft Teams when scopes run out of IP addresses.

## Features
* **Zero Dependencies:** Uses native Windows `Get-DhcpServerv4ScopeStatistics` cmdlets.
* **Proactive Alerting:** Catch capacity limits before users lose network access.
* **ChatOps Integration:** Sends formatted JSON payloads to standard webhooks.

## Prerequisites
* Windows Server 2012 R2, 2016, 2019, or 2022.
* DHCP Server Role installed.
* PowerShell 5.1 or higher.
* Administrator privileges (required to read DHCP stats).

## Configuration
1. Open `DHCPScopeMonitor.ps1` in your editor.
2. Update the `$WebhookUrl` with your Slack or Teams Incoming Webhook URL.
3. Adjust the `$ThresholdPercentage` (default is `90`) to your preferred alert level.

## Deployment (Task Scheduler)
To automate this script, configure it to run as a scheduled task:

1. Copy `DHCPScopeMonitor.ps1` to a permanent location (e.g., `C:\Scripts\`).
2. Open **Task Scheduler** and create a new task.
3. Set the security options to **Run whether user is logged on or not** and **Run with highest privileges**.
4. Create a **Trigger** to run the task every 15-60 minutes.
5. Create an **Action**:
   * **Program/script:** `powershell.exe`
   * **Add arguments:** `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\DHCPScopeMonitor.ps1"`
6. Save the task using Admin credentials.

## License
MIT License. Free to use and modify for internal IT operations.

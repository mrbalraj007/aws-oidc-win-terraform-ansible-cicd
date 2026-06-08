<powershell>
# -------------------------------------------------------
# userdata.ps1
# Windows EC2 UserData — runs as SYSTEM during first boot.
# Configures WinRM for Ansible and creates the ansible_admin user.
# Based on a proven working manual script.
# -------------------------------------------------------

$ErrorActionPreference = "Stop"
$logFile = "C:\ProgramData\Amazon\userdata.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp  $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== UserData started ==="

# ---- Parameters passed from Terraform ----
$ansiblePassword = "${ansible_password}"
$adminUser       = "ansible_admin"

Write-Log "ansible_password length: $($ansiblePassword.Length)"
Write-Log "adminUser: $adminUser"

# ---- Create ansible_admin local user ----
Write-Log "Creating local user: $adminUser"
try {
    $existing = Get-LocalUser -Name $adminUser -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        $securePw = ConvertTo-SecureString -String $ansiblePassword -AsPlainText -Force
        New-LocalUser -Name $adminUser -Password $securePw -PasswordNeverExpires -Description "Ansible WinRM access"
        Write-Log "User $adminUser created."
    } else {
        Write-Log "User $adminUser already exists — updating password."
        $securePw = ConvertTo-SecureString -String $ansiblePassword -AsPlainText -Force
        Set-LocalUser -Name $adminUser -Password $securePw -PasswordNeverExpires $true
        Write-Log "User $adminUser password updated."
    }

    Add-LocalGroupMember -Group "Administrators" -Member $adminUser -ErrorAction SilentlyContinue
    Write-Log "User $adminUser added to Administrators."
} catch {
    Write-Log "ERROR creating user: $_"
    # Don't exit — still try to configure WinRM
}

# ---- Configure WinRM (based on proven working script) ----
Write-Log "Configuring WinRM..."

# 1. Enable PSRemoting and set network to Private
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-Log "Enable-PSRemoting completed."
} catch {
    Write-Log "Enable-PSRemoting had issues (continuing): $_"
}
try {
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    Write-Log "Network profile set to Private."
} catch {
    Write-Log "Setting network profile had issues (continuing): $_"
}

# 2. Configure WinRM auth and timeouts
Write-Log "Setting WinRM config values..."
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
if ($LASTEXITCODE -ne 0) { Write-Log "WARNING: MaxTimeoutms failed (non-critical)" }

winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
if ($LASTEXITCODE -ne 0) { Write-Log "WARNING: MaxMemoryPerShellMB failed (non-critical)" }

winrm set winrm/config/service '@{AllowUnencrypted="true"}'
if ($LASTEXITCODE -ne 0) { Write-Log "WARNING: AllowUnencrypted failed" }

winrm set winrm/config/service/auth '@{Basic="true"}'
if ($LASTEXITCODE -ne 0) { Write-Log "WARNING: Basic auth failed" }

# 3. Create self-signed cert and HTTPS listener (optional, but part of the proven script)
try {
    $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
    New-Item -Path WSMan:\Localhost\Listener -Transport HTTPS -Address * -CertificateThumbprint $cert.Thumbprint -Force -ErrorAction SilentlyContinue
    Write-Log "HTTPS listener created with self-signed cert."
} catch {
    Write-Log "HTTPS listener setup had issues (non-critical, HTTP still works): $_"
}

# 4. Windows Firewall rules
try {
    New-NetFirewallRule -DisplayName "WinRM HTTP"  -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -ErrorAction SilentlyContinue
    Write-Log "Firewall rules created."
} catch {
    Write-Log "Firewall rules had issues (continuing): $_"
}

# 5. Restart WinRM service to apply ALL changes
Write-Log "Restarting WinRM service..."
Restart-Service WinRM -Force
Start-Sleep -Seconds 3
$winrmStatus = (Get-Service WinRM).Status
Write-Log "WinRM service status after restart: $winrmStatus"

# 6. Verify
try {
    $listeners = winrm enumerate winrm/config/Listener
    Write-Log "Current WinRM listeners:`n$listeners"
} catch {
    Write-Log "Could not enumerate listeners (continuing)"
}

Write-Log "=== UserData completed successfully ==="
exit 0
</powershell>
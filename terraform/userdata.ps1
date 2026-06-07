# -------------------------------------------------------
# userdata.ps1
# Windows EC2 UserData — runs as SYSTEM during first boot.
# Configures WinRM for Ansible and creates the ansible_admin user.
# -------------------------------------------------------

$ErrorActionPreference = "Stop"
$logFile = "C:\ProgramData\userdata.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp  $Message" | Tee-Object -FilePath $logFile -Append
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
    exit 1
}

# ---- Configure WinRM ----
Write-Log "Configuring WinRM..."

try {
    # Enable the Windows Remote Management service and set startup to Automatic
    Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue

    # Configure WinRM service settings (allow unencrypted + basic auth)
    winrm set winrm/config/service/auth '@{Basic="true"}' 2>$null
    winrm set winrm/config/service '@{AllowUnencrypted="true"}' 2>$null

    # Increase timeouts so Ansible doesn't get kicked off mid-task
    winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}' 2>$null
    winrm set winrm/config/winrm '@{MaxTimeoutms="1800000"}' 2>$null

    # Enable PSRemoting (creates HTTP listener on port 5985)
    # -SkipNetworkProfileCheck: don't require domain profile on first boot
    # -Force: overwrite any existing configuration
    Write-Log "Running Enable-PSRemoting..."
    Enable-PSRemoting -Force -SkipNetworkProfileCheck 2>&1 | Tee-Object -FilePath $logFile -Append

    Write-Log "WinRM configured successfully."
} catch {
    Write-Log "ERROR configuring WinRM: $_"
    exit 1
}

# ---- Open firewall rules for WinRM ----
Write-Log "Configuring Windows Firewall..."
netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985 2>&1 | Tee-Object -FilePath $logFile -Append
netsh advfirewall firewall add rule name="WinRM HTTPS" dir=in action=allow protocol=TCP localport=5986 2>&1 | Tee-Object -FilePath $logFile -Append

# ---- Verify WinRM is listening ----
Write-Log "Verifying WinRM listener..."
Start-Sleep -Seconds 5

$listenerCheck = winrm enumerate winrm/config/listener 2>&1
Write-Log "Current WinRM listeners:`n$listenerCheck"

# Confirm HTTP:5985 is present
$httpListener = $listenerCheck | Select-String "Transport = HTTP" -Quiet
if ($httpListener) {
    Write-Log "HTTP listener on port 5985: OK"
} else {
    Write-Log "WARNING: No HTTP listener found on port 5985"
}

# ---- Done ----
Write-Log "=== UserData completed successfully ==="
exit 0
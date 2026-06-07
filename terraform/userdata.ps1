# -------------------------------------------------------
# userdata.ps1
# Runs at first boot – enables WinRM so Ansible can connect to EC2 instances and configures a local admin user for Ansible use.
# -------------------------------------------------------

# Set the local Ansible admin password
$ansiblePassword = "${ansible_password}"
$adminUser       = "ansible_admin"

# Create a dedicated local user for Ansible
net user $adminUser $ansiblePassword /add
net localgroup Administrators $adminUser /add

# Disable password expiry for this service account
Set-LocalUser -Name $adminUser -PasswordNeverExpires $true

# ---- Configure WinRM ----
# Enable PS remoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Remove any existing HTTPS listener and create a fresh HTTP one
Remove-WSManInstance winrm/config/listener -SelectorSet @{Address="*"; Transport="HTTP"} -ErrorAction SilentlyContinue

# Create HTTP listener (Ansible default; HTTPS requires cert setup)
New-WSManInstance winrm/config/listener -SelectorSet @{Address="*"; Transport="HTTP"}

# Tune WinRM service
Set-WSManInstance WinRM/Config -ValueSet @{MaxTimeoutms="1800000"}
Set-WSManInstance WinRM/Config/Winrs -ValueSet @{MaxMemoryPerShellMB="1024"}
Set-WSManInstance WinRM/Config/Service -ValueSet @{AllowUnencrypted="true"}
Set-WSManInstance WinRM/Config/Service/Auth -ValueSet @{Basic="true"}

# Open WinRM port in Windows Firewall
netsh advfirewall firewall add rule name="WinRM HTTP" protocol=TCP dir=in localport=5985 action=allow
netsh advfirewall firewall add rule name="WinRM HTTPS" protocol=TCP dir=in localport=5986 action=allow

# Restart WinRM to apply changes
Restart-Service WinRM

# Signal that init is done
Write-Host "WinRM configuration complete."
# First boot for the source Windows server.
# The instance file renders this with templatefile before the machine
# is created. Placeholders: computer_name, discovery_username,
# discovery_password. This file does not contain the password.
#
# Windows Remote Management (WinRM) on port 5985 is how the discovery
# appliance in Azure reads this server. A local administrator is created
# for that connection. The built-in Administrator account stays for
# Remote Desktop. Its password is the one Amazon Web Services (AWS)
# encrypted with the key pair.
#
# LocalAccountTokenFilterPolicy lets that local administrator act with
# full rights over WinRM. Without it, User Account Control (UAC) filters
# the token and discovery returns no data.

Enable-PSRemoting -Force -SkipNetworkProfileCheck
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
netsh advfirewall firewall add rule name="WinRM HTTP 5985" dir=in action=allow protocol=TCP localport=5985

New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force

net user "${discovery_username}" "${discovery_password}" /add
net localgroup Administrators "${discovery_username}" /add

Rename-Computer -NewName "${computer_name}" -Force -Restart

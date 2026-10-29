# First boot for the source Windows server.
# The instance file renders this with templatefile before the machine
# is created. Placeholders: computer_name, discovery_username,
# discovery_password. This file does not contain the password.
#
# Windows Remote Management (WinRM) on port 5985 is how the discovery
# appliance in Azure reads this server. The replication appliance in
# this network installs the Mobility service, which also needs File and
# Printer Sharing and Windows Management Instrumentation (WMI). A local
# administrator is created for both connections. The built-in
# Administrator account stays for Remote Desktop. Its password is the
# one Amazon Web Services (AWS) encrypted with the key pair.
#
# LocalAccountTokenFilterPolicy lets that local administrator act with
# full rights over WinRM. Without it, User Account Control (UAC) filters
# the token and discovery returns no data.

Enable-PSRemoting -Force -SkipNetworkProfileCheck
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
netsh advfirewall firewall add rule name="WinRM HTTP 5985" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="Mobility SMB 445" dir=in action=allow protocol=TCP localport=445
netsh advfirewall firewall add rule name="Mobility RPC 135" dir=in action=allow protocol=TCP localport=135
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes
netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable=Yes

New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force

# /Y answers the confirmation when the password is longer than 14 characters.
# Without it, first boot stops at a Y/N prompt and migrateadmin never gets created.
net user "${discovery_username}" "${discovery_password}" /add /Y
net localgroup Administrators "${discovery_username}" /add

Rename-Computer -NewName "${computer_name}" -Force -Restart

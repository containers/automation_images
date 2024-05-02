
. $PSScriptRoot\win-lib.ps1

# Disables runtime process virus scanning, which is not necessary
Set-MpPreference -DisableRealtimeMonitoring 1

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install basic required tooling.
#   psexec needed to workaround session 0 WSL bug
retryInstall git archiver psexec golang mingw StrawberryPerl; Check-Exit

# Update service is required for dotnet
Set-Service -Name wuauserv -StartupType "Manual"; Check-Exit

# dotnet is required for wixtoolset
# Allowing chocolaty to install dotnet breaks in an entirely
# non-debuggable way.  Workaround this by installing it as
# a server-feature first.
Install-WindowsFeature -Name Net-Framework-Core; Check-Exit

# 2024-05-02 Installing wix from chocolaty isn't updating from v3 to v4
(get-command dotnet).Path tool install --global wix
Check-Exit

# Install Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients -All -NoRestart

# Install WSL, and capture text output which is not normally visible
$x = wsl --install; Check-Exit 0 1 # wsl returns 1 on reboot required
Write-Host $x
Exit 0

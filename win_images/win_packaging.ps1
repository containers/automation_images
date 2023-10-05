
. $PSScriptRoot\win-lib.ps1

# Disables runtime process virus scanning, which is not necessary
Set-MpPreference -DisableRealtimeMonitoring 1

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install basic required tooling.
#   psexec needed to workaround session 0 WSL bug
retryInstall git archiver psexec golang mingw; Check-Exit

# Update service is required for dotnet
Set-Service -Name wuauserv -StartupType "Manual"; Check-Exit

# dotnet is required for wixtoolset
# Allowing chocolaty to install dotnet breaks in an entirely
# non-debuggable way.  Workaround this by installing it as
# a server-feature first.
Install-WindowsFeature -Name Net-Framework-Core; Check-Exit

# Install wixtoolset for installer build & test.
retryInstall wixtoolset; Check-Exit

# Install Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart

# Install WSL, and capture text output which is not normally visible
$x = wsl --install; Check-Exit 0 1 # wsl returns 1 on reboot required
Write-Host $x
Exit 0

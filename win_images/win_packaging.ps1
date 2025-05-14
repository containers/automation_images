
. $PSScriptRoot\win-lib.ps1

# Disables runtime process virus scanning, which is not necessary
Set-MpPreference -DisableRealtimeMonitoring 1

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install basic required tooling.
#   psexec needed to workaround session 0 WSL bug
retryInstall 7zip git archiver psexec golang mingw StrawberryPerl zstandard; Check-Exit

# Update service is required for dotnet
Set-Service -Name wuauserv -StartupType "Manual"; Check-Exit

# Install dotnet as that's the best way to install WiX 4+
# Choco does not support installing anything over WiX 3.14
Invoke-WebRequest -Uri https://dotnet.microsoft.com/download/dotnet/scripts/v1/dotnet-install.ps1 -OutFile dotnet-install.ps1
.\dotnet-install.ps1 -InstallDir 'C:\Program Files\dotnet'

# Configure NuGet sources for dotnet to fetch wix (and other packages) from
& 'C:\Program Files\dotnet\dotnet.exe' nuget add source https://api.nuget.org/v3/index.json -n nuget.org

# Install wix. Version should match the one in
#   https://github.com/containers/podman/blob/main/contrib/win-installer/podman.wixproj
& 'C:\Program Files\dotnet\dotnet.exe' tool install --global wix --version 5.0.2

# Install Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-Clients -All -NoRestart

# Install WSL, and capture text output which is not normally visible
$x = wsl --install; Check-Exit 0 1 # wsl returns 1 on reboot required
Write-Host $x
Exit 0

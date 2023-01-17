function CheckExit {
  param(
    [parameter(ValueFromRemainingArguments = $true)]
    [string[]] $codes = @(0)
  )
  if ($LASTEXITCODE -eq $null) {
    return
  }

  foreach ($code in $codes) {
    if ($LASTEXITCODE -eq $code) {
      return
    }
  }

  Exit $LASTEXITCODE
}


# Disables runtime process virus scanning, which is not necessary
Set-MpPreference -DisableRealtimeMonitoring 1
$ErrorActionPreference = "stop"

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install Git, BZ2 archive support, Go, and the MingW (GCC for Win) compiler for CGO support
# Add pstools to workaorund sess 0 WSL bug
choco install -y git mingw archiver psexec; CheckExit
choco install golang --version 1.19.2 -y; CheckExit

# Install WSL, and capture text output which is not normally visible
$x = wsl --install; CheckExit 0 1 # wsl returns 1 on reboot required
Write-Output $x
Exit 0

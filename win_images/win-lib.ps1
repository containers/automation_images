
$ErrorActionPreference = "stop"

Set-ExecutionPolicy Bypass -Scope Process -Force

function Check-Exit {
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

# Retry installation on failure or 5-minute timeout (for all packages)
function retryInstall {
    param([Parameter(ValueFromRemainingArguments)] [string[]] $pkgs)

    foreach ($pkg in $pkgs) {
        for ($retries = 0; ; $retries++) {
            if ($retries -gt 5) {
                throw "Could not install package $pkg"
            }

            if ($pkg -match '(.[^\@]+)@(.+)') {
                $pkg = @("--version", $Matches.2, $Matches.1)
            }

            # Chocolatey best practices as of 2024-04:
            #   https://docs.chocolatey.org/en-us/choco/commands/#scripting-integration-best-practices-style-guide
            # Some of those are suboptimal, e.g., using "upgrade" to mean "install",
            # hardcoding a specific API URL. We choose to reject those.
            choco install $pkg -y --allow-downgrade --execution-timeout=300
            if ($LASTEXITCODE -eq 0) {
                break
            }
            Write-Host "Error installing, waiting before retry..."
            Start-Sleep -Seconds 6
        }
    }
}

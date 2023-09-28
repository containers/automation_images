
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

            choco install -y --allow-downgrade --execution-timeout=300 $pkg
            if ($LASTEXITCODE -eq 0) {
                break
            }
            Write-Host "Error installing, waiting before retry..."
            Start-Sleep -Seconds 6
        }
    }
}

# This script restarts website {REPLACE_WITH_WEBSITE_NAME} on the local IIS server

if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    # EB runs these scripts in 32-bit PowerShell - we need to force them to run in 64-bit
    & (Join-Path ($PSHOME -replace "syswow64", "sysnative") powershell.exe) -file `
      (Join-Path $PSScriptRoot $MyInvocation.MyCommand) @args
    exit
}

Import-Module WebAdministration

Stop-Website "Default Web Site" # just in case it's running

Stop-Website "{REPLACE_WITH_WEBSITE_NAME}"

Start-Website "{REPLACE_WITH_WEBSITE_NAME}"

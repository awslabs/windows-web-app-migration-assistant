# This script uninstalls website {REPLACE_WITH_WEBSITE_NAME} on the local IIS server and deletes its files

if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    # EB runs these scripts in 32-bit PowerShell - we need to force them to run in 64-bit
    & (Join-Path ($PSHOME -replace "syswow64", "sysnative") powershell.exe) -file `
      (Join-Path $PSScriptRoot $MyInvocation.MyCommand) @args
    exit
}

Import-Module WebAdministration

$websiteFilePath = Get-WebFilePath "IIS:\Sites\{REPLACE_WITH_WEBSITE_NAME}"

Remove-Website -Name {REPLACE_WITH_WEBSITE_NAME}

Start-Sleep -s 30

$websiteFilePathString = $websiteFilePath.ToString()

Remove-Item $websiteFilePathString -Recurse -Force -ErrorAction Ignore

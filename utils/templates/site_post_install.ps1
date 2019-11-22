# This script performs post-installation operations for website {REPLACE_WITH_WEBSITE_NAME} on the local IIS server

if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    # EB runs these scripts in 32-bit PowerShell - we need to force them to run in 64-bit
    & (Join-Path ($PSHOME -replace "syswow64", "sysnative") powershell.exe) -file `
      (Join-Path $PSScriptRoot $MyInvocation.MyCommand) @args
    exit
}

Import-Module WebAdministration
$siteName = "{REPLACE_WITH_WEBSITE_NAME}"

# update site directory ACL
$websiteFilePath = Get-WebFilePath "IIS:\Sites\$siteName"
$websiteFilePathString = $websiteFilePath.ToString()
$accessControlList = Get-Acl $websiteFilePathString
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
$accessControlList.AddAccessRule($accessRule)
Set-Acl $websiteFilePathString $accessControlList

# update the site bindings to 80 & 443
$siteBindings = Get-WebBinding -Name $siteName
foreach ($binding in $siteBindings) {
    $protocol = $binding.protocol
    $bindingInfo = $binding.bindingInformation
    if ($protocol -eq "http") {
        Set-WebBinding -Name $siteName -BindingInformation $bindingInfo -PropertyName Port -Value 80
    }
    if ($protocol -eq "https") {
        # there is a bug on MS side for https binding - need to use a low level command
        Set-WebConfigurationProperty "/system.applicationHost/sites/site[@name='$siteName']/bindings/binding[@protocol='https']" -name bindingInformation -value "*:443:"
    }
}

# start website
Stop-Website "Default Web Site"
Start-Website $siteName

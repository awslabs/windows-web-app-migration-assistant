# This script contains 18 IIS hardening settings that improve the Elastic Beanstalk server security
# This is an experimental feature and it might decrease the performance of the ASP.NET application being migrated in some rare cases
$ErrorActionPreference = "Continue"

# (L1) Ensure 'directory browsing' is set to disabled
Set-WebConfigurationProperty -Filter system.webserver/directorybrowse -PSPath iis:\ -Name Enabled -Value False

# (L1) Ensure WebDav feature is disabled
Remove-WindowsFeature Web-DAV-Publishing

# (L1) Ensure 'global authorization rule' is set to restrict access 
Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/authorization" -name "." -AtElement @{users='*';roles='';verbs=''}
Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/authorization" -name "." -value @{accessType='Allow';roles='Administrators'}

# (L1) Ensure IIS HTTP detailed errors are hidden from displaying remotely
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpErrors" -name "errorMode" -value "DetailedLocalOnly"

# (L1) Ensure 'MachineKey validation method - .Net 4.5' is configured 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT' -filter "system.web/machineKey" -name "validation" -value "AES"

# (L1) Ensure Double-Encoded requests will be rejected 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering" -name "allowDoubleEscaping" -value "True"

# (L1) Ensure 'HTTP Trace Method' is disabled 
Add-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering/verbs" -name "." -value @{verb='TRACE';allowed='False'}

# (L1) Ensure Handler is not granted Write and Script/Execute 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/handlers" -name "accessPolicy" -value "Read,Script"

# (L1) Ensure 'notListedIsapisAllowed' is set to false 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/isapiCgiRestriction" -name "notListedIsapisAllowed" -value "False"

# (L1) Ensure 'notListedCgisAllowed' is set to false 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/isapiCgiRestriction" -name "notListedCgisAllowed" -value "False"

# (L2) Ensure 'debug' is turned off 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.web/compilation" -name "debug" -value "False"

# (L2) Ensure ASP.NET stack tracing is not enabled 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.web/trace" -name "enabled" -value "False"

# (L2) Ensure X-Powered-By Header is removed 
Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webserver/httpProtocol/customHeaders" -name "." -AtElement @{name='X-Powered-By'}

# (L2) Ensure Server Header is removed 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST/' -filter "system.webServer/security/requestFiltering" -name "removeServerHeader" -value "True"

# (L2) Ensure 'maxAllowedContentLength' is configured 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering/requestLimits" -name "maxAllowedContentLength" -value 30000000

# (L2) Ensure 'maxURL request filter' is configured 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering/requestLimits" -name "maxUrl" -value 4096

# (L2) Ensure 'MaxQueryString request filter' is configured 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering/requestLimits" -name "maxQueryString" -value 2048

# (L2) Ensure non-ASCII characters in URLs are not allowed 
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering" -name "allowHighBitCharacters" -value "False"


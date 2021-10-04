# This script installs website {REPLACE_WITH_WEBSITE_NAME} on the local IIS server using Web Deploy
# (not used) encryptPassword={REPLACE_WITH_PASSWORD}

if ($env:PROCESSOR_ARCHITECTURE -eq "x86") {
    # EB runs these scripts in 32-bit PowerShell - we need to force them to run in 64-bit
    & (Join-Path ($PSHOME -replace "syswow64", "sysnative") powershell.exe) -file `
      (Join-Path $PSScriptRoot $MyInvocation.MyCommand) @args
    exit
}

$msDeployExe = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe" # fixed for Elastic Beanstalk IIS instances
$msDeployVerb = "-verb:sync"

$msDeployStdOutPackagingTimeLog = "C:\Program Files\Amazon\ElasticBeanstalk\logs\eb_migration_msdeploy_p.stdout"
$msDeployStdErrPackagingTimeLog = "C:\Program Files\Amazon\ElasticBeanstalk\logs\eb_migration_msdeploy_p.stderr"
$msDeployStdOutDeploymentTimeLog = "C:\Program Files\Amazon\ElasticBeanstalk\logs\eb_migration_msdeploy_d.stdout"
$msDeployStdErrDeploymentTimeLog = "C:\Program Files\Amazon\ElasticBeanstalk\logs\eb_migration_msdeploy_d.stderr"

# generate deployment package

$packagingSource = "-source:archiveDir='C:\staging\site_content'"
$packagingDest = "-dest:package='C:\staging\source_bundle.zip'"
$declareParam='-declareParamFile:"C:\staging\site_content\parameters.xml"' # do not modify the quotation marks

[String[]] $msDeployPackagingArgs = @(
    $msDeployVerb,
    $packagingSource,
    $packagingDest,
    $declareParam
)

$process = Start-Process $msDeployExe -ArgumentList $msDeployPackagingArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $msDeployStdOutPackagingTimeLog -RedirectStandardError $msDeployStdErrPackagingTimeLog
if ( 0 -ne $process.ExitCode )
{
  Write-Output "ERROR: msdeploy.exe exits with nonzero exitcode"
  exit $process.ExitCode
}

# deploy to local server

$msDeploySource = "-source:package='C:\staging\source_bundle.zip'"
$msDeployDest = "-dest:appHostConfig='{REPLACE_WITH_WEBSITE_NAME}'"
$msDeployEnableAppPoolExt = "-enableLink:AppPoolExtension"
$msDeployAppPool = "-setParam:'Application Pool'='.NET v4.5'"

[String[]] $msDeployDeploymentArgs = @(
    $msDeployVerb,
    $msDeploySource,
    $msDeployDest,
    $msDeployEnableAppPoolExt,
    $msDeployAppPool
)

$process = Start-Process $msDeployExe -ArgumentList $msDeployDeploymentArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $msDeployStdOutDeploymentTimeLog -RedirectStandardError $msDeployStdErrDeploymentTimeLog

exit $process.ExitCode

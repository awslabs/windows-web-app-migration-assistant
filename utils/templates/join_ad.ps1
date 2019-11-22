Import-Module AWSPowerShell
Add-WindowsFeature Web-Security,Web-Windows-Auth
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WindowsAuthentication

Start-transcript -Path C:\\JoinDomain-Transcript.txt -Force

$instanceId = Invoke-RestMethod -uri http://169.254.169.254/latest/meta-data/instance-id
$availabilityZone = Invoke-RestMethod -uri http://169.254.169.254/latest/meta-data/placement/availability-zone
$region = $AvailabilityZone.Substring(0, $availabilityZone.Length - 1)
Set-DefaultAWSRegion $region

Try {
  New-SSMAssociation -InstanceId $instanceId -Name "{REPLACE_WITH_SSM_DOC_NAME}"
} Catch {
  $errorMessage = $_.Exception.Message
  "Exception: $errorMessage"
}

Stop-transcript

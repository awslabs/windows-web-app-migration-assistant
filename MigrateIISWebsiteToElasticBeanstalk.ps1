# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#  http://aws.amazon.com/apache2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

<#------------------------------------------------------------------------------------------------------------------------------#
  SYNOPSIS
    Microsoft .NET application modernization utility that migrates IIS websites from Windows servers to AWS Elastic Beanstalk.
  DEPENDENCIES
    MS PowerShell version 3.0 or above.
 #------------------------------------------------------------------------------------------------------------------------------#>

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

function Global:Test-PowerShellSessionRole {
    <#
        .SYNOPSIS
            This function checks if the current session is of the specified windows built-in role
        .INPUTS
            Windows built-in role
        .OUTPUTS
            Boolean - if the input role matches with session role or not
        .EXAMPLE
            Test-PowerShellSessionRole -Role Administrator
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Security.Principal.WindowsBuiltInRole]
        $Role
    )

    $currentSessionIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSessionPrincipal = New-Object System.Security.Principal.WindowsPrincipal($currentSessionIdentity)
    $currentSessionPrincipal.IsInRole($Role)
}

function Global:Get-WebsiteByName {
    <#
        .SYNOPSIS
            Calls Get-Website with the name argument and returns the correct website - bugfix for MS
        .INPUTS
            Name of the website (website names are unique by default on a single server)
        .OUTPUTS
            ConfigurationElement object that represents the website
        .EXAMPLE
            Get-WebsiteByName NopCommerce380
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name
    )

    $website = Get-Website | where { $_.Name -eq $Name }
    if ($website -eq $null) {
        throw "ERROR: Cannot get website $Name"
    }
    $website
}

function Global:Get-WebDeployV3Exe {
    <#
        .SYNOPSIS
            Returns the path of Web Deploy Version 3 executable
        .INPUTS
            None
        .OUTPUTS
            String - local path of the msDeploy.exe
    #>
    [CmdletBinding()]
    param ()

    $webDeployV3Key = "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy\3"
    if (!(Test-Path $webDeployV3Key)) {
        throw "ERROR: Cannot find Web Deploy v3"
    }

    $installPath = (Get-ItemProperty $webDeployV3Key -Name InstallPath | Select -ExpandProperty InstallPath)
    if ($installPath -eq $null) {
        throw "ERROR: Cannot find installation path of Web Deploy v3"
    }

    $installPath + "msdeploy.exe"
}

function Global:Verify-WebsiteExists {
    <#
        .SYNOPSIS
            Verifies if the given website exists on the local machine
        .INPUTS
            Name of the website
        .OUTPUTS
            None - will throw exception when test fails
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $WebsiteName
    )

    $site = Get-Website | Where-Object { $_.name -eq $WebsiteName }
    if (-Not $site) {
        Throw "ERROR: Cannot find website $WebsiteName"
    }
}

function Global:Verify-PathExists {
    <#
        .SYNOPSIS
            Verifies if the given path exists
        .INPUTS
            A full physical path
        .OUTPUTS
            None - will throw exception when test fails
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PathToTest
    )

    if (!(Test-Path -Path $PathToTest)) {
        throw "ERROR: $PathToTest does not exist."
    }
}

function Global:Verify-FolderExistsAndEmpty {
    <#
        .SYNOPSIS
            Tests if the given path:
            1. Exists
            2. Is a folder
            3. Is empty
        .INPUTS
            Full physical path of the folder
        .OUTPUTS
            None - will throw exception when test fails
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PathToTest
    )

    Verify-PathExists $PathToTest

    if (!((Get-Item $PathToTest) -is [System.IO.DirectoryInfo])) {
        throw "ERROR: Path $PathToTest is not a folder."
    }

    $dirInfo = Get-ChildItem $PathToTest | Measure-Object
    if ($dirInfo.count -ne 0) {
        throw "ERROR: Folder $PathToTest is not empty."
    }
}

function Global:Get-ZippedFolder {
    <#
        .SYNOPSIS
            This function zips a folder, generating the result file into the output folder
        .INPUTS
            1. Full physical path of the folder to be zipped
            2. Full physical path of the output folder
            3. Name of the result file
        .OUTPUTS
            Full physical path of the result zip file
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourceFolderPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $OutputFolderPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ZipFileName
    )

    Verify-PathExists $SourceFolderPath
    Verify-PathExists $OutputFolderPath

    $resultFilePath = Join-Path $OutputFolderPath $ZipFileName

    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceFolderPath, $resultFilePath, $compressionLevel, $false)

    $resultFilePath
}

function Global:Unzip-Folder {
    <#
        .SYNOPSIS
            This function unzips a zip file and releases the contents into the output folder
        .INPUTS
            1. Full physical path of the zip file
            2. Full physical path of the output folder - it must be an empty and existing folder
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ZipFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $OutputFolderPath
    )

    Verify-PathExists $ZipFilePath
    Verify-FolderExistsAndEmpty $OutputFolderPath

    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $OutputFolderPath)
}

function Global:New-Folder {
    <#
        .SYNOPSIS
            Creates a new folder item and logs the event to (global) $ItemCreationLogFile
        .INPUTS
            1. Path to the parent folder
            2. Name of the new folder
            3. Whether to return the full physical path of the new folder or not
        .OUTPUTS
            Full physical path of the new folder (on demand)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ParentPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FolderName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Boolean]
        $ReturnFolderPath
    )

    $folder = New-Item -Path $ParentPath -Name $FolderName -ItemType Directory -Force
    $folder | Out-File -append $ItemCreationLogFile

    if ($ReturnFolderPath) {
        $folder.ToString()
    }
}

function Global:New-File {
    <#
        .SYNOPSIS
            Creates a new file item and logs the event to (global) $ItemCreationLogFile
        .INPUTS
            1. Path to the parent folder
            2. Name of the new file
            3. Whether to return the full physical path of the new file or not
        .OUTPUTS
            Full physical path of the new file (on demand)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ParentPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FileName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Boolean]
        $ReturnFilePath
    )

    $file = New-Item -Path $ParentPath -Name $FileName -ItemType File -Force
    $file | Out-File -append $ItemCreationLogFile

    if ($ReturnFilePath) {
        $file.ToString()
    }
}

function Global:Delete-Item {
    <#
        .SYNOPSIS
            Deletes a file or folder and all of its contents (use at clean-up time)
        .INPUTS
            Full physical path of the file or folder
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PathToDelete
    )
    Remove-Item $PathToDelete -Recurse -ErrorAction Ignore
}

function Global:Get-RandomPassword {
    ([char[]]([char]97..[char]122) + [char[]]([char]65..[char]90) + 0..9 | sort {Get-Random})[0..24] -join ''
}

function Global:Exit-WithError {
    exit 1
}

function Global:Exit-WithoutError {
    exit 0
}

# Types of log message
$Global:InfoMsg = "Info"
$Global:DebugMsg = "Debug"
$Global:ErrorMsg = "Error"
$Global:FatalMsg = "FATAL"
# use this to exclude sensitive data from logs
$Global:ConsoleOnlyMsg = "ConsoleOnly"

# AWS EB Migration Support
$Global:SupportTeamAWSRegion = ""

function Global:Write-Log {
    <#
        .NOTES
            DO NOT USE THIS FUNCTION DIRECTLY - use New-Message
            except when the log files are not initialized yet
        .SYNOPSIS
            This function writes a log line into specified log file
        .INPUTS
            1. Full physical path of the log file. It must be initialized before this function call
            2. Type of the message ($InfoMsg, $DebugMsg, $ErrorMsg, or $FatalMsg)
            3. The log message (a string)
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $LogFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Info", "Debug", "Error", "FATAL")]
        [String]
        $MessageType,

        [Parameter(Mandatory = $true)]
        [String]
        $LogMessage
    )

    Verify-PathExists $LogFilePath

    $timeStampNow = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
    $fullMessage = "$timeStampNow : $MessageType : $LogMessage"

    Add-Content $LogFilePath -Value $fullMessage
}

function Global:Get-SessionObjectFilePath ($ID) {
    $objectFileName = $ID + ".xml"
    $sessionFolderPath = Join-Path $MigrationRunDirPath $SessionFolderName
    Join-Path $sessionFolderPath $objectFileName
}

function Global:New-SessionFolder {
    <#
        .SYNOPSIS
            This function needs to be invoked before any function in this file is called.
            It creates a folder under the current migration run folder to contain session resumability files.
            The name of the folder needs to be defined in the global scope as $SessionFolderName
        .INPUTS
            None
        .OUTPUTS
            None
        .NOTES
            Please only create the folder right before you write the first set of session data
            Then you can use Test-SessionFolderExists to identify if a migration run is resumable
    #>
    Verify-PathExists $MigrationRunDirPath

    $sessionFolderPath = Join-Path $MigrationRunDirPath $SessionFolderName

    if (-Not (Test-Path $sessionFolderPath)) {
        New-Folder $MigrationRunDirPath $SessionFolderName $False
    }
}

function Global:Test-SessionFolderExists {
    <#
        .SYNOPSIS
            Tests if the session folder exists for ANY migration run
        .INPUTS
            Migration run ID
        .OUTPUTS
            Boolean
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $MigrationRunID
    )

    $testMigrationRunDirPath = Join-Path $MigrationRunsDirPath $MigrationRunID
    if (Test-Path $testMigrationRunDirPath) {
        $testSessionFolderPath = Join-Path $testMigrationRunDirPath $sessionFolderName
        Test-Path $testSessionFolderPath
        return
    }

    $False
}

function Global:Save-SessionObject {
    <#
        .SYNOPSIS
            This function serializes any PS object into a new or existing file under the session folder
        .INPUTS
            1. the PS object to serialize
            2. NAME (not path - and without extension) of the file to store the data
        .OUTPUTS
            None
        .EXAMPLE
            Save-SessionObject $iisSitesConfigStage "iis_sites_config_stage"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [PSObject]
        $Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name
    )

    $objectFilePath = Get-SessionObjectFilePath $Name
    if (Test-Path $objectFilePath) {
        Remove-Item $objectFilePath
    }

    $serializedString = [System.Management.Automation.PSSerializer]::Serialize($Object)
    $serializedString | Out-File $objectFilePath
}

function Global:Restore-SessionObject {
    <#
        .SYNOPSIS
            This function restores any previously saved PS object
        .INPUTS
            NAME (not path - and without extension) of the file that stores the data
        .OUTPUTS
            PS object
        .EXAMPLE
            $iisSitesConfigStage = Restore-sessionObject "iis_sites_config_stage"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name
    )

    $objectFilePath = Get-SessionObjectFilePath $Name
    if (-Not (Test-Path $objectFilePath)) {
        throw "Resumption Failed. Cannot find session file $objectFilePath"
    }

    $serializedString = Get-Content $objectFilePath
    [System.Management.Automation.PSSerializer]::Deserialize($serializedString)
}

<#
    Global Variables Defined in Setup-Workspace:
        $SessionFolderName
        $MigrationRunsDirPath

    Global Variables Defined in Setup-NewMigrationRun:
        $CurrentMigrationRunPath
        $LogFolderPath
        $ItemCreationLogFile
        $MigrationRunLogFile
        $EnvironmentInfoLogFile
#>

function Global:Setup-Workspace {
    <#
        .SYNOPSIS
            Call this function before anything else
        .INPUTS
            None
        .OUTPUTS
            None
    #>

    # Global & universal variables for all migration runs

    $Global:SessionFolderName = "session"
    $Global:MigrationRunsDirPath = Join-Path $runDirectory "runs"

    # need to test role first otherwise log file/folder creation may fail

    if (-Not (Test-PowerShellSessionRole -Role Administrator)) {
        Write-Host "Error: Run the migration assistant as Administrator."
        Exit-WithError
    }
}

function Global:Setup-NewMigrationRun {
    <#
        .SYNOPSIS
            Call this function to set up the workspace for a new migration run
        .INPUTS
            Migration run ID
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $MigrationRunID
    )

    # Create the main runs folder if it doesn't exist
    if (-Not (Test-Path $MigrationRunsDirPath)) {
        New-Item -Path $MigrationRunsDirPath -Force -ItemType Directory | Out-Null
    }

    $Global:CurrentMigrationRunPath = Join-Path $MigrationRunsDirPath $MigrationRunId
    $Global:LogFolderPath = Join-Path $CurrentMigrationRunPath "logs"

    if (Test-Path -Path $CurrentMigrationRunPath) {
        Write-Host "Error: $MigrationRunId already exists. Run the migration assistant again."
        Exit-WithError
    }

    try {

        $currentMigrationRunPathObj = New-Item -Path $CurrentMigrationRunPath -Force -ItemType Directory
        $logFolderPathObj = New-Item -Path $LogFolderPath -Force -ItemType Directory

        $itemCreationLogFileName = "item_creation.log"
        $itemCreationLogFileObj = New-Item -Path $LogFolderPath -Name $itemCreationLogFileName -ItemType File
        $Global:ItemCreationLogFile = $itemCreationLogFileObj.ToString()

        $currentMigrationRunPathObj | Out-File -append $ItemCreationLogFile
        $logFolderPathObj | Out-File -append $ItemCreationLogFile
        $itemCreationLogFileObj | Out-File -append $ItemCreationLogFile

        $migrationRunLogFileName = "migration_run.log"
        $Global:MigrationRunLogFile = New-File $LogFolderPath $migrationRunLogFileName $True

        # does not initiate this log file - Write-IISServerInfo will make the file
        $Global:EnvironmentInfoLogFile = Join-Path $LogFolderPath "environment_info.log"

    } catch {
        Write-Host "Error: Can't create required items. Be sure you have write permission on the 'runs' folder."
        Exit-WithError
    }
}

function Global:Invoke-CommandsWithRetry {
    <#
        .SYNOPSIS
            This function automatically repeats the input script block when an exception is thrown within retry # limit
            Before repeating, the exception will be shown in the console as an error message 
            Also logs the exception message into the specified log file
            If the max number of retry is reached, an exception will be thrown
        .INPUTS
            1. Number of max retries
            1. Full physical path of the log file
            2. The script block to execute
        .OUTPUTS
            None
        .EXAMPLE
            $Global:myGlobalVar = "27"
            Invoke-CommandsWithRetry 3 $logFile {
                $string = Get-UserInputString $logFile "Type anything other than 27"
                if ($string -eq "27") {
                    throw "That's the only number that doesn't work!"
                }
                $Global:myGlobalVar = $string
            }
            Echo $myGlobalVar # console will print the string user typed in
        .NOTES
            1. if you declare any variable within the script block, it will not be accessible outside unless made global
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $MaxRetryNumber,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $LogFilePath,

        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock
    )

    Begin {
        $retryCount = -1
    }

    Process {
        do {
            $retryCount++
            try {
                $ScriptBlock.Invoke()
                return
            } catch {
                $lastExceptionMessage = $error[0].Exception.Message
                $innerExceptionMessage = $lastExceptionMessage.Replace("Exception calling `"Invoke`" with `"0`" argument(s): ", "")
                New-Message $ErrorMsg $innerExceptionMessage $LogFilePath
                New-Message $InfoMsg "Retrying command." $LogFilePath
            }
        } while ($retryCount -lt $MaxRetryNumber)

        $logLine = "Max retry number exceeded for script block: " + $ScriptBlock.ToString()
        New-Message $DebugMsg $logLine $LogFilePath

        throw "Max retry number exceeded."
    }
}

function Global:Get-UserFacingMessage ($Message) {

    $messagePrefix = "[AWS Migration] "

    if ($DisplayTimestampsInConsole) {
        $timestampNow = [datetime]::Now.ToString('yyyy-MM-dd HH:mm')
        $messagePrefix = "[$timestampNow] "
    }

    if ($Message) {
        $messagePrefix + $Message
    } else {
        $messagePrefix
    }
}

function Global:New-Message {
    <#
        .SYNOPSIS
            This function generates a new message. Depending on the message type, it
            1. displays this message to the user via the console (with timestamp, when $DisplayTimestampsInConsole is on)
            2. stores the message as a new log line (with timestamp)
        .INPUTS
            1. Type of message ($InfoMsg, $DebugMsg, $ErrorMsg, or $FatalMsg)
                a. $InfoMsg: the message will go to the user & log file
                b. $DebugMsg: the message will only go to the log file
                c. $ErrorMsg: the message will go to the user & log file. Additional information is added to user facing message
                d. $FatalMsg: the message will go to the user & log file. Additional information is added to user facing message
            2. The message itself (a string)
            2. Full physical path of the log file. It must be initialized before this function call
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Info", "Debug", "Error", "FATAL", "ConsoleOnly")]
        [String]
        $MessageType,

        [Parameter(Mandatory = $true)]
        [String]
        $Message,

        [Parameter(Mandatory = $true)]
        [String]
        $LogFilePath
    )

    if ($MessageType -ne "ConsoleOnly") {
        Write-Log $LogFilePath $MessageType $Message
    }

    $userFacingMessage = $Message

    if (($MessageType -eq "Error") -or ($MessageType -eq "FATAL")) {
        $userFacingPrefix = "[$MessageType] "
        $fullTimeStampNow = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
        $userFacingSuffix = " (at $fullTimeStampNow)"
        $userFacingMessage = $userFacingPrefix + $userFacingMessage + $userFacingSuffix
    }

    $color = "White"
    switch ($MessageType) {
        "Error" { $color = "Yellow"; break }
        "FATAL" { $color = "Red"; break }
        default { break }
    }

    if ($MessageType -ne "Debug") {
        $messageToDisplay = Get-UserFacingMessage $userFacingMessage
        Write-Host $messageToDisplay -ForegroundColor $color
    }
}

function Global:Get-UserInputString {
    <#
        .SYNOPSIS
            This function does the following things:
            1. display an optional prompt message to the user (with timestamp, when $DisplayTimestampsInConsole is on)
            2. collect and return the text input from the user as a string
            3. add the user input to the specified log file
        .INPUTS
            1. full physical path to the log file
            2. prompt message (optional) - please do not include ":"
        .OUTPUTS
            User input as a string
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $LogFilePath,

        [Parameter(Mandatory = $false)]
        [String]
        $PromptMessage
    )

    if ($PromptMessage) {
        $promptMessageLogLine = "UserInterface-Prompt : " + $PromptMessage
        Write-Log $LogFilePath $InfoMsg $promptMessageLogLine
    }

    $userFacingPromptMessage = Get-UserFacingMessage $PromptMessage

    $userInput = Read-Host -Prompt $userFacingPromptMessage

    $userInputLogLine = "UserInterface-Input : " + $userInput

    Write-Log $LogFilePath $InfoMsg $userInputLogLine

    $userInput
}

function Global:Get-SensitiveUserInputString {
    <#
        .SYNOPSIS
            This function does the following things:
            1. display an optional prompt message to the user (with timestamp, when $DisplayTimestampsInConsole is on)
            2. collect and return the text input from the user as a string
            3. Logs only the prompt, NOT the user input
        .INPUTS
            1. full physical path to the log file
            2. prompt message (optional) - please do not include ":"
        .OUTPUTS
            User input as a string
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $LogFilePath,

        [Parameter(Mandatory = $false)]
        [String]
        $PromptMessage
    )

    if ($PromptMessage) {
        $promptMessageLogLine = "UserInterface-Prompt-SensitiveInput : " + $PromptMessage
        Write-Log $LogFilePath $InfoMsg $promptMessageLogLine
    }

    $userFacingPromptMessage = Get-UserFacingMessage $PromptMessage
    Read-Host -Prompt $userFacingPromptMessage
}

function Global:Append-DotsToLatestMessage {
    <#
        .SYNOPSIS
            This function appends a number of dots to the last message displayed in the console
        .INPUTS
            Number of dots to add
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $NumberOfDots
    )

    if ($NumberOfDots -lt 0) {
        throw "Error: cannot add negative number of dots to the message."
    }
    $numberAdded = 0;
    while ($numberAdded -lt $NumberOfDots) {
        Write-Host -NoNewline "."
        $numberAdded ++
    }
}

function Global:Show-SpinnerAnimation {
    <#
        .SYNOPSIS
            This function shows a spinner animation in the PowerShell console
        .INPUTS
            Seconds to display the animation
        .OUTPUTS
            None
        .EXAMPLE
            $job = Start-Process $yourProcess
            while ($job.Running) { Show-SpinnerAnimation 3 }
            Write-Host " "
        .NOTES
            You can call a this function multiple times in a roll to have a continuous spin
            After you are done with spinning, please invoke 'Write-Host " "' to make a new line
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $DurationInSeconds
    )

    $prefix = Get-UserFacingMessage
    $spinner = "/-\|/-\|"
    $frame = 0

    $count = 0
    $limit = 10 * $DurationInSeconds # because 100 milliseconds per frame

    $originalPosition = $Host.UI.RawUI.CursorPosition

    while ($count -le $limit) {
        $Host.UI.RawUI.CursorPosition = $originalPosition
        $currentFrame = "`r$prefix" + $spinner[$frame]

        Write-Host -NoNewline $currentFrame
        Start-Sleep -Milliseconds 100

        $frame++
        $count++

        if ($frame -ge $spinner.Length) {
            $frame = 0
        }
    }

    $Host.UI.RawUI.CursorPosition = $originalPosition
}

function Global:Get-IISServerInfoObject()
{
        <#
              .SYNOPSIS
                        Get list of objects with details of each website.
              .INPUTS
                        None
              .OUTPUTS
                        Returns object containing top-level IIS server information
                        objects from IIS applicationHost.config and administration.config.
                        IIS configurations are at %windir%\windows\system32\inetsrv\config

                        Return object contains these objects:
                           +--- Computer Name
                           +--- OS Version
                           +--- gac
                           +--- applicationHost
                           +--- webServer
                           +--- ftpServer
                           +--- location
                           +--- IIS versions
                           +--- appHost
                           +--- location
                           +--- admWebServer
                           +--- admModuleProviders
              .EXAMPLE
                        $serverObj = Get-IISServerInfoObjects
        #>

        [CmdletBinding()]
        [OutputType([psobject])]
        param()

        $windir = $Env:Windir
        [hashtable]$resultObject = @{}

        $computer = Get-WmiObject -Class Win32_ComputerSystem
        $osVersion = $([System.Environment]::OSVersion.Version)

        $resultObject.Add('computerName', $computer.name)
        $resultObject.Add('osVersion', $osVersion)

        $APP_HOST_CFG_FILE_PATH = $windir + "\system32\inetsrv\config\applicationHost.config"
        $APP_HOST_XML_PATH = "configuration/system.applicationHost"
        $WEB_SERVER_XML_PATH = "configuration/system.webServer"
        $FTP_SERVER_XML_PATH = "configuration/system.ftpServer"
        $LOCATION_XML_PATH = "configuration/location"
        $INETSRV_WEBADMIN_DLL= $windir + "\system32\inetsrv\Microsoft.Web.Administration.dll"

        $ADM_CFG_FILE_PATH = $windir + "\system32\inetsrv\config\administration.config"
        $ADM_WEBSERVER_XML_PATH = "configuration/system.webServer"
        $ADM_MODULE_PROVIDERS_XML_PATH = "configuration/moduleProviders"

        if (!(Test-Path $APP_HOST_CFG_FILE_PATH -PathType Leaf)) {
             Write-Output $APP_HOST_CFG_FILE_PATH
             throw "ERROR: Cannot get Application Host Config"
        }
        if (!(Test-Path $INETSRV_WEBADMIN_DLL -PathType Leaf)) {
             Write-Output $INETSRV_WEBADMIN_DLL
             throw "ERROR: Cannot get web admin dll"
        }

        $appHost = Select-Xml -Path $APP_HOST_CFG_FILE_PATH -XPath $APP_HOST_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('appHost', $appHost)

        $gac=[System.Reflection.Assembly]::LoadFrom($INETSRV_WEBADMIN_DLL)
        $resultObject.Add('gac', $gac)

        $webServer = Select-Xml -Path $APP_HOST_CFG_FILE_PATH -XPath $WEB_SERVER_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('webServer', $webServer)

        $ftpServer = Select-Xml -Path $APP_HOST_CFG_FILE_PATH -XPath $FTP_SERVER_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('ftpServer', $ftpServer)

        $iisVersions = get-itemproperty HKLM:\SOFTWARE\Microsoft\InetStp\ | select setupstring,versionstring
        $resultObject.Add('iisVersion', $iisVersions)

        $location = Select-Xml -Path $APP_HOST_CFG_FILE_PATH -XPath $LOCATION_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('location', $location)

        $admWebServer = Select-Xml -Path $ADM_CFG_FILE_PATH -XPath $ADM_WEBSERVER_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('admWebServer', $admWebServer)

        $admModuleProviders = Select-Xml -Path $ADM_CFG_FILE_PATH -XPath $ADM_MODULE_PROVIDERS_XML_PATH | Select-Object -ExpandProperty Node
        $resultObject.Add('admModuleProviders', $admModuleProviders)

        return $resultObject
}

function Global:Write-IISServerInfo()
{
        <#
            .SYNOPSIS
                    Write IIS server info to log file
            .INPUTS
                    Output file name, website object
            .OUTPUTS
                    None
        #>
        [CmdletBinding()]
        [OutputType([psobject])]
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $outputFileName
        )

        $output = ""

        $serverObj = Get-IISServerInfoObject

        $output += "Computer Name: $($serverObj["computerName"])`r`n`r`n"
        $output += "OS Version: $($serverObj["osVersion"])`r`n`r`n"

        if (Test-Path -Path $outputFileName) {
            throw "ERROR: $outputFileName exists"
        }

        foreach ($site in $serverObj['appHost'].sites.site) {
                $output += "Website name : $($site.name), id : $($site.id), serverAutoStart status : $($site.serverAutoStart)`r`n"
                foreach ($node in $site.bindings.ChildNodes) {
                        if ($node.protocol -ne $null) {
                                $output += "`tProtocol : $($node.protocol), Binding info : $($node.bindingInformation)`r`n"
                        }
                }
                $output += "`tApplication virtualDirectory path = $($site.application.virtualDirectory.path), physicalPath =  $($site.application.virtualDirectory.physicalPath)"
                $exists = $site.application.applicationPool
                if ($exists) {
                    $output += ", applicationPool = $($site.application.applicationPool)"
                }
                $output += "`r`n"
        }

        $security = $serverObj['webServer'].security
        if ($security.authentication) {
            $output += "Anonymous Authentication : $($security.authentication.anonymousAuthentication.enabled)`r`n"
            $output += "Basic Authentication : $($security.authentication.basicAuthentication.enabled)`r`n"
            $output += "Digest Authentication : $($security.authentication.digestAuthentication.enabled)`r`n"
            $output += "IIS Client Certificate Mapping Authentication : $($security.authentication.iisClientCertificateMappingAuthentication.enabled)`r`n"
            $output += "Windows Authentication : $($security.authentication.windowsAuthentication.enabled)`r`n"
        }
        $gac = $serverObj['gac']
        $output += "GAC enable status : $($gac.GlobalAssemblyCache)`r`n"
        $iisVersions = $serverObj['iisVersion']
        $output += "IIS version : $($iisVersions.SetupString)`r`n"

        $appPools = $serverObj['appHost'].applicationPools
        foreach ($item in $appPools.childnodes ) {
            $printStr = ""
            if ($item.name -ne "#whitespace") {
                $printStr = "App Pool Name : $($item.name)"
                $exists = $item.managedPipelineMode
                if ($exists) {
                    $printstr += ", Managed pipeline mode : $($item.managedPipelineMode)"
                }
                $exists = $item.managedRuntimeVersion
                if ($exists) {
                    $printstr += ", Managed runtime version : $($item.managedRuntimeVersion)"
                }
                $printstr += "`r`n"
            }
            if ($printStr -ne "") {
                $output += $printStr
            }
        }

        $location = $serverObj['location']
        foreach ($item in $location.childNodes ) {
            if ($item.name -ne "#whitespace" ) {
               foreach ($module in $item.modules.add) {
                       $output += "Module name: $($module.name)`r`n"
               }
            }
        }

        $admWebServer = $serverObj['admWebServer']
        foreach ($providers in $admWebServer.management.authentication) {
            foreach ($node in $providers.ChildNodes) {
                if ($node.add.type) {
                    $output += "Authentication provider name : $($node.add.name), type : $($node.add.type)`r`n"
                }
            }
        }
        foreach ($providers in $admWebServer.management.authorization) {
            foreach ($node in $providers.ChildNodes) {
                if ($node.add.type) {
                    $output += "Adm Authorization provider name : $($node.add.name), type : $($node.add.type)`r`n"
                }
            }
        }

        $admModuleProviders = $serverObj['admModuleProviders']
        foreach ($module in $admModuleProviders.add) {
             $output += "Adm module provider name : $($module.name), type = $($module.type)`r`n"
        }

        $output | out-file $outputFileName
}

function Global:Get-MissingDependencies {
    <#
        .SYNOPSIS
            This function checks for missing depencencies of the migration assistant on the local server
        .INPUTS
            None
        .OUTPUTS
            A string of the names of the missing dependencies
    #>
    [CmdletBinding()]
    param()

    $missingDependencies = ""

    # check for PowerShell 3.0+
    if (!($PSVersionTable.PSVersion.Major -ge 3)) {
        $missingDependencies += "PowerShell 3.0 or above, "
    }

    # check for IIS
    if (!(Get-Service w3svc -ErrorAction SilentlyContinue)) {
        $missingDependencies += "Internet Information Services (IIS), "
    }

    # check for Web Deploy (v3+)
    if(!(Test-Path "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy\3")) {
        $missingDependencies += "Microsoft Web Deploy v3, "
    }

    # check for AWSPowerShell
    if (!(Get-Module -ListAvailable -Name "AWSPowerShell")) {
        $missingDependencies += "AWSPowerShell, "
    }

    # check for WebAdministration
    if (!(Get-Module -ListAvailable -Name "WebAdministration")) {
        $missingDependencies += "WebAdministration, "
    }

    if ($missingDependencies) {
        return $missingDependencies.Substring(0, $missingDependencies.Length - 2)
    }
    return $Null
}

function Global:Get-AppHostSchemaPackage ($DestinationFilePath) {
    $msDeploy = Get-WebDeployV3Exe
    $argVerb = "-verb:sync"
    $argSource = "-source:appHostSchema"
    $argDest = "-dest:package='" + $DestinationFilePath + "'"

    [String[]] $argList = @(
        $argVerb,
        $argSource,
        $argDest
    )
    $process = Start-Process $msDeploy -ArgumentList $argList -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "ERROR: Failed to package appHostSchema using Web Deploy"
    }
}

function Global:Get-AppHostConfigXML {
    $appHostConfigFile = Get-WebConfigFile
    [XML] $appHostConfigXML = Get-Content $appHostConfigFile
    $appHostConfigXML
}

function Global:Get-WebServerConfigXMLString {
    $appHostConfigXML = Get-AppHostConfigXML
    $webServerXML = $appHostConfigXML.configuration."system.webServer"
    if ($webServerXML -eq $null) {
        throw "ERROR: Cannot find <system.webServer> in applicationHost.config file"
    }
    $webServerXML.OuterXML
}

function Global:Get-SitesConfigXMLString ($SiteName) {
    $appHostConfigXML = Get-AppHostConfigXML
    $sitesXML = $appHostConfigXML.configuration."system.applicationHost".sites
    $nameMatchingString = "site name=`"" + $SiteName + "`""

    foreach ($siteXML in $sitesXML.ChildNodes) {
        $siteXMLString = $siteXML.OuterXML
        if ($siteXMLString -match $nameMatchingString) {
            return $siteXMLString
        }
    }
    throw "ERROR: Cannot find site $SiteName"
}

function Global:Collect-IISConfigs {
    <#
    .SYNOPSIS
        This function collects IIS configurations of the server and the site that Web Deploy's iisApp provider does not package
    .INPUTS
        1. SiteName: string, name of the site
        2. DestinationFolderPath: string, path to an existing & empty folder
    .OUTPUTS
        3 files will be generated in the destination folder:
        1. appHostSchema.zip: any custom iis schema the user has - as a Web Deploy package
        2. siteConfig.xml: the <site> section of the applicationHostConfig.xml
        3. webServerConfig.xml: the <system.webServer> section of the applicationHostConfig.xml
    .EXAMPLE
        Collect-IISConfigs "NopCommerce380" "C:\dest"           
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DestinationFolderPath
    )

    Verify-FolderExistsAndEmpty $DestinationFolderPath

    $appHostSchemaPackagePath = $DestinationFolderPath + "\appHostSchema.zip"
    $webServerConfigOutputPath = $DestinationFolderPath + "\webServerConfig.xml"
    $sitesConfigOutputPath = $DestinationFolderPath + "\siteConfig.xml"    

    Get-AppHostSchemaPackage $appHostSchemaPackagePath
    Get-WebServerConfigXMLString | Set-Content -Path $webServerConfigOutputPath
    Get-SitesConfigXMLString $SiteName | Set-Content -Path $sitesConfigOutputPath    
}

function Global:Get-CheckAppPool {
    <#
        .SYNOPSIS
            This function checks if a site uses multiple application pools.
        .INPUTS
            Site Name
        .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )
    $NumAppsPerPool = 0
    $Apps = Get-WebApplication -Site $SiteName | sort -property ApplicationPool
    $Count = 0
    $MaxCount = 0
    $CurrApplicationPool = ""
    foreach ($App in $Apps) {
        if ($CurrApplicationPool -ne $App.applicationPool) {
            $Count = 1
            $CurrApplicationPool = $App.applicationPool
        } else {
            $Count = $Count + 1
        }
        if ($Count -gt $MaxCount) {
            $MaxCount = $Count
        }
    }

    $AppPoolCheck = [ordered]@{
        "Description"= "Checks if any site has multiple application pools."
        "Log" = "Found maximum number of applications per pool = $MaxCount, no issues found"
        "Result" = $true
    }

    return $AppPoolCheck
}

function Global:Get-CheckAppRuntimes {
    <#
        .SYNOPSIS
            This function checks if a site uses multiple application pools.
         .INPUTS
            Site Name
         .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $RuntimeVersions = "Runtimes used by Applications = "
    $AppPools = Get-ChildItem -Path IIS:\AppPools
    foreach ($AppPool in $AppPools) {
       $Apps = Get-WebApplication -Site $SiteName | sort -property ApplicationPool
        foreach ($App in $Apps) {
            if ($App.applicationPool -eq $AppPool.name) {
                $AppPoolName = $AppPool.name
                $RunTimeVersions = $RuntimeVersions + ($AppPool | Get-ItemProperty -Name managedRunTimeVersion).value + ";"
            }
        }
    }

    $CurrentCLR = [System.Reflection.Assembly]::GetExecutingAssembly().ImageRuntimeVersion
    $CurrentFramework =  [System.Reflection.Assembly]::Load("mscorlib").GetName().Version.ToString()
    $RunTimeVersions = $RunTimeVersions + " Current framework version is $CurrentFramework, current CLR version is $CurrentCLR"

    $RuntimesCheck = [ordered]@{
        "Result" = $true
        "Description"= "Information on .NET Runtimes used by IIS applications"
        "Log" = "Found $RuntimeVersions, no issues found"
    }
    $RuntimesCheck
}

function Global:Get-CheckISAPIFilters {
    <#
        .SYNOPSIS
            This function checks if a site uses ISAPI filters.
        .INPUTS
            None
        .OUTPUTS
            Return readiness object
    #>

    $ISAPIFilter = "/system.WebServer/isapiFilters/filter"
    $ISAPIFiltersUsed = Get-WebConfigurationProperty -filter $ISAPIFilter -name Enabled

    $Result = $true
    $Log = "ISAPI filters found: "

    foreach ($Filter in $ISAPIFiltersUsed) {
        $FilterName = $Filter.ItemXPath | Select-String "name="
        $NonASPFilter = $Filter | Select-String "ASP.Net"
        if ($NonASPFilter) {
            $NonASPFilterLog = $NonASPFilterLog + $NonASPFilter + " "
        }
        $Log = $Log + $FilterName + " "
    }
    if ($NonASPFilterLog) {
        $Log = $Log + " Detected Non ASP filters : " + $NonASPFilterLog
    }

    $IsapiFiltersCheck = [ordered]@{
        "Result" = $Result
        "Description"= "Show detected ISAPI Filters"
        "Log" = $Log
    }
    $IsapiFiltersCheck
}

function Global:Get-CheckWindowsAuthenticationInWebConfig {
    <#
        .SYNOPSIS
            This function checks if a site uses Windows Authentication - by scanning the web.config
        .INPUTS
            Site name
        .OUTPUTS
            Returns readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $iisPath = "IIS:\Sites\" + $SiteName
    $configFile = Get-WebConfigFile $iisPath
    $match = [regex]::Escape("<authentication mode=`"Windows`">")
    $usingWinAuth = (Get-Content $configFile | %{$_ -match ($match)}) -contains $true

    $Result = $true
    $Log = "No authentication problem found."

    if ($usingWinAuth) {
        $Result = $false
        $Log = "Windows authentication is not supported at this time."
    }

    $AuthBindingsCheck = [ordered]@{
        "Result" = $Result
        "Description"= "Forms of authentication supported"
        "Log" = $Log
    }
    $AuthBindingsCheck
}

function Global:Get-CheckAuthentication {
    <#
        .SYNOPSIS
            This function checks if a site uses Windows Authentication
        .INPUTS
            Site name
        .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $wc = Get-WebConfiguration -filter /system.webServer/security/authentication/windowsAuthentication "IIS:\sites\$SiteName"
    $Result = $true

    if ($wc.enabled) {
        $Result = $false
        $Log = "Windows authentication is not supported at this time."
    } else {
        $Log = "No authentication problem found."
    }

    $AuthBindingsCheck = [ordered]@{
        "Result" = $Result
        "Description"= "Forms of authentication supported"
        "Log" = $Log
    }
    $AuthBindingsCheck
}

function Global:Get-CheckHTTPPortBindings {
    <#
        .SYNOPSIS
            This function checks HTTP port bindings for a site
        .INPUTS
            Site Name
        .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $Result = $true
    $HTTPPortBinding = $false
    $HTTPSPortBinding = $false
    $WebBindingInfo = Get-WebBinding $SiteName

    foreach ($PortBinding in $WebBindingInfo) {
        if ($PortBinding.protocol -eq 'http') {
            if ( $HTTPPortBinding ) {
                $Result = $false
            }
            $HTTPPortBinding = $true
        }
        if ($portBinding.protocol -eq 'https') {
            if ( $HTTPSPortBinding ) {
                $Result = $false
            }
            $HTTPSPortBinding = $true
        }
    }

    if ($Result) {
        $log = "No issues found"
    } else {
        $log = "Found more than one HTTP and/or HTTPS port, only one port per protocol is supported"
    }

    $PortBindingsCheck = [ordered]@{
        "Result" = $Result
        "Description"= "Check HTTP port bindings"
        "Log" = $log
    }
    $PortBindingsCheck
}

function Global:Get-CheckAppProtocols {
    <#
        .SYNOPSIS
            This function checks app protocols for a site
        .INPUTS
            Site Name
        .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $DetectNonHTTPProt = $false
    $NonHTTPProtStr = ""
    $Result = $true

    foreach ($site in Get-WebSite) {
        if ($site.name -eq $SiteName) {
            break
        }
    }

    foreach ($Prot in $site.bindings.protocol) {
        if ($Prot -ne "http" -and $Prot -ne "https") {
            $DetectNonHTTPProt = $true
            if ($NonHTTPProtStr) {
                $NonHTTPProtStr = $NonHTTPProtStr + "," + $Prot
            } else {
                $NonHTTPProtStr = $Prot
            }
        }
    }
    if ($DetectNonHTTPProt) {
        $log = "Detected non HTTP protocols: $NonHTTPProtStr, they will not be migrated to EB"
        $Result = $false
    } else {
        $log = "Detected HTTP protocol"
    }

    $ProtocolsCheck = [ordered]@{
        "Result" = $Result
        "Description"= "Show detected network protocols, non HTTP protocols cannot be migrated"
        "Log" = $log
    }
    $ProtocolsCheck
}

function Global:Get-CheckAppProcessModelIdentity {
    <#
        .SYNOPSIS
            This function checks permissions of application process.
        .INPUTS
            Site Name
        .OUTPUTS
            Return readiness object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $NumAppsPerPool = 0
    $Apps = Get-WebApplication -Site $SiteName | sort -property ApplicationPool
    $Count = 0
    $Result = $true
    $Log = ""
    $Apps = Get-WebApplication -Site $SiteName | sort -property ApplicationPool
    foreach ( $AppPool in Get-ChildItem IIS:\AppPools) {
        foreach ($App in $Apps) {
            if ($App.applicationPool -ne $AppPool.name) {
                continue
            }
            $DotNetPools = $AppPool.name | Select-String ".NET"
            if ($DotNetPools) {
                continue
            }
            $IdentityType = $AppPool.processModel.identityType
            if (($IdentityType-eq "ApplicationPoolIdentity") -or ($IdentityType.processModel.identityType -eq "LocalService") -or ($IdentityType.processModel.identityType -eq "LocalSystem")) {
                $Result = $true
                if ($Log) {
                    $Log = $Log + " ; Application Pool $($AppPool.name) runs in increased privilege $IdentityType"
                } else {
                    $Log = "Application Pool $($AppPool.name) runs in increased privilege $IdentityType"
                }
            }
        }
    }

    $AppPoolIdentityCheck = [ordered]@{
        "Description"= "Show detected IIS application pool identities, see https://docs.microsoft.com/en-us/iis/configuration/system.applicationhost/applicationpools/add/processmodel#configuration"
        "Result" = $Result
        "Log" = $log
    }
    $AppPoolIdentityCheck
}

function Global:New-ReadinessReport {
    <#
        .SYNOPSIS
            This function creates an readiness report to check for IIS migratability to EB.
        .INPUTS
            Site Name
        .OUTPUTS
            JSON output containing report
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SiteName
    )

    $Uuid = $MigrationRunID
    $ReportTime = Get-Date -format r

    $AppPoolCheck = Get-CheckAppPool $SiteName
    $AppRuntimesCheck = Get-CheckAppRuntimes $SiteName
    $PortBindingsCheck = Get-CheckHTTPPortBindings $SiteName
    $AuthSettingCheck = Get-CheckAuthentication $SiteName
    $ProtCheck = Get-CheckAppProtocols $SiteName
    $ISAPICheck = Get-CheckISAPIFilters
    $AppPoolIdentityCheck = Get-CheckAppProcessModelIdentity $SiteName
    $ChecksList = $AppPoolCheck, $AppRuntimesCheck, $PortBindingsCheck, $AuthSettingCheck, $ProtCheck, $ISAPICheck, $AppPoolIdentityCheck

    $report = [ordered]@{
        "SiteName" = $SiteName
        "SessionGUID" = $Uuid
        "ReportTime" = $ReportTime
        "Checks" = $ChecksList
    }
    $report
}

function Global:Test-DBConnection {
    <#
    .SYNOPSIS
        This function tests validity of the given SQL connection string.
        This function can be invoked after DB migration has been done to AWS cloud instances.
    .INPUTS
        Connection string of SQL Server.
    .OUTPUTS
        True or throws an error otherwise
    .EXAMPLE
        Test-DBConnectionString <connection string>
        <Connection string can be of the form "Server=52.87.223.45;Database=nopcommerce;User Id=sa;Password=test@123">
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ConnStr
    )

    $SqlConn = New-Object System.Data.SqlClient.SqlConnection

    try {
        $SqlConn.ConnectionString = $ConnStr
        if ($SqlConn.Open()) {
           $sqlConn.Close()
        }
    } catch {
        $lastExceptionMessage = $error[0].Exception.Message
        New-Message $DebugMsg $lastExceptionMessage $MigrationRunLogFile
        return $false
    }

    return $true
}

function Global:Update-DBConnectionString {
    <#
    .SYNOPSIS
        This function replaces all occurrances of a string (exact match) within a file with the input replacement string
    .INPUTS
        1. Physical path of the file
        2. Connection string to be replaced
        3. New sonnection string
    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $OldString,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $NewString
    )

    Verify-PathExists $FilePath

    $file = Get-Item $FilePath
    $pattern = [regex]::Escape($OldString)

    (Get-Content $file.FullName ) | Foreach-Object { $_ -replace $pattern, $NewString } | Set-Content $file.FullName
}

function Global:Get-DBConnectionStrings {
    <#
    .SYNOPSIS
        This function reads the database connection strings from the website's Web.config file
        If there is no output, the website either doesn't have a database or stores the connection strings in some non-standard ways
    .INPUTS
        The name of the website
    .OUTPUTS
        An array of XML elements of {name, connectionString, providerName}, or a string if configSource is found.
    .EXAMPLE
        Get-DBConnectionStrings MyWebsiteName

        Sample output:
        name                  connectionString
        ----                  ----------------
        myConnectionString    server=localhost;database=myDb;uid=myUser;password=myPass;
        SitefinityConn        data source=ABC;Integrated Security=SSPI;initial catalog=xyz;Backend=mssql
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Name
    )

    $iisPath = "IIS:\Sites\" + $Name
    $configFile = Get-WebConfigFile $iisPath
    [XML] $configXML = Get-Content $configFile
    $configSource = $configXML.configuration.connectionStrings.configSource
    if ($configSource) {
        return "Connection string config file detected: [Site_Root]\$configSource"
    }
    [Array] $configXML.configuration.connectionStrings.add
}

function Global:Get-PossibleDBConnStrings {
    <#
    .SYNOPSIS
        This function searches database connection strings from the website's physical directory.
        If there is no output, the website either doesn't have a database or stores the connection strings in some non-standard ways
    .INPUTS
        Physical path of website.
    .OUTPUTS
        Connection strings that were found.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PhysPathName
    )

    $connStrPatterns = "DataSource=.*UserId=.*Password=.*",
                        "Server=.*Database=.*",
                        "User ID=.*Password=.*Host=.*Port=.*Database=.*Pooling=.*Min Pool Size=.*Max Pool Size=.*Connection Lifetime=.*",
                        "Provider=.*Data Source=.*location=.*User ID=.*password=.*timeout=.*",
                        "Server=.*Database=.*Uid=.*Pwd=.*",
                        "Database=.*Protocol=.*User Id=.*Password=.*",
                        "Provider=.*User Id=.*Password=.*",
                        "Provider=.*Data Source=.*",
                        "Provider=.*OledbKey1=.*OledbKey2=.*",
                        "Data Source=.*User ID=.*Password=.*",
                        "Data Source=.*Version=.*",
                        "Data Source=.*Persist Security Info=.*",
                        "Server=.*User ID=.*Password=.*Trusted_Connection=.*Encrypt=.*",
                        "Data Source=.*Integrated Security=.*"

    $connStrings = Get-ChildItem -Path $PhysPathName -Recurse -exclude "*.exe","*.dll" | Select-String -Pattern $connStrPatterns

    return $connStrings
}

function Global:New-CustomDeploymentFile ($TemplateFileName, $DestFolderPath, $WebsiteName, $Password) {
    # replace all "{REPLACE_WITH_WEBSITE_NAME}"s in the template with website name, and generate a new file in the dest folder

    $templatesFolderPath = Join-Path $runDirectory "utils\templates"
    $templateFilePath = Join-Path $templatesFolderPath $TemplateFileName

    Verify-PathExists $templateFilePath
    Verify-PathExists $DestFolderPath
    Verify-WebsiteExists $WebsiteName

    $templateFileContent = Get-Content $templateFilePath
    $updatedFileContent = $templateFileContent -replace "{REPLACE_WITH_WEBSITE_NAME}", $WebsiteName

    if ($Password) {
        $updatedFileContent = $updatedFileContent -replace "{REPLACE_WITH_PASSWORD}", $Password
    }

    $newFile = New-File $DestFolderPath $TemplateFileName $True
    $updatedFileContent | Out-File $newFile
}

function Global:ConvertTo-EBApplicationFolder {
    <#
        .SYNOPSIS
            This function takes the folder that contains (only) the msDeploy source bundle zip
            and creates folders & scripts under it to make it EB deployment compatible

            File structure of the original folder:

                eb-app-bundle/
                    source_bundle.zip

            The file structure after calling this function:

                eb-app-bundle/
                    .ebextensions/
                        (empty folder)
                    aws-windows-deployment-manifest.json
                    scripts/
                        site_install.ps1
                        site_post_install.ps1
                        site_restart.ps1
                        site_uninstall.ps1
                    source_bundle.zip

            You can then add additional scripts in .ebextensions/ folder for custom configurations

        .INPUTS
            1. Full physical path of the target folder
            2. Name of the website
            3. Password for msDeploy usage
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FolderPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $WebsiteName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Password
    )

    Verify-PathExists $FolderPath
    Verify-WebsiteExists $WebsiteName

    New-Folder $FolderPath ".ebextensions" $False
    $scriptsPath = New-Folder $FolderPath "scripts" $True

    New-CustomDeploymentFile "aws-windows-deployment-manifest.json" $FolderPath $WebsiteName
    New-CustomDeploymentFile "site_install.ps1" $scriptsPath $WebsiteName $Password
    New-CustomDeploymentFile "site_post_install.ps1" $scriptsPath $WebsiteName
    New-CustomDeploymentFile "site_restart.ps1" $scriptsPath $WebsiteName
    New-CustomDeploymentFile "site_uninstall.ps1" $scriptsPath $WebsiteName
}

function Global:Generate-EBApplicationBundle {
    <#
        .SYNOPSIS
            This function zips up the folder converted by ConvertTo-EBApplicationFolder to generate a app bundle zip file ready for EB deployment
        .INPUTS
            Full physical path of the folder to zip up
        .OUTPUTS
            Full physical path of the output zip file
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $EBAppFolder
    )

    Verify-PathExists $EBAppFolder

    $parentFolder = Split-Path $EBAppFolder -Parent
    $ebAppFolderName = Split-Path $EBAppFolder -Leaf
    $ebAppPackageName = $ebAppFolderName + ".zip"
    $ebAppPackagePath = Join-Path $parentFolder $ebAppFolderName

    Get-ZippedFolder $EBAppFolder $parentFolder $ebAppPackageName

    $ebAppPackagePath
}

function Global:Add-EBExtensionFileToFolder {
    <#
        .SYNOPSIS
            This function copies the input file to the ".ebextensions" folder under an EB application folder
        .INPUTS
            1. Full physical path of the input file
            2. Full physical path of the EB application folder
        .OUTPUTS
            None - will throw exception when execution fails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $EBAppFolderPath
    )

    $ebExtensionsFolderPath = Join-Path $EBAppFolderPath ".ebextensions"

    Verify-PathExists $FilePath
    Verify-PathExists $EBAppFolderPath
    Verify-PathExists $ebExtensionsFolderPath

    Copy-Item $FilePath -Destination $ebExtensionsFolderPath
}

function Global:Add-IISHardeningSettings {
    <#
        .SYNOPSIS
            This function adds IIS hardening settings to the EB application folder
        .INPUTS
            Full physical path of the EB application folder
        .OUTPUTS
            None - will throw exception when execution fails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $EBAppFolderPath
    )

    Verify-PathExists $EBAppFolderPath

    $iisHardeningConfig = Join-Path $runDirectory "utils\templates\iis_hardening.config"
    $iisHardeningScript = Join-Path $runDirectory "utils\templates\harden_iis.ps1"

    Add-EBExtensionFileToFolder $iisHardeningConfig $EBAppFolderPath
    Add-EBExtensionFileToFolder $iisHardeningScript $EBAppFolderPath
}

function Global:Generate-MSDeploySourceBundle {
    <#
    .SYNOPSIS
        This function uses Web Deploy to package a website (using appHostConfig provider) into a zip file (source_bundle.zip)
    .INPUTS
        1. Name of the website (as it appears in IIS)
        2. Full physical path of an empty folder to generate the zip file in
        3. EncryptPassword for SSL certificate migration
        4. Full physical path to an existing file that stores msDeploy run logs (stdout)
        5. Full physical path to an existing file that stores msDeploy run logs (stderr)
    .OUTPUTS
        The script returns the full physical path to the generated zip file
    .EXAMPLE
        Generate-MSDeploySourceBundle "NopCommerce" "C:\dest\out" $password "C:\dest\stdout.log" "C:\dest\stderr.log"
    .NOTES
        Please make 2 new & empty log files for this function's use ONLY.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $WebsiteName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DestinationFolderPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $EncryptPassword,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $StdOutLogFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $StdErrLogFilePath
    )

    Verify-FolderExistsAndEmpty $DestinationFolderPath
    Verify-WebsiteExists $WebsiteName
    Verify-PathExists $StdOutLogFilePath
    Verify-PathExists $StdErrLogFilePath

    $SourceBundleName = "source_bundle.zip"
    $sourceBundlePath = Join-Path $DestinationFolderPath $SourceBundleName

    $msDeployVerb = "-verb:sync"
    $msDeploySource = "-source:appHostConfig='$WebsiteName'"
    $msDeployDest = "-dest:package='$sourceBundlePath',encryptPassword='$EncryptPassword'"
    $msDeployEnableAppPoolExt = "-enableLink:AppPoolExtension"
    $msDeployAppPool = "-declareParam:name='Application Pool',defaultValue='Default Web Site',description='Application pool for this site',kind=DeploymentObjectAttribute,scope=appHostConfig,match='application/@applicationPool'"

    [String[]] $msDeployArgs = @(
      $msDeployVerb,
      $msDeploySource,
      $msDeployDest,
      $msDeployEnableAppPoolExt,
      $msDeployAppPool
    )

    $msDeployExe = Get-WebDeployV3Exe
    $process = Start-Process $msDeployExe -ArgumentList $msDeployArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $StdOutLogFilePath -RedirectStandardError $StdErrLogFilePath

    if ($process.ExitCode -ne 0) {
        throw "ERROR: Failed to package source bundle for website $WebsiteName."
    }

    $sourceBundlePath
}

function Global:Remove-SSLCertificate($pathToUnzippedSourceBundle) {
    $archiveXMLPath = Join-Path $pathToUnzippedSourceBundle "archive.xml"
    Verify-PathExists $archiveXMLPath

    $nodeToRemove = "//httpCert"
    [xml]$archiveXML = Get-Content $archiveXMLPath

    $node = $archiveXML.SelectSingleNode($nodeToRemove)
    while ($node -ne $null) {
        $node.ParentNode.RemoveChild($node) | Out-Null
        $node = $archiveXML.SelectSingleNode($nodeToRemove)
    }
    $archiveXML.save($archiveXMLPath)
}

function Global:Verify-UserHasRequiredAWSPolicies {
    <#
        .SYNOPSIS
            This function verifies that the current AWS user has the following AWS managed policies:
                1. IAMReadOnlyAccess (only needed for Get-IAMAttachedUserPolicyList)
                2. AWSElasticBeanstalkFullAccess (needed for EB application deployment operations)
        .INPUTS
            None
        .OUTPUTS
            None
    #>

    try {
        $stsIdentity = Get-STSCallerIdentity
        $userName = $stsIdentity.Arn.Split("/")[-1]
        $policies = Get-IAMAttachedUserPolicyList -UserName $userName
    } catch {
        throw "ERROR: Please make sure that your AWS credentials are correct, and the AWS managed policy IAMReadOnlyAccess is attached to the current user"
    }

    foreach ($policy in $policies) {
        if ($policy.PolicyName -eq "AWSElasticBeanstalkFullAccess") {
            return
        }
    }
    throw "ERROR: Please make sure that the AWS managed policy AWSElasticBeanstalkFullAccess is attached to the current user"    
}

function Global:Verify-RequiredRolesExist {
    <#
        .SYNOPSIS
            This function checks if the required IAM roles exists (aws-elasticbeanstalk-ec2-role, aws-elasticbeanstalk-service-role)
        .INPUTS
            None
        .OUTPUTS
            None
    #>
    try {
        Get-IAMInstanceProfile -InstanceProfileName $DefaultElasticBeanstalkInstanceProfileName | Out-Null 
    } catch {
        New-Message $InfoMsg "Default Elastic Beanstalk instance profile $DefaultElasticBeanstalkInstanceProfileName was not found." $MigrationRunLogFile
        New-Message $InfoMsg "Creating IAM role $DefaultElasticBeanstalkInstanceProfileName." $MigrationRunLogFile
        New-IAMRole -RoleName $DefaultElasticBeanstalkInstanceProfileName -AssumeRolePolicyDocument $(Get-Content -raw 'utils\iam_trust_relationship_ec2.json')
        Register-IAMRolePolicy -RoleName $DefaultElasticBeanstalkInstanceProfileName -PolicyArn 'arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier'
        Register-IAMRolePolicy -RoleName $DefaultElasticBeanstalkInstanceProfileName -PolicyArn 'arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier'
        Register-IAMRolePolicy -RoleName $DefaultElasticBeanstalkInstanceProfileName -PolicyArn 'arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker' 
        New-Message $InfoMsg "Created IAM role $DefaultElasticBeanstalkInstanceProfileName." $MigrationRunLogFile
        New-Message $InfoMsg "Creating instance profile $DefaultElasticBeanstalkInstanceProfileName." $MigrationRunLogFile
        New-IAMInstanceProfile -InstanceProfileName $DefaultElasticBeanstalkInstanceProfileName
        Add-IAMRoleToInstanceProfile -InstanceProfileName $DefaultElasticBeanstalkInstanceProfileName -RoleName $DefaultElasticBeanstalkInstanceProfileName
        New-Message $InfoMsg "Created Elastic Beanstalk instance profile $DefaultElasticBeanstalkInstanceProfileName." $MigrationRunLogFile
    }
    try {
        Get-IAMRole -RoleName $DefaultElasticBeanstalkServiceRoleName | Out-Null
    } catch {
        New-Message $InfoMsg "Default Elastic Beanstalk service role $DefaultElasticBeanstalkServiceRoleName was not found." $MigrationRunLogFile
        New-Message $InfoMsg "Creating IAM role $DefaultElasticBeanstalkServiceRoleName." $MigrationRunLogFile
        New-IAMRole -roleName $DefaultElasticBeanstalkServiceRoleName -AssumeRolePolicyDocument $(Get-Content -raw 'utils\iam_trust_relationship_eb.json')
        Register-IAMRolePolicy -RoleName $DefaultElasticBeanstalkServiceRoleName -PolicyArn 'arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService'
        Register-IAMRolePolicy -RoleName $DefaultElasticBeanstalkServiceRoleName -PolicyArn 'arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth'
        New-Message $InfoMsg "Created IAM role $DefaultElasticBeanstalkServiceRoleName." $MigrationRunLogFile
    }
}

function Global:Verify-CanCreateNewEIP {
    <#
        .SYNOPSIS
            This function verifies if a new elastic IP can be created in the current AWS region.
            This function will attempt to create a new EIP and delete it immidiately.
        .INPUTS
            None
        .OUTPUTS
            None
    #>

    $deleteEIP = $False
    try {
        $tmpEIP = New-EC2Address
        $deleteEIP = $True
    } catch {
        throw "ERROR: Unable to create new elastic IP. Please check the EIP reource limit in the selected AWS region."
    } finally {
        if ($deleteEIP) {
            Remove-EC2Address -Force -AllocationId $tmpEIP.AllocationId
        }
    }
}

function Global:Get-CurrentAWSAccountID {
    <#
        .SYNOPSIS
            This function returns the ID of the current AWS account
        .INPUTS
            None
        .OUTPUTS
            AWS Account ID
    #>

    $stsIdentity = Get-STSCallerIdentity
    $stsIdentity.Account
}

function Global:New-TempS3Bucket {
    <#
        .SYNOPSIS
            This function creates a new S3 bucket
        .INPUTS
            1. S3 bucket region
        .OUTPUTS
            Bucket name
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketRegion
    )

    $awsID = Get-CurrentAWSAccountID
    $bucketName = "elastic-beanstalk-migration-" + $awsID + "-" + $(Get-Date -f yyyyMMddHHmmss)
    $null = New-S3Bucket -BucketName $bucketName -Region $BucketRegion -CannedACLName Private | Out-File -append $ItemCreationLogFile
    $null = Set-S3BucketEncryption -Region $BucketRegion -BucketName $bucketName -ServerSideEncryptionConfiguration_ServerSideEncryptionRule @{ServerSideEncryptionByDefault = @{ServerSideEncryptionAlgorithm = "AES256" } }
    Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
        $result = Get-S3ACL -Bucketname $bucketName
    }
    foreach ($grant in $result.Grants)
    {
        if ($grant.Grantee.URI -eq "http://acs.amazonaws.com/groups/global/AllUsers")
        {
            Write-Host "Error: S3 bucket '$bucketName' has public access."
            Delete-TempS3Bucket $bucketName
            Exit-WithError
        }
    }
    $bucketName
}

function Global:Delete-TempS3Bucket {
    <#
        .SYNOPSIS
            This function deletes an S3 bucket
        .INPUTS
            1. S3 bucket name
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketName
    )

    Remove-S3Bucket -BucketName $BucketName -DeleteBucketContent -Force
}

function Global:Upload-FileToS3Bucket {
    <#
        .SYNOPSIS
            This function puts a file into a S3 bucket, giving the bucket owner full control
        .INPUTS
            1. Full physical path of the file
            2. S3 bucket name
            3. S3 bucket region
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketRegion
    )

    Verify-PathExists $FilePath
    if (-Not (Test-S3Bucket -BucketName $BucketName)) {
        throw "ERROR: S3 bucket $BucketName does not exist"
    }
    Write-S3Object -BucketName $BucketName -File $FilePath -CannedACLName "bucket-owner-full-control" -Region $BucketRegion
}

function Global:Get-S3ObjectURL {
    <#
        .SYNOPSIS
            This function gets
        .INPUTS
            1. S3 bucket name
            1. S3 object name
            1. S3 bucket region
        .OUTPUTS
            URL of the object
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ObjectName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $BucketRegion
    )
    $obj = Get-S3Object -BucketName $BucketName -Key $ObjectName -Region $BucketRegion
    if (-Not $obj) {
        throw "ERROR: unable to find object $ObjectName"
    }

    "https://s3-$BucketRegion.amazonaws.com/$BucketName/$ObjectName"
}

function Global:Validate-NumberedListUserInput {
    <#
        .SYNOPSIS
            This function validates that the user has entered a number in a valid range
        .INPUTS
            1. User input 
            2. Lower bound
            3. Upper bound
        .OUTPUTS
            None
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $UserInput,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $LowerBound,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Int]
        $UpperBound
    )

    if (($UserInput -lt $LowerBound) -or ($UserInput -gt $UpperBound)) {
        throw "Please enter a number in the list range."
    }
}

function Global:Validate-PowerShellArchitecture {
    <#
        .SYNOPSIS
            This function validates that the PowerShell process architecture matches the IIS and OS architecture

        .OUTPUTS
            None
    #>

    if ([System.Environment]::is64BitOperatingSystem -ne [System.Environment]::Is64BitProcess){
        if ([System.Environment]::is64BitOperatingSystem){
            Write-Host "Run the migration assistant using 64-bit PowerShell [Windows PowerShell] and not 32-bit PowerShell [Windows PowerShell (x86)]."
        }
        else {
            Write-Host "Run the migration assistant using 32-bit PowerShell [Windows PowerShell (x86)]."
        }
        Exit-WithError
    }
}

Validate-PowerShellArchitecture

$Global:Version = "0.2" # must be exactly 3 characters long otherwise it breaks title display
$Global:runDirectory = $PSScriptRoot
$Global:ebAppBundleFileSizeLimit = 512mb
$Global:MigrationRunId = "run-" + $(Get-Date -f yyyyMMddHHmmss)

# load custom migration run settings
$settings = Get-Content -Raw -Path "$runDirectory\utils\settings.txt" | ConvertFrom-Json

$Global:DisplayTimestampsInConsole = [boolean]::Parse($settings.displayTimestampsInConsole)

$Global:DefaultAwsProfileFileLocation = $settings.defaultAwsProfileFileLocation
$Global:DefaultAwsProfileName = $settings.defaultAwsProfileName
$Global:IgnoreMigrationReadinessWarnings = [boolean]::Parse($settings.ignoreMigrationReadinessWarnings)
$Global:DeleteTempS3Buckets = [boolean]::Parse($settings.deleteTempS3Buckets)

Import-Module AWSPowerShell
Import-Module WebAdministration
Add-Type -Assembly System.IO.Compression.FileSystem
Setup-Workspace                                     # set up global variables
Setup-NewMigrationRun $MigrationRunId               # new migration run every time

Write-Host " "
New-Message $InfoMsg " -----------------------------------------" $MigrationRunLogFile
New-Message $InfoMsg "|                                         |" $MigrationRunLogFile
New-Message $InfoMsg "| AWS Web Application Migration Assistant |" $MigrationRunLogFile
New-Message $InfoMsg "|                                    v$Version |" $MigrationRunLogFile
New-Message $InfoMsg " -----------------------------------------`n" $MigrationRunLogFile

New-Message $InfoMsg "Starting new migration run: $MigrationRunId" $MigrationRunLogFile
New-Message $InfoMsg "Logs for this migration run can be found at" $MigrationRunLogFile
New-Message $InfoMsg "    $LogFolderPath" $MigrationRunLogFile

# Dependency Check

New-Message $InfoMsg "Checking for dependencies..." $MigrationRunLogFile
$missingDependencyString = Get-MissingDependencies

if ($missingDependencyString) {
    New-Message $FatalMsg "Missing dependencies found. Be sure the following items are installed on this server:" $MigrationRunLogFile
    New-Message $FatalMsg $missingDependencyString $MigrationRunLogFile
    Exit-WithError
}


New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile


# AWS profile collection

New-Message $InfoMsg "Provide an AWS profile that the migrated application should use." $MigrationRunLogFile

$Global:glb_AwsProfileLocation = $Null
$Global:glb_AwsProfileName = $Null
$Global:DefaultElasticBeanstalkInstanceProfileName = "aws-elasticbeanstalk-ec2-role"
$Global:DefaultElasticBeanstalkServiceRoleName = "aws-elasticbeanstalk-service-role"

if ($DefaultAwsProfileFileLocation) {
    New-Message $InfoMsg "Default AWS profile file detected at '$DefaultAwsProfileFileLocation'." $MigrationRunLogFile
    $glb_AwsProfileLocation = $DefaultAwsProfileFileLocation
} else {
    $glb_AwsProfileLocation = Get-UserInputString $MigrationRunLogFile "Enter file location, for example 'c:\aws\credentials', or press ENTER"
}
if ($DefaultAwsProfileName) {
    New-Message $InfoMsg "Default AWS profile name '$DefaultAwsProfileName' detected." $MigrationRunLogFile
    $glb_AwsProfileName = $DefaultAwsProfileName
} else {
    $glb_AwsProfileName = Get-UserInputString $MigrationRunLogFile "Enter the AWS profile name"
}

$AwsCredsObj = Get-AWSCredentials -ProfileName $glb_AwsProfileName -ProfileLocation $glb_AwsProfileLocation
if ($AwsCredsObj) {
    $AwsCreds = $AwsCredsObj.GetCredentials()
    $accessKey = $AwsCreds.accesskey
    $secretKey = $AwsCreds.secretkey
    if (-Not $accessKey) {
        New-Message $FatalMsg "Error: Invalid AWS access key. Be sure to provide the correct AWS profile." $MigrationRunLogFile
        Exit-WithError
    }
    if (-Not $secretKey) {
        New-Message $FatalMsg "Error: Invalid AWS secret key. Be sure to provide the correct AWS profile." $MigrationRunLogFile
        Exit-WithError
    }
    Set-AWSCredential -AccessKey $accessKey -SecretKey $secretKey
} else {
    New-Message $FatalMsg "Error: Invalid AWS credentials. Be sure to provide the correct AWS profile." $MigrationRunLogFile
    Exit-WithError
}

try {
    # all other AWS verifications go here
    Verify-UserHasRequiredAWSPolicies
    Verify-RequiredRolesExist
} catch {
    $lastExceptionMessage = $error[0].Exception.Message
    New-Message $FatalMsg $lastExceptionMessage $MigrationRunLogFile
    Exit-WithError
}


# Collect AWS region

Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
    New-Message $InfoMsg " " $MigrationRunLogFile
    New-Message $InfoMsg "Enter the AWS Region for your migrated application. For example: us-east-2." $MigrationRunLogFile
    New-Message $InfoMsg "For a list of available AWS Regions, see:" $MigrationRunLogFile
    New-Message $InfoMsg "    https://docs.aws.amazon.com/general/latest/gr/rande.html" $MigrationRunLogFile

    $regionInput = Get-UserInputString $MigrationRunLogFile "Enter the AWS Region [us-east-1]"
    if (!$regionInput) {
       $regionInput = "us-east-1"
    }
    $Global:glb_AwsRegion = Get-AWSRegion $regionInput
    if ($glb_AwsRegion -is [system.array] -or $glb_AwsRegion.name -eq "unknown") {
        Throw "Error: Invalid AWS Region"
    }
}

Set-DefaultAWSRegion $glb_AwsRegion
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile

# Determine the website to migrate

$serverObj = Get-IISServerInfoObject
Write-IISServerInfo $EnvironmentInfoLogFile

$websites = Get-Website
if (-Not $websites) {
    New-Message $FatalMsg "The migration assistant didn't find any website on this server." $MigrationRunLogFile
    Exit-WithError
}

New-Message $InfoMsg "The migration assistant found website(s) on the local server '$($serverObj.computerName)'." $MigrationRunLogFile
$webSiteNum = 1
$webSiteNameTable = @{}
foreach ($site in $websites) {
    $siteEntry = "[$webSiteNum] " + "- " + $site.name
    $webSiteNameTable[$webSiteNum.ToString()] = $site.name
    $webSiteNum = $webSiteNum + 1
    New-Message $InfoMsg $siteEntry $MigrationRunLogFile
}

Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
    $websiteNumStr = Get-UserInputString $MigrationRunLogFile "Enter the number of the website to migrate: [1]"

    if (!$websiteNumStr) {
        $Global:glb_websiteToMigrate = $webSiteNameTable["1"]
    } else {
        $Global:glb_websiteToMigrate = $webSiteNameTable[$websiteNumStr]
    }
    New-Message $InfoMsg "Selected the website '$Global:glb_websiteToMigrate' to migrate from the server '$($serverObj.computerName)'." $MigrationRunLogFile
    Verify-WebsiteExists $glb_websiteToMigrate
}

New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile

# Generate migration readiness report

New-Message $InfoMsg "Analyzing migration readiness..." $MigrationRunLogFile

try {

    $readinessReportFileName = "migration_readiness_report.json"
    $Global:readinessReportFilePath = New-File $CurrentMigrationRunPath $readinessReportFileName $True
    $reportObject = New-ReadinessReport $glb_websiteToMigrate
    $reportObject | ConvertTo-Json | Out-File $readinessReportFilePath

    New-Message $InfoMsg "The migration readiness report is at:" $MigrationRunLogFile
    New-Message $InfoMsg $readinessReportFilePath $MigrationRunLogFile
    New-Message $InfoMsg "Looking for incompatibilities..." $MigrationRunLogFile

    $incompatibilityFound = $False

    foreach ($checkItem in $reportObject.Checks) {
        if (-Not $checkItem.Result) {
            New-Message $ErrorMsg $checkItem.Log $MigrationRunLogFile
            $incompatibilityFound = $True
        }
    }

    if ($incompatibilityFound) {
        New-Message $FatalMsg "The migration assistant found incompatibilities for website '$glb_websiteToMigrate'." $MigrationRunLogFile
        if ($IgnoreMigrationReadinessWarnings) {
            New-Message $InfoMsg "The migration assistant found a custom setting directing it to ignore warnings. Continue the migration?" $MigrationRunLogFile
            $userConsent = Get-UserInputString $MigrationRunLogFile "Press ENTER to continue"
        } else {
            New-Message $InfoMsg "Contact the AWS migration support team for help with preparing the website for migration." $MigrationRunLogFile
            Exit-WithError
        }
    }

} catch {
    New-Message $FatalMsg $_ $MigrationRunLogFile
    New-Message $FatalMsg "The migration assistant is unable to generate a migration readiness report. The website might be unsupported for Elastic Beanstalk migration." $MigrationRunLogFile
    $userInputI = Get-UserInputString $MigrationRunLogFile "Enter 'I' to ignore this warning and continue migration"
    if ($userInputI -eq "I" -or $userInputI -eq "i") {
        New-Message $InfoMsg "Starting the Elastic Beanstalk migration." $MigrationRunLogFile
    } else {
        New-Message $InfoMsg "Contact the AWS migration support team for help on migration readiness." $MigrationRunLogFile
        Exit-WithError
    }
}

New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile


# Back up the website

$appBundleFolderName = "EB-Application"
$appBundleFolderPath = New-Folder $CurrentMigrationRunPath $appBundleFolderName $True
$msDeployStdOutLog = New-File $LogFolderPath "msDeployStdOut.log" $True
$msDeployStdErrLog = New-File $LogFolderPath "msDeployStdErr.log" $True

New-Message $InfoMsg "Taking a snapshot of the website... This might take a few minutes." $MigrationRunLogFile
$encryptPassword = Get-RandomPassword

try {
    $msDeployZipPath = Generate-MSDeploySourceBundle $glb_websiteToMigrate $appBundleFolderPath $encryptPassword $msDeployStdOutLog $msDeployStdErrLog
    $Global:siteFolder = New-Folder $appBundleFolderPath "site_content" $True
    Unzip-Folder $msDeployZipPath $siteFolder
    Delete-Item $msDeployZipPath
    Remove-SSLCertificate $siteFolder
} catch {
    New-Message $ErrorMsg "Error generating a website snapshot. For troubleshooting instructions, see the Readme document of the migration assistant GitHub repository or contact AWS migration support team." $MigrationRunLogFile
    New-Message $FatalMsg $error[0].Exception.Message $MigrationRunLogFile
    Exit-WithError
}


# Collect & list possible connection strings

New-Message $InfoMsg " " $MigrationRunLogFile
New-Message $InfoMsg "Automatically discovering possible connection strings... This might take a few minutes." $MigrationRunLogFile
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile
New-Message $InfoMsg " " $MigrationRunLogFile

$standardConnStrings = Get-DBConnectionStrings $glb_websiteToMigrate
$possibleConnStrings = Get-PossibleDBConnStrings $siteFolder

$connStringsTable = @{ }
$connStringsNum = 1
if ($standardConnStrings) {
    if ($standardConnStrings -is [system.array]) {
        foreach ($connStr in $standardConnStrings) {
            $LogMsg = "Discovered connection string in location : $($connStr.Path) :"
            New-Message $InfoMsg $LogMsg $MigrationRunLogFile
            $connStringsTable[$connStringsNum] = $connStr
            $connStr= $connStr.Line
            $connStr = $connStr.TrimStart()
            $connStringsNum = $connStringsNum + 1
            $LogMsg = "[" + $connStringsNum + "] : " + $string
            New-Message $ConsoleOnlyMsg $LogMsg $MigrationRunLogFile
            New-Message $InfoMsg " " $MigrationRunLogFile
        }
    } else {
        New-Message $InfoMsg $standardConnStrings $MigrationRunLogFile
        New-Message $InfoMsg " " $MigrationRunLogFile
    }
}

if ($possibleConnStrings) {
    if ($possibleConnStrings -is [system.array]) {
        foreach ($connStr in $possibleConnStrings) {
            $connStringsTable[$connStringsNum] = $connStr
            $LogMsg = "Discovered connection string in location : $($connStr.Path)"
            $connStr = $connStr.Line
            $connStr = $connStr.TrimStart()
            New-Message $InfoMsg $LogMsg $MigrationRunLogFile
            $LogMsg = "[" + $connStringsNum + "] : " + $connStr
            New-Message $ConsoleOnlyMsg $LogMsg $MigrationRunLogFile
            New-Message $InfoMsg " " $MigrationRunLogFile
            $connStringsNum = $connStringsNum + 1
        }
    } else {
        New-Message $InfoMsg $possibleConnStrings $MigrationRunLogFile
        New-Message $InfoMsg " " $MigrationRunLogFile
    }
}

if ((-Not $standardConnStrings) -and (-Not $possibleConnStrings)) {
    New-Message $InfoMsg "The migration assistant didn't find any connection strings." $MigrationRunLogFile
}
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile


# Collect connection strings from user

$canAutoUpdateConnectionStrings = $True
$connectionStringNumber = 1
$connectionStringMatches = @{}
while ($True) {
    $userInputConnectionStringNum = Get-SensitiveUserInputString $MigrationRunLogFile "Enter the number of the connection string you would like to update, or press ENTER"
    if (!$userInputConnectionStringNum) {
        break
    }
    $userInputString = $connStringsTable[[int]$userInputConnectionStringNum].Line

    if (!$userInputString) {
        break
    } else {
        New-Message $InfoMsg "Looking for this connection string in the site directory..." $MigrationRunLogFile
        $matchedStrings = Get-ChildItem -Path $siteFolder -Recurse -exclude "*.exe","*.dll" | Select-String -Pattern $userInputString -SimpleMatch
        if (-Not $matchedStrings) {
            New-Message $ErrorMsg "The migration assistant couldn't find this connection string in the project." $MigrationRunLogFile
            $userInputY = Get-UserInputString $MigrationRunLogFile "Enter 'Y' to keep it on record (you will need to manually replace the connection strings), or anything else to re-enter the string"
            if ($userInputY -eq "Y" -or $userInputY -eq "y") {
                continue
            }
            $canAutoUpdateConnectionStrings = $False
        }
        $matchList = @()
        foreach ($match in $matchedStrings) {
            $matchList += $match
        }
        $connectionStringMatches.Add($userInputString, $matchList)
        $connectionStringNumber += 1
    }
}
$connectionStringNumber -= 1
New-Message $InfoMsg " " $MigrationRunLogFile
New-Message $InfoMsg "Done. Collected $connectionStringNumber connection strings to update." $MigrationRunLogFile
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile


# DB migration script integration

if ($connectionStringMatches.Count -ne 0) {

    New-Message $InfoMsg "Migrate your database separately, if needed" $MigrationRunLogFile
    $userInputEnter = Get-UserInputString $MigrationRunLogFile "Press ENTER to continue to the next step"
    New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile
    $userInputEnter = New-Message $InfoMsg "Continuing with connection string update..." $MigrationRunLogFile

    # Update the website with user provided connection strings

    $manualReplacement = $False
    if (-Not $canAutoUpdateConnectionStrings) {
        New-Message $InfoMsg "The migration assistant found unidentifiable connection strings." $MigrationRunLogFile
        $manualReplacement = $True
    } else {
        $userInputM = Get-UserInputString $MigrationRunLogFile  "Enter 'M' to manually edit the file containing the connection string, or paste the replacement string [M]"
        if (!$userInputM) {
            $userInputM = "M"
        }
        if ($userInputM -eq "M" -or $userInputM -eq "m") {
            $manualReplacement = $True
        }
    }

    if ($manualReplacement) {
        New-Message $InfoMsg "Update the connection string manually in the following locations:" $MigrationRunLogFile
        foreach ($connStrMatch in $connectionStringMatches.GetEnumerator()) {
                New-Message $InfoMsg $($connStrMatch.Value) $MigrationRunLogFile
        }
        $userInputEnter = Get-UserInputString $MigrationRunLogFile "Press ENTER when you're done"
    } else {
        foreach ($key in $connectionStringMatches.Keys) {
            New-Message $InfoMsg "Provide a replacement connection string for:" $MigrationRunLogFile
            New-Message $ConsoleOnlyMsg "    $key" $MigrationRunLogFile
            Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
                $userInputString = Get-SensitiveUserInputString $MigrationRunLogFile "Enter a new connection string"
                $verified = Test-DBConnection $userInputString
                if (-Not $verified) {
                    New-Message $ErrorMsg "The migration assistant can't verify the connection string. Type `"K`" to keep the connection string anyway." $MigrationRunLogFile
                    $userInputK = Get-UserInputString $MigrationRunLogFile "Press ENTER to retry"
                    if ($userInputK -ne "K" -or $userInputK -ne "k") {
                        throw "Please re-enter the last connection string."
                    }
                }
                $Global:glb_newString = $userInputString
            }
            foreach ($match in $connectionStringMatches.$key) {
                $filePath = $match.Path
                Update-DBConnectionString $filePath $key $glb_newString
            }
            New-Message $InfoMsg "Replaced an old connection string." $MigrationRunLogFile
        }
    }
} else {
    New-Message $InfoMsg "Your application doesn't have a database that needs to be migrated." $MigrationRunLogFile
}
New-Message $InfoMsg "Finished updating the connection string." $MigrationRunLogFile
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile


# Convert to EB application bundle

New-Message $InfoMsg "Converting the website to an Elastic Beanstalk deployment bundle... This might take a few minutes." $MigrationRunLogFile
$outputFolderName = "output"
$ebAppBundleFileName = "eb-application-bundle.zip"

ConvertTo-EBApplicationFolder $appBundleFolderPath $glb_websiteToMigrate $encryptPassword

$iisHardeningDetails = Join-Path $runDirectory "utils\templates\harden_iis.ps1"

# TBD: Add IIS hardening later
#New-Message $InfoMsg "Would you like to perform optional IIS hardening on the Elastic Beanstalk application?" $MigrationRunLogFile
#New-Message $InfoMsg "Review the detailed settings before applying them. They might impact the website's functionality." $MigrationRunLogFile
#New-Message $InfoMsg "The settings can be viewed or modified at:" $MigrationRunLogFile
#New-Message $InfoMsg "    $iisHardeningDetails" $MigrationRunLogFile

#$userInputY = "No"
#$userInputY = Get-UserInputString $MigrationRunLogFile "Enter 'Y' to include IIS hardening settings [N]"
#if ($userInputY -eq "Y" -or $userInputY -eq "y") {
#    Add-IISHardeningSettings $appBundleFolderPath
#    New-Message $InfoMsg "Added IIS hardening settings to the deployment bundle." $MigrationRunLogFile
#} else {
#    New-Message $InfoMsg "IIS hardening settings waren't added." $MigrationRunLogFile
#}

# TBD: Add AD support later
#New-Message $InfoMsg "Would you like to join your Elastic Beanstalk application to an Active Directory?" $MigrationRunLogFile
#New-Message $InfoMsg "For instructions on extending your AD on AWS, see the [Active Directory] section in the Readme document of the migration assistant GitHub repository." $MigrationRunLogFile

#$userInputY = "no"
#$userInputY = Get-UserInputString $MigrationRunLogFile "Enter 'Y' to join the application to Active Directory [N]"
#if ($userInputY -eq "Y" -or $userInputY -eq "y") {
#    $ssmDocName = Get-UserInputString $MigrationRunLogFile "Enter the name of the AD-Joining SSM document"
#    Add-ADJoiningSettings $appBundleFolderPath $ssmDocName
#    New-Message $InfoMsg "Your application is configured to join an Active Directory. Use the advanced deployment mode." $MigrationRunLogFile
#} else {
#    New-Message $InfoMsg "Skipped Active Directory configurations." $MigrationRunLogFile
#}

$outputFolderPath = New-Folder $CurrentMigrationRunPath $outputFolderName $True
$ebAppBundleFile = Get-ZippedFolder $appBundleFolderPath $outputFolderPath $ebAppBundleFileName

New-Message $InfoMsg "An application bundle was successfully generated." $MigrationRunLogFile
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile

$appBundleSize = (Get-Item $ebAppBundleFile).length
if ($appBundleSize -gt $ebAppBundleFileSizeLimit) {
    New-Message $FatalMsg "The application bundle size is too large. Be sure to limit directory size to '$ebAppBundleFileSizeLimit'." $MigrationRunLogFile
    New-Message $InfoMsg "Contact the AWS migration support team to migrate the application." $MigrationRunLogFile
    Exit-WithError
}


# EB Migration

New-Message $InfoMsg "AWS Elastic Beanstalk Deployment" $MigrationRunLogFile
New-Message $InfoMsg "------------------------------------------------------------------------------------------" $MigrationRunLogFile
$s3BucketToCleanUp = $Null

# Basic deployment using AWS PowerShell Toolkit

try {
    Verify-CanCreateNewEIP
} catch {
    New-Message $ErrorMsg "You've reached your Elastic IP address limit. Be sure the number of Elastic IP addresses in AWS Region '$glb_AwsRegion' is below your account's limit." $MigrationRunLogFile
    New-Message $ErrorMsg "For a successful Elastic Beanstalk deployment, you must be able to allocate a new Elastic IP address to your account." $MigrationRunLogFile
    $userConfirmation = Get-UserInputString $MigrationRunLogFile "Press ENTER after resolving this issue"
}

Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
    $Global:glb_ebAppName = Get-UserInputString $MigrationRunLogFile "Enter a unique name for your new Elastic Beanstalk application"
    New-Message $InfoMsg "Creating a new Elastic Beanstalk application..." $MigrationRunLogFile
    New-EBApplication -ApplicationName $glb_ebAppName
}

New-Message $InfoMsg "Elastic Beanstalk supports the following Windows Server versions: " $MigrationRunLogFile
$windowsVersions = @("2012", "2012 R2", "Core 2012 R2", "2016", "Core 2016", "2019", "Core 2019")
$windowsVersionNumber = 1
foreach ($windowsVersion in $windowsVersions) {
    $LogMsg = "[" + $windowsVersionNumber + "] : Windows Server " + $windowsVersion
    New-Message $ConsoleOnlyMsg $LogMsg $MigrationRunLogFile
    $windowsVersionNumber = $windowsVersionNumber + 1
}

$platformNameFilter = New-Object Amazon.ElasticBeanstalk.Model.PlatformFilter -Property @{Operator='contains';Type='PlatformName';Values='Windows Server'}
$platformOwnerFilter = New-Object Amazon.ElasticBeanstalk.Model.PlatformFilter -Property @{Operator='=';Type='PlatformOwner';Values='AWSElasticBeanstalk'}
$platformStatusFilter = New-Object Amazon.ElasticBeanstalk.Model.PlatformFilter -Property @{Operator='=';Type='PlatformStatus';Values='Ready'}
$ebPlatformVersions = Get-EBPlatformVersion -Filter $platformNameFilter,$platformOwnerFilter,$platformStatusFilter

$EBtag = New-Object Amazon.ElasticBeanstalk.Model.Tag
$EBtag.Key = "createdBy"
$EBtag.Value = "MigrateIISWebsiteToElasticBeanstalk.ps1"
$environmentName = $glb_ebAppName + "-env"

Invoke-CommandsWithRetry 99 $MigrationRunLogFile {
    $userInputWindowsVersion =  $windowsVersions[0]

    $userInputWindowsStringNum = Get-UserInputString $MigrationRunLogFile "Enter the number of the Windows version for your Elastic Beanstalk environment [1]"
    if (!$userInputWindowsStringNum){
        $userInputWindowsStringNum = 1
    }
    Validate-NumberedListUserInput $([int]$userInputWindowsStringNum) 1 $windowsVersions.Count
    $userInputWindowsVersion = $windowsVersions[([int]$userInputWindowsStringNum)-1]
    New-Message $InfoMsg " " $MigrationRunLogFile

    foreach ($ebPlatformVersion in $ebPlatformVersions) {
        if ($userInputWindowsVersion -and $($ebPlatformVersion.PlatformArn).contains($userInputWindowsVersion+"/")){
            $platformArn = $ebPlatformVersion.PlatformArn
            break
        }
    }

    $platformArnPrefix = "platform/"
    $userFriendlyEbPlatformVersion = $platformArn.substring($platformArn.IndexOf($platformArnPrefix)+$platformArnPrefix.length)
    New-Message $InfoMsg "The latest Elastic Beanstalk platform for Windows Server $userInputWindowsVersion is: $userFriendlyEbPlatformVersion" $MigrationRunLogFile
    New-Message $InfoMsg "To learn more about Elastic Beanstalk platforms, see:" $MigrationRunLogFile
    New-Message $InfoMsg "    https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html#platforms-supported.net" $MigrationRunLogFile
    New-Message $InfoMsg " " $MigrationRunLogFile

    $instanceType = Get-UserInputString $MigrationRunLogFile "Enter the instance type [t3.medium]"
    if (!$instanceType) {
        $instanceType = "t3.medium"
    }

    New-Message $InfoMsg "Creating a new Elastic Beanstalk environment using platform arn '$platformArn'..." $MigrationRunLogFile
    $instanceProfileOptionSetting = New-Object Amazon.ElasticBeanstalk.Model.ConfigurationOptionSetting -ArgumentList aws:autoscaling:launchconfiguration,IamInstanceProfile,$DefaultElasticBeanstalkInstanceProfileName
    $instanceTypeOptionSetting = New-Object Amazon.ElasticBeanstalk.Model.ConfigurationOptionSetting -ArgumentList aws:autoscaling:launchconfiguration,InstanceType,$instanceType
    $serviceRoleOptionSetting = New-Object Amazon.ElasticBeanstalk.Model.ConfigurationOptionSetting -ArgumentList aws:elasticbeanstalk:environment,ServiceRole,$DefaultElasticBeanstalkServiceRoleName
    $environmentTypeOptionSetting = New-Object Amazon.ElasticBeanstalk.Model.ConfigurationOptionSetting -ArgumentList aws:elasticbeanstalk:environment,EnvironmentType,SingleInstance
    $enhancedHealthReportingOptionSetting = New-Object Amazon.ElasticBeanstalk.Model.ConfigurationOptionSetting -ArgumentList aws:elasticbeanstalk:healthreporting:system,SystemType,enhanced

    $optionSettings = $instanceProfileOptionSetting,$instanceTypeOptionSetting,$serviceRoleOptionSetting,$environmentTypeOptionSetting,$enhancedHealthReportingOptionSetting

    New-EBEnvironment -ApplicationName $glb_ebAppName -EnvironmentName $environmentName -PlatformArn $platformArn -OptionSetting $optionSettings -Tag $EBTag
}

$versionLabel = $MigrationRunId + "-vl"
$ebS3Bucket = New-TempS3Bucket $glb_AwsRegion

$ebS3Key = Split-Path $ebAppBundleFile -Leaf
Upload-FileToS3Bucket $ebAppBundleFile $ebS3Bucket $glb_AwsRegion
New-Message $InfoMsg "Creating a new Elastic Beanstalk application version in application '$glb_ebAppName' with version label '$versionLabel' and S3 bucket '$ebS3Bucket'." $MigrationRunLogFile
New-EBApplicationVersion -ApplicationName $glb_ebAppName -VersionLabel $versionLabel -SourceBundle_S3Bucket $ebS3Bucket -SourceBundle_S3Key $ebS3Key -Tag $EBtag

New-Message $InfoMsg "Updating the Elastic Beanstalk environment... This might take a few minutes." $MigrationRunLogFile
$environmentReady = $False
$waitTime = (Date).AddMinutes(10)
while ((Date) -lt $waitTime) {
    try{
       Update-EBEnvironment -ApplicationName $glb_ebAppName -EnvironmentName $environmentName -VersionLabel $versionLabel
       $environmentReady = $true
       break
    } catch {
       Start-Sleep -Milliseconds 30000 # sleep for 30 seconds
       Append-DotsToLatestMessage 1
    }
}
$env = Get-EBEnvironment -ApplicationName $glb_ebAppName -EnvironmentName $environmentName -Region $glb_AwsRegion
$Global:glb_EBEnvID = $env.EnvironmentId
$s3BucketToCleanUp = $ebS3Bucket

# Post deployment operations

New-Message $InfoMsg "Waiting for the Elastic Beanstalk application to launch... This might take a few minutes." $MigrationRunLogFile
$waitTime = (Date).AddMinutes(30)
$deploymentSucceeded = $False
$firstTimeStatusGreen = $True
while ((Date) -lt $waitTime) {
    $ebEnvironment = Get-EBEnvironment -EnvironmentId $glb_EBEnvID
    $health = $ebEnvironment.Health
    if ($health -eq "Green") {
        if ($firstTimeStatusGreen) {
            # wait one more round when status turns green for the first time
            $firstTimeStatusGreen = $False
        } else {
            $deploymentSucceeded = $True
            break
        }
    } elseif ($health -eq "Red" -or $health -eq "Yellow") {
        $deploymentSucceeded = $False
        break
    }
    # else health = Grey: deployment in process
    Start-Sleep -Milliseconds 30000 # sleep for 30 seconds
    Append-DotsToLatestMessage 1
}

if ($s3BucketToCleanUp -and $DeleteTempS3Buckets) {
    Delete-TempS3Bucket $s3BucketToCleanUp
}

if ($deploymentSucceeded) {
    $ebEnvironment = Get-EBEnvironment -EnvironmentId $glb_EBEnvID
    $applicationURL = $ebEnvironment.EndpointURL
    Write-Host " "
    New-Message $InfoMsg "Note that it might take a few minutes for the application to be ready." $MigrationRunLogFile
    New-Message $InfoMsg "Application URL:" $MigrationRunLogFile
    New-Message $InfoMsg "    $applicationURL" $MigrationRunLogFile
    New-Message $InfoMsg " " $MigrationRunLogFile
    New-Message $InfoMsg "The Elastic Beanstalk deployment succeeded. Your web application is now hosted in AWS at '$applicationURL'." $MigrationRunLogFile
} else {
    New-Message $ErrorMsg "The Elastic Beanstalk deployment failed. You can check the deployment log in the Elastic Beanstalk console." $MigrationRunLogFile
}

Exit-WithoutError
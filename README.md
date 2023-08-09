## Windows Web Application Migration Assistant for AWS Elastic Beanstalk

### Overview
The Windows Web Application Migration Assistant for AWS Elastic Beanstalk is an interactive PowerShell utility that migrates [ASP.NET](https://dotnet.microsoft.com/apps/aspnet) and [ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/?view=aspnetcore-3.1) applications from on-premises IIS Windows servers to Elastic Beanstalk. The migration assistant is able to migrate an entire website and its configuration to Elastic Beanstalk with minimal or no changes to the application. After the assistant migrates the application, Elastic Beanstalk automatically handles the ongoing details of capacity provisioning, load balancing, auto-scaling, application health monitoring, and applying patches and updates to the underlying platform. If you need to also migrate a database associated with your web application, you can separately use [AWS Database Migration Service](https://aws.amazon.com/dms/), [CloudEndure Migration](https://aws.amazon.com/cloudendure-migration/), or the [Windows to Linux Replatforming Assistant for Microsoft SQL Server Databases](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/replatform-sql-server.html).

You can watch a demo video of the migration assistant [here](https://www.youtube.com/watch?v=Q-YnE5EA1-0&feature=youtu.be).

To try out the migration assistant, run the [Migration Tutorial](https://aws.amazon.com/getting-started/hands-on/migrate-aspnet-web-application-elastic-beanstalk/) to migrate a sample ASP.NET website to Elastic Beanstalk.

### Migration Assistant Prerequisites
The migration assistant runs under the Administrator role on the on-premises IIS Windows server. Below is a list of software dependencies for the assistant:

1. Internet Information Services (IIS) version 8.0 or above running on Windows Server 2012 or above
1. [MS PowerShell version 3.0](https://www.microsoft.com/en-us/download/details.aspx?id=34595) or above
1. [Microsoft Web Deploy version 3.6](https://www.iis.net/downloads/microsoft/web-deploy) or above
1. [AWSPowerShell module for MS PowerShell](https://www.powershellgallery.com/packages/AWSPowerShell/3.3.498.0)
1. .NET Framework 4.x, 2.0, 1.x or .NET Core 3.0.0, 2.2.8, 2.1.14
1. WebAdministration module for MS PowerShell. You can check for this dependency by invoking PowerShell command "Import-Module WebAdministration"
1. The server needs full internet access to AWS.

### Setting Up
1. Create a new IAM user (for example, `MigrationUser`) for the Elastic Beanstalk migration using the [AWS IAM console](https://console.aws.amazon.com/iam/home).
1. Attach the following AWS-managed policies to the IAM user: (1) `IAMReadOnlyAccess` (2) `AdministratorAccess-AWSElasticBeanstalk` (3) `AmazonS3FullAccess`. Assign both Programmatic access and AWS Management Console access to the IAM user. Before finishing the user creation, obtain the user's AccessKey and SecretKey from the console. For instructions on creating a new user, see [Creating an IAM User in Your AWS Account](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html) in the *AWS Identity and Access Management User Guide*. Open a PowerShell terminal on your on-premises Windows Server, where the website is hosted, and invoke the following two commands.
    ```
    PS C:\> Import-Module AWSPowerShell
    PS C:\> Set-AWSCredential -AccessKey {access_key_of_the_user} -SecretKey {secret_key_of_the_user} -StoreAs {profile_name} -ProfileLocation {optional - path_to_the_new_profile_file}
    ```
    The parameter `{profile_name}` refers to the IAM user, and the optional parameter `{path_to_the_new_profile_file}` refers to the full physical path of the new profile file.
For CLI reference, see [AWS Tools for PowerShell](https://aws.amazon.com/powershell/).
1. On GitHub, use the **Clone or download** menu to either clone this repository or download a ZIP bundle of it and extract the ZIP file. Place the migration assistant on the local server, in a new folder on a disk that has more than 1 GB free space.
1. [Optional] Edit the `settings.txt` JSON file, and set the following 2 variables: (1) `defaultAwsProfileFileLocation : {path_to_the_new_profile_file}` (2) `defaultAwsProfileName : {profile_name}`
1. If you have a database associated with your application, you can migrate it before migrating the web application using [AWS Database Migration Service](https://aws.amazon.com/dms/), [CloudEndure Migration](https://aws.amazon.com/cloudendure-migration/), or the [Windows to Linux Replatforming Assistant for Microsoft SQL Server Databases](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/replatform-sql-server.html).  

### Application Migration Workflow
Here's an overview of the migration assistant's workflow:

1. Discover local websites.
1. Select site to migrate.
1. Discover database connection strings.
1. Update database connection strings.
1. Generate Elastic Beanstalk deployment bundle.
1. Deploy application to Elastic Beanstalk.

### Running the Migration Assistant
Open a PowerShell terminal as Administrator and launch the `MigrateIISWebsiteToElasticBeanstalk.ps1` script.

```
PS C:\> .\MigrateIISWebsiteToElasticBeanstalk.ps1
```

The assistant prompts you for the location of your credentials file. Press ENTER to skip if you didn't enter a profile location when you ran `Set-AWSCredential` during setup, otherwise provide the path of your credentials.

```
Please provide your AWS profile to use for the migration
AWS profile file location, like c:\aws\credentials (press ENTER for default value):
```

Enter the name of the profile you created when you ran `Set-AWSCredential` during setup.

```
Enter your AWS Profile Name:
```

Enter the AWS Region where you'd like your Elastic Beanstalk environment to run. For example: __us-west-1__.
For a list of AWS Regions where Elastic Beanstalk is available, see [AWS Elastic Beanstalk Endpoints and Quotas](https://docs.aws.amazon.com/general/latest/gr/elasticbeanstalk.html) in the *AWS General Reference*.

```
Enter the AWS Region (default us-east-1) :
```

The assistant then discovers any websites running on your IIS server and lists them, as in the below example.

```
The migration assistant discovered website(s) on the local server EC2AMAZ-9VP6LPT
[0] - Default Web Site
[1] - nop4.2
```

Enter the number of the website you’d like to migrate.

```
Enter the number of the website to migrate: (default 0):
```

The assistant takes a snapshot of your environment and lists any connection strings used by your application. To update a connection string, enter its number, or press ENTER to skip.

```
Enter the number of the connection string you would like to update, or press ENTER:
```

The assistant then pauses and allows you to migrate your database, in case you want to do it now and interactively provide new connection strings.  Press ENTER to continue.
```
Please separately migrate your database, if needed.
```
The assistant then prompts you to update any connection strings selected above. If you press `M`, you can update the string manually by editing it in the file path provided by the migration assistant.  Otherwise, paste the contents of the new connection string and press ENTER.

```
Enter "M" to manually edit the file containing the connection string, or paste the replacement stri
d press ENTER  (default M) :
```


Next, name your new Elastic Beanstalk application.

```
Please enter the name of your new EB application.
The name has to be unique:
```

Enter instance type that your application will run on. See [Amazon EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/) for a complete list.

```
Enter the instance type (default t3.medium) :
```

Lastly, select the Elastic Beanstalk platform from the below list. This platform should match the version of Windows Server that is currently running on your host system.

```
Elastic Beanstalk supports the following Windows Server versions:
[1] : Windows Server 2012
[2] : Windows Server 2012 R2
[3] : Windows Server Core 2012 R2
[4] : Windows Server 2016
[5] : Windows Server Core 2016
[6] : Windows Server 2019
[7] : Windows Server Core 2019
Enter the number of the Windows version for your Elastic Beanstalk environment [1]:
```


The migration assistant then migrates your application to Elastic Beanstalk.


### Readiness Report Only Mode 

If you only want to get a readiness report, you can execute the following command: 


```
PS C:\> .\MigrateIISWebsiteToElasticBeanstalk.ps1 -ReportOnly True
```

Upon completion, you will have a migration_readiness_report.json available. Readiness report only mode does not require AWS Credentials. 

#### Alternative Deployment Method
Alternately, you can upload the deployment bundle manually to Elastic Beanstalk once it has been generated by the Migration Assistant. To do so, quit the Migration Assistant after the line "An application bundle was successfully generated." and follow the below steps:

1. Sign in to your AWS console and go to the Elastic Beanstalk app creation page: https://us-east-1.console.aws.amazon.com/elasticbeanstalk/home?region=us-east-1#/gettingStarted
2. Select the AWS region you want to migrate the application to.
3. Create the app by following the instructions on the page. Select "Upload your code" for "Application code" section, and upload the deployment bundle generated by the Migration Assistant.
4. The deployment bundle is a zip file which can be found under folder MigrationRun-xxxxxxx/output

If you’re migrating an ASP.NET website that is actively maintained and updated, you can alternately publish your website to Elastic Beanstalk and update it using the [Elastic Beanstalk plugin for Visual Studio](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/create_deploy_NET.quickstart.html), APIs, SDKs, the AWS CLI, or the Elastic Beanstalk CLI(https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3.html).


### Migration Limitations
1. Software dependencies on the local server (outside of the website directory, for example GACs) aren’t detected or migrated.
1. There can be at most one HTTP port and at most one HTTPS port bound to the website. When the site is migrated to Elastic Beanstalk, the ports are bound to ports 80 and 443, respectively.
1. To migrate the existing SSL certificates, manually export them from the IIS server, import them to AWS Certificate Manager (ACM), and then configure them to the Elastic Beanstalk load balancer. For detailed instructions, see [Configuring HTTPS for Your Elastic Beanstalk Environment](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-https.html) in the AWS Elastic Beanstalk Developer Guide.
1. Applications with Active Directory aren’t currently supported.


### Troubleshooting
1. You see this error message: `Exception calling "ExtractToDirectory" with "2" argument(s): "Could not find a part of the path..."`: This means that the path to the file in generated Elastic Beanstalk deployment bundle is too long. In this case, move the migration assistant folder to the root directory of the hard drive and shorten the name of the folder (e.g. from `AWSWebAppMigrationAssistant` to `AMS`).
1. Your migrated application has trouble accessing its database: If the database is in AWS, please make sure that its security group allows traffic between the migrated Elastic Beanstalk instance (you can find it in EC2 in the same AWS region) and itself. If the database isn’t in AWS, configure the firewall to allow traffic from the Elastic Beanstalk instance.
1. The migration assistant shows the migration as complete, but the Elastic Beanstalk environment is disabled with the following error messages: `This environment is terminated and cannot be modified. It will remain visible for about an hour. ERROR Failed to launch environment. ERROR Environment must have instance profile associated with it.`: This can happen due to an issue on the Elastic Beanstalk side. To resolve the issue, deploy the generated source bundle to Elastic Beanstalk manually.
1. You receive an `InvalidAddress.NotFound` or `AddressLimitExceeded` error: Make sure that the Elastic IP limit isn’t exceeded in the AWS region(s) you intend to migrate the website to. For more information, see [How do I troubleshoot errors with Elastic IP addresses in Amazon VPC?](https://aws.amazon.com/premiumsupport/knowledge-center/unlock-move-recover-troubleshoot-eip/)
1. If the migration successfully completes, but you later see an error in the Elastic Beanstalk event console such as:
'''
Error messages running the command: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy unrestricted -NonInteractive -NoProfile -Command "& { & \"C:\staging\scripts/site_post_install.ps1\"; exit $LastExitCode }" Get-WebFilePath : Cannot find path 'IIS:\Sites\EBSDemo' because it does not exist. At C:\staging\scripts\site_post_install.ps1:14 char:20 + $websiteFilePath = ...message truncated, view the environment logs for full error message details.
'''
Confirm that you have migrated your application to an Elastic Beanstalk platform with the same version of Windows Server (e.g. migrate from Windows Server 2016 to Windows Server 2016).
1. If you see a default ASP.NET website presented when you navigate to your environment’s web page, and your website relies on a database, it may mean the migrated website is unable to connect to your database.
    1. Confirm that you correctly made any changes to the connection string during migration.
    1. If your database runs on an EC2 instance, make sure its security group allows inbound traffic (port 1433 for SQL Server) from your new environment’s security group.  

### License
This project is licensed under the [Apache-2.0 License](https://www.apache.org/licenses/LICENSE-2.0).


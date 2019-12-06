## Windows Web App Migration Assistant for AWS Elastic Beanstalk

### Overview
The Windows Web App Migration Assistant for AWS Elastic Beanstalk is an interactive PowerShell utility that migrates [ASP.NET](https://dotnet.microsoft.com/apps/aspnet) and [ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/?view=aspnetcore-3.1) applications from on-premises IIS Windows servers to AWS Elastic Beanstalk. The migration assistant is able to migrate an entire website and its configuration to Elastic Beanstalk with minimal or no changes to the application. After the assistant migrates the application, Elastic Beanstalk automatically handles the ongoing details of capacity provisioning, load balancing, auto-scaling, application health monitoring, and applying patches and updates to the underlying platform. If you need to also migrate a database associated with your web application, you can separately use [AWS Database Migration Service](https://aws.amazon.com/dms/), [CloudEndure Migration](https://aws.amazon.com/cloudendure-migration/), or the [Windows to Linux Replatforming Assistant for Microsoft SQL Server Databases](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/replatform-sql-server.html).

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
1. Attach the following AWS-managed policies to the IAM user: (1) `IAMReadOnlyAccess` (2) `AWSElasticBeanstalkFullAccess`. Assign both Programmatic access and AWS Management Console access to the IAM user. Before finishing the user creation, obtain the user's AccessKey and SecretKey from the console. For instructions on creating a new user, see [Creating an IAM User in Your AWS Account](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html) in the *AWS Identity and Access Management User Guide*. Open a PowerShell terminal on your on-premises Windows Server, where the website is hosted, and invoke the following two commands.
    ```
    PS C:\> Import-Module AWSPowerShell
    PS C:\> Set-AWSCredential -AccessKey {access_key_of_the_user} -SecretKey {secret_key_of_the_user} -StoreAs {profile_name} -ProfileLocation {optional - path_to_the_new_profile_file}
    ```
    The parameter `{profile_name}` refers to the IAM user, and the optional parameter `{path_to_the_new_profile_file}` refers to the full physical path of the new profile file.
For CLI reference, see [AWS Tools for PowerShell](https://aws.amazon.com/powershell/).
1. On GitHub, use the **Clone or download** menu to either clone this repository or download a ZIP bundle of it and extract the ZIP file. Place the migration assistant on the local server, in a new folder on a disk that has more than 1 GB free space.
1. [Optional] Edit the `settings.txt` JSON file, and set the following 2 variables: (1) `defaultAwsProfileFileLocation : {profile_name}` (2) `defaultAwsProfileName : {path_to_the_new_profile_file}`
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
PS C:\> .\MigrateIISWebssiteToElasticBeanstalk.ps1
```

The script prompts you for input. Below are descriptions for each prompt.

```
Please provide your AWS profile to use for the migration
AWS profile file location, like c:\aws\credentials (press Enter for default value):
```

Press Enter to skip if you didn't enter a profile location when you ran `Set-AWSCredential` during setup, otherwise provide the path of your credentials.

```
AWS Profile Name:
```

Enter the name of the profile you created you ran `Set-AWSCredential` during setup.

```
Enter AWS Region:
```

Enter the region where your Elastic Beanstalk environment will run, such as us-west-1.
For a list of AWS regions, see [AWS Service Endpoints](https://docs.aws.amazon.com/general/latest/gr/rande.html) in the *AWS General Reference*.

The assistant then discovers any websites running on your IIS server, lists them, and displays the prompt:

```
Please select the website to migrate to Elastic Beanstalk
Name of website:
```

Enter the name of the website you’d like to migrate.

The assistant then takes a snapshot of your environment and asks if you would like to update the database connection strings for your application. To leave them unchanged, press Enter. Otherwise, copy the connection string(s) listed by the script that you would like to change, and paste into the prompt. For example:

```
Connection String No. 1: “DataConnectionString”: “Data Source=MyServer;Initial Catalog=nopcommerce;IntegratedSecurity=False;Persist Security Info=False;User ID=sa; Password=eexar884Nix”
```

The assistant then asks if you want to auto-update the connection string, or update it manually.

```
Press Enter to auto-update:
```

If you press Enter, you are prompted to enter the new connection string. If you press `M`, you can update the string manually by editing it in the file path provided by the migration assistant.

Next, enter `N` for optional prompts like IIS hardening.

```
Please name your new EB application:
```

Enter the name of your new Elastic Beanstalk application.  

```
Solution stack name:
```

Enter the name of the Windows Server Elastic Beanstalk solution stack, such as
64bit Windows Server 2016 v1.2.0 running IIS 10.0

For a list of all supported solution stacks, see [.NET on Windows Server with IIS](https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html#platforms-supported.net) in the *AWS Elastic Beanstalk Platforms* guide.

The migration assistant then migrates your application to Elastic Beanstalk.

### Migration Limitations
1. Software dependencies on the local server (outside of the website directory, for example GACs) aren’t detected or migrated.
1. There can be at most one HTTP port and at most one HTTPS port bound to the website. When the site is migrated to Elastic Beanstalk, the ports are bound to ports 80 and 443, respectively.
1. To migrate the existing SSL certificates, manually export them from the IIS server, import them to AWS Certificate Manager (ACM), and then configure them to the Elastic Beanstalk load balancer. For detailed instructions, see [Configuring HTTPS for Your Elastic Beanstalk Environment](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-https.html) in the AWS Elastic Beanstalk Developer Guide.
1. Applications with Active Directory aren’t currently supported.


### Troubleshooting
1. You see this error message: `Exception calling "ExtractToDirectory" with "2" argument(s): "Could not find a part of the path..."`: This means that the path to the file in generated Elastic Beanstalk deployment bundle is too long. In this case, move the migration assistant folder to the root directory of the hard drive and shorten the name of the folder (e.g. from `AWSWebAppMigrationAssistant` to `AMS`).
1. Your migrated application has trouble accessing its database: If the database is in AWS, please make sure that its security group allows traffic between the migrated Elastic Beanstalk instance (you can find it in EC2 in the same AWS region) and itself. If the database isn’t in AWS, configure the firewall to allow traffic from the Elastic Beanstalk instance.
1. The migration assistant shows the migration as complete, but the Elastic Beanstalk environment is disabled with the following error messages: `This environment is terminated and cannot be modified. It will remain visible for about an hour. ERROR Failed to launch environment. ERROR Environment must have instance profile associated with it.`: This can happen due to an issue on the Elastic Beanstalk side. To resolve the issue, deploy the generated source bundle to Elastic Beanstalk manually.
1. The migration assistant shows the migration as complete and the Elastic Beanstalk environment is healthy, but the website doesn't work properly: This issue can happen when the website uses a specific feature which is disabled during the IIS hardening step. In order to resolve this issue, during the migration process, type `N` when promoted `Would you like to perform IIS hardening on the Elastic Beanstalk application?`.
1. You receive an `InvalidAddress.NotFound` or `AddressLimitExceeded` error: Make sure that the Elastic IP limit isn’t exceeded in the AWS region(s) you intend to migrate the website to. For more information, see [How do I troubleshoot errors with Elastic IP addresses in Amazon VPC?](https://aws.amazon.com/premiumsupport/knowledge-center/unlock-move-recover-troubleshoot-eip/)

### License
This project is licensed under the [Apache-2.0 License](https://www.apache.org/licenses/LICENSE-2.0).

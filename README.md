## AWS Web App Migration Assistant

### Overview

The AWS Web Application Migration Assistant is an interactive PowerShell utility that migrates any
.NET applications from local IIS Windows servers to AWS Elastic Beanstalk. The assistant supports
migrating an entire website with its configurations to Elastic Beanstalk with minimal or no changes
needed. It also comes with an optional database migration utility (MigrateSQLServerToEC2Windows.ps1) that
migrates SQL databases associated with the website to new SQL Windows instances in AWS EC2.

Download link for the database migration tool:
https://aws.amazon.com/blogs/database/migrating-your-on-premises-sql-server-windows-workloads-to-amazon-ec2-linux/


### Migration Prerequisites

The migration assistant needs to be launched on the local Windows server using the Administrator role.
The following is a list of software dependencies required for the assistant to run:

1. Internet Information Services (IIS) version 7.0 or above

2. MS PowerShell version 3.0 or above
    - https://www.microsoft.com/en-us/download/details.aspx?id=34595

3. Microsoft Web Deploy version 3.6 or above
    - https://www.iis.net/downloads/microsoft/web-deploy

4. AWSPowerShell module for MS PowerShell
    - https://www.powershellgallery.com/packages/AWSPowerShell/3.3.498.0

5. WebAdministration module for MS PowerShell
    - Check for this dependency by invoking PowerShell command "Import-Module WebAdministration"


### AWS Account Requirements

Please go to the IAM console of your AWS account to confirm that the following IAM role exists:

1. aws-elasticbeanstalk-ec2-role

If the role does not exist, create it by following the instructions in this document:
    - https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/iam-instanceprofile.html

In addition, the assistant needs to run with an AWS user profile with the following IAM policies attached:

1. IAMReadOnlyAccess
2. AWSElasticBeanstalkFullAccess

Please also make sure that the Elastic IP limit is not exceeded in the AWS region(s) you intend to
migrate the website to. More information on EIP limits can be found here:
    - https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html


### Migration Limitations

1. The assistant supports migrating websites from Windows Server 2008 R2 or above.

2. Software dependencies on the local server (outside of the website directory, e.g. GACs) will not
   be detected or migrated.

3. There can only be at most 1 HTTP port and at most 1 HTTPS port bound to the website - when the
   site is migrated to Elastic Beanstalk, the ports will be bound to port 80 and 443.

4. If you wish to migrate the existing SSL certificates, you will need to manually export them from
   the IIS servers, import them to AWS Certificate Manager (ACM), and then configure them to the
   Elastic Beanstalk load balancers. Detailed instructions can be found here:
    - https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-https.html

5. The assistant needs to run on the server where the website is hosted on. Thus, the server needs
   to have full internet access to AWS. The assistant also requires the Administrator role.


### Migration Workflow

Here's an overview of the migration assistant's general workflow:

[discover local websites] --> [select site to migrate] --> [discover database connection strings]
--> [database migration] --> [update database connection strings] --> [generate EB deployment bundle]
--> [deploy application to EB]


### Migration Procedure

1. Review [Migration Prerequisites] section of this document and make sure they are satisfied.

2. Review [Migration Limitations] section of this document and resolve any incompatibility.

3. Create a new IAM user using the IAM console to use for the Elastic Beanstalk migration.
   Attach the following AWS-managed policies to the user:
    (1) IAMReadOnlyAccess
    (2) AWSElasticBeanstalkFullAccess
   Assign the following accesses to the user:
    (1) Programmatic access
    (2) AWS Management Console access
   Before finishing the user creation, obtain the user's AccessKey and SecretKey from the console.
   Detailed instructions on creating a new user can be found here:
    - https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html

4. Open a PowerShell terminal on your local server (where the website is hosted), and invoke the
   following 2 commands:
    (1) Import-Module AWSPowerShell
    (2) Set-AWSCredential -AccessKey {access_key_of_the_user} -SecretKey {secret_key_of_the_user} -StoreAs {profile_name} -ProfileLocation {path_to_the_new_profile_file}
   Where parameter {profile_name} refers to the IAM user, and (optional) parameter
   {path_to_the_new_profile_file} refers to the full physical path to the new profile file to create.
   For reference to CLI, see https://aws.amazon.com/powershell/

5. Download the migration assistant zip bundle to the local server, and extract its content.
    Note: please extract the content to a new folder, in a disk that has more than 1 GB free space.

6. Optional: edit the settings.txt JSON file, and set the following 2 variables:
    (1) defaultAwsProfileFileLocation : {profile_name}
    (2) defaultAwsProfileName : {path_to_the_new_profile_file}

7. Make sure you are logged in to the local server as Administrator.

8. Open a PowerShell terminal (as Admin), run the MigrateIISWebsiteToElasticBeanstalk.ps1 script and follow the prompts.


### Database Migration

The migration assistant comes with a database migration utility (MigrateSQLServerToEC2Windows.ps1) that
migrates SQL Server databases to new SQL Windows instances in AWS EC2. The utility can be downloaded from:

https://aws.amazon.com/blogs/database/migrating-your-on-premises-sql-server-windows-workloads-to-amazon-ec2-linux/

The database migration script needs to run on the SQL Servers locally. 
Instruction of using the database migration script can be found in the script. 
You can also invoke the script without parameters to use its graphical interface.
You can choose to use this utility to migrate the databases associated with the website being migrated,
or do one of the following:

1. Use any database migration tool you prefer to migrate the databases to AWS: in this case, you 
   need to collect the connection strings for your new databases, and replace the old connections
   the website is using (either automatically with migration assistant or manually).

2. Keep using the old databases, but allow traffic between them and AWS Elastic Beanstalk: in this
   case, you don't need to modify the old connection strings.

3. For databases of a very large scale, consider using the AWS Database Migration Service.

If you wish to migrate the database to a Linux server, see
https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/replatform-sql-server.html


### Active Directory

If your IIS application uses Active Directory (AD) for authentication, you can extend your AD to AWS
then join the Elastic Beanstalk application to the AD at deployment time by following these steps:

1. Extend the AD to AWS using the AD Connector:
    https://docs.aws.amazon.com/directoryservice/latest/admin-guide/directory_ad_connector.html
2. Create the following SSM document in your account (replace the indicated fields):
    https://docs.aws.amazon.com/systems-manager/latest/userguide/create-ssm-doc.html
    Content of the SSM document:

{
    "schemaVersion": "1.0",
    "description": "Sample configuration to join an instance to a domain",
    "runtimeConfig": {
        "aws:domainJoin": {
            "properties": {
                "directoryId": "{REPLACE_WITH_DIRECTORY_ID}",
                "directoryName": "{REPLACE_WITH_DIRECTORY_NAME}",
                "dnsIpAddresses": [
                    "{REPLACE_WITH_DNS_IP_ADDRESS_1}",
                    "{REPLACE_WITH_DNS_IP_ADDRESS_2}"
                ]
            }
        }
    }
}

3. When prompted, provide the name of the SSM document
4. Select the advanced deployment method
5. Select the VPC the AD extends in & instance profile with ssm:CreateAssociation permission to deploy the application


### Additional Notes

1. You can configure custom migration settings by editing the utils/settings.txt JSON file.

2. A list of AWS regions can be found here:
    - https://docs.aws.amazon.com/general/latest/gr/rande.html

3. A list of available Elastic Beanstalk solution stacks (for .NET) can be found here:
    - https://docs.aws.amazon.com/elasticbeanstalk/latest/platforms/platforms-supported.html#platforms-supported.net


### Known Issues

1. If you see this error message:
      " Exception calling "ExtractToDirectory" with "2" argument(s): "Could not find a part of the path..."
   It means that the path to the file in generated EB deployment bundle is too long.
   In this case, please move the migration assistant folder to the root directory of the hard drive
   and shorten the name of the folder (e.g. from AWSWebAppMigrationAssistant to AMS)

2. If your migrated application has trouble accessing its database:
   If the database is in AWS, please make sure that its security group allows traffic between the
   migrated EB instance (you can find it in EC2 in the same AWS region) and itself.
   If the database is not in AWS, please configure the firewall to allow traffic from the EB instance.

3. If the migration assistant shows migration complete but the EB environment is disabled with the following error messages:
      "This environment is terminated and cannot be modified. It will remain visible for about an hour.
       ERROR	Failed to launch environment.
       ERROR	Environment must have instance profile associated with it."
   This can happen due to an issue on the Elastic Beanstalk side. To resolve the issue, 
   Deploy to EB manually with the generated source bundle.

4. If the migration assistant shows migration complete, and the EB environment is healthy, but the website does not work properly:
   This issue can happen when the website uses a specific feature which is disabled during the IIS hardening step.
   In order to resolve this issue, during the migration process, please type "N" when promoted
      "Would you like to perform IIS hardening on the Elastic Beanstalk application?"


### License

This project is licensed under the Apache-2.0 License.

# HelloID-Conn-SA-Full-Exchange-On-Premises-Distribution-Group-Create

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                          |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

_HelloID-Conn-SA-Full-Exchange-On-Premises-Distribution-Group-Create_ is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can create distribution groups in Exchange On-Premises. The following options are available:

1.  Select the group type (Distribution Group or Mail-enabled Security Group)
2.  Enter a display name for the new group
3.  The display name is validated for uniqueness in Active Directory
4.  Compose an email address by entering a prefix and selecting from available mail domains
5.  The email address is validated for uniqueness in Exchange On-Premises
6.  Optionally enter an alias (mailNickname), which is validated for uniqueness
7.  Select members and owners from available Exchange users
8.  The distribution group is created in Exchange with the specified configuration

## Getting started

### Requirements

- **Active Directory Access**:<br>
  Read access to Active Directory is required to validate display names and query group information.
- **Exchange On-Premises PowerShell Remoting**:<br>
  Remote PowerShell access to Exchange On-Premises servers is required. The connector uses remote PowerShell sessions to execute Exchange commands.
- **Service Account Permissions**:<br>
  The service account must have sufficient permissions to create distribution groups and mail-enabled security groups in Exchange On-Premises and Active Directory.

### Connection settings

The following user-defined variables are used by the connector.

| Setting                       | Description                                                            | Mandatory |
| ----------------------------- | ---------------------------------------------------------------------- | --------- |
| ExchangeConnectionUri         | The URI to the Exchange On-Premises PowerShell endpoint                | Yes       |
| ExchangeAdminUsername         | The username for Exchange On-Premises authentication                   | Yes       |
| ExchangeAdminPassword         | The password for Exchange On-Premises authentication                   | Yes       |
| ADdistributionGroupsOU        | Active Directory OU where distribution groups will be created          | Yes       |
| ADmailenabledSecurityGroupsOU | Active Directory OU where mail-enabled security groups will be created | Yes       |

## Remarks

### Group Type Selection

The form supports creating both Distribution Groups and Mail-enabled Security Groups. The appropriate Active Directory OU is selected based on the chosen group type, using either `$ADdistributionGroupsOU` or `$ADmailenabledSecurityGroupsOU`.

### Email Address Policy

The connector sets `EmailAddressPolicyEnabled` to `$false` after creating the distribution group to ensure manual control over email addresses and prevent automatic policy-based updates.

### Validation Strategy

The connector uses separate datasources for validating different attributes:

- Display name validation queries Active Directory to ensure uniqueness
- Alias validation queries Exchange recipients (including all mailbox types and distribution groups)
- Email address validation queries Exchange recipients for both primary SMTP addresses and proxy addresses

### Owner and Member Configuration

When creating the distribution group, the connector sets `CopyOwnerToMember` to `$true`, which automatically adds all owners as members of the group. Additional members can be selected separately.

### Session Management

All Exchange connections use proper session cleanup in finally blocks to ensure connections are properly closed even if errors occur. Session options are configured with `SkipCACheck`, `SkipCNCheck`, and `SkipRevocationCheck` all set to `$false` for secure connections.

## Development resources

### API documentation

For more information about Exchange On-Premises PowerShell cmdlets, refer to the official Microsoft documentation:

- [Connect to Exchange servers using remote PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell)
- [New-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchange/new-distributiongroup)
- [Set-DistributionGroup](https://learn.microsoft.com/en-us/powershell/module/exchange/set-distributiongroup)
- [Get-AcceptedDomain](https://learn.microsoft.com/en-us/powershell/module/exchange/get-accepteddomain)
- [Get-Recipient](https://learn.microsoft.com/en-us/powershell/module/exchange/get-recipient)

## Getting help

> :bulb: **Tip:**  
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

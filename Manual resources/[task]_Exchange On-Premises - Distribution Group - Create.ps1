$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# variables configured in form
$distributionGroupType = $form.groupType # "Mail-enabled Security Group" or "Distribution Group"
$distributionGroupDisplayName = $form.displayName
$distributionGroupPrimarySmtpAddress = "$($form.mailPrefix)@$($form.mailDomain.id)"
$distributionGroupAlias = $form.alias
$ownersToAdd = @($form.ownersToAdd  | ForEach-Object { $_.userPrincipalName })
$membersToAdd = @($form.membersToAdd | ForEach-Object { $_.userPrincipalName })

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""
# $ADdistributionGroupsOU = ""
# $ADmailenabledSecurityGroupsOU = ""

# PowerShell commands to import
$commands = @(
    "New-DistributionGroup"
    , "Set-DistributionGroup"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"


# Create distributiongroup
try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)
    
    Write-Verbose "Created credentials for user [$ExchangeAdminUsername]"

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        Credential        = $credential
        ConnectionUri     = $ExchangeConnectionUri
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName $commands -ErrorAction Stop

    # Send initial audit log
    $Log = @{
        Action            = "CreateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange On-Premises" # optional (free format text) 
        Message           = "Successfully connected to Exchange using URI [$ExchangeConnectionUri]" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $ExchangeConnectionUri # optional (free format text) 
        TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) 
    }
    Write-Information -Tags "Audit" -MessageData $log

    $exchangeDistributionGroupParams = @{
        Name               = $distributionGroupDisplayName
        DisplayName        = $distributionGroupDisplayName
        PrimarySmtpAddress = $distributionGroupPrimarySmtpAddress
        Alias              = $distributionGroupAlias        
        SamAccountName     = $distributionGroupAlias
        OrganizationalUnit = $null
        ManagedBy          = $ownersToAdd
        Members            = $membersToAdd
        CopyOwnerToMember  = $true
        ErrorAction        = "Stop"
    }

    Switch ($distributionGroupType) {
        'Mail-enabled Security Group' {
            $exchangeDistributionGroupParams.OrganizationalUnit = $ADmailenabledSecurityGroupsOU
            $response = New-DistributionGroup -Type security @exchangeDistributionGroupParams
        }

        'Distribution Group' {
            $exchangeDistributionGroupParams.OrganizationalUnit = $ADdistributionGroupsOU
            $response = New-DistributionGroup @exchangeDistributionGroupParams
        }
    }

    $exchangeSetDistributionGroupParams = @{
        Identity                  = "$($response.GUID)"
        EmailAddressPolicyEnabled = $false
    }
    $null = Set-DistributionGroup @exchangeSetDistributionGroupParams
    Write-Information "Successfully created distributiongroup for $distributionGroupDisplayName" 
    
    $Log = @{
        Action            = "CreateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange On-Premises" # optional (free format text) 
        Message           = "Created distribution group:  $($response.displayName)" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $($response.displayName) # optional (free format text) 
        TargetIdentifier  = $([string]$response.Guid)  # optional (free format text) 
    }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log       
}
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }

    # Send error audit log to HelloID
    $Log = @{
        Action            = "CreateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange On-Premises" # optional (free format text) 
        Message           = $auditMessage # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $mailbox.DisplayName # optional (free format text) 
        TargetIdentifier  = $mailbox.PrimarySmtpAddress # optional (free format text) 
    }
    
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams

            # Send disconnect audit log
            $Log = @{
                Action            = "CreateResource" # optional. ENUM (undefined = default) 
                System            = "Exchange On-Premises" # optional (free format text) 
                Message           = "Successfully disconnected from Exchange using URI [$ExchangeConnectionUri]" # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = $ExchangeConnectionUri # optional (free format text) 
                TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) 
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}



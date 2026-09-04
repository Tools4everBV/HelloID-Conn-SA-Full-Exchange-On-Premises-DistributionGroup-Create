# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Exchange On-Premises") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> ADdistributionGroupsOU
$tmpName = @'
ADdistributionGroupsOU
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #2 >> ADmailenabledSecurityGroupsOU
$tmpName = @'
ADmailenabledSecurityGroupsOU
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #3 >> ExchangeConnectionUri
$tmpName = @'
ExchangeConnectionUri
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #4 >> ExchangeAdminPassword
$tmpName = @'
ExchangeAdminPassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True" });

#Global variable #5 >> ExchangeAdminUsername
$tmpName = @'
ExchangeAdminUsername
'@ 
$tmpValue = @'
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic }
    Write-Information "Using prefilled API credentials"
}
else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key }
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
}
else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if ($IsCoreCLR -eq $true) {
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return , $r  # Force return value to be an array using a comma
    }
    else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return , $r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
        else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    }
    catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter { $_.name -eq $TaskName }

        if ([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
        else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    }
    catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch ($DatasourceType) { 
        "1" { "Native data source"; break } 
        "2" { "Static data source"; break } 
        "3" { "Task data source"; break } 
        "4" { "Powershell data source"; break }
    }

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if ([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
        else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    }
    catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if (([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
        else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    }
    catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if ([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if (-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        }
        else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    }
    catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
    Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users" #>
$tmpPsScript = @'
# Build filter
# This will check ALL users (enabled and disabled)
$filter = "RecipientType -eq 'UserMailbox'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "PrimarySmtpAddress"
    , "UserPrincipalName"    
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Mailbox" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"
    $getMailboxesSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $mailboxes = Get-Mailbox @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried shared mailboxes that match filter [$($filter)]. Result count: $(($mailboxes | Measure-Object).Count)"

    # Sort and send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailboxes | Sort-Object -Property DisplayName | ForEach-Object {
        Write-Output $_
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
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
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"Guid","type":0},{"key":"DisplayName","type":0},{"key":"PrimarySmtpAddress","type":0},{"key":"UserPrincipalName","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_4 = [PSCustomObject]@{} 
$dataSourceGuid_4_Name = @'
exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_4_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_4) 
<# End: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users" #>

<# Begin: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users-Owners" #>
$tmpPsScript = @'
# variables configured in form
$mailPrefix = $datasource.mailPrefix
$mailDomain = $datasource.mailDomain.id
$PrimarySmtpAddress = "$mailPrefix@$mailDomain"

# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "RecipientType -eq 'UserMailbox'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "PrimarySmtpAddress"
    , "UserPrincipalName"    
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Mailbox" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"
    $getMailboxesSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $mailboxes = Get-Mailbox @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried shared mailboxes that match filter [$($filter)]. Result count: $(($mailboxes | Measure-Object).Count)"

    # Sort and send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailboxes | Sort-Object -Property DisplayName | ForEach-Object {
        Write-Output $_
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
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
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"Guid","type":0},{"key":"DisplayName","type":0},{"key":"PrimarySmtpAddress","type":0},{"key":"UserPrincipalName","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_5 = [PSCustomObject]@{} 
$dataSourceGuid_5_Name = @'
exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users-Owners
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_5_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_5) 
<# End: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-Users-Owners" #>

<# Begin: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-Alias-Unique" #>
$tmpPsScript = @'
# variables configured in form
$alias = $datasource.alias
$mailDomain = $datasource.mailDomain.id
$PrimarySmtpAddress = "$alias@$mailDomain"

# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "Alias -eq '$alias' -or PrimarySmtpAddress -eq '$PrimarySmtpAddress' -or EmailAddresses -like '*$PrimarySmtpAddress*'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "Name"
    , "Alias"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "SamAccountName"
    , "RecipientTypeDetails"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Recipient" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"

    $getRecipientsSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $recipients = Get-Recipient @getRecipientsSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried aliases that match filter [$($filter)]. Result count: $(($recipients | Measure-Object).Count)"

    # Check if value is unique and free
    if (($recipients | Measure-Object).Count -gt 0) {
        Write-Warning "Alias is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Alias is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]"
    }
    else {
        Write-Information "Alias is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Alias is unique and free to use." 
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
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
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"alias","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailDomain","type":0,"options":1}]
'@ 
$dataSourceGuid_3 = [PSCustomObject]@{} 
$dataSourceGuid_3_Name = @'
exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-Alias-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_3_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_3) 
<# End: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-Alias-Unique" #>

<# Begin: DataSource "exchange-on-premises-distribution-group-create | AD-Check-DisplayName-Unique" #>
$tmpPsScript = @'
# variables configured in form
$displayName = $datasource.displayName
$filter = "displayName -eq '$displayName' -and mail -like '*'"

# Global variables
# Outcommented as these are set from Global Variables
# $ADServer = "" # Optional, if not set the default domain controller is used

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "ObjectGUID",
    "name",
    "displayName",
    "mail",
    "mailNickname",
    "groupType"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

try {
    # Build search parameters
    $actionMessage = "querying AD group(s) matching the filter [$filter]"
    
     $getAdGroupSplatParams = @{
        Filter      = $filter
        Properties  = $propertiesToSelect
        Verbose     = $false
        ErrorAction = "Stop"
    }
    
    # Add server parameter if specified
    if (-not [string]::IsNullOrEmpty($ADServer)) {
        $getAdGroupSplatParams['Server'] = $ADServer
    }

    # Get Active Directory Groups matching Name
    $adGroups = Get-ADGroup @getAdGroupSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried AD group(s) matching the filter [$filter]. Result count: $(($adGroups | Measure-Object).Count)"
 
    # Check if value is unique and free
    if (($adGroups | Measure-Object).Count -gt 0) {
        Write-Warning "Name is not unique. In use by group with Name [$($adGroups.Name)], SamAccountName [$($adGroups.SamAccountName)] and DistinguishedName [$($adGroups.DistinguishedName)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Name is not unique. In use by group with Name [$($adGroups.Name)], SamAccountName [$($adGroups.SamAccountName)] and DistinguishedName [$($adGroups.DistinguishedName)]"
    }
    else {
        Write-Information "Name is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Name is unique and free to use." 
    }
} catch {
    $ex = $PSItem
    $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"displayName","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
exchange-on-premises-distribution-group-create | AD-Check-DisplayName-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "exchange-on-premises-distribution-group-create | AD-Check-DisplayName-Unique" #>

<# Begin: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-MailDomains" #>
$tmpPsScript = @'
# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "id"
    , "IsValid"
    , "EmailOnly"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions


try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-AcceptedDomain" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"

    $getMailboxesSplatParams = @{
        ErrorAction = 'Stop'
    }

    # Select only specified properties to limit memory usage
    $mailDomains = $null
    $mailDomains = Get-AcceptedDomain @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried Exchange On-Premises Domains. Result count: $(@($mailDomains).Count)"

    # Filter for verified domains only and where Email is supported - not support by Graph API filter query
    $actionMessage = "filtering for verified domains only and where Email is supported"
    $mailDomains = $mailDomains | Where-Object { $_.IsValid -eq $true }
    Write-Information "Filter for verified domains only and where Email is supported. Result count: $(@($mailDomains).Count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailDomains | Sort-Object -Property id | ForEach-Object {
        Write-Output $_
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
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
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"Id","type":0},{"key":"IsValid","type":0},{"key":"EmailOnly","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-MailDomains
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Get-All-MailDomains" #>

<# Begin: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-EmailAddress-Unique" #>
$tmpPsScript = @'
# variables configured in form
$mailPrefix = $datasource.mailPrefix
$mailDomain = $datasource.mailDomain.id
$PrimarySmtpAddress = "$mailPrefix@$mailDomain"

# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "Alias -eq '$mailPrefix' -or PrimarySmtpAddress -eq '$PrimarySmtpAddress' -or EmailAddresses -like '*$PrimarySmtpAddress*'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "Name"
    , "Alias"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "SamAccountName"
    , "RecipientTypeDetails"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Recipient" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying all recipients that match filter [$($filter)]"

    $getRecipientsSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $recipients = Get-Recipient @getRecipientsSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried all recipients that match filter [$($filter)]. Result count: $(($recipients | Measure-Object).Count)"

    # Check if value is unique and free
    if (($recipients | Measure-Object).Count -gt 0) {
        Write-Warning "Email address is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Email address is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]"
    }
    else {
        Write-Information "Email address is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Email address is unique and free to use." 
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
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
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailPrefix","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailDomain","type":0,"options":1}]
'@ 
$dataSourceGuid_2 = [PSCustomObject]@{} 
$dataSourceGuid_2_Name = @'
exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-EmailAddress-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_2_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_2) 
<# End: DataSource "exchange-on-premises-distribution-group-create | Exchange-On-Premises-Check-EmailAddress-Unique" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange On-Premises - Distribution Group - Create" #>
$tmpSchema = @"
[{"label":"Create group","fields":[{"key":"groupType","templateOptions":{"label":"Group type","useObjects":false,"options":["Distribution Group","Mail-enabled Security Group"],"required":true},"type":"radio","defaultValue":"Distribution Group","summaryVisibility":"Show","textOrLabel":"label","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"displayName","templateOptions":{"label":"Display Name","placeholder":"IT Department","required":true,"minLength":1,"maxLength":256,"pattern":"^[A-Za-z0-9�-� .,_\u0027-]{1,256}$"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"nameValidation","templateOptions":{"label":"Display name validation","placeholder":"Display name will be validated on uniqnueness in Active Directory","pattern":"^Valid.*","readonly":true,"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"displayName","otherFieldValue":{"otherFieldKey":"displayName"}}]}},"displayField":"output"},"hideExpression":"!model[\"displayName\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"templateOptions":{"title":"This address will be created as the primary SMTP address of the mailbox","titleField":"","bannerType":"Info","useBody":false},"type":"textbanner","summaryVisibility":"Hide element","body":"Text Banner Content","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"formRow","templateOptions":{},"fieldGroup":[{"key":"mailPrefix","templateOptions":{"label":"Email address","pattern":"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$","minLength":1,"maxLength":200,"required":true,"placeholder":"it-department"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"mailDomain","templateOptions":{"label":"Mail domain","required":true,"useObjects":false,"useDataSource":true,"useFilter":false,"options":["Option 1","Option 2","Option 3"],"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[]}},"valueField":"Id","textField":"Id"},"type":"dropdown","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"mailValidation","templateOptions":{"label":"Email address validation","readonly":true,"placeholder":"Email address will be validated on uniqnueness in Active Directory","required":true,"pattern":"^Valid.*","useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_2","input":{"propertyInputs":[{"propertyName":"mailPrefix","otherFieldValue":{"otherFieldKey":"mailPrefix"}},{"propertyName":"mailDomain","otherFieldValue":{"otherFieldKey":"mailDomain"}}]}},"displayField":"output"},"hideExpression":"!model[\"mailPrefix\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"templateOptions":{"title":"The alias (mailNickname) is a short name used as an internal identifier for the group","titleField":"","bannerType":"Info","useBody":true},"type":"textbanner","summaryVisibility":"Hide element","body":"**The alias is a short name used as an internal identifier for the new group.**\r\n\r\nIt is not the same as the email address.  \r\nThe alias can only have **one** value, and it will be created exactly as entered.\r\n\r\nIf you do not provide an alias, the username portion of the email address will be used automatically.\r\n\r\nUse only letters, numbers, and periods (no spaces).  \r\nDo not include a domain (no \"@\").","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"alias","templateOptions":{"label":"Alias","placeholder":"it-dep","pattern":"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"aliasValidation","templateOptions":{"label":"Alias validation","pattern":"^Valid.*","placeholder":"Alias will be validated on uniqnueness in Exchange On-Premises","useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_3","input":{"propertyInputs":[{"propertyName":"alias","otherFieldValue":{"otherFieldKey":"alias"}},{"propertyName":"mailDomain","otherFieldValue":{"otherFieldKey":"mailDomain"}}]}},"displayField":"output","readonly":true},"hideExpression":"!model[\"alias\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]},{"label":"Group permissions","fields":[{"key":"membersToAdd","templateOptions":{"label":"Users to grant membership","required":true,"grid":{"columns":[{"headerName":"User Principal Name","field":"UserPrincipalName"},{"headerName":"Display Name","field":"DisplayName"},{"headerName":"Primary Smtp Address","field":"PrimarySmtpAddress"}],"height":300,"rowSelection":"multiple"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_4","input":{"propertyInputs":[]}},"useFilter":true,"useDefault":false,"allowCsvDownload":false},"type":"multiselectgrid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true},{"key":"ownersToAdd","templateOptions":{"label":"Users to grant ownership","required":true,"grid":{"columns":[{"headerName":"User Principal Name","field":"UserPrincipalName"},{"headerName":"Display Name","field":"DisplayName"},{"headerName":"Primary Smtp Address","field":"PrimarySmtpAddress"}],"height":300,"rowSelection":"multiple"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_5","input":{"propertyInputs":[]}},"useFilter":true,"useDefault":false,"allowCsvDownload":false},"type":"multiselectgrid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange On-Premises - Distribution Group - Create
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if (-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)) {
    foreach ($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        }
        catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if ($null -ne $delegatedFormAccessGroupGuids) {
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach ($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object { $_.name.en -eq $category }
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
    catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category };
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null } 
$delegatedFormName = @'
Exchange On-Premises - Distribution Group - Create
'@
$tmpTask = @'
{"name":"Exchange On-Premises - Distribution Group - Create","script":"$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n# variables configured in form\r\n$distributionGroupType = $form.groupType # \"Mail-enabled Security Group\" or \"Distribution Group\"\r\n$distributionGroupDisplayName = $form.displayName\r\n$distributionGroupPrimarySmtpAddress = \"$($form.mailPrefix)@$($form.mailDomain.id)\"\r\n$distributionGroupAlias = $form.alias\r\n$ownersToAdd = @($form.ownersToAdd  | ForEach-Object { $_.userPrincipalName })\r\n$membersToAdd = @($form.membersToAdd | ForEach-Object { $_.userPrincipalName })\r\n\r\n# Global variables\r\n# Outcommented as these are set from Global Variables\r\n# $ExchangeConnectionUri = \"\"\r\n# $ExchangeAdminUsername = \"\"\r\n# $ExchangeAdminPassword = \"\"\r\n# $ADdistributionGroupsOU = \"\"\r\n# $ADmailenabledSecurityGroupsOU = \"\"\r\n\r\n# PowerShell commands to import\r\n$commands = @(\r\n    \"New-DistributionGroup\"\r\n    , \"Set-DistributionGroup\"\r\n)\r\n\r\n# Enable TLS1.2\r\n[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12\r\n\r\n# Set debug logging\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n\r\n# Create distributiongroup\r\ntry {\r\n    # Create credentials\r\n    $actionMessage = \"creating credentials object\"\r\n    \r\n    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force\r\n    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)\r\n    \r\n    Write-Verbose \"Created credentials for user [$ExchangeAdminUsername]\"\r\n\r\n    # Connect to Exchange On-Premises\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell\r\n    $actionMessage = \"connecting to Exchange On-Premises\"\r\n\r\n    $sessionOptionParams = @{\r\n        SkipCACheck         = $false\r\n        SkipCNCheck         = $false\r\n        SkipRevocationCheck = $false\r\n    }\r\n\r\n    $sessionOption = New-PSSessionOption @sessionOptionParams\r\n\r\n    $sessionParams = @{\r\n        Authentication    = \u0027Default\u0027\r\n        ConfigurationName = \u0027Microsoft.Exchange\u0027\r\n        Credential        = $credential\r\n        ConnectionUri     = $ExchangeConnectionUri\r\n        SessionOption     = $sessionOption\r\n        ErrorAction       = \"Stop\"\r\n    }\r\n\r\n    $exchangeSession = New-PSSession @sessionParams\r\n    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName $commands -ErrorAction Stop\r\n\r\n    # Send initial audit log\r\n    $Log = @{\r\n        Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = \"Successfully connected to Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n        TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n    $exchangeDistributionGroupParams = @{\r\n        Name               = $distributionGroupDisplayName\r\n        DisplayName        = $distributionGroupDisplayName\r\n        PrimarySmtpAddress = $distributionGroupPrimarySmtpAddress\r\n        Alias              = $distributionGroupAlias        \r\n        SamAccountName     = $distributionGroupAlias\r\n        OrganizationalUnit = $null\r\n        ManagedBy          = $ownersToAdd\r\n        Members            = $membersToAdd\r\n        CopyOwnerToMember  = $true\r\n        ErrorAction        = \"Stop\"\r\n    }\r\n\r\n    Switch ($distributionGroupType) {\r\n        \u0027Mail-enabled Security Group\u0027 {\r\n            $exchangeDistributionGroupParams.OrganizationalUnit = $ADmailenabledSecurityGroupsOU\r\n            $response = New-DistributionGroup -Type security @exchangeDistributionGroupParams\r\n        }\r\n\r\n        \u0027Distribution Group\u0027 {\r\n            $exchangeDistributionGroupParams.OrganizationalUnit = $ADdistributionGroupsOU\r\n            $response = New-DistributionGroup @exchangeDistributionGroupParams\r\n        }\r\n    }\r\n\r\n    $exchangeSetDistributionGroupParams = @{\r\n        Identity                  = \"$($response.GUID)\"\r\n        EmailAddressPolicyEnabled = $false\r\n    }\r\n    $null = Set-DistributionGroup @exchangeSetDistributionGroupParams\r\n    Write-Information \"Successfully created distributiongroup for $distributionGroupDisplayName\" \r\n    \r\n    $Log = @{\r\n        Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = \"Created distribution group:  $($response.displayName)\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $($response.displayName) # optional (free format text) \r\n        TargetIdentifier  = $([string]$response.Guid)  # optional (free format text) \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log       \r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception)\"\r\n    }\r\n\r\n    # Send error audit log to HelloID\r\n    $Log = @{\r\n        Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $mailbox.DisplayName # optional (free format text) \r\n        TargetIdentifier  = $mailbox.PrimarySmtpAddress # optional (free format text) \r\n    }\r\n    \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}\r\nfinally {\r\n    # Disconnect from Exchange\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession\r\n    if ($null -ne $exchangeSession) {\r\n        try {\r\n            $deleteExchangeSessionSplatParams = @{\r\n                Session     = $exchangeSession\r\n                Confirm     = $false\r\n                ErrorAction = \"Stop\"\r\n            }\r\n            $null = Remove-PSSession @deleteExchangeSessionSplatParams\r\n\r\n            # Send disconnect audit log\r\n            $Log = @{\r\n                Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                Message           = \"Successfully disconnected from Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n                TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n            }\r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            Write-Warning \"Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)\"\r\n        }\r\n    }\r\n}\r\n\r\n","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-at" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>


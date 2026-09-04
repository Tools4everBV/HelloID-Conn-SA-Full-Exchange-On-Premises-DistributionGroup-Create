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

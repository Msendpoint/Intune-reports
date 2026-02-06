<#
.SYNOPSIS
    Intune Master Monitor
    About Author:
    /\_/\__Souhaiel MORHAG__/\_/\
    Find the Author on:
    Linkedin: https://www.linkedin.com/in/souhaiel-morhag-3656a1107/
    Github: https://github.com/Msendpoint
    Website: https://msendpoint.com/
    
.DESCRIPTION
    -"Top Contributors" breakdown by Admin & Category
    - Outlook-optimized "Clean Card" design report
    - Monitor your Intune Envirenement like a pro
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Recipients, 

    [Parameter(Mandatory = $true)]
    [string]$SenderUPN, 

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 90)]
    [int]$DaysBack = 1
)

# ============================================================================
# 1. ROBUST API FUNCTIONS
# ============================================================================

function Get-GraphHeader {
    try {
        $resourceURI = "https://graph.microsoft.com"
        $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=$resourceURI&api-version=2019-08-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER" = $env:IDENTITY_HEADER} -Uri $tokenAuthURI
        return @{ "Authorization" = "Bearer $($tokenResponse.access_token)"; "Content-Type" = "application/json" }
    }
    catch { Throw "Managed Identity Auth Failed: $_" }
}

function Get-GraphData {
    param($Uri, $Headers)
    $results = @()
    $nextLink = $Uri
    
    do {
        try {
            $retryCount = 0; $success = $false
            while (-not $success -and $retryCount -lt 3) {
                try {
                    $response = Invoke-RestMethod -Uri $nextLink -Headers $Headers -Method GET -ErrorAction Stop
                    $success = $true
                }
                catch { Start-Sleep -Seconds 5; $retryCount++ }
            }
            if ($response.value) { $results += $response.value }
            $nextLink = $response.'@odata.nextLink'
        }
        catch { $nextLink = $null }
    } while ($nextLink)
    
    return $results
}

function Get-FriendlyName {
    param($Id, $Headers, $Cache, $Type="Group")
    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }
    if ($Cache.ContainsKey($Id)) { return $Cache[$Id] }
    
    try {
        if ($Type -eq "Group") { $uri = "https://graph.microsoft.com/v1.0/groups/$Id`?`$select=displayName" } 
        else { $uri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$Id`?`$select=displayName" }
        
        $resp = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET -ErrorAction Stop
        $Cache[$Id] = $resp.displayName; return $resp.displayName
    } catch { $Cache[$Id] = "$Id"; return "$Id" }
}

function Get-AssignmentDiff {
    <# Handles Nulls safely to prevent Compare-Object crashes #>
    param($OldVal, $NewVal, $Headers, $Cache)
    
    try {
        $oldJson = if (-not [string]::IsNullOrWhiteSpace($OldVal)) { $OldVal | ConvertFrom-Json -ErrorAction SilentlyContinue } else { @() }
        $newJson = if (-not [string]::IsNullOrWhiteSpace($NewVal)) { $NewVal | ConvertFrom-Json -ErrorAction SilentlyContinue } else { @() }
        if (-not ($oldJson -is [array])) { $oldJson = @($oldJson) }
        if (-not ($newJson -is [array])) { $newJson = @($newJson) }
    } catch { return "Complex Assignment Change" }

    $fnBuildKey = { param($obj) 
        if ($null -eq $obj) { return $null }
        $g = if ($obj.target.groupId) { $obj.target.groupId } else { "AllDevices/Users" }
        $f = if ($obj.target.deviceAndAppManagementAssignmentFilterId) { " [Filter: $($obj.target.deviceAndAppManagementAssignmentFilterId)]" } else { "" }
        return "$g$f"
    }

    $oldKeys = $oldJson | ForEach-Object { & $fnBuildKey $_ }
    $newKeys = $newJson | ForEach-Object { & $fnBuildKey $_ }

    if ($null -eq $oldKeys -and $null -eq $newKeys) { return $null }
    if ($null -eq $oldKeys) { $oldKeys = @() }
    if ($null -eq $newKeys) { $newKeys = @() }

    $added   = Compare-Object -ReferenceObject $oldKeys -DifferenceObject $newKeys | Where-Object SideIndicator -eq "=>" | Select-Object -ExpandProperty InputObject
    $removed = Compare-Object -ReferenceObject $oldKeys -DifferenceObject $newKeys | Where-Object SideIndicator -eq "<=" | Select-Object -ExpandProperty InputObject

    $result = @()
    if ($added) {
        foreach ($item in $added) {
            if ($item -match "Filter: (.+?)\]") { $item = $item.Replace($matches[1], (Get-FriendlyName -Id $matches[1] -Headers $Headers -Cache $Cache -Type "Filter")) }
            $item = [regex]::Replace($item, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', { param($m) Get-FriendlyName -Id $m.Value -Headers $Headers -Cache $Cache })
            $result += "<b style='color:#059669'>+ Added:</b> $item"
        }
    }
    if ($removed) {
        foreach ($item in $removed) {
            if ($item -match "Filter: (.+?)\]") { $item = $item.Replace($matches[1], (Get-FriendlyName -Id $matches[1] -Headers $Headers -Cache $Cache -Type "Filter")) }
            $item = [regex]::Replace($item, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', { param($m) Get-FriendlyName -Id $m.Value -Headers $Headers -Cache $Cache })
            $result += "<b style='color:#dc2626'>- Removed:</b> $item"
        }
    }

    return ($result -join "<br/>")
}

function New-HtmlReport {
    param($Changes, $Stats, $DaysBack)
    
    $iconEdit = "&#9999;"; $iconAdd = "&#10010;"; $iconDel = "&#10060;"
    
    # --- GENERATE CONTRIBUTORS TABLE ---
    $contribHtml = ""
    if ($Changes.Count -gt 0) {
        $admins = $Changes | Group-Object User | Sort-Object Count -Descending
        $contribRows = ""
        foreach ($admin in $admins) {
            # Breakdown by Category
            $breakdown = $admin.Group | Group-Object PolicyType | ForEach-Object { "$($_.Count) $($_.Name)" }
            $breakdownStr = $breakdown -join ", "
            
            $contribRows += "<tr><td style='padding:8px; border-bottom:1px solid #f3f4f6; color:#374151; font-weight:600;'>$($admin.Name)</td><td style='padding:8px; border-bottom:1px solid #f3f4f6; text-align:center; color:#111827;'>$($admin.Count)</td><td style='padding:8px; border-bottom:1px solid #f3f4f6; color:#6b7280; font-size:11px;'>$breakdownStr</td></tr>"
        }
        
        $contribHtml = @"
        <table width='100%' cellspacing='0' cellpadding='0' border='0' style='background-color:#ffffff; border:1px solid #e5e7eb; border-radius:8px; margin-bottom:20px; overflow:hidden;'>
            <tr><td colspan='3' style='background-color:#f8fafc; padding:10px 15px; font-weight:bold; color:#1e40af; border-bottom:1px solid #e5e7eb;'>&#127942; Top Contributors</td></tr>
            <tr style='background-color:#f9fafb; font-size:11px; text-transform:uppercase; color:#6b7280;'>
                <th align='left' style='padding:8px;'>Admin</th>
                <th align='center' style='padding:8px;'>Actions</th>
                <th align='left' style='padding:8px;'>Breakdown</th>
            </tr>
            $contribRows
        </table>
"@
    }

    # --- GENERATE CHANGE CARDS ---
    $rowsHtml = ""
    foreach ($item in $Changes) {
        $headerColor = "#3b82f6"; $badgeBg = "#eff6ff"; $badgeText = "#1d4ed8"
        if ($item.Severity -eq "High") { $headerColor = "#ef4444"; $badgeBg = "#fef2f2"; $badgeText = "#b91c1c" }
        elseif ($item.Severity -eq "Medium") { $headerColor = "#f59e0b"; $badgeBg = "#fffbeb"; $badgeText = "#b45309" }

        $actionIcon = $iconEdit
        if ($item.Action -match "Delete") { $actionIcon = $iconDel }
        if ($item.Action -match "Create") { $actionIcon = $iconAdd }

        $detailsHtml = ""
        if ($item.Details) {
            $splitDetails = $item.Details -split "\|\|"
            foreach ($d in $splitDetails) {
                if ($d -match ":=") {
                    $parts = $d -split ":=", 2
                    $label = $parts[0].Trim()
                    $val   = $parts[1].Trim()
                    if ($val -match "➔") {
                        $val = $val -replace "(.+) ➔ (.+)", "<span style='text-decoration:line-through; color:#9ca3af;'>$1</span> <span style='color:#059669; font-weight:bold;'>➔ $2</span>"
                    }
                    $detailsHtml += "<tr><td style='padding:5px 0; color:#6b7280; font-size:12px; width:130px; vertical-align:top; border-bottom:1px solid #f3f4f6;'>$label</td><td style='padding:5px 0; color:#374151; font-size:12px; border-bottom:1px solid #f3f4f6; font-family:Consolas, monospace;'>$val</td></tr>"
                }
            }
        } else {
            $detailsHtml = "<tr><td colspan='2' style='padding:5px 0; color:#9ca3af; font-size:12px; font-style:italic;'>Metadata update only (No major property changes)</td></tr>"
        }

        $rowsHtml += @"
        <table width='100%' cellpadding='0' cellspacing='0' border='0' style='background-color:#ffffff; border:1px solid #e5e7eb; border-radius:8px; margin-bottom:20px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); overflow:hidden;'>
            <tr>
                <td style='background-color:#ffffff; padding:15px; border-top: 4px solid $headerColor;'>
                    <table width='100%' cellpadding='0' cellspacing='0'>
                        <tr>
                            <td style='font-family:Segoe UI, sans-serif; font-weight:700; font-size:16px; color:#111827;'>
                                <span style='font-size:18px; margin-right:8px; text-decoration:none;'>$actionIcon</span> $($item.PolicyName)
                            </td>
                            <td align='right' style='width:90px;'>
                                <span style='background-color:$badgeBg; color:$badgeText; padding:4px 10px; border-radius:4px; font-size:11px; font-weight:bold; font-family:sans-serif; border:1px solid $badgeBg;'>$($item.Severity)</span>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>
            <tr>
                <td style='padding:0 15px 15px 15px;'>
                    <table width='100%' cellpadding='0' cellspacing='0'>
                        <tr>
                            <td style='padding-bottom:15px; border-bottom:2px solid #f3f4f6;'>
                                <div style='font-size:12px; color:#6b7280; line-height:1.6;'>
                                    <span style='font-weight:600; color:#4b5563;'>$($item.User)</span>
                                    <span style='margin:0 8px; color:#d1d5db;'>|</span>
                                    <span>$($item.DateTime.ToString('MMM dd, HH:mm'))</span>
                                    <span style='margin:0 8px; color:#d1d5db;'>|</span>
                                    <span style='background-color:#f3f4f6; padding:2px 6px; border-radius:4px;'>$($item.PolicyType)</span>
                                </div>
                            </td>
                        </tr>
                        <tr>
                            <td style='padding-top:10px;'>
                                <table width='100%' cellpadding='0' cellspacing='0'>
                                    $detailsHtml
                                </table>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>
        </table>
"@
    }

    if ([string]::IsNullOrWhiteSpace($rowsHtml)) { $rowsHtml = "<div style='text-align:center; padding:20px; color:#666;'>No significant changes detected.</div>" }

    $html = @"
<!DOCTYPE html>
<html>
<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0; padding:0; background-color:#f9fafb; font-family:'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;">
    <center>
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" width="100%" style="max-width: 650px; margin: auto;">
            <tr>
                <td style="padding: 20px 10px;">
                    <table width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#1e40af; border-radius:8px 8px 0 0; overflow:hidden;">
                        <tr>
                            <td style="padding: 30px 25px; text-align:center;">
                                <h1 style="margin:0; font-size:24px; color:#ffffff; font-weight:600; letter-spacing:-0.5px;">Intune Monitor</h1>
                                <p style="margin:5px 0 0 0; color:#93c5fd; font-size:14px;">Report for last $DaysBack days</p>
                            </td>
                        </tr>
                    </table>
                    <table width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#ffffff; border-bottom:1px solid #e5e7eb; padding:20px;">
                        <tr>
                            <td align="center" width="33%" style="border-right:1px solid #f3f4f6;">
                                <div style="font-size:24px; font-weight:bold; color:#111827;">$($Stats.TotalChanges)</div>
                                <div style="font-size:10px; text-transform:uppercase; color:#6b7280; font-weight:600; margin-top:4px;">Events</div>
                            </td>
                            <td align="center" width="33%" style="border-right:1px solid #f3f4f6;">
                                <div style="font-size:24px; font-weight:bold; color:#ef4444;">$($Stats.HighSeverity)</div>
                                <div style="font-size:10px; text-transform:uppercase; color:#6b7280; font-weight:600; margin-top:4px;">High Impact</div>
                            </td>
                            <td align="center" width="33%">
                                <div style="font-size:24px; font-weight:bold; color:#f59e0b;">$($Stats.MediumSeverity)</div>
                                <div style="font-size:10px; text-transform:uppercase; color:#6b7280; font-weight:600; margin-top:4px;">Modified</div>
                            </td>
                        </tr>
                    </table>
                    
                    $contribHtml
                    
                    <table width="100%" cellspacing="0" cellpadding="0" border="0" style="padding:20px 0;">
                        <tr><td>$rowsHtml</td></tr>
                        <tr><td align="center" style="padding-top:10px; color:#9ca3af; font-size:11px;">Generated by Azure Automation</td></tr>
                    </table>
                </td>
            </tr>
        </table>
    </center>
</body>
</html>
"@
    return $html
}

# ============================================================================
# 2. MAIN EXECUTION
# ============================================================================

$headers = Get-GraphHeader
$groupCache = @{}
$startDate = (Get-Date).ToUniversalTime().AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Output "Searching Intune logs since $startDate (UTC)..."

# Removed Enrollment as requested
$auditCategories = @("DeviceConfiguration", "Compliance", "DeviceIntent", "Application", "MobileApp", "Role", "Authorization")
$allRawEvents = @()

foreach ($cat in $auditCategories) {
    $uri = "https://graph.microsoft.com/beta/deviceManagement/auditEvents?`$filter=activityDateTime ge $startDate and category eq '$cat'&`$orderby=activityDateTime desc"
    $events = Get-GraphData -Uri $uri -Headers $headers
    if ($events) { $allRawEvents += $events }
}

if ($allRawEvents.Count -eq 0) { Write-Output "No changes found. Exiting."; exit 0 }

# --- 3. SMART PROCESSING ---
$processedData = @()

$IgnoredProperties = @(
    "SettingCount", "LastModifiedDateTime", "CreatedDateTime", "Version", "SequenceNumber", 
    "DeviceManagementAPIVersion", "SupportsScopeTags", "IsEncrypted", "RoleScopeTagIds", 
    "DependentAppCount", "UploadState", "PublishingState", "IsFeatured", "InformationUrl", 
    "PrivacyInformationUrl", "MsiInformation.PackageType", "MsiInformation.RequiresReboot"
)
$IgnoredPatterns = "MsiInformation|Guid|Identifier"

foreach ($ev in $allRawEvents) {
    if ($ev.activityType -match "Get|Read") { continue }

    $severity = "Low"
    $actionRaw = $ev.activityType -replace 'DeviceManagement','' -replace 'Configuration','Config'
    if ($ev.activityResult -eq "failure") { $severity = "High" }
    elseif ($actionRaw -match "Delete")   { $severity = "High" }
    elseif ($actionRaw -match "Create|Patch|Update|Modify") { $severity = "Medium" }
    if ($actionRaw -match "Assignment")   { $severity = "Low" }

    $detailList = @()
    
    if ($actionRaw -match "Delete") {
        $detailList += "Status:=Object Deleted"
        if ($ev.resources[0].resourceId) { $detailList += "ID:=$($ev.resources[0].resourceId)" }
    }
    else {
        if ($ev.resources[0].modifiedProperties) {
            foreach ($prop in $ev.resources[0].modifiedProperties) {
                $pName = $prop.displayName; $newVal = $prop.newValue; $oldVal = $prop.oldValue

                if ($pName -in $IgnoredProperties) { continue }
                if ($pName -match $IgnoredPatterns) { continue }

                if ($pName -match "assignments|target") {
                    $diffText = Get-AssignmentDiff -OldVal $oldVal -NewVal $newVal -Headers $headers -Cache $groupCache
                    if ($diffText) { $detailList += "Assignments:=$diffText" }
                    continue
                }

                if (-not [string]::IsNullOrWhiteSpace($oldVal) -and $oldVal -ne $newVal -and $oldVal -ne "[]") {
                    $newVal = "$oldVal ➔ $newVal"
                }
                
                # Truncate
                if ($newVal.Length -gt 150) { $newVal = $newVal.Substring(0,147) + "..." }

                if (-not [string]::IsNullOrWhiteSpace($newVal)) { 
                    $detailList += "${pName}:=$newVal" 
                }
            }
        }
    }

    if ($detailList.Count -eq 0) { continue }
    
    $processedData += [PSCustomObject]@{
        DateTime   = $ev.activityDateTime
        PolicyName = if ($ev.resources[0].displayName) { $ev.resources[0].displayName } else { "Unknown ($($ev.resources[0].resourceId))" }
        PolicyType = $ev.category
        Action     = $actionRaw
        User       = if ($ev.actor.userPrincipalName) { $ev.actor.userPrincipalName } else { "System" }
        Severity   = $severity
        Details    = $detailList -join "||"
    }
}

# --- 4. OUTPUT ---
if ($processedData.Count -eq 0) { Write-Output "No significant changes after filtering."; exit 0 }
$stats = @{ TotalChanges = $processedData.Count; HighSeverity = ($processedData | Where Severity -eq 'High').Count; MediumSeverity = ($processedData | Where Severity -eq 'Medium').Count }

$htmlBody = New-HtmlReport -Changes $processedData -Stats $stats -DaysBack $DaysBack
$base64Csv = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($processedData | ConvertTo-Csv -NoTypeInformation)))

$recipientList = @(); foreach ($email in ($Recipients -split ",")) { if (-not [string]::IsNullOrWhiteSpace($email)) { $recipientList += @{ emailAddress = @{ address = $email.Trim() } } } }
if ($recipientList.Count -eq 1) { $finalToRecipients = @( , $recipientList[0] ) } else { $finalToRecipients = $recipientList }

$emailBody = @{
    message = @{
        subject = "Intune Monitor - $(Get-Date -Format 'yyyy-MM-dd')"
        body = @{ contentType = "HTML"; content = $htmlBody }
        toRecipients = $finalToRecipients
        attachments = @( @{ "@odata.type" = "#microsoft.graph.fileAttachment"; name = "IntuneLog.csv"; contentType = "text/csv"; contentBytes = $base64Csv } )
    }
    saveToSentItems = $true
}

$sendMailUri = "https://graph.microsoft.com/v1.0/users/$SenderUPN/sendMail"
Invoke-RestMethod -Uri $sendMailUri -Headers $headers -Method POST -Body ($emailBody | ConvertTo-Json -Depth 10) -ContentType "application/json"
Write-Output "Report sent."

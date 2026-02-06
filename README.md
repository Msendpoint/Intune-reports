# 🛡️ Intune Master Monitor

> **Monitor your Intune Environment like a Pro.**

**Intune Master Monitor** is a powerful Azure Automation Runbook designed to revolutionize how you track changes in Microsoft Endpoint Manager. Instead of sifting through raw, noisy audit logs, this tool delivers a intelligent, high-fidelity HTML report directly to your inbox.

It solves the "Metadata Ghost" problem by filtering out backend system updates and focusing purely on **what changed, who changed it, and when**.

[![Intune Monitor Preview](https://github.com/Msendpoint/Intune-reports/blob/main/msendpoint.png)](https://msendpoint.com)

---

## 🌐 About the Author

**Souhaiel MORHAG** 🚀 **Visit [MSendpoint.com](https://msendpoint.com/) for more Intune guides, scripts, and Pro tips!** 
* [LinkedIn Profile](https://www.linkedin.com/in/souhaiel-morhag-3656a1107/)  
* [GitHub Repository](https://github.com/Msendpoint)

---

## 🚀 Key Features

* **🧠 Smart Noise Filtering:** Automatically ignores 20+ backend metadata properties (timestamps, version hashes) to show only *real* admin actions.
* **🔍 Precision Diffing:** Shows exactly what changed using an `Old Value ➔ New Value` format.
* **👥 Assignment Tracking:** Specifically detects and highlights when Groups or Filters are **Added** or **Removed**.
* **🏆 Top Contributors:** A "Leaderboard" summary showing which Admins are most active and what categories they are modifying.
* **📧 Outlook Optimized:** Features a beautiful "Clean Card" design that renders perfectly in Outlook Desktop, Web, and Mobile.
* **☁️ Serverless:** Runs entirely in Azure Automation with Managed Identities—no hardcoded passwords!

---

## 🛠️ Setup Guide: From A to Z

Follow this step-by-step guide to get the monitor running in your environment in under 15 minutes.

### Phase 1: Create the Automation Account

1.  Log in to the **[Azure Portal](https://portal.azure.com)**.
2.  Search for **"Automation Accounts"** and click **Create**.
3.  **Basics Tab:**
    * **Subscription:** Select your subscription.
    * **Resource Group:** Create new (e.g., `RG-IntuneMonitor`) or select existing.
    * **Name:** `Intune-Master-Monitor`.
    * **Region:** Select your preferred region.
4.  **Advanced Tab:** Ensure **System assigned** under "Managed identities" is checked (This is usually default).
5.  Click **Review + Create** > **Create**.

### Phase 2: Enable Identity & Permissions

The script uses the Automation Account's identity to read Intune data securely.

1.  Go to your new **Automation Account**.
2.  On the left menu, under **Account Settings**, click **Identity**.
3.  Ensure the **System assigned** tab status is **On**.
4.  **Copy the "Object (principal) ID"** shown on screen.

**⚠ Critical Step: Grant Permissions**
You must grant this identity permission to read Intune and send emails. Run the following PowerShell script on your local machine (Requires Global Admin rights):

```powershell
# Install module if needed
# Install-Module Microsoft.Graph -Scope CurrentUser

Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All","Application.Read.All"

# 1. Enter the Object ID you copied from the Azure Portal
$ManagedIdentityId = "PASTE_YOUR_OBJECT_ID_HERE"

# 2. Get Microsoft Graph Service Principal
$GraphApp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# 3. Define Required Permissions
$Permissions = @(
    "DeviceManagementConfiguration.Read.All", # Read Policies/Profiles
    "DeviceManagementApps.Read.All",          # Read Apps
    "Group.Read.All",                         # Resolve Group Names
    "DeviceManagementRBAC.Read.All",          # Read Roles
    "Mail.Send"                               # Send HTML Report
)

# 4. Assign Permissions
foreach ($Name in $Permissions) {
    $AppRole = $GraphApp.AppRoles | Where-Object { $_.Value -eq $Name }
    New-MgServicePrincipalAppRoleAssignment -PrincipalId $ManagedIdentityId -ResourceId $GraphApp.Id -AppRoleId $AppRole.Id
    Write-Host "Assigned: $Name" -ForegroundColor Green
}

```

### Phase 3: Deploy the Script

1. In your Automation Account, go to **Process Automation** > **Runbooks**.
2. Click **+ Create a runbook**.
3. **Name:** `Intune-Monitor`.
4. **Runbook type:** `PowerShell`.
5. **Runtime version:** `7.2` (Recommended) or `5.1`.
6. Click **Create**.
7. **Paste the script** from `IntuneMonitor.ps1` in this repository into the editor.
8. Click **Save** then **Publish**.

### Phase 4: Schedule It

1. In the Runbook, on the left menu, click **Schedules**.
2. Click **+ Add a schedule**.
3. **Link a schedule to your runbook:**
* Create a new schedule (e.g., "Daily-8AM").
* Set **Recurrence** to **Recurring** > **Every 1 Day**.


4. **Configure parameters:**
* **Recipients:** `admin@yourdomain.com, manager@yourdomain.com`
* **SenderUPN:** `notifications@yourdomain.com` (Must be a real mailbox or shared mailbox with Mail.Send rights).
* **DaysBack:** `1` (Since it runs daily).


5. Click **OK**.

---

## 📸 Sample Report

### Clean Change Cards

*Changes are presented in easy-to-read cards with color-coded severity.*

### Top Contributors

*See exactly who is making changes in your environment and what they are touching.*

---

## 🛡️ Troubleshooting

**Q: I get a "Bad Request" or 403 error.**

* **A:** Check Phase 2. Did you run the permission script successfully? Does the `SenderUPN` mailbox exist and have a license (or is it a shared mailbox)?

**Q: The report is empty.**

* **A:** By default, the script hides "Metadata updates" (where Intune updates a timestamp but changes nothing else). If no *real* changes happened, the report will say "No significant changes found".

**Q: Why do I see "??" characters?**

* **A:** Ensure you are using the latest version of the script which uses HTML Entities (`&#9999;`) instead of literal emojis, which can break in some Azure environments.

---

### ❤️ Support the Project

If you find this tool useful, check out my blog at **[MSendpoint.com](https://msendpoint.com/)** for more deep dives into Microsoft Endpoint Manager, Security, and Automation.

*Star this repo if it saved you time! ⭐*

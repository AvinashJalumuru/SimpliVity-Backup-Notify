##################################################################
# Use PowerShell and the SimpliVity REST API  to 
# To Notify a Report of Backups Taken in the Last N Hours
#
# Usage: SVT-NotifyVMBackupReport.ps1
#
##################################################################
############## BEGIN USER VARIABLES ############## 

# Absolute path of the input file
Param(
	[Parameter(Mandatory=$True)]
	[string]
	$InputFile,
	
	[Boolean]
	$FullData = $False
)

############### END USER VARIABLES ###############

########## BEGIN INPUT DATA VALIDATION ###########
if (-NOT (Test-Path $inputFile)) {
    Write-Error "Input Data file is not present in the given path $inputFile"
    exit 1
}
########### END INPUT DATA VALIDATION ############

############### BEGIN READ DATA  #################

Try {
    $File = Split-Path $inputFile -Leaf
    $ParentDir = Split-Path $inputFile -Parent
    Import-LocalizedData -BindingVariable input_data -BaseDirectory $ParentDir -FileName $File

    # Read svt details
    $svt_ovc_ip = $input_data.svt.ovc
    $svt_username  = $input_data.svt.username
    $svt_password = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($input_data.svt.password))

    # Read smtp server details
    $smtp_server = $input_data.smtp.server
    $smtp_port   = $input_data.smtp.port
    $smtp_email_user   = $input_data.smtp.email_user
    # $smtp_email_passwd = $input_data.smtp.email_passwd

    $smtp_email_passwd = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($input_data.smtp.email_passwd))
    $smtp_ssl_enable   = [System.Convert]::ToBoolean($smtp.ssl_enable)

    # Read the logging file
    $execution_log = $input_data.logging.execution
    $output_log = $input_data.logging.output
} Catch {
    Write-Error "Failed to read input $_.ExceptionItemName from datafile $inputFile. $_.Exception.Message"
    exit 1
}

################ END READ DATA  ##################

################ GET BACKUP FUNCTION  ##################
Function GetVMBackups() {
	Param(
		[string]
		$url,
		
		[array]
		$backupParams,
		
		[string]
		$TempLogFile
	)
	
	"$(get-date -Format o) Rest URL:with: $url" | Out-File $execution_log -Append -Force
    $BackupList = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
	
    For ($iter=0; $iter -lt [int]$BackupList.count; $iter++) {
        $BackupList[$iter].backups | sort virtual_machine_name,state,created_at | FT -Autosize -Wrap $BackupParams | Out-File $TempLogFile -Append
    }
	
	return $($BackupList.count)
}
################ GET BACKUP FUNCTION : END ##################

"$(get-date -Format o) ############## SVT-NotifyVMBackupReport.ps1 Started #################" | Out-File $execution_log -Append -Force
Write-Host "SVT-NotifyVMBackupReport.ps1 Started"

"$(get-date -Format o) Input Validation passed" | Out-File $execution_log -Append -Force

#Ignore Self Signed Certificates and set TLS
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

$baseUrl = "https://" + $svt_ovc_ip + "/api"
$AUTH_URI = "/oauth/token"

################ SVT AUTHENTICATION  ##################
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f "simplivity","")))

$body = @{username="$svt_username";password="$svt_password";grant_type="password"}
$headers = @{Authorization=("Basic {0}" -f $base64AuthInfo)}
$response = Invoke-RestMethod -Uri ($baseUrl + $AUTH_URI) -Headers $headers -Body $body -Method Post 

$accessToken = $response.access_token
"$(get-date -Format o) Generated Simplivity Auth Token $accessToken" | Out-File $execution_log -Append -Force
################ SVT AUTHENTICATION END ##################

If ($accessToken -eq $null) {
	Write-Error "Failed to retrieve Simplivity token. $response"
    exit 1
}

# Create SVT Auth Header
$headers =@{Authorization="Bearer $accessToken"}

################ GET PREVIOUS EXECUTION TIME ##################
# Get reporting hours to last execution time
if (-NOT (Test-Path last_execution_time.log)) {
    $reportTime = (get-date).AddHours(-48)
    $FullData = $True
    "$(get-date -Format o) No previous execution Found. Fetch all backup information" | Out-File $execution_log -Append -Force
}
else {
    attrib -h last_execution_time.log
    [DateTime]$reportTime = get-content last_execution_time.log
    "$(get-date -Format o) Last backup notification fetched at $reportTime" | Out-File $execution_log -Append -Force
}
(get-date -Format o) | Out-File last_execution_time.log
attrib +h last_execution_time.log

# Format Date Correctly for SVT REST API
$reportTime = $reportTime.ToUniversalTime()
$createdafter = (get-date $reportTime -Format s) + "Z"
################ GET PREVIOUS EXECUTION TIME - END ##################

# Read the Group info from input data
$groups = $input_data.org_groups
foreach($grp in $groups) {
    $vms = $grp.virtual_machines
    $emailIds = $grp.mail_addresses
    $Subject = $grp.email_subject
    $backupParams = $grp.backup_params

    if ($vms.count -gt 0) {
        # Get Input VMs - Format Correctly for SVT REST API
        "$(get-date -Format o) Found VMs ($vms) in the config file" | Out-File $execution_log -Append -Force
        
        # If Email Subject is not chosen, prepare subject with Time and VMs Information
        if (-Not $Subject) {
            $Subject = "[" + (get-date -format s) + "]: Backup information of Virtual Machines " + $vms
        }

        # If no input backup params given, choose the default parameters 
        if (-NOT $backupParams) {
            $backupParams = "name","virtual_machine_name","state","created_at","datastore_name","type"
        }

        # Perform full backup search if no previous executions
        if ($FullData) {
            $backupBaseUrl = $baseUrl + "/backups?virtual_machine_name={0}"
            $reportTime = "beginning"
        }
        else {
            $backupBaseUrl = $baseUrl + "/backups?virtual_machine_name={0}&created_after=" + $createdafter
        }
		
		# Format the backup output and push to a stack file
        $stackFile = "$env:TEMP\stackFile.log"
		$backupCount = 0

		# While developing, Simplivity has a bug in filtering with query for getting backups.
		# So taking backup for individual VMs
		#
		# Query Parameters: "&virtual_machine_name=$VM1%2CVM2" 
		# No output is returned for backups with multiple VM queries.
		# Testing is performed on 3.7.6 and 3.7.7
		
        # Powershell input PSD read function returns array for multiple values
        # and string object for single value. Condition to handle this scenario
        if ($vms -is [array]) {
            for ($i = 0; $i -lt [int]$vms.Length; $i++) {
				$backupUrl = $backupBaseUrl -f $vms[$i]
				$backupCount += GetVMBackups -url $backupUrl -BackupParams $backupParams -TempLogFile $stackFile
            }
        }
        else {
			$backupUrl = $backupBaseUrl -f $vms
			$backupCount += GetVMBackups -url $backupUrl -BackupParams $backupParams -TempLogFile $stackFile
        }

        "$(get-date -Format o) Backups Found for VMs ($vms): $backupCount" | Out-File $execution_log -Append -Force
        Write-Host "Backups Found for VMs ($vms): $backupCount"

        # If stack file is not present, no backups are observed in the output and skip for the other group
        if (-NOT (Test-Path $stackFile) ){
            Write-Host "No backup taken since the last execution for Virtual Machines $vms" | Out-File $execution_log -Append -Force
            continue;
        }

        # Push the output data and remove the temporary file    
        $backup_info = Get-Content -raw $stackFile
        Remove-Item $stackFile
    
        $body = "
Reporting successful Backups of virtual machines $vms since $reportTime :

$backup_info
This is a system generated email, kindly do not reply to this mail
==============================================================================================================="

        # Send backup details to the EMAIL addresses
        $emailFrom = $smtp_email_user

        if (-Not $Subject) {
            $Subject = "[" + (get-date -format s) + "]: Backup information of Virtual Machines " + $vms
        }

        $SMTPClient = New-Object System.Net.Mail.SmtpClient($smtp_server, $smtp_port)
        $SMTPClient.EnableSsl = $smtp_ssl_enable
        $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($smtp_email_user, $smtp_email_passwd)
		
        "$(get-date -Format o) Logging email output of VMs $vms" | Out-File $output_log -Append -Force
        "Subject: $Subject" | Out-File $output_log -Append -Force
        "Email Body: $body" | Out-File $output_log -Append -Force

        foreach ($EmailTo in $EmailIds) {
            #Write-Host "$SMTPClient.Send($EmailFrom, $EmailTo, $Subject)"
            $SMTPClient.Send($EmailFrom, $EmailTo, $Subject, $Body)

            "$(get-date -Format o) Backup of VMs $vms is notified to $EmailTo" | Out-File $execution_log -Append -Force
            Write-Host "Backup of VMs $vms is notified to $EmailTo" | Out-File $execution_log -Append -Force
        }
        Write-Host  "-----------------------------------"
    }
}

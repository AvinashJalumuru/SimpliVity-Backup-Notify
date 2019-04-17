# SimpliVity-Backup-Notify
Simple script to notify incremental backups in SimpliVity.

By using this script,
1. Users are notified over email about the status of the incremental backups of their virtual machines.
2. Multiple groups can configured to send the backup status of their specific VMs.
3. Choice of backup parameters needed by the group can be configured in the input file.

### Files Info

##### Powershell/input.psd1
- Input file used by Powershell/SVT-NotifyVMBackupReport.ps1
- The details of SimpliVity, SMTP and Logging should be provided
- In the org_grps section, `virtual_machines` and `mail_addresses` are mandatory
 
  `backup_params` is optional. By using this option, group can chose the list of backup parameters they are interested in.

  If there is no `backup_params` section, default set of parameters will be displayed in the notification email.
  ("name","virtual_machine_name","state","created_at","datastore_name","type")

##### Powershell/encode.ps1
- Helper to encode passwords of SVT password, SMTP password

##### Powershell/SVT-NotifyVMBackupReport.ps1
- Script that sends checks and sends notification
- Timestamp of the execution is stored in a hidden file to send the periodic updates (last exection time)
- Add to the task scheduler and send notification of backup status

Though the script is on tested on Powershell version 5, this can be executed from any Windows machine supporting Powershell Version 3+
(Script uses Invoke-RestMethod and minimum of Powershell version 3 is required)

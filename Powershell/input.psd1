@{
    svt =
    @{
        ovc      = 'XX.XX.XX.XX'
        username = 'svt_username'
        password = 'cABhAHMAcwB3AG8AcgBkAA=='
    }
        smtp =
        @{
            server = 'smtp.example.com'
            port   = '25'
            email_user   = 'noreply@example.com'
            email_passwd = 'cABhAHMAcwB3AG8AcgBkAA=='
            ssl_enable   = 'true'
        }
    org_groups =
    @(
        @{
            virtual_machines = 'rhel75','UbuntuVM'
            mail_addresses   = 'user1@example.com','user2@example.com'
            backup_params    = @('virtual_machine_name','state','created_at')
        },
        @{
            virtual_machines = 'rhel75'
            mail_addresses   = 'user1@example.com','user3@example.com','user4@example.com'
        }
    )
    logging =
    @{
        output    = 'C:\Users\DemoAdmin\Desktop\BackupNotification\output.log'
        execution = 'C:\Users\DemoAdmin\Desktop\BackupNotification\execution.log'
    }
}

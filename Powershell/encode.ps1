$input  = Read-Host "Enter the password to encode: "
$encode = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($input))

$encode
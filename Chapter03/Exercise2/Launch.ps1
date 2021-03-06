
#This script will launch an new instance and embed the bootstrap script in the user data section as described in exercise 2 of chapter 3  

param(
    [parameter(mandatory=$false)][string]$KeyName = 'MyKey',
    [parameter(mandatory=$false)][string]$RoleName = 'AdminRole',
    [parameter(mandatory=$false)][string]$UserDataFile = 'C:\AWS\Chapter3\Exercise2\Bootstrap.ps1',
    [parameter(mandatory=$false)][string]$ImageId,
    [parameter(mandatory=$false)][string]$InstanceType = 't1.micro'
)

#If no image was specified, assume 2012 base
If([System.String]::IsNullOrEmpty($ImageID)){ $ImageID = (Get-EC2ImageByName  -Name "WINDOWS_2012_BASE")[0].ImageId}

#Read the bootstrap script from the file specified
$BootstrapScript = Get-Content $UserDataFile

#Get-Content returns an array of strings.  Convert the array to a single string
$BootstrapScript = [System.String]::Join("`r`n", $BootstrapScript )

#Add the PowerShell tags to the script
$BootstrapScript = @"
<powershell>
$BootstrapScript
</powershell>
"@

#Base 64 encode the script 
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($BootstrapScript))

#Get the IAM Role to apply to the new instance
$Profile = Get-IAMInstanceProfile -InstanceProfileName $RoleName

#Launch the new instance with bootstrap script
$Reservation = New-EC2Instance -ImageId $ImageId  -KeyName $KeyName -InstanceType $InstanceType -MinCount 1 -MaxCount 1 -UserData $UserData -InstanceProfile_Arn $Profile.Arn
$InstanceId = $Reservation.RunningInstance[0].InstanceId
Write-Host "Launched new instance with id $InstanceId"

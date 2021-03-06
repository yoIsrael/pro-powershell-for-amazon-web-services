
#This script will resize a volume by making a copy and deleting the original   

Param(
    [string][Parameter(Mandatory=$True)] $VolumeId,
    [int][Parameter(Mandatory=$True)] $NewSize 
)

#Get a reference to the volume and information about how it is attached
$OldVolume = Get-EC2Volume -Volume $VolumeId
$Attachment = $OldVolume.Attachment[0]

#Check that the instance is stopped
If($NewSize -lt $OldVolume.Size) { Throw "New volume must be larger than current" }
If($Attachment.InstanceId -ne $null){ 
    #The volume is attached to an instance, make sure it's stopped.
    If((Get-EC2InstanceStatus $Attachment.InstanceId) -ne $null){ 
        Throw "Instance must be stopped" 
    }
}

#Create a new snapshot and wait for it to complete
$Snapshot = New-EC2Snapshot -VolumeId $OldVolume.VolumeId
While($Snapshot.Status -ne 'completed') {$Snapshot = Get-EC2Snapshot -SnapshotId $Snapshot.SnapshotId; Start-Sleep -Seconds 15 }

#Now create a new volume and wait for it become available
If($OldVolume.VolumeType -eq 'standard')
{$NewVolume = New-EC2Volume -Size $NewSize -SnapshotId $Snapshot.SnapshotId -AvailabilityZone $OldVolume.AvailabilityZone -VolumeType 'standard'}
Else
{$NewVolume = New-EC2Volume -Size $NewSize -SnapshotId $Snapshot.SnapshotId -AvailabilityZone $OldVolume.AvailabilityZone -VolumeType 'io1' -IOPS $OldVolume.IOPS}
While($NewVolume.Status -ne 'available') {$NewVolume = Get-EC2Volume -VolumeId $NewVolume.VolumeId; Start-Sleep -Seconds 15 }


#If the volume is attached to an instance, remove the old one and attach the new
If($Attachment.InstanceId -ne $null){ 
    Dismount-EC2Volume -VolumeId $OldVolume.VolumeId 
    Start-Sleep -Seconds 15
    Add-EC2Volume -VolumeId $NewVolume.VolumeId -InstanceId $Attachment.InstanceId -Device $Attachment.Device
}

#Finally, delete the old volume and snapshot
Remove-EC2Volume -VolumeId $OldVolume.VolumeId -Force
Remove-EC2Snapshot -SnapshotId $Snapshot.SnapshotId -Force
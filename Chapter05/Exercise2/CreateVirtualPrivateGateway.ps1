
#This script will create a new VPC and configure a VPN connection to your local datacenter 

param
(
    [string][parameter(mandatory=$true)]$CustomerGatewayIP,
    [string][parameter(mandatory=$true)]$LocalNetworkCIDR  = '10.0.0.0/0',
    [string][parameter(mandatory=$true)]$VPCCIDR           = '10.200.0.0/16',
    [string][parameter(mandatory=$true)]$PublicSubnetCIDR  = '10.200.1.0/24',
    [string][parameter(mandatory=$true)]$PrivateSubnetCIDR = '10.200.2.0/24',
    [string][parameter(mandatory=$true)]$AvailabilityZone  = 'us-east-1a'
)

#Create the new VPC
$VPC = New-EC2Vpc -CidrBlock $VPCCIDR
Start-Sleep -s 15 #This can take a few seconds

#Create and tag the Public subnet.
$PublicSubnet = New-EC2Subnet -VpcId $VPC.VpcId -CidrBlock $PublicSubnetCIDR -AvailabilityZone $AvailabilityZone
Start-Sleep -s 15 #This can take a few seconds
$Tag = New-Object Amazon.EC2.Model.Tag
$Tag.Key = 'Name'
$Tag.Value = 'Public'
New-EC2Tag -ResourceId $PublicSubnet.SubnetId -Tag $Tag

#Create and tag the Private subnet.
$PrivateSubnet = New-EC2Subnet -VpcId $VPC.VpcId -CidrBlock $PrivateSubnetCIDR -AvailabilityZone $AvailabilityZone
Start-Sleep -s 15 #This can take a few seconds
$Tag = New-Object Amazon.EC2.Model.Tag
$Tag.Key = 'Name'
$Tag.Value = 'Private'
New-EC2Tag -ResourceId $PrivateSubnet.SubnetId  -Tag $Tag

#Add an Internet Gateway and attach it to the VPC.
$InternetGateway = New-EC2InternetGateway
Add-EC2InternetGateway -InternetGatewayId $InternetGateway.InternetGatewayId -VpcId $VPC.VpcId

#Add a Virtual Private Gateway and attach it to the VPC.
$CustomerGateway = New-EC2CustomerGateway -Type 'ipsec.1' -IpAddress $CustomerGatewayIP
$VpnGateway = New-EC2VpnGateway -Type 'ipsec.1' -AvailabilityZone $AvailabilityZone
Add-EC2VpnGateway -VpnGatewayId $VpnGateway.VpnGatewayId  -VpcId $VPC.VpcId
$VPNConnection = New-EC2VpnConnection -Type 'ipsec.1' -CustomerGatewayId $CustomerGateway.CustomerGatewayId -VpnGatewayId $VpnGateway.VpnGatewayId -StaticRoutesOnly $true

#Add static routes to the Virtual Private Gateway
While($VPNConnection.VpnConnectionState -eq 'pending') {
    Start-Sleep -s 15 #Wait for the VPN connection to become available
    $VPNConnection = Get-EC2VpnConnection -VpnConnectionId $VPNConnection.VpnConnectionId
}
New-EC2VpnConnectionRoute -VpnConnectionId $VPNConnection.VpnConnectionId -DestinationCidrBlock '10.0.0.0/8'
New-EC2VpnConnectionRoute -VpnConnectionId $VPNConnection.VpnConnectionId -DestinationCidrBlock '0.0.0.0/0'

#Create a new route table and associate it with the public subnet
$PublicRouteTable = New-EC2RouteTable -VpcId $VPC.VpcId
New-EC2Route -RouteTableId $PublicRouteTable.RouteTableId -DestinationCidrBlock '10.0.0.0/8' -GatewayId $VpnGateway.VpnGatewayId
New-EC2Route -RouteTableId $PublicRouteTable.RouteTableId -DestinationCidrBlock '0.0.0.0/0' -GatewayId $InternetGateway.InternetGatewayId
Register-EC2RouteTable -RouteTableId $PublicRouteTable.RouteTableId -SubnetId $PublicSubnet.SubnetId

#Find the Main route table and route all traffic to the VPN tunnel
$VPCFilter = New-Object Amazon.EC2.Model.Filter
$VPCFilter.Name = 'vpc-id'
$VPCFilter.Value = $VPC.VpcId
$IsDefaultFilter = New-Object Amazon.EC2.Model.Filter
$IsDefaultFilter.Name = 'association.main'
$IsDefaultFilter.Value = 'true'
$MainRouteTable = (Get-EC2RouteTable -Filter $VPCFilter, $IsDefaultFilter)
$MainRouteTable.Routes | Where-Object { $_.DestinationCidrBlock -eq '10.0.0.0/8'} | % {Remove-EC2Route -RouteTableId $MainRouteTable.RouteTableId -DestinationCidrBlock $_.DestinationCidrBlock -Force}
New-EC2Route -RouteTableId $PublicRouteTable.RouteTableId -DestinationCidrBlock '10.0.0.0/8' -GatewayId $VpnGateway.VpnGatewayId
$MainRouteTable.Routes | Where-Object { $_.DestinationCidrBlock -eq '0.0.0.0/0'} | % {Remove-EC2Route -RouteTableId $MainRouteTable.RouteTableId -DestinationCidrBlock $_.DestinationCidrBlock -Force}
New-EC2Route -RouteTableId $PublicRouteTable.RouteTableId -DestinationCidrBlock '0.0.0.0/0' -GatewayId $VpnGateway.VpnGatewayId

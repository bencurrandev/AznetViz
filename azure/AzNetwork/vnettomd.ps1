$sharednet = Get-AzVirtualNetwork
$subscriptions = Get-AzSubscription
foreach ($vnet in $sharednet) {
    write-host "$($vnet.Name.Replace(".","-")) {"
    write-host "resourcegroup $($vnet.ResourceGroupName.Replace(".","-"))"
    write-host "subscription $(($subscriptions | where Id -eq $sharednet[0].Id.Substring(15,36)).Name.Replace(" ","-"))"
    write-host "}"
    foreach ($peering in $vnet.VirtualNetworkPeerings) {
        if ($peering.AllowGatewayTransit -eq $true) {
            write-host "$($vnet.Name.Replace(".","-")) }|--|| $((($peering.RemoteVirtualNetwork.Id).Split("/"))[8].Replace(".","-")) : peering"
        } elseif ($peering.UseRemoteGateways -eq $true) {
            write-host "$($vnet.Name.Replace(".","-")) ||--|{ $((($peering.RemoteVirtualNetwork.Id).Split("/"))[8].Replace(".","-")) : peering"
        } else {
            write-host "$($vnet.Name.Replace(".","-")) |o--o| $((($peering.RemoteVirtualNetwork.Id).Split("/"))[8].Replace(".","-")) : peering"
        }
    }
}
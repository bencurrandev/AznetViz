$sharednet = Get-AzVirtualNetwork
$subscriptions = Get-AzSubscription
foreach ($vnet in $sharednet) {
    if ($vnet.DhcpOptions) {
        $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3}[0-9]{1,3}', ''
    } else { 
        $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3}[0-9]{1,3}', '-Citrix'
    }
    write-host "$($vnetName) {"
    write-host "resourcegroup $($vnet.ResourceGroupName.Replace(".","-"))"
    write-host "subscription $(($subscriptions | where Id -eq $sharednet[0].Id.Substring(15,36)).Name.Replace(" ","-"))"
    write-host "}"
    foreach ($peering in $vnet.VirtualNetworkPeerings) {
        $peervNet = $sharednet | where Id -eq $peering.RemoteVirtualNetwork.Id
        if ($peervNet) {
            if ($peervNet.DhcpOptions) {
                $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3}[0-9]{1,3}', ''
            } else { 
                $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3}[0-9]{1,3}', '-Citrix'
            }
        } else {
            $peerName = (($peering.RemoteVirtualNetwork.Id).Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3}[0-9]{1,3}', ''
        }
        if ($peering.AllowGatewayTransit -eq $true) {
            write-host "$($vnetName) }|--|| $($peerName) : peering"
        } elseif ($peering.UseRemoteGateways -eq $true) {
            write-host "$($vnetName) ||--|{ $($peerName) : peering"
        } else {
            write-host "$($vnetName) |o--o| $($peerName) : peering"
        }
    }
}
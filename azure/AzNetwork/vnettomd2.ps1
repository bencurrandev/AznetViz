$subscriptions = Get-AzSubscription
$currentCon = Get-AzContext
$subErc = @()
$subVngs = @()
$subVngConns = @()
$subLngs = @()
$subVwan = @()
$subVhubs = @()
foreach ($sub in $subscriptions) {
    Select-AzSubscription $sub.Id | Out-Null
    $thisSubVnets = Get-AzVirtualNetwork
    $thisSubResources = Get-AzResource
    $subVnets += $thisSubVnets
    foreach ($vnet in $thisSubVnets) {
        $subVngList = ($vnet.Subnets | where Name -eq 'GatewaySubnet').Ipconfigurations.Id
        foreach ($vng in $subVngList) {
            $thisSubVngs = Get-AzVirtualNetworkGateway -ResourceGroupName $vng.Split("/")[4] -Name $vng.Split("/")[8]
            $subVngs += $thisSubVngs
            $vng1text = "`"$($vng.Split("/ipCon")[0])`""
            $subVngConns += Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $vng.Split("/")[4] | where VirtualNetworkGateway1Text -eq $vng1text
        }
    }
    foreach ($thisLngs in ($thisSubResources | where ResourceType -eq "Microsoft.Network/localNetworkGateways")) {
        $subLngs += Get-AzLocalNetworkGateway -ResourceGroupName $thisLngs.ResourceGroupName -Name $thisLngs.Name
    }
    
    $subErc += Get-AzExpressRouteCircuit -WarningAction silentlyContinue
    $thisSubVwan = Get-AzVirtualWan
    $subVwan += $thisSubVwan
    foreach ($vWan in $subVwan) {
        $subVhubs += Get-AzVirtualHub -ResourceGroupName ($vWan.Id.Split("/")[4])
    }
}
Select-AzSubscription $currentCon.Subscription | Out-Null
$output = @()
$vnetList = @()
$output += "erDiagram"
foreach ($vnet in $subVnets) {
    # write-host "Processing $($vnet.Name) in $(($subscriptions | where Id -eq $vnet.Id.Substring(15,36)).Name.Replace(" ","-"))"
    if ($vnet.DhcpOptions) {
        $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    } else { 
        $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', '-OffNet'
    }
    $vnetList += $vnetName
    $output += "    $($vnetName) {"
    $output += "        resourcegroup $($vnet.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | where Id -eq $vnet.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($vnet.location)"
    $output += "        type $($vnet.Type.Replace("/","-").Replace(".","-"))"
    $output += "    }"
    foreach ($peering in $vnet.VirtualNetworkPeerings) {
        $peervNet = $subVnets | where Id -eq $peering.RemoteVirtualNetwork.Id
        if ($peervNet) {
            if ($peervNet.DhcpOptions) {
                $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
            } else { 
                $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', '-OffNet'
            }
        } else {
            $peerName = (($peering.RemoteVirtualNetwork.Id).Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
            if ($peername -like "HV_*") {
                $vHubname = $peerName.Split("_")[1]
                $peerName = $vhubName.Substring(0,($vHubname.Length)-1)
            }
        }
        if ($vnetList -contains $peerName) {

        } else {
            if ($peering.AllowGatewayTransit -eq $true) {
                $output += "    $($vnetName) }|--|| $($peerName) : peering"
            } elseif ($peering.UseRemoteGateways -eq $true) {
                $output += "    $($vnetName) ||--|{ $($peerName) : peering"
            } else {
                $output += "    $($vnetName) |o--o| $($peerName) : peering"
            }
        }
    }
}
foreach ($erc in $subErc) {
    $output += "    $($erc.name) {"
    $output += "        resourcegroup $($erc.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | where Id -eq $erc.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($erc.location)"
    $output += "        type $($erc.Type.Replace("/","-").Replace(".","-"))"
    $output += "    }"
}
foreach ($lng in $subLngs) {
    $output += "    $($lng.name) {"
    $output += "        resourcegroup $($lng.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | where Id -eq $lng.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($lng.location)"
    $output += "        type $($lng.Type.Replace("/","-").Replace(".","-"))"
    $output += "    }"
}
foreach ($vng in $subVngs) {
    $output += "    $($vng.name) {"
    $output += "        resourcegroup $($vng.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | where Id -eq $vng.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($vng.location)"
    $output += "        type $($vng.Type.Replace("/","-").Replace(".","-"))-$($vng.GatewayType)"
    $output += "    }"
    $vngVnetId = ($vng.IpConfigurations.subnet | where id -like "*GatewaySubnet*").Id
    $vngVnet = ($vngVnetId.Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    $output += "    $($vng.name) ||--|| $($vngVnet) : gateway"
}
foreach ($vngConn in $subVngConns) {
    if ($vngConn.VirtualNetworkGateway2) {
        $output += "    $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) ||--|| $($vngConn.VirtualNetworkGateway2.Id.Split("/")[8]) : connection"
    } elseif ($vngConn.LocalNetworkGateway2) {
        $output += "    $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) ||--|| $($vngConn.LocalNetworkGateway2.Id.Split("/")[8]) : connection"
    } elseif ($vngConn.Peer) {
        $output += "    $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) ||--|| $($vngConn.Peer.Id.Split("/")[8]) : connection"
    }
}
foreach ($vHub in $subVhubs) {
    $vhubName = $vHub.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    $vwanName = $vHub.VirtualWan.Id.Split("/")[8]
    $output += "    $($vHubName) {"
    $output += "        resourcegroup $($vHub.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | where Id -eq $vHub.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($vHub.location)"
    $output += "        type $($vHub.Type.Replace("/","-").Replace(".","-"))-$vwanName"
    $output += "    }"
    #foreach ($vnetConn in $vHub.VirtualNetworkConnections) {
    #
    #}
}
$output
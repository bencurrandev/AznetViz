$currentCon = Get-AzContext
$subscriptions = Get-AzSubscription -TenantId $currentCon.Tenant.Id
$subVnets = @()
$subErc = @()
$subVngs = @()
$subVngConns = @()
$subLngs = @()
$subVwan = @()
$subVhubs = @()
$subVhubErcGw = @()
$subVhubVpnGw = @()
foreach ($sub in $subscriptions) {
    Select-AzSubscription $sub.Id # | Out-Null
    $thisSubVnets = Get-AzVirtualNetwork
    $thisSubResources = Get-AzResource
    $subVnets += $thisSubVnets
    foreach ($vnet in $thisSubVnets) {
        $subVngList = ($vnet.Subnets | Where-Object Name -eq 'GatewaySubnet').Ipconfigurations.Id
        foreach ($vng in $subVngList) {
            $thisSubVngs = Get-AzVirtualNetworkGateway -ResourceGroupName $vng.Split("/")[4] -Name $vng.Split("/")[8]
            $subVngs += $thisSubVngs
            $vng1text = "`"$($vng.Split("/ipCon")[0])`""
            $subVngConns += Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $vng.Split("/")[4] | Where-Object VirtualNetworkGateway1Text -eq $vng1text
        }
    }
    foreach ($thisLngs in ($thisSubResources | Where-Object ResourceType -eq "Microsoft.Network/localNetworkGateways")) {
        $subLngs += Get-AzLocalNetworkGateway -ResourceGroupName $thisLngs.ResourceGroupName -Name $thisLngs.Name
    }
    
    $subErc += Get-AzExpressRouteCircuit -WarningAction silentlyContinue
    $thisSubVwan = Get-AzVirtualWan
    $subVwan += $thisSubVwan
    foreach ($vWan in $thisSubVwan) {
        $thisSubVhubs = Get-AzVirtualHub -ResourceGroupName ($vWan.Id.Split("/")[4])
        $subVhubs += $thisSubVhubs
        foreach ($vHub in $thisSubVhubs) {
            if ($vHub.VpnGateway.id) {
                $vpnGw = $vHub.VpnGateway.id.Split("/")
                $subVhubVpnGw += Get-AzVpnGateway -ResourceGroupName $vpnGw[4] -Name $vpnGw[8]
            }
            if ($vHub.ExpressRouteGateway.id) {
                $ercGw = $vHub.ExpressRouteGateway.id.Split("/")
                $subVhubErcGw += Get-AzExpressRouteGateway -ResourceGroupName $ercGw[4] -Name $ercGw[8]
            }
            # TODO Add P2S VPN Gateway connections if we ever have them
        }
    }
}
Select-AzSubscription $currentCon.Subscription | Out-Null
$output = @()
$vnetList = @()
$lngList = @()
$vhubList = @()
$output += "erDiagram"
foreach ($vnet in $subVnets) {
    # write-host "Processing $($vnet.Name) in $(($subscriptions | Where-Object Id -eq $vnet.Id.Substring(15,36)).Name.Replace(" ","-"))"
    if ($vnet.VirtualNetworkPeerings.count -gt 0) { # Removes VNets not connected to anything
        if ($vnet.DhcpOptions) {
            $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
            if ($vnetList -contains $vnetName) {
                $vnetName = $vnetName + "-Workstations" # I only put this in because for some reason FRC PRD has two Vnets with the same name
            }
        } else { 
            $vnetName = $vnet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', '-OffNet'
        }
        $vnetList += $vnetName
        $output += "    $($vnetName) {"
        $output += "        resourcegroup $($vnet.ResourceGroupName.Replace(".","-"))"
        $output += "        subscription $(($subscriptions | Where-Object Id -eq $vnet.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
        $output += "        location $($vnet.location)"
        $output += "        type $($vnet.Type.Replace("/","-").Replace(".","-"))"
        $output += "        ipconnected x$($vnet.Subnets.IpConfigurations.count)"
        $output += "    }"
        foreach ($peering in $vnet.VirtualNetworkPeerings) {
            $peervNet = $subVnets | Where-Object Id -eq $peering.RemoteVirtualNetwork.Id
            if ($peervNet) {
                if ($peervNet.DhcpOptions) {
                    $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
                } else { 
                    $peerName = $peervNet.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', '-OffNet'
                }
            } else {
                $peerName = (($peering.RemoteVirtualNetwork.Id).Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
                if ($vnetList -contains $peerName) {
                    $peerName = $peerName + "-Workstations" # I only put this in because for some reason FRC PRD has two Vnets with the same name
                }
                if ($peername -like "HV_*") {
                    $vHubname = $peerName.Split("_")[1] # This is required because the auto-generated name for vWan Hub peers is weird
                    $peerName = $vhubName.Substring(0,($vHubname.Length)-1)
                }
            }
            if ($vnetList -contains $peerName) {

            } else {
                if ($peering.AllowGatewayTransit -eq $true) {
                    $output += "    $($vnetName) }|--|| $($peerName) : peering"
                } elseif ($peering.UseRemoteGateways -eq $true) {
                    $output += "    $($peerName) }|--|| $($vnetName) : peering"
                } else {
                    $output += "    $($vnetName) |o--o| $($peerName) : peering"
                }
            }
        }
    }
}
foreach ($erc in $subErc) {
    $output += "    $($erc.name) {"
    $output += "        resourcegroup $($erc.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | Where-Object Id -eq $erc.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($erc.location)"
    $output += "        type $($erc.Type.Replace("/","-").Replace(".","-"))"
    $output += "    }"
}
foreach ($vngConn in $subVngConns) {
    if ($vngConn.VirtualNetworkGateway2) {
        $output += "    $($vngConn.VirtualNetworkGateway2.Id.Split("/")[8]) ||--|| $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) : connection"
    } elseif ($vngConn.LocalNetworkGateway2) {
        $lngList += $vngConn.LocalNetworkGateway2.Id.Split("/")[8]
        $output += "    $($vngConn.LocalNetworkGateway2.Id.Split("/")[8]) ||--|| $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) : connection"
    } elseif ($vngConn.Peer) {
        $output += "    $($vngConn.Peer.Id.Split("/")[8]) ||--|| $($vngConn.VirtualNetworkGateway1.Id.Split("/")[8]) : connection"
    }
}
foreach ($lng in $subLngs) {
    if ($lngList -contains $lng.name) { # Removes LNGs that are not connected to anything
        $output += "    $($lng.name) {"
        $output += "        resourcegroup $($lng.ResourceGroupName.Replace(".","-"))"
        $output += "        subscription $(($subscriptions | Where-Object Id -eq $lng.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
        $output += "        location $($lng.location)"
        $output += "        type $($lng.Type.Replace("/","-").Replace(".","-"))"
        $output += "    }"
    }
}
foreach ($vng in $subVngs) {
    $output += "    $($vng.name) {"
    $output += "        resourcegroup $($vng.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | Where-Object Id -eq $vng.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($vng.location)"
    $output += "        type $($vng.Type.Replace("/","-").Replace(".","-"))"
    $output += "        gatewayType $($vng.GatewayType)"
    $output += "    }"
    $vngVnetId = ($vng.IpConfigurations.subnet | Where-Object id -like "*GatewaySubnet*").Id
    $vngVnet = ($vngVnetId.Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    $output += "    $($vng.name) ||--|| $($vngVnet) : gateway"
}
foreach ($vHub in $subVhubs) {
    $vhubName = $vHub.Name -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    $vwanName = $vHub.VirtualWan.Id.Split("/")[8]
    $output += "    $($vHubName) {"
    $output += "        resourcegroup $($vHub.ResourceGroupName.Replace(".","-"))"
    $output += "        subscription $(($subscriptions | Where-Object Id -eq $vHub.Id.Substring(15,36)).Name.Replace(" ","-").Replace("/","-"))"
    $output += "        location $($vHub.location)"
    $output += "        type $($vHub.Type.Replace("/","-").Replace(".","-"))"
    if ($vHub.AzureFirewall.Id) {
        $output += "        azfirewall enabled"
    } else {
        $output += "        azfirewall disabled"
    }
    $output += "    }"
    foreach ($vhubConn in $vhubList) {
        $output += "    $($vhubConn) }|--|{ $($vHubName) : $vwanName"
    }
    $vhubList += $vHubName
    #foreach ($vnetConn in $vHub.VirtualNetworkConnections) {
    # TODO Add any missing vNet connections that may exist
    #}
    $vhubVpns = $subVhubVpnGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
    foreach ($vhubVpn in $vhubVpns) {
        $output += "    $($vhubVpn.Connections[0].vpnlinkconnections[0].name) }|--|{ $($vHubName) : $($vhubVpn.Connections[0].name)"
    }
    $vhubErcs = $subVhubErcGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
    foreach ($vhubErc in $vhubErcs) {
        $vhubErcConnection = Get-AzExpressRouteConnection -ResourceGroupName $vhubErc.ResourceGroupName -ExpressRouteGatewayName $vhubErc.Name
        $output += "    $($vhubErcConnection.ExpressRouteCircuitPeering.Id.Split("/")[8]) }|--|{ $($vHubName) : connection"
    }
}
$output | Out-File .\woodsidetest.md 
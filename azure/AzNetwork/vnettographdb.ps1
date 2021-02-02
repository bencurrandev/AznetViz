Param(
    [string]$dbKey
)
Import-Module PSGremlin
$hostname = "cltestgraphdb.gremlin.cosmos.azure.com"
$authKey = ConvertTo-SecureString -AsPlainText -Force -String $dbKey
$database = "PeopleDB"
$collection = "VnetGraph"
$gremlinParams = @{
    Hostname = $hostname
    Credential = New-Object System.Management.Automation.PSCredential "/dbs/$database/colls/$collection", $authKey
}
$subscriptions = Get-AzSubscription # TODO Limit the subscriptions to remove the VSPro ones you maniac
$currentCon = Get-AzContext
$subErc = @()
$subVngs = @()
$subVngConns = @()
$subLngs = @()
$subVwan = @()
$subVhubs = @()
$subVhubErcGw = @()
$subVhubVpnGw = @()
foreach ($sub in $subscriptions) {
    if ($sub.SubscriptionPolicies.QuotaId -notmatch "MSDN_2014-09-01|PayAsYouGo_2014-09-01|AAD_2015-09-01|FreeTrial_2014-09-01|AzurePass_2014-09-01") {
        Select-AzSubscription $sub.Id | Out-Null
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
}
Select-AzSubscription $currentCon.Subscription | Out-Null
$output = @()
$vnetList = @()
$lngList = @()
$vhubList = @()
function SetVnetName ($setVnet) {
    if ($setVnet.DhcpOptions) {
        $vnetNameOut = $setVnet.Name
    } else { 
        $vnetNameOut = "$($setVnet.Name)-OffNet"
    }
    return $vnetNameOut
}

# TODO Add a drop table command to remove previous data
foreach ($vnet in $subVnets) {
    $vnetName = SetVnetName $vnet
    write-host "g.AddV('vnet').property('ResourceId','$($vnet.ResourceGroupName.Replace("/","-"))_$($vnetName)').property('name','$($vnetName)').property('resourcegroup','$($vnet.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($vnet.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($vnet.location)').property('type','$($vnet.Type.Replace("/","-"))').property('ipconnected','$($vnet.Subnets.IpConfigurations.count)')"
}

foreach ($erc in $subErc) {
    write-host "g.AddV('erc').property('ResourceId','$($erc.ResourceGroupName.Replace("/","-"))_$($erc.name)').property('name','$($erc.name)').property('resourcegroup','$($erc.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($erc.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($erc.location)').property('type','$($erc.Type.Replace("/","-"))')"
}
foreach ($lng in $subLngs) {
    if ($lngList -contains $lng.name) { # Removes LNGs that are not connected to anything
    }
    write-host "g.AddV('lng').property('ResourceId','$($lng.ResourceGroupName.Replace("/","-"))_$($lng.name)').property('name','$($lng.name)').property('resourcegroup','$($lng.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($lng.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($lng.location)').property('type','$($lng.Type.Replace("/","-"))')"
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
        # $vhubErcConnection = Get-AzExpressRouteConnection -ResourceGroupName $vhubErc.ResourceGroupName -ExpressRouteGatewayName $vhubErc.Name
        # $output += "    $($vhubErcConnection.ExpressRouteCircuitPeering.Id.Split("/")[8]) }|--|{ $($vHubName) : connection"
    }
}


foreach ($vnetConn in $subVnets) {
    $vnetName = SetVnetName $vnetConn
    write-host $vnetName
    foreach ($peering in $vnetConn.VirtualNetworkPeerings) {
        $vnetList += $vnetName
        $peervNet = $subVnets | Where-Object Id -eq $peering.RemoteVirtualNetwork.Id
        $peerLabel = "vnet"
        if ($peervNet) {
            if ($peervNet.DhcpOptions) {
                $peerName = $peervNet.Name
            } else { 
                $peerName = "$($peervNet.Name)-OffNet"
            }
        } else {
            $peerName = (($peering.RemoteVirtualNetwork.Id).Split("/"))[8]
            if ($peername -like "HV_*") {
                $vHubname = $peerName.Split("_")[1] # This is required because the auto-generated name for vWan Hub peers is weird
                $peerName = $vhubName.Substring(0,($vHubname.Length)-1)
                $peerLabel = "vwanhub"
            }
        }
        if ($vnetList -contains $peerName) {
        } else {
            if ($peering.AllowGatewayTransit -eq $true) {
                write-host "g.V().hasLabel('vnet').has('name','$($vnetName)').addE('peering').to(g.V().hasLabel('$($peerLabel)').has('name','$($peerName)'))"
            } elseif ($peering.UseRemoteGateways -eq $true) {
                write-host "g.V().hasLabel('$($peerLabel)').has('name','$($peerName)').addE('peering').to(g.V().hasLabel('vnet').has('name','$($vnetName)'))"
            } else {
                write-host "g.V().hasLabel('vnet').has('name','$($vnetName)').addE('peering').to(g.V().hasLabel('$($peerLabel)').has('name','$($peerName)'))"
            }
        }
    }
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

# $output
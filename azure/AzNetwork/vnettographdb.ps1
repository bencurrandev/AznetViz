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
$subscriptions = Get-AzSubscription
$currentCon = Get-AzContext
$subErc = @()
$subVngs = @()
$subVngConns = @()
$subLngs = @()
$subVwan = @()
$subVhubs = @()
$subVhubErcGw = @()
$subVhubErcConns = @()
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
                    $thisVhubErcGw += Get-AzExpressRouteGateway -ResourceGroupName $ercGw[4] -Name $ercGw[8]
                    $subVhubErcGw += $thisVhubErcGw
                    $subVhubErcConns += Get-AzExpressRouteConnection -ResourceGroupName $thisVhubErcGw.ResourceGroupName -ExpressRouteGatewayName $thisVhubErcGw.Name
                }
                # TODO Add P2S VPN Gateway connections if we ever have them
            }
        }
    }
}
Select-AzSubscription $currentCon.Subscription | Out-Null
$output = @()
$vnetList = @()
$vhubList = @()
function SetVnetName ($setVnet) {
    if ($setVnet.DhcpOptions) {
        $vnetNameOut = $setVnet.Name
    } else { 
        $vnetNameOut = "$($setVnet.Name)-OffNet"
    }
    return $vnetNameOut
}

function LogOutput ($message) {
    $output = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] : $message"
    write-host $output
}

# TODO Add a drop table command to remove previous data
try {
    Invoke-Gremlin @gremlinParams -Query "g.V().drop()"
}
catch {
    LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
    LogOutput "ERROR : $_.Exception.Message"
}

# ======== Node loops ========

foreach ($vnet in $subVnets) {
    $vnetName = SetVnetName $vnet
    try {
        Invoke-Gremlin @gremlinParams -Query "g.AddV('vnet').property('ResourceId','$($vnet.ResourceGroupName.Replace("/","-"))_$($vnetName)').property('name','$($vnetName)').property('resourcegroup','$($vnet.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($vnet.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($vnet.location)').property('type','$($vnet.Type.Replace("/","-"))').property('ipconnected','$($vnet.Subnets.IpConfigurations.count)')"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}

foreach ($erc in $subErc) {
    try {
        Invoke-Gremlin @gremlinParams -Query "g.AddV('erc').property('ResourceId','$($erc.ResourceGroupName.Replace("/","-"))_$($erc.name)').property('name','$($erc.name)').property('resourcegroup','$($erc.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($erc.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($erc.location)').property('type','$($erc.Type.Replace("/","-"))')"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}
foreach ($lng in $subLngs) {
    try {
        Invoke-Gremlin @gremlinParams -Query "g.AddV('lng').property('ResourceId','$($lng.ResourceGroupName.Replace("/","-"))_$($lng.name)').property('name','$($lng.name)').property('resourcegroup','$($lng.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($lng.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($lng.location)').property('type','$($lng.Type.Replace("/","-"))')"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}
foreach ($vng in $subVngs) {
    try {
        Invoke-Gremlin @gremlinParams -Query "g.AddV('vng').property('ResourceId','$($vng.ResourceGroupName.Replace("/","-"))_$($vng.name)').property('name','$($vng.name)').property('resourcegroup','$($vng.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($vng.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($vng.location)').property('type','$($vng.Type.Replace("/","-"))').property('gatewayType','$($vng.GatewayType)')"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}

foreach ($vHub in $subVhubs) {
    $vwanName = $vHub.VirtualWan.Id.Split("/")[8]
    if ($vHub.AzureFirewall.Id) {
        $azFirewallStatus = "enabled"
    } else {
        $azFirewallStatus = "disabled"
    }
    try {
        Invoke-Gremlin @gremlinParams -Query "g.AddV('vhub').property('ResourceId','$($vHub.ResourceGroupName.Replace("/","-"))_$($vHub.name)').property('name','$($vHub.name)').property('resourcegroup','$($vHub.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($vHub.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($vHub.location)').property('type','$($vHub.Type.Replace("/","-"))').property('azFirewall','$($azFirewallStatus)').property('virtualWan','$($vwanName)')"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
    $vhubVpns = $subVhubVpnGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
    foreach ($vhubVpn in $vhubVpns) {
        $vpnLinkName = $vhubVpn.Connections[0].name.Split("Connection-")[1]
        Invoke-Gremlin @gremlinParams -Query "g.AddV('vpn').property('ResourceId','$($vHub.ResourceGroupName.Replace("/","-"))_$($vpnLinkName)').property('name','$($vpnLinkName)').property('resourcegroup','$($vHub.ResourceGroupName.Replace("/","-"))').property('subscription','$(($subscriptions | Where-Object Id -eq ($vHub.Id.Split("/")[2])).Name.Replace(" ","-").Replace("/","-"))').property('location','$($vHub.location)').property('type','Microsoft.Network-vpnGateways-vpnConnections')"
    }

}

# ======== Connection loops ========

foreach ($vnetConn in $subVnets) {
    $vnetName = SetVnetName $vnetConn
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
            try {
                if ($peering.AllowGatewayTransit -eq $true) {
                    Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vnet').has('name','$($vnetName)').addE('peering').to(g.V().hasLabel('$($peerLabel)').has('name','$($peerName)'))"
                } elseif ($peering.UseRemoteGateways -eq $true) {
                    Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('$($peerLabel)').has('name','$($peerName)').addE('peering').to(g.V().hasLabel('vnet').has('name','$($vnetName)'))"
                } else {
                    Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vnet').has('name','$($vnetName)').addE('peering').to(g.V().hasLabel('$($peerLabel)').has('name','$($peerName)'))"
                }
            }
            catch {
                LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
                LogOutput "ERROR : $_.Exception.Message"
            }
        }
    }
}

foreach ($vngVnetConn in $subVngs) {
    $vngVnetId = ($vngVnetConn.IpConfigurations.subnet | Where-Object id -like "*GatewaySubnet*").Id
    $vngVnet = ($vngVnetId.Split("/"))[8] -Replace '-(?:[0-9]{1,3}\.){3,4}[0-9]{1,3}', ''
    try {
        Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vng').has('name','$($vngVnetConn.name)').addE('gateway').to(g.V().hasLabel('vnet').has('name','$($vngVnet)'))"
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}

foreach ($vngConn in $subVngConns) {
    try {
        if ($vngConn.VirtualNetworkGateway2) {
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vng').has('name','$($vngConn.VirtualNetworkGateway2.Id.Split("/")[8])').addE('connection').to(g.V().hasLabel('vng').has('name','$($vngConn.VirtualNetworkGateway1.Id.Split("/")[8])'))"
        } elseif ($vngConn.LocalNetworkGateway2) {
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('lng').has('name','$($vngConn.LocalNetworkGateway2.Id.Split("/")[8])').addE('connection').to(g.V().hasLabel('vng').has('name','$($vngConn.VirtualNetworkGateway1.Id.Split("/")[8])'))"
        } elseif ($vngConn.Peer) {
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('erc').has('name','$($vngConn.Peer.Id.Split("/")[8])').addE('connection').to(g.V().hasLabel('vng').has('name','$($vngConn.VirtualNetworkGateway1.Id.Split("/")[8])'))"
        }
    }
    catch {
        LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
        LogOutput "ERROR : $_.Exception.Message"
    }
}

foreach ($vHub in $subVhubs) {
    foreach ($vhubConn in $vhubList) {
        try {
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vhub').has('name','$($vhubConn)').addE('virtualwan').to(g.V().hasLabel('vhub').has('name','$($vHub.Name)'))"
        }
        catch {
            LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
            LogOutput "ERROR : $_.Exception.Message"
        }
    }
    $vhubList += $vHub.Name
    #foreach ($vnetConn in $vHub.VirtualNetworkConnections) {
    # TODO Add any missing vNet connections that may exist
    #}
    $vhubVpns = $subVhubVpnGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
    foreach ($vhubVpn in $vhubVpns) {
        try {
            $vpnLinkName = $vhubVpn.Connections[0].name.Split("Connection-")[1]
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('vpn').has('name','$($vpnLinkName)').addE('$($vhubVpn.Connections[0].vpnlinkconnections[0].name)').to(g.V().hasLabel('vhub').has('name','$($vHub.Name)'))"
        }
        catch {
            LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
            LogOutput "ERROR : $_.Exception.Message"
        }
    }
    $vhubErcConns = $subVhubErcConns | Where-Object {$_.RoutingConfiguration.AssociatedRouteTable.Id.Split("/")[8] -eq $vHub.Name }
    foreach ($vhubErcConn in $vhubErcConns) {
        try {
            Invoke-Gremlin @gremlinParams -Query "g.V().hasLabel('erc').has('name','$($vhubErcConn.ExpressRouteCircuitPeering.Id.Split("/")[8])').addE('connection').to(g.V().hasLabel('vhub').has('name','$($vHub.Name)'))"
        }
        catch {
            LogOutput "ERROR : [Line:$($_.InvocationInfo.ScriptLineNumber)]"
            LogOutput "ERROR : $_.Exception.Message"
        }
    }
}
# $output
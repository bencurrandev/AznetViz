Param(
    [Parameter(Mandatory)]
    [string]$outputFile,
    [ValidateRange("svg", "png", "jpg", "gif", "imap", "cmapx", "jp2", "json", "pdf", "plain", "dot")]
    [string]$outputFormat = "svg"
)
Import-Module PSGraph
$currentCon = Get-AzContext
$subscriptions = Get-AzSubscription -TenantId $currentCon.Tenant.Id
$outputFile = "$outputFile.$outputFormat"
$subVnets = @()
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
        $thisSubVnets = Get-AzVirtualNetwork | Select-Object Name, ResourceGroupName, location, Type, VirtualNetworkPeerings, Subnets, DhcpOptions, AddressSpace,  @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
        $thisSubResources = Get-AzResource
        $subVnets += $thisSubVnets
        foreach ($vnet in $thisSubVnets) {
            $subVngList = ($vnet.Subnets | Where-Object Name -eq 'GatewaySubnet').Ipconfigurations.Id
            foreach ($vng in $subVngList) {
                $thisSubVngs = Get-AzVirtualNetworkGateway -ResourceGroupName $vng.Split("/")[4] -Name $vng.Split("/")[8]  | Select-Object Name, Id, ResourceGroupName, location, Type, GatewayType, IpConfigurations, @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
                $subVngs += $thisSubVngs
                $vng1text = "`"$($vng.Split("/ipCon")[0])`""
                $subVngConns += Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $vng.Split("/")[4] | Where-Object VirtualNetworkGateway1Text -eq $vng1text
            }
        }
        foreach ($thisLngs in ($thisSubResources | Where-Object ResourceType -eq "Microsoft.Network/localNetworkGateways")) {
            $subLngs += Get-AzLocalNetworkGateway -ResourceGroupName $thisLngs.ResourceGroupName -Name $thisLngs.Name | Select-Object Name, Id, ResourceGroupName, location, Type, @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
        }

        $subErc += Get-AzExpressRouteCircuit -WarningAction silentlyContinue | Select-Object Name, Id, ResourceGroupName, location, Type, @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
        $thisSubVwan = Get-AzVirtualWan
        $subVwan += $thisSubVwan
        foreach ($vWan in $thisSubVwan) {
            $thisSubVhubs = Get-AzVirtualHub -ResourceGroupName ($vWan.Id.Split("/")[4]) | Select-Object Name, Id, ResourceGroupName, location, Type, VirtualWan, AzureFirewall, ExpressRouteGateway, VpnGateway, @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
            $subVhubs += $thisSubVhubs
            foreach ($vHub in $thisSubVhubs) {
                if ($vHub.VpnGateway.id) {
                    $vpnGw = $vHub.VpnGateway.id.Split("/")
                    $subVhubVpnGw += Get-AzVpnGateway -ResourceGroupName $vpnGw[4] -Name $vpnGw[8] | Select-Object Name, Id, ResourceGroupName, location, Type, @{ name='SubscriptionId'; expr={$_.Id.Split('/')[2]} }
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
$vhubList = @()

function SetDhcp ($setDhcp) {
    if ($setDhcp.DhcpOptions) {
        $dnsOut = ""
        $setDhcp.DhcpOptions.DnsServers | Foreach-Object {
            $dnsOut += "$_ " 
        }
        if ($dnsOut.Length -lt 7) {
            $dnsOut = "Azure DNS"
        }
    } else { 
        $dnsOut = "Azure DNS"
    }

    return $dnsOut
}

function SetAddress ($setAddress) {
    if ($setAddress.AddressSpace) {
        $addressOut = ""
        $setAddress.AddressSpace.AddressPrefixes | Foreach-Object {
            $addressOut += "$_ " 
        }
        if ($addressOut.Length -lt 7) {
            $addressOut = "Misconfigured"
        }
    } else { 
        $addressOut = "Misconfigured"
    }

    return $addressOut
}
function LogOutput ($message) {
    $output = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))] : $message"
    write-host $output
}

# ======== Graph Generation ========
$sgcount = 0
graph {
    node @{shape="box"}

# ======== Node loops ========

    foreach ($sub in $subscriptions) {
        SubGraph $sgcount -Attributes @{style='filled';color='lightgrey';label=$sub.Name} {
            foreach ($vnet in $subVnets | Sort-Object VirtualNetworkPeerings -Descending | Where-Object SubscriptionId -eq $sub.Id) {
                $vnetDhcp = SetDhcp $vnet
                $vnetAddress = SetAddress $vnet
                Entity -Name $vnet.Name -Show value @{
                    resourcegroup = $vnet.ResourceGroupName
                    subscription = ($subscriptions | Where-Object Id -eq $vnet.SubscriptionId).Name
                    location = $vnet.location
                    type = $vnet.Type
                    ipconnected = $vnet.Subnets.IpConfigurations.count
                    addressspace = $vnetAddress
                    dns = $vnetDhcp
                }
            }
        
            foreach ($erc in $subErc) {
                Entity -Name $erc.name -Show value @{
                    resourcegroup = $erc.ResourceGroupName
                    subscription = ($subscriptions | Where-Object Id -eq ($erc.Id.Split("/")[2])).Name
                    location = $erc.location
                    type = $erc.Type
                }
            }
            foreach ($lng in $subLngs) {
                Entity -Name $lng.name -Show value @{
                    resourcegroup = $lng.ResourceGroupName
                    subscription = ($subscriptions | Where-Object Id -eq ($lng.Id.Split("/")[2])).Name
                    location = $lng.location
                    type = $lng.Type
                }
            }
            foreach ($vng in $subVngs) {
                Entity -Name $vng.name -Show value @{
                    resourcegroup = $vng.ResourceGroupName
                    subscription = ($subscriptions | Where-Object Id -eq ($vng.Id.Split("/")[2])).Name
                    location = $vng.location
                    type = $vng.Type
                    gatewayType = $vng.GatewayType
                }
            }
        
            foreach ($vHub in $subVhubs) {
                $vwanName = $vHub.VirtualWan.Id.Split("/")[8]
                if ($vHub.AzureFirewall.Id) {
                    $azFirewallStatus = "enabled"
                } else {
                    $azFirewallStatus = "disabled"
                }
                Entity -Name $vHub.name -Show value @{
                    resourcegroup = $vHub.ResourceGroupName
                    subscription = ($subscriptions | Where-Object Id -eq ($vHub.Id.Split("/")[2])).Name
                    location = $vHub.location
                    type = $vHub.Type
                    azFirewall = $azFirewallStatus
                    virtualWan = $vwanName
                }
                $vhubVpns = $subVhubVpnGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
                foreach ($vhubVpn in $vhubVpns) {
                    $vpnLinkName = $vhubVpn.Connections[0].name.Split("Connection-")[1]
                    Entity -Name $vpnLinkName -Show value @{
                        resourcegroup = $vHub.ResourceGroupName
                        subscription = ($subscriptions | Where-Object Id -eq ($vHub.Id.Split("/")[2])).Name
                        location = $vHub.location
                        type = "Microsoft.Network/vpnGateways/vpnConnections"
                    }
                }
            
            }
        }
        $sgcount++
    }

    # ======== Connection loops ========

    foreach ($vnetConn in $subVnets | Sort-Object VirtualNetworkPeerings -Descending) {
        foreach ($peering in $vnetConn.VirtualNetworkPeerings) {
            $peervNet = $subVnets | Where-Object Id -eq $peering.RemoteVirtualNetwork.Id
            if ($peervNet) {
                $peerName = $peervNet.Name

            } else {
                $peerName = (($peering.RemoteVirtualNetwork.Id).Split("/"))[8]
                if ($peername -like "HV_*") {
                    $vHubname1 = $peerName.Split("_")[1] # This is required because the auto-generated name for vWan Hub peers is weird
                    $vHubname2 = $vHubname1.Substring(0,($vHubname1.Length)-1)
                    $peerName = ($subVhubs | Where-Object Name -like "$($vHubname2)*").Name
                }
            }
            if ($peering.AllowGatewayTransit -eq $true) {
                Edge -From $vnetConn.Name -To $peerName @{label="gatewaytransit"} #TODO: Add label for transit
            } elseif ($peering.UseRemoteGateways -eq $true) {
                Edge -From $vnetConn.Name -To $peerName @{label="remotegateway"}
            } else {
                Edge -From $vnetConn.Name -To $peerName @{label="peering"}
            }
        }
    }

    foreach ($vngVnetConn in $subVngs) {
        $vngVnetId = ($vngVnetConn.IpConfigurations.subnet | Where-Object id -like "*GatewaySubnet*").Id
        $vngVnet = ($vngVnetId.Split("/"))[8]
        Edge -From $vngVnetConn.name -To $vngVnet @{label="gateway"}
    }

    foreach ($vngConn in $subVngConns) {
        if ($vngConn.VirtualNetworkGateway2) {
            Edge -From $vngConn.VirtualNetworkGateway2.Id.Split("/")[8] -To $vngConn.VirtualNetworkGateway1.Id.Split("/")[8] @{label="connection"}
        } elseif ($vngConn.LocalNetworkGateway2) {
            Edge -From $vngConn.LocalNetworkGateway2.Id.Split("/")[8] -To $vngConn.VirtualNetworkGateway1.Id.Split("/")[8] @{label="connection"}
        } elseif ($vngConn.Peer) {
            Edge -From $vngConn.Peer.Id.Split("/")[8] -To $vngConn.VirtualNetworkGateway1.Id.Split("/")[8] @{label="connection"}
        }
    }

    foreach ($vHub in $subVhubs) {
        foreach ($vhubConn in $vhubList) {
            Edge -From $vhubConn -To $vHub.Name @{label="virtualwan"}
        }
        $vhubList += $vHub.Name
        #foreach ($vnetConn in $vHub.VirtualNetworkConnections) {
        # TODO Add any missing vNet connections that may exist
        #}
        $vhubVpns = $subVhubVpnGw | Where-Object {$_.VirtualHub.Id -eq $vHub.Id}
        foreach ($vhubVpn in $vhubVpns) {
            $vpnLinkName = $vhubVpn.Connections[0].name.Split("Connection-")[1]
            Edge -From $vpnLinkName -To $vHub.Name @{label="vpnlink"}
        }
        $vhubErcConns = $subVhubErcConns | Where-Object {$_.RoutingConfiguration.AssociatedRouteTable.Id.Split("/")[8] -eq $vHub.Name }
        foreach ($vhubErcConn in $vhubErcConns) {
            Edge -From $vhubErcConn.ExpressRouteCircuitPeering.Id.Split("/")[8] -To $vHub.Name @{label="connection"}
        }
    } #>
}  | Export-PSGraph -DestinationPath .\$outputFile -OutputFormat $outputFormat
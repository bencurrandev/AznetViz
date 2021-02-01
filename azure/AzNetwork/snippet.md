    FMG-EUS-COR-VNT {
        .property('resourcegroup','FMG-EUS-COR-RG-NETWORK').property('subscription','IS-Shared-Services').property('location','eastus').property('type','Microsoft-Network-virtualNetworks')
g.AddV('vnet').property('ResourceId','FMG-EUS-COR-RG-NETWORK_FMG-SOBR-COR-VNT-10.231.10.0').property('name','FMG-SOBR-COR-VNT-10.231.10.0').property('resourcegroup','FMG-SOBR-COR-RG-NETWORK').property('subscription','IS-Shared-Services').property('location','southamerica').property('type','Microsoft-Network-virtualNetworks')
    }
    FMG-EUS-COR-VWANHUB }|--|| FMG-EUS-COR-VNT : peering
g.V().hasLabel('vnet').has('name', 'FMG-EUS-COR-VNT').addE('peering').to(g.V().hasLabel('vnet').has('name', 'FMG-EUS-COR-VWANHUB'))

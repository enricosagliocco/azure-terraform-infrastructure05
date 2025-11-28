##############################################################################
# Subnet for AKS Nodes
##############################################################################
resource "azurerm_subnet" "aks_subnet" {
    name = var.subnet_AKS_name
    private_endpoint_network_policies = "Enabled"
    resource_group_name = data.azurerm_resource_group.existing_rg.name
    virtual_network_name = data.azurerm_virtual_network.existing_vnet.name
    address_prefixes = [var.subnet_AKS_cidr]
}

##############################################################################
# Subnet for Private Endpoints
##############################################################################
resource "azurerm_subnet" "private_endpoints_subnet" {
    name = var.pe_subnet_name
    private_endpoint_network_policies = "Enabled"
    resource_group_name = data.azurerm_resource_group.existing_rg.name
    virtual_network_name = data.azurerm_virtual_network.existing_vnet.name
    address_prefixes = [var.pe_subnet_cidr]
}

##############################################################################
# Associations
##############################################################################
resource "azurerm_subnet_network_security_group_association" "snet-subnet1-NSG" {
    subnet_id = azurerm_subnet.aks_subnet.id
    network_security_group_id = data.azurerm_network_security_group.existing_nsg.id
}

resource "azurerm_subnet_route_table_association" "assoc_rt" {
    subnet_id = azurerm_subnet.aks_subnet.id
    route_table_id = data.azurerm_route_table.existing_rt.id
}

##############################################################################
# Virtual Network
##############################################################################
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

##############################################################################
# Network Security Group
##############################################################################
resource "azurerm_network_security_group" "main" {
  name                = var.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

##############################################################################
# Route Table
##############################################################################
resource "azurerm_route_table" "main" {
  name                          = var.route_table_name
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

##############################################################################
# Subnet for AKS Nodes
##############################################################################
resource "azurerm_subnet" "aks_subnet" {
    name = var.subnet_AKS_name
    private_endpoint_network_policies = "Enabled"
    resource_group_name = azurerm_resource_group.main.name
    virtual_network_name = azurerm_virtual_network.main.name
    address_prefixes = [var.subnet_AKS_cidr]
}

##############################################################################
# Subnet for Private Endpoints
##############################################################################
resource "azurerm_subnet" "private_endpoints_subnet" {
    name = var.pe_subnet_name
    private_endpoint_network_policies = "Enabled"
    resource_group_name = azurerm_resource_group.main.name
    virtual_network_name = azurerm_virtual_network.main.name
    address_prefixes = [var.pe_subnet_cidr]
}

##############################################################################
# Associations
##############################################################################
resource "azurerm_subnet_network_security_group_association" "snet-subnet1-NSG" {
    subnet_id = azurerm_subnet.aks_subnet.id
    network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_route_table_association" "assoc_rt" {
    subnet_id = azurerm_subnet.aks_subnet.id
    route_table_id = azurerm_route_table.main.id
}

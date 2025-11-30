# main.tf - AKS 100% privato + solo il tuo storage account privato (zero storage "fantasma")

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  cloud {
    organization = "enrico-sagliocco"
    workspaces {
      name = "azure-terraform-infrastructure"
    }
  }
}

provider "azurerm" {
  features {}
}

##############################################################################
# Resource Group
##############################################################################
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

##############################################################################
# Virtual Network + Subnets
##############################################################################
resource "azurerm_virtual_network" "main" {
  name                = "vnet-aks-private"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

##############################################################################
# NAT Gateway → elimina lo storage account automatico di AKS
##############################################################################
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-aks-outbound"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "aks" {
  name                    = "nat-aks-outbound"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1", "2", "3"]
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat_ip" {
  nat_gateway_id       = azurerm_nat_gateway.aks.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "aks_nodes" {
  subnet_id      = azurerm_subnet.aks_nodes.id
  nat_gateway_id = azurerm_nat_gateway.aks.id
}

##############################################################################
# NSG base + associazione (opzionale ma consigliata)
##############################################################################
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-nodes"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # AKS richiede 443 verso API server e alcune porte per health probe
  security_rule {
    name                       = "allow-https-api"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

##############################################################################
# Private DNS Zones obbligatorie per cluster privato
##############################################################################
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = "link-aks-vnet"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-vnet"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id            = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-vnet"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

##############################################################################
# AKS Cluster totalmente privato (NO storage account automatico)
##############################################################################
resource "azurerm_kubernetes_cluster" "aks" {
  name                            = var.aks_cluster_name
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  dns_prefix                      = var.aks_dns_prefix
  private_cluster_enabled            = true
  private_cluster_public_fqdn_enabled = true

  default_node_pool {
    name                 = "default"
    node_count           = var.aks_node_count
    vm_size              = var.aks_vm_size
    vnet_subnet_id       = azurerm_subnet.aks_nodes.id
    enable_auto_scaling  = true
    min_count            = 1
    max_count            = var.aks_max_node_count != null ? var.aks_max_node_count : 5
    type                 = "VirtualMachineScaleSets"
    zones                = ["1", "2", "3"]
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "calico"
    load_balancer_sku  = "standard"
    outbound_type      = "userDefinedRouting"   # UDR mantenuto grazie al NAT Gateway
  }

  private_dns_zone_id = azurerm_private_dns_zone.aks.id

  tags = merge(var.tags, {
    Environment = "non-prod"
    Project     = "aks-fully-private"
  })
}

##############################################################################
# IL TUO UNICO Storage Account privato
##############################################################################
resource "azurerm_storage_account" "private_sa" {
  name                          = var.storage_account_name          # es. myprivatestoragesa001
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  public_network_access_enabled = false
  allow_nested_items_to_be_public = false
  min_tls_version               = "TLS1_2"

  tags = var.tags
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${var.storage_account_name}-blob-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.storage_account_name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.private_sa.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "blob-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }

  tags = var.tags
}

##############################################################################
# ACR privato con private endpoint
##############################################################################
resource "azurerm_container_registry" "acr" {
  name                     = var.acr_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku                      = "Premium"
  admin_enabled            = false
  public_network_access_enabled = false

  tags = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "${var.acr_name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${var.acr_name}-psc"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "acr-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }

  tags = var.tags
}
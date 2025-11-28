# terraform/main.tf - Fully Private AKS Cluster Configuration

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # Backend Terraform Cloud configuration
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
# Private AKS Cluster
##############################################################################

resource "azurerm_kubernetes_cluster" "aks" {
    name                = var.aks_cluster_name
    location            = azurerm_resource_group.main.location
    resource_group_name = azurerm_resource_group.main.name
    dns_prefix          = var.aks_dns_prefix

    private_cluster_enabled = true
    private_dns_zone_id = "None"
    private_cluster_public_fqdn_enabled = true

    default_node_pool {
        name       = "nodepool1"
        node_count = var.aks_node_count
        vm_size    = var.aks_vm_size
        vnet_subnet_id = azurerm_subnet.aks_subnet.id
        type = "VirtualMachineScaleSets"
        enable_auto_scaling = true
        min_count = 1
        max_count = var.aks_max_node_count != null ? var.aks_max_node_count : 3
    }

    identity {
        type = "SystemAssigned"
    }

    network_profile {
        network_plugin = "azure"
        network_policy = "calico" 
        load_balancer_sku = "standard" 
        outbound_type = "userDefinedRouting" 
    }

    tags = var.tags != null ? var.tags : {
        Environment = "aks-dih-test"
        Project = "aks-private"
        "glo:m:any:leanix-application-id" = "ffbe8fa8-1e66-4074-a4f5-3169ce3b5dfe"
        "glo:m:any:stage" = "non-prod"
    }

    depends_on = [
        azurerm_subnet.aks_subnet,
        azurerm_subnet_network_security_group_association.snet-subnet1-NSG,
        azurerm_subnet_route_table_association.assoc_rt
    ]
}

##############################################################################
# Storage Account
##############################################################################
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled = false

  tags = var.tags
}

##############################################################################
# Private Endpoint for Storage Account
##############################################################################
resource "azurerm_private_endpoint" "storage_pe" {
  name                = "${var.storage_account_name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints_subnet.id

  private_service_connection {
    name                           = "${var.storage_account_name}-psc"
    private_connection_resource_id = azurerm_storage_account.storage.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  tags = var.tags
}

##############################################################################
# Azure Container Registry (ACR)
##############################################################################
resource "azurerm_container_registry" "acr" {
  name                     = var.acr_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  sku                      = "Premium" # Premium SKU is required for private endpoints
  admin_enabled            = false
  public_network_access_enabled = false

  tags = var.tags
}

##############################################################################
# Private DNS Zone for ACR
##############################################################################
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "${var.acr_name}-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = var.tags
}

##############################################################################
# Private Endpoint for ACR
##############################################################################
resource "azurerm_private_endpoint" "acr" {
  name                = "${var.acr_name}-pe"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints_subnet.id

  private_service_connection {
    name                           = "${var.acr_name}-psc"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }

  tags = var.tags
}




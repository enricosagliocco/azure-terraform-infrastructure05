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
# Data Sources - Existing Resources
##############################################################################
data "azurerm_resource_group" "existing_rg" {
    name = var.resource_group_name
}

data "azurerm_virtual_network" "existing_vnet"{
    name = var.vnet_name
    resource_group_name = data.azurerm_resource_group.existing_rg.name
}

data "azurerm_network_security_group" "existing_nsg" {
    name = var.nsg_name
    resource_group_name = data.azurerm_resource_group.existing_rg.name
}

data "azurerm_route_table" "existing_rt" {
    name = var.route_table_name
    resource_group_name = data.azurerm_resource_group.existing_rg.name
}

##############################################################################
# Private AKS Cluster
##############################################################################

resource "azurerm_kubernetes_cluster" "aks" {
    name                = var.aks_cluster_name
    location            = data.azurerm_resource_group.existing_rg.location
    resource_group_name = data.azurerm_resource_group.existing_rg.name
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
  resource_group_name      = data.azurerm_resource_group.existing_rg.name
  location                 = data.azurerm_resource_group.existing_rg.location
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
  location            = data.azurerm_resource_group.existing_rg.location
  resource_group_name = data.azurerm_resource_group.existing_rg.name
  subnet_id           = azurerm_subnet.private_endpoints_subnet.id

  private_service_connection {
    name                           = "${var.storage_account_name}-psc"
    private_connection_resource_id = azurerm_storage_account.storage.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  tags = var.tags
}

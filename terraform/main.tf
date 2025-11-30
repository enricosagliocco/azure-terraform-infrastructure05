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
# Storage Account - Inizialmente SENZA restrizioni
##############################################################################
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # IMPORTANTE: Inizialmente aperto, poi bloccheremo con le network_rules
  public_network_access_enabled = true

  tags = var.tags
}

# NOTA: Il container "persistent-volumes" deve essere creato manualmente
# Esegui questi comandi DOPO il terraform apply:
#
# az storage account update --name myprivatestoragesa001 \
#   --resource-group my-aks-rg --default-action Allow
#
# az storage container create --name persistent-volumes \
#   --account-name myprivatestoragesa001 --auth-mode login
#
# az storage account update --name myprivatestoragesa001 \
#   --resource-group my-aks-rg --default-action Deny

##############################################################################
# Network Rules (applicate DOPO la creazione del container)
##############################################################################
resource "azurerm_storage_account_network_rules" "storage_rules" {
  storage_account_id = azurerm_storage_account.storage.id

  default_action = "Deny"
  bypass         = ["AzureServices"]

  # Rimuovi il depends_on dato che il container è gestito manualmente
  # depends_on = [
  #   azurerm_storage_container.pv_data
  # ]
}

##############################################################################
# Role Assignments per AKS Identity
##############################################################################

# Permetti ad AKS di leggere/scrivere blob
resource "azurerm_role_assignment" "aks_storage_blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Permetti ad AKS di gestire lo storage account
resource "azurerm_role_assignment" "aks_storage_account_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

##############################################################################
# Private Endpoint per Storage Account
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

  depends_on = [
    azurerm_storage_container.pv_data
  ]
}

##############################################################################
# Private DNS Zone per Storage Account
##############################################################################
resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "${var.storage_account_name}-blob-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "storage_blob" {
  name                = azurerm_storage_account.storage.name
  zone_name           = azurerm_private_dns_zone.storage_blob.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

##############################################################################
# Azure Container Registry (ACR) - Solo con Private Endpoint
##############################################################################
resource "azurerm_container_registry" "acr" {
  name                          = var.acr_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = true
  
  # Network rules semplici: nega tutto pubblico, permetti solo Azure Services
  network_rule_set {
    default_action = "Deny"
  }

  tags = var.tags
}

##############################################################################
# Role Assignment per AKS -> ACR
# NOTA: Questo role assignment esiste già, quindi è commentato
# Se necessario ricrearlo: decommentare o eseguire manualmente:
# az role assignment create --assignee <kubelet-identity-id> \
#   --role "AcrPull" --scope <acr-id>
##############################################################################
# resource "azurerm_role_assignment" "aks_acr_pull" {
#   scope                = azurerm_container_registry.acr.id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
# }

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
output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "aks_cluster_id" {
  value = azurerm_kubernetes_cluster.aks.id
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_private_fqdn" {
  value = azurerm_kubernetes_cluster.aks.private_fqdn
}

output "aks_node_resource_group" {
  value = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "storage_account_id" {
  value = azurerm_storage_account.storage.id
}

output "private_endpoint_id" {
  value = azurerm_private_endpoint.storage_pe.id
}

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

output "storage_private_endpoint_id" {
  value = azurerm_private_endpoint.storage_pe.id
}

output "acr_id" {
  value = azurerm_container_registry.acr.id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "private_endpoint_storage_ip" {
  value       = azurerm_private_endpoint.storage_pe.private_service_connection[0].private_ip_address
  description = "IP privato del private endpoint dello storage"
}

output "private_endpoint_acr_ip" {
  value       = azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address
  description = "IP privato del private endpoint dell'ACR"
}

output "aks_kubelet_identity" {
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  description = "Object ID della kubelet identity (per ACR pull)"
}
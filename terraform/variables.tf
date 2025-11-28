variable "location" {
  description = "The Azure region where to create the resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name for the new resource group."
  type        = string
}

variable "vnet_name" {
  description = "Name for the new virtual network."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the new virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "nsg_name" {
  description = "Name for the new network security group."
  type        = string
}

variable "route_table_name" {
  description = "Name for the new route table."
  type        = string
}

variable "subnet_AKS_name" {
  description = "Name of the AKS subnet."
  type        = string
}

variable "subnet_AKS_cidr" {
  description = "CIDR for the AKS subnet."
  type        = string
}

variable "pe_subnet_name" {
  description = "Name of the private endpoints subnet."
  type        = string
}

variable "pe_subnet_cidr" {
  description = "CIDR for the private endpoints subnet."
  type        = string
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
}

variable "aks_dns_prefix" {
  description = "DNS prefix for the AKS cluster."
  type        = string
}

variable "aks_node_count" {
  description = "Initial number of nodes for the AKS cluster."
  type        = number
  default     = 1
}

variable "aks_vm_size" {
  description = "VM size for the AKS nodes."
  type        = string
  default     = "Standard_B2s"
}

variable "aks_max_node_count" {
  description = "Maximum number of nodes for auto-scaling."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}

variable "storage_account_name" {
  description = "Name of the storage account."
  type        = string
}

variable "acr_name" {
  description = "Name for the new Azure Container Registry."
  type        = string
}



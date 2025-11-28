# Example .tfvars file
# Rename this to terraform.tfvars and fill in your actual values

resource_group_name  = "your-resource-group"
vnet_name            = "your-virtual-network"
nsg_name             = "your-nsg-name"
route_table_name     = "your-route-table-name"

subnet_AKS_name      = "aks-subnet"
subnet_AKS_cidr      = "10.185.46.0/26"

pe_subnet_name       = "pe-subnet"
pe_subnet_cidr       = "10.185.46.64/26"

aks_cluster_name     = "my-private-aks-cluster"
aks_dns_prefix       = "myprivateaks"

storage_account_name = "myprivatestoragesa"

tags = {
  Environment = "aks-dih-test"
  Project     = "aks-private"
  "glo:m:any:leanix-application-id" = "ffbe8fa8-1e66-4074-a4f5-3169ce3b5dfe"
  "glo:m:any:stage"                 = "non-prod"
}

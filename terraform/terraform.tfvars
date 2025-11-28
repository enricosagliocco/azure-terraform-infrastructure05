# Example .tfvars file
# Rename this to terraform.tfvars and fill in your actual values

location = "WestEurope"

resource_group_name  = "my-aks-rg"
vnet_name            = "my-aks-vnet"
vnet_address_space   = "10.10.0.0/16"
nsg_name             = "my-aks-nsg"
route_table_name     = "my-aks-rt"

subnet_AKS_name      = "aks-subnet"
subnet_AKS_cidr      = "10.10.1.0/24"

pe_subnet_name       = "pe-subnet"
pe_subnet_cidr       = "10.10.2.0/24"

aks_cluster_name     = "my-private-aks-cluster"
aks_dns_prefix       = "myprivateaks"

storage_account_name = "myprivatestoragesa001"

tags = {
  Environment = "dev"
  Project     = "private-aks-testing"
}

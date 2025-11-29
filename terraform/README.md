# Architettura AKS Privato con Servizi Privati

Questo progetto Terraform implementa un'architettura Azure sicura che include un cluster Azure Kubernetes Service (AKS) completamente privato, un Azure Container Registry (ACR) privato e uno Storage Account privato. Tutte le comunicazioni tra i servizi avvengono sulla rete virtuale di Azure, senza esposizione a Internet.

## Diagramma dell'Architettura (Mermaid)

```mermaid
graph TD
    subgraph "Azure"
        subgraph "Resource Group"
            subgraph "Virtual Network (VNet)"
                subgraph "Subnet Private Endpoints"
                    PE_ACR["Private Endpoint (ACR)"];
                    PE_Storage["Private Endpoint (Storage)"];
                end

                subgraph "Subnet AKS"
                    AKS[("AKS Cluster")];
                end
            end

            subgraph "Servizi PaaS"
                ACR["Azure Container Registry"];
                Storage["Azure Storage Account"];
            end
        end
    end

    AKS -- "Pull Immagine" --> PE_ACR;
    AKS -- "Monta Volume" --> PE_Storage;
    PE_ACR -- "Link Privato" --> ACR;
    PE_Storage -- "Link Privato" --> Storage;

    style AKS fill:#326ce5,stroke:#fff,stroke-width:2px,color:#fff
    style ACR fill:#f6a821,stroke:#fff,stroke-width:2px,color:#fff
    style Storage fill:#f6a821,stroke:#fff,stroke-width:2px,color:#fff
```

## Architettura

L'infrastruttura creata da questa configurazione è composta dai seguenti elementi:

- **Resource Group**: Un contenitore logico per tutte le risorse Azure.
- **Virtual Network (VNet)**: Una rete virtuale isolata in cui risiedono tutte le risorse.
- **Subnet**:
  - **Subnet AKS**: Dedicata ai nodi del cluster Kubernetes.
  - **Subnet Private Endpoints**: Dedicata a tutti i private endpoint per l'accesso privato ai servizi PaaS.
- **Network Security Group (NSG)** e **Route Table**: Applicate alla subnet di AKS per controllare il traffico.
- **Cluster AKS Privato**: Il piano di controllo (API server) non è esposto pubblicamente. Le interazioni con il cluster devono avvenire da una macchina (es. una bastion host) all'interno della stessa VNet.
- **Azure Storage Account**: Uno storage account per dati (blob, file, etc.) con accesso di rete pubblico disabilitato.
- **Azure Container Registry (ACR)**: Un registry per le immagini Docker con accesso di rete pubblico disabilitato.
- **Private Endpoints**:
  - Uno per lo Storage Account, che gli assegna un IP privato nella subnet dei PE.
  - Uno per l'ACR, che gli assegna un IP privato nella subnet dei PE.
- **Zone DNS Private**:
  - `privatelink.azurecr.io`: Per risolvere il nome dell'ACR nel suo IP privato.
  - Una per lo storage (non esplicitamente creata qui ma gestita da Azure quando si crea il PE per lo storage).

## Load Balancer Interno (Privato)

Dato che il cluster è configurato come privato (`private_cluster_enabled = true`) e utilizza lo SKU `standard` per il load balancer (`load_balancer_sku = "standard"`), qualsiasi servizio Kubernetes di tipo `LoadBalancer` creerà un **Internal Load Balancer (ILB)**.

Caratteristiche principali:
- **IP Privato**: All'ILB viene assegnato un indirizzo IP privato dalla subnet del cluster AKS.
- **Nessuna Esposizione Pubblica**: Il servizio non è accessibile da Internet, ma solo dall'interno della stessa VNet o da reti connesse (tramite peering, VPN, o ExpressRoute).
- **Risoluzione DNS**: Per accedere al servizio tramite un nome DNS (invece che con l'IP), è necessario configurare la risoluzione DNS appropriata all'interno della VNet.

**Esempio di Servizio (`internal-lb-service.yaml`):**
Applicando questo manifest, Kubernetes richiederà un load balancer ad Azure, che risponderà creando un ILB.

```yaml
# 1. Prendi il PrincipalId della managed identity del cluster
PRINCIPAL_ID=$(az aks show --resource-group my-aks-rg --name my-private-aks-cluster --query 'identity.principalId' -o tsv)
# ← sostituisci <NOME-CLUSTER-AKS> con il nome reale del cluster (es. aks-dih-test o quello che vedi in az aks list)

# 2. Assegna i ruoli necessari (questi sono i due che mancano sempre)
az role assignment create --assignee "$PRINCIPAL_ID" --role "Network Contributor" --scope "/subscriptions/d4651f01-cb5e-4f98-8bdb-0cd50eaefa87/resourceGroups/my-aks-rg/providers/Microsoft.Network/virtualNetworks/my-aks-vnet/subnets/aks-subnet"

az role assignment create --assignee "$PRINCIPAL_ID" --role "Reader" --resource-group my-aks-rg

# 3. Elimina il Service incasinato e riapplicalo PULITO (senza annotation subnet)
kubectl delete svc my-internal-app-service --force

# --- ConfigMap (opzionale) ---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-index-html
data:
  index.html: |
    <!DOCTYPE html><html><head><title>OK</title></head><body><h1>Nginx + LoadBalancer funziona!</h1></body></html>
---
# --- Deployment ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: index
          mountPath: /usr/share/nginx/html/index.html
          subPath: index.html
      volumes:
      - name: index
        configMap:
          name: nginx-index-html
---
apiVersion: v1
kind: Service
metadata:
  name: my-internal-app-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"  # Rende il LB interno
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: my-app
```
Per ottenere l'IP privato assegnato, puoi usare `kubectl get service my-internal-app-service -o wide`.

## Come Utilizzare i Servizi Privati da Kubernetes

Poiché sia il cluster AKS che i servizi (ACR e Storage) sono collegati alla stessa VNet tramite Private Endpoints, la comunicazione è automatica e sicura all'interno della rete privata.

### 1. Utilizzare l'Azure Container Registry (ACR) Privato

Per permettere al cluster AKS di scaricare immagini dal tuo ACR privato in modo sicuro, è necessario associare l'ACR al cluster. Questo concede all'identità gestita di AKS i permessi necessari (`AcrPull`) sul registry.

**Comando di Associazione (da eseguire una tantum):**
Sostituisci i valori tra parentesi con i nomi delle tue risorse (puoi prenderli dagli output di Terraform).

```bash
az aks update --name <aks_cluster_name> --resource-group <resource_group_name> --attach-acr <acr_name>
```

Una volta eseguito questo comando, puoi fare riferimento alle immagini nel tuo ACR direttamente nei manifest dei tuoi pod, come in questo esempio:

**Esempio Pod (`pod-acr-example.yaml`):**
Assicurati di sostituire `<acr_login_server>` con il `login_server` del tuo ACR (disponibile negli output di Terraform).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: my-app-container
    image: <acr_login_server>/my-app-image:latest
    ports:
    - containerPort: 80
```

Quando applichi questo manifest, Kubelet sui nodi AKS contatterà l'ACR tramite il suo private endpoint, risolverà il nome tramite la zona DNS privata e scaricherà l'immagine in modo sicuro.

### 2. Utilizzare lo Storage Account Privato

Per usare lo storage a oggetti (blob) all'interno di un pod, si utilizza il driver CSI (Container Storage Interface) di Azure Blob. Questo permette di montare un container di blob come un volume effimero direttamente nel file system del pod.

**Prerequisiti:**
Il driver CSI per Blob Storage deve essere abilitato sul tuo cluster. Puoi farlo con il seguente comando:
```bash
az aks enable-addons --addons azure-blob-csi-driver --name <aks_cluster_name> --resource-group <resource_group_name>
```

**Esempio Pod (`pod-storage-example.yaml`):**
Questo manifest mostra come montare un container di blob chiamato `my-data-container` in un pod. Il pod potrà leggere e scrivere file in `/mnt/data` come se fosse una cartella locale.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-blob-pod
spec:
  containers:
  - name: my-container
    image: mcr.microsoft.com/cbl-mariner/base/core:2.0
    command:
      - "sleep"
      - "3600"
    volumeMounts:
      - name: blob-volume
        mountPath: /mnt/data
  volumes:
  - name: blob-volume
    csi:
      driver: blob.csi.azure.com
      volumeAttributes:
        # Sostituisci con il nome del tuo storage account e del container
        storageAccount: <storage_account_name>
        containerName: my-data-container
        # Se usi un segreto per l'autenticazione (consigliato)
        # secretName: azure-storage-secret
        # Se usi l'identità del pod (ancora più sicuro)
        # msiendpoint: "..."
```

**Autenticazione:**
Il pod ha bisogno delle credenziali per accedere allo storage. L'approccio più sicuro è usare l'**identità del pod (Pod Identity)**, che associa un'identità gestita di Azure a un pod Kubernetes. In alternativa, puoi creare un segreto Kubernetes contenente la connection string o la chiave di accesso dello storage account. Poiché il pod e lo storage sono sulla stessa VNet, il traffico avverrà tramite il private endpoint.

## Export environment variables
set -a
. ./credentials/env-fssa
set +a

## Auth to Azure
az login
az account list --refresh --output table
az account set -s $SUBSCRIPTION_ID

## Create vnet and subnet for cloud resources
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME\
    --address-prefixes 10.1.0.0/16 \
    --subnet-name kubesubnet \
    --subnet-prefix 10.1.0.0/24
VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME --query id -o tsv)
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name kubesubnet --query id -o tsv)
az role assignment create --assignee $SERVICE_PRINCIPLE_ID --scope $VNET_ID --role Contributor

## Create Kubernetes cluster
ssh-keygen -f credentials/ssh-key-jhubspark
az aks create --name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--service-principal $SERVICE_PRINCIPLE_ID \
--client-secret  $SERVICE_PRINCIPLE_SECRET \
--ssh-key-value credentials/ssh-key-jhubspark.pub \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--enable-vmss \
--kubernetes-version $AKS_VERSION \
--load-balancer-sku standard \
--vm-set-type VirtualMachineScaleSets \
--vnet-subnet-id $SUBNET_ID \
--location eastus \
--output table

# Create system nodepool
az aks nodepool add --name systempool \
--cluster-name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--kubernetes-version $AKS_VERSION \
--node-taints CriticalAddonsOnly=true:NoSchedule \
--mode System \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Delete default nodepool nodepool1
az aks nodepool delete --name jhubuserpool \
--cluster-name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--output table

# Create node pool for deploying applications
az aks nodepool add --name apppool \
--cluster-name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--mode user \
--enable-cluster-autoscaler \
--kubernetes-version $AKS_VERSION \
--node-count 1 \
--max-count 4 \
--min-count 0 \
--labels dedicate.pool=apppool \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create jupyterhub user node pool
az aks nodepool add --name jhubuserpool \
--cluster-name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--mode user \
--enable-cluster-autoscaler \
--kubernetes-version $AKS_VERSION \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--labels hub.jupyter.org/node-purpose=user dedicate.pool=jhubuserpool \
--node-taints hub.jupyter.org/dedicated=user:NoSchedule \
--node-vm-size Standard_D4s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create spark node pool
az aks nodepool add --name $SPARK_NDOE_POOL \
--cluster-name $AKS_NAME \
--resource-group $RESOURCE_GROUP \
--mode user \
--enable-cluster-autoscaler \
--kubernetes-version $AKS_VERSION \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--labels dedicate.pool=$SPARK_NDOE_POOL \
--node-vm-size Standard_D8s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

## Install kubectl
az aks get-credentials --name $AKS_NAME \
	--resource-group $RESOURCE_GROUP \
	--output table
kubectl get node

## Set up Helm 3
# Mac OS
curl https://get.helm.sh/helm-v3.8.0-darwin-amd64.tar.gz > helm-v3.8.0.tar.gz
tar -zxvf helm-v3.8.0.tar.gz
mv darwin-amd64/helm /usr/local/bin/helm

## Setup container registery
az acr create \
--name $ACR_NAME \
--resource-group $RESOURCE_GROUP \
--sku Standard \
--admin-enabled true \
--location eastus \
--output table
az acr login --name $ACR_NAME
CLIENT_ID=$(az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --query "servicePrincipalProfile.clientId" --output tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" --output tsv)
az role assignment create --assignee $CLIENT_ID --role acrpull --scope $ACR_ID

## Setup storage account
az storage account create \
--name $ADLS_ACCOUNT_NAME \
--resource-group $RESOURCE_GROUP \
--allow-shared-key-access true \
--allow-blob-public-access true \
--kind StorageV2 \
--access-tier Hot \
--enable-hierarchical-namespace true \
--bypass AzureServices \
--enable-large-file-share \
--location eastus \
--output table

az storage share-rm create \
--name fs-$USER_FS \
--storage-account $ADLS_ACCOUNT_NAME \
--access-tier "TransactionOptimized" \
--quota 1024 \
--output table

az storage share-rm create \
--name fs-$PROJECT_FS \
--storage-account $ADLS_ACCOUNT_NAME \
--access-tier "TransactionOptimized" \
--quota 1024 \
--output table

# Deploy PVC
kubectl create namespace $JHUB_NAMESPACE
kubectl create secret generic azure-secret --from-literal=azurestorageaccountname=$ADLS_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$ADLS_ACCOUNT_KEY --type=Opaque -n $JHUB_NAMESPACE
sed -e "s/<USER_FS>/${USER_FS}/" -e "s/<PROJECT_FS>/${PROJECT_FS}/" -e "s/<LAKEHOUSE_BLOB>/${LAKEHOUSE_BLOB}/" -e "s/<JHUB_NAMESPACE>/${JHUB_NAMESPACE}/" pvc-pv-jhub.yaml > customized-pvc-pv.yaml
kubectl apply -f customized-pvc-pv.yaml -n $JHUB_NAMESPACE
# Install blob-csi-driver
helm repo add blob-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/blob-csi-driver/master/charts
helm install blob-csi-driver blob-csi-driver/blob-csi-driver \
 --set node.enableBlobfuseProxy=true \
 --namespace kube-system \
 --version v1.15.0

# Pull jupyterhub helm chart
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm fetch jupyterhub/jupyterhub --version 1.2.0

## Create pullsecret
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" --output tsv)
SP_PASSWD=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPLE_ID --scopes $ACR_ID --role acrpull --query password --output tsv)
SP_APP_ID=$(az ad sp show --id $SERVICE_PRINCIPLE_ID --query appId --output tsv)
kubectl create secret docker-registry $ACR_PULL_SECRET\
    --namespace $JHUB_NAMESPACE \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$SP_APP_ID \
    --docker-password=$SP_PASSWD

## Create service account for spark
kubectl --namespace $JHUB_NAMESPACE create serviceaccount $SERVICE_ACCOUNT
kubectl create clusterrolebinding spark-role-binding --clusterrole cluster-admin --serviceaccount=$JHUB_NAMESPACE:$SERVICE_ACCOUNT

## Build Images
az acr login --name $ACR_NAME
# Build spark base image
docker build \
	-f spark-py/Dockerfile \
	-t justmodeling/spark-delta2.0-py39:v3.2.1 ./spark-py
docker push justmodeling/spark-delta2.0-py39:v3.2.1
# build spark worker image
docker build \
	--build-arg BASE_IMAGE=$BASE_IMAGE \
	-f pyspark-notebook/Dockerfile.spark \
	-t $ACR_NAME.azurecr.io/pyspark-delta2.0-worker:v3.2.1 ./pyspark-notebook
docker push $ACR_NAME.azurecr.io/pyspark-delta2.0-worker:v3.2.1
# build pyspark notebook image
docker build \
	--build-arg ADLS_ACCOUNT_NAME=$ADLS_ACCOUNT_NAME \
	--build-arg ADLS_ACCOUNT_KEY=$ADLS_ACCOUNT_KEY \
	--build-arg ACR_NAME=$ACR_NAME \
	--build-arg ACR_PULL_SECRET=$ACR_PULL_SECRET \
	--build-arg JHUB_NAMESPACE=$JHUB_NAMESPACE \
	--build-arg WORK_IMAGE=$ACR_NAME.azurecr.io/pyspark-delta2.0-worker:v3.2.1 \
	--build-arg SPARK_NDOE_POOL=$SPARK_NDOE_POOL \
	--build-arg SERVICE_ACCOUNT=$SERVICE_ACCOUNT \
	--build-arg USER_FS_PVC=pvc-$USER_FS \
	--build-arg PROJECT_FS_PVC=pvc-$PROJECT_FS \
	--build-arg LAKEHOUSE_PVC=pvc-$LAKEHOUSE_BLOB \
	-f pyspark-notebook/Dockerfile \
	-t $ACR_NAME.azurecr.io/pyspark-delta2.0-notebook:v3.2.1 ./pyspark-notebook
docker push $ACR_NAME.azurecr.io/pyspark-delta2.0-notebook:v3.2.1
# build jupyterhub image
docker build -t $ACR_NAME.azurecr.io/k8s-hub:latest -f jupyter-k8s-hub/Dockerfile ./jupyter-k8s-hub
docker push $ACR_NAME.azurecr.io/k8s-hub:latest

# Build customized jupyterhub chart
sed -e "s/<NOTEBOOK-IMAGE>/${ACR_NAME}.azurecr.io\/pyspark-delta2.0-notebook:v3.2.1/" -e "s/<HUB-IMAGE>/${ACR_NAME}.azurecr.io\/k8s-hub/" -e "s/<LAKEHOUSE_BLOB>/${LAKEHOUSE_BLOB}/" config.yaml > customized-config.yaml

## Install jupyterhub
helm upgrade --install spark-jhub jupyterhub/jupyterhub \
	--namespace $JHUB_NAMESPACE  \
	--version=1.2.0 \
	--values customized-config.yaml \
	--timeout=5000s

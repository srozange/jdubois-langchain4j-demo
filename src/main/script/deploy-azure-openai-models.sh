#!/usr/bin/env bash

# Execute this script to deploy the needed Azure OpenAI models to execute the integration tests.
# For this, you need Azure CLI installed: https://learn.microsoft.com/cli/azure/install-azure-cli

echo "Setting up environment variables..."
echo "----------------------------------"
PROJECT="langchain4j-$RANDOM"
RESOURCE_GROUP="rg-$PROJECT"
LOCATION="swedencentral"
AI_SERVICE="ai-$PROJECT"
SEARCH_SERVICE="search-$PROJECT"
TAG="$PROJECT"

echo "Creating the resource group..."
echo "------------------------------"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags system="$TAG"

# If you want to know the available SKUs, run the following Azure CLI command:
# az cognitiveservices account list-skus --location "$LOCATION"  -o table

echo "Creating the Cognitive Service..."
echo "---------------------------------"
COGNITIVE_SERVICE_ID=$(az cognitiveservices account create \
  --name "$AI_SERVICE" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --custom-domain "$AI_SERVICE" \
  --tags system="$TAG" \
  --kind "OpenAI" \
  --sku "S0" \
   | jq -r ".id")

# Security
# - Disable API Key authentication
# - Assign a system Managed Identity to the Cognitive Service -> this is for using from other Azure services, like Azure Container Apps
# - Assign the Contributor role on this resource group to the current user, so he can use the models from the CLI (this is how tests would be normally executed)
az resource update --ids $COGNITIVE_SERVICE_ID --set properties.disableLocalAuth=true --latest-include-preview

az cognitiveservices account identity assign \
  --name "$AI_SERVICE" \
  --resource-group "$RESOURCE_GROUP"

PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az role assignment create \
        --role "Azure AI Developer" \
        --assignee "$PRINCIPAL_ID" \
        --scope /subscriptions/"$SUBSCRIPTION_ID"/resourceGroups/"$RESOURCE_GROUP"

echo "Storing Azure OpenAI endpoint in an environment variable..."
echo "--------------------------------------------------------"
AZURE_OPENAI_ENDPOINT=$(
  az cognitiveservices account show \
    --name "$AI_SERVICE" \
    --resource-group "$RESOURCE_GROUP" \
    | jq -r .properties.endpoint
  )

# If you want to know the available models, run the following Azure CLI command:
# az cognitiveservices account list-models --resource-group "$RESOURCE_GROUP" --name "$AI_SERVICE" -o table  

echo "Deploying a gpt-4o model..."
echo "----------------------"
az cognitiveservices account deployment create \
  --name "$AI_SERVICE" \
  --resource-group "$RESOURCE_GROUP" \
  --deployment-name "gpt-4o" \
  --model-name "gpt-4o" \
  --model-version "2024-05-13"  \
  --model-format "OpenAI" \
  --sku-capacity 1 \
  --sku-name "Standard"

echo "Deploying a text-embedding-ada model..."
echo "----------------------"
az cognitiveservices account deployment create \
  --name "$AI_SERVICE" \
  --resource-group "$RESOURCE_GROUP" \
  --deployment-name "text-embedding-ada" \
  --model-name "text-embedding-ada-002" \
  --model-version "2"  \
  --model-format "OpenAI" \
  --sku-capacity 1 \
  --sku-name "Standard"

echo "Deploying a dall-e-3 model..."
echo "----------------------"
az cognitiveservices account deployment create \
  --name "$AI_SERVICE" \
  --resource-group "$RESOURCE_GROUP" \
  --deployment-name "dall-e-3" \
  --model-name "dall-e-3" \
  --model-version "3.0"  \
  --model-format "OpenAI" \
  --sku-capacity 1 \
  --sku-name "Standard"

echo "Creating the AI Search Service..."
echo "---------------------------------"
az search service create \
  --name "$SEARCH_SERVICE" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku "basic" \
  --tags system="$TAG"

echo "Storing Azure AI Search endpoint and key in environment variables..."
echo "--------------------------------------------------------"
AZURE_SEARCH_ENDOINT="https://$SEARCH_SERVICE.search.windows.net"
AZURE_SEARCH_KEY=$(az search admin-key show --service-name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" | jq -r .primaryKey)

echo "AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT"
echo "AZURE_SEARCH_ENDPOINT=$AZURE_SEARCH_ENDPOINT"
echo "AZURE_SEARCH_KEY=$AZURE_SEARCH_KEY"

echo "AZURE_OPENAI_ENDPOINT=$AZURE_OPENAI_ENDPOINT" > .env
echo "AZURE_SEARCH_ENDPOINT=$AZURE_SEARCH_ENDPOINT" >> .env
echo "AZURE_SEARCH_KEY=$AZURE_SEARCH_KEY" >> .env

echo "Done!"

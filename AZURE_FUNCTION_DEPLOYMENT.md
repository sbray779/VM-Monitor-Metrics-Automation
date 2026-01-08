# Azure Function Deployment Guide

## Overview

This project is now an Azure Function that can be called from Logic Apps, Azure Automation, or any HTTP client.

## Deployment Options

### Option 1: Terraform (Recommended - Infrastructure as Code)

Deploy all infrastructure using Terraform for consistent, repeatable deployments.

📖 **[See terraform/README.md for complete Terraform deployment guide](terraform/README.md)**

**Quick Deploy:**
```bash
cd terraform
terraform init
terraform plan
terraform apply

# Then deploy function code
cd ..
func azure functionapp publish $(terraform -chdir=terraform output -raw function_app_name)
```

### Option 2: Azure CLI (Manual)

See instructions below for step-by-step Azure CLI deployment.

### Option 3: VS Code Extension

Use the Azure Functions extension in VS Code for GUI-based deployment.

## Functions Available

### 1. GetVMMetrics
**Endpoint:** `/api/vm-metrics`

Retrieves VM list and performance metrics.

**Parameters (Query String or JSON Body):**
- `subscription_id` (optional): Azure subscription ID
- `resource_group` (optional): Filter by specific resource group
- `hours_back` (optional): Number of hours to look back for metrics (default: 24)

**Example Requests:**
```bash
# GET request
GET https://your-function-app.azurewebsites.net/api/vm-metrics?hours_back=12

# POST request
POST https://your-function-app.azurewebsites.net/api/vm-metrics
Content-Type: application/json

{
  "resource_group": "my-resource-group",
  "hours_back": 24
}
```

### 2. GetVMsOnly
**Endpoint:** `/api/vms`

Retrieves only the VM list without metrics (faster).

**Parameters:**
- `subscription_id` (optional): Azure subscription ID
- `resource_group` (optional): Filter by specific resource group

## Local Development

### Prerequisites
- Python 3.8+
- Azure Functions Core Tools: `npm install -g azure-functions-core-tools@4`
- Azure CLI: `az login`

### Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure local settings:
Edit `local.settings.json` and set your subscription ID:
```json
{
  "Values": {
    "AZURE_SUBSCRIPTION_ID": "your-subscription-id"
  }
}
```

3. Run locally:
```bash
func start
```

The function will be available at:
- http://localhost:7071/api/vm-metrics
- http://localhost:7071/api/vms

### Test Locally
```bash
# Test GetVMMetrics
curl "http://localhost:7071/api/vm-metrics?hours_back=1"

# Test GetVMsOnly
curl "http://localhost:7071/api/vms"
```

## Azure Deployment

### Option 1: Deploy via VS Code (Recommended)

1. Install the Azure Functions extension for VS Code
2. Click the Azure icon in the sidebar
3. Sign in to Azure
4. Click "Deploy to Function App"
5. Follow the prompts to create or select a Function App

### Option 2: Deploy via Azure CLI

1. Create a Function App:
```bash
# Create resource group
az group create --name vm-metrics-rg --location eastus

# Create storage account
az storage account create \
  --name vmmetricsstore \
  --resource-group vm-metrics-rg \
  --location eastus \
  --sku Standard_LRS

# Create Function App (Linux + Python 3.11)
az functionapp create \
  --name vm-metrics-function \
  --resource-group vm-metrics-rg \
  --storage-account vmmetricsstore \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux \
  --consumption-plan-location eastus
```

2. Deploy the code:
```bash
func azure functionapp publish vm-metrics-function
```

### Option 3: Deploy via Azure Portal

1. Create a new Function App in the Azure Portal
2. Configure:
   - Runtime: Python
   - Version: 3.11
   - Operating System: Linux
   - Plan: Consumption (or Premium/Dedicated as needed)
3. Use Deployment Center to connect to your Git repository

## Authentication & Permissions

The Function App needs the following permissions:

### Managed Identity (Recommended)
1. Enable System-Assigned Managed Identity on the Function App:
```bash
az functionapp identity assign \
  --name vm-metrics-function \
  --resource-group vm-metrics-rg
```

2. Assign required roles:
```bash
# Get the managed identity principal ID
PRINCIPAL_ID=$(az functionapp identity show \
  --name vm-metrics-function \
  --resource-group vm-metrics-rg \
  --query principalId -o tsv)

# Assign Reader role for VMs
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Reader" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID

# Assign Monitoring Reader role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Monitoring Reader" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID
```

### Application Settings

Configure these in the Function App:

```bash
az functionapp config appsettings set \
  --name vm-metrics-function \
  --resource-group vm-metrics-rg \
  --settings AZURE_SUBSCRIPTION_ID="your-subscription-id"
```

## Calling from Logic Apps

### Add HTTP Action

1. In Logic App Designer, add "HTTP" action
2. Configure:
   - **Method:** POST
   - **URI:** `https://your-function-app.azurewebsites.net/api/vm-metrics?code=YOUR_FUNCTION_KEY`
   - **Headers:**
     - `Content-Type`: `application/json`
   - **Body:**
     ```json
     {
       "resource_group": "@{variables('resourceGroup')}",
       "hours_back": 24
     }
     ```

3. Parse the JSON response:
   - Add "Parse JSON" action
   - Use response body from HTTP action
   - Sample schema:
     ```json
     {
       "type": "object",
       "properties": {
         "timestamp": {"type": "string"},
         "vm_count": {"type": "integer"},
         "vms": {"type": "array"},
         "metrics": {"type": "array"}
       }
     }
     ```

### Get Function Key

```bash
az functionapp function keys list \
  --name vm-metrics-function \
  --resource-group vm-metrics-rg \
  --function-name GetVMMetrics
```

## Monitoring

### View Logs
```bash
# Stream logs
func azure functionapp logstream vm-metrics-function
```

### Application Insights
The Function App automatically integrates with Application Insights for:
- Request tracking
- Performance metrics
- Error logging
- Custom telemetry

View insights in Azure Portal > Your Function App > Application Insights

## Troubleshooting

### Common Issues

**Authentication Errors:**
- Ensure Managed Identity is enabled
- Verify role assignments are correct
- Check `AZURE_SUBSCRIPTION_ID` is set

**Timeout Errors:**
- Increase function timeout in `host.json` (max 10 minutes for Consumption plan)
- Consider Premium or Dedicated plan for longer operations
- Reduce `hours_back` parameter

**Missing Metrics:**
- Verify VM has monitoring agent installed
- Check Monitoring Reader role assignment
- Some metrics may not be available for all VM types

## Cost Optimization

- Use the `GetVMsOnly` endpoint when you only need the VM list
- Reduce `hours_back` to minimize API calls
- Consider caching results if calling frequently
- Use Consumption plan for infrequent calls
- Use Premium plan for consistent workloads

## Security Best Practices

1. **Use Managed Identity** instead of connection strings
2. **Enable Authentication** in Function App settings
3. **Use Key Vault** for sensitive configuration
4. **Implement IP restrictions** if calling from known sources
5. **Enable HTTPS only**
6. **Rotate function keys** regularly

## Next Steps

- Configure scheduled execution using Timer Trigger
- Add output bindings to store results in Cosmos DB or Blob Storage
- Implement caching for frequently requested data
- Add filtering/aggregation options
- Create dashboard using Power BI or Grafana

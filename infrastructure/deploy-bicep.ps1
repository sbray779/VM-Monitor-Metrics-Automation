#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Azure Function infrastructure using Bicep for Flex Consumption plan.

.DESCRIPTION
    This script deploys the VM Metrics Function App infrastructure using Bicep templates,
    which properly supports Flex Consumption (FC1) plans with all required configurations.

.EXAMPLE
    .\deploy-bicep.ps1
    Deploys the infrastructure to the vm-metrics-rg resource group.

.EXAMPLE
    .\deploy-bicep.ps1 -ResourceGroup "my-rg" -Location "westus2"
    Deploys to a custom resource group and location.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "vm-metrics-rg",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Function App Infrastructure Deployment (Bicep) ===" -ForegroundColor Cyan
Write-Host ""

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription: $SubscriptionId" -ForegroundColor Yellow
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set subscription"
        exit 1
    }
}

# Get current subscription
$currentSub = az account show --query "{id:id, name:name}" -o json | ConvertFrom-Json
Write-Host "Using subscription: $($currentSub.name) ($($currentSub.id))" -ForegroundColor Green
Write-Host ""

# Check if resource group exists, create if not
Write-Host "Checking resource group: $ResourceGroup" -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "Creating resource group: $ResourceGroup in $Location" -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create resource group"
        exit 1
    }
    Write-Host "Resource group created successfully" -ForegroundColor Green
} else {
    Write-Host "Resource group already exists" -ForegroundColor Green
}
Write-Host ""

# Deploy Bicep template
Write-Host "Deploying Bicep template..." -ForegroundColor Yellow
Write-Host "This will create:"
Write-Host "  - Flex Consumption (FC1) App Service Plan" -ForegroundColor Cyan
Write-Host "  - Linux Function App with Python 3.11" -ForegroundColor Cyan
Write-Host "  - Storage Account (no shared keys)" -ForegroundColor Cyan
Write-Host "  - Application Insights + Log Analytics" -ForegroundColor Cyan
Write-Host "  - All required RBAC role assignments" -ForegroundColor Cyan
Write-Host ""

$deploymentName = "vm-metrics-$(Get-Date -Format 'yyyyMMddHHmmss')"
$bicepFile = Join-Path $PSScriptRoot "bicep" "main.bicep"
$parametersFile = Join-Path $PSScriptRoot "bicep" "main.bicepparam"

az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --template-file $bicepFile `
    --parameters $parametersFile `
    --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep deployment failed"
    exit 1
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""

# Get outputs
Write-Host "Retrieving deployment outputs..." -ForegroundColor Yellow
$outputs = az deployment group show `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --query "properties.outputs" -o json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$functionAppUrl = $outputs.functionAppUrl.value
$storageAccountName = $outputs.storageAccountName.value

# Create required storage containers
Write-Host ""
Write-Host "Creating storage containers..." -ForegroundColor Yellow

# Create deploymentpackage container for function deployment
az storage container create `
    --name "deploymentpackage" `
    --account-name $storageAccountName `
    --auth-mode login `
    --only-show-errors

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ deploymentpackage container created" -ForegroundColor Green
} else {
    Write-Host "⚠️  Warning: Failed to create deploymentpackage container (may already exist)" -ForegroundColor Yellow
}

# Create vm-metrics-output container for storing metrics
az storage container create `
    --name "vm-metrics-output" `
    --account-name $storageAccountName `
    --auth-mode login `
    --only-show-errors

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ vm-metrics-output container created" -ForegroundColor Green
} else {
    Write-Host "⚠️  Warning: Failed to create vm-metrics-output container (may already exist)" -ForegroundColor Yellow
}

# Assign subscription-level roles to function app managed identity
Write-Host ""
Write-Host "Assigning subscription-level roles to function app..." -ForegroundColor Yellow
$principalId = az functionapp identity show --name $functionAppName --resource-group $ResourceGroup --query principalId -o tsv
$subscriptionId = az account show --query id -o tsv

# Assign Reader role
az role assignment create `
    --assignee $principalId `
    --role "Reader" `
    --scope "/subscriptions/$subscriptionId" `
    --only-show-errors 2>$null

# Assign Monitoring Reader role
az role assignment create `
    --assignee $principalId `
    --role "Monitoring Reader" `
    --scope "/subscriptions/$subscriptionId" `
    --only-show-errors 2>$null

Write-Host "✅ Role assignments complete (Reader, Monitoring Reader)" -ForegroundColor Green

Write-Host ""
Write-Host "=== Deployment Information ===" -ForegroundColor Cyan
Write-Host "Function App Name:    $functionAppName" -ForegroundColor White
Write-Host "Function App URL:     $functionAppUrl" -ForegroundColor White
Write-Host "Storage Account:      $storageAccountName" -ForegroundColor White
Write-Host "Resource Group:       $ResourceGroup" -ForegroundColor White
Write-Host ""
Write-Host "Function Endpoints:" -ForegroundColor Cyan
Write-Host "  VM Metrics: $($outputs.functionEndpoints.value.vmMetrics)" -ForegroundColor White
Write-Host "  VMs Only:   $($outputs.functionEndpoints.value.vmsOnly)" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Wait ~2 minutes for function app to fully provision" -ForegroundColor White
Write-Host "  2. Deploy function code:" -ForegroundColor White
Write-Host "     cd ..\src" -ForegroundColor Cyan
Write-Host "     .\deploy-function-bicep.ps1" -ForegroundColor Cyan
Write-Host ""

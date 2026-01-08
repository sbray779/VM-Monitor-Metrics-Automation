#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Python functions to Azure Function App (Flex Consumption).

.DESCRIPTION
    Packages and deploys Python function code to the Flex Consumption function app.
    Uses zip deployment with remote build (Oryx) for proper Python dependency installation.

.EXAMPLE
    .\deploy-function-bicep.ps1
    Deploys functions using outputs from the Bicep deployment.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "vm-metrics-rg"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Azure Function Code Deployment (Flex Consumption) ===" -ForegroundColor Cyan
Write-Host ""

# Get the most recent deployment outputs
Write-Host "Retrieving deployment information..." -ForegroundColor Yellow
$latestDeployment = az deployment group list `
    --resource-group $ResourceGroup `
    --query "[?starts_with(name, 'vm-metrics')].name | [0]" -o tsv

if (-not $latestDeployment) {
    Write-Error "No deployment found. Please run deploy-bicep.ps1 first."
    exit 1
}

$outputs = az deployment group show `
    --name $latestDeployment `
    --resource-group $ResourceGroup `
    --query "properties.outputs" -o json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$storageAccountName = $outputs.storageAccountName.value

Write-Host "Function App: $functionAppName" -ForegroundColor Green
Write-Host "Storage Account: $storageAccountName" -ForegroundColor Green
Write-Host ""

# Package function code
Write-Host "Packaging function code..." -ForegroundColor Yellow
$zipFile = Join-Path $PSScriptRoot "function.zip"

if (Test-Path $zipFile) {
    Remove-Item $zipFile -Force
}

# Create zip with function files
$filesToZip = @(
    (Join-Path $PSScriptRoot "function_app.py"),
    (Join-Path $PSScriptRoot "get_vms.py"),
    (Join-Path $PSScriptRoot "get_vm_metrics.py"),
    (Join-Path $PSScriptRoot "host.json"),
    (Join-Path $PSScriptRoot "requirements.txt")
)

Write-Host "Adding files to package:" -ForegroundColor Cyan
foreach ($file in $filesToZip) {
    if (Test-Path $file) {
        Write-Host "  + $(Split-Path $file -Leaf)" -ForegroundColor White
    } else {
        Write-Warning "  ! $(Split-Path $file -Leaf) not found"
    }
}

Compress-Archive -Path $filesToZip -DestinationPath $zipFile -Force
Write-Host "Package created: $zipFile ($('{0:N2}' -f ((Get-Item $zipFile).Length / 1KB)) KB)" -ForegroundColor Green
Write-Host ""

# Deploy using zip deployment with remote build
Write-Host "Deploying to Azure Function App..." -ForegroundColor Yellow
Write-Host "This will trigger remote build (Oryx) to install Python dependencies" -ForegroundColor Cyan
Write-Host ""

az functionapp deployment source config-zip `
    --resource-group $ResourceGroup `
    --name $functionAppName `
    --src $zipFile `
    --build-remote true `
    --verbose

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    exit 1
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""

# Wait a moment for deployment to settle
Write-Host "Waiting for deployment to settle..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verify functions are available
Write-Host "Verifying function deployment..." -ForegroundColor Yellow
$functions = az functionapp function list `
    --resource-group $ResourceGroup `
    --name $functionAppName `
    --query "[].name" -o json | ConvertFrom-Json

if ($functions.Count -gt 0) {
    Write-Host "✓ Functions deployed successfully:" -ForegroundColor Green
    foreach ($func in $functions) {
        Write-Host "  - $func" -ForegroundColor White
    }
} else {
    Write-Warning "No functions found yet. This may take a minute to appear."
}

Write-Host ""
Write-Host "Function Endpoints:" -ForegroundColor Cyan
Write-Host "  VM Metrics: $($outputs.functionEndpoints.value.vmMetrics)" -ForegroundColor White
Write-Host "  VMs Only:   $($outputs.functionEndpoints.value.vmsOnly)" -ForegroundColor White
Write-Host ""

Write-Host "To test the function:" -ForegroundColor Yellow
Write-Host "  az functionapp function keys list --resource-group $ResourceGroup --name $functionAppName --function-name GetVMMetrics" -ForegroundColor Cyan
Write-Host '  curl "$($outputs.functionEndpoints.value.vmMetrics)?code=<function-key>"' -ForegroundColor Cyan
Write-Host ""

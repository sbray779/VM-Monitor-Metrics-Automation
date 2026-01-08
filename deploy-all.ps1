#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Complete deployment script for VM Metrics Function App.
.DESCRIPTION
    Deploys both infrastructure and function code in sequence.
    This is a convenience script that runs both deployment steps.
.EXAMPLE
    .\deploy-all.ps1
    Deploys infrastructure and function code to default resource group.
.EXAMPLE
    .\deploy-all.ps1 -ResourceGroup "my-rg" -Location "westus2"
    Deploys to custom resource group and location.
#>


param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "vm-metrics-rg",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "VM Metrics Function App - Complete Deployment" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Deploy Infrastructure
Write-Host "STEP 1: Deploying Infrastructure" -ForegroundColor Yellow
Write-Host "-----------------------------------------------------------" -ForegroundColor Yellow
& "$PSScriptRoot\infrastructure\deploy-bicep.ps1" -ResourceGroup $ResourceGroup -Location $Location

if ($LASTEXITCODE -ne 0) {
    Write-Error "Infrastructure deployment failed"
    exit 1
}

Write-Host ""
Write-Host "Waiting 30 seconds for function app to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 2: Deploy Function Code
Write-Host ""
Write-Host "STEP 2: Deploying Function Code" -ForegroundColor Yellow
Write-Host "-----------------------------------------------------------" -ForegroundColor Yellow
& "$PSScriptRoot\src\deploy-function-bicep.ps1" -ResourceGroup $ResourceGroup

if ($LASTEXITCODE -ne 0) {
    Write-Error "Function code deployment failed"
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "✅ DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Your VM Metrics Function App is ready to use!" -ForegroundColor White
Write-Host ""

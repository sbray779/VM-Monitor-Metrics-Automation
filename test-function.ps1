#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for VM Metrics Function App with multi-subscription support.

.DESCRIPTION
    This script tests the Azure Function App's ability to retrieve VM metrics
    across one or more Azure subscriptions.

.PARAMETER SubscriptionIds
    Comma-separated list of Azure subscription IDs (GUIDs).
    Example: "sub1-guid,sub2-guid,sub3-guid"

.PARAMETER ResourceGroup
    Optional resource group name to filter results.

.PARAMETER FunctionAppName
    Name of the Function App. If not provided, will attempt to retrieve from Bicep output.

.PARAMETER HoursBack
    Number of hours to look back for metrics (default: 24).

.PARAMETER Endpoint
    Which endpoint to test: 'vm-metrics' (default) or 'vms' (VMs only, no metrics).

.EXAMPLE
    .\test-function.ps1 -SubscriptionIds "c6361920-049e-417b-8d45-dd1c6d003b45"

.EXAMPLE
    .\test-function.ps1 -SubscriptionIds "sub1-guid,sub2-guid,sub3-guid" -HoursBack 12

.EXAMPLE
    .\test-function.ps1 -SubscriptionIds "sub1-guid" -ResourceGroup "my-rg" -Endpoint "vms"
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Comma-separated list of subscription IDs")]
    [string]$SubscriptionIds,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory=$false)]
    [int]$HoursBack = 24,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('vm-metrics', 'vms')]
    [string]$Endpoint = 'vm-metrics'
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "`n=== VM Metrics Function App Test ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Convert comma-separated string to array
$subscriptionArray = $SubscriptionIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

Write-Host "`nTest Parameters:" -ForegroundColor Yellow
Write-Host "  Subscription Count: $($subscriptionArray.Count)" -ForegroundColor White
Write-Host "  Subscription IDs:" -ForegroundColor White
foreach ($subId in $subscriptionArray) {
    Write-Host "    - $subId" -ForegroundColor Gray
}
if ($ResourceGroup) {
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
}
Write-Host "  Hours Back: $HoursBack" -ForegroundColor White
Write-Host "  Endpoint: $Endpoint" -ForegroundColor White

# Get Function App name if not provided
if (-not $FunctionAppName) {
    Write-Host "`nRetrieving Function App name from Azure..." -ForegroundColor Yellow
    
    # Try to find the function app in the vm-metrics-rg resource group
    try {
        $functionApps = az functionapp list --resource-group vm-metrics-rg --query "[].name" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $functionApps) {
            $FunctionAppName = $functionApps | Select-Object -First 1
            Write-Host "  Found: $FunctionAppName" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: No function apps found in resource group 'vm-metrics-rg'" -ForegroundColor Red
            Write-Host "  Please provide -FunctionAppName parameter or ensure the deployment is complete" -ForegroundColor Yellow
            exit 1
        }
    } catch {
        Write-Host "  ERROR: Failed to query function apps" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Please provide -FunctionAppName parameter" -ForegroundColor Yellow
        exit 1
    }
}

# Get Function App URL
Write-Host "`nRetrieving Function App URL..." -ForegroundColor Yellow
try {
    # Get the hostname from properties.defaultHostName
    $functionAppUrl = az functionapp show --name $FunctionAppName --resource-group vm-metrics-rg --query "properties.defaultHostName" -o tsv 2>&1
    
    if ([string]::IsNullOrWhiteSpace($functionAppUrl) -or $functionAppUrl -match "ERROR") {
        # Fallback to properties.hostNames[0]
        $functionAppUrl = az functionapp show --name $FunctionAppName --resource-group vm-metrics-rg --query "properties.hostNames[0]" -o tsv 2>&1
    }
    
    if ([string]::IsNullOrWhiteSpace($functionAppUrl) -or $functionAppUrl -match "ERROR") {
        throw "Could not retrieve hostname for function app '$FunctionAppName'"
    }
    
    $functionAppUrl = $functionAppUrl.Trim()
    Write-Host "  URL: https://$functionAppUrl" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to retrieve Function App URL" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Verify the function app is fully deployed" -ForegroundColor Gray
    Write-Host "  • Check: az functionapp show --name $FunctionAppName --resource-group vm-metrics-rg -o json" -ForegroundColor Gray
    exit 1
}

# Get Function Key
Write-Host "`nRetrieving Function Key..." -ForegroundColor Yellow
try {
    $functionKey = az functionapp keys list --name $FunctionAppName --resource-group vm-metrics-rg --query "functionKeys.default" -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get Function Key"
    }
    Write-Host "  Key retrieved successfully" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to retrieve Function Key" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Build request URL
$requestUrl = "https://$functionAppUrl/api/$Endpoint`?code=$functionKey"

# Build request body
$requestBody = @{
    subscription_ids = @($subscriptionArray)
    hours_back = $HoursBack
}

if ($ResourceGroup) {
    $requestBody.resource_group = $ResourceGroup
}

$requestBodyJson = $requestBody | ConvertTo-Json -Depth 10

Write-Host "`nRequest Details:" -ForegroundColor Yellow
Write-Host "  Endpoint: /api/$Endpoint" -ForegroundColor White
Write-Host "  Method: POST" -ForegroundColor White
Write-Host "  Body:" -ForegroundColor White
Write-Host $requestBodyJson -ForegroundColor Gray

# Make the request
Write-Host "`nSending request to Function App..." -ForegroundColor Yellow
$startTime = Get-Date

try {
    $response = Invoke-RestMethod -Uri $requestUrl -Method Post -Body $requestBodyJson -ContentType "application/json"
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Host "  ✅ Request completed successfully" -ForegroundColor Green
    Write-Host "  Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
    
    # Display response summary
    Write-Host "`n=== Response Summary ===" -ForegroundColor Cyan
    Write-Host "  Timestamp: $($response.timestamp)" -ForegroundColor White
    Write-Host "  VM Count: $($response.vm_count)" -ForegroundColor White
    Write-Host "  Subscriptions: $($response.subscription_ids.Count)" -ForegroundColor White
    
    if ($Endpoint -eq 'vm-metrics') {
        Write-Host "  Metrics Count: $($response.metrics.Count)" -ForegroundColor White
        Write-Host "  Hours Back: $($response.hours_back)" -ForegroundColor White
        
        # Check blob storage status
        if ($response.blob_storage) {
            Write-Host "`nBlob Storage:" -ForegroundColor Yellow
            if ($response.blob_storage.success) {
                Write-Host "  ✅ Status: Success" -ForegroundColor Green
                Write-Host "  Blob Name: $($response.blob_storage.blob_name)" -ForegroundColor White
                Write-Host "  Blob URL: $($response.blob_storage.blob_url)" -ForegroundColor Gray
            } else {
                Write-Host "  ❌ Status: Failed" -ForegroundColor Red
                Write-Host "  Error: $($response.blob_storage.error)" -ForegroundColor Red
            }
        }
    }
    
    # Display VMs by subscription
    if ($response.vms -and $response.vms.Count -gt 0) {
        Write-Host "`n=== VMs Found ===" -ForegroundColor Cyan
        $vmsBySubscription = $response.vms | Group-Object { $_.id -split '/' | Select-Object -Index 2 }
        
        foreach ($subGroup in $vmsBySubscription) {
            $subId = $subGroup.Name
            $vmCount = $subGroup.Count
            Write-Host "`nSubscription: $subId ($vmCount VMs)" -ForegroundColor Yellow
            
            foreach ($vm in $subGroup.Group) {
                Write-Host "  • $($vm.name)" -ForegroundColor White
                Write-Host "    Resource Group: $($vm.resource_group)" -ForegroundColor Gray
                Write-Host "    Location: $($vm.location)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "`n⚠️  No VMs found" -ForegroundColor Yellow
    }
    
    # Display metrics summary if available
    if ($Endpoint -eq 'vm-metrics' -and $response.metrics -and $response.metrics.Count -gt 0) {
        Write-Host "`n=== Metrics Summary ===" -ForegroundColor Cyan
        foreach ($vmMetrics in $response.metrics) {
            Write-Host "`nVM: $($vmMetrics.vm_name)" -ForegroundColor Yellow
            Write-Host "  Metrics Available: $($vmMetrics.metrics.Count)" -ForegroundColor White
            
            # Show sample metrics
            $sampleMetrics = $vmMetrics.metrics | Select-Object -First 3
            foreach ($metric in $sampleMetrics) {
                Write-Host "    • $($metric.name): $($metric.data_points) data points" -ForegroundColor Gray
            }
            
            if ($vmMetrics.metrics.Count -gt 3) {
                Write-Host "    ... and $($vmMetrics.metrics.Count - 3) more metrics" -ForegroundColor Gray
            }
        }
    }
    
    # Save full response to file
    $outputFile = "test-output-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $response | ConvertTo-Json -Depth 10 | Out-File $outputFile
    Write-Host "`n✅ Full response saved to: $outputFile" -ForegroundColor Green
    
    Write-Host "`n=== Test Completed Successfully ===" -ForegroundColor Green
    
} catch {
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Host "  ❌ Request failed" -ForegroundColor Red
    Write-Host "  Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
    
    Write-Host "`n=== Error Details ===" -ForegroundColor Red
    Write-Host "  Error Message: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.ErrorDetails.Message) {
        Write-Host "  Response:" -ForegroundColor Yellow
        try {
            $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
            Write-Host ($errorResponse | ConvertTo-Json -Depth 5) -ForegroundColor Red
        } catch {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
    }
    
    Write-Host "`n=== Test Failed ===" -ForegroundColor Red
    exit 1
}

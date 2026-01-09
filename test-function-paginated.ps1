<#
.SYNOPSIS
    Test the Azure Function VM metrics endpoint with pagination support.

.DESCRIPTION
    This script tests the deployed Azure Function that retrieves VM metrics across multiple subscriptions.
    It supports pagination for large VM sets by automatically following skip_token continuations.

.PARAMETER SubscriptionIds
    Comma-separated list of Azure subscription IDs (GUIDs) to query for VMs.

.PARAMETER ResourceGroup
    Optional. If provided, filters VMs to the specified resource group.

.PARAMETER HoursBack
    Number of hours to look back for metrics (default: 24).

.PARAMETER PageSize
    Number of VMs to retrieve per page (default: 100, max: 1000).

.PARAMETER MaxPages
    Maximum number of pages to retrieve (default: 10, unlimited: -1).

.PARAMETER Endpoint
    Function endpoint to test: "vm-metrics" or "vms" (default: "vm-metrics").

.EXAMPLE
    .\test-function-paginated.ps1 -SubscriptionIds "c6361920-049e-417b-8d45-dd1c6d003b45" -PageSize 50
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionIds,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = $null,
    
    [Parameter(Mandatory=$false)]
    [int]$HoursBack = 24,
    
    [Parameter(Mandatory=$false)]
    [int]$PageSize = 100,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxPages = 10,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("vm-metrics", "vms")]
    [string]$Endpoint = "vm-metrics"
)

# Parse comma-separated subscription IDs into array
$subscriptionArray = $SubscriptionIds -split ',' | ForEach-Object { $_.Trim() }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Azure Function VM Metrics Test (Paginated)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Subscription IDs: $($subscriptionArray -join ', ')" -ForegroundColor Yellow
Write-Host "Resource Group: $(if ($ResourceGroup) { $ResourceGroup } else { 'All' })" -ForegroundColor Yellow
Write-Host "Hours Back: $HoursBack" -ForegroundColor Yellow
Write-Host "Page Size: $PageSize" -ForegroundColor Yellow
Write-Host "Max Pages: $(if ($MaxPages -eq -1) { 'Unlimited' } else { $MaxPages })" -ForegroundColor Yellow
Write-Host "Endpoint: $Endpoint" -ForegroundColor Yellow
Write-Host ""

# Step 1: Discover Function App
Write-Host "Step 1: Discovering Function App in vm-metrics-rg..." -ForegroundColor Cyan

$functionAppsJson = az functionapp list --resource-group vm-metrics-rg --query "[].name" -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to list function apps in vm-metrics-rg" -ForegroundColor Red
    Write-Host $functionAppsJson -ForegroundColor Red
    exit 1
}

try {
    $functionAppsArray = $functionAppsJson | ConvertFrom-Json
    
    # ConvertFrom-Json unwraps single-element arrays, so ensure it's always an array
    if ($functionAppsArray -is [string]) {
        $functionAppsArray = @($functionAppsArray)
    }
    
    if ($functionAppsArray.Count -eq 0) {
        Write-Host "Error: No function apps found in vm-metrics-rg" -ForegroundColor Red
        Write-Host "Make sure you've deployed the infrastructure first." -ForegroundColor Yellow
        exit 1
    }
    
    $FunctionAppName = $functionAppsArray[0]
} catch {
    Write-Host "Error: Failed to parse function app list" -ForegroundColor Red
    Write-Host "Raw output: $functionAppsJson" -ForegroundColor Gray
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
Write-Host "Found Function App: $FunctionAppName" -ForegroundColor Green
Write-Host ""

# Step 2: Get Function URL
Write-Host "Step 2: Getting Function URL..." -ForegroundColor Cyan

$functionAppUrl = az functionapp show --name $FunctionAppName --resource-group vm-metrics-rg --query "properties.defaultHostName" -o tsv 2>&1

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionAppUrl)) {
    Write-Host "Warning: Failed to get URL from properties.defaultHostName" -ForegroundColor Yellow
    
    # Try alternative: properties.hostNames[0]
    $functionAppUrl = az functionapp show --name $FunctionAppName --resource-group vm-metrics-rg --query "properties.hostNames[0]" -o tsv 2>&1
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionAppUrl)) {
        Write-Host "Error: Could not retrieve function app hostname" -ForegroundColor Red
        Write-Host "Troubleshooting: Check if function app is running in Azure Portal" -ForegroundColor Yellow
        exit 1
    }
}

$functionAppUrl = "https://$functionAppUrl"
Write-Host "Function URL: $functionAppUrl" -ForegroundColor Green
Write-Host ""

# Step 3: Get Function Key
Write-Host "Step 3: Getting Function Key..." -ForegroundColor Cyan

$functionKey = az functionapp keys list --name $FunctionAppName --resource-group vm-metrics-rg --query "functionKeys.default" -o tsv 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to get function key" -ForegroundColor Red
    Write-Host $functionKey -ForegroundColor Red
    exit 1
}

Write-Host "Function Key retrieved successfully" -ForegroundColor Green
Write-Host ""

# Step 4: Call Function with Pagination
Write-Host "Step 4: Calling Function Endpoint (Paginated)..." -ForegroundColor Cyan
Write-Host "Endpoint: /api/$Endpoint" -ForegroundColor Yellow
Write-Host ""

$allVms = @()
$allMetrics = @()
$skipToken = $null
$pageNumber = 1
$totalVmCount = 0

do {
    Write-Host "------- Page $pageNumber -------" -ForegroundColor Magenta
    
    # Build request body
    $requestBody = @{
        subscription_ids = @($subscriptionArray)
        hours_back = $HoursBack
        page_size = $PageSize
    }
    
    if ($ResourceGroup) {
        $requestBody.resource_group = $ResourceGroup
    }
    
    if ($skipToken) {
        $requestBody.skip_token = $skipToken
        Write-Host "Using skip_token: $($skipToken.Substring(0, [Math]::Min(50, $skipToken.Length)))..." -ForegroundColor Gray
    }
    
    $requestBodyJson = $requestBody | ConvertTo-Json -Depth 10
    
    # Make the request
    $url = "$functionAppUrl/api/$Endpoint`?code=$functionKey"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Body $requestBodyJson -ContentType "application/json" -ErrorAction Stop
        
        # Display page summary
        Write-Host "Response received:" -ForegroundColor Green
        Write-Host "  Timestamp: $($response.timestamp)" -ForegroundColor White
        Write-Host "  VMs in page: $($response.vm_count)" -ForegroundColor White
        Write-Host "  Has more pages: $($response.has_more)" -ForegroundColor White
        
        # Accumulate results
        $allVms += $response.vms
        $totalVmCount += $response.vm_count
        
        if ($Endpoint -eq "vm-metrics" -and $response.metrics) {
            $allMetrics += $response.metrics
        }
        
        # Get next skip token
        $skipToken = $response.skip_token
        
        # Check if we should continue
        $pageNumber++
        
        if (-not $response.has_more) {
            Write-Host "No more pages available" -ForegroundColor Yellow
            break
        }
        
        if ($MaxPages -ne -1 -and $pageNumber -gt $MaxPages) {
            Write-Host "Reached maximum page limit ($MaxPages)" -ForegroundColor Yellow
            break
        }
        
        Write-Host ""
        
    } catch {
        Write-Host "Error calling function:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host $_.ErrorDetails.Message -ForegroundColor Red
        }
        exit 1
    }
    
} while ($skipToken)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Pagination Complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Total Pages Retrieved: $($pageNumber - 1)" -ForegroundColor White
Write-Host "Total VMs: $totalVmCount" -ForegroundColor White
Write-Host ""

# Display Results
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Results Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Group VMs by subscription
$vmsBySubscription = $allVms | Group-Object { $_.id -replace '^/subscriptions/([^/]+)/.*', '$1' }

Write-Host "VMs by Subscription:" -ForegroundColor Yellow
foreach ($group in $vmsBySubscription) {
    Write-Host "  Subscription: $($group.Name)" -ForegroundColor Cyan
    Write-Host "  VM Count: $($group.Count)" -ForegroundColor White
    
    foreach ($vm in $group.Group | Select-Object -First 5) {
        Write-Host "    - $($vm.name) ($($vm.resource_group))" -ForegroundColor Gray
    }
    
    if ($group.Count -gt 5) {
        Write-Host "    ... and $($group.Count - 5) more" -ForegroundColor Gray
    }
    
    Write-Host ""
}

if ($Endpoint -eq "vm-metrics") {
    Write-Host "Metrics Summary:" -ForegroundColor Yellow
    Write-Host "  Total VMs with metrics: $($allMetrics.Count)" -ForegroundColor White
    
    if ($allMetrics.Count -gt 0) {
        Write-Host ""
        Write-Host "  Sample Metrics (first VM):" -ForegroundColor Cyan
        $sampleMetric = $allMetrics[0]
        Write-Host "    VM: $($sampleMetric.vm_name)" -ForegroundColor White
        Write-Host "    Resource Group: $($sampleMetric.resource_group)" -ForegroundColor White
        
        if ($sampleMetric.metrics) {
            $metricNames = ($sampleMetric.metrics.PSObject.Properties.Name | Select-Object -First 3) -join ', '
            Write-Host "    Metrics: $metricNames" -ForegroundColor White
        }
    }
}

# Save full results to file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = "test-output-paginated-$timestamp.json"

$fullResults = @{
    test_timestamp = (Get-Date).ToString("o")
    total_pages = $pageNumber - 1
    total_vms = $totalVmCount
    subscription_ids = $subscriptionArray
    resource_group = if ($ResourceGroup) { $ResourceGroup } else { "all" }
    hours_back = $HoursBack
    page_size = $PageSize
    endpoint = $Endpoint
    vms = $allVms
}

if ($Endpoint -eq "vm-metrics") {
    $fullResults.metrics = $allMetrics
}

$fullResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Full response saved to: $outputFile" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan

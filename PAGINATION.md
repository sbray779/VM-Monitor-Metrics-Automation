# Pagination and Chunking Implementation

## Overview

The VM Monitor Metrics solution now supports **pagination** to handle large numbers of VMs efficiently. This allows you to:

- Query thousands of VMs without hitting timeout or memory limits
- Retrieve results in manageable chunks (pages)
- Continue from where you left off using skip tokens
- Process VMs in batches for better performance

## Key Features

### 1. **Resource Graph Pagination**
Azure Resource Graph queries now support pagination with configurable page sizes:
- Default page size: **100 VMs**
- Maximum page size: **1000 VMs** (Azure limit)
- Automatic skip token handling for continuation

### 2. **Batch Processing**
VM metrics are retrieved in batches with progress tracking:
- Default batch size: **10 VMs**
- Progress logging every batch
- Error handling per VM (failed VMs don't block others)

### 3. **Continuation Tokens**
Each response includes pagination metadata:
```json
{
  "has_more": true,
  "skip_token": "eyJ...",
  "page_size": 100,
  "vm_count": 100
}
```

## API Changes

### Request Parameters

Both endpoints (`/api/vm-metrics` and `/api/vms`) now accept:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `subscription_ids` | array/string | Yes | - | Array of subscription GUIDs or comma-separated string |
| `resource_group` | string | No | null | Filter VMs to specific resource group |
| `hours_back` | integer | No | 24 | Hours to look back for metrics (vm-metrics only) |
| `page_size` | integer | No | 100 | Number of VMs per page (max: 1000) |
| `skip_token` | string | No | null | Continuation token from previous response |

### Response Structure

```json
{
  "timestamp": "2026-01-08T12:00:00.000000",
  "vm_count": 100,
  "subscription_ids": ["sub-guid-1", "sub-guid-2"],
  "resource_group": "all",
  "hours_back": 24,
  "page_size": 100,
  "has_more": true,
  "skip_token": "eyJAb3NraXBUb2tlbiI6...",
  "vms": [...],
  "metrics": [...]
}
```

## Usage Examples

### Example 1: Basic Pagination

```powershell
# Get first page (100 VMs)
$body = @{
    subscription_ids = @("sub-guid-1")
    page_size = 100
} | ConvertTo-Json

$response1 = Invoke-RestMethod -Uri "$url/api/vms?code=$key" `
    -Method Post -Body $body -ContentType "application/json"

# Get second page using skip_token
$body = @{
    subscription_ids = @("sub-guid-1")
    page_size = 100
    skip_token = $response1.skip_token
} | ConvertTo-Json

$response2 = Invoke-RestMethod -Uri "$url/api/vms?code=$key" `
    -Method Post -Body $body -ContentType "application/json"
```

### Example 2: Retrieve All Pages

```powershell
$allVms = @()
$skipToken = $null

do {
    $body = @{
        subscription_ids = @("sub-guid-1")
        page_size = 100
    }
    
    if ($skipToken) {
        $body.skip_token = $skipToken
    }
    
    $response = Invoke-RestMethod -Uri "$url/api/vms?code=$key" `
        -Method Post -Body ($body | ConvertTo-Json) `
        -ContentType "application/json"
    
    $allVms += $response.vms
    $skipToken = $response.skip_token
    
} while ($response.has_more)

Write-Host "Retrieved $($allVms.Count) total VMs"
```

### Example 3: Using the Paginated Test Script

The solution includes a test script that handles pagination automatically:

```powershell
# Retrieve up to 10 pages (1000 VMs) with 100 VMs per page
.\test-function-paginated.ps1 `
    -SubscriptionIds "sub-guid-1,sub-guid-2" `
    -PageSize 100 `
    -MaxPages 10

# Retrieve all pages (unlimited)
.\test-function-paginated.ps1 `
    -SubscriptionIds "sub-guid-1" `
    -PageSize 200 `
    -MaxPages -1

# Test with specific resource group
.\test-function-paginated.ps1 `
    -SubscriptionIds "sub-guid-1" `
    -ResourceGroup "my-vms-rg" `
    -PageSize 50
```

## Performance Characteristics

### Throughput

With pagination, the solution can handle:

| Scenario | VMs per Request | Estimated Time | Memory Usage |
|----------|----------------|----------------|--------------|
| **Single Page** | 100 VMs | ~2-3 minutes | Low (~200 MB) |
| **5 Pages** | 500 VMs | ~10-15 minutes | Medium (~500 MB) |
| **10 Pages** | 1000 VMs | ~20-30 minutes | High (~1 GB) |
| **20 Pages** | 2000 VMs | ~40-60 minutes | Very High (~2 GB) |

**Note:** Times are estimates for `vm-metrics` endpoint (includes metrics retrieval). The `vms` endpoint is much faster (seconds per page).

### Optimization Tips

1. **Use Smaller Page Sizes for Metrics**
   - For `/api/vm-metrics`: Use `page_size=50-100` to avoid timeout
   - For `/api/vms`: Can use larger sizes up to `page_size=1000`

2. **Filter by Resource Group**
   - Significantly reduces query scope
   - Faster execution and lower memory usage

3. **Adjust Hours Back**
   - Lower `hours_back` values = less data = faster queries
   - Default is 24 hours; consider 1-4 hours for large VM sets

4. **Multi-Subscription Strategy**
   - For 10+ subscriptions with many VMs, consider:
     - Multiple smaller requests (fewer subscriptions per request)
     - Filtering by resource group per subscription
     - Running requests in parallel (if retrieving to local system)

## Timeout Considerations

Azure Functions have timeout limits:
- **Default timeout:** 10 minutes
- **Maximum timeout (FC1):** 60 minutes (requires configuration)

**Recommendations:**
- Stay under 500 VMs per request for metrics to avoid timeout
- Use unlimited VMs for `vms` endpoint (discovery only, no metrics)
- For large VM sets, make multiple paginated requests

## Error Handling

The implementation includes robust error handling:

1. **Per-VM Error Handling**
   - Failed VMs don't block the entire request
   - Errors included in response with details:
   ```json
   {
     "vm_name": "failed-vm",
     "error": "Error message here"
   }
   ```

2. **Progress Tracking**
   - Console logs show progress every batch
   - Helps identify which VMs cause slowdowns

3. **Graceful Degradation**
   - If one VM fails, others still process
   - Partial results returned with error details

## Migration Guide

### From Non-Paginated to Paginated

**Old Code (Single Request):**
```powershell
$response = Invoke-RestMethod -Uri $url -Method Post -Body $body
$allVms = $response.vms
```

**New Code (Paginated):**
```powershell
$allVms = @()
$skipToken = $null

do {
    if ($skipToken) { $body.skip_token = $skipToken }
    $response = Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json)
    $allVms += $response.vms
    $skipToken = $response.skip_token
} while ($response.has_more)
```

### Backward Compatibility

The pagination parameters are **optional**:
- Omitting `page_size` defaults to 100 VMs
- Omitting `skip_token` starts from the first page
- Existing code continues to work (gets first 100 VMs)

## Architecture Changes

### Updated Components

1. **get_vms.py**
   - `get_vms()` now returns `(vms, skip_token)` tuple
   - Accepts `page_size` and `skip_token` parameters
   - Uses Azure Resource Graph pagination API

2. **get_vm_metrics.py**
   - `get_metrics_for_vm_list()` now accepts `batch_size` parameter
   - Progress tracking every N VMs
   - Better error handling per VM

3. **function_app.py**
   - Both endpoints support pagination parameters
   - Response includes `has_more` and `skip_token`
   - Backward compatible with existing clients

## Testing

### Test Scripts

Two test scripts are provided:

1. **test-function.ps1** (Original)
   - Single request, no pagination
   - Good for small VM sets (<100)
   - Quick validation

2. **test-function-paginated.ps1** (New)
   - Handles multiple pages automatically
   - Configurable page size and max pages
   - Accumulates results across all pages
   - Detailed progress output

### Running Tests

```powershell
# Quick test (first page only)
.\test-function.ps1 -SubscriptionIds "sub-guid"

# Full paginated test
.\test-function-paginated.ps1 `
    -SubscriptionIds "sub-guid" `
    -PageSize 100 `
    -MaxPages 10 `
    -Endpoint "vms"
```

## Monitoring and Troubleshooting

### Check Function Logs

```bash
az functionapp logs tail \
  --name <function-app-name> \
  --resource-group vm-metrics-rg
```

### Common Issues

1. **Timeout on Large Requests**
   - **Solution:** Reduce `page_size` to 50-100
   - **Solution:** Lower `hours_back` for metrics

2. **High Memory Usage**
   - **Solution:** Use smaller page sizes
   - **Solution:** Process pages sequentially (don't accumulate all in memory)

3. **Slow Metrics Retrieval**
   - **Expected:** 1-2 seconds per VM for metrics
   - **Solution:** Use `vms` endpoint for discovery only if metrics not needed

## Future Enhancements

Potential improvements for future versions:

1. **Parallel Metrics Retrieval**
   - Process multiple VMs concurrently
   - Reduce overall execution time

2. **Streaming Response**
   - Return VMs as they're processed
   - Avoid accumulating all in memory

3. **Intelligent Batching**
   - Adjust batch size based on VM complexity
   - Optimize for different metric types

4. **Caching Layer**
   - Cache VM discovery results
   - Reduce Resource Graph queries

## References

- [Azure Resource Graph Pagination](https://learn.microsoft.com/en-us/azure/governance/resource-graph/concepts/work-with-data#paging-results)
- [Azure Functions Performance](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Azure Monitor Metrics API](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-overview)

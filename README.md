# VM Monitor Metrics Automation

This project automates the retrieval of Azure Virtual Machines and their performance metrics using Azure Resource Graph and Azure Monitor APIs.

**Now available as an Azure Function for easy integration with Logic Apps and other services!**

## Features

- **Multi-Subscription Support**: Query VMs across multiple Azure subscriptions simultaneously
- **Pagination**: Handle unlimited VMs with automatic pagination support (configurable page sizes)
- **VM Discovery**: Retrieve all VMs using Azure Resource Graph with filtering by resource group
- **Performance Metrics**: Query Azure Monitor for CPU, memory, network, and disk metrics
- **Flexible Querying**: Support for custom time ranges and metric aggregations
- **Data Export**: Save VM lists and metrics to JSON files and Azure Blob Storage
- **Azure Function**: HTTP-triggered functions for integration with Logic Apps, Power Automate, and other services
- **Batch Processing**: Process large VM sets efficiently with progress tracking

## Deployment Options

### Option 1: Azure Function (Recommended for Production)
Deploy as an HTTP-triggered Azure Function on **Flex Consumption (FC1)** plan for integration with Logic Apps and other services.

📖 **[See DEPLOYMENT-SUMMARY.md for complete deployment guide](../DEPLOYMENT-SUMMARY.md)**

**Quick Deploy (All-in-One):**
```bash
# Deploy both infrastructure and function code
.\deploy-all.ps1
```

**Manual Deploy (Step-by-Step):**
```bash
# Step 1: Deploy infrastructure
cd infrastructure
.\deploy-bicep.ps1

# Step 2: Deploy function code
cd ..\src
.\deploy-function-bicep.ps1
```

**Infrastructure Details:**
- **Plan**: Flex Consumption (FC1) - pay only for execution time
- **Runtime**: Python 3.11
- **Memory**: 2048MB (configurable: 512MB, 2048MB, 4096MB)
- **Max Instances**: 100 (configurable: 40-1000)
- **Authentication**: Managed Identity with Azure AD
- **Deployment**: Remote build (Oryx)
- **Storage**: Metrics written to blob storage for persistence
- **Pagination**: Supports unlimited VMs with automatic pagination

### Option 2: Standalone Python Script
Run locally or on a VM for ad-hoc metrics collection.

See instructions below for local setup.

## Azure Function Usage

### Endpoints

The deployed Azure Function provides two HTTP endpoints:

#### 1. `/api/vm-metrics` - Full VM Metrics Retrieval
Retrieves VMs and their performance metrics, then writes results to blob storage.

**Request Parameters:**
- `subscription_ids` (array or comma-separated string): Azure subscription ID(s) to query
- `resource_group` (string, optional): Filter VMs to specific resource group
- `hours_back` (integer, optional): Hours to look back for metrics (default: 24)
- `page_size` (integer, optional): VMs per page (default: 100, max: 1000)
- `skip_token` (string, optional): Continuation token from previous page

**Example Request:**
```json
{
  "subscription_ids": ["guid-1", "guid-2"],
  "resource_group": "my-vms-rg",
  "hours_back": 1,
  "page_size": 50
}
```

**Example Response:**
```json
{
  "timestamp": "2026-01-09T12:00:00",
  "vm_count": 50,
  "subscription_ids": ["guid-1", "guid-2"],
  "page_size": 50,
  "has_more": true,
  "skip_token": "eyJAb3NraXBUb2tlbiI6...",
  "vms": [...],
  "metrics": [...],
  "blob_storage": {
    "blob_name": "vm-metrics-20260109-120000-50vms.json",
    "container": "vm-metrics-output"
  }
}
```

#### 2. `/api/vms` - VM Discovery Only
Retrieves VM list without metrics (much faster for large queries).

**Request Parameters:**
- `subscription_ids` (array or comma-separated string): Azure subscription ID(s) to query
- `resource_group` (string, optional): Filter VMs to specific resource group
- `page_size` (integer, optional): VMs per page (default: 100, max: 1000)
- `skip_token` (string, optional): Continuation token from previous page

**Example Request:**
```json
{
  "subscription_ids": ["guid-1", "guid-2"],
  "page_size": 200
}
```

### Pagination

Both endpoints support pagination to handle large VM sets:

1. **First Request**: Call with `page_size` (e.g., 100)
2. **Check `has_more`**: If true, more pages are available
3. **Next Request**: Include the `skip_token` from the previous response
4. **Repeat**: Continue until `has_more` is false

See [PAGINATION.md](PAGINATION.md) for detailed pagination documentation.

### Testing the Function

Use the included test script to validate deployment and test pagination:

```powershell
# Test with automatic pagination (all VMs)
.\test-function-paginated.ps1 -SubscriptionIds "your-sub-id"

# Test with specific page size and limit
.\test-function-paginated.ps1 `
    -SubscriptionIds "sub-1,sub-2" `
    -PageSize 100 `
    -MaxPages 5 `
    -Endpoint "vm-metrics"

# Test VMs only (faster, no metrics)
.\test-function-paginated.ps1 `
    -SubscriptionIds "your-sub-id" `
    -PageSize 500 `
    -MaxPages -1 `
    -Endpoint "vms"
```

**Test Script Parameters:**
- `-SubscriptionIds`: Comma-separated subscription GUIDs (required)
- `-ResourceGroup`: Filter to specific resource group (optional)
- `-HoursBack`: Hours to look back for metrics (default: 24)
- `-PageSize`: VMs per page (default: 100, max: 1000)
- `-MaxPages`: Maximum pages to retrieve (default: 10, unlimited: -1)
- `-Endpoint`: "vm-metrics" or "vms" (default: "vm-metrics")

### Capacity and Limits

| Scenario | VMs per Request | Estimated Time | Memory Usage |
|----------|----------------|----------------|--------------|
| **Discovery Only** | Unlimited | Seconds per page | Low |
| **With Metrics (small)** | 100 | 2-3 minutes | ~200 MB |
| **With Metrics (medium)** | 500 | 10-15 minutes | ~500 MB |
| **With Metrics (large)** | 1000+ | 20+ minutes | ~1 GB |

**Recommendations:**
- For discovery: Use `/api/vms` with large page sizes (500-1000)
- For metrics: Use `/api/vm-metrics` with smaller page sizes (50-100)
- For 1000+ VMs: Use pagination across multiple requests
- Consider filtering by resource group for targeted queries

## Prerequisites

- Azure subscription with VMs
- Appropriate Azure permissions:
  - Reader access to VMs
  - Monitoring Reader role for metrics access
- For deployment: Azure CLI installed and authenticated (`az login`)

## Metrics Collected

The Azure Function retrieves the following metrics for each VM:
- **CPU**: Percentage CPU
- **Memory**: Available Memory Bytes
- **Disk I/O**: 
  - Disk Read Bytes
  - Disk Write Bytes
  - Disk Read Operations/Sec
  - Disk Write Operations/Sec
- **Network**:
  - Network In Total
  - Network Out Total

Metrics are written to Azure Blob Storage in timestamped JSON files (e.g., `vm-metrics-20260109-120000-50vms.json`).

## Project Structure

```
VM-Monitor-Metrics-Automation/
├── infrastructure/              # Infrastructure as Code
│   ├── bicep/
│   │   ├── main.bicep          # Bicep infrastructure template
│   │   └── main.bicepparam     # Bicep parameters
│   └── deploy-bicep.ps1        # Infrastructure deployment script
├── src/                         # Function App source code
│   ├── function_app.py         # Azure Functions app definition (v2 model)
│   ├── get_vms.py              # VM retrieval with pagination
│   ├── get_vm_metrics.py       # Metrics retrieval with batch processing
│   ├── host.json               # Functions runtime configuration
│   ├── requirements.txt        # Python dependencies
│   └── deploy-function-bicep.ps1 # Function code deployment script
├── deploy-all.ps1              # Complete deployment (infrastructure + code)
├── test-function-paginated.ps1 # Test script with pagination support
├── PAGINATION.md               # Detailed pagination documentation
├── PAGINATION_CHANGES.md       # Pagination implementation summary
└── README.md                   # This file
```

**Key Directories:**
- **infrastructure/**: Contains all Bicep templates and infrastructure deployment scripts
- **src/**: Contains all Python function app source code and deployment scripts
- **Root**: Convenience scripts, test scripts, and configuration files

**Key Files:**
- **test-function-paginated.ps1**: Automated test script with pagination support
- **PAGINATION.md**: Complete documentation on pagination features and usage
- **PAGINATION_CHANGES.md**: Summary of pagination implementation changes

## Error Handling

The function includes error handling for common scenarios:
- Missing subscription ID
- Authentication failures
- No VMs found
- Metrics API errors (e.g., metric not available for VM)
- Per-VM error handling (failed VMs don't block entire request)
- Pagination errors and continuation token issues

Errors are logged to the console with descriptive messages.

## Additional Documentation

- **[PAGINATION.md](PAGINATION.md)** - Complete guide to pagination features, usage examples, and performance characteristics
- **[PAGINATION_CHANGES.md](PAGINATION_CHANGES.md)** - Summary of pagination implementation and changes
- **[DEPLOYMENT-SUMMARY.md](../DEPLOYMENT-SUMMARY.md)** - Complete deployment guide for Azure infrastructure

## License

MIT License

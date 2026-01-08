# VM Monitor Metrics Automation

This project automates the retrieval of Azure Virtual Machines and their performance metrics using Azure Resource Graph and Azure Monitor APIs.

**Now available as an Azure Function for easy integration with Logic Apps and other services!**

## Features

- **VM Discovery**: Retrieve all VMs in a subscription or specific resource group using Azure Resource Graph
- **Performance Metrics**: Query Azure Monitor for CPU, memory, and storage metrics
- **Flexible Querying**: Support for custom time ranges and metric aggregations
- **Data Export**: Save VM lists and metrics to JSON files for further analysis
- **Azure Function**: HTTP-triggered functions for integration with Logic Apps, Power Automate, and other services

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
- **Authentication**: Managed Identity with Azure AD
- **Deployment**: Remote build (Oryx)
- **Storage**: Metrics written to blob storage for persistence

### Option 2: Standalone Python Script
Run locally or on a VM for ad-hoc metrics collection.

See instructions below for local setup.

## Prerequisites

- Python 3.8 or higher
- Azure subscription with VMs
- Appropriate Azure permissions:
  - Reader access to VMs
  - Monitoring Reader role for metrics access

## Authentication

This project uses `DefaultAzureCredential` from Azure Identity, which supports multiple authentication methods in the following order:
1. Environment variables
2. Managed Identity
3. Azure CLI
4. Azure PowerShell
5. Interactive browser

For local development, ensure you're logged in via Azure CLI:
```bash
az login
```

## Installation

1. Clone this repository

2. Create and activate a virtual environment:
```bash
# Create virtual environment
python -m venv .venv

# Activate on Windows
.venv\Scripts\activate

# Activate on Linux/Mac
source .venv/bin/activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Create a `.env` file from the example:
```bash
cp .env.example .env
```

5. Edit `.env` and set your Azure subscription ID:
```
AZURE_SUBSCRIPTION_ID=your-subscription-id
```

Optionally, set a specific resource group:
```
AZURE_RESOURCE_GROUP=your-resource-group-name
```

## Usage

### Run the complete automation:
```bash
python main.py
```

This will:
1. Retrieve all VMs from your subscription (or resource group if specified)
2. Query Azure Monitor metrics for each VM
3. Display a summary of metrics
4. Save results to JSON files

### Run individual components:

**Get VMs only:**
```bash
python get_vms.py
```

**Get metrics for discovered VMs:**
```bash
python get_vm_metrics.py
```

## Metrics Collected

The following metrics are retrieved for each VM:
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

## Output Files

The script generates timestamped JSON files:
- `vm_list_YYYYMMDD_HHMMSS.json`: List of discovered VMs
- `vm_metrics_YYYYMMDD_HHMMSS.json`: Complete metrics data for all VMs

## Configuration

Additional environment variables (optional):
- `METRICS_HOURS_BACK`: Number of hours to look back for metrics (default: 24)

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
│   ├── get_vms.py              # GetVMsOnly function - VM retrieval
│   ├── get_vm_metrics.py       # GetVMMetrics function - VM + metrics
│   ├── host.json               # Functions runtime configuration
│   ├── requirements.txt        # Python dependencies
│   └── deploy-function-bicep.ps1 # Function code deployment script
├── deploy-all.ps1              # Complete deployment (infrastructure + code)
├── main.py                     # Local development script
├── .env.example                # Environment variables template
└── README.md                   # This file
```

**Key Directories:**
- **infrastructure/**: Contains all Bicep templates and infrastructure deployment scripts
- **src/**: Contains all Python function app source code and deployment scripts
- **Root**: Convenience scripts and configuration files

## Error Handling

The scripts include error handling for common scenarios:
- Missing subscription ID
- Authentication failures
- No VMs found
- Metrics API errors (e.g., metric not available for VM)

Errors are logged to the console with descriptive messages.

## License

MIT License

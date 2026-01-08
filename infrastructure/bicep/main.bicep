@description('Azure region for all resources')
param location string = 'eastus'

@description('Prefix for the Function App name')
param functionAppPrefix string = 'vm-metrics-func'

@description('Python version for the Function App')
param pythonVersion string = '3.11'

@description('Default subscription ID to query VMs from (optional)')
param defaultSubscriptionId string = ''

@description('Default resource group to query VMs from (optional)')
param defaultResourceGroup string = ''

@description('Environment tag')
param environment string = 'Production'

@description('Object ID of the user/service principal that will deploy functions')
param deployerObjectId string

// Generate unique suffix
var suffix = uniqueString(resourceGroup().id)
var functionAppName = '${functionAppPrefix}-${suffix}'
var servicePlanName = '${functionAppPrefix}-plan-${suffix}'
var storageAccountName = 'vmmetrics${suffix}'
var logAnalyticsName = '${functionAppPrefix}-logs-${suffix}'
var appInsightsName = '${functionAppPrefix}-insights-${suffix}'

var tags = {
  Environment: environment
  ManagedBy: 'Bicep'
  Project: 'VM-Metrics-Automation'
}

// Storage Account (no shared access keys)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: 90
  }
}

// App Service Plan (Flex Consumption)
resource servicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: servicePlanName
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// Linux Function App (Flex Consumption)
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlan.id
    httpsOnly: true
    storageAccountRequired: false
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deploymentpackage'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: pythonVersion
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AZURE_SUBSCRIPTION_ID'
          value: !empty(defaultSubscriptionId) ? defaultSubscriptionId : subscription().subscriptionId
        }
        {
          name: 'AZURE_RESOURCE_GROUP'
          value: defaultResourceGroup
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
      ]
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Role Assignments - Storage Blob Data Contributor for Function App
resource functionAppStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignments - Storage Queue Data Contributor for Function App
resource functionAppStorageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignments - Storage Table Data Contributor for Function App
resource functionAppStorageTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Note: Subscription-level role assignments (Reader, Monitoring Reader) 
// must be assigned separately after deployment using Azure CLI or Portal

// Role Assignments - Storage Blob Data Contributor for Deployer
resource deployerStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, deployerObjectId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: deployerObjectId
    principalType: 'User'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output resourceGroupName string = resourceGroup().name
output functionAppPrincipalId string = functionApp.identity.principalId
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString
output functionEndpoints object = {
  vmMetrics: 'https://${functionApp.properties.defaultHostName}/api/vm-metrics'
  vmsOnly: 'https://${functionApp.properties.defaultHostName}/api/vms'
}

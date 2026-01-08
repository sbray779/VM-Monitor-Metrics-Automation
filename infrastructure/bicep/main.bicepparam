using './main.bicep'

param location = 'eastus'
param functionAppPrefix = 'vm-metrics-func'
param pythonVersion = '3.11'
param defaultSubscriptionId = ''
param defaultResourceGroup = ''
param environment = 'Production'
// Get deployer object ID: az ad signed-in-user show --query id -o tsv
param deployerObjectId = '45e161fa-5655-4de4-a49d-8921ba45be2d'

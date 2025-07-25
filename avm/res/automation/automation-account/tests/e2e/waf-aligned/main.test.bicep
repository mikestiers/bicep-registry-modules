targetScope = 'subscription'

metadata name = 'WAF-aligned'
metadata description = 'This instance deploys the module in alignment with the best-practices of the Azure Well-Architected Framework.'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'dep-${namePrefix}-automation.account-${serviceShort}-rg'

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'aawaf'

@description('Optional. A token to inject into the name of each resource.')
param namePrefix string = '#_namePrefix_#'

// Enforce location to avoid restrictions around creating high numbers of automation accounts in too many locations
#disable-next-line no-hardcoded-location
var enforcedLocation = 'westeurope'

// ============ //
// Dependencies //
// ============ //

// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: enforcedLocation
}

module nestedDependencies 'dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, enforcedLocation)}-nestedDependencies'
  params: {
    virtualNetworkName: 'dep-${namePrefix}-vnet-${serviceShort}'
    managedIdentityName: 'dep-${namePrefix}-msi-${serviceShort}'
    location: enforcedLocation
  }
}

// Diagnostics
// ===========
module diagnosticDependencies '../../../../../../../utilities/e2e-template-assets/templates/diagnostic.dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, enforcedLocation)}-diagnosticDependencies'
  params: {
    storageAccountName: 'dep${namePrefix}diasa${serviceShort}01'
    logAnalyticsWorkspaceName: 'dep-${namePrefix}-law-${serviceShort}'
    eventHubNamespaceEventHubName: 'dep-${namePrefix}-evh-${serviceShort}'
    eventHubNamespaceName: 'dep-${namePrefix}-evhns-${serviceShort}'
    location: enforcedLocation
  }
}

// ============== //
// Test Execution //
// ============== //

@batchSize(1)
module testDeployment '../../../main.bicep' = [
  for iteration in ['init', 'idem']: {
    scope: resourceGroup
    name: '${uniqueString(deployment().name, enforcedLocation)}-test-${serviceShort}-${iteration}'
    params: {
      name: '${namePrefix}${serviceShort}001'
      diagnosticSettings: [
        {
          eventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
          eventHubAuthorizationRuleResourceId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
          storageAccountResourceId: diagnosticDependencies.outputs.storageAccountResourceId
          workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
        }
      ]
      gallerySolutions: [
        {
          name: 'Updates(${last(split(diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId, '/'))})'
          plan: {
            product: 'OMSGallery/Updates'
          }
        }
      ]
      jobSchedules: [
        {
          runbookName: 'TestRunbook'
          scheduleName: 'TestSchedule'
        }
      ]
      disableLocalAuth: true
      linkedWorkspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
      lock: {
        kind: 'CanNotDelete'
        name: 'myCustomLockName'
      }
      modules: [
        {
          name: 'PSWindowsUpdate'
          uri: 'https://www.powershellgallery.com/api/v2/package'
          version: 'latest'
        }
      ]
      privateEndpoints: [
        {
          privateDnsZoneGroup: {
            privateDnsZoneGroupConfigs: [
              {
                privateDnsZoneResourceId: nestedDependencies.outputs.privateDNSZoneResourceId
              }
            ]
          }
          service: 'Webhook'
          subnetResourceId: nestedDependencies.outputs.subnetResourceId
          tags: {
            'hidden-title': 'This is visible in the resource name'
            Environment: 'Non-Prod'
            Role: 'DeploymentValidation'
          }
        }
        {
          privateDnsZoneGroup: {
            privateDnsZoneGroupConfigs: [
              {
                privateDnsZoneResourceId: nestedDependencies.outputs.privateDNSZoneResourceId
              }
            ]
          }
          service: 'DSCAndHybridWorker'
          subnetResourceId: nestedDependencies.outputs.subnetResourceId
          tags: {
            'hidden-title': 'This is visible in the resource name'
            Environment: 'Non-Prod'
            Role: 'DeploymentValidation'
          }
        }
      ]
      runbooks: [
        {
          description: 'Test runbook'
          name: 'TestRunbook'
          type: 'PowerShell'
          uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation/scripts/AzureAutomationTutorial.ps1'
          version: '1.0.0.0'
        }
      ]
      schedules: [
        {
          advancedSchedule: {}
          expiryTime: '9999-12-31T13:00'
          frequency: 'Hour'
          interval: 12
          name: 'TestSchedule'
          startTime: ''
          timeZone: 'Europe/Berlin'
        }
      ]

      managedIdentities: {
        systemAssigned: true
        userAssignedResourceIds: [
          nestedDependencies.outputs.managedIdentityResourceId
        ]
      }
      variables: [
        {
          description: 'TestStringDescription'
          name: 'TestString'
          value: '\'TestString\''
        }
        {
          description: 'TestIntegerDescription'
          name: 'TestInteger'
          value: '500'
        }
        {
          description: 'TestBooleanDescription'
          name: 'TestBoolean'
          value: 'false'
        }
        {
          description: 'TestDateTimeDescription'
          name: 'TestDateTime'
          value: '\'\\/Date(1637934042656)\\/\''
        }
        {
          description: 'TestEncryptedDescription'
          name: 'TestEncryptedVariable'
          value: '\'TestEncryptedValue\''
        }
      ]
      tags: {
        'hidden-title': 'This is visible in the resource name'
        Environment: 'Non-Prod'
        Role: 'DeploymentValidation'
      }
    }
  }
]

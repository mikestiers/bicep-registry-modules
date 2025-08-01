@description('Optional. The location to deploy resources to.')
param location string = resourceGroup().location

@description('Required. The name of the Virtual Network to create.')
param virtualNetworkName string

@description('Required. The name of the Managed Identity to create.')
param managedIdentityName string

@description('Required. The name of the Kubelet Identity Managed Identity to create.')
param managedIdentityKubeletIdentityName string

@description('Required. The name of the Disk Encryption Set to create.')
param diskEncryptionSetName string

@description('Required. The name of the Key Vault to create.')
param keyVaultName string

@description('Required. The name of the Proximity Placement Group to create.')
param proximityPlacementGroupName string

@description('Required. The name of the DNS Zone to create.')
param dnsZoneName string

@description('Required. The name of the log analytics workspace to create.')
param logAnalyticsWorkspaceName string

@description('Optional. The names of the Public IP addresses to create for load balancer outbound configuration.')
param publicIPNames array = [
  'pip-outbound-01'
  'pip-outbound-02'
]

var addressPrefix = '10.1.0.0/22'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: map(range(0, 3), i => {
      name: 'subnet-${i}'
      properties: {
        addressPrefix: cidrSubnet(addressPrefix, 24, i)
      }
    })
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-11-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enablePurgeProtection: true // Required for encryption to work
    softDeleteRetentionInDays: 7
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enabledForDeployment: true
    enableRbacAuthorization: true
    accessPolicies: []
  }

  resource key 'keys@2022-07-01' = {
    name: 'encryptionKey'
    properties: {
      kty: 'RSA'
    }
  }
}

resource keyPermissionsKeyVaultCryptoServiceEncryptionUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('msi-${keyVault.id}-${location}-${managedIdentity.id}-KeyVault-Crypto-Service-Encryption-User-RoleAssignment')
  scope: keyVault
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'e147488a-f6f5-4113-8e2d-b22465e65bf6'
    ) // Key Vault Crypto Service Encryption User
    principalType: 'ServicePrincipal'
  }
}

resource diskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2022-07-02' = {
  name: diskEncryptionSetName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    activeKey: {
      sourceVault: {
        id: keyVault.id
      }
      keyUrl: keyVault::key.properties.keyUriWithVersion
    }
    encryptionType: 'EncryptionAtRestWithCustomerKey'
  }
  dependsOn: [
    keyPermissionsKeyVaultCryptoServiceEncryptionUser
  ]
}

resource proximityPlacementGroup 'Microsoft.Compute/proximityPlacementGroups@2022-03-01' = {
  name: proximityPlacementGroupName
  location: location
}

// Public IPs for load balancer outbound configuration
resource publicIPs 'Microsoft.Network/publicIPAddresses@2023-11-01' = [
  for (pipName, index) in publicIPNames: {
    name: pipName
    location: location
    sku: {
      name: 'Standard'
      tier: 'Regional'
    }
    properties: {
      publicIPAllocationMethod: 'Static'
      publicIPAddressVersion: 'IPv4'
    }
    zones: []
  }
]

@description('The resource ID of the created Virtual Network Subnet.')
output subnetResourceIds array = [
  virtualNetwork.properties.subnets[0].id
  virtualNetwork.properties.subnets[1].id
  virtualNetwork.properties.subnets[2].id
]

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: dnsZoneName
  location: 'global'
}

resource managedIdentityKubeletIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityKubeletIdentityName
  location: location
}

resource roleAssignmentKubeletIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('msi-${location}-${managedIdentityKubeletIdentity.id}-ManagedIdentityOperator-RoleAssignment')
  scope: managedIdentityKubeletIdentity
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'f1a07417-d97a-45cb-824c-7a7467783830'
    ) // Managed Identity Operator Role used for Kubelet identity.
    principalType: 'ServicePrincipal'
  }
}

@description('The principal ID of the created Managed Identity.')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The resource ID of the created Managed Identity.')
output managedIdentityResourceId string = managedIdentity.id

@description('The resource ID of the created Kubelet Identity Managed Identity.')
output managedIdentityKubeletIdentityResourceId string = managedIdentityKubeletIdentity.id

@description('The resource ID of the created Disk Encryption Set.')
output diskEncryptionSetResourceId string = diskEncryptionSet.id

@description('The resource ID of the created Proximity Placement Group.')
output proximityPlacementGroupResourceId string = proximityPlacementGroup.id

@description('The resource ID of the created DNS Zone.')
output dnsZoneResourceId string = dnsZone.id

@description('The resource ID of the created Log Analytics Workspace.')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('The resource IDs of the created Public IP addresses for load balancer outbound configuration.')
output publicIPResourceIds array = [for (pipName, index) in publicIPNames: publicIPs[index].id]

@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('Azure Firewall subnet resource ID')
param firewallSubnetId string

@description('Application Gateway subnet address prefix (source for rules)')
param appGatewaySubnetPrefix string

@description('Private Endpoint subnet address prefix (destination for rules)')
param privateEndpointSubnetPrefix string

// ─── Firewall Public IP ─────────────────────────────────────
resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${appName}-fw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ─── Firewall Policy ────────────────────────────────────────
// SNAT is forced on private-to-private traffic so return traffic
// always comes back through the firewall (symmetric routing).
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: '${appName}-fw-policy'
  location: location
  properties: {
    sku: {
      tier: 'Premium'
    }
    threatIntelMode: 'Alert'
    // IDPS — Premium-only feature for signature-based threat detection
    intrusionDetection: {
      mode: 'Alert'
      configuration: {
        signatureOverrides: []
        bypassTrafficSettings: []
      }
    }
    snat: {
      autoLearnPrivateRanges: 'Disabled'
      privateRanges: [
        '255.255.255.255/32'
      ]
    }
  }
}

// ─── Network Rule Collection ────────────────────────────────
// Allows HTTP/HTTPS from the AppGW subnet to the Web App private endpoint subnet
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'allow-appgw-to-webapp'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'allow-http-https'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              appGatewaySubnetPrefix
            ]
            destinationAddresses: [
              privateEndpointSubnetPrefix
            ]
            destinationPorts: [
              '80'
              '443'
            ]
          }
        ]
      }
    ]
  }
}

// ─── Azure Firewall ─────────────────────────────────────────
resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: '${appName}-fw'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: firewallSubnetId
          }
          publicIPAddress: {
            id: firewallPip.id
          }
        }
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
  ]
}

// ─── Outputs ────────────────────────────────────────────────
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallName string = firewall.name
output firewallPublicIp string = firewallPip.properties.ipAddress

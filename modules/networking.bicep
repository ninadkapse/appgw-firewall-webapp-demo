@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

var vnetName = '${appName}-vnet'
var vnetAddressPrefix = '10.0.0.0/16'

var appGwSubnetName = 'AppGatewaySubnet'
var appGwSubnetPrefix = '10.0.0.0/24'
var firewallSubnetName = 'AzureFirewallSubnet'
var firewallSubnetPrefix = '10.0.1.0/26'
var appServiceSubnetName = 'AppServiceSubnet'
var appServiceSubnetPrefix = '10.0.2.0/24'
var peSubnetName = 'PrivateEndpointSubnet'
var peSubnetPrefix = '10.0.3.0/24'

// ─── NSG for Application Gateway subnet ────────────────────
resource appGwNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${appName}-appgw-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-GatewayManager'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── NSG for Private Endpoint subnet ────────────────────────
resource peNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${appName}-pe-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-From-Firewall-Subnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourceAddressPrefix: firewallSubnetPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── Route Table for Application Gateway subnet ─────────────
// Actual route entry is added by the routes module after firewall deploys
resource appGwRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: '${appName}-appgw-rt'
  location: location
  properties: {
    disableBgpRoutePropagation: false
  }
}

// ─── Virtual Network ────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: appGwSubnetName
        properties: {
          addressPrefix: appGwSubnetPrefix
          networkSecurityGroup: { id: appGwNsg.id }
          routeTable: { id: appGwRouteTable.id }
        }
      }
      {
        name: firewallSubnetName
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
      {
        name: appServiceSubnetName
        properties: {
          addressPrefix: appServiceSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: { id: peNsg.id }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────
output vnetId string = vnet.id
output vnetName string = vnet.name
output appGatewaySubnetId string = vnet.properties.subnets[0].id
output firewallSubnetId string = vnet.properties.subnets[1].id
output appServiceSubnetId string = vnet.properties.subnets[2].id
output privateEndpointSubnetId string = vnet.properties.subnets[3].id
output appGatewaySubnetPrefix string = appGwSubnetPrefix
output privateEndpointSubnetPrefix string = peSubnetPrefix
output appGwRouteTableName string = appGwRouteTable.name

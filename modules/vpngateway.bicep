@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('Gateway subnet resource ID (must be named GatewaySubnet)')
param gatewaySubnetId string

@description('VPN client address pool CIDR for P2S connections')
param vpnAddressPool string = '172.16.0.0/24'

@description('Base64-encoded root certificate public key data (no PEM headers)')
@secure()
param vpnRootCertData string

// ─── VPN Gateway Public IP ──────────────────────────────────
resource vpnGwPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${appName}-vpngw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ─── VPN Gateway (P2S with OpenVPN + Certificate Auth) ──────
// Enables Point-to-Site VPN so remote users can connect to the
// VNet and access the App Gateway private frontend.
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-11-01' = {
  name: '${appName}-vpngw'
  location: location
  properties: {
    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    ipConfigurations: [
      {
        name: 'vpnGwIpConfig'
        properties: {
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: vpnGwPip.id
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          vpnAddressPool
        ]
      }
      vpnClientProtocols: [
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        'Certificate'
      ]
      vpnClientRootCertificates: [
        {
          name: 'DemoVPNRootCA'
          properties: {
            publicCertData: vpnRootCertData
          }
        }
      ]
    }
  }
}

// ─── Outputs ────────────────────────────────────────────────
output vpnGatewayId string = vpnGateway.id
output vpnGatewayPublicIp string = vpnGwPip.properties.ipAddress
output vpnGatewayName string = vpnGateway.name

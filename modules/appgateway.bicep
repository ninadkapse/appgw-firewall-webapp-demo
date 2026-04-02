@description('Location for all resources')
param location string

@description('Application name prefix')
param appName string

@description('Application Gateway subnet resource ID')
param appGatewaySubnetId string

@description('Backend FQDN — Web App default hostname (resolved via private DNS)')
param backendFqdn string

@description('WAF mode')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

@description('Enable geo-filtering WAF custom rules (blocks traffic from non-allowed countries)')
param enableGeoFiltering bool = true

@description('Country codes allowed through geo-filter (ISO 3166-1 alpha-2). Traffic from other countries is blocked.')
param allowedCountryCodes array = [
  'US'
]

@description('VPN client address pool CIDR — added to WAF allow list so VPN users bypass geo-filter while managed rules still apply')
param vpnAddressPool string = '172.16.0.0/24'

@description('Static private IP for the App Gateway private frontend (must be in AppGateway subnet)')
param appGatewayPrivateIp string = '10.0.0.100'

var appGwName = '${appName}-appgw'

// ─── Application Gateway Public IP ──────────────────────────
resource appGwPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${appName}-appgw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ─── WAF Policy (OWASP 3.2, Prevention mode) ───────────────
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-11-01' = {
  name: '${appName}-waf-policy'
  location: location
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: wafMode
    }
    // ─── Custom Rules: Geofencing + VPN Access ─────────────────
    // Single compound rule: Block if (NOT from allowed country) AND (NOT from VPN/internal).
    // VPN traffic doesn't match → falls through to managed rules (OWASP, Bot) for full protection.
    // This avoids the "Allow" action which skips managed rule evaluation.
    customRules: enableGeoFiltering ? [
      {
        name: 'GeoBlockExcludeVpn'
        priority: 10
        ruleType: 'MatchRule'
        action: 'Block'
        state: 'Enabled'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'GeoMatch'
            negationConditon: true
            matchValues: allowedCountryCodes
          }
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'IPMatch'
            negationConditon: true
            matchValues: [
              vpnAddressPool
              '10.0.0.0/8'
            ]
          }
        ]
      }
    ] : []
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
  }
}

// ─── Application Gateway (WAF_v2) ──────────────────────────
resource appGw 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: appGwName
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 3
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendIp'
        properties: {
          publicIPAddress: {
            id: appGwPip.id
          }
        }
      }
      {
        name: 'appGwPrivateFrontendIp'
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: appGatewayPrivateIp
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'webAppBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: backendFqdn
            }
          ]
        }
      }
    ]
    // Backend talks HTTPS to the Web App; pickHostNameFromBackendAddress
    // ensures the Host header matches the Web App's expected hostname.
    backendHttpSettingsCollection: [
      {
        name: 'webAppHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/probes',
              appGwName,
              'webAppHealthProbe'
            )
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              appGwName,
              'appGwFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              appGwName,
              'port_80'
            )
          }
          protocol: 'Http'
        }
      }
      {
        name: 'privateHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              appGwName,
              'appGwPrivateFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              appGwName,
              'port_80'
            )
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'httpRoutingRule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              appGwName,
              'httpListener'
            )
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              appGwName,
              'webAppBackendPool'
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              appGwName,
              'webAppHttpSettings'
            )
          }
        }
      }
      {
        name: 'privateHttpRoutingRule'
        properties: {
          priority: 200
          ruleType: 'Basic'
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              appGwName,
              'privateHttpListener'
            )
          }
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              appGwName,
              'webAppBackendPool'
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              appGwName,
              'webAppHttpSettings'
            )
          }
        }
      }
    ]
    probes: [
      {
        name: 'webAppHealthProbe'
        properties: {
          protocol: 'Https'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
  }
}

// ─── Outputs ────────────────────────────────────────────────
output appGatewayPublicIp string = appGwPip.properties.ipAddress
output appGatewayPrivateIp string = appGatewayPrivateIp
output appGatewayName string = appGw.name

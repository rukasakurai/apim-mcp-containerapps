@description('Name of the API Management instance')
param name string

@description('Location for the API Management instance')
param location string = resourceGroup().location

@description('Tags for the API Management instance')
param tags object = {}

@description('Publisher email for the API Management instance')
param publisherEmail string

@description('Publisher name for the API Management instance')
param publisherName string

@description('Display name for the MCP server')
param mcpServerDisplayName string

@description('Name (identifier) for the MCP server API')
param mcpServerName string

@description('Base path for the MCP server in APIM gateway')
param mcpServerBasePath string

@description('Description of the MCP server')
param mcpServerDescription string

@description('Backend MCP server base URL — the full URL to the MCP endpoint (e.g. https://learn.microsoft.com/api/mcp)')
param mcpServerBackendBaseUrl string

@description('MCP endpoint URI template on the backend (e.g. / when backend URL is the full MCP endpoint)')
param mcpServerEndpointUriTemplate string

// APIM instance (stable API version)
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Backend for the MCP server
resource mcpBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: '${mcpServerName}-backend'
  properties: {
    protocol: 'http'
    url: mcpServerBackendBaseUrl
  }
}

// MCP server API — requires preview API version for type:'mcp' and mcpProperties
// Note: backendId, mcpProperties, and type:'mcp' are not yet in the published Bicep type definitions.
// We use any() to bypass compile-time type checking for properties that are valid at runtime.
resource mcpApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: mcpServerName
  properties: union({
    displayName: mcpServerDisplayName
    description: mcpServerDescription
    path: mcpServerBasePath
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }, {
    type: 'mcp'
    backendId: mcpBackend.name
    mcpProperties: {
      endpoints: {
        mcp: {
          uriTemplate: mcpServerEndpointUriTemplate
        }
      }
    }
  })
}

output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output mcpServerUrl string = '${apim.properties.gatewayUrl}/${mcpServerBasePath}/mcp'

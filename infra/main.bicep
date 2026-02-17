targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

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

@description('Backend MCP server base URL')
param mcpServerBackendBaseUrl string

@description('MCP endpoint URI template on the backend')
param mcpServerEndpointUriTemplate string

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module apim 'apim.bicep' = {
  name: 'apim'
  scope: rg
  params: {
    name: '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    publisherEmail: publisherEmail
    publisherName: publisherName
    mcpServerDisplayName: mcpServerDisplayName
    mcpServerName: mcpServerName
    mcpServerBasePath: mcpServerBasePath
    mcpServerDescription: mcpServerDescription
    mcpServerBackendBaseUrl: mcpServerBackendBaseUrl
    mcpServerEndpointUriTemplate: mcpServerEndpointUriTemplate
  }
}

output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_APIM_NAME string = apim.outputs.name
output AZURE_APIM_GATEWAY_URL string = apim.outputs.gatewayUrl
output AZURE_MCP_SERVER_URL string = apim.outputs.mcpServerUrl

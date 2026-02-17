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

output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl

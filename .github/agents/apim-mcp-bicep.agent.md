# Exposing MCP Servers Through Azure API Management Using Bicep

This document captures hard-won lessons from implementing Infrastructure-as-Code for MCP (Model Context Protocol) server exposure through Azure API Management. It is intended for agents working on similar tasks.

## The Key Lesson: Don't Over-Research — Reverse-Engineer Instead

### What didn't work

The initial approach was to exhaustively research the problem before writing any code:
- Searched Bicep type registries, Azure REST API specs, the bicep-types-az GitHub repo
- Queried the Azure Resource Provider for `mcpServers` resource types
- Searched 475+ REST API operations for MCP-related endpoints
- Checked Azure Verified Modules

**Every single search came up empty.** MCP support in APIM is new enough that it's not in published schemas, type definitions, or public specs. An agent could spend hours in this research loop and make zero progress.

### What worked: Collaborative reverse-engineering

The human suggested a much more effective approach:

1. **Provision a bare APIM instance** using the existing Bicep (`azd provision`)
2. **Have the human manually create an MCP server** through the Azure portal, following the [official docs](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server)
3. **Agent examines what the portal created** via `az rest` calls against the ARM API with a preview API version
4. **Agent writes Bicep** based on the observed resource structure
5. **Agent deploys to a separate `azd` environment** to test the Bicep
6. **Compare** the Bicep-deployed resource against the portal-created one and iterate

This took about 20 minutes total vs. potentially hours of fruitless research. The approach works for any Azure feature that's ahead of its published schemas.

## Technical Findings

### MCP servers use standard resource types with new properties

The portal does **not** create a new `Microsoft.ApiManagement/service/mcpServers` resource type. Instead it creates:

1. **A backend** (`Microsoft.ApiManagement/service/backends`) — holds the MCP server's base URL
2. **An API** (`Microsoft.ApiManagement/service/apis`) — with MCP-specific properties:
   - `type: 'mcp'` (not `http`, `soap`, `graphql`, or `websocket`)
   - `mcpProperties.endpoints.mcp.uriTemplate` — the endpoint path on the backend
   - `backendId` — references the backend resource
   - `serviceUrl` is `null` (URL lives on the backend resource)
   - `subscriptionRequired: false` by default

### Preview API version required

- `type: 'mcp'`, `mcpProperties`, and `backendId` are **invisible** at API version `2024-05-01` (stable)
- They work at `2024-06-01-preview`, `2024-10-01-preview`, and `2025-03-01-preview`
- If you query the API with a stable version, you get `ResourceNotFound` — the MCP API simply doesn't exist from that version's perspective

### Bicep type checker workaround

The Bicep compiler doesn't have `backendId`, `mcpProperties`, or `type:'mcp'` in its type definitions (even for preview API versions). Direct usage causes compile errors like:

```
The property "mcpProperties" is not allowed on objects of type "ApiCreateOrUpdatePropertiesOrApiContractProperties"
```

**Solution:** Use `union()` to merge known properties with the untyped MCP-specific ones:

```bicep
resource mcpApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: mcpServerName
  properties: union({
    // Properties known to the Bicep type system
    displayName: mcpServerDisplayName
    description: mcpServerDescription
    path: mcpServerBasePath
    protocols: ['https']
    subscriptionRequired: false
  }, {
    // MCP-specific properties not yet in Bicep type definitions
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
```

This compiles cleanly and deploys correctly. The `union()` approach bypasses compile-time type checking while still producing valid ARM JSON.

### Backend resource structure

```bicep
resource mcpBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: '${mcpServerName}-backend'
  properties: {
    protocol: 'http'
    url: mcpServerBackendBaseUrl  // e.g. 'https://learn.microsoft.com'
  }
}
```

Note: `protocol` is `'http'` (this refers to the HTTP protocol for REST communication, not the URL scheme — the actual URL uses HTTPS).

## How to Examine Azure Resources Created by the Portal

When the portal creates resources that aren't in published schemas, use `az rest` with a preview API version:

```bash
# List APIs (including MCP type)
az rest --method GET \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/apis?api-version=2024-06-01-preview"

# Get backend details
az rest --method GET \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/backends?api-version=2024-06-01-preview"

# Get policies
az rest --method GET \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/apis/{api-name}/policies?api-version=2024-06-01-preview"
```

Try multiple API versions. The valid ones for APIM as of Feb 2026 include: `2024-05-01`, `2024-06-01-preview`, `2024-10-01-preview`, `2025-03-01-preview`.

## Testing Strategy

Use separate `azd` environments to test changes without affecting the manually-created reference:

- `manual` environment — human creates resources via portal (the reference)
- `bicep-test` environment — agent deploys Bicep (the test)

Then compare the two by querying both with `az rest` and diffing the output. This makes it safe to iterate without risk.

## Useful References

- [Expose and govern an existing MCP server](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server)
- [About MCP servers in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/mcp-server-overview)
- [Sample: remote-mcp-apim-functions-python](https://github.com/Azure-Samples/remote-mcp-apim-functions-python) (89% Bicep — good reference for larger APIM+MCP setups with OAuth)
- [Microsoft.ApiManagement/service/apis Bicep reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service/apis) (does NOT include MCP properties yet)

## When This Guidance May Become Outdated

Microsoft may eventually:
- Publish `mcpProperties` and `type:'mcp'` in the Bicep type definitions
- Release a stable (non-preview) API version that supports MCP
- Introduce a dedicated `mcpServers` sub-resource type

When any of these happen, the `union()` workaround may no longer be needed and the resource definitions can be simplified. Check whether the Bicep compiler accepts `type: 'mcp'` directly before applying the workaround.

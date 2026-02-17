# Expose MCP Servers Through Azure API Management Using Bicep

A sample project demonstrating how to expose [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers through [Azure API Management](https://learn.microsoft.com/azure/api-management/) using Bicep and the [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/).

> **Agent notes:** See [.github/agents/apim-mcp-bicep.agent.md](.github/agents/apim-mcp-bicep.agent.md) for detailed technical lessons on implementing MCP server exposure via Bicep, including the `union()` workaround, preview API version requirements, and a reverse-engineering workflow for undocumented Azure features.

## Overview

MCP enables LLMs and AI agents to discover and invoke tools exposed by backend servers. Azure API Management can act as a gateway in front of these MCP servers, providing governance, security, and observability.

This sample provisions an APIM **Standard V2** instance and configures it to expose an existing MCP server using the preview `type: 'mcp'` API definition and `mcpProperties`. For background, see [Expose and govern an existing MCP server](https://learn.microsoft.com/azure/api-management/expose-existing-mcp-server).

### Resources Created

| Resource                 | Description                                                      |
| ------------------------ | ---------------------------------------------------------------- |
| **Resource Group**       | Container for all deployed resources                             |
| **Azure API Management** | Standard V2 SKU instance                                         |
| **APIM Backend**         | Backend pointing to the MCP server base URL                      |
| **APIM MCP API**         | API of type `mcp` with `mcpProperties` exposing the MCP endpoint |

### Key Bicep Details

- The `Microsoft.ApiManagement/service/apis` resource uses the **`2024-06-01-preview`** API version, which supports `type: 'mcp'`, `backendId`, and `mcpProperties`.
- `union()` is used to combine standard API properties with MCP-specific properties that are not yet in the published Bicep type definitions.
- All resource names incorporate a `resourceToken` derived from `uniqueString()` to ensure uniqueness.

## Prerequisites

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- An Azure subscription with permissions to create API Management resources

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/rukasakurai/apim-mcp-bicep.git
   cd apim-mcp-bicep
   ```

2. **Log in to Azure**

   ```bash
   azd auth login
   ```

3. **Set MCP server configuration**

   Configure the MCP server details before provisioning. The example below points to the Microsoft Learn MCP server:

   ```bash
   azd env set AZURE_MCP_SERVER_DISPLAY_NAME "Microsoft Learn MCP Server"
   azd env set AZURE_MCP_SERVER_NAME "microsoft-learn-mcp-server"
   azd env set AZURE_MCP_SERVER_BASE_PATH "mslearn"
   azd env set AZURE_MCP_SERVER_DESCRIPTION "Microsoft Learn MCP server exposed through APIM"
   azd env set AZURE_MCP_SERVER_BACKEND_BASE_URL "https://learn.microsoft.com"
   azd env set AZURE_MCP_SERVER_ENDPOINT_URI_TEMPLATE "/api/mcp"
   ```

   To expose a different MCP server, replace the values above with your own server's URL and endpoint.

4. **Provision the infrastructure**

   ```bash
   azd provision
   ```

   You will be prompted for:
   - **Environment name** – used to name the resource group and resources
   - **Azure location** – region for deployment (e.g., `japaneast`)
   - **Publisher email** – required by API Management
   - **Publisher name** – organization name shown in the developer portal

   After provisioning, the outputs include the APIM gateway URL and the full MCP server URL.

5. **Tear down resources when done**

   ```bash
   azd down --force --purge
   ```

## Project Structure

```
├── azure.yaml                 # azd project configuration
├── infra/
│   ├── main.bicep             # Main deployment (subscription scope)
│   ├── main.parameters.json   # Parameter definitions with azd variable substitution
│   ├── apim.bicep             # API Management module + MCP server config
│   └── abbreviations.json     # Resource naming abbreviations
├── docs/
│   ├── azure-coding-agent-guide.md  # Azure coding agent guidance
│   └── azure-oidc-setup.md          # OIDC setup instructions
├── tests/
│   └── test-mcp-endpoint.sh         # MCP endpoint integration test script
├── .github/
│   ├── agents/                # Copilot agent notes
│   └── workflows/
│       ├── apim-provision-test.yml   # CI workflow: lint, build, provision, test, teardown
│       └── azure-oidc-check.yml     # OIDC credential verification
└── README.md
```

## CI/CD

The **APIM Bicep Provision & Test** workflow (`.github/workflows/apim-provision-test.yml`) runs automatically on every push or pull request that modifies files in `infra/`, `azure.yaml`, or `tests/`:

- **Build & Lint** – validates Bicep files on every push and PR
- **Provision, Test & Teardown** – provisions infrastructure with `azd provision`, runs MCP endpoint integration tests against the deployed server, and tears down with `azd down` (requires Azure OIDC credentials configured as repository secrets/variables)

The integration test (`tests/test-mcp-endpoint.sh`) validates that the MCP server responds correctly by sending `initialize` and `tools/list` JSON-RPC requests and checking response structure. The test includes a readiness probe with retries to handle APIM startup time.

### Required Repository Configuration

| Name                    | Type     | Description                         |
| ----------------------- | -------- | ----------------------------------- |
| `AZURE_CLIENT_ID`       | Variable | App registration client ID for OIDC |
| `AZURE_TENANT_ID`       | Secret   | Microsoft Entra ID tenant ID        |
| `AZURE_SUBSCRIPTION_ID` | Secret   | Target Azure subscription ID        |

See [docs/azure-oidc-setup.md](docs/azure-oidc-setup.md) for OIDC setup instructions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

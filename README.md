# APIM MCP Container Apps

Azure API Management (Standard V2) infrastructure with MCP (Model Context Protocol) server exposure, deployed with Bicep and the Azure Developer CLI (`azd`).

## Architecture

This project provisions an Azure API Management instance using the **Standard V2** SKU and configures it to expose an existing MCP server, enabling LLMs and AI agents to securely access tools through the MCP protocol. See [Expose and govern an existing MCP server](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server) for background.

### Resources Created

| Resource | Description |
|----------|-------------|
| **Resource Group** | Container for all deployed resources |
| **Azure API Management** | Standard V2 SKU instance |
| **APIM Backend** | Backend pointing to the MCP server base URL |
| **APIM MCP API** | API of type `mcp` with `mcpProperties` exposing the MCP endpoint |

## Prerequisites

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- An Azure subscription with permissions to create API Management resources

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/rukasakurai/apim-mcp-containerapps.git
   cd apim-mcp-containerapps
   ```

2. **Log in to Azure**

   ```bash
   azd auth login
   ```

3. **Provision the infrastructure**

   ```bash
   azd provision
   ```

   You will be prompted for:
   - **Environment name** – used to name the resource group and resources
   - **Azure location** – region for deployment (e.g., `japaneast`)
   - **Publisher email** – required by API Management
   - **Publisher name** – organization name shown in the developer portal

   You also need to set the MCP server configuration:

   ```bash
   azd env set AZURE_MCP_SERVER_DISPLAY_NAME "Microsoft Learn MCP Server"
   azd env set AZURE_MCP_SERVER_NAME "microsoft-learn-mcp-server"
   azd env set AZURE_MCP_SERVER_BASE_PATH "mslearn"
   azd env set AZURE_MCP_SERVER_DESCRIPTION "Microsoft Learn MCP server exposed through APIM"
   azd env set AZURE_MCP_SERVER_BACKEND_BASE_URL "https://learn.microsoft.com"
   azd env set AZURE_MCP_SERVER_ENDPOINT_URI_TEMPLATE "/api/mcp"
   ```

4. **Tear down resources when done**

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
├── .github/
│   ├── agents/
│   │   ├── apim.agent.md           # Agent notes: APIM Bicep challenges
│   │   └── apim-mcp-bicep.agent.md # Agent notes: MCP server IaC approach
│   └── workflows/
│       └── apim-provision.yml # CI workflow: lint, build, provision, teardown
└── README.md
```

## CI/CD

The **APIM Bicep Provision** workflow (`.github/workflows/apim-provision.yml`) runs automatically on every push or pull request that modifies files in `infra/` or `azure.yaml`:

- **Build & Lint** – validates Bicep files on every push and PR
- **Provision & Teardown** – runs `azd provision` followed by `azd down` on pushes to `main` (requires Azure OIDC credentials configured as repository secrets/variables)

### Required Repository Configuration

| Name | Type | Description |
|------|------|-------------|
| `AZURE_CLIENT_ID` | Variable | App registration client ID for OIDC |
| `AZURE_TENANT_ID` | Secret | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Secret | Target Azure subscription ID |

See [docs/azure-oidc-setup.md](docs/azure-oidc-setup.md) for OIDC setup instructions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
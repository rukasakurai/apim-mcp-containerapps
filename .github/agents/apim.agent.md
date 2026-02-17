# APIM Bicep Agent Notes

This document captures challenges and decisions encountered when creating the Azure API Management Bicep infrastructure.

## Challenges

### 1. Standard V2 SKU Requires a Specific API Version

The `StandardV2` SKU is not recognized by older API versions of the `Microsoft.ApiManagement/service` resource. You must use API version `2024-05-01` or later. Using an older version (e.g., `2023-03-01-preview` or earlier GA versions) results in a validation error stating that the SKU name is invalid.

### 2. APIM Provisioning Time

Azure API Management instances, even with the V2 SKUs, can take a significant amount of time to provision (often 10-30 minutes). This affects CI/CD pipeline design—workflows that run `azd provision` followed by `azd down` need sufficient timeout allowances and should always run teardown with `if: always()` to avoid leaving resources behind on failure.

### 3. azd Parameter Substitution

The `main.parameters.json` file uses `${AZURE_ENV_NAME}` and `${AZURE_LOCATION}` syntax for azd environment variable substitution. The `publisherEmail` parameter is required by APIM and must be supplied via the `AZURE_APIM_PUBLISHER_EMAIL` environment variable. If omitted, the deployment will fail with a validation error.

### 4. Subscription-Level Deployment Scope

Azure Developer CLI (`azd`) expects `main.bicep` to use `targetScope = 'subscription'` so it can create the resource group. This means the APIM resource itself must be deployed via a Bicep module scoped to the resource group, rather than being defined directly in `main.bicep`.

### 5. Bicep Linting with `az bicep lint`

The `az bicep lint` command validates Bicep files against best practices. Some common lint warnings include unused parameters and missing descriptions. All parameters in the APIM module include `@description` decorators to satisfy lint rules and improve documentation.

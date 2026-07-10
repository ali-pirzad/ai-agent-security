# Phased Deployment — Resources & Validation Gates

Each phase is a separate Terraform root under `infra/terraform/`. Deploy in order. Do not proceed
until the validation gate passes and the user confirms.

## Egress governance — the primary security narrative

Target flow: **Copilot Studio → approved connector → APIM → VNet / Private Endpoint → Customer API**.
Each control is enforced in the phase where the resource is created — do NOT try to apply them all in
Phase 1. Enforcement map:

| # | Egress control | Enforced in | Notes |
|---|----------------|-------------|-------|
| 1 | Backend cannot reach public internet (`DenyInternetOutbound` on function subnet) | **Phase 1** ✅ done | Requires `vnetRouteAllEnabled=true` (Phase 3) to be fully effective |
| 2 | Backend has no public endpoint; APIM resolves it to a private IP | **Phase 3** | `public_network_access_enabled=false` + private endpoint + `privatelink.azurewebsites.net` |
| 3 | All backend outbound routed through the VNet | **Phase 3** | Function app setting `vnetRouteAllEnabled=true` (`WEBSITE_VNET_ROUTE_ALL=1`) |
| 4 | APIM backend uses the **private** hostname; key/validation/rate-limit enforced | **Phase 4** | APIM named-value function key; policies in `policies/*.xml` |
| 5 | Only approved callers can reach APIM ingress | **Phase 4** (revisit Phase 5) | APIM subnet NSG inbound = `AzureConnectors` service tag **+ `VirtualNetwork`** (Foundry agent calls APIM from inside the VNet — do NOT restrict to AzureConnectors alone or Phase 5 breaks) |
| 6 | APIM's own egress cannot reach arbitrary internet (defense-in-depth, optional) | **Phase 4** | Allow required Azure service tags (Storage, SQL, KeyVault, AzureMonitor, AzureActiveDirectory, DNS) then deny Internet. Risky for stv2 — demo-optional |

**Copilot Studio itself is SaaS** — its outbound cannot be forced through the VNet. That hop is
governed by Power Platform **DLP policy** + a custom connector scoped only to the APIM host +
APIM subscription key/OAuth. VNet/private-endpoint egress governance applies from **APIM inward**.

## Phase 1 — Foundation / Network (`01-foundation`)
**Resources**
- Resource Group.
- VNet `192.168.0.0/16`.
- Subnets: `apim`, `function-integration`, `private-endpoint`, and `agent` (`/24`, delegated to
  `Microsoft.App/environments`).
- NSGs: APIM required inbound/outbound rules; `function-integration` subnet **deny internet
  outbound** (egress demo).
- Private DNS zones:
  - `privatelink.azurewebsites.net`
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.services.ai.azure.com`
  - `privatelink.search.windows.net`
  - `privatelink.documents.azure.com`
  - `privatelink.blob.core.windows.net`

**Gate:** subnets + agent-subnet delegation + NSG rules + all DNS zones exist; `terraform plan` clean.

## Phase 2 — Observability (`02-observability`)
**Resources:** Log Analytics workspace, Application Insights (shared by APIM diagnostics and Foundry
agent tracing).
**Gate:** workspace + App Insights provisioned; connection string exported.

## Phase 3 — Backend API (`03-backend`)
**Resources:** Storage (shared-key disabled, identity-based `AzureWebJobsStorage` + role assignments),
App Service Plan B1 Linux, Function App (VNet-integrated, public network access disabled, private
endpoint), deploy `src/customer-api` code (`GET /customer/{id}`).
**Egress controls (2, 3):** `public_network_access_enabled=false`; private endpoint into
`snet-private-endpoint`; app setting `vnetRouteAllEnabled=true` so ALL function outbound hits the
Phase 1 `DenyInternetOutbound` rule.
**Gate:** Function resolves to a **private IP only**; not reachable from public internet; a test call
from the function to a public URL is blocked.

## Phase 4 — API Management (`04-apim`)
**Resources:** APIM (Developer, VNet External injection), API + operation for the customer endpoint,
policies from `infra/terraform/policies/*.xml` (subscription-key/OAuth auth, rate-limit, request/
response validation, logging), backend + named-value function key (secret), App Insights diagnostics.
**Egress controls (4, 5, optional 6):** APIM backend targets the function's **private** hostname;
tighten the APIM subnet NSG inbound to `AzureConnectors` **+ `VirtualNetwork`** (+ optional admin IP);
optionally add APIM egress deny-internet after allowing required Azure service tags.
**Gate:** allowed call succeeds through APIM; blocked scenarios (no key, external URL) fail as designed;
APIM→backend traffic resolves to the private IP.

> **This is where you first need to understand the Copilot Studio connector** — the connector is
> built from what APIM exposes here (gateway URL, the OpenAPI/Swagger export of the API, and the
> subscription key). You cannot build/scope the connector before Phase 4 exists. See the Manual phase.

## Phase 5 — AI Foundry Network-Isolated Agent (`05-foundry`)
Base on official template `15b-private-network-standard-agent-setup-byovnet` (azurerm + azapi),
consuming Phase 1 VNet via `terraform_remote_state`.
**Resources**
- BYO data stores, all private + local-auth disabled: Cosmos DB (SQL API), AI Search (Standard),
  Storage.
- Foundry account (`AIServices` kind, S0, system-assigned MI, `publicNetworkAccess = Disabled`,
  private endpoint).
- `gpt-4o` model deployment.
- Project + connections (Cosmos / Storage / Search).
- Capability hosts: account (empty) + project (cosmos/storage/search connections) via `azapi`.
- RBAC role assignments; private endpoints for all dependencies.
**Gate:** Foundry account is private-only (`publicNetworkAccess = Disabled` audited); an agent can be
created in the project; all dependencies reached via private endpoints.

## Manual — Agent Configuration & Demos

### When connector knowledge is needed
Connector work is **the last step, and only after Phase 4** (APIM must exist first). Timeline:
1. **Phases 1–3:** no connector knowledge required — pure Azure infra.
2. **Phase 4 (APIM live):** now the connector inputs exist — export the API's OpenAPI definition,
   note the gateway base URL and the subscription key. This is the earliest the connector can be built.
3. **Manual phase:** actually create and scope the connector + governance.

### How the Copilot Studio custom connector works (build it here)
- **Definition:** import the **OpenAPI/Swagger** exported from the APIM API. The connector's host is
  locked to the **APIM gateway URL** — the only endpoint it can call. It has no generic HTTP action.
- **Auth:** the connector sends the APIM **subscription key** (header `Ocp-Apim-Subscription-Key`) or
  OAuth; APIM rejects any call without it.
- **Allow-list governance:** a Power Platform **DLP policy** places this connector in *Business* and
  blocks generic HTTP / unapproved connectors, so an agent cannot call anything else.
- **Result:** Copilot Studio → (this connector only) → APIM → private backend. Any attempt to reach a
  different host is not expressible in the agent (no connector for it) and is blocked by DLP.

### AI Foundry agent
- Agent **OpenAPI tool** → **same APIM** endpoint (calls originate inside the VNet, hence the
  `VirtualNetwork` allowance in APIM inbound — control #5).

### Validate
- End-to-end allowed + blocked runs on both platforms using `docs/demo-scenarios`.

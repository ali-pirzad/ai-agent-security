# AI Agents Security — Build Journal & Decision Log

A living record of **what** was built, **why**, **how**, and every **gotcha / fix** encountered.
Updated as each phase completes. Skim the tables; dive into "Why" and "Gotchas" to learn the reasoning.

- **Goal:** A customer-facing demo proving enterprise-grade, Zero-Trust security for AI agents
  (Microsoft Copilot Studio **and** Azure AI Foundry) behind one perimeter: VNet isolation,
  private endpoints, APIM governance, deny-by-default.
- **Subscription:** `connectivity` (`22d921af-…`) — an Azure Landing Zone *platform* subscription
  (this causes several governance gotchas below).
- **Region:** `centralus` · **IaC:** Terraform (`azurerm ~> 4.2`) · **Prefix:** `aas`
- **Core flow proven:** `Agent → approved connector → APIM → VNet / Private Endpoint → Customer API`

---

## The egress-governance model (the security thesis)

VNet/private-endpoint egress control applies **from APIM inward**. Copilot Studio is SaaS — its own
outbound can't be forced through the VNet, so that hop is governed by connector allow-listing + DLP +
making APIM the only reachable endpoint.

| # | Control | Enforced in | Status |
|---|---------|-------------|--------|
| 1 | Backend can't reach public internet (`DenyInternetOutbound` on function subnet) | Phase 1 | ✅ |
| 2 | Backend has no public endpoint; APIM resolves it to a private IP | Phase 3 | ✅ |
| 3 | All backend outbound routed through the VNet | Phase 3 (Flex: inherent) | ✅ |
| 4 | APIM → private backend hostname; key/validation/rate-limit | Phase 4 | ✅ |
| 5 | Only approved callers reach APIM ingress (`AzureConnectors` + `VirtualNetwork`) | Phase 4 (revisit P5) | ⏳ documented, not yet tightened |
| 6 | APIM's own egress can't reach arbitrary internet (defense-in-depth) | Phase 4 (optional) | ⏳ optional |

---

## What was built, per phase

### Phase 1 — Foundation / Network (`infra/terraform/01-foundation`)
**Purpose:** the private perimeter everything else plugs into.

| Resource | Purpose |
|----------|---------|
| Resource group `rg-aas-demo-cus` | container for the demo |
| VNet `vnet-aas-cus` `192.168.0.0/16` | the isolation boundary |
| Subnet `snet-apim` | hosts the VNet-injected APIM gateway |
| Subnet `snet-function` (delegated `Microsoft.App/environments`) | Flex Consumption VNet integration |
| Subnet `snet-private-endpoint` | private endpoints for backend + Foundry deps |
| Subnet `snet-agent` (`/24`, delegated `Microsoft.App/environments`) | Foundry Standard Agent runtime |
| NSG `nsg-aas-apim-cus` | APIM required inbound/outbound rules |
| NSG `nsg-aas-func-cus` | **deny-all-internet egress** (the Zero-Trust proof point) |
| 7 private DNS zones + VNet links | private name resolution for azurewebsites, blob, cognitiveservices, openai, services.ai, search, documents |
| Policy exemption `exempt-aas-ddos` | see gotcha G1 |

**Why `192.168.0.0/16`:** the Foundry network-isolated agent template does not support `10.x` in
`centralus`; Class C avoids that.

### Phase 2 — Observability (`02-observability`)
**Purpose:** the evidence layer — proves "blocked vs allowed" and feeds APIM + Foundry telemetry.

| Resource | Purpose |
|----------|---------|
| Log Analytics `log-aas-cus` (PerGB2018, 30d) | central log sink |
| Application Insights `appi-aas-cus` (workspace-based) | APIM gateway telemetry + Foundry agent traces |

**Why now (not later):** it's a demo requirement (show request traces), and both Phase 4 (APIM
diagnostics) and Phase 5 (agent tracing) consume it — deferring would mean rework.

### Phase 3 — Backend API (`03-backend`)
**Purpose:** the private "customer data" API the agent is allowed to call.

| Resource | Purpose |
|----------|---------|
| Storage `staascusjbwlgy` (shared-key **disabled**, public off) | Function runtime + deployment package, identity-based |
| Blob private endpoint | private storage access |
| App Service Plan `asp-aas-cus` (**FC1** Flex Consumption, Linux) | serverless host, per Azure best practice |
| Function App `func-aas-cus-jbwlgy` (Node 20, system MI, VNet-integrated) | the API |
| Site private endpoint `pe-aas-func-site` | inbound private-only access |
| RBAC: MI → `Storage Blob Data Owner` | keyless storage access |
| Code `src/customer-api` | `GET /customer/{id}` + welcome (`/root`) |

**Egress lockdown:** `public_network_access_enabled = false` → backend returns **403** publicly,
reachable only from inside the VNet. Flex Consumption routes *all* outbound through the VNet subnet
by default (no `WEBSITE_VNET_ROUTE_ALL` toggle needed), satisfying control #3 inherently.

**Auth model decision (important):** the `customer` endpoint is **anonymous at the function**, protected
by **network isolation** (private endpoint + no public access + APIM as the only in-VNet caller).
Client auth is enforced at APIM (subscription key). Reason: the Flex function-key management API is
unavailable in this Flex+private configuration (gotcha G6). This is arguably a *stronger* Zero-Trust
story — there is no shared secret to leak or rotate. Production hardening path: APIM managed identity
→ function Easy Auth (adds an app registration; out of scope for the demo).

### Phase 5 — AI Foundry network-isolated agent (`05-foundry`)
**Purpose:** prove the *same* Zero-Trust perimeter secures a second agent platform (Azure AI Foundry),
with all agent state in customer-owned, private data stores. Ported from the official Terraform
template `15b-private-network-standard-agent-setup-byovnet`, adapted to reuse our existing VNet,
subnets, DNS zones, and resource group (single subscription).

| Resource | Purpose |
|----------|---------|
| Foundry account `aifoundry4484` (`AIServices`, S0, SMI) | agent runtime; **agent VNet-injected** into `snet-agent` |
| Model `gpt-5-mini` (GlobalStandard) | the agent's LLM |
| Cosmos DB `aifoundry4484cosmosdb` (private, local-auth off) | agent thread/message storage |
| AI Search `aifoundry4484search` (Standard, private) | agent vector store |
| Storage `aifoundry4484storage` (private-by-ACL) | agent file storage |
| Project `project4484` + 3 connections (Cosmos/Storage/Search) | the agent workspace |
| Project **capability host** `caphostproj` (`azapi`) | wires BYO stores into the agent runtime |
| 4 private endpoints (Foundry/Cosmos/Search/Storage) | private-only connectivity |
| RBAC (Cosmos Operator + SQL data role, Search x2, Storage Blob Data Contributor/Owner w/ ABAC) | keyless, scoped access for the project MI |

**Firewall decision (chosen: allow-my-IP):** the Foundry account is `publicNetworkAccess = Enabled`
with `networkAcls.defaultAction = Deny` and `ipRules = [<your workstation IP>]`, plus the private
endpoint. This lets you create/test the agent from the portal without a jump box. For a fully-private
posture, set `publicNetworkAccess = Disabled` and drop `ipRules` (then access requires VM/Bastion/VPN).
`allowed_client_ip` is a variable.

**Storage nuance:** `publicNetworkAccess` shows `Enabled` but the network ACL is **Deny-all** with an
`AzureServices` bypass — this is the official template's design, because the capability-host process
needs the bypass to create the agent blob containers. Cosmos and Search are fully `Disabled`.

**Capability host learning:** template `15b` has **only a project-level** capability host (no
account-level one) — contrary to an earlier assumption. The template is authoritative.

### Phase 4 — API Management (`04-apim`)
**Purpose:** the governance chokepoint — the single, governed front door.

| Resource | Purpose |
|----------|---------|
| Public IP `pip-aas-apim-cus` (Standard, DNS label) | required for APIM stv2 VNet injection |
| APIM `apim-aas-cus-egtyrm` (Developer, **VNet External**) | public gateway, private backend |
| API `welcome-api` (path `""`, no key) | public landing at gateway root → rewrites to backend `/root` |
| API `customer-api` (path `api`, **subscription key required**) | governed data API → backend `/customer/{id}` |
| API policies (`policies/*.xml`) | rate-limit (20/60s), `{id}` regex validation, response-header hygiene |
| Subscription `aas-demo-client` (all-APIs scope) | the client credential |
| Logger + diagnostic → App Insights | request/response tracing (100% sampling) |

**Gateway:** `https://apim-aas-cus-egtyrm.azure-api.net`
- `GET /` → "Welcome to Azure Agents Security" (no key)
- `GET /api/customer/{id}` + `Ocp-Apim-Subscription-Key` → customer JSON

---

## Testing / validation performed

| Phase | Check | Result |
|-------|-------|--------|
| 1 | subnet delegations, deny-egress NSG rule, DDoS exemption | ✅ confirmed via `az` |
| 2 | workspace + App Insights provisioned | ✅ |
| 3 | `/customer/ACME-42` returns `{customerId, riskScore, riskTier, transactions[]}` | ✅ |
| 3 | public URL after lockdown | **403** (blocked) ✅ |
| 4 | welcome at gateway root (no key) | 200 ✅ |
| 4 | customer call **with** key | 200 + data ✅ |
| 4 | customer call **no key** | 401 ✅ |
| 4 | invalid id (`bad!!id`) | 400 (validated at gateway) ✅ |
| 4 | undefined route (`/api/orders/1`) | 404 ✅ |
| 4 | direct-to-backend bypass | 403 (private only) ✅ |
| 5 | Foundry account firewall | Enabled + default Deny + ipRules=[your IP] ✅ |
| 5 | Cosmos / AI Search public access | Disabled ✅ |
| 5 | Storage public access | Enabled + ACL Deny-all (AzureServices bypass) ✅ |
| 5 | Model deployment `gpt-5-mini` | Succeeded ✅ |

---

## Gotchas & troubleshooting log

Numbered so we can reference them. Each: **symptom → root cause → fix**.

- **G1 — DDoS policy blocks VNet creation.** *Symptom:* VNet create fails 404 on a non-existent
  `ddos-centralus` plan. *Cause:* the `connectivity` management group assigns a **Modify** policy
  `Enable-DDoS-VNET` that force-attaches a DDoS plan. *Fix:* `azurerm_resource_group_policy_exemption`
  (Waiver) on the RG; VNet `depends_on` it.

- **G2 — `terraform … -out=FILE` fails.** *Symptom:* "Too many command line arguments." *Cause:* this
  PowerShell mangles the `-out=` token. *Fix:* use the `-chdir=PATH` global flag and omit `-out`
  (apply directly).

- **G3 — Azure auth timeouts.** *Symptom:* Terraform "could not acquire access token." *Cause:*
  network couldn't reach `login.microsoftonline.com` (VPN). *Fix:* reconnect network; **not** a
  OneDrive/file-location issue.

- **G4 — `Microsoft.App` RP not registered.** *Symptom:* Flex VNet integration fails. *Cause:* the
  resource provider wasn't registered in the subscription. *Fix:* `az provider register -n
  Microsoft.App --wait`, then re-apply.

- **G5 — Flex code deploy silently registers nothing.** *Symptom:* `az functionapp deployment source
  config-zip` returns 202 but 0 functions; root shows the default page. *Cause:* `config-zip` relies
  on `WEBSITE_RUN_FROM_PACKAGE`, unsupported on Flex Consumption. *Fix:* deploy with **Azure Functions
  Core Tools** — `func azure functionapp publish <app> --javascript --no-build`.

- **G6 — Flex function keys unavailable.** *Symptom:* `az functionapp keys list` and ARM `listkeys`
  both return "Bad Request." *Cause:* Flex + private-networking key-management limitation. *Fix:*
  pivoted to **anonymous backend + network isolation + APIM subscription key** (see Phase 3 auth
  decision).

- **G7 — Functions host reserves `/`.** *Symptom:* welcome function at empty route lands at `/root`,
  not `/`; the host's default page occupies `/`. *Cause:* Node v4 maps empty `route` to the function
  name, and the host owns `/`. *Fix:* surface the welcome at the **APIM** gateway root instead
  (rewrite `/` → backend `/root`).

- **G8 — Any Flex code change needs public access.** *Note:* SCM/deploy is private once locked down,
  so redeploys require flipping `function_public_network_access_enabled = true` briefly, then back.

- **G9 — APIM subscription key rejected as invalid.** *Symptom:* 401 "invalid subscription key" with a
  valid-looking key. *Cause:* `azurerm_api_management_subscription.api_id` scopes the subscription to
  the API **revision** (`/apis/customer-api;rev=1`), which the gateway doesn't match at runtime.
  *Fix:* omit `api_id` so the scope is **all APIs**.

- **G10 — Public IP forced replacement.** *Symptom:* a subscription-only change tried to destroy the
  APIM public IP (fails, in use). *Cause:* a `connectivity` governance policy stamps **`ip_tags`** on
  public IPs; Terraform wants to remove them → forces replacement. *Fix:* `lifecycle { ignore_changes
  = [ip_tags] }` on the public IP.

- **G11 — gpt-4o retired for new deployments.** *Symptom:* model deployment fails 400
  `ServiceModelDeprecating: 'gpt-4o,2024-11-20' ... cannot be used for new deployments`. *Cause:* by
  mid-2026 gpt-4o is retired for *new* deploys. *Fix:* pick a current GA chat model
  (`az cognitiveservices account list-models ... lifecycleStatus=='GenerallyAvailable'`) — switched to
  `gpt-5-mini` `2025-08-07`. All 22 other resources had already applied; only the deployment re-ran.

**Pattern to remember:** several gotchas (G1, G10) come from deploying into a **governed Landing Zone
platform subscription**. Policies mutate resources post-create; ignore that drift or exempt it.

---

## Still to do

- **Manual — Foundry agent:** in the Foundry portal (reachable from your allow-listed IP), create an
  agent in `project4484` on `gpt-5-mini`, then add an **OpenAPI tool** pointing at the same APIM
  endpoint `https://apim-aas-cus-egtyrm.azure-api.net/api/customer/{id}` (subscription key). This
  proves both agent platforms egress through the identical governed gateway.
- **Manual — Copilot Studio:** custom connector (OpenAPI import + subscription key) + DLP policy so
  the agent can only call the approved connector.
- **Control #5 (optional):** tighten APIM subnet NSG inbound to `AzureConnectors` + `VirtualNetwork`.
- **Demo:** end-to-end allowed/blocked runs on both platforms.

## Teardown (important)

- Destroy in reverse (05 → 01). Before deleting the Foundry account you must **purge** it (soft-delete
  blocks reuse), and the **agent subnet is single-use** per account — a failed capability-host run
  leaves a `legionservicelink` on the subnet; on retry use a new VNet/subnet name.

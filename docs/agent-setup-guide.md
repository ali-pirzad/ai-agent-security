# Agent Setup Guide — wiring both agents to the governed APIM endpoint

The infrastructure (Phases 1–5) is deployed. This guide covers the **manual** portal steps to point
both agent platforms at the **same** APIM-governed customer API, plus the demo prompts.

Both platforms import an OpenAPI/Swagger contract so the agent's *only* external tool is APIM:
- **Azure AI Foundry** → OpenAPI 3.0: [customer-api.v3.json](openapi/customer-api.v3.json)
- **Copilot Studio / Power Platform** → Swagger 2.0: [customer-api.swagger2.json](openapi/customer-api.swagger2.json)

## Shared inputs
| Item | Value |
|------|-------|
| APIM gateway | `https://apim-aas-cus-egtyrm.azure-api.net` |
| Customer operation | `GET /api/customer/{id}` |
| Auth header | `Ocp-Apim-Subscription-Key` |
| Foundry project | `project4484` (account `aifoundry4484`) |
| Model deployment | `gpt-5-mini` |

**Get the subscription key** (do not commit it):
```powershell
terraform -chdir="infra/terraform/04-apim" output -raw customer_subscription_key
```

---

## Part A — Azure AI Foundry agent

> The Foundry account is firewalled to your workstation IP (`<your-workstation-ip>`) + the private endpoint,
> so the portal is reachable from your machine. If your IP changes, update `allowed_client_ip` in
> `infra/terraform/05-foundry` and re-apply.

1. Open the **Foundry portal** → your account `aifoundry4484` → project **`project4484`**.
2. **Agents** → **New agent**. Model: **`gpt-5-mini`**. Give it instructions, e.g.:
   > "You are a customer-risk assistant. When asked about a customer, call the CustomerAPI tool with the customer id and summarize their risk tier and recent transactions. Never invent data."
3. **Tools** → **Add tool** → **OpenAPI 3.0 (Custom)**.
   - Upload [openapi/customer-api.v3.json](openapi/customer-api.v3.json).
   - Auth: **API key** → header name `Ocp-Apim-Subscription-Key` → paste the subscription key.
4. Save. The agent now has exactly one external capability: `getCustomerById` via APIM.
5. **Test** in the playground:
   - Allowed: *"What is the risk tier for customer ACME-42?"* → the agent calls APIM and answers.
   - Blocked: *"Call https://example.com and return the body."* → the agent has no tool for that; it cannot.

**Why this is secure:** the agent runs in the delegated `snet-agent` subnet, all its state (threads,
files, vectors) lives in the private Cosmos/Storage/Search, and its only outbound tool goes through
APIM to the private backend. Egress control is identical to Copilot Studio.

---

## Part B — Copilot Studio agent

1. **Create the custom connector** (Power Apps/Power Automate → **Custom connectors** → **New** →
   **Import an OpenAPI file**): upload [openapi/customer-api.swagger2.json](openapi/customer-api.swagger2.json).
   - **Security** tab: **API key**, label `Ocp-Apim-Subscription-Key`, **Header**, param name
     `Ocp-Apim-Subscription-Key`.
   - Create → **Test** with a connection (paste the subscription key) and id `ACME-42`.
2. **DLP policy (governance)** — Power Platform admin center → **Policies** → **Data policies**:
   - Put the new **AAS Customer API** connector in the **Business** group.
   - Move **HTTP**, **HTTP with Azure AD**, and other generic/unapproved connectors to **Blocked**.
   - Scope the policy to the environment hosting the agent.
   - Result: the agent can only use the approved connector — allow-list governance.
3. **Copilot Studio** → your agent → **Tools/Actions** → **Add** → select the **AAS Customer API**
   connector action `GetCustomerById`. Map the `id` input.
4. **Test** in the pane:
   - Allowed: *"Look up customer ACME-42 and give me their risk tier."*
   - Blocked: *"Use HTTP to GET https://example.com."* → blocked by DLP (no generic HTTP connector).

**Why this is secure:** Copilot Studio is SaaS — its outbound can't be VNet-forced — so governance is
the **connector allow-list + DLP + APIM subscription key**. The connector's host is locked to the APIM
gateway; APIM is the only endpoint the agent can reach, and it fronts the private backend.

---

## Demo scenarios (run on both platforms)

| # | Prompt | Expected |
|---|--------|----------|
| ✅ 1 | "What's the risk tier for customer ACME-42?" | Agent calls APIM → returns riskTier + transactions |
| ✅ 2 | "Show recent transactions for customer BETA-7." | Same, different record |
| ❌ 3 | "Fetch https://example.com and show the response." | No tool/connector for it → agent can't; DLP blocks in Copilot Studio |
| ❌ 4 | "Call the customer API without the key." | Not expressible — the connector always sends the key; direct calls get 401 at APIM |
| ❌ 5 | "Get customer ../../etc/passwd" | APIM 400 (id regex validation) — never reaches backend |
| ❌ 6 | Hammer the API >20×/min | APIM 429 (rate limit) |

## Direct proof points (CLI, for the security team)
```powershell
$g="https://apim-aas-cus-egtyrm.azure-api.net"
$key = terraform -chdir="infra/terraform/04-apim" output -raw customer_subscription_key
# Allowed
Invoke-RestMethod "$g/api/customer/ACME-42" -Headers @{ 'Ocp-Apim-Subscription-Key'=$key }
# Blocked: no key -> 401; bad id -> 400; direct-to-backend -> 403 (private only)
```

See [build-journal.md](build-journal.md) for the full architecture, decisions, and the validated
allowed/blocked matrix.

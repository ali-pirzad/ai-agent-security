---
name: secure-agent-demo
description: 'Build and deploy a Zero-Trust demo that secures Microsoft Copilot Studio AND Azure AI Foundry agents behind the same enterprise perimeter (VNet isolation, private endpoints, Azure API Management governance, deny-by-default RBAC) on Azure using Terraform. USE FOR: secure Copilot Studio demo, AI Foundry agent security, network-isolated agent, APIM agent governance, private endpoint agent, VNet egress control for agents, phased Terraform deploy of the ai-agents-security workspace, customer-facing agent security proof. DO NOT USE FOR: production hardening beyond a demo, non-Azure agent platforms, generic Terraform unrelated to this project.'
argument-hint: 'Name the phase to work on (e.g. "deploy phase 1 foundation") or the layer to change'
---

# Secure Copilot Studio + Azure AI Foundry Agent Demo

Repeatable workflow for the `ai-agents-security` workspace: a customer-facing demo that
**proves enterprise-grade security for AI agents**. It secures two agent platforms —
**Microsoft Copilot Studio** and **Azure AI Foundry** — behind one Zero-Trust perimeter and
routes all agent egress through **Azure API Management (APIM)** to a private backend API.

## When to Use
- Deploying or modifying any layer of this demo (network, backend, APIM, AI Foundry, agents).
- Adding a new secured tool/connector for either agent platform.
- Demonstrating allowed vs blocked (egress / non-approved tool / exfiltration) scenarios.
- Onboarding into the project's design decisions and known gotchas.

## Non-Negotiable Principles
1. **Zero Trust / deny-by-default** — nothing is reachable unless explicitly allowed.
2. **All agent egress flows through APIM** — Copilot Studio and Foundry agents call the *same*
   APIM-fronted backend. No generic HTTP / open connectors. No public outbound.
3. **Private by default** — backend, Foundry account, and all BYO data stores have public
   network access disabled and are reached via private endpoints.
4. **Identity over keys** — Managed Identity + scoped RBAC; local auth disabled where supported.
5. **Phased delivery** — deploy one layer, validate its gate, confirm, *then* proceed.

## Fixed Project Settings
| Setting | Value |
|--------|-------|
| IaC | Terraform, `azurerm` >= 4.2 (+ `azapi` for Foundry capability hosts) |
| Region | `centralus` |
| VNet address space | `192.168.0.0/16` (Class C — centralus is not in the 10.x supported list for Foundry) |
| APIM SKU | Developer (VNet **External** injection: public gateway, private backend) |
| Resource name prefix | `aas` (short for "AI Agents Security") |
| Function | App Service Plan B1 Linux, Node 20, VNet-integrated, public access disabled |
| APIM publisher email | `alipirzad@microsoft.com` |
| Foundry model | `gpt-4o` (verify capacity in `centralus` before Phase 5) |

## Repository Layout
```
infra/terraform/
  01-foundation/     # RG, VNet, subnets, NSGs, private DNS zones
  02-observability/  # Log Analytics, Application Insights
  03-backend/        # Storage (MI), ASP B1, Function App (private), code deploy
  04-apim/           # APIM (VNet-injected), API, policies, backend, named values
  05-foundry/        # Cosmos + AI Search + Storage + Foundry account/project + caphosts + model
  policies/          # APIM policy XML
src/customer-api/    # Node.js Function — GET /customer/{id} -> {customerId, transactions, riskScore}
docs/                # deployment-guide, copilot-studio-setup, foundry-agent-setup, demo-scenarios
```
Each phase is its own Terraform root with **local state**; later phases read earlier outputs via
`terraform_remote_state`. This enables apply → validate → confirm per layer.

## Deployment Workflow
Work **one phase at a time**. Do not start a phase until the prior phase's validation gate passes
and the user confirms. Detailed per-phase resources and validation gates are in
[phases reference](./references/phases.md).

For each phase:
1. `terraform init` then `terraform plan` in the phase folder — review for a clean plan.
2. `terraform apply` — deploy the layer.
3. Run the phase's **validation gate** (see [phases reference](./references/phases.md)).
4. Report results and get confirmation before the next phase.

Traffic flow to prove: **Agent (Copilot Studio / Foundry) → APIM → Private Endpoint → Function App**,
with the backend subnet having **no outbound internet**.

## Known Gotchas
Read [gotchas reference](./references/gotchas.md) before Phase 5. Highlights:
- Failed Foundry capability-host retries require a **new VNet name**; **purge** the account on destroy.
- centralus needs `192.168.0.0/16`, not `10.x`.
- Foundry needs extra private DNS zones (cognitiveservices, openai, services.ai, search, documents)
  and an **agent subnet `/24` delegated to `Microsoft.App/environments`**.

## Demo Scenarios (both platforms)
- ✅ Allowed: agent calls the approved API via APIM (subscription key + policies enforced).
- ❌ Blocked: agent calls an external/public API (deny-by-default egress).
- ❌ Blocked: agent uses a non-approved tool/connector (allow-list governance / DLP).
- ❌ Blocked: data exfiltration attempt (private endpoints + NSG egress deny).
Sample prompts and expected outcomes live in `docs/demo-scenarios`.

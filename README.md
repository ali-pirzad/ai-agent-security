# Securing AI Agents the Zero-Trust Way

**One governed perimeter for Microsoft Copilot Studio _and_ Azure AI Foundry.**

A working, Terraform-deployed demo that proves enterprise-grade security for AI agents: VNet isolation, private endpoints, Azure API Management governance, and deny-by-default egress — with every control validated by a real HTTP status code, not a slide.

---

## Why this exists

Whether a team builds a low-code agent in **Copilot Studio** or a pro-code agent on **Azure AI Foundry**, the security team asks the same three questions:

1. **Where can the agent send data?** (egress / network control)
2. **What is it allowed to call, and can I see every call?** (API governance + audit)
3. **How do I know it can't wander off-script?** (agent-level restrictions)

This project answers all three with infrastructure you can deploy and test.

## Architecture

> **Agent → approved connector/tool → Azure API Management → private network (VNet + private endpoints) → private backend API.**

```mermaid
flowchart LR
    subgraph agents["Agent layer (callers)"]
        CS["Microsoft<br/>Copilot Studio"]
        FA["Azure AI<br/>Foundry Agent"]
    end

    APIM["Azure API Management<br/>• subscription key<br/>• rate-limit 20/60s<br/>• request validation<br/>• logging<br/><i>public gateway, VNet-injected</i>"]
    APPI["App Insights +<br/>Log Analytics"]

    subgraph vnet["VNet 192.168.0.0/16 — deny by default"]
        direction TB
        FN["Customer API (Function)<br/><i>private endpoint • public OFF • deny internet egress</i>"]
        subgraph foundry["AI Foundry — account firewalled (admin IP + PE)"]
            direction TB
            FACC["Foundry account + model<br/><i>VNet-injected agent</i>"]
            COS["Cosmos DB<br/>(threads)"]
            SRCH["AI Search<br/>(vectors)"]
            STOR["Storage<br/>(files)"]
        end
    end

    CS -- "approved connector + DLP" --> APIM
    FA -- "OpenAPI tool" --> APIM
    APIM -- "private endpoint (key)" --> FN
    APIM -. "logs / traces" .-> APPI
    FACC --- COS
    FACC --- SRCH
    FACC --- STOR

    X1["❌ external / public API — no connector"]:::blk
    X2["❌ no key → 401 · bad id → 400 · bypass → 403 · >20/min → 429"]:::blk
    CS -.->|blocked| X1
    APIM -.->|enforced| X2

    classDef blk fill:#FDE7E9,stroke:#D13438,color:#000;
```

## How it's built (phased Terraform)

Each phase is independent infrastructure-as-code, validated before the next is layered on top.

| Phase | Folder | What it creates | Why |
|---|---|---|---|
| **1 · Foundation** | [`infra/terraform/01-foundation`](infra/terraform/01-foundation) | VNet, 4 subnets, NSGs (incl. deny-internet egress), 7 private DNS zones | The network perimeter — "where data can go" |
| **2 · Observability** | [`infra/terraform/02-observability`](infra/terraform/02-observability) | Log Analytics + Application Insights | Prove every control with telemetry |
| **3 · Backend** | [`infra/terraform/03-backend`](infra/terraform/03-backend) | Private Function API + storage (managed identity, public access OFF) | The data worth protecting |
| **4 · API Management** | [`infra/terraform/04-apim`](infra/terraform/04-apim) | VNet-injected APIM gateway + policies | The single governed door — auth, validation, rate-limit, logging |
| **5 · Foundry** | [`infra/terraform/05-foundry`](infra/terraform/05-foundry) | Foundry account/project/model + private Cosmos/Search/Storage | Network-isolated agent, same perimeter |

## How the phases fit together

Solid arrows = **build-time dependency** (`terraform_remote_state`); dotted arrows = **runtime** data/telemetry flow. Full one-pager: [`docs/phases-overview.md`](docs/phases-overview.md).

```mermaid
flowchart TB
    subgraph P1["Phase 1 — Foundation (network perimeter)"]
        VNET["VNet 192.168.0.0/16"]
        SNAPIM["snet-apim"]
        SNFUNC["snet-function<br/>deny-internet egress"]
        SNPE["snet-private-endpoint"]
        SNAGENT["snet-agent"]
        DNS["7 private DNS zones"]
        VNET --- SNAPIM & SNFUNC & SNPE & SNAGENT & DNS
    end

    subgraph P2["Phase 2 — Observability"]
        LAW["Log Analytics<br/>log-aas-cus"]
        AI["App Insights<br/>appi-aas-cus (workspace-based)"]
        AI --- LAW
    end

    subgraph P3["Phase 3 — Private backend"]
        FUNC["Function API<br/>public OFF · managed identity"]
        STOR3["Storage (blob)"]
        FUNC --- STOR3
    end

    subgraph P4["Phase 4 — API Management"]
        APIM["APIM gateway (VNet-injected)<br/>key · rate-limit · validation · logging"]
        SUB["subscription: aas-demo-client"]
        APIM --- SUB
    end

    subgraph P5["Phase 5 — AI Foundry"]
        FACC["Foundry account + model<br/>firewalled (admin IP + PE)"]
        PROJ["project + capability host"]
        COS["Cosmos (threads)"]
        SRCH["AI Search (vectors)"]
        STOR5["Storage (files)"]
        FACC --- PROJ
        PROJ --- COS & SRCH & STOR5
    end

    P1 -->|remote state: RG, subnets, DNS| P2
    P1 -->|subnets + DNS| P3
    P2 -->|workspace / App Insights IDs| P3
    P1 -->|apim subnet| P4
    P3 -->|backend URL| P4
    P2 -->|logger + diagnostic| P4
    P1 -->|agent + PE subnets + DNS| P5
    P2 -->|App Insights conn string| P5
    P4 -->|gateway URL for OpenAPI tool| P5

    APIM -.->|private endpoint + key| FUNC
    APIM -.->|gateway logs / traces| AI
    FUNC -.->|requests / failures| AI
    FACC -.->|agent traces| AI

    classDef sink fill:#E7F0FD,stroke:#0F6CBD,color:#000;
    class LAW,AI sink;
```

## Proof, not promises

Same results on **both** agent platforms:

| Scenario | Result | Proves |
|---|---|---|
| ✅ Approved API via gateway (with key) | **200** + data | The intended path works |
| ❌ Missing / invalid key | **401** | Auth enforced at the gateway |
| ❌ Invalid / injection-style id | **400** | Input validated before backend |
| ❌ Undefined route / other API | **404** | No connector exists for anything else |
| ❌ Direct-to-backend (bypass) | **403** | Backend is private-only |
| ❌ Abusive burst | **429** | Rate limiting protects the backend |

## Repository map

| Path | Contents |
|---|---|
| [`infra/terraform/`](infra/terraform) | The five deployment phases |
| [`src/customer-api/`](src/customer-api) | Mock customer/risk API (Azure Functions) |
| [`docs/article.md`](docs/article.md) | Full step-by-step write-up (what / why / how it helps) |
| [`docs/phases-overview.md`](docs/phases-overview.md) | One-pager: all five phases and how they chain |
| [`docs/phase-1-foundation.md`](docs/phase-1-foundation.md) | Phase 1 diagram with NSG rules |
| [`docs/architecture.html`](docs/architecture.html) | Interactive architecture + real-world walkthrough |
| [`docs/build-journal.md`](docs/build-journal.md) | Decision log and gotchas |
| [`docs/agent-setup-guide.md`](docs/agent-setup-guide.md) | Wiring the Foundry agent + Copilot Studio connector |

## Deploy

Each phase is applied in order (Windows PowerShell):

```powershell
terraform -chdir="infra/terraform/01-foundation" init
terraform -chdir="infra/terraform/01-foundation" apply -input=false
# …repeat for 02 → 05
```

> Provide secrets (subscription ID, allow-listed IP, etc.) via each phase's `terraform.tfvars` — **not committed** (see [.gitignore](.gitignore)).

## The honest caveat

Copilot Studio is SaaS — you **cannot** force its own outbound traffic through your VNet. So its hop is governed by an **allow-listed custom connector + Power Platform DLP + gateway key**; VNet/private-endpoint egress control applies from **API Management inward**, where the sensitive data lives.

---

*This is a demo pattern for learning and customer conversations — not production hardening. See [`docs/build-journal.md`](docs/build-journal.md) for the full reasoning and known gotchas.*

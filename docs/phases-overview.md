# The five phases, on one page

Each phase is independent Terraform with its own state. Later phases read earlier phases via `terraform_remote_state`, and at runtime traffic/telemetry flows between the deployed resources. Solid arrows = **build-time dependency** (remote state); dotted arrows = **runtime** data/telemetry flow.

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
        PEFUNC["site private endpoint"]
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

    %% ---- build-time dependencies (remote state) ----
    P1 -->|remote state: RG, subnets, DNS| P2
    P1 -->|subnets + DNS| P3
    P2 -->|workspace / App Insights IDs| P3
    P1 -->|apim subnet| P4
    P3 -->|backend URL| P4
    P2 -->|logger + diagnostic| P4
    P1 -->|agent subnet + PE subnet + DNS| P5
    P2 -->|App Insights conn string| P5
    P4 -->|gateway URL for OpenAPI tool| P5

    %% ---- runtime flows ----
    FUNC -.->|private endpoint| SNPE
    APIM -.->|private endpoint + key| FUNC
    APIM -.->|gateway logs / traces| AI
    FUNC -.->|requests / failures| AI
    FACC -.->|agent traces| AI
    FACC -.->|private endpoints| SNPE

    classDef sink fill:#E7F0FD,stroke:#0F6CBD,color:#000;
    class LAW,AI sink;
```

## What each phase contributes

| Phase | Creates | Security question it answers |
|---|---|---|
| **1 · Foundation** | VNet, 4 subnets, NSGs (deny-internet egress), 7 private DNS zones | *Where can data go?* — nowhere unapproved |
| **2 · Observability** | Log Analytics + workspace-based App Insights | *Can I prove it?* — every hop is logged |
| **3 · Backend** | Private Function API + storage, public access OFF, managed identity | *What are we protecting?* — the data, off the internet |
| **4 · API Management** | VNet-injected gateway + policies (key, rate-limit, validation, logging) | *What can the agent call?* — one governed operation |
| **5 · AI Foundry** | Foundry account/project/model + private Cosmos/Search/Storage | *Same guarantees for pro-code agents* |

## Reading the arrows

- **Solid** (`—▶`): a phase consumes an earlier phase's outputs at deploy time via `terraform_remote_state` — e.g. Phase 4 needs Phase 1's `snet-apim` and Phase 3's backend URL.
- **Dotted** (`⋯▶`): live traffic or telemetry once deployed — e.g. APIM → Function over a private endpoint with the subscription key; all three tiers → App Insights.
- **Blue nodes**: the observability sink that every other phase reports into.

See each phase folder under [`../infra/terraform`](../infra/terraform) and the per-phase deep dives in [`../docs`](../docs).

# Architecture — Secure AI Agents on Azure

Two views of the same design:
- **Deck / whiteboard:** [architecture.excalidraw](architecture.excalidraw) — open at https://aka.ms/excalidraw
- **In-repo (below):** Mermaid

## Zero-Trust egress flow

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
            FACC["Foundry account + gpt-5-mini<br/><i>VNet-injected agent</i>"]
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

## Reading it
- **Left → center:** both agents can only reach **APIM** (Copilot Studio via an allow-listed connector + DLP; Foundry via an OpenAPI tool). Copilot Studio is SaaS, so its hop is governed by connector + DLP + key — not the VNet.
- **Center → right:** APIM is the single governed door; it calls the **private** Function backend via a private endpoint using the key. Everything past APIM is inside the VNet with **no public access** and **deny-internet egress**.
- **Foundry stack:** the agent's state (threads, vectors, files) stays in **customer-owned, private** Cosmos / AI Search / Storage; the Foundry account is firewalled to the admin IP + private endpoint.
- **Blocked (red):** external APIs (no connector), missing/invalid key (401), invalid id (400 at the gateway), direct-to-backend bypass (403, private-only), and rate abuse (429).

See [build-journal.md](build-journal.md) for the full decision log and [agent-setup-guide.md](agent-setup-guide.md) for wiring the agents.

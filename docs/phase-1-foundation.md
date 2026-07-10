# Phase 1 — Foundation (network perimeter)

How Phase 1 sets up every later phase: the VNet, its four purpose-built subnets, their NSGs (inbound/outbound rules), the deny-by-default egress rule, and the private DNS zones.

Only `snet-apim` and `snet-function` have NSGs. `snet-private-endpoint` and `snet-agent` have **no NSG** (private endpoints don't need one; the agent subnet is delegated and managed by the Foundry platform).

```mermaid
flowchart TB
    RG["Resource Group + DDoS exemption"] --> VNET["VNet 192.168.0.0/16"]

    %% ---- snet-apim ----
    VNET --> S1["snet-apim (192.168.1.0/24)<br/>→ Phase 4 APIM"]
    S1 --> NSG1["nsg-aas-apim-cus"]
    NSG1 --> AIN["Inbound (Allow)<br/>100 · TCP 443 · Internet → VNet (client HTTPS)<br/>110 · TCP 3443 · ApiManagement → VNet (control plane)<br/>120 · TCP 6390 · AzureLoadBalancer → VNet (probes)"]
    NSG1 --> AOUT["Outbound (Allow)<br/>100 · TCP 443 · VNet → Storage<br/>110 · TCP 1433 · VNet → SQL<br/>120 · TCP 443 · VNet → AzureKeyVault<br/>130 · TCP 1886,443 · VNet → AzureMonitor"]

    %% ---- snet-function ----
    VNET --> S2["snet-function (192.168.2.0/24)<br/>delegated Microsoft.App/environments<br/>→ Phase 3 backend"]
    S2 --> NSG2["nsg-aas-func-cus"]
    NSG2 --> FOUT["Outbound<br/>100 · Allow · ANY · VNet → VNet (reach private endpoints)"]
    NSG2 --> DENY["4096 · DENY · ANY · * → Internet<br/>Zero-Trust: no uncontrolled egress"]:::deny

    %% ---- snet-private-endpoint ----
    VNET --> S3["snet-private-endpoint (192.168.3.0/24)<br/>→ PEs (Phase 3 + 5)"]
    S3 --> NSG3["no NSG · hosts private endpoints"]:::none

    %% ---- snet-agent ----
    VNET --> S4["snet-agent (192.168.4.0/24)<br/>delegated Microsoft.App/environments<br/>→ Phase 5 Foundry agent"]
    S4 --> NSG4["no NSG · Foundry-managed agent subnet"]:::none

    %% ---- DNS ----
    VNET --> DNS["7 private DNS zones<br/>→ all later PEs resolve privately"]

    classDef deny fill:#FDE7E9,stroke:#D13438,color:#000;
    classDef none fill:#F3F2F1,stroke:#8A8886,color:#000,font-style:italic;
```

## Subnet plan

| Subnet | CIDR | Role | Special config |
|---|---|---|---|
| `snet-apim` | `192.168.1.0/24` | API Management injection | No delegation (stv2 needs a plain subnet) |
| `snet-function` | `192.168.2.0/24` | Function VNet integration | Delegated to `Microsoft.App/environments` |
| `snet-private-endpoint` | `192.168.3.0/24` | Hosts private endpoints | Plain subnet |
| `snet-agent` | `192.168.4.0/24` | Foundry Standard Agent | Delegated to `Microsoft.App/environments` |

See [../infra/terraform/01-foundation/main.tf](../infra/terraform/01-foundation/main.tf) for the full definition and [build-journal.md](build-journal.md) for the decision log.

# Gotchas & Hard-Won Lessons

## Region / Addressing
- **centralus is not in the 10.x (Class A) supported list** for the Foundry network-isolated agent
  template. Use `192.168.0.0/16` (Class C) for the VNet address space across all phases.
- Verify **`gpt-4o` capacity in centralus** before Phase 5. If unavailable, only the *model
  deployment* may move region/model; keep every other resource in `centralus`.

## Governed / Landing Zone subscription (e.g. "connectivity")
- These platform subscriptions inherit **Azure Landing Zone guardrail policies** from their
  management-group hierarchy. The one that bites: **`Enable-DDoS-VNET`** (a Modify policy assigned
  at the `connectivity` MG) force-attaches a DDoS Protection Plan to every VNet at create time. If
  that plan doesn't exist, **VNet creation fails with a 404** and everything downstream (subnets,
  NSG associations, DNS links) fails too.
- **Fix (demo):** create a `azurerm_resource_group_policy_exemption` (`exemption_category = "Waiver"`)
  scoped to the demo RG, referencing the assignment ID
  `/providers/Microsoft.Management/managementGroups/connectivity/providers/Microsoft.Authorization/policyAssignments/Enable-DDoS-VNET`,
  and make the VNet `depends_on` it. Find the assignment via
  `az policy assignment list --disable-scope-strict-match`.
- Governance may revert exemptions on shared platform subs; a dedicated sandbox/workload sub is
  cleaner if available.

## Terraform CLI on Windows PowerShell
- `terraform plan/apply -out=FILE` fails with **"Too many command line arguments"** in this shell.
  Use the `-chdir=PATH` global flag and **omit `-out`** (apply directly).

## AI Foundry Capability Hosts (Phase 5)
- Capability-host provisioning is **slow** — expect long applies; do not assume a hang.
- **On a failed capability-host retry, you must use a NEW VNet name** (a stale service link, e.g.
  `legionservicelink`, blocks re-creation). Plan resource names so they can be rotated.
- **Purge the Foundry account on destroy** — a soft-deleted account blocks re-creation with the same
  name. Purge before re-applying.
- Account capability host is created empty; the **project** capability host carries the
  cosmos/storage/search connections.

## Networking for Foundry
- Required **extra private DNS zones** beyond the backend's `azurewebsites.net`:
  `cognitiveservices.azure.com`, `openai.azure.com`, `services.ai.azure.com`,
  `search.windows.net`, `documents.azure.com` (blob zone already added for the backend).
- Required **agent subnet**: `/24`, delegated to `Microsoft.App/environments`.

## Identity & Auth
- Storage `AzureWebJobsStorage` is **identity-based** (shared key disabled) — the Function App's
  managed identity needs `Storage Blob Data Owner` (and queue/table roles as used) or the app fails
  silently at startup.
- Cosmos DB, AI Search, and Foundry have **local auth disabled** — RBAC role assignments must be in
  place before agents/connections work; missing roles surface as opaque 401/403s.

## APIM
- Developer SKU **External** VNet injection keeps the gateway publicly reachable (so Copilot Studio
  and Foundry can call it) while the backend stays private. Do not use Internal unless the demo adds
  a private ingress path.
- Client → APIM uses a **subscription key**; APIM → Function uses a **function key stored as a named
  value** (secret). Keep these two credentials distinct.

## Cost / Time Flags (demo)
- Priciest pieces: Cosmos DB + AI Search (Standard) + APIM (Developer). Acceptable for a demo but call
  out cost to the user. Tear down phases in reverse order when done.

# Securing AI Agents the Zero-Trust Way: One Governed Perimeter for Copilot Studio *and* Azure AI Foundry

*A step-by-step account of a demo environment I built to prove enterprise-grade security for AI agents — what each piece is, why it exists, and what it actually buys the customer.*

---

## Why I built this

Every enterprise I talk to is racing to put AI agents in front of employees and customers. Some are building low-code agents in **Microsoft Copilot Studio**; others are building pro-code agents on **Azure AI Foundry**. Different teams, different tools — but the moment the security team gets involved, the conversation is *identical*, and it comes down to three questions:

1. **Where can this agent send data?** If an agent can call "any URL," it's a data-exfiltration channel with a friendly chat window on top.
2. **What is the agent actually allowed to call, and can I see every call?** "Trust me, it only reads the customer record" is not an audit answer.
3. **How do I know it can't wander off-script?** Prompt injection, a rogue tool, a curious user — the blast radius has to be bounded by design, not by hope.

Slides don't answer those questions. So I built a **working demo you can test** — one where you can watch the allowed call succeed and, just as importantly, watch every disallowed call get blocked with a real HTTP status code.

The core idea: **put both agent platforms behind the exact same Zero-Trust perimeter.** That way the security story a customer has to approve is the same whether their team ships on Copilot Studio or on Foundry. One perimeter to review, one perimeter to defend.

---

## The whole thing in one sentence

> **Agent → an approved connector/tool → Azure API Management → a private network (VNet + private endpoints) → a private backend API.**

Everything to the right of API Management lives inside a virtual network with **no public access** and **deny-by-default internet egress**. API Management is the single, governed front door. The agent's *only* external capability is one approved API — it literally has no way to express a call to anything else.

To make it concrete, imagine a **bank's support copilot** that looks up a business customer's risk score before a loan officer approves a wire transfer. That copilot *must* read the core risk system — but it must reach **only** that one approved API. Never the open internet. Never a public data broker. Never the database directly. That's the scenario the demo enforces.

---

## How I built it, step by step

I deployed the environment in phases, on purpose. Each phase is independent infrastructure-as-code (Terraform), and I validated that each layer worked before building the next one on top of it. That discipline matters: when something breaks, you know exactly which layer to look at, and a customer can adopt the pattern one layer at a time instead of swallowing it whole.

### Step 1 — Lay down the network boundary *(the "where can data go" answer)*

**What I built:** A virtual network with dedicated, purpose-built subnets — one for API Management, one for the backend function, one for private endpoints, one for the Foundry agent. Each subnet has a Network Security Group (NSG). The backend subnet carries an explicit **deny-all-internet-outbound** rule. On top of that, I created **private DNS zones** for every Azure dependency (storage, the function host, the AI services, Cosmos DB, AI Search) so that every name resolves to a *private* IP inside the VNet, never a public one.

**Why it's built this way:** The network is the hardest, least-bypassable boundary you have. Application-layer rules can be misconfigured; a deny rule on outbound traffic cannot be talked around by a clever prompt. Private DNS is the quiet hero here — without it, a resource might resolve to its public endpoint and "leak" around the private path. With it, the private path is the *only* path.

**How it helps the customer:** This is the literal answer to "where can the agent send data?" — **nowhere you didn't approve.** A security reviewer can read the NSG rules and the DNS zones and see the boundary, rather than taking anyone's word for it.

### Step 2 — Stand up observability *(so every later claim is provable)*

**What I built:** A Log Analytics workspace and an Application Insights instance, wired in before any workload existed.

**Why it's built this way:** You can't prove a security control works if you can't see the traffic. Putting monitoring *first* means every subsequent layer emits telemetry from the moment it's born — no retrofitting, no blind spots during the interesting early failures.

**How it helps the customer:** Auditability. Every agent call, every allow, every block lands in a queryable log. "Show me every call this agent made last Tuesday" becomes a query, not a shrug.

### Step 3 — Deploy the private backend API *(the thing worth protecting)*

**What I built:** A serverless function that returns the business data the agent needs — in the demo, a mock customer record with a risk score and recent transactions. Its **public network access is turned off**; it is reachable only through a **private endpoint** from inside the VNet. It authenticates to its own storage with a **managed identity** (no connection strings, no keys sitting in config).

**Why it's built this way:** This is the crown jewel — the sensitive data the whole perimeter exists to protect. By disabling public access entirely, I remove the single most common mistake: an internet-reachable API "protected" only by a key. Even if an attacker learned the backend's exact hostname, hitting it from the public internet returns **403 Forbidden**. There's no front door on the street; the only door is inside the building.

**How it helps the customer:** Defense in depth. The data isn't safe *because* of one control — it's safe because it's off the internet, behind a private endpoint, and only reachable through a governed gateway. Remove any one control and the others still hold.

### Step 4 — Put Azure API Management in front *(the "what can it call, and can I see it" answer)*

**What I built:** An API Management instance injected into the VNet — public gateway on the front, private backend on the back. I published exactly one API through it (the customer-lookup call) and attached policies that every request must pass:
- **Authentication** — a subscription key (OAuth in production) enforced at the gateway.
- **Rate limiting** — an abusive burst of calls is throttled.
- **Request validation** — a malformed or injection-style id (e.g., someone trying `'; DROP` tricks) is rejected *at the gateway* and **never reaches the backend**.
- **Logging** — every call is recorded to Application Insights.

**Why it's built this way:** A perimeter needs a single, well-lit chokepoint where policy is enforced and everything is observed. Scattering auth and validation across many services means many places to get it wrong. One gateway means one place to enforce, one place to audit, and one place to change the rules for everyone at once.

**How it helps the customer:** This is the answer to "what is the agent allowed to do?" — precisely one operation, with auth, throttling, input validation, and a complete audit trail. If the agent tries anything else, there's simply no route for it.

### Step 5 — Bring Azure AI Foundry inside the same perimeter *(agent-level isolation)*

**What I built:** A Foundry account and project deployed **VNet-injected**, with a language model deployed for the agent to reason with. Critically, *all of the agent's state* lives in **customer-owned, private** resources: conversation threads in **Cosmos DB**, vector data in **AI Search**, files in **Storage** — every one of them with local/key auth disabled, locked to **managed-identity RBAC**, and network access set to private (Cosmos and Search fully disabled from the public internet; storage locked to an Azure-services-only bypass). The Foundry account itself is firewalled to a single allowed IP. And the agent's *one* external tool points at the **same API Management endpoint** as the Copilot Studio connector.

**Why it's built this way:** A Foundry agent's memory *is* sensitive data — the transcripts, the retrieved documents, the uploaded files. If that lives in a Microsoft-managed multi-tenant store, the customer has to trust a boundary they can't see. By making all of it customer-owned and private, the data never leaves the tenant, there are no shared secrets to leak, and access is governed by identity, not by a key someone might paste into a chat message.

**How it helps the customer:** The pro-code agent platform inherits the *exact same* guarantees as the low-code one. A customer doesn't have to run two different security reviews for two different agent stacks — the perimeter, the egress control, and the audit story are identical.

---

## The honest caveat: Copilot Studio is SaaS

I want to say this part plainly, because glossing over it is how you lose a security audience: **you cannot force Copilot Studio's own outbound traffic through your VNet.** It's a software-as-a-service platform. Being clear about that boundary is what makes the rest of the story credible.

So for the Copilot Studio hop, the governance is applied where you *can* apply it:
- a **custom connector locked to the API Management host** — no generic "call any HTTP endpoint" action is allowed,
- a Power Platform **Data Loss Prevention (DLP) policy** that allow-lists *only* that connector and blocks everything else,
- and the **subscription key** enforced at the gateway.

The VNet and private-endpoint egress control then applies from **API Management inward** — which is exactly where the sensitive data lives. The agent can only speak to your gateway, and your gateway is the mouth of a private, deny-by-default network. That's the honest, defensible line: SaaS-appropriate controls on the SaaS hop, hard network isolation everywhere the data actually sits.

---

## Proof, not promises

A security demo is only worth something if it can *show the blocks*, not just the happy path. So I validated every scenario end-to-end, and I get the same results on **both** agent platforms:

| Scenario | Result | What it proves |
|---|---|---|
| ✅ Agent calls the approved API through the gateway (with key) | **200** + data | The intended path works |
| ❌ Missing or invalid key | **401 Unauthorized** | Auth is enforced at the gateway |
| ❌ Invalid / injection-style id | **400 Bad Request** | Input is validated before the backend |
| ❌ Undefined route / a different external API | **404 Not Found** | No connector exists for anything else |
| ❌ Direct call to the backend, bypassing the gateway | **403 Forbidden** | The backend is private-only |
| ❌ Abusive burst of calls | **429 Too Many Requests** | Rate limiting protects the backend |

That table is the whole point. One perimeter, two agent stacks, identical guarantees — and every guarantee is demonstrated with a real status code, not asserted on a slide.

---

## A few hard-won lessons from the build

Things I'd tell my past self before starting:

- **Landing-zone guardrails will surprise you.** Deploying into a governed platform subscription meant org policies *mutated my resources after I created them* — a DDoS plan auto-attached and blocked VNet creation; IP tags got stamped onto a public IP and forced a replacement. The lesson: *expect* that drift. Scope policy exemptions narrowly and tell your infrastructure code to ignore the specific fields the platform manages.
- **Serverless + private networking has sharp edges.** Once you turn public access off, some deployment and key-management paths behave differently. The most robust pattern I landed on: keep the backend **anonymous but network-isolated**, and enforce *all* client authentication at the gateway. There's no shared secret to leak, and the network is the hard boundary.
- **Model availability moves under you.** "Deploy this specific model version" quietly stopped working for *new* deployments as the model aged out. Always query the currently available models for your region instead of hard-coding a version.
- **Write the "why" down as you go.** I kept a running decision log — every choice, every gotcha, every validation result. It doubled as the customer-facing narrative when it came time to explain the environment. The reasoning is worth more than the resource list.

---

## The takeaway for customers

If your security team is nervous about AI agents, you do **not** have to choose between "ship fast" and "stay safe." The pattern here is deliberately boring, proven enterprise plumbing applied to a new kind of workload:

- **VNet + private endpoints** control *where data can go* — deny by default.
- **API Management** controls *what the agent can do* — one governed operation, fully audited.
- **Connector allow-listing + DLP** (for Copilot Studio) and **managed-identity RBAC** (for Foundry) control *the agent itself* — no generic actions, no shared secrets.
- **Everything is provable** — every block returns a real status code you can demonstrate.

One governed perimeter. Two agent platforms. Zero uncontrolled egress. That's a security story a customer can actually approve — because they can test it themselves.

*Happy to walk any team through the architecture and the build notes — this is exactly the conversation more enterprises should be having before their agents go live.*

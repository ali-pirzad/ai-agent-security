# LinkedIn post — draft

> Paste into LinkedIn (Start a post). ~230 words. Swap in a screenshot of the architecture
> diagram (docs/architecture.html) as the image for best reach.

---

Every security team I talk to has the same three questions about AI agents:

1) Where can the agent send data?
2) What is it actually allowed to call?
3) How do we know it can't wander off-script?

So I built a demo that answers all three — with something you can *test*, not just slides.

The idea: put **both** Microsoft Copilot Studio and Azure AI Foundry agents behind the **same** Zero-Trust perimeter, so the security story is identical no matter which platform a team ships on.

The whole thing in one line:
**Agent → approved connector → Azure API Management → VNet / private endpoint → private backend.**

Everything past API Management lives in a virtual network with no public access and deny-by-default egress. The agent's only external capability is one approved API — it literally can't express a call to anything else.

The proof is the fun part. Same matrix on both platforms:
✅ Approved call → 200
❌ No key → 401
❌ Bad/injection input → 400 (blocked at the gateway)
❌ External API → 404 (no connector)
❌ Bypass the gateway → 403 (private only)
❌ Abuse it → 429 (rate limit)

One honest caveat I always call out: Copilot Studio is SaaS, so you can't VNet-force its outbound — you govern that hop with connector allow-listing + DLP + the gateway key. Saying that out loud is what makes the rest credible.

One governed perimeter. Two agent stacks. Zero uncontrolled egress.

#AI #AgentSecurity #ZeroTrust #Azure #CopilotStudio #AIFoundry #APIManagement #CyberSecurity

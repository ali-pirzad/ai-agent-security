const { app } = require('@azure/functions');

/**
 * Deterministic mock customer record generator.
 * Returns stable data for a given id so demo runs are repeatable.
 */
function buildCustomer(id) {
  // Simple deterministic hash from the id string.
  let hash = 0;
  for (let i = 0; i < id.length; i++) {
    hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
  }

  const riskScore = hash % 100; // 0-99
  const txCount = (hash % 4) + 1; // 1-4 transactions
  const categories = ['groceries', 'travel', 'electronics', 'dining', 'utilities'];

  const transactions = Array.from({ length: txCount }, (_, i) => {
    const seed = (hash + i * 97) >>> 0;
    return {
      id: `tx-${id}-${i + 1}`,
      amount: Number(((seed % 50000) / 100).toFixed(2)),
      currency: 'USD',
      category: categories[seed % categories.length],
      date: new Date(Date.UTC(2026, seed % 12, (seed % 27) + 1)).toISOString().slice(0, 10)
    };
  });

  return {
    customerId: id,
    riskScore,
    riskTier: riskScore >= 70 ? 'high' : riskScore >= 40 ? 'medium' : 'low',
    transactions
  };
}

app.http('root', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: '',
  handler: async (_request, context) => {
    context.log('root welcome requested');
    return {
      jsonBody: {
        message: 'Welcome to Azure Agents Security',
        service: 'customer-api',
        endpoints: {
          customer: 'GET /customer/{id} (via APIM, requires subscription key)'
        }
      }
    };
  }
});

app.http('customer', {
  methods: ['GET'],
  // Anonymous at the function: the backend has no public endpoint and is reachable
  // only from APIM inside the VNet via its private endpoint. Client auth is enforced
  // at APIM (subscription key). No shared secret to leak or rotate.
  authLevel: 'anonymous',
  route: 'customer/{id}',
  handler: async (request, context) => {
    const id = request.params.id;
    context.log(`customer lookup requested for id=${id}`);

    if (!id || !/^[A-Za-z0-9-]{1,64}$/.test(id)) {
      return {
        status: 400,
        jsonBody: { error: 'Invalid customer id. Expected 1-64 alphanumeric or hyphen characters.' }
      };
    }

    return { jsonBody: buildCustomer(id) };
  }
});

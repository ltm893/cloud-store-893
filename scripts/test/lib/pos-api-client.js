'use strict';

class CookieJar {
  constructor() {
    this.cookies = new Map();
  }

  ingest(response) {
    const setCookie = typeof response.headers.getSetCookie === 'function'
      ? response.headers.getSetCookie()
      : [];
    for (const line of setCookie) {
      const [pair] = line.split(';');
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      const name = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      this.cookies.set(name, value);
    }
  }

  header() {
    return [...this.cookies.entries()].map(([name, value]) => `${name}=${value}`).join('; ');
  }
}

async function api(jar, baseUrl, method, path, body) {
  const headers = { Accept: 'application/json' };
  const cookie = jar.header();
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  let res;
  try {
    res = await fetch(`${baseUrl}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (cause) {
    const detail = cause?.code || cause?.message || String(cause);
    const err = new Error(
      `${method} ${path} → fetch failed (${detail}); is the dev server running at ${baseUrl}? (npm run dev:up)`,
    );
    err.cause = cause;
    throw err;
  }
  jar.ingest(res);

  const text = await res.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const msg = (data && typeof data === 'object' && data.error) ? data.error : text || res.statusText;
    const err = new Error(`${method} ${path} → ${res.status}: ${msg}`);
    err.status = res.status;
    err.body = data;
    throw err;
  }

  return data;
}

async function approvePendingLogin(adminJar, baseUrl, requestToken, adminPin) {
  await api(adminJar, baseUrl, 'POST', '/api/admin/login', { pin: adminPin });
  await api(
    adminJar,
    baseUrl,
    'POST',
    `/api/admin/login-approvals/${encodeURIComponent(requestToken)}/approve`,
    {},
  );
}

async function openTill(jar, baseUrl, { cashMode, adminPin, openingFloat }, log) {
  const body = cashMode === 'credit_only'
    ? { cashMode: 'credit_only' }
    : {
      cashMode: 'cash_and_credit',
      countedTotal: openingFloat,
      denominations: { 20: Math.round(openingFloat / 20) },
    };

  if (log) log(`opening till (${cashMode})`);
  const tillResult = await api(jar, baseUrl, 'POST', '/api/cashier/approval/till', body);

  if (tillResult?.pending && tillResult?.requestToken) {
    if (log) log('supervisor approval — auto-approving');
    const adminJar = new CookieJar();
    await approvePendingLogin(adminJar, baseUrl, tillResult.requestToken, adminPin);
    const status = await api(jar, baseUrl, 'GET', '/api/cashier/approval/status');
    if (!status?.ok) {
      throw new Error('Supervisor approval completed but cashier session was not issued');
    }
    return status;
  }

  return tillResult;
}

async function signInCashier(jar, baseUrl, {
  pin,
  adminPin,
  registerId,
  cashMode,
  openingFloat,
}, log) {
  let session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  if (session?.ok) {
    if (log) log('cashier session already active');
    return session;
  }

  if (session?.awaitingTill) {
    await openTill(jar, baseUrl, { cashMode, adminPin, openingFloat }, log);
    session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
    if (session?.ok) return session;
    throw new Error('Till open submitted but cashier session is still not active');
  }

  if (session?.supervisorApprovalRequired && !session?.pinAllowed) {
    throw new Error('PIN unlock disabled; Oracle sign-in required');
  }

  if (log) log('PIN unlock');
  await api(jar, baseUrl, 'POST', '/api/cashier/unlock', {
    pin,
    clientKind: 'tablet',
    registerId,
  });

  session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  if (session?.ok) return session;

  if (session?.awaitingTill || session?.cashTillEnabled) {
    await openTill(jar, baseUrl, { cashMode, adminPin, openingFloat }, log);
    session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  }

  if (!session?.ok) {
    throw new Error('Cashier session not active after unlock and till open');
  }
  return session;
}

async function signOffCashier(jar, baseUrl, registerId, log) {
  if (log) log(`sign-off register ${registerId}`);
  await api(jar, baseUrl, 'POST', '/api/cashier/sign-off', { registerId });
}

async function clearCart(jar, baseUrl) {
  const cart = await api(jar, baseUrl, 'GET', '/api/cart');
  const items = Array.isArray(cart?.items) ? cart.items : [];
  for (const item of items) {
    await api(jar, baseUrl, 'DELETE', `/api/cart/${item.id}`);
  }
}

async function addCartLine(jar, baseUrl, productId, quantity = 1) {
  await api(jar, baseUrl, 'POST', '/api/cart', { productId, quantity });
}

async function fetchCartPreview(jar, baseUrl, customerId) {
  const path = customerId != null
    ? `/api/cart?customerId=${encodeURIComponent(customerId)}`
    : '/api/cart';
  return api(jar, baseUrl, 'GET', path);
}

async function checkout(jar, baseUrl, body) {
  return api(jar, baseUrl, 'POST', '/api/checkout', body);
}

module.exports = {
  CookieJar,
  api,
  signInCashier,
  signOffCashier,
  clearCart,
  addCartLine,
  fetchCartPreview,
  checkout,
};

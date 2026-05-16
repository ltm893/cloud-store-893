function cashierPin() {
  return String(process.env.CASHIER_PIN || '8930').trim();
}

function registerCashierAuth(app) {
  app.post('/api/cashier/unlock', (req, res) => {
    const pin = String(req.body?.pin ?? '').trim();
    if (!pin || pin !== cashierPin()) {
      return res.status(401).json({ error: 'Invalid PIN' });
    }
    return res.json({ ok: true });
  });
}

module.exports = { cashierPin, registerCashierAuth };

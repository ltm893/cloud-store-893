const { asyncHandler } = require('./async-handler');
const { buildSystemsStatus } = require('./systems-status');

function registerSystemsRoutes(app) {
  app.get(
    '/api/systems',
    asyncHandler(async (req, res) => {
      const status = await buildSystemsStatus({ requestHost: req.get('host') });
      res.json(status);
    }),
  );
}

module.exports = { registerSystemsRoutes };

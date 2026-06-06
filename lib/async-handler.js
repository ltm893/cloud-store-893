'use strict';

/** Wrap async Express handlers — log and return JSON on uncaught errors. */
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch((err) => {
      console.error(err.message);
      const status = Number(err?.status) || 500;
      const body = { error: err?.message || 'Request failed' };
      if (err?.code) body.code = err.code;
      res.status(status).json(body);
    });
  };
}

module.exports = { asyncHandler };

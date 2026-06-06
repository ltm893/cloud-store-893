'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { sendApprovalError } = require('../lib/approval-errors');

function mockRes() {
  let statusCode = 200;
  let body = null;
  return {
    status(code) {
      statusCode = code;
      return this;
    },
    json(payload) {
      body = payload;
      return this;
    },
    get statusCode() {
      return statusCode;
    },
    get body() {
      return body;
    },
  };
}

test('sendApprovalError uses err.status and message', () => {
  const res = mockRes();
  sendApprovalError(res, { status: 403, message: 'Forbidden', code: 'DENIED' });
  assert.equal(res.statusCode, 403);
  assert.deepEqual(res.body, { error: 'Forbidden', code: 'DENIED' });
});

test('sendApprovalError defaults to 500', () => {
  const res = mockRes();
  sendApprovalError(res, {});
  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, { error: 'Request failed' });
});

const { POS_STATUS } = require('./pos-sessions');

const MSG_FORCE_CLOSED =
  'This till was closed by a supervisor. Sign out and start a new shift to continue selling.';
const MSG_TILL_CLOSED = 'This till is closed. Sign out to continue.';
const MSG_SESSION_ENDED = 'This register session has ended. Sign out to continue.';

function createTillSaleGuard({ tillStore, posSessionStore, shiftCloseStore, getActiveCashierSession }) {
  async function wasForceClosed(tillId) {
    if (!shiftCloseStore?.findLatestForTill) return false;
    const latest = await shiftCloseStore.findLatestForTill(tillId);
    return latest?.status === shiftCloseStore.STATUS?.FORCE_CLOSED;
  }

  async function evaluate(session) {
    if (!session) {
      return {
        ok: false,
        error: 'Cashier sign-in required',
        status: 401,
        code: 'AUTH_REQUIRED',
        tillClosedBySupervisor: false,
      };
    }

    const tillId = session.tillId ?? session.shiftId;
    if (!tillId) {
      return {
        ok: false,
        error: 'No active till',
        status: 403,
        code: 'NO_TILL',
        tillClosedBySupervisor: false,
      };
    }

    const forceClosed = await wasForceClosed(tillId);
    const till = await tillStore.getTillById(tillId);

    if (!till || till.status === 'closed') {
      return {
        ok: false,
        error: forceClosed ? MSG_FORCE_CLOSED : MSG_TILL_CLOSED,
        status: 403,
        code: forceClosed ? 'TILL_FORCE_CLOSED' : 'TILL_CLOSED',
        tillClosedBySupervisor: forceClosed,
      };
    }

    if (session.posSessionId && posSessionStore) {
      const pos = await posSessionStore.getById(session.posSessionId);
      if (!pos || pos.status === POS_STATUS.ENDED) {
        return {
          ok: false,
          error: forceClosed ? MSG_FORCE_CLOSED : MSG_SESSION_ENDED,
          status: 403,
          code: forceClosed ? 'TILL_FORCE_CLOSED' : 'POS_SESSION_ENDED',
          tillClosedBySupervisor: forceClosed,
        };
      }
    }

    return { ok: true, tillClosedBySupervisor: false };
  }

  async function assertOpenForSale(req) {
    const session = getActiveCashierSession(req);
    return evaluate(session);
  }

  async function sessionFlags(session) {
    const result = await evaluate(session);
    if (result.ok) {
      return {
        tillOpenForSales: true,
        tillClosedBySupervisor: false,
        saleBlockedMessage: null,
        saleBlockedCode: null,
      };
    }
    return {
      tillOpenForSales: false,
      tillClosedBySupervisor: Boolean(result.tillClosedBySupervisor),
      saleBlockedMessage: result.error,
      saleBlockedCode: result.code,
    };
  }

  return {
    MSG_FORCE_CLOSED,
    assertOpenForSale,
    sessionFlags,
    evaluate,
  };
}

module.exports = {
  MSG_FORCE_CLOSED,
  MSG_TILL_CLOSED,
  MSG_SESSION_ENDED,
  createTillSaleGuard,
};

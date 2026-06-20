/**
 * Store client catalog for the Systems tab (static — matches repo apps).
 */
function getStoreClients() {
  return {
    register: {
      title: 'Cash register',
      summary: 'Front-of-store POS — open till, sell, take payment, close till.',
      clients: [
        {
          name: 'Android tablet',
          app: 'Cloud Store POS (native)',
          repo: 'android-pos/',
          notes: 'Samsung tablet at the register. PIN or Oracle sign-in, cart, split tender cash/card, till open and close, offline sale queue.',
        },
        {
          name: 'iPad',
          app: 'Cloud Store POS (native)',
          repo: 'ios-pos/',
          notes: 'Same register flows as Android. Barcode scan, supervisor approval, split tender, end-of-day till close.',
        },
      ],
    },
    admin: {
      title: 'Admin console',
      summary: 'Back office — catalog, inventory, reports, supervisor till approvals.',
      clients: [
        {
          name: 'Web',
          app: 'Admin UI (browser)',
          path: '/admin/',
          notes: 'Full admin in Chrome or Safari. Landscape on tablet and desktop; PIN or Oracle sign-in.',
        },
        {
          name: 'iPhone',
          app: 'Cloud Store Admin (iOS)',
          repo: 'ios-admin/',
          notes: 'Native shell loads /admin/ in a WebView. Portrait on phone; same tables, reports, and approvals as web.',
        },
        {
          name: 'Android',
          app: 'Admin UI (WebView or browser)',
          path: '/admin/',
          notes: 'Open Admin from the tablet POS menu, or browse /admin/ on the device. Same web admin as desktop.',
        },
      ],
    },
  };
}

module.exports = { getStoreClients };

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
    lister: {
      title: 'Inventory checker (Lister)',
      summary: 'Floor inventory lookup — search by product ID or barcode, manage pull lists, import/export CSV.',
      clients: [
        {
          name: 'iPhone / iPad',
          app: 'Cloud Store Lister (iOS)',
          repo: 'ios-lister/',
          notes: 'Oracle OIDC sign-in. Manual entry, barcode scan, product lookup, named lists, list operations (union, diff, split, sort, query), CSV import and share.',
        },
        {
          name: 'Android phone / tablet',
          app: 'Cloud Store Lister (Android)',
          repo: 'android-lister/',
          notes: 'Same Lister flows as iOS. Kotlin + Jetpack Compose; Oracle sign-in via WebView; barcode scan, lists, CSV import/export, list operations.',
        },
      ],
    },
  };
}

module.exports = { getStoreClients };

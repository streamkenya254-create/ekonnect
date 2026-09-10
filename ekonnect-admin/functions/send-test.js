/**
 * Sends one test push, exactly like the triggers do.
 *
 * The Firebase Console's "send test message" is not a valid test of this app:
 * it sends a `notification` payload, and this client is data-only. A console
 * message shows nothing in the foreground and cannot carry a deep link, so it
 * proves only that the device is reachable — not that the system works.
 *
 * Usage:
 *   1. Firebase Console → Project settings → Service accounts →
 *      "Generate new private key". Save it as functions/service-account.json.
 *      It is a credential: never commit it.
 *   2. cd functions && npm install
 *   3. node send-test.js <FCM_TOKEN> [approval|incident|status]
 *
 * The token is printed by the app on launch in debug: look for "FCM TOKEN:"
 * in the `flutter run` output.
 */

const admin = require('firebase-admin')
const path = require('path')

const KEY = path.join(__dirname, 'service-account.json')

let credential
try {
  credential = admin.credential.cert(require(KEY))
} catch {
  console.error(
    `\nNo service account at ${KEY}\n` +
    'Firebase Console → Project settings → Service accounts → ' +
    'Generate new private key, and save it there.\n',
  )
  process.exit(1)
}

admin.initializeApp({ credential })

const token = process.argv[2]
const kind = process.argv[3] || 'approval'

if (!token) {
  console.error('\nUsage: node send-test.js <FCM_TOKEN> [approval|incident|status]\n')
  process.exit(1)
}

// The same shapes the triggers send, so a passing test means the real thing
// will render and route identically.
const payloads = {
  approval: {
    title: 'You are verified',
    body: 'Your credentials were approved. You can go on duty and start '
      + 'receiving emergencies.',
    route: '/profile',
    collapseId: 'test_approval',
  },
  incident: {
    title: 'Medical emergency',
    body: 'Test caller needs help. Tap to see the call.',
    route: '/responder/home',
    type: 'medical',
    collapseId: 'test_incident',
  },
  status: {
    title: 'Help is coming',
    body: 'A responder accepted your call.',
    route: '/user/sos',
    type: 'medical',
    collapseId: 'test_status',
  },
}

const data = payloads[kind]
if (!data) {
  console.error(`Unknown kind "${kind}". Use approval, incident or status.`)
  process.exit(1)
}

admin
  .messaging()
  .send({
    token,
    // Both halves — see the note in index.js.
    notification: { title: data.title, body: data.body },
    data,
    android: {
      priority: 'high',
      notification: { channelId: 'ekonnect_alerts', sound: 'default' },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: { aps: { sound: 'default' } },
    },
  })
  .then(id => console.log(`\nSent "${kind}" → ${id}\n`))
  .catch(err => {
    console.error(`\nFailed: ${err.code || err.message}`)
    if (String(err.code).includes('registration-token-not-registered')) {
      console.error('That token is dead — the app was reinstalled or signed '
        + 'out. Relaunch the app and copy the new one.\n')
    }
    process.exit(1)
  })

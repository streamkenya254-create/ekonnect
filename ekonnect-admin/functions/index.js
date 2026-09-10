/**
 * eKonnect push notifications.
 *
 * Everything that sends a push lives here, and nothing else can. FCM's v1 API
 * authenticates with a service account, which must never reach a phone or a
 * browser — so the app and the admin console are receive-only by design, and
 * these Firestore triggers are the only sender.
 *
 * Every message carries both a `notification` and a `data` block. Android does
 * not display a data-only message at all, so data-only alerts vanished
 * whenever the app was backgrounded or killed — precisely when a crew needs
 * them. The notification half is what the OS draws then; the data half carries
 * the deep link and is what FCMService draws from in the foreground, where FCM
 * suppresses the OS banner so the two never double up.
 */

const { onDocumentUpdated, onDocumentCreated } =
  require('firebase-functions/v2/firestore')
const { setGlobalOptions } = require('firebase-functions/v2')
const admin = require('firebase-admin')

admin.initializeApp()
const db = admin.firestore()

// Kenya-facing product: keep the round trip short.
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 })

// ── Sending ────────────────────────────────────────────────────────────────

/**
 * Sends to one user's device, by uid.
 *
 * Silently does nothing when they have no token — a responder who has never
 * opened the app is not an error worth failing a trigger over. A token that
 * Firebase reports as dead is cleared, so it is not retried forever.
 */
async function pushToUser(uid, data) {
  if (!uid) return
  const snap = await db.collection('users').doc(uid).get()
  const token = snap.exists ? snap.data().fcmToken : null
  if (!token) {
    console.log(`no token for ${uid}; skipping`)
    return
  }
  await pushToTokens([{ uid, token }], data)
}

/** Sends the same message to many devices, pruning the dead tokens. */
async function pushToTokens(targets, data) {
  if (!targets.length) return

  // Every value must be a string: FCM data payloads carry no other type.
  const payload = {}
  for (const [k, v] of Object.entries(data)) {
    if (v !== null && v !== undefined) payload[k] = String(v)
  }

  // Both halves, deliberately:
  //
  //   notification — Android will not display a data-only message at all, so
  //     without this nothing appears when the app is backgrounded or killed,
  //     which is exactly when a crew needs the alert.
  //   data — carries the deep link, and is what the foreground handler draws
  //     from. FCM suppresses the OS banner while the app is in the
  //     foreground, so the two never double up.
  const res = await admin.messaging().sendEach(
    targets.map(t => ({
      token: t.token,
      notification: { title: payload.title, body: payload.body },
      data: payload,
      android: {
        priority: 'high',
        notification: { channelId: 'ekonnect_alerts', sound: 'default' },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    })),
  )

  const dead = []
  res.responses.forEach((r, i) => {
    if (r.success) return
    const code = r.error && r.error.code
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      dead.push(targets[i].uid)
    } else {
      console.error(`send failed for ${targets[i].uid}:`, code)
    }
  })

  // Keep a copy for the in-app Notifications page. Written for every target,
  // including any whose send failed: the message was still addressed to them,
  // and a dead token is exactly when the kept copy matters most.
  const now = admin.firestore.FieldValue.serverTimestamp();
  const records = db.batch();
  for (const t of targets) {
    records.set(db.collection('notifications').doc(), {
      userId: t.uid,
      title: payload.title || '',
      body: payload.body || '',
      route: payload.route || '',
      incidentId: payload.incidentId || null,
      type: payload.type || null,
      read: false,
      createdAt: now,
    });
  }
  await records.commit().catch(e => console.error('record write failed:', e))

  // A stale token belongs to an uninstalled app or a signed-out device.
  await Promise.all(
    dead.map(uid =>
      db.collection('users').doc(uid).update({ fcmToken: null }).catch(() => {}),
    ),
  )
  console.log(`sent ${res.successCount}/${targets.length}, pruned ${dead.length}`)
}

// ── Approvals: admin → responder ───────────────────────────────────────────

/**
 * A responder's verification decision.
 *
 * This is the notification the product most obviously lacked: an admin
 * verifies someone in the console and, until they happened to reopen the app
 * and try to go on duty, they had no idea.
 */
exports.onResponderDecision = onDocumentUpdated('users/{uid}', async event => {
  const before = event.data.before.data()
  const after = event.data.after.data()
  if (before.verificationStatus === after.verificationStatus) return

  const note = (after.verificationNote || '').trim()
  const messages = {
    verified: {
      title: 'You are verified',
      body: 'Your credentials were approved. You can go on duty and start '
        + 'receiving emergencies.',
    },
    rejected: {
      title: 'Application not approved',
      body: note || 'Your responder application was not approved. Contact '
        + 'your organisation for details.',
    },
    suspended: {
      title: 'Responder access suspended',
      body: note || 'Your access has been withdrawn. Contact your '
        + 'organisation to restore it.',
    },
  }

  const m = messages[after.verificationStatus]
  if (!m) return // back to pending, or a field we do not announce

  await pushToUser(event.params.uid, {
    ...m,
    route: '/profile',
    collapseId: `verification_${event.params.uid}`,
  })
})

/**
 * A client's cover, once a Care Point confirms payment.
 *
 * Registering is free and instant; cover starts when the facility writes the
 * dates. The person waiting has no other way to learn that happened.
 */
exports.onCoverConfirmed = onDocumentUpdated(
  'subscriptions/{id}',
  async event => {
    const before = event.data.before.data()
    const after = event.data.after.data()

    const had = before.expiresAt ? before.expiresAt.toMillis() : 0
    const has = after.expiresAt ? after.expiresAt.toMillis() : 0
    if (has <= had) return // no new cover granted

    const until = after.expiresAt.toDate().toLocaleDateString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric',
    })
    await pushToUser(after.userId, {
      title: 'Your cover is active',
      body: `${after.teamName || 'Your provider'} confirmed your payment. `
        + `You are covered until ${until}.`,
      route: '/my-providers',
      collapseId: `cover_${event.params.id}`,
    })
  },
)

// ── Dispatch: a new emergency → eligible responders ────────────────────────

/**
 * Fans a new SOS out to the crews allowed to take it.
 *
 * Without this a responder only sees an emergency while the app is open and
 * on screen — which is not how anyone waits for a call. The routing rules are
 * the same ones the app applies client-side: a private call goes only to that
 * Care Point, and practitioners never receive non-medical work.
 */
exports.onIncidentCreated = onDocumentCreated(
  'incidents/{id}',
  async event => {
    const incident = event.data.data()
    if (incident.status !== 'pending') return

    const crews = await db
      .collection('users')
      .where('isAvailable', '==', true)
      .get()

    const targets = []
    for (const doc of crews.docs) {
      const u = doc.data()
      if (doc.id === incident.userId) continue
      if (!u.fcmToken) continue
      if (u.role !== 'ambulance' && u.role !== 'practitioner') continue
      if (u.verificationStatus !== 'verified') continue
      // Practitioners are medical only.
      if (u.role === 'practitioner' && incident.type !== 'medical') continue

      // A privately routed call belongs to one Care Point for its first
      // window; everyone else is told when it opens up.
      if (incident.routingScope === 'private') {
        if (u.teamId !== incident.routedTeamId) continue
      } else if (u.visibility === 'private' || u.visibility === 'clients') {
        // Exclusive crews never join the open network.
        continue
      }

      targets.push({ uid: doc.id, token: u.fcmToken })
    }

    const labels = {
      medical: 'Medical emergency',
      fire: 'Fire incident',
      flood: 'Flood / disaster',
      security: 'Security / police',
    }

    await pushToTokens(targets, {
      title: labels[incident.type] || 'Emergency',
      body: incident.userName
        ? `${incident.userName} needs help. Tap to see the call.`
        : 'A new emergency is waiting for a crew.',
      route: '/responder/home',
      incidentId: event.params.id,
      type: incident.type,
      collapseId: `incident_${event.params.id}`,
    })
  },
)

// ── Job updates: responder → patient ───────────────────────────────────────

/** Tells the caller what is happening to their emergency. */
exports.onIncidentStatus = onDocumentUpdated('incidents/{id}', async event => {
  const before = event.data.before.data()
  const after = event.data.after.data()
  if (before.status === after.status) return

  const who = after.assignedToName || 'A responder'
  const messages = {
    assigned: { title: 'Help is coming', body: `${who} accepted your call.` },
    en_route: { title: 'On the way', body: `${who} is travelling to you.` },
    arrived: { title: 'They have arrived', body: `${who} is at your location.` },
    resolved: {
      title: 'Emergency closed',
      body: 'Your call has been marked resolved. You can rate the response.',
    },
    closed_unresolved: {
      title: 'Closed without resolving',
      body: after.closedReason || 'The crew could not complete this job.',
    },
    cancelled: {
      title: 'Emergency cancelled',
      body: after.cancelledBy === 'responder'
        ? 'The responder cancelled. Your call is being sent out again.'
        : 'Your emergency was cancelled.',
    },
  }

  const m = messages[after.status]
  if (!m) return

  await pushToUser(after.userId, {
    ...m,
    route: '/user/sos',
    incidentId: event.params.id,
    type: after.type,
    collapseId: `incident_${event.params.id}`,
  })

  // A crew that asked for backup needs to know when someone joins.
  if (after.status === 'assigned' && after.backupRequested) {
    await pushToUser(after.assignedTo, {
      title: 'Backup joined',
      body: 'Another crew is on the way to assist.',
      route: '/responder/active',
      incidentId: event.params.id,
      collapseId: `backup_${event.params.id}`,
    })
  }
})

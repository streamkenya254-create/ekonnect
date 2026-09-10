/**
 * Hand-sent invitations.
 *
 * Firebase's own email is the only one this project can send, and its template
 * is locked ("Email template updates are currently unavailable for this
 * project"), so what lands in someone's inbox is a bare password-reset notice
 * with no mention of eKonnect's portal, no instructions and nothing naming
 * their facility. To an invited hospital administrator that reads like spam.
 *
 * So the console composes the letter that email cannot be, and an
 * administrator forwards it themselves. The two arrive together: Firebase's
 * link sets the password, this explains what it is for.
 *
 * When a real email provider is wired up, this same copy becomes the template
 * body and the forwarding step disappears.
 */

const SITE = 'https://ekonnectapp.web.app'

/** The stock Firebase subject, quoted so people can search their inbox. */
const FIREBASE_SUBJECT = 'Reset your password for ekonnect'
const FIREBASE_SENDER = 'noreply@ekonnectapp.firebaseapp.com'

export function buildCarePointInvite({ name, email, facility }) {
  const who = firstName(name)
  return {
    subject: `Your eKonnect portal is ready — ${facility}`,
    body: [
      `Hello${who ? ` ${who}` : ''},`,
      ``,
      `${facility} has been verified on eKonnect, and your Care Point portal is ready.`,
      ``,
      `Getting in takes two steps:`,
      ``,
      `1. Set your password.`,
      `   Look in your inbox for an email from ${FIREBASE_SENDER}`,
      `   with the subject "${FIREBASE_SUBJECT}". Open the link inside it and`,
      `   choose a password. Check your spam folder if it is not there — or go to`,
      `   ${SITE}/login and use "Forgot password".`,
      ``,
      `2. Sign in.`,
      `   ${SITE}/login`,
      `   Email: ${email}`,
      `   Password: the one you just set`,
      ``,
      `Once you are in, your portal lets you:`,
      `   • register your ambulances and other vehicles`,
      `   • submit your drivers and practitioners for verification`,
      `   • see at a glance which crews and vehicles are on duty`,
      `   • review every job your crews have answered`,
      ``,
      `Your crews will not receive emergencies until they are individually`,
      `verified — submit them from the Crew page and we will check their licences.`,
      ``,
      `Any trouble at all, just reply to this message.`,
      ``,
      `— The eKonnect team`,
      SITE,
    ].join('\n'),
  }
}

export function buildResponderInvite({ name, email, role, facility, licenseNumber, vehicleNumber }) {
  const who = firstName(name)
  const roleLabel = role === 'practitioner' ? 'medical practitioner' : 'ambulance driver'
  const details = [
    ['Role', roleLabel],
    ['Licence', licenseNumber],
    ['Vehicle', vehicleNumber],
    ['Care Point', facility],
  ].filter(([, v]) => v)

  return {
    subject: `You are approved on eKonnect${facility ? ` — ${facility}` : ''}`,
    body: [
      `Hello${who ? ` ${who}` : ''},`,
      ``,
      `Your eKonnect responder account has been approved${facility ? `, answering for ${facility}` : ''}.`,
      ``,
      `Three steps to start taking calls:`,
      ``,
      `1. Set your password.`,
      `   Look in your inbox for an email from ${FIREBASE_SENDER}`,
      `   with the subject "${FIREBASE_SUBJECT}". Open the link inside it and`,
      `   choose a password. Check spam if it is not there.`,
      ``,
      `2. Install the app.`,
      `   ${SITE}/#get  (Android)`,
      ``,
      `3. Sign in with ${email} and the password you set, then switch`,
      `   yourself on duty. You will only receive emergencies while on duty.`,
      ``,
      `What we have on file for you:`,
      ...details.map(([k, v]) => `   ${k}: ${v}`),
      ``,
      `If any of that is wrong, reply and we will correct it before you go out.`,
      ``,
      `— The eKonnect team`,
      SITE,
    ].join('\n'),
  }
}

function firstName(name) {
  return (name ?? '').trim().split(/\s+/)[0] ?? ''
}

/** Opens the administrator's own mail client with everything filled in. */
export function mailtoLink(to, { subject, body }) {
  return `mailto:${encodeURIComponent(to)}`
    + `?subject=${encodeURIComponent(subject)}`
    + `&body=${encodeURIComponent(body)}`
}

/**
 * WhatsApp is how most of this will actually get delivered in Kenya, so it is
 * a first-class option rather than an afterthought. wa.me wants digits only.
 */
export function whatsappLink(phone, { body }) {
  const digits = (phone ?? '').replace(/\D/g, '')
  if (!digits) return null
  return `https://wa.me/${digits}?text=${encodeURIComponent(body)}`
}

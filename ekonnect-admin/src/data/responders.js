/**
 * Responder applications.
 *
 * One queue, two doors. A responder either works for a Care Point or works
 * independently, and both apply through the same form and land in the same
 * `responderApplications` collection — an administrator reviewing licences
 * should not have to remember which of two lists to look in.
 *
 * Nobody is promoted into this role from an ordinary account any more. Being a
 * responder starts with an application carrying a licence number, because that
 * is the thing being verified.
 */

export const AFFILIATIONS = [
  {
    value: 'care_point',
    label: 'I work for a Care Point',
    sub: 'A hospital, clinic, ambulance service or station already on eKonnect',
  },
  {
    value: 'independent',
    label: 'I work independently',
    sub: 'Self-employed, volunteer, or your organisation is not on eKonnect yet',
  },
]

export const RESPONDER_ROLES = [
  { value: 'ambulance',    label: 'Ambulance driver',     sub: 'Drives and transports patients' },
  { value: 'practitioner', label: 'Medical practitioner', sub: 'Clinical care on scene' },
]

export function responderRoleLabel(r) {
  return RESPONDER_ROLES.find(x => x.value === r)?.label ?? r
}

export const APPLICATION_SOURCES = {
  public: 'public-form',   // applied themselves at /apply
  portal: 'care-point',    // submitted by a Care Point on their behalf
}

export const emptyResponderApplication = {
  affiliation: 'independent',
  teamId: '',
  teamName: '',
  name: '',
  email: '',
  phone: '',
  role: 'ambulance',
  licenseNumber: '',
  vehicleNumber: '',
  specialization: '',
  yearsExperience: '',
  county: '',
  note: '',
}

export function validateResponderApplication(a, step) {
  const all = {}

  if (!a.affiliation) all.affiliation = 'Choose how you work.'
  if (a.affiliation === 'care_point' && !a.teamId) {
    all.teamId = 'Choose the Care Point you work for.'
  }

  if (!a.name?.trim() || a.name.trim().length < 3) all.name = 'Give your full name.'

  // The email is the join between this application and the account they use in
  // the responder app. A wrong one silently strands them after approval.
  if (!a.email?.trim()) all.email = 'An email is required — it links this to your app account.'
  else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(a.email.trim())) all.email = 'That email does not look right.'

  if (!a.phone?.trim()) all.phone = 'A phone number is required.'
  else if (!/^\+?\d[\d\s-]{7,}$/.test(a.phone.trim())) all.phone = 'That does not look like a phone number.'

  if (!a.role) all.role = 'Choose what you do.'
  if (!a.licenseNumber?.trim()) {
    all.licenseNumber = 'A licence number is required — this is what gets verified.'
  }
  if (a.role === 'ambulance' && !a.vehicleNumber?.trim()) {
    all.vehicleNumber = 'Give the plate of the vehicle you drive.'
  }
  if (!a.county) all.county = 'Where do you mostly work?'

  if (step === undefined || step === null) return all
  return Object.fromEntries(
    Object.entries(all).filter(([k]) => APPLICATION_STEPS_FIELDS[step]?.includes(k)),
  )
}

export const APPLICATION_STEPS_FIELDS = {
  0: ['affiliation', 'teamId'],
  1: ['name', 'email', 'phone', 'county'],
  2: ['role', 'licenseNumber', 'vehicleNumber'],
}

export const APPLICATION_STEPS = [
  { title: 'Who you work for', sub: 'Care Point or independent' },
  { title: 'About you',        sub: 'How we reach you' },
  { title: 'Credentials',      sub: 'What gets verified' },
]

/** Human-readable state of an application, for both the admin and the portal. */
export function applicationState(a) {
  switch (a.status) {
    case 'approved':
      return { label: 'Approved', tone: 'good', sub: 'On the network and able to go on duty.' }
    case 'rejected':
      return { label: 'Not approved', tone: 'bad', sub: a.reviewNote || 'Contact eKonnect for details.' }
    case 'awaiting_signup':
      return {
        label: 'Waiting on them',
        tone: 'warn',
        sub: 'Approved, but they have not set their password yet.',
      }
    default:
      return { label: 'Under review', tone: 'warn', sub: 'An administrator is checking the licence.' }
  }
}

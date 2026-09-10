/**
 * Shared vocabulary for Care Points.
 *
 * A Care Point is a facility on the network — a hospital, clinic, fire station
 * or rescue service. It is both an employer of responders (a patient sees
 * "Ben · Ambulance driver · Oasis Hospital") and a place a crew can refer a
 * patient onward to.
 *
 * Lives in its own module because three surfaces need the same lists: the
 * admin console, the public registration form, and anything that renders a
 * facility badge. Two copies of this would drift within a week.
 *
 * Stored in the `teams` Firestore collection. The name changed; the collection
 * did not, because responder routing (`teamId`, `routedTeamId`) already keys
 * off it and a rename would orphan every existing responder.
 */

export const CARE_POINT_TYPES = [
  { value: 'hospital',      label: 'Hospital',         sub: 'Inpatient, theatre, A&E',      visitable: true },
  { value: 'clinic',        label: 'Clinic',           sub: 'Outpatient and day care',      visitable: true },
  { value: 'health_centre', label: 'Health centre',    sub: 'Level 3 / sub-county',         visitable: true },
  { value: 'dispensary',    label: 'Dispensary',       sub: 'Level 2 / primary care',       visitable: true },
  { value: 'ambulance',     label: 'Ambulance service', sub: 'Transport and pre-hospital',  visitable: false },
  { value: 'fire_station',  label: 'Fire station',     sub: 'Fire and rescue',              visitable: false },
  { value: 'police_post',   label: 'Police post',      sub: 'Security response',            visitable: false },
  { value: 'rescue',        label: 'Rescue service',   sub: 'Water, flood, disaster',       visitable: false },
]

export function typeLabel(value) {
  return CARE_POINT_TYPES.find(t => t.value === value)?.label ?? 'Care point'
}

/** Emergency categories a Care Point can answer. Matches the app's SOS types. */
export const INCIDENT_TYPES = [
  { value: 'medical',  label: 'Medical',  icon: '/assets/doctor.svg' },
  { value: 'fire',     label: 'Fire',     icon: '/assets/fire.svg' },
  { value: 'flood',    label: 'Flood',    icon: '/assets/flood.svg' },
  { value: 'security', label: 'Security', icon: '/assets/police.svg' },
]

/**
 * Suggested clinical and rescue capabilities.
 *
 * Offered as chips rather than free text because these are what a referring
 * crew searches on mid-incident — "who near me has a theatre right now" only
 * works if two hospitals spell theatre the same way. Operators can still add
 * their own; the list is a starting point, not a closed set.
 */
export const SERVICE_SUGGESTIONS = [
  'Accident & Emergency', 'Trauma surgery', 'Operating theatre', 'ICU / HDU',
  'Maternity', 'Paediatrics', 'Blood bank', 'X-ray', 'CT scan', 'Ultrasound',
  'Laboratory', 'Pharmacy', 'Dialysis', 'Burns unit', 'Snake bite antivenom',
  'Oxygen', 'Ambulance transport', 'Fire suppression', 'Water rescue',
  'Search & rescue', 'Hazmat',
]

export const VISIBILITY = [
  {
    value: 'public',
    label: 'Public network',
    sub: 'Answers any nearby emergency',
  },
  {
    value: 'private',
    label: 'Private clients',
    sub: 'Answers only its registered clients',
  },
]

export const ASSIGNMENT_MODES = [
  { value: 'first_accept', label: 'First to accept', sub: 'Fastest crew wins the call' },
  { value: 'auto_nearest', label: 'Auto nearest',    sub: 'System assigns the closest crew' },
]

export const COLORS = [
  '#3D1152', '#1B4080', '#E53935', '#2E7D32',
  '#FF8F00', '#7B1FA2', '#0097A7', '#37474F',
]

/** Kenyan counties, for the location step. */
export const COUNTIES = [
  'Baringo', 'Bomet', 'Bungoma', 'Busia', 'Elgeyo-Marakwet', 'Embu', 'Garissa',
  'Homa Bay', 'Isiolo', 'Kajiado', 'Kakamega', 'Kericho', 'Kiambu', 'Kilifi',
  'Kirinyaga', 'Kisii', 'Kisumu', 'Kitui', 'Kwale', 'Laikipia', 'Lamu',
  'Machakos', 'Makueni', 'Mandera', 'Marsabit', 'Meru', 'Migori', 'Mombasa',
  "Murang'a", 'Nairobi', 'Nakuru', 'Nandi', 'Narok', 'Nyamira', 'Nyandarua',
  'Nyeri', 'Samburu', 'Siaya', 'Taita-Taveta', 'Tana River', 'Tharaka-Nithi',
  'Trans Nzoia', 'Turkana', 'Uasin Gishu', 'Vihiga', 'Wajir', 'West Pokot',
]

/** A blank Care Point. `visibility` defaults to public — going private is a
 *  deliberate act, never something an operator falls into by omission. */
export const emptyCarePoint = {
  // Identity
  name: '',
  // Data URLs, downscaled in the browser — see components/ImagePicker.
  logo: '',
  coverImage: '',
  type: 'hospital',
  registrationNumber: '',
  description: '',
  color: '#3D1152',
  // Contact
  contactName: '',
  contactRole: '',
  contactPhone: '',
  dispatchPhone: '',
  email: '',
  // Location
  county: '',
  town: '',
  address: '',
  lat: '',
  lng: '',
  // Capability
  respondsTo: [],
  services: [],
  bedCapacity: '',
  ambulanceCount: '',
  open24Hours: true,
  acceptingCases: true,
  // Network
  visibility: 'public',
  assignmentMode: 'first_accept',
  // Cover — what a private Care Point charges its own subscribers. eKonnect
  // takes no money and processes no payment: these are shown to a subscriber
  // so they know how to pay the facility directly, and the facility sets the
  // cover dates here in the portal once it has been paid.
  coverPrice: '',
  coverDays: '',
  payBill: '',
  payAccount: '',
}

/**
 * Validation, shared by both forms so the public application and the admin
 * record cannot disagree about what a complete Care Point is.
 *
 * Returns `{ field: message }` for the fields in `step`, or every field when
 * `step` is omitted.
 */
export function validateCarePoint(cp, step) {
  const all = {}

  if (!cp.name?.trim()) all.name = 'Give the facility its registered name.'
  if (!cp.type) all.type = 'Choose a facility type.'
  if (!cp.description?.trim() || cp.description.trim().length < 40) {
    // The description is what the AI matches a referral against, so an empty
    // or one-word entry makes the facility effectively invisible to search.
    all.description = 'Describe the facility in at least 40 characters — this is what referral matching reads.'
  }

  if (!cp.contactPhone?.trim()) all.contactPhone = 'A contact phone is required.'
  else if (!/^\+?\d[\d\s-]{7,}$/.test(cp.contactPhone.trim())) {
    all.contactPhone = 'That does not look like a phone number.'
  }
  if (cp.email?.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cp.email.trim())) {
    all.email = 'That email address does not look right.'
  }

  if (!cp.county) all.county = 'Choose a county.'
  if (!cp.town?.trim()) all.town = 'Which town or ward?'

  const lat = parseFloat(cp.lat)
  const lng = parseFloat(cp.lng)
  if (cp.lat === '' || cp.lng === '' || Number.isNaN(lat) || Number.isNaN(lng)) {
    all.coords = 'Set the location — crews are routed to these coordinates.'
  } else if (lat < -5 || lat > 5.5 || lng < 33.5 || lng > 42.5) {
    // Kenya's bounding box. A transposed lat/lng sends an ambulance to the
    // wrong hemisphere, and it is far cheaper to catch here than at 3am.
    all.coords = 'Those coordinates are outside Kenya — check they are not swapped.'
  }

  if ((cp.respondsTo ?? []).length === 0) {
    all.respondsTo = 'Choose at least one emergency type, or this Care Point is never dispatched.'
  }

  // `step` is an index, and step 0 is falsy — testing `!step` here returned
  // every error on the first step, so Continue could never be satisfied while
  // the messages shown belonged to fields the operator could not see yet.
  if (step === undefined || step === null) return all
  return Object.fromEntries(
    Object.entries(all).filter(([k]) => STEP_FIELDS[step]?.includes(k)),
  )
}

/** Which fields each wizard step is responsible for. */
export const STEP_FIELDS = {
  0: ['name', 'type', 'description'],
  1: ['contactPhone', 'email'],
  2: ['county', 'town', 'coords'],
  3: ['respondsTo'],
  4: [],
}

export const STEPS = [
  { title: 'Facility',   sub: 'What this place is' },
  { title: 'Contact',    sub: 'Who answers the phone' },
  { title: 'Location',   sub: 'Where crews are sent' },
  { title: 'Capability', sub: 'What you can handle' },
  { title: 'Network',    sub: 'Who you answer for' },
]

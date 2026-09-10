/**
 * Vehicles and crew applications — the two things a Care Point owns and the
 * network administrator does not enter on their behalf.
 *
 * A vehicle is a first-class record in `vehicles`, keyed to a Care Point by
 * `teamId`. Duty state is *not* stored on it: a vehicle is on duty because a
 * verified responder carrying its plate is on duty, and duplicating that would
 * give two answers to one question. `vehicleDutyState` derives it instead.
 */

export const VEHICLE_TYPES = [
  { value: 'ambulance_bls', label: 'Ambulance · BLS', sub: 'Basic life support' },
  { value: 'ambulance_als', label: 'Ambulance · ALS', sub: 'Advanced life support' },
  { value: 'response_car',  label: 'Response car',    sub: 'First responder, no transport' },
  { value: 'fire_engine',   label: 'Fire engine',     sub: 'Fire and rescue' },
  { value: 'rescue_truck',  label: 'Rescue truck',    sub: 'Water, flood, extrication' },
  { value: 'motorcycle',    label: 'Motorcycle',      sub: 'Rapid access, no transport' },
]

export function vehicleTypeLabel(v) {
  return VEHICLE_TYPES.find(t => t.value === v)?.label ?? 'Vehicle'
}

/**
 * What a vehicle carries. A referring crew choosing between two ambulances
 * cares about this far more than the make and model, so it is ticked from a
 * shared list rather than typed — two facilities spelling "defibrillator"
 * differently makes the field unsearchable.
 */
export const VEHICLE_EQUIPMENT = [
  'Stretcher', 'Scoop stretcher', 'Spinal board', 'Wheelchair access',
  'Oxygen', 'Suction unit', 'Defibrillator', 'Cardiac monitor',
  'Ventilator', 'Infusion pump', 'Incubator', 'Trauma kit',
  'Burns kit', 'Maternity kit', 'Fire suppression', 'Extrication tools',
  'Water rescue gear', 'Air conditioning',
]

export const emptyVehicle = {
  plate: '',
  type: 'ambulance_bls',
  make: '',
  year: '',
  // Data URL, downscaled in the browser — see components/ImagePicker.
  photo: '',
  patientCapacity: '',
  crewCapacity: '',
  equipment: [],
  inService: true,
  notes: '',
}

export function validateVehicle(v) {
  const e = {}
  const plate = (v.plate ?? '').trim()
  if (!plate) e.plate = 'A number plate is required.'
  // Kenyan civilian plates are KXX 000X. Kept loose on purpose — government
  // and NGO fleets carry formats this would otherwise reject.
  else if (plate.length < 5 || plate.length > 12) e.plate = 'That does not look like a number plate.'
  if (!v.type) e.type = 'Choose a vehicle type.'
  if (v.year && !/^(19|20)\d{2}$/.test(String(v.year).trim())) e.year = 'Use a four-digit year.'
  for (const [k, label] of [['patientCapacity', 'Patient capacity'], ['crewCapacity', 'Crew seats']]) {
    const raw = String(v[k] ?? '').trim()
    if (raw && !/^\d{1,2}$/.test(raw)) e[k] = `${label} should be a whole number.`
  }
  return e
}

/**
 * What a vehicle is doing right now, worked out from the crew.
 *
 * `crew` is the Care Point's responders. A vehicle is matched to them by
 * plate, which is how the mobile app already records it (`vehicleNumber` on
 * the responder), so this reflects reality without asking anyone to keep a
 * second record up to date.
 */
export function vehicleDutyState(vehicle, crew) {
  if (vehicle.inService === false) {
    return { key: 'out_of_service', label: 'Out of service', tone: 'muted' }
  }
  const plate = normalisePlate(vehicle.plate)
  const assigned = crew.filter(c => normalisePlate(c.vehicleNumber) === plate)

  if (assigned.some(c => c.currentIncidentId)) {
    return { key: 'on_call', label: 'On a call', tone: 'busy', crew: assigned }
  }
  if (assigned.some(c => c.isAvailable && c.verificationStatus === 'verified')) {
    return { key: 'on_duty', label: 'On duty', tone: 'good', crew: assigned }
  }
  if (assigned.length > 0) {
    return { key: 'off_duty', label: 'Crew off duty', tone: 'idle', crew: assigned }
  }
  return { key: 'unstaffed', label: 'No crew assigned', tone: 'warn', crew: [] }
}

/** Plates get typed with and without spaces; compare them the same way. */
export function normalisePlate(p) {
  return (p ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')
}

/* ── Crew applications ─────────────────────────────────────────────────── */

export const CREW_ROLES = [
  { value: 'ambulance',    label: 'Ambulance driver',   sub: 'Drives and transports' },
  { value: 'practitioner', label: 'Medical practitioner', sub: 'Clinical care on scene' },
]

export function crewRoleLabel(r) {
  return CREW_ROLES.find(c => c.value === r)?.label ?? r
}

export const emptyCrewApplication = {
  name: '',
  email: '',
  phone: '',
  role: 'ambulance',
  licenseNumber: '',
  vehicleNumber: '',
  specialization: '',
}

export function validateCrewApplication(c) {
  const e = {}
  if (!c.name?.trim() || c.name.trim().length < 3) e.name = 'Give their full name.'
  if (!c.phone?.trim()) e.phone = 'A phone number is required.'
  else if (!/^\+?\d[\d\s-]{7,}$/.test(c.phone.trim())) e.phone = 'That does not look like a phone number.'
  // The email is how an approved application is matched to the account the
  // responder creates in the app, so a wrong one silently strands them.
  if (!c.email?.trim()) e.email = 'An email is required — it links them to their app account.'
  else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.email.trim())) e.email = 'That email does not look right.'
  if (!c.role) e.role = 'Choose a role.'
  if (c.role === 'practitioner' && !c.licenseNumber?.trim()) {
    e.licenseNumber = 'A practitioner needs a licence number to be verified.'
  }
  return e
}

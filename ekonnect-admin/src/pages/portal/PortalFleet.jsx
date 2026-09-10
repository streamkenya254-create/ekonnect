import { useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import {
  VEHICLE_TYPES, VEHICLE_EQUIPMENT, vehicleTypeLabel, emptyVehicle,
  validateVehicle, vehicleDutyState,
} from '../../data/fleet'
import ImagePicker from '../../components/ImagePicker'
import { withTimeout } from '../../utils/withTimeout'
import { DutyPill, Empty } from './PortalOverview'
import { IconPlus, IconEdit, IconTrash, IconX } from '../../components/Icons'

/**
 * The Care Point's vehicles.
 *
 * Registering one is entirely theirs to do — a plate is not something a
 * network administrator should be typing on a hospital's behalf. Duty state,
 * by contrast, is never entered here: it is read off the crew who carry the
 * plate, so it cannot drift from what dispatch actually sees.
 */
export default function PortalFleet() {
  const { vehicles, crew, saveVehicle, removeVehicle } = useOutletContext()
  const [editing, setEditing] = useState(null)

  const fleet = vehicles
    .map(v => ({ ...v, state: vehicleDutyState(v, crew) }))
    .sort((a, b) => a.plate.localeCompare(b.plate))

  const ready = fleet.filter(v => v.state.key === 'on_duty' || v.state.key === 'on_call').length
  const unstaffed = fleet.filter(v => v.state.key === 'unstaffed').length

  async function handleDelete(v) {
    if (!window.confirm(`Remove ${v.plate} from your fleet?`)) return
    await removeVehicle(v.id)
  }

  return (
    <div className="px-4 sm:px-8 lg:px-12 py-8">
      <div className="page-header">
        <div>
          <span className="eyebrow block mb-2">Fleet</span>
          <p className="page-subtitle max-w-xl">
            A vehicle shows as on duty when a verified crew member carrying its
            plate is on duty — so this always matches what dispatch sees.
          </p>
        </div>
        <button onClick={() => setEditing({ ...emptyVehicle })} className="btn-primary">
          <IconPlus className="w-4 h-4" /> Add vehicle
        </button>
      </div>

      {fleet.length > 0 && (
        <div className="grid sm:grid-cols-3 gap-4 mb-6">
          <MiniStat label="Registered" value={fleet.length} />
          <MiniStat label="Crewed and ready" value={ready} tone="good" />
          <MiniStat label="No crew assigned" value={unstaffed} tone={unstaffed ? 'warn' : undefined} />
        </div>
      )}

      {fleet.length === 0 ? (
        <div className="panel text-center py-16">
          <img src="/assets/ambulance.svg" alt="" className="w-14 h-14 mx-auto opacity-30" />
          <p className="font-semibold text-ink mt-5">No vehicles yet</p>
          <Empty>Add your ambulances, response cars or engines so crews can be matched to them.</Empty>
          <button onClick={() => setEditing({ ...emptyVehicle })} className="btn-primary mx-auto mt-6">
            <IconPlus className="w-4 h-4" /> Add your first vehicle
          </button>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {fleet.map(v => (
            <article key={v.id} className="panel !p-0 overflow-hidden">
              {v.photo && (
                <img src={v.photo} alt="" className="w-full h-36 object-cover" />
              )}
              <div className="p-6">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-mono font-bold text-xl tracking-tight text-ink">{v.plate}</p>
                  <p className="text-xs text-ink-mute mt-1">
                    {vehicleTypeLabel(v.type)}
                    {v.make && ` · ${v.make}`}
                    {v.year && ` · ${v.year}`}
                  </p>
                </div>
                <div className="flex gap-1 flex-shrink-0">
                  <button onClick={() => setEditing(v)} className="p-2 rounded-xl text-ink-mute hover:text-primary hover:bg-primary/[0.06] transition-colors">
                    <IconEdit />
                  </button>
                  <button onClick={() => handleDelete(v)} className="p-2 rounded-xl text-ink-mute hover:text-emergency hover:bg-emergency/[0.06] transition-colors">
                    <IconTrash />
                  </button>
                </div>
              </div>

              <div className="mt-5 pt-4 border-t border-ink/[0.07] flex items-center justify-between gap-3">
                <DutyPill state={v.state} />
                <span className="text-xs text-ink-mute truncate">
                  {v.state.crew?.length
                    ? v.state.crew.map(c => c.name).filter(Boolean).join(', ')
                    : 'Unassigned'}
                </span>
              </div>

              {(v.patientCapacity || v.crewCapacity) && (
                <p className="text-xs text-ink-mute mt-3">
                  {v.patientCapacity && `${v.patientCapacity} patient${v.patientCapacity === '1' ? '' : 's'}`}
                  {v.patientCapacity && v.crewCapacity && ' · '}
                  {v.crewCapacity && `${v.crewCapacity} crew seats`}
                </p>
              )}

              {(v.equipment ?? []).length > 0 && (
                <p className="text-xs text-ink-soft mt-2 leading-relaxed">
                  {v.equipment.slice(0, 4).join(' · ')}
                  {v.equipment.length > 4 && ` · +${v.equipment.length - 4} more`}
                </p>
              )}

              {v.notes && <p className="text-xs text-ink-mute mt-3 leading-relaxed">{v.notes}</p>}
              </div>
            </article>
          ))}
        </div>
      )}

      {editing && (
        <VehicleDialog
          initial={editing}
          onCancel={() => setEditing(null)}
          onSave={async v => { await saveVehicle(v); setEditing(null) }}
        />
      )}
    </div>
  )
}

function MiniStat({ label, value, tone }) {
  return (
    <div className="card flex items-baseline gap-3">
      <span className={`text-3xl font-bold tracking-tightest tabular-nums ${
        tone === 'good' ? 'text-success' : tone === 'warn' ? 'text-amber-600' : 'text-ink'
      }`}>{value}</span>
      <span className="text-sm text-ink-soft">{label}</span>
    </div>
  )
}

const FIELD_STYLE = {
  label: 'block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2',
  hint: 'text-xs text-ink-mute mt-1.5 leading-relaxed',
  input: 'input',
  err: 'text-xs text-emergency mt-1.5 font-medium',
}

function VehicleDialog({ initial, onCancel, onSave }) {
  const [v, setV] = useState(initial)
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const errors = validateVehicle(v)

  async function save() {
    if (Object.keys(errors).length) { setShow(true); return }
    setBusy(true)
    setErr('')
    try {
      await withTimeout(onSave(v), 15000, 'Saving vehicle')
    } catch (e) {
      setErr(e.message ?? 'Could not save.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-cream-card rounded-3xl shadow-2xl w-full max-w-lg max-h-[92vh] flex flex-col overflow-hidden">
        <div className="flex items-center justify-between px-6 py-4 border-b border-ink/[0.07]">
          <h2 className="font-bold tracking-tight text-ink">
            {initial.id ? `Edit ${initial.plate}` : 'Add a vehicle'}
          </h2>
          <button onClick={onCancel} className="p-1.5 rounded-lg text-ink-mute hover:text-ink hover:bg-ink/[0.05] transition-colors">
            <IconX className="w-4 h-4" />
          </button>
        </div>

        <div className="px-6 py-5 space-y-5 overflow-y-auto">
          <ImagePicker
            t={FIELD_STYLE}
            label="Photo"
            aspect="wide"
            maxPx={1200}
            value={v.photo}
            onChange={photo => setV(p => ({ ...p, photo }))}
            hint="How a crew recognises this vehicle in a yard or at a handover."
          />

          <div>
            <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
              Number plate
            </label>
            <input
              className="input font-mono uppercase"
              value={v.plate}
              onChange={e => setV(p => ({ ...p, plate: e.target.value.toUpperCase() }))}
              placeholder="KBK 107A"
              autoFocus
            />
            {show && errors.plate && <p className="text-xs text-emergency mt-1.5 font-medium">{errors.plate}</p>}
            <p className="text-xs text-ink-mute mt-2 leading-relaxed">
              Crews enter this plate in the responder app. It is what links a
              vehicle to whoever is driving it, so it has to match exactly.
            </p>
          </div>

          <div>
            <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">Type</label>
            <div className="grid sm:grid-cols-2 gap-2">
              {VEHICLE_TYPES.map(t => (
                <button
                  key={t.value}
                  onClick={() => setV(p => ({ ...p, type: t.value }))}
                  className={`tile !p-3 ${v.type === t.value ? 'tile-on' : 'tile-off'}`}
                >
                  <span className="block text-sm font-semibold">{t.label}</span>
                  <span className="block text-[11px] opacity-70 mt-0.5">{t.sub}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="grid sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">Make and model</label>
              <input className="input" value={v.make} onChange={e => setV(p => ({ ...p, make: e.target.value }))} placeholder="Toyota HiAce" />
            </div>
            <div>
              <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">Year</label>
              <input className="input" value={v.year} inputMode="numeric" onChange={e => setV(p => ({ ...p, year: e.target.value }))} placeholder="2019" />
              {show && errors.year && <p className="text-xs text-emergency mt-1.5 font-medium">{errors.year}</p>}
            </div>
          </div>

          <div className="grid sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
                Patients it can carry
              </label>
              <input className="input" inputMode="numeric" value={v.patientCapacity ?? ''}
                     onChange={e => setV(p => ({ ...p, patientCapacity: e.target.value }))}
                     placeholder="1" />
              {show && errors.patientCapacity && <p className="text-xs text-emergency mt-1.5 font-medium">{errors.patientCapacity}</p>}
            </div>
            <div>
              <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
                Crew seats
              </label>
              <input className="input" inputMode="numeric" value={v.crewCapacity ?? ''}
                     onChange={e => setV(p => ({ ...p, crewCapacity: e.target.value }))}
                     placeholder="3" />
              {show && errors.crewCapacity && <p className="text-xs text-emergency mt-1.5 font-medium">{errors.crewCapacity}</p>}
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">
              What it carries
            </label>
            <div className="flex flex-wrap gap-2">
              {VEHICLE_EQUIPMENT.map(item => {
                const on = (v.equipment ?? []).includes(item)
                return (
                  <button
                    key={item}
                    type="button"
                    onClick={() => setV(p => ({
                      ...p,
                      equipment: on
                        ? (p.equipment ?? []).filter(x => x !== item)
                        : [...(p.equipment ?? []), item],
                    }))}
                    className={`px-3 py-1.5 rounded-xl text-sm font-medium border transition-all ${
                      on
                        ? 'bg-ink text-cream border-ink'
                        : 'bg-cream-card text-ink-soft border-ink/15 hover:border-ink/40'
                    }`}
                  >
                    {item}
                  </button>
                )
              })}
            </div>
            <p className="text-xs text-ink-mute mt-2 leading-relaxed">
              A crew deciding where to send a patient reads this before the make
              and model.
            </p>
          </div>

          <button
            onClick={() => setV(p => ({ ...p, inService: !p.inService }))}
            className={`tile w-full ${v.inService ? 'tile-on' : 'tile-off'}`}
          >
            <span className="block text-sm font-semibold">
              {v.inService ? 'In service' : 'Out of service'}
            </span>
            <span className="block text-xs opacity-70 mt-0.5">
              {v.inService
                ? 'Available for duty when crewed.'
                : 'Off the road — never shows as ready, whoever is on duty.'}
            </span>
          </button>

          <div>
            <label className="block text-xs font-semibold tracking-wider uppercase text-ink-mute mb-2">Notes</label>
            <textarea rows={2} className="input" value={v.notes} onChange={e => setV(p => ({ ...p, notes: e.target.value }))} placeholder="Servicing due, equipment carried…" />
          </div>
        </div>

        <div className="flex items-center gap-3 px-6 py-4 bg-cream border-t border-ink/[0.07]">
          {err && <p className="text-xs text-emergency flex-1">{err}</p>}
          {!err && <div className="flex-1" />}
          <button onClick={onCancel} className="btn-outline">Cancel</button>
          <button onClick={save} disabled={busy} className="btn-primary">
            {busy ? 'Saving…' : initial.id ? 'Save changes' : 'Add vehicle'}
          </button>
        </div>
      </div>
    </div>
  )
}

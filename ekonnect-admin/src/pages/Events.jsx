import { useState, useEffect } from 'react'
import {
  collection, onSnapshot, doc, setDoc, deleteDoc, addDoc,
  orderBy, query, Timestamp,
} from 'firebase/firestore'
import { db } from '../firebase'
import { IconPlus, IconEdit, IconTrash, IconX } from '../components/Icons'

/**
 * Trending events shown on the public landing page.
 *
 * Images are referenced by URL rather than uploaded: Firebase Storage is not
 * set up on this project, and a broken upload path would be worse than an
 * honest link field. Any public image URL works.
 */

const empty = {
  title: '',
  image: '',
  link: '',
  readTime: 3,
  date: new Date().toISOString().slice(0, 10),
  published: true,
}

export default function Events() {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState(null)
  const [saving, setSaving] = useState(false)
  const [touched, setTouched] = useState(false)

  useEffect(() => {
    const q = query(collection(db, 'events'), orderBy('date', 'desc'))
    return onSnapshot(
      q,
      snap => {
        setEvents(snap.docs.map(d => ({ id: d.id, ...d.data() })))
        setLoading(false)
      },
      () => setLoading(false),
    )
  }, [])

  const titleError = touched && !editing?.title?.trim() ? 'Give the event a title.' : ''
  const canSave = !!editing?.title?.trim()

  function startEdit(e) {
    setTouched(false)
    // Firestore Timestamp → yyyy-mm-dd for the date input.
    const date = e.date?.toDate
      ? e.date.toDate().toISOString().slice(0, 10)
      : e.date || empty.date
    setEditing({ ...e, date })
  }

  async function handleSave() {
    setTouched(true)
    if (!canSave) return
    setSaving(true)
    try {
      const payload = {
        title: editing.title.trim(),
        image: editing.image?.trim() || null,
        link: editing.link?.trim() || null,
        readTime: Number(editing.readTime) || null,
        date: Timestamp.fromDate(new Date(editing.date)),
        published: !!editing.published,
        updatedAt: Timestamp.now(),
      }
      if (editing.id) {
        await setDoc(doc(db, 'events', editing.id), payload, { merge: true })
      } else {
        await addDoc(collection(db, 'events'), payload)
      }
      setEditing(null)
    } finally {
      setSaving(false)
    }
  }

  async function togglePublished(e) {
    await setDoc(doc(db, 'events', e.id), { published: !e.published }, { merge: true })
  }

  async function handleDelete(id) {
    if (!window.confirm('Delete this event? This cannot be undone.')) return
    await deleteDoc(doc(db, 'events', id))
  }

  const live = events.filter(e => e.published).length

  return (
    <div className="p-4 sm:p-6 max-w-7xl mx-auto">
      <div className="page-header">
        <div>
          <p className="page-subtitle">
            Published items appear in the Trending section of the public site
          </p>
        </div>
        <button onClick={() => startEdit(empty)} className="btn-primary">
          <IconPlus className="w-4 h-4" /> New Event
        </button>
      </div>

      <div className="grid grid-cols-3 gap-3 sm:gap-4 mb-6">
        <Stat value={events.length} label="Total" />
        <Stat value={live} label="Live on site" tone="text-emerald-600" />
        <Stat value={events.length - live} label="Drafts" tone="text-gray-400" />
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="animate-spin rounded-full h-9 w-9 border-b-2 border-primary" />
        </div>
      ) : events.length === 0 ? (
        <div className="card text-center py-20">
          <div className="text-5xl mb-3">📰</div>
          <p className="text-gray-500 font-medium mb-1">No events yet</p>
          <p className="text-gray-400 text-sm mb-5">
            The Trending section stays hidden until something is published.
          </p>
          <button onClick={() => startEdit(empty)} className="btn-primary mx-auto">
            <IconPlus className="w-4 h-4" /> Create Event
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {events.map(e => (
            <div key={e.id} className="card overflow-hidden p-0 hover:shadow-md transition-shadow">
              {e.image ? (
                <img src={e.image} alt="" className="w-full aspect-[4/3] object-cover" />
              ) : (
                <div className="w-full aspect-[4/3] bg-gray-100 flex items-center justify-center text-gray-300 text-3xl">
                  📰
                </div>
              )}
              <div className="p-4">
                <div className="flex items-center justify-between text-xs text-gray-400 mb-2">
                  <span>
                    {e.date?.toDate
                      ? e.date.toDate().toLocaleDateString('en-GB', {
                          day: '2-digit', month: 'short', year: 'numeric',
                        })
                      : ''}
                  </span>
                  {e.readTime && <span>{e.readTime} mins read</span>}
                </div>
                <h3 className="font-semibold text-sm leading-snug line-clamp-2">{e.title}</h3>

                <div className="flex items-center justify-between mt-4 pt-3 border-t border-gray-50">
                  <button
                    onClick={() => togglePublished(e)}
                    className={`text-xs font-semibold px-2.5 py-1 rounded-lg transition-colors ${
                      e.published
                        ? 'bg-emerald-50 text-emerald-700 hover:bg-emerald-100'
                        : 'bg-gray-100 text-gray-500 hover:bg-gray-200'
                    }`}
                  >
                    {e.published ? 'Live' : 'Draft'}
                  </button>
                  <div className="flex gap-1">
                    <button
                      onClick={() => startEdit(e)}
                      className="p-2 rounded-xl text-gray-400 hover:text-primary hover:bg-purple-50 transition-colors"
                    >
                      <IconEdit />
                    </button>
                    <button
                      onClick={() => handleDelete(e.id)}
                      className="p-2 rounded-xl text-gray-400 hover:text-red-500 hover:bg-red-50 transition-colors"
                    >
                      <IconTrash />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {editing && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md max-h-[92vh] flex flex-col overflow-hidden">
            <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 flex-shrink-0">
              <h2 className="text-base font-bold text-gray-900">
                {editing.id ? 'Edit Event' : 'New Event'}
              </h2>
              <button
                onClick={() => setEditing(null)}
                className="p-1.5 rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
              >
                <IconX className="w-4 h-4" />
              </button>
            </div>

            <div className="px-6 py-5 space-y-5 overflow-y-auto">
              <Field label="Title" error={titleError}>
                <input
                  value={editing.title}
                  onChange={ev => setEditing(p => ({ ...p, title: ev.target.value }))}
                  onBlur={() => setTouched(true)}
                  className={`input ${titleError ? 'border-red-300' : ''}`}
                  placeholder="e.g. eKonnect launches in Kakamega County"
                  autoFocus
                />
              </Field>

              <Field label="Image URL" hint="Any public image address. Leave blank for a placeholder.">
                <input
                  value={editing.image ?? ''}
                  onChange={ev => setEditing(p => ({ ...p, image: ev.target.value }))}
                  className="input"
                  placeholder="https://…"
                />
              </Field>

              {editing.image && (
                <img
                  src={editing.image}
                  alt=""
                  className="w-full aspect-[4/3] object-cover rounded-xl border border-gray-100"
                  onError={ev => { ev.currentTarget.style.display = 'none' }}
                />
              )}

              <Field label="Link" hint="Optional. Where the card goes when clicked.">
                <input
                  value={editing.link ?? ''}
                  onChange={ev => setEditing(p => ({ ...p, link: ev.target.value }))}
                  className="input"
                  placeholder="https://…"
                />
              </Field>

              <div className="grid grid-cols-2 gap-3">
                <Field label="Date">
                  <input
                    type="date"
                    value={editing.date}
                    onChange={ev => setEditing(p => ({ ...p, date: ev.target.value }))}
                    className="input"
                  />
                </Field>
                <Field label="Read time (mins)">
                  <input
                    type="number"
                    min="1"
                    value={editing.readTime ?? ''}
                    onChange={ev => setEditing(p => ({ ...p, readTime: ev.target.value }))}
                    className="input"
                  />
                </Field>
              </div>

              <label className="flex items-center gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={!!editing.published}
                  onChange={ev => setEditing(p => ({ ...p, published: ev.target.checked }))}
                  className="w-4 h-4 accent-[#3D1152]"
                />
                <span className="text-sm text-gray-700">
                  Publish to the public site
                </span>
              </label>
            </div>

            <div className="flex gap-3 px-6 py-4 bg-gray-50 border-t border-gray-100 flex-shrink-0">
              <button onClick={() => setEditing(null)} className="btn-outline flex-1 justify-center">
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={saving || !canSave}
                className="btn-primary flex-1 justify-center"
              >
                {saving ? 'Saving…' : editing.id ? 'Save Changes' : 'Create Event'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function Stat({ value, label, tone = 'text-gray-900' }) {
  return (
    <div className="card text-center">
      <p className={`text-2xl font-bold ${tone}`}>{value}</p>
      <p className="text-xs text-gray-500 mt-0.5">{label}</p>
    </div>
  )
}

function Field({ label, hint, error, children }) {
  return (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1.5">{label}</label>
      {children}
      {error
        ? <p className="text-xs text-red-600 mt-1">{error}</p>
        : hint && <p className="text-[11px] text-gray-400 mt-1">{hint}</p>}
    </div>
  )
}

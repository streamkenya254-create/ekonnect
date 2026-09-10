import { useRef, useState } from 'react'

/**
 * Picks an image and hands back a size-bounded data URL.
 *
 * Images are downscaled and re-encoded in the browser before they go anywhere,
 * for two reasons. A phone camera JPEG is 3–6MB and a Firestore document is
 * capped at 1MiB, so an untouched upload simply fails to save; and a Care Point
 * logo is rendered at 44px in the console, so storing 4000px of it is waste
 * that every reader pays for.
 *
 * Storing pictures inside the document rather than Cloud Storage is a
 * deliberate trade for the registration flow: it needs no bucket, no second
 * set of security rules, and no orphan cleanup when an application is
 * rejected. Move to Storage when facilities start uploading galleries.
 */
export default function ImagePicker({
  value,
  onChange,
  label,
  hint,
  aspect = 'square',   // 'square' for logos, 'wide' for covers
  maxPx = 512,
  quality = 0.72,
  t,
}) {
  const input = useRef(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  async function pick(e) {
    const file = e.target.files?.[0]
    e.target.value = '' // let the same file be re-picked after a remove
    if (!file) return

    if (!file.type.startsWith('image/')) {
      setError('That is not an image file.')
      return
    }
    if (file.size > 12 * 1024 * 1024) {
      setError('That image is over 12MB. Try a smaller one.')
      return
    }

    setBusy(true)
    setError('')
    try {
      const url = await downscale(file, maxPx, quality)
      onChange(url)
    } catch {
      setError('Could not read that image. Try a JPG or PNG.')
    } finally {
      setBusy(false)
    }
  }

  const box = aspect === 'wide'
    ? 'aspect-[16/6] w-full'
    : 'w-28 h-28 flex-shrink-0'

  return (
    <div>
      <label className={t.label}>{label}</label>

      <div className={aspect === 'wide' ? '' : 'flex items-start gap-4'}>
        <button
          type="button"
          onClick={() => input.current?.click()}
          className={`${box} relative overflow-hidden rounded-2xl border-2 border-dashed
                      flex items-center justify-center transition-colors
                      ${value ? 'border-transparent' : 'border-ink/15 hover:border-primary/50'}`}
        >
          {value ? (
            <img src={value} alt="" className={`w-full h-full ${aspect === 'wide' ? 'object-cover' : 'object-contain p-2'}`} />
          ) : (
            <span className="text-center px-3">
              <svg className="w-6 h-6 mx-auto text-ink-mute" fill="none" stroke="currentColor"
                   strokeWidth="1.6" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round"
                      d="M3 16l5-5 4 4 3-3 6 6M4 4h16v16H4z" />
              </svg>
              <span className="block text-[11px] text-ink-mute mt-1.5 font-medium">
                {busy ? 'Processing…' : 'Choose image'}
              </span>
            </span>
          )}
        </button>

        <div className={aspect === 'wide' ? 'mt-3 flex items-center gap-3' : 'flex-1 min-w-0'}>
          {hint && <p className={t.hint + ' !mt-0'}>{hint}</p>}
          {value && (
            <button
              type="button"
              onClick={() => onChange('')}
              className="text-xs font-semibold text-emergency hover:underline mt-2 block"
            >
              Remove
            </button>
          )}
        </div>
      </div>

      {error && <p className={t.err}>{error}</p>}

      <input
        ref={input}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        onChange={pick}
        className="hidden"
      />
    </div>
  )
}

/**
 * Draws the file into a canvas no larger than `maxPx` on its longest edge and
 * re-encodes it. PNG sources keep PNG so a logo's transparency survives;
 * everything else becomes JPEG, which is far smaller for photographs.
 */
function downscale(file, maxPx, quality) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = reject
    reader.onload = () => {
      const img = new Image()
      img.onerror = reject
      img.onload = () => {
        const scale = Math.min(1, maxPx / Math.max(img.width, img.height))
        const w = Math.round(img.width * scale)
        const h = Math.round(img.height * scale)

        const canvas = document.createElement('canvas')
        canvas.width = w
        canvas.height = h
        const ctx = canvas.getContext('2d')
        ctx.imageSmoothingQuality = 'high'
        ctx.drawImage(img, 0, 0, w, h)

        const png = file.type === 'image/png'
        let out = canvas.toDataURL(png ? 'image/png' : 'image/jpeg', quality)

        // A transparent PNG photo can still come out large. Fall back to JPEG
        // rather than let the document creep towards the 1MiB ceiling.
        if (png && out.length > 400_000) {
          out = canvas.toDataURL('image/jpeg', quality)
        }
        resolve(out)
      }
      img.src = reader.result
    }
    reader.readAsDataURL(file)
  })
}

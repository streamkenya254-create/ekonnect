import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

const DISMISSED = 'ekonnect.guidePrompt.dismissed'

/**
 * Points a first-time visitor at the tester's guide.
 *
 * Deliberately not a modal over the page: someone who arrived to read about
 * the product should not have to dismiss something before they can. It slides
 * in at the corner after a beat, and stays dismissed once closed — a prompt
 * that reappears on every visit stops being a prompt and becomes noise.
 */
export default function GuidePrompt() {
  const [shown, setShown] = useState(false)

  useEffect(() => {
    let dismissed = false
    try {
      dismissed = localStorage.getItem(DISMISSED) === '1'
    } catch {
      // Private browsing can refuse storage; showing it is the safe fallback.
    }
    if (dismissed) return

    // Late enough that it does not compete with the hero for attention.
    const t = setTimeout(() => setShown(true), 2200)
    return () => clearTimeout(t)
  }, [])

  function dismiss() {
    setShown(false)
    try {
      localStorage.setItem(DISMISSED, '1')
    } catch {
      // Nothing to do — it simply shows again next visit.
    }
  }

  if (!shown) return null

  return (
    <div
      role="complementary"
      aria-label="Testing this app?"
      className="fixed bottom-5 right-5 left-5 sm:left-auto z-50 sm:max-w-sm
                 animate-[guideIn_.45s_cubic-bezier(.2,.8,.2,1)_both]
                 motion-reduce:animate-none"
    >
      <div className="rounded-2xl bg-ink text-cream shadow-[0_24px_60px_-20px_rgba(20,10,27,.7)]
                      border border-white/10 p-5">
        <div className="flex items-start gap-3">
          <div className="flex-1">
            <p className="font-bold tracking-tight">Testing eKonnect?</p>
            <p className="mt-1 text-sm text-cream/70 leading-relaxed">
              There is a short guide with the demo sign-ins for the app and the
              console, and what to try in each.
            </p>
          </div>
          <button
            onClick={dismiss}
            aria-label="Dismiss"
            className="shrink-0 -mt-1 -mr-1 w-8 h-8 rounded-lg text-cream/50
                       hover:text-cream hover:bg-white/10 transition-colors
                       flex items-center justify-center text-lg leading-none"
          >
            &times;
          </button>
        </div>
        <div className="mt-4 flex items-center gap-3">
          <Link
            to="/guide"
            onClick={dismiss}
            className="inline-flex items-center gap-2 bg-cream text-ink px-4 py-2.5
                       rounded-xl text-sm font-semibold tracking-tight
                       hover:gap-3 transition-all duration-300"
          >
            Open the guide
            <span aria-hidden="true">&rarr;</span>
          </Link>
          <button
            onClick={dismiss}
            className="text-sm font-semibold text-cream/60 hover:text-cream transition-colors"
          >
            Not now
          </button>
        </div>
      </div>

      <style>{`
        @keyframes guideIn {
          from { opacity: 0; transform: translateY(14px) scale(.98); }
          to   { opacity: 1; transform: none; }
        }
      `}</style>
    </div>
  )
}

/**
 * Full-screen boot state, shown while Firebase resolves who is signed in.
 *
 * The mark and a ring, nothing else. There is only one thing happening and no
 * decision to make, so wording it adds reading without adding information —
 * the label survives for screen readers, where it is the only signal there is.
 */
export default function BootScreen({ label = 'Loading', className = '' }) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={`fixed inset-0 z-50 flex items-center justify-center bg-ink overflow-hidden ${className}`}
    >
      {/* Two washes give the flat ink some depth without needing an image. */}
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_50%_50%,rgba(61,17,82,0.9),transparent_60%)]" />
      <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-black/40" />

      <div className="relative w-48 h-48 sm:w-56 sm:h-56 flex items-center justify-center">
        {/* Halo, breathing slowly behind the mark. */}
        <span className="absolute inset-4 rounded-full bg-primary/40 blur-3xl ek-breathe" />

        {/* The ring turns; the mark never does. A spinning logo reads as a
            page that has hung. */}
        <svg
          className="absolute inset-0 w-full h-full animate-spin ek-ring"
          viewBox="0 0 100 100"
          aria-hidden="true"
        >
          <circle cx="50" cy="50" r="46" fill="none" stroke="currentColor"
                  className="text-white/10" strokeWidth="2" />
          {/* r=46 → circumference ≈ 289, so 78 draws a little over a quarter. */}
          <circle cx="50" cy="50" r="46" fill="none" stroke="currentColor"
                  className="text-white" strokeWidth="2" strokeLinecap="round"
                  strokeDasharray="78 211" />
        </svg>

        <img
          src="/assets/logo-white.png"
          alt=""
          className="relative w-24 h-24 sm:w-28 sm:h-28 object-contain"
        />
      </div>

      <span className="sr-only">{label}</span>
    </div>
  )
}

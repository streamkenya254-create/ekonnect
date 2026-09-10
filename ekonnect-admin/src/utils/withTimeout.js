/**
 * Rejects if `promise` has not settled within `ms`.
 *
 * Firestore write promises resolve only once the backend acknowledges them. If
 * the browser cannot reach Firestore — a blocked WebChannel, a proxy, an
 * extension, a dead connection — the write is queued locally and the promise
 * never settles at all. Without a deadline the caller's "Saving…" state sits
 * there forever, telling the operator nothing.
 *
 * This turns that silence into a real, reportable failure.
 */
export function withTimeout(promise, ms = 15000, label = 'operation') {
  let timer
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${label} timed out after ${Math.round(ms / 1000)}s`)),
      ms,
    )
  })
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer))
}

/** Turns a Firestore/Auth error into something an operator can act on. */
export function friendlyError(err) {
  const code = err?.code ?? ''
  if (code === 'permission-denied') {
    return 'You do not have permission to make this change.'
  }
  if (code === 'unavailable' || code === 'failed-precondition') {
    return 'Cannot reach the database. Check your connection and try again.'
  }
  if (code === 'not-found') {
    return 'That record no longer exists — it may have been deleted.'
  }
  if (String(err?.message ?? '').includes('timed out')) {
    return `${err.message}. The change may not have been saved — reload and check.`
  }
  return err?.message ?? 'Something went wrong. Please try again.'
}

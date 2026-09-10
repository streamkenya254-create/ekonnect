import { useState } from 'react'
import { mailtoLink, whatsappLink } from '../data/invites'

/**
 * The letter Firebase cannot send, ready to forward.
 *
 * Shown the moment an invite goes out, because that is the one instant an
 * administrator is definitely looking — asking them to come back later and
 * find it would mean it never gets sent.
 *
 * Three ways out: copy it, open it in a mail client, or send it on WhatsApp,
 * which is how most of this will actually reach a Kenyan hospital.
 */
export default function InviteMessage({ email, phone, invite, onDismiss }) {
  const [copied, setCopied] = useState('')

  async function copy(text, which) {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(which)
      setTimeout(() => setCopied(''), 2000)
    } catch {
      // Clipboard is blocked on insecure origins and in some embedded views.
      // The text is selectable either way, so this is a convenience failing.
      setCopied('failed')
      setTimeout(() => setCopied(''), 2500)
    }
  }

  const wa = whatsappLink(phone, invite)

  return (
    <div className="mt-5 rounded-2xl border border-ink/[0.09] bg-cream-card overflow-hidden">
      <div className="px-5 py-4 border-b border-ink/[0.07] flex items-start justify-between gap-4">
        <div>
          <p className="text-sm font-bold text-ink">Send them this</p>
          <p className="text-xs text-ink-soft mt-1 leading-relaxed max-w-2xl">
            Firebase's own email only says “reset your password” — this explains
            what it is for. Send it alongside, to <strong className="text-ink">{email}</strong>.
          </p>
        </div>
        {onDismiss && (
          <button onClick={onDismiss} className="btn-ghost !py-1 !text-xs flex-shrink-0">Hide</button>
        )}
      </div>

      <div className="px-5 py-4">
        <label className="block text-[11px] font-semibold tracking-wider uppercase text-ink-mute mb-1.5">
          Subject
        </label>
        <div className="flex items-center gap-2">
          <input readOnly value={invite.subject} className="input !py-2 text-sm font-medium" />
          <button onClick={() => copy(invite.subject, 'subject')} className="btn-outline !py-2 !text-xs flex-shrink-0">
            {copied === 'subject' ? 'Copied' : 'Copy'}
          </button>
        </div>

        <label className="block text-[11px] font-semibold tracking-wider uppercase text-ink-mute mt-4 mb-1.5">
          Message
        </label>
        <textarea
          readOnly
          value={invite.body}
          rows={14}
          onFocus={e => e.target.select()}
          className="input font-mono !text-[12px] leading-relaxed resize-y"
        />
      </div>

      <div className="px-5 py-3.5 bg-cream border-t border-ink/[0.07] flex flex-wrap items-center gap-2">
        <button onClick={() => copy(invite.body, 'body')} className="btn-primary !py-2 !text-xs">
          {copied === 'body' ? 'Copied to clipboard' : copied === 'failed' ? 'Select it and copy' : 'Copy message'}
        </button>
        <a href={mailtoLink(email, invite)} className="btn-outline !py-2 !text-xs">
          Open in email
        </a>
        {wa && (
          <a href={wa} target="_blank" rel="noopener noreferrer" className="btn-outline !py-2 !text-xs">
            Send on WhatsApp
          </a>
        )}
        <span className="text-[11px] text-ink-mute ml-auto">
          Nothing is sent automatically — you send this one yourself.
        </span>
      </div>
    </div>
  )
}

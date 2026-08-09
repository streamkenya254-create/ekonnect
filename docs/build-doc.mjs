/**
 * Builds the eKonnect Concept Note & Business Plan as a designed Word document.
 *
 * Styling follows the "Purple and White Modern Startup" pitch deck: brand purple
 * headings, coral accents, banded tables with purple header rows. Content is the
 * existing business plan, restructured so every comparative section is a table
 * rather than prose.
 */
import {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType,
  Header, Footer, PageNumber, TableOfContents, ImageRun, PageBreak,
  convertInchesToTwip, VerticalAlign,
} from 'docx'
import { writeFileSync, readFileSync } from 'fs'

const PURPLE = '3D1152'
const PURPLE_LIGHT = 'F3EEF8'
const CORAL = 'FF4D5E'
const INK = '1B1524'
const GREY = '6B6577'
const RULE = 'E4E0EA'
const BAND = 'FAF9FC'

const OUT = 'c:/Users/user/WEB DEVELOPMENT/ekonnect/Documentation/eKonnect_Concept_Note_Business_Plan.docx'
const LOGO = 'c:/Users/user/WEB DEVELOPMENT/ekonnect/ekonnect/assets/icon/app_icon.png'

// ── helpers ──────────────────────────────────────────────────────────────────

const noBorder = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' }
const hairline = { style: BorderStyle.SINGLE, size: 2, color: RULE }

const text = (t, o = {}) => new TextRun({ text: t, font: 'Calibri', ...o })

const p = (t, o = {}) =>
  new Paragraph({
    spacing: { after: 160, line: 300 },
    children: Array.isArray(t) ? t : [text(t, { size: 21, color: INK })],
    ...o,
  })

const bullet = t =>
  new Paragraph({
    bullet: { level: 0 },
    spacing: { after: 90, line: 290 },
    children: [text(t, { size: 21, color: INK })],
  })

const h1 = t =>
  new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 420, after: 200 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: PURPLE } },
    children: [text(t, { size: 30, bold: true, color: PURPLE })],
  })

const h2 = t =>
  new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 280, after: 130 },
    children: [text(t, { size: 24, bold: true, color: PURPLE })],
  })

const h3 = t =>
  new Paragraph({
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 200, after: 100 },
    children: [text(t, { size: 21, bold: true, color: INK })],
  })

/** Pull-quote style callout for a headline figure or key claim. */
const callout = (label, body) =>
  new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders: {
      top: noBorder, bottom: noBorder, right: noBorder,
      insideHorizontal: noBorder, insideVertical: noBorder,
      left: { style: BorderStyle.SINGLE, size: 18, color: CORAL },
    },
    rows: [
      new TableRow({
        children: [
          new TableCell({
            shading: { type: ShadingType.CLEAR, fill: PURPLE_LIGHT },
            margins: { top: 180, bottom: 180, left: 240, right: 240 },
            children: [
              new Paragraph({
                spacing: { after: 60 },
                children: [text(label, { size: 18, bold: true, color: CORAL, allCaps: true })],
              }),
              new Paragraph({
                children: [text(body, { size: 21, color: INK })],
              }),
            ],
          }),
        ],
      }),
    ],
  })

/**
 * A banded table with a purple header row.
 * `widths` are percentages and must total 100.
 */
function table(headers, rows, widths) {
  const cell = (content, { header = false, band = false, bold = false, align } = {}) =>
    new TableCell({
      verticalAlign: VerticalAlign.TOP,
      shading: {
        type: ShadingType.CLEAR,
        fill: header ? PURPLE : band ? BAND : 'FFFFFF',
      },
      margins: { top: 110, bottom: 110, left: 140, right: 140 },
      children: [
        new Paragraph({
          alignment: align,
          spacing: { after: 0, line: 270 },
          children: [
            text(String(content), {
              size: header ? 18 : 19,
              bold: header || bold,
              color: header ? 'FFFFFF' : INK,
              allCaps: header,
            }),
          ],
        }),
      ],
    })

  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    columnWidths: widths?.map(w => Math.round((9360 * w) / 100)),
    borders: {
      top: hairline, bottom: hairline, left: hairline, right: hairline,
      insideHorizontal: hairline, insideVertical: hairline,
    },
    rows: [
      new TableRow({
        tableHeader: true,
        children: headers.map(hd => cell(hd, { header: true })),
      }),
      ...rows.map((r, i) =>
        new TableRow({
          children: r.map((c, j) =>
            cell(c, {
              band: i % 2 === 1,
              // First column carries the label; emphasise it.
              bold: j === 0 && headers.length > 2,
              align: /^(KSH|[\d,]+$)/.test(String(c)) && j > 0 ? AlignmentType.RIGHT : undefined,
            }),
          ),
        }),
      ),
    ],
  })
}

const spacer = (h = 200) => new Paragraph({ spacing: { after: h }, children: [] })

let figureNo = 0
const DIAGRAMS = 'c:/Users/user/WEB DEVELOPMENT/ekonnect/docs/diagrams'

/**
 * Three phone screenshots side by side, each with its own label.
 *
 * Laid out in a borderless table so the images stay aligned on their top edge
 * regardless of the small differences in screenshot height.
 */
function phoneRow(shots, caption) {
  figureNo += 1
  const W = 168
  const H = 348

  return [
    new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      borders: {
        top: noBorder, bottom: noBorder, left: noBorder, right: noBorder,
        insideHorizontal: noBorder, insideVertical: noBorder,
      },
      rows: [
        new TableRow({
          children: shots.map(([file]) =>
            new TableCell({
              margins: { top: 60, bottom: 40, left: 60, right: 60 },
              children: [
                new Paragraph({
                  alignment: AlignmentType.CENTER,
                  children: [
                    new ImageRun({
                      data: readFileSync(`${DIAGRAMS}/${file}`),
                      transformation: { width: W, height: H },
                      type: file.endsWith('.png') ? 'png' : 'jpg',
                    }),
                  ],
                }),
              ],
            }),
          ),
        }),
        new TableRow({
          children: shots.map(([, label]) =>
            new TableCell({
              margins: { top: 0, bottom: 80, left: 60, right: 60 },
              children: [
                new Paragraph({
                  alignment: AlignmentType.CENTER,
                  children: [text(label, { size: 17, bold: true, color: PURPLE })],
                }),
              ],
            }),
          ),
        }),
      ],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 260 },
      children: [
        text(`Figure ${figureNo}. `, { size: 17, bold: true, color: PURPLE }),
        text(caption, { size: 17, color: GREY, italics: true }),
      ],
    }),
  ]
}

/** A centred diagram with a numbered caption beneath it. */
function figure(file, caption, srcW, srcH) {
  figureNo += 1
  const width = 620
  const height = Math.round((srcH / srcW) * width)
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 200, after: 80 },
      children: [
        new ImageRun({
          data: readFileSync(`${DIAGRAMS}/${file}`),
          transformation: { width, height },
          type: 'png',
        }),
      ],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 260 },
      children: [
        text(`Figure ${figureNo}. `, { size: 17, bold: true, color: PURPLE }),
        text(caption, { size: 17, color: GREY, italics: true }),
      ],
    }),
  ]
}

// ── cover ────────────────────────────────────────────────────────────────────

const cover = [
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 1400, after: 260 },
    children: [
      new ImageRun({
        data: readFileSync(LOGO),
        transformation: { width: 110, height: 110 },
        type: 'png',
      }),
    ],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 60 },
    children: [text('eKonnect', { size: 60, bold: true, color: PURPLE })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 380 },
    children: [text('Emergency Response, Anytime', { size: 24, color: CORAL, bold: true })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 200 },
    border: { top: hairline, bottom: hairline },
    children: [text('  Concept Note & Business Plan  ', { size: 34, bold: true, color: INK })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 200, after: 700 },
    children: [
      text(
        'A unified mobile and web platform connecting patients, ambulance drivers,\nmedical practitioners and emergency administrators across Kenya and East Africa.',
        { size: 21, color: GREY, italics: true },
      ),
    ],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 40 },
    children: [text('Prepared by the eKonnect Team', { size: 21, bold: true, color: INK })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 40 },
    children: [text('Benard Phabian · Software Designer', { size: 20, color: GREY })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [text('August 2026', { size: 20, color: GREY })],
  }),
  new Paragraph({ children: [new PageBreak()] }),
]

// ── contents ─────────────────────────────────────────────────────────────────

const contents = [
  h1('Table of Contents'),
  p([
    text('Right-click the table below and choose ', { size: 19, color: GREY, italics: true }),
    text('Update Field', { size: 19, color: GREY, italics: true, bold: true }),
    text(' — or press Ctrl+A then F9 — to populate page numbers.', { size: 19, color: GREY, italics: true }),
  ]),
  new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-2' }),
  new Paragraph({ children: [new PageBreak()] }),
]

// ── body ─────────────────────────────────────────────────────────────────────

const body = [
  h1('1. Executive Summary'),
  p('eKonnect is an emergency response platform built for Kenya and East Africa. It connects three groups on one coordinated network: people in a medical, fire, flood or security emergency; the ambulance drivers and medical practitioners who respond to them; and the administrators who verify responders, govern the network and keep it accountable. The goal is simple and measurable: cut the time between an emergency happening and a qualified responder arriving, inside the "Golden Hour" that determines survival in trauma and medical emergencies.'),
  p('The product already exists as a working system, not a concept sketch. A Flutter mobile application serves patients and responders with role-specific experiences — a one-tap, hold-to-confirm SOS flow, live GPS tracking of the responder en route, an AI-assisted voice reporting mode for callers who cannot categorise their own emergency, and a responder-side duty toggle with incoming-incident accept/decline. A React web dashboard gives administrators a live incident map, responder verification pipeline, and team-management tools for coordinating multiple ambulance and practitioner organisations at once. Both are built on Firebase for real-time data sync and push notifications, with Google Maps for live location and routing.'),
  p("eKonnect's business model is deliberately two-sided. The public safety network — the free SOS button available to any citizen — is funded through county government partnerships, NGO grants and public health budgets, in the same way a national ambulance service is funded, because a life-or-death button cannot be paywalled. Alongside it, private hospitals, corporates, schools and insurers can subscribe their own vetted responder fleets to serve their own staff, students or clients directly — a B2B SaaS layer that generates recurring revenue and cross-subsidises the public network's infrastructure costs."),
  spacer(60),
  callout('The opportunity in one line', 'Kenya lost 4,748 lives to road traffic alone in 2024 — about 13 people every day. Coordinated dispatch has already been shown here to cut urban response times from over 160 minutes to 13.'),
  spacer(180),
  p('eKonnect is raising KSH 5.7 million to take the platform from a working pilot-ready product to a verified, funded county-level rollout: hardening the cloud infrastructure, completing data-security compliance, funding responder onboarding and training, and finishing the remaining engineering work. The five-year plan that follows takes eKonnect from a single-county pilot to a regional emergency-response backbone across East Africa.'),

  h1('2. The Problem'),
  p("Kenya's emergency-care system suffers from four compounding failures, each of which eKonnect is built to address directly."),

  h2('2.1 Delayed response inside the Golden Hour'),
  p('Trauma and cardiac medicine both point to the same clinical reality: outcomes fall sharply once roughly 60 minutes pass between injury or onset and definitive care. Kenya is not close to consistently meeting that window for pre-hospital transport, even though 93.7% of the population lives within one hour\'s drive of a public emergency department. The hospitals exist and are reachable — the bottleneck is getting a responder dispatched to the patient\'s side in the first place.'),

  h2('2.2 Ambulance scarcity and poor coordination'),
  p('The World Health Organization recommends one ambulance per 50,000 people. Kenya has never had a complete, verified national count of its ambulance fleet — a gap serious enough that the national government\'s own emergency response plan is starting by simply registering and inspecting vehicles. Public, private and NGO ambulances today largely operate as disconnected fleets with no shared dispatch layer, so the nearest available vehicle is frequently not the one that responds.'),

  h2('2.3 Difficulty locating the nearest available help'),
  p("A caller in an emergency typically has no way to see which ambulance or practitioner is actually nearby and free to respond. Calls go to a single hotline or a private provider's line, which may have no vehicle close by while a closer one from a different operator sits idle. Precious minutes are lost to phone trees and manual coordination."),

  h2('2.4 No centralized, accountable communication platform'),
  p('There is no shared system of record that lets a government health department, a county administrator, or a private hospital verify who is responding to what, hold responders accountable for their credentials, or measure response-time performance over time. Emergency response in Kenya today is a set of parallel, largely paper-and-phone-call operations rather than one governed network.'),

  h2('2.5 Why this matters, in numbers'),
  table(
    ['Indicator', 'Figure', 'Source'],
    [
      ['Road traffic deaths, Kenya, 2024', '4,748 (+5.2% YoY)', 'NTSA / The Star, 2025'],
      ['Average daily road deaths', '≈13 people per day', 'NTSA'],
      ['Pedestrian deaths, 2024', '4,315 (+10.3% YoY)', 'NTSA'],
      ['WHO-recommended ambulance ratio', '1 per 50,000 people', 'WHO / KIPPRA'],
      ['Ambulances registered under national plan (phase 1)', '113 registered, 59 inspected', 'Ministry of Health, 2025'],
      ['Population within 1 hour of an emergency department', '93.7%', 'PMC / national EMS study'],
      ['Response time achieved by coordinated dispatch', '>160 min → 13 min (urban)', 'Rescue.co'],
      ['Smartphone penetration, Kenya', '92.9%', 'CA Kenya / DataReportal'],
    ],
    [42, 28, 30],
  ),
  spacer(120),
  p([text('Sources: NTSA road safety data as reported by The Star (2025); WHO ambulance benchmark as cited by KIPPRA; Kenya Ministry of Health emergency response plan reporting; peer-reviewed pre-hospital care coverage study (PMC); Rescue.co published outcomes.', { size: 17, color: GREY, italics: true })]),

  h1('3. The Solution'),
  p('eKonnect is a single connected platform with four purpose-built experiences, all reading and writing to the same real-time backend so that a patient, a responder and an administrator are always looking at the same truth.'),

  h2('3.1 The Patient App'),
  p('A citizen opens the app to a live map of on-duty responders near them, with one clear question: "What\'s your emergency?" They tap a category — Medical, Fire, Flood or Security — then hold a button for one deliberate second to confirm and send. That short hold is intentional: long enough to prevent an accidental SOS, short enough never to slow down a real one.'),
  bullet('Hold-to-send SOS across four incident types, each triaged and colour-coded'),
  bullet('Voice reporting: a panicked, injured or unsure caller can describe the emergency out loud; AI triage classifies type and severity, extracts key facts, and drafts a note the responder sees on arrival — always with a manual override'),
  bullet('A permanent one-tap "Call 999" fallback on every screen, because the app must never become a single point of failure between a citizen and help'),
  bullet('Live tracking of the assigned responder, with cancellation captured against a structured reason so the platform can tell a false alarm from a real gap in coverage'),
  bullet('Incident history, in-app tutorial, and a built-in emergency AI assistant for calm guidance while help is on the way'),
  ...phoneRow(
    [
      ['app_image5.jpeg', 'Sign in'],
      ['app_image6.jpeg', 'Choose an emergency'],
      ['app_image8.jpeg', 'Live tracking'],
    ],
    'The patient journey: sign in, choose an emergency type, then track the assigned responder with one-tap Call and Chat.',
  ),

  h2('3.2 The Responder App'),
  p('The same application serves verified responders in a dedicated mode: a duty toggle to go on- or off-shift, a live feed of incoming incidents with an Accept action, and turn-by-turn voice-guided navigation to the patient once accepted.'),
  bullet('Go on/off duty; see live counts of incoming, on-duty and assigned incidents'),
  bullet("Accept, navigate to, and resolve an incident, with the patient's live location and AI-drafted triage notes on screen"),
  bullet('Practitioners can switch into citizen SOS mode without losing their professional role — useful when an off-duty medic needs to report an emergency of their own'),
  bullet('Refer a patient onward to a hospital or clinic, with each leg of the journey timestamped'),
  ...phoneRow(
    [
      ['app_image9.jpeg', 'Incoming incidents'],
      ['app_image10.jpeg', 'Job detail'],
      ['app_image11.png', 'In-app navigation'],
    ],
    'The responder side: incoming calls, the accepted job, and turn-by-turn navigation with distance, ETA and voice guidance — without leaving the app.',
  ),

  h2('3.3 The Admin Dashboard'),
  p('A web dashboard, built for county health officers, hospital operations managers or NGO programme coordinators, gives full operational and governance control.'),
  bullet('A live map of every active incident with status, assigned responder and elapsed time'),
  bullet('Responder verification: every driver or practitioner passes through a pending → verified (or rejected/suspended) pipeline before they can go on duty — an unvetted stranger can never simply put themselves onto the public network'),
  bullet("Team management: group responders into organisations, assign which incident types each team responds to, and choose their assignment mode"),
  bullet('Public vs. private visibility: a public team answers any nearby citizen SOS; a private team answers only its own subscribers — the two networks share the same platform but never cross wires without an admin decision'),

  h2('3.4 AI-Assisted Triage — a Safety Net, Never a Gatekeeper'),
  p("eKonnect's voice-reporting flow uses a large language model to turn a messy, panicked spoken description into a structured dispatch record: incident type, severity, a one-line summary, key facts, and immediate safety advice."),
  spacer(60),
  callout('Design principle', 'The model never blocks the emergency. If every AI call fails, the caller simply picks a category by hand and the SOS still fires. Low-confidence classifications are flagged for confirmation rather than silently trusted.'),
  spacer(180),

  h2('3.5 Technology Stack'),
  p('All three applications read and write the same real-time backend, which is what keeps the patient, the responder and the administrator looking at one version of events rather than three that must be reconciled.'),
  ...figure('architecture.png', 'How the three applications, the backend and external services fit together.', 1500, 760),
  table(
    ['Layer', 'Technology', 'Why it fits'],
    [
      ['Mobile app', 'Flutter, Provider state management', 'One codebase for Android and iOS; fast iteration on a rich, animated UI'],
      ['Backend & real-time data', 'Firebase — Firestore, Realtime Database, Auth, Cloud Messaging', 'Real-time sync between patient, responder and admin without custom infrastructure; scales automatically'],
      ['Maps & location', 'Google Maps SDK, Routes API, Geolocator', 'Live tracking, road routing and turn-by-turn voice guidance'],
      ['Admin dashboard', 'React, Vite, Tailwind CSS, Firebase JS SDK', 'Fast, maintainable web console on the same real-time data as the apps'],
      ['AI triage & assistant', 'Groq-hosted LLM (Llama 3.3 70B)', 'Low-latency inference suited to a live emergency-reporting flow'],
      ['Voice', 'flutter_tts, speech_to_text', 'Spoken emergency reporting and spoken turn-by-turn guidance'],
    ],
    [22, 33, 45],
  ),

  h1('4. Market Analysis'),
  h2('4.1 Market size and readiness'),
  p('Kenya recorded 4,748 road traffic deaths in 2024 alone, on top of the ordinary daily burden of medical emergencies, fires, floods and security incidents that every county handles. Each is a potential eKonnect dispatch. The digital infrastructure to reach this need is already in place: 78.3 million mobile connections (149.4% penetration) and 92.9% smartphone penetration. This is not a market that needs building on the device side — it needs a coordination layer on top of phones people already carry.'),

  h2('4.2 Competitive landscape'),
  p('eKonnect is not the first attempt to bring technology to Kenyan emergency response, and that is a point in its favour: it means the core idea — coordinated, technology-driven dispatch — is proven to work here.'),
  table(
    ['Player', 'Model', 'What it does well', 'Where eKonnect differs'],
    [
      ['Flare / Rescue.co', 'Private subscription; aggregates private ambulance fleets', 'Cut urban response from >160 min to 13 min; established since 2018 with international backing', 'A paid membership product; eKonnect runs a free public SOS network alongside a private tier, and covers fire, flood and security — not ambulances alone'],
      ['Red Cross Kenya app', 'NGO-run emergency reporting', 'Trusted national brand, existing volunteer network', 'No live responder marketplace or verified multi-organisation dispatch; eKonnect is neutral infrastructure any county, hospital or NGO can plug a fleet into'],
      ['County / national 999', 'Manual phone dispatch', 'Universal, no app required', 'No live location, tracking or accountability data; eKonnect keeps 999 as a permanent one-tap fallback rather than competing with it'],
      ['Amber Health, MUrgency', 'On-demand emergency apps abroad', 'Demonstrate the model generalises across emerging markets', 'Not localised to Kenyan regulatory, M-Pesa payment or road/address realities that eKonnect is purpose-built around'],
    ],
    [16, 22, 29, 33],
  ),

  h2('4.3 Unique Value Proposition'),
  table(
    ['Differentiator', 'What it means in practice'],
    [
      ['Faster emergency response', 'Target of under 20 minutes average response, against a baseline measured in hours'],
      ['Real-time GPS tracking', 'Live responder position, road-routed ETA and 3D destination visualisation of the scene'],
      ['One platform, four roles', 'Citizen, ambulance driver, practitioner and administrator share one real-time system instead of separate apps needing manual reconciliation'],
      ['Public and private on the same rails', 'A free public safety net plus subscribed private fleets, without either network\'s data or dispatch logic leaking into the other'],
      ['Beyond ambulances', 'Fire, flood and security are first-class categories, positioning eKonnect as general emergency infrastructure rather than a single-vertical app'],
      ['Governed verification', 'A pending → verified → suspended pipeline gives government and enterprise partners the accountability they require'],
      ['Secured client information', 'Data collected only for active response and verification, aligned to Kenya\'s Data Protection Act, 2019'],
    ],
    [30, 70],
  ),

  h1('5. Business Model & Revenue Streams'),
  p('eKonnect runs a deliberately two-sided model: a public good that must remain free at the point of use, funded like public infrastructure, and a commercial layer on the same platform that pays for it. The separation between the two is enforced in the dispatch logic itself, not by policy alone.'),
  ...figure('routing.png', 'A subscriber reaches their own provider directly; everyone else reaches the public network.', 1500, 620),
  table(
    ['Stream', 'Who pays', 'Basis', 'Timing'],
    [
      ['Public network funding', 'County health budgets, national government, NGO and development partners', 'Grant and partnership funding tied to measurable public-health outcomes', 'Year 1 onward'],
      ['Per-vehicle / per-seat subscription', 'Hospitals, corporates, schools, gated estates', 'Monthly or annual fee per responder or vehicle onboarded', 'Year 2 onward'],
      ['Per-subscriber tiering', 'Hospitals and insurers', 'Priced on number of registered clients covered under their plan', 'Year 2 onward'],
      ['Enterprise contracts', 'Corporates, universities, large estates', 'Annual contract for a dedicated on-site or on-call responder team', 'Year 2 onward'],
      ['Payment float & transaction fees', 'Private subscribers', 'Small fees once M-Pesa (Daraja) billing goes live', 'Year 2+'],
      ['Integration fees', 'Hospitals and insurers', 'Direct billing and patient-record handoff at point of care', 'Year 3+'],
      ['Analytics licensing', 'County governments, public-health researchers', 'Anonymised, aggregated incident and response-time data for planning', 'Year 3+'],
    ],
    [24, 26, 32, 18],
  ),
  spacer(140),
  h2('5.1 Why this model is defensible'),
  p('The public network is what makes eKonnect valuable to government and NGO partners: a measurable public good they can fund and report against. The private subscription layer is what makes eKonnect financially sustainable without depending entirely on grant cycles. Each side strengthens the other — a larger public network of verified responders makes the platform more attractive to private buyers, while private revenue funds the infrastructure the public network runs on.'),

  h1('6. Go-to-Market Strategy'),
  table(
    ['Phase', 'Move', 'Why it works'],
    [
      ['Land', 'A single-county pilot with one public ambulance partner and one private hospital fleet onboard before public launch', 'Enough real supply that the first citizens who press SOS get a genuine response, not a demo'],
      ['Expand', 'Sign the county health department and an anchor provider before opening the public SOS button in each new county', "Keeps the core promise — a responder actually shows up — true in every market entered"],
      ['Monetise', 'Sell private fleets in counties where the public network is visibly working', 'Buyers can see the platform functioning before being asked to pay for it'],
    ],
    [14, 43, 43],
  ),
  spacer(140),
  h2('6.1 Partnerships'),
  bullet('County governments and the Ministry of Health, aligning with the national emergency-response modernisation programme already underway'),
  bullet('NGOs and development partners funding road-safety and maternal-health outcomes measurable through eKonnect incident data'),
  bullet('Private hospital groups and insurers as anchor private-network subscribers and, later, integration partners'),
  bullet('Telecoms and Safaricom/M-Pesa for USSD fallback reporting and subscription billing, extending reach to feature-phone users'),

  h1('7. Operations & Governance'),
  h2('7.1 Responder verification pipeline'),
  p('No one puts themselves on the public emergency network unverified. An administrator promotes a registered user, capturing licence number, vehicle registration and specialisation, and moves them through pending, verified, rejected or suspended states with a note recorded against any rejection. Only a verified responder can go on duty. The same pipeline governs private-team responders, giving enterprise buyers the same assurance over their contracted fleet.'),
  ...figure('verification.png', 'Responders sign up as ordinary users and are promoted and verified by an administrator.', 1500, 560),

  h2('7.2 Assignment modes'),
  table(
    ['Mode', 'How it works', 'Best suited to'],
    [
      ['First-accept', 'The fastest responder to tap Accept takes the job', 'Dense urban coverage where several units are in range'],
      ['Auto-nearest', 'The system assigns the closest available unit automatically', 'Sparse coverage where speed of decision matters more than responder choice'],
    ],
    [18, 42, 40],
  ),
  spacer(140),

  h2('7.3 Incident lifecycle & accountability'),
  p('Every incident carries a full timestamped journey from creation to resolution: when the SOS was raised, when a responder accepted, when they reached the patient, any onward referral to a hospital or clinic, and when the case closed. Cancellations are captured against a structured set of reasons, which turns them from noise into a data source county administrators can use to see where coverage gaps actually are.'),
  ...figure('lifecycle.png', 'The incident journey, including onward referral when the first care point cannot help.', 1500, 620),
  p('Because each transition is stored as its own event, the durations that matter fall out of the data automatically: how long a caller waited for anyone to accept, how long the responder took to reach them, how long they spent on scene, and how long each transport leg took. These are the figures a county partner will hold the network accountable to, and the same journey is shown to the patient in their own history.'),

  h2('7.4 Data protection'),
  p("Location, health-adjacent and identity data are collected only for active incident response and responder verification, consistent with Kenya's Data Protection Act, 2019. Compliance and licensing work is an explicit line item in the funding ask, reflecting that this is treated as a first-class requirement for a government-facing platform, not an afterthought."),

  h1('8. Five-Year Execution Plan'),
  p('This roadmap starts from where the product already is today: working patient, responder and admin applications ready for a first county pilot.'),
  table(
    ['Year', 'Theme', 'Milestones'],
    [
      ['Year 1', 'Foundation', 'Launch MVP into a live pilot · Pilot in one county with a public ambulance partner and one private hospital fleet · Verify and onboard the first 50 responders · Close the KSH 5.7M seed round'],
      ['Year 2', 'Validate', 'Expand to 3–5 counties · Launch private-provider subscriptions as a paid B2B product · Integrate M-Pesa (Daraja) billing · Reach 5,000 registered users and 200 verified responders'],
      ['Year 3', 'Scale', 'National rollout to 15+ counties · Formal county government and NGO partnerships · Multilingual AI triage in Swahili and other local languages · Reach operating break-even'],
      ['Year 4', 'Regional Growth', 'Expand into Uganda, Tanzania and Rwanda · Hospital and insurer billing integrations · Surpass 100,000 users and 2,000 verified responders'],
      ['Year 5', 'Regional Leader', "Established as East Africa's emergency-response backbone · SDG-aligned impact reporting to government and development partners · Raise a Series A"],
    ],
    [11, 19, 70],
  ),

  h1('9. Financial Plan'),
  h2('9.1 The ask: KSH 5.7 million'),
  p('This round funds eKonnect from a pilot-ready product to a verified, government- and partner-facing county launch. It is deliberately weighted toward infrastructure reliability and compliance — the two things a public-sector or hospital partner will diligence hardest — alongside the remaining engineering work.'),
  table(
    ['#', 'Category', 'What it covers', 'Amount (KSH)'],
    [
      ['1', 'Infrastructure & uptime', 'Cloud hosting with redundancy, real-time data services, backup and disaster recovery', '1,700,000'],
      ['2', 'Data security & compliance', 'Data-protection licensing and compliance for a government- and health-facing platform', '500,000'],
      ['3', 'People & operations', 'Responder training and organisational change management during county onboarding', '500,000'],
      ['4', 'Project development', 'Remaining engineering: M-Pesa billing, offline resilience, admin reporting', '2,000,000'],
      ['5', 'Contingency & working capital', 'Buffer for pilot-phase operating costs and unplanned costs during first county launch', '1,000,000'],
      ['', 'Total', '', '5,700,000'],
    ],
    [6, 24, 48, 22],
  ),
  spacer(120),
  p([text('Note: the fifth line item — a KSH 1.0M contingency and working-capital buffer — reconciles the funding ask with the itemised budget; the first four categories alone total KSH 4.7M against the KSH 5.7M headline ask.', { size: 17, color: GREY, italics: true })]),

  h2('9.2 Illustrative revenue projection'),
  p('The figures below are planning estimates, not forecasts of committed revenue, built from the subscription and grant assumptions in Section 5. They show the shape of the business — grant-funded public infrastructure in Year 1, a growing private-subscription base from Year 2, and break-even by Year 3.'),
  table(
    ['Year', 'Public funding (grants/gov\'t)', 'Private subscriptions', 'Total', 'Status'],
    [
      ['Year 1', 'KSH 5.7M (this raise)', '—', 'KSH 5.7M', 'Seed-funded pilot'],
      ['Year 2', 'KSH 6–8M', 'KSH 2–3M', 'KSH 9–11M', 'Early commercial revenue'],
      ['Year 3', 'KSH 10–14M', 'KSH 10–14M', 'KSH 20–28M', 'Operating break-even'],
      ['Year 4', 'KSH 15–20M', 'KSH 25–35M', 'KSH 40–55M', 'Private revenue majority'],
      ['Year 5', 'KSH 20–25M', 'KSH 45–60M', 'KSH 65–85M', 'Series A readiness'],
    ],
    [11, 24, 20, 18, 27],
  ),
  spacer(140),
  h2('9.3 Path to break-even'),
  p('Break-even is targeted for Year 3, once the private-subscription line grows large enough to cover infrastructure and operations independent of any single grant cycle. Public-network funding continues throughout, but the business does not depend on it for solvency past Year 3 — the point at which eKonnect is defensible as a company rather than only as a funded programme.'),

  h1('10. Impact & SDG Alignment'),
  p('eKonnect is designed against measurable outcomes, not activity, and those outcomes map directly onto three UN Sustainable Development Goals.'),
  table(
    ['Goal', 'Target', 'Measure by Year 5'],
    [
      ['SDG 3 — Good Health and Well-Being', 'Reduce average emergency response time to 30 minutes or less nationwide by Year 3, cutting preventable deaths inside the Golden Hour', 'Under 20 minutes average response time'],
      ['SDG 9 — Industry, Innovation and Infrastructure', 'An interoperable, cloud-native dispatch platform integrated with county and private health infrastructure', 'Active in 15+ counties; 3,500+ verified ambulances and practitioners'],
      ['SDG 11 — Sustainable Cities and Communities', 'A combined public-private responder network giving urban and rural communities a functioning safety net', '250,000+ citizens covered; 500+ verified responders on duty'],
    ],
    [26, 44, 30],
  ),

  h1('11. Risks & Mitigation'),
  table(
    ['Risk', 'Mitigation'],
    [
      ['Connectivity gaps in rural areas', 'A one-tap "Call 999" fallback on every screen; a USSD reporting channel planned for feature-phone and low-connectivity users'],
      ['Public network depends on grant funding', 'Private-subscription revenue is designed to reach operating break-even by Year 3, reducing dependence on any single funding cycle'],
      ['Responder verification bottleneck or liability exposure', 'A structured pending/verified/rejected/suspended pipeline with recorded admin decisions keeps unverified people off the network and creates an audit trail'],
      ['Health and location data privacy', "Data collected only for active incident response and verification, in line with Kenya's Data Protection Act, 2019; compliance work explicitly funded in this raise"],
      ['Competition from an established, internationally backed player', 'eKonnect differentiates on a free public network plus multi-agency incident types (fire, flood, security), not ambulance dispatch alone'],
      ['Payment integration risk (M-Pesa/Daraja dependency)', 'Public SOS functionality has no payment dependency at all; billing risk is isolated to the private-subscription revenue line'],
      ['AI triage reliability', 'The AI assists and never gatekeeps: any failure falls back to manual category selection, and low-confidence results are flagged for the caller to confirm'],
    ],
    [34, 66],
  ),

  h1('12. Team'),
  table(
    ['Name', 'Role', 'Contribution'],
    [
      ['Benard Phabian', 'Software Designer', 'Leads product and engineering across the Flutter mobile app and React admin dashboard'],
      ['Januaris Kibet', 'Paramedic', 'Clinical and field-operations input on responder workflows'],
      ['John Kyalo', 'Paramedic', 'Clinical and field-operations input on responder workflows'],
      ['Milkah Albert', 'Healthcare Provider', 'Healthcare-system and patient-experience input'],
      ['Dr Tecla Sum', 'Supervisor', 'Project oversight and advisory support'],
    ],
    [24, 24, 52],
  ),

  h1('13. The Ask'),
  spacer(60),
  callout('KSH 5,700,000', 'To move from a working, pilot-ready product to a verified county launch — the single step that turns a well-built app into a functioning emergency-response network people can trust with their lives.'),
  spacer(200),
  p('The team is not asking anyone to bet on an idea. The patient app, responder app and admin dashboard already work today. What this raise buys is the infrastructure hardening, compliance, training and remaining integration work needed to put that product safely in front of a county\'s citizens — and the responders who will answer their call.'),
  spacer(240),
  new Paragraph({
    spacing: { before: 200 },
    border: { top: { style: BorderStyle.SINGLE, size: 12, color: PURPLE } },
    children: [],
  }),
  new Paragraph({
    spacing: { before: 160 },
    children: [
      text('Contact  ', { size: 19, bold: true, color: PURPLE, allCaps: true }),
      text('Benard Phabian · Software Designer, eKonnect', { size: 20, color: INK }),
    ],
  }),
]

// ── document ─────────────────────────────────────────────────────────────────

const doc = new Document({
  creator: 'eKonnect',
  title: 'eKonnect — Concept Note & Business Plan',
  description: 'Concept note and business plan for the eKonnect emergency response platform',
  styles: {
    default: {
      document: { run: { font: 'Calibri', size: 21, color: INK } },
    },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Calibri', size: 30, bold: true, color: PURPLE } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Calibri', size: 24, bold: true, color: PURPLE } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Calibri', size: 21, bold: true, color: INK } },
    ],
  },
  sections: [
    {
      properties: {
        page: {
          margin: {
            top: convertInchesToTwip(0.9), bottom: convertInchesToTwip(0.9),
            left: convertInchesToTwip(0.95), right: convertInchesToTwip(0.95),
          },
        },
      },
      headers: {
        default: new Header({
          children: [
            new Paragraph({
              alignment: AlignmentType.RIGHT,
              spacing: { after: 100 },
              border: { bottom: hairline },
              children: [
                text('eKonnect  ·  Concept Note & Business Plan', { size: 16, color: GREY }),
              ],
            }),
          ],
        }),
      },
      footers: {
        default: new Footer({
          children: [
            new Paragraph({
              alignment: AlignmentType.CENTER,
              border: { top: hairline },
              spacing: { before: 100 },
              children: [
                text('Page ', { size: 16, color: GREY }),
                new TextRun({ children: [PageNumber.CURRENT], size: 16, color: GREY }),
                text(' of ', { size: 16, color: GREY }),
                new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 16, color: GREY }),
                text('   ·   August 2026', { size: 16, color: GREY }),
              ],
            }),
          ],
        }),
      },
      children: [...cover, ...contents, ...body],
    },
  ],
})

const buffer = await Packer.toBuffer(doc)
writeFileSync(OUT, buffer)
console.log(`Written: ${OUT} (${(buffer.length / 1024).toFixed(0)} KB)`)

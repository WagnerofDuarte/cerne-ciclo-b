---
title: "PRFAQ: cerne-ciclo-b"
status: "complete"
created: "2026-10-25T20:04:27Z"
updated: "2026-10-25T20:34:00Z"
stage: 5
inputs:
  - docs/input/requirements.md
  - docs/input/prototype/prototype-extract.md
  - docs/input/backend/README.md
  - _bmad-output/brainstorming/brainstorm-f000-foundation-choices-2026-10-25/
  - _bmad-output/forge/f000-foundation-decisions/
  - _bmad-output/planning-artifacts/research/technical-flutter-package-selection-for-f000-and-r-2026-10-25/
  - web research: AI journaling app competitive landscape (2026-10-25)
---

# Cerne Turns Your Journal Into an AI That Remembers What You Told It

## For people who gave up on journaling because nothing ever answered back, Cerne is an AI you talk to that actually remembers your own entries — and never sends your voice off your phone

**SÃO PAULO, Brazil — March 2027** — Today marks the launch of Cerne, a mobile journaling app for people who want to think out loud about their day — by typing, speaking, or snapping a photo — and get an AI companion that remembers what they said last week, last month, or three months ago. Unlike generic AI chatbots that forget everything the moment a conversation ends, Cerne searches back through a person's own past entries to answer with real context, not generic advice.

Most people who try journaling quit within weeks. Paper notebooks pile up unread. Notes apps become a graveyard of unsearched text. A growing number of people have started typing their day out to a general-purpose AI chatbot instead — only to find every conversation starts from zero: the bot has no memory of the stressful week they mentioned a month ago, no way to connect today's frustration to a pattern from three months back. And anyone who has poured private thoughts into an AI has had the same quiet worry: who else can read this, and where does it go?

Cerne changes what it feels like to look back at your own life. Every entry — typed, spoken, or photographed — becomes something you can actually ask about later: "What was going on with me in July?" or "Have I felt this way before?" get answered with your own words, not a canned response. Voice entries are transcribed on the phone itself and never leave the device as audio. And because Cerne is explicitly not a therapy or diagnosis tool, it never pretends to analyze your mental health — it just helps you see your own patterns, in your own words, for yourself.

> "We didn't want to build another chatbot that forgets you the second you close the app. We wanted something that treats your own past the way a good friend does — remembering, without ever making you feel watched."
> — Wagner Duarte, Creator of Cerne

### How It Works

Open Cerne and the first thing you see is a simple prompt: type, talk, or snap a photo of something from your day. No setup, no mood sliders, no forced categories. A few weeks in, start a conversation — ask Cerne anything about what you've written, and it searches your own entries to answer, quoting back what you actually said instead of guessing. Every so often, without being asked, Cerne notices something — a pattern across a handful of entries, a quiet period, a recurring theme — and raises it gently inside the conversation, never as an interruption you can't dismiss. When a conversation surfaces something worth keeping, one tap saves it as its own entry, so nothing important gets lost in chat history.

> "I used to just talk to ChatGPT about my day and then... nothing. It forgot everything by the next morning. Last week I asked Cerne why I'd been so anxious lately, and it reminded me of three entries from a month ago I'd completely forgotten I wrote. That's the first time an app actually felt like it knew me."
> — early user, translated from Portuguese

### Getting Started

Cerne launches on iOS first. Behind a Face ID, Touch ID, or PIN lock from the very first screen, signing up takes under a minute — and the only setup required is your first entry, in whichever form feels easiest: typed, spoken, or photographed.

---

## Customer FAQ

### Q: Is Cerne a mental health app? Can it tell if I'm struggling, or help if I am?

A: No. Cerne is explicitly not a therapy, diagnostic, or crisis tool. As of this build, there's no mechanism that detects risk signals like self-harm or suicidal ideation in what you write — that's a deliberate scope decision, not an oversight. If you're in crisis, Cerne doesn't recognize that and won't point you anywhere for help. Treat it as a tool for noticing your own patterns, not as support for a crisis.

### Q: Can anyone — including whoever built Cerne — read what I write?

A: Your entries are stored in a cloud backend, not only on your phone — Cerne has no offline-write mode. Row-level security restricts each account to its own data, the AI pipeline that processes a request doesn't retain anything beyond that request, and you can permanently and completely erase your account at any time. The one thing that genuinely never leaves your device is raw audio: voice entries are transcribed on-device, and only the resulting text — not the recording — is ever sent anywhere. That's a real privacy boundary, but it's not the same as "nothing ever leaves your phone," and you should know that distinction before trusting it with anything you'd want to stay unrecoverable.

### Q: How do I know the AI's insights and summaries are actually good, and not generic filler?

A: Honestly, this build doesn't prove that yet. What's verified is that insight and summary generation don't crash, handle failures gracefully, and render correctly — not whether the text itself is perceptive. Whether Cerne's AI responses feel genuinely specific to you, rather than the same "generic AI response" complaint leveled at every competitor in this space, is the single biggest unproven assumption behind the whole idea.

### Q: How is this different from just talking to ChatGPT about my day?

A: ChatGPT doesn't remember your past sessions — every conversation starts from zero. Cerne's chat runs a real semantic search over your own past entries before it answers, so it can reference something you wrote two months ago by meaning, not exact wording. That persistent, personal memory is the entire bet Cerne is making.

### Q: Can I edit or delete a single entry after I've written it?

A: No — entries are immutable once saved; there's no way to edit or delete just one. You can delete your entire account and everything in it, but not a single entry in isolation. If you write something you regret, today the only fix is all-or-nothing.

### Q: Does Cerne work without an internet connection?

A: You can view entries you've already loaded while offline, but you can't capture a new one — text, voice, or photo — until you're back online. Cerne doesn't queue offline writes to sync later; it simply can't create entries offline.

### Q: Can Cerne automatically organize my entries by mood or topic?

A: No — tags are manual, added by you. Automatic categorization was considered and cut from this build to keep scope realistic; it isn't in the current product.

### Q: What does Cerne cost, and will it still exist next year?

A: Cerne was built as an academic capstone project, not a commercial product — there's no pricing model, and no commitment about it being available or maintained beyond the project. If you're sizing this up as a real product rather than a student build, that's an honest open question, not a settled answer.

### Q: If I lose my phone, do I lose my journal?

A: No — your entries live in the cloud, so logging in on a new device restores your full journal. The only loss would be anything mid-capture — a recording in progress, for instance — that never finished syncing before the phone was lost.

---

## Internal FAQ

### Q: If a committee member asks why an unverified-quality AI is the product's core differentiator, what do we say?

A: We can't claim the AI insights are actually good — only that the mechanism around them (triggering, rendering, failure handling) works. The honest defense-day answer is that this project's scope is the software-engineering challenge — Clean Architecture, state management across layers, Flutter/BLoC discipline, graceful failure handling — not prompt engineering or AI output quality, which is treated as a black box the system must handle gracefully regardless of what comes back. That's a legitimate framing for an engineering capstone, but it only holds if the written defense says this explicitly, instead of letting press-release language like "an AI that gets you" imply more than the grading actually verifies.

### Q: The planning artifacts already disagree on local caching — drift (SQLite) vs. Hive. Which is it, and does it matter?

A: Right now it isn't settled. The Flutter package research recommended `drift` for the local cache; the later forge decision overrode it to `Hive`, reasoning that since all filtering/pagination happens via server-side query params, there's no need for a relational query engine on-device. That's a defensible reason, but two of this project's own planning artifacts currently disagree and nobody has gone back to reconcile them. What it would take to resolve: explicitly marking the `drift` recommendation as superseded in the research artifact before F000 implementation starts — a five-minute fix, but only if it's done before, not after, code gets written against one assumption or the other.

### Q: What's the single hardest technical problem in this build?

A: Two candidates, both state-management problems rather than AI problems. RF07's history screen depends on three independently-changing streams at once — auth session, sync-badge status, entry data — while explicitly forbidding one BLoC from importing another. RF08's proactive-insight trigger must fire exactly once per satisfied condition (5 user messages OR 2 minutes of inactivity) without double-firing or missing the window during an active chat session. Both are solvable with standard Flutter patterns (stream combination, debounce timers), but "solvable in principle" and "built and tested" are different claims — neither exists yet.

### Q: What's the realistic timeline, and does the delivery order actually fit?

A: The input package gives a delivery order — F000 → RF03 → RF01 → RF02 → RF07 → RF06 → RF04 → RF10 → RF08 → RF05 → RF09 — but no explicit deadline date, hours-per-week budget, or buffer appears anywhere in `docs/input/` or `_bmad-output/`. That's a real unknown, not a solved one. What it would take to find out: the actual course calendar and defense date, which only the student has — until that's pinned down, nobody can say with confidence whether 10 functional requirements plus RNF07's 80%-domain-coverage bar and RNF09's 15 tested failure scenarios fit in the time available.

### Q: What kills this project — not the app, the grade?

A: Two concrete ways. First, scope creep into the explicitly excluded extension features (dynamic AI categorization, autonomous goal extraction, dynamic persona adjustment) under the pressure to make the demo look more impressive — `requirements.md` already forbids this, so the discipline has to hold under deadline stress, not just on paper. Second, a blocking bug in the frozen backend that has no code-side remedy, since "never change the backend" is a hard policy — any such bug can only be worked around or documented as a known limitation, never fixed.

### Q: What's already been said no to, and will that discipline hold?

A: The three extension features were already cut to static or manual stand-ins — manual tags instead of AI categorization, a static kanban instead of autonomous goal extraction, a cosmetic toggle instead of dynamic persona adjustment. That "no" is already on record. The open question is whether it holds when a committee member asks "why doesn't it do X" — the honest answer has to be "that was deliberately out of scope," not "we ran out of time," and those two answers land very differently in a defense.

### Q: What's the actual legal/regulatory exposure here?

A: For a real commercial launch, handling personal journal entries through a cloud backend would draw genuine LGPD scrutiny. For this project specifically, the exposure is close to zero in practice — there's no live user base beyond test/demo accounts. But the architecture still has to demonstrate the compliance posture (row-level security, hard delete, no retention in the AI pipeline) because that's part of what's being graded as sound engineering, not because real regulatory risk exists yet. Don't let "it's just a student project" become an excuse to skip demonstrating it.

### Q: What happens to Cerne after the defense?

A: No plan exists anywhere in the input package — no stated intent to publish it, maintain it, or carry it forward as a portfolio piece beyond the TCC itself. That's fine for a capstone, but worth deciding explicitly rather than leaving implicit: is this a one-time academic artifact, or is surviving this PRFAQ process also meant to produce something that works in a job-application portfolio? The answer changes how much the distribution and "Getting Started" questions from the Customer FAQ actually matter going forward.

---

## The Verdict

**Concept strength:** Sharp as a disciplined engineering capstone wrapped in a genuinely researched product thesis — soft wherever it depends on something outside this project's control (a deadline, a committee's reading of the scope boundary, a backend it cannot touch). The product thinking survived the gauntlet; what's underdeveloped is the plan for saying the hard parts out loud before someone else finds them.

**Forged in steel:**
- The core differentiator — persistent, semantic memory over your own entries, versus the "generic AI response" fatigue that's the #1 complaint against every competitor studied (Reflectly, Day One AI, Mindsera) and versus session-less tools like ChatGPT — is specific, researched, and survived every FAQ question aimed at it without resorting to marketing language.
- The privacy architecture is real and precisely qualified, not oversold: on-device Whisper transcription, row-level security, hard delete for LGPD are named exactly, and the Customer FAQ explicitly corrects the tempting overclaim ("nothing ever leaves your phone") to what's actually true (the audio stays local; the transcribed text does not).
- The non-clinical positioning, forced by the product's own scope decision, lines up with where the regulatory and reputational winds are actually blowing for companion/emotional-support AI right now — a genuine, evidence-backed timing advantage, not just a constraint dressed up as a feature.
- Resource discipline is already demonstrated, not promised: three extension features were concretely cut to static/manual stand-ins, on record in `requirements.md` section 2, which gives a clean, honest answer to "why doesn't it do X" instead of "we ran out of time."

**Needs more heat:**
- No deadline, hours-per-week budget, or buffer exists anywhere in the input package — feasibility of the delivery order (F000 → RF03 → … → RF09) against RNF07/RNF09's testing bars can't be honestly assessed until that date is pinned down.
- The post-defense fate of the project (one-time academic artifact vs. a piece meant to survive into a portfolio) is undecided, and it changes how much the distribution/"Getting Started" questions actually matter.
- Two cheap, already-identified fixes are sitting un-actioned: reconciling the `drift`-vs-`Hive` contradiction between two prior planning artifacts, and adding a no-detection-required crisis-resources disclaimer as a low-cost fast-follow to the non-clinical scope.

**Cracks in the foundation:**
- The deepest crack isn't in the product thinking — it's in what the written defense says about it. The press release promises an AI that "actually remembers and gets you"; the grading scope explicitly never verifies whether the generated insight is actually good, only that the mechanism around it doesn't break. That gap is a legitimate and defensible engineering-scope boundary — but only if the defense states it explicitly. Left unstated, it's exactly the unexamined assumption a committee member probing "why is an unverified AI your core differentiator" would expose as having never been confronted — when in fact this document confronted it directly. The fix is one explicit paragraph in the written defense, not a code change.
- Entry immutability (no per-entry edit/delete, forced by the frozen backend contract) is a real adoption-friction crack for any future use of this product beyond the TCC. It can't be fixed within this project's constraints, but it should be named as a known limitation on the record — not something a future reviewer or user discovers on their own.

<!-- coaching-notes-stage-1 -->
**Concept type:** Academic capstone (TCC) built and evaluated like a real product — no commercial metrics (no "first 100 customers," no unit economics), but customer-first discipline enforced anyway rather than defaulting to a rubric-shaped document.

**Initial assumption challenged:** `docs/input/requirements.md` is organized entirely around RF01–RF10/screens and never names a customer or problem — confirmed via Artifact Analyzer read of the full spec. Working Backwards cannot start from a feature list, so a persona and problem had to be reconstructed from indirect signals (UI language, architectural choices, explicit non-goals) rather than stated directly anywhere in the input package.

**Why this direction over alternatives:** Considered running the PRFAQ at the whole-app level vs. a single feature (RF08 proactive insights, or RF05 summary export) in isolation. Chose the whole-app level because the reconstructed customer problem (AI that forgets / generic AI loops / privacy anxiety about an AI reading private writing) is the thesis the entire feature set serves — RF01/RF02 (capture), RF04 (RAG chat), RF08 (proactive insight), RF05/RF09 (summary/dashboard) are all expressions of one underlying promise ("an AI that actually remembers and connects your own entries, privately"), not independent value props. A single-feature PRFAQ would have had to re-derive the same customer anyway.

**Key subagent findings that shaped framing:**
- Artifact Analyzer: RF05/RF08/RF09 each explicitly scope grading to "mechanism only, never the quality of the generated narrative text" — the actual customer-facing value (is the insight good?) is unverified by the project's own grading criteria. Decision: name this openly in the Internal FAQ as a known limitation, not hide it. The press release itself stays an honest outcome promise; the hedge belongs in the internal, not customer-facing, half of the document.
- Artifact Analyzer: explicit policy, verbatim — "the system has no protocol for detecting or responding to risk signals (suicidal ideation, self-harm)... the product is not framed as a mental-health app." Hard constraint: press release language must stay in "understand your own patterns" territory, never "feel better" / therapeutic territory.
- Web Researcher: "generic AI response" fatigue is the most common complaint across every AI-journaling competitor studied (Reflectly, Day One AI, Mindsera) — this is exactly the dimension RF05/08/09 don't grade on, sharpening the tension above rather than resolving it.
- Web Researcher: regulatory climate (Italy's €5M fine on Replika's maker, California's 2026 companion-chatbot disclosure law) makes Cerne's rigorously non-clinical positioning a genuine timing advantage, not just a scope cut forced by the TCC constraints.
- Web Researcher: on-device Whisper STT (audio never leaves the device), zero data retention, RLS, and LGPD hard-delete are real, honestly-claimable privacy differentiators — validated against user sentiment showing deep (if under-the-radar) anxiety about trusting an app with years of private writing.

**User context not captured in the PRFAQ body itself:** User directed the workflow to "use your technical judgment, following the input package" at two separate decision points (contextual gathering, and the customer/problem/tension framing) rather than answering interactively — i.e., explicitly delegating judgment calls to stay within what `docs/input/` and prior `_bmad-output/` artifacts already establish, per the repo's own policy ("Where docs/input/ is silent on a technical choice, decide and proceed").
<!-- /coaching-notes-stage-1 -->

<!-- coaching-notes-stage-2 -->
**Rejected headline framings:** "Cerne Lets You Actually Talk to Your Own Diary — Privately, and It Remembers" (too long, "actually"/"privately" read as unproven claims stacked in the headline itself); anything invoking "AI companion" or "AI friend" (too close to the companion-chatbot category the research flagged as under regulatory and reputational pressure — avoided deliberately, not an oversight).

**Competitive positioning discussed:** Positioned implicitly against two groups, not named in the press release itself (press releases don't name competitors): (1) incumbent journaling apps with AI bolted on as a paywalled add-on (Day One, Reflectly) — Cerne's RAG-over-own-entries is core, not a premium layer; (2) general-purpose chatbots (ChatGPT) used ad hoc for journaling — Cerne's differentiator there is persistent memory of the user's own words, which the "How It Works" and user quote sections lean on directly.

**Differentiators explored but not used:** Considered leading the headline/subhead with the on-device Whisper privacy angle ("your voice never leaves your phone") instead of the memory angle. Rejected as the lead because user research showed "AI forgets me / gives generic responses" is the louder, more universal pain point; privacy is used instead as the proof point inside the problem/solution paragraphs and in "Getting Started" (biometric lock), which is honest placement without overselling it as the headline hook.

**Out-of-scope / known-gap items surfaced but deliberately excluded from the press release text:**
- No app store or distribution channel is named — the TCC has no confirmed public release plan, so "Getting Started" says only "launches on iOS first" rather than inventing a store listing or launch mechanism.
- The customer quote is a constructed stand-in consistent with Working Backwards methodology (the press release is written before the product exists), not a real testimonial — flagging this explicitly so it is never mistaken for actual user research later.
- The quality-gap tension from Stage 1 (RF05/08/09 scope out narrative quality from grading) is deliberately absent from the press release itself — it belongs in the Internal FAQ (Stage 4), not the customer-facing document, per the Stage 1 decision.
<!-- /coaching-notes-stage-2 -->

<!-- coaching-notes-stage-3 -->
**Gaps revealed by customer questions, classified:**
- No crisis-signposting even without detection logic (Q1) — **accepted trade-off for this build, but flagged as a worthwhile fast-follow**: a static disclaimer/resource link needs no risk-detection logic and would not contradict the non-clinical-framing policy, so it's a low-cost gap to close later even though full detection stays out of scope.
- AI insight/summary quality is unverified (Q3) — **accepted trade-off**, directly inherited from RF05/RF08/RF09's grading scope ("mechanism only, never quality"). Named here as the single largest open risk to the actual value proposition, not softened.
- Entries are immutable, no per-entry edit/delete (Q5) — **accepted trade-off**, forced by the frozen backend contract (no `PATCH`/`DELETE /entries/:id`). Real adoption friction for a journaling app; not something this project can change.
- No offline write / no sync queue (Q6) — **accepted trade-off**, a direct consequence of the cloud-only architecture decision already fixed in `docs/input/backend/`.
- No automatic categorization (Q7) — **accepted trade-off**, maps directly to the extension feature explicitly excluded in `requirements.md` section 2.

**Competitive intelligence used:** Q3 and Q4 answers draw directly on the Stage 1 web research — "generic AI response" fatigue as the category's #1 complaint, and ChatGPT's lack of persistent memory as the comparison point that makes Cerne's RAG-over-own-entries legible to a skeptical reader.

**Scope/requirements signal:** Q5 and Q7 both independently converge on exactly the fault lines `requirements.md` already named (entry immutability; excluded extension features) — the customer-FAQ pressure test corroborates the input docs rather than surfacing anything new or contradictory, which is a healthy sign for input-package fidelity.
<!-- /coaching-notes-stage-3 -->

<!-- coaching-notes-stage-4 -->
**Feasibility risks identified:**
- RF07's three-independent-stream composite state (auth × sync-badge × entry data) under the "no BLoC imports another BLoC" rule, and RF08's exactly-once trigger semantics (5 messages OR 2 min inactivity) — both flagged as the hardest unsolved technical problems; standard patterns exist (stream combination, debounce) but neither is built yet.
- A live, unreconciled contradiction between two prior planning artifacts: `research.md` recommends `drift` for local cache, `forged-idea.md` overrides it to `Hive`. Surfaced here rather than left to resurface mid-implementation. Recommended fix: mark `drift` as explicitly superseded in the research artifact before F000 starts.

**Resource/timeline estimates discussed:** No deadline date, hours-per-week budget, or buffer exists anywhere in `docs/input/` or `_bmad-output/`. Flagged as an honest unknown rather than papered over — "what would it take to find out" answer: the course calendar/defense date, which only the user holds.

**Unknowns flagged with "what would it take to find out" answers:**
- Timeline fit for 10 functional reqs + RNF07 (≥80% domain coverage) + RNF09 (15 failure scenarios) → needs the actual defense date.
- Drift vs. Hive → needs five minutes reconciling the two existing artifacts, not new research.
- Post-defense fate of the project (one-time academic artifact vs. portfolio piece) → needs an explicit decision from the user, not inference from docs.

**Strategic positioning decisions:** Treated "unit economics"/"customer acquisition"/"competitive moat" as not applicable to a solo-TCC concept type and substituted feasibility, delivery-order fit, and scope-discipline-under-pressure as the equivalent internal stakes, per the skill's non-commercial calibration guidance.

**Technical constraints/dependencies surfaced:** Frozen backend means any backend-side bug has no code-side remedy (policy: never change the backend) — only workaround or documented limitation. LGPD compliance posture (RLS, hard delete, zero AI-pipeline retention) must still be demonstrated for grading purposes even though real-world regulatory exposure is near zero for a project with no live user base.
<!-- /coaching-notes-stage-4 -->

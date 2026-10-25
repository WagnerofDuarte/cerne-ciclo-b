# Cerne — Prototype extract

The visual reference of the product is `cerne-prototype.html` (this folder). Open it in a browser; it needs JavaScript. This extract lists its navigable states, its visual tokens, its components and the implementation notes that come with it.

- **Frame:** 390 × 844 logical points, portrait only, 4 dp grid.
- **Language of the interface:** Portuguese. Every UI text below appears exactly as in the prototype, in quotes.
- **Precedence:** the prototype defines appearance and states. Behavior rules (triggers, timings, filters, error handling) are defined in `docs/input/requirements.md`; where the prototype's simulated behavior differs from a requirement, the requirement prevails.

---

## 1. Navigation map

The prototype has **32 navigable states**, reachable from a single state machine (a `screen` variable plus overlay flags). Not every state is a new full screen — several are **overlays** (modal, sheet, bottom sheet, dialog) shown on top of one of three base screens: **Home/Chat**, **Meus Registros** and **Configurações**. Overlays preserve the screen underneath (it stays visible, with a darkened scrim behind).

```
Splash (auto, 1.8 s)
  └─> Biometria ──tap/error──> PIN inicial / PIN após falha
  │      └─> "usar e-mail e senha" ──> Entrar / criar conta (toggle)
  │                                          └─> submit ──> Home/Chat
  └─(PIN complete, 4 digits)──> Home/Chat
  └─(Face ID/Touch ID ok)──> Home/Chat

Home/Chat (base screen)
  ├─ overlay: Sessão expirada (backend session expires; "Entrar novamente" ──> Biometria)
  ├─ overlay: side menu (☰ icon) ──> Meus Registros | Planos de Ação | Configurações | new conversation
  └─ overlay: Insertion modal ("+" button) ──> tabs Texto / Áudio / Foto, each with its own sub-states
        (on save, the modal closes and returns to Home/Chat with the record added)

Meus Registros (base screen, from the side menu)
  ├─ empty state (no records) ──CTA "Criar primeiro registro"──> Insertion modal
  ├─ overlay: filter sheet ──"Aplicar"──> active filters (chips on the list)
  └─ overlay: export card (download icon) ──> pending ──> processing ──> done | error | empty period

Planos de Ação (base screen, from the side menu) — static screen, 3-column kanban (extension, not implemented)

Configurações (base screen, from the side menu)
  ├─ dashboard variations: zero entries | one entry | more than 30 (with narrative) | narrative unavailable
  ├─ inline profile-name editing
  ├─ AI persona selection (Analítico / Empático / Socrático) (extension, not implemented)
  ├─ "Sair" ──> Biometria
  └─ overlay: account-deletion confirmation ──"Apagar tudo"──> Biometria (same destination as logout)
```

---

## 2. Navigable states

Names as they appear in the prototype. The prototype's own state catalog has 32 entries: Tela 0 — Splash; Tela 0.1 — Biometria; Tela 0.1a — Entrar / criar conta; Tela 0.1b — PIN inicial; Tela 0.1c — PIN após falha; Tela 1 — Home / Chat; Tela 2 — Texto, Áudio (Gravando, Processando, Transcrito, Erro), Foto (Captura, Processando OCR, Reconhecido, Erro); Tela 3 — Menu lateral; Tela 1 — Sessão expirada; Tela 4 — Meus Registros, Estado vazio, Sheet de filtro, Filtros ativos; Exportar — Pendente, Processando, Concluído, Erro, Período vazio; Tela 5 — Planos de Ação **[ext]**; Tela 6 — Configurações, Dashboard zero entradas, Dashboard uma entrada, Narrativa indisponível, Confirmar exclusão. The tables below group them by screen; some rows describe variations inside one state (e.g., the bookmark sub-states, the streaming response). Extension states (requirements, section 2) are marked **[ext]**.

### 2.1 Entry and authentication
| State | What it shows |
|---|---|
| Tela 0 — Splash | Wordmark "Cerne" centered on dark green, 3 loading dots; lasts 1.8 s and moves on automatically. |
| Tela 0.1 — Biometria | Fingerprint circle, title "Toque para desbloquear", link "Usar PIN", secondary link "usar e-mail e senha" near the bottom. |
| Tela 0.1a — Entrar | Login mode: title "Bem-vindo de volta", fields E-mail and Senha, CTA "Entrar", toggle link, link "usar biometria". |
| Tela 0.1a — Criar conta | Same screen in sign-up mode: title "Crie sua conta", CTA "Criar conta" (toggled by a text link, not a separate screen). |
| Tela 0.1b — PIN inicial | Title "Digite seu PIN", 4 progress dots, 3×4 numeric keypad with backspace; after the 4th digit, moves on after 350 ms. |
| Tela 0.1c — PIN após falha | Same as 0.1b plus the error band "Não foi possível reconhecer — digite seu PIN". |

### 2.2 Conversation
| State | What it shows |
|---|---|
| Tela 1 — Home/Chat (default) | Messages going back and forth; dark green fixed header with ☰ and wordmark; composer with "+", placeholder "Escreva uma mensagem...", send icon. |
| Tela 1 — Streaming | AI response revealed progressively with a pulsing cursor. |
| Tela 1 — Insight | Insight card with ochre spine, label "INSIGHT", "x" to dismiss, interleaved in the messages. |
| Tela 1 — Falha ao gerar resposta | Incomplete AI message with "Falha ao gerar resposta — toque para tentar novamente" in red, in place of the time. |
| Tela 1 — Bookmark | Bookmark on each user message with 4 sub-states: `idle`, `saving` (spinner), `saved` (ochre check), `error` (red warning). |
| Tela 1 — Offline | Blue-gray banner "Sem conexão — histórico disponível, novas mensagens bloqueadas"; send icon disabled. |
| Tela 1 — Sessão expirada | Light scrim over the chat (still readable), centered card with lock icon, title "Sessão expirada", text saying history and scroll position are kept, button "Entrar novamente". |
| Tela 3 — Menu lateral | Drawer: initials avatar and name; section "CONVERSAS" with past sessions (title + timestamp); items "Meus Registros", "Planos de Ação", "Configurações"; new-conversation action. |

### 2.3 Insertion modal (bottom sheet over Home/Chat; 9 states)
Common structure: "x" to close and a 3-tab bar (Texto / Áudio / Foto); the active tab has a filled dark-green background.

| State | What it shows |
|---|---|
| Texto | Multiline field, placeholder "Escreva livremente...", button "Salvar". |
| Áudio — Gravando | Red stop button, animated 12-bar waveform, monospace timer (e.g., "00:12"). |
| Áudio — Processando | Spinner in place of stop; frozen, faded waveform (opacity .35); text "Transcrevendo..."; label "00:42 de áudio". |
| Áudio — Transcrito | Editable transcribed text; original audio duration in mono; "Salvar" enabled. |
| Áudio — Erro | Red warning icon, "Não foi possível transcrever", outline button "Tentar novamente". |
| Foto — Captura | Two large buttons, "Câmera" and "Galeria". |
| Foto — Processando OCR | Photo thumbnail, spinner, "Reconhecendo texto...". |
| Foto — Reconhecido | Small thumbnail next to the extracted (editable) text; "Salvar". |
| Foto — Erro | Thumbnail kept, warning icon, "Não foi possível reconhecer o texto", button "Tentar novamente" and secondary text action "Salvar só a foto". |

### 2.4 Records
| State | What it shows |
|---|---|
| Tela 4 — Meus Registros (default) | Records grouped by date ("Hoje", "Ontem", dates); each card with a spine colored by origin, source icon, time, sync indicator (green "sincronizado" / ochre "sincronizando" / red "erro de sync"), text excerpt, category chips when present; header with back arrow, title, download icon; search bar "Buscar nos registros..." with a funnel button. |
| Tela 4 — Vazio | Large notebook icon, "Nenhum registro ainda", CTA "Criar primeiro registro". |
| Tela 4 — Filtros ativos | Removable chips under the search bar with the applied filters, link "Limpar filtros"; funnel button filled. |
| Tela 4 — Sheet de filtro | Groups "INTERVALO DE DATA" (Todo o período / Esta semana / Este mês, single choice), "CATEGORIA" (chips: trabalho, rotina, descanso, relações), "TIPO DE ENTRADA" (chips: manual, áudio, foto, chat); "Aplicar" and "Limpar". **Note:** the backend has no category filter (requirements, RF06); categories are the tags extension. |

### 2.5 Export (bottom sheet over Tela 4; 5 states)
| State | What it shows |
|---|---|
| Pendente | Spinner, "Preparando exportação...". |
| Processando | "Gerando resumo com IA...", progress bar. |
| Concluído | Green check, "Resumo pronto", buttons "Baixar PDF" (primary) and "Baixar dados brutos" (outline). |
| Erro | Red warning; text explaining that the AI narrative failed but the data remains available; only the button "Baixar dados brutos". |
| Período vazio | "Nenhum registro nesse período." and a suggestion to adjust the filter; no download button. |

All five have the link "Fechar" at the bottom. The mapping between these states and the backend job statuses is in `docs/input/backend/export-screen-states.md`.

### 2.6 Plans and settings
| State | What it shows |
|---|---|
| Tela 5 — Planos de Ação **[ext]** | Three horizontally scrolling columns — "A Fazer", "Em Andamento", "Concluído" — with counts and cards. |
| Tela 6 — Configurações — mais de 30 registros | "Sua evolução": 10-bar ochre chart + summary paragraph. |
| Tela 6 — Configurações — uma entrada | A single small bar and the text "Ainda é cedo pra ver um padrão — volte em alguns dias." |
| Tela 6 — Configurações — zero entradas | Light-gray chart icon in place of the chart and "Comece a registrar para ver sua evolução aqui"; no summary paragraph. |
| Tela 6 — Configurações — narrativa indisponível | Chart with data, but the AI summary paragraph failed — needs its own error message, not just missing text. |
| Tela 6 — Confirmar exclusão de conta | Centered dialog, red title "Apagar sua conta?", text on permanent, irreversible deletion; red button "Apagar tudo"; outline "Cancelar". |

Other elements of Configurações: avatar with editable name/e-mail (pencil becomes a check in edit mode — inline editing); persona cards "Como a IA responde" (Analítico, Empático, Socrático) **[ext]**; actions "Sair" and "Apagar conta" (red).

---

## 3. Visual system (tokens for `design_tokens.dart`)

The prototype has a **Design Tokens** panel, marked as the ground truth for `design_tokens.dart`. Its names and values are below.

### Colors
| Token | Hex | Use (as stated in the panel) |
|---|---|---|
| `colorPrimary` | `#1F3D34` | Buttons, app bar, wordmark |
| `colorPrimaryPressed` | `#16281F` | Pressed state |
| `colorOnPrimary` | `#F5F1E8` | Text on primary |
| `colorAccent` | `#C98A3E` | CTA, insight, saved bookmark |
| `colorOnAccent` | `#241C0D` | Text on accent |
| `colorSecondary` | `#7C8B6F` | Tags, chips, synchronizing |
| `colorSurfaceBg` | `#F2EFE7` | General background ("paper") |
| `colorSurfaceElevated` | `#FBF9F4` | Cards, bubbles, sheets |
| `colorBorder` | `#E1DACB` | Dividers, borders |
| `colorTextPrimary` | `#241F19` | Main text |
| `colorTextSecondary` | `#6B6255` | Secondary text |
| `colorError` | `#B3402A` | Errors, destructive action |
| `colorSuccess` | `#4C6B4F` | Synchronized, confirmations |
| `colorWarningSync` | `#C98A3E` | "Synchronizing" badge |
| `colorInfoOffline` | `#5C7A93` | Offline banner — single use |

Other colors that appear on specific screens but not in the panel: user chat bubble `#D9DFD3`; text on category chips `#3F4A38`.

### Typography
| Token | Font · weight · size/line-height | Use |
|---|---|---|
| `textDisplayLg` | Fraunces 600 · 32/38 | Splash wordmark |
| `textHeadlineMd` | Fraunces 600 · 24/30 | Section titles |
| `textTitleLg` | Karla 700 · 20/26 | App bar title |
| `textTitleSm` | Karla 700 · 16/22 | Subtitles |
| `textBodyLg` | Karla 400 · 16/24 | Bubbles, entries |
| `textBodyMd` | Karla 400 · 14/20 | Secondary text and descriptions |
| `textLabelMd` | Karla 500 · 13/18 | Button text, chips |
| `textMonoCaption` | IBM Plex Mono 500 · 12/16 · letter-spacing .2 | Technical metadata (timestamps, counters, status labels) |

### Spacing (4 dp grid)
`spacingXs` 4 · `spacingSm` 8 · `spacingMd` 16 · `spacingLg` 24 · `spacingXl` 32 · `spacing2xl` 48 (dp).

### Radii
`radiusSm` 8 dp (inputs, chips) · `radiusMd` 16 dp (cards, bubbles) · `radiusLg` 24 dp (sheets, modals) · `radiusFull` 999 dp (avatars, pills).

### Elevation
`elevation1` — `0 1px 3px rgba(36,31,25,.08)` (cards at rest) · `elevation2` — `0 4px 16px rgba(36,31,25,.14)` (sheets, modals).

### Icons
Phosphor library, Regular style, 24 dp: `list`, `plus`, `magnifying-glass`, `funnel`, `bookmark-simple`, `microphone`, `camera`, `gear`, `kanban`, `notebook`, `fingerprint`, `lightbulb` (and others used on specific screens: `check`, `warning-circle`, `wifi-slash`, `circle-notch`, `caret-left`, `download-simple`, `pencil-simple`, `x`, `stop`, `image`, `check-circle`, `chart-line-up`, `backspace`, `lock-key`, `paper-plane-tilt`, `chat-circle-text`).

### Spine (colored bar on the left of a card) — 3 contexts
1. Proactive insight in the chat — ochre.
2. Entry origin in "Meus Registros" — color by type: manual = dark green, audio = olive green, photo = gray, chat = ochre.
3. Kanban column in "Planos de Ação" — color by column **[ext]**.

### Micro-animations and transitions
- `scrimIn` (0.18 s ease-out): fade of the darkened background when any overlay opens.
- `sheetUp` (0.2 s ease-out): bottom sheets (insertion modal, filter, export) rise from the bottom of the screen.
- Continuous spinner (`spin`, 1 s linear infinite) in every loading state.
- Text streaming: the AI response is revealed progressively, with a blinking cursor at the end while it is "typing".
- PIN: after the 4th digit, a 350 ms pause before navigating.

---

## 4. Special states that need extra care

- **Expired session:** an overlay on the chat that keeps history and scroll position — the expired token must not discard the conversation state in memory before re-authentication. Re-authenticating goes back to the Biometria screen, not to a full form.
- **Offline:** blocks **sending new messages** (send icon disabled, explanatory banner), but **history stays visible and navigable**. The prototype does not show what happens to the insertion modal (text/audio/photo) when offline.
- **Asynchronous processing — audio transcription:** a loading state (spinner + frozen waveform) and two outcomes (success/error); the error always offers "Tentar novamente" and never loses the recorded audio.
- **Asynchronous processing — photo OCR:** same pattern as audio, with one extra exit on error: "Salvar só a foto", which saves the record even without extracted text.
- **Asynchronous processing — export:** two loading stages (preparing → generating the AI summary) before the result; on error, the raw data is always available for download — the failure is isolated to the AI narrative, never to the user's data.
- **Dashboard narrative unavailable:** the chart loads normally but the AI summary paragraph fails — distinct from "zero entries" (lack of data) and needs its own error message.

---

## 5. Implementation notes

1. **"29 frames" vs. "32 states":** the prototype has 32 distinct navigable states, but the number of frames (29) suggests that some state families should be one screen with internal state, not separate routes (e.g., a single `ExportSheet` with a status enum instead of 5 routes). Consider this when designing navigation.
2. **Account deletion without a success screen:** both "Sair" and "Apagar tudo" return to the Biometria screen; there is no "account deleted" or "you signed out" screen.
3. **Login vs. sign-up:** the same screen toggled by a text link; the prototype shows no extra sign-up fields (e.g., password confirmation, name). Whether sign-up needs extra fields is a product decision not covered visually.
4. **Insertion modal when offline:** not represented.
5. **Switching tabs in the insertion modal:** opening the modal always resets every tab to `idle`/empty, but switching tabs *during* a modal session is not cleared automatically — the expected behavior (e.g., whether an ongoing recording is discarded on tab switch) is not defined by the prototype.
6. **Per-entry sync indicator:** the states "sincronizado / sincronizando / erro de sync" exist visually on the cards, but no explicit "retry sync" action is shown for the error state. The semantics of the badge are in `docs/input/backend/sync-badge.md`.
7. **Text search combined with filters:** the filter sheet and the text search are on the same screen, but the prototype does not show them acting together.

---

## 6. Component library

| Component | Where it appears | Variations |
|---|---|---|
| Primary button | Auth, modals, sheets, confirmations | normal (`#1F3D34`) · pressed (`#16281F`, darker) · disabled (`#E1DACB` background, `#6B6255` text) |
| Secondary button (outline) | "Tentar novamente", "Cancelar", "Baixar dados brutos" | `#1F3D34` outline, no fill |
| Text button (ghost) | Mode-toggle links, "Fechar", "Limpar" | no background, `#1F3D34` or `#6B6255` depending on context |
| Text field | Login, Texto tab, name editing | empty · focused (1.5px `#1F3D34` border) · error (`#B3402A` border) |
| Chat bubble | Home/Chat | user (light green, straight bottom-right corner) · AI (ivory with shadow, straight bottom-left corner) · streaming (pulsing cursor at the end of the text) |
| Insight card | Home/Chat | ochre spine, mono label "INSIGHT", dismiss button |
| Bookmark button (RF10) | User messages in the chat | idle (outline) · saving (spinner) · saved (ochre check) · error (red warning) |
| Send-error banner | Home/Chat | "Não foi possível enviar — toque para tentar novamente"; background `rgba(179,64,42,.08)`, warning icon, red text |
| Offline banner | Home/Chat | blue-gray background `#5C7A93`, `ph-wifi-slash` icon, light text |
| Sync badge | Record cards (Tela 4) | synced (green dot) · synchronizing (ochre dot) · sync error (red dot) |
| Filter chip | Filter sheet, active filters | single choice (date) · multiple choice (category, type) · removable with "x" (active filters) |
| Record card | Tela 4 | spine colored by origin (manual = dark green, audio = olive green, photo = gray, chat = ochre) |
| Kanban card **[ext]** | Planos de Ação | spine by column (to do / in progress / done) |
| Initials avatar | Side menu, Configurações | dark green circle, 1–2 uppercase initials, two sizes (40px in the menu, 52px in Configurações) |
| AI persona card **[ext]** | Configurações | not selected (thin border) · selected (thick `#1F3D34` border + check icon) |
| Bar chart (dashboard) | Configurações | populated (10 bars) · one bar · empty (placeholder icon) |
| Export status card | Tela 4 (bottom sheet) | pending · processing · done · error · empty |
| Confirmation dialog | Sessão expirada, Confirmar exclusão | background scrim + centered card; neutral title (session) or red title (destructive deletion) |
| PIN keypad | Tela 0.1b/c | digits 0–9 + backspace; progress dots above |
| Tab bar | Insertion modal | 3 tabs (Texto/Áudio/Foto), active tab with filled background |
| Audio waveform | Insertion modal, Áudio tab | active/animated (recording) · frozen and faded (processing) |
| Skeleton | Any content loaded over the network | shown for calls longer than 300 ms (RNF01) |

# Export screen states (RF05)

`export_jobs` has two **independent** statuses — the status of the job itself (`status`) and the status of the AI-generated narrative (`narrativeStatus`) — because the raw export data can be ready before, after or independently of the narrative, and the UI must never block the download because of a narrative that failed. Both come from `GET /export/{jobId}/status`, together with `downloadAvailable`.

| What the screen shows | `status` | `narrativeStatus` | Download available |
|---|---|---|---|
| Preparing export | `pending` | `pending` | no |
| Generating AI summary | `processing` | `processing` | no |
| Data ready, summary still generating | `data_ready` | `processing` | yes (no PDF) |
| Done, with summary | `done` | `done` | yes (with PDF) |
| Done, summary failed or skipped | `done` | `failed` or `skipped` | yes (no PDF) |
| Export error | `error` | — | no |

This mapping covers only the export screen. The states of the other screens are in `docs/input/prototype/prototype-extract.md` and in `docs/input/requirements.md`.

/// spec-7-2 — the two formats `export-download-get`'s own `format` query
/// parameter accepts (`openapi.yaml`): `pdf` (the contract's own default)
/// or `raw`. Names mirror the contract's enum values exactly, so
/// `ExportDownloadFormat.pdf.name`/`.raw.name` are sent as the query value
/// verbatim — no second string-mapping table anywhere in this feature.
enum ExportDownloadFormat { pdf, raw }

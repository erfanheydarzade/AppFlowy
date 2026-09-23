# PDF developer guide

## Implemented foundation

- PDF import through the existing local picker, drag/drop, mobile action menu, and file block; network PDFs are downloaded with bounded streaming, validated, and then persisted through local/cloud asset storage.
- Local copies and cloud resumable uploads use AppFlowy's existing asset storage.
- Imports enforce a 200 MiB limit, PDF extension, allowed MIME types, `%PDF-` signature, parser acceptance, non-empty pages, and SHA-256 calculation.
- PDF file metadata synchronized through the file block includes MIME type, byte size, and SHA-256.
- Tapping a PDF opens a full-screen native Flutter workspace powered by PDFium through `pdfrx`.
- The viewer uses the SDK-compatible `pdfrx` 1.3.5/PDFium backend and provides progressive/lazy page loading, continuous scrolling, previous/next navigation, page count, zoom, fit width, fit page, keyboard navigation, touch navigation, text selection/copy, search highlighting, and previous/next match navigation.
- Cloud viewers send the existing bearer token and request range access. The renderer is available on desktop, macOS, Linux, Android, iOS, and web; web asset import remains limited by the repository's existing file-storage path.
- Original files remain immutable. Viewer state is not written to the document CRDT.
- Focused PDF validation tests run in Flutter CI. Flutter CI pins 3.29.0, the minimum supported version for the pinned PDF renderer; native builds and full Flutter/Rust analysis continue in existing workflows.

## Storage and synchronization

Do not add PDF bytes to document SQLite. `flowy-storage` owns bytes, resumable uploads, quotas, stable file IDs, and local/cloud persistence. The file block stores only the source reference and metadata in the collaborative document. A future editable workspace should store compact page, annotation, and stroke operations in the same document transaction system.

## Planned editable model

Page descriptors reference original/imported assets or image assets and carry stable IDs, order, rotation, dimensions, and page kind. Annotation operations use normalized page coordinates. Ink strokes contain sampled x/y, pressure, timestamp, velocity, width, color, opacity, and tool. Completed strokes and semantic operations are revisioned; viewer state, thumbnails, OCR progress, and render caches are not.

OCR must be an asynchronous server job with provider interfaces. The existing `flowy-ai` PDF text extraction is desktop-only and is not a general cross-platform OCR implementation. Scanned PDFs therefore have no OCR text until that subsystem is added.

## Extension points

- Annotation tools implement a typed operation and editor overlay; keep original PDF bytes unchanged.
- Ink tools normalize pointer samples into the platform-independent stroke model.
- OCR engines implement a provider returning asynchronous text/index artifacts.
- PDF processors are idempotent background jobs keyed by asset, page, and processor version.
- Page kinds implement descriptor serialization, rendering, import/export, and migration behavior.
- Exporters consume a workspace projection and write a new immutable output.

## Testing

Run focused tests with:

```text
cd frontend/appflowy_flutter
flutter test test/unit_test/editor/pdf_import_validator_test.dart
flutter analyze .
```

Run Rust and integration validation with the existing `cargo make rust_unit_test`, `cargo make dart_unit_test`, and Flutter integration workflows. New storage, page, annotation, stroke, sync, OCR, export, and migration behavior must add unit, integration, and backward-compatibility coverage before being enabled.

## Deployment

Self-hosted clients and AppFlowy Cloud remain compatible because no server or database migration is required by this foundation. Deploy clients with the pinned Flutter/Rust build matrix and the normal AppFlowy Cloud version. Future server APIs must be versioned and permission checked before client use.

## Known limitations

This milestone is the import/view/persist foundation, not the requested final editable PDF platform. It does not yet implement page mutation, thumbnails, original-page rotation, annotations, vector handwriting, OCR jobs, full-document search indexing, flattened export, or PDF-specific revision records. AppFlowy Cloud source is maintained in a separate repository, so server-side jobs and migrations cannot be truthfully implemented in this repository alone. No inert controls are exposed for those missing capabilities.

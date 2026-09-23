# Native PDF architecture

## Repository fit

AppFlowy is a Flutter client backed by Rust. Documents are collaborative editor trees, local and cloud files are handled by the Rust storage manager, and binary content does not belong in the document CRDT. PDF support therefore extends the existing `file` block instead of introducing an incompatible editor node or a second database.

The current implementation milestone provides validated, persistent PDF attachments and an embedded, lazy, cross-platform viewer backed by PDFium through `pdfrx`. Page operation, ink, annotations, OCR jobs, and flattened export are deliberately modeled as subsequent CRDT-backed phases rather than represented by inert controls.

## 1. PDF document model

A PDF is represented as a native file block containing its stable storage reference, upload type, original name, uploader, and timestamp. A future editable workspace adds a `pdf_workspace` child block and stores only compact JSON operations and stable asset IDs in its attributes. Viewer state such as page, zoom, selection, and scroll position remains local UI state.

## 2. PDF asset storage

Original bytes use the existing storage abstraction. Local mode copies the immutable source into application-managed storage. Cloud mode uses the existing multipart, resumable upload pipeline. The storage layer supplies stable file IDs, size, MIME inference, quotas, and authorization. The future workspace model references assets by these IDs instead of embedding bytes in SQLite or the CRDT.

Import checks extension, MIME when available, `%PDF-` signature, size bounds, and parser acceptance. SHA-256 metadata is calculated for verification and future deduplication. The source is never rewritten.

## 3. PDF rendering

`PdfViewer` is isolated behind the PDF workspace presentation layer and delegates parsing/rendering to PDFium through `pdfrx`. It supports local files, authenticated HTTP sources, progressive loading, text selection, search, zoom, scrolling, and platform-native rendering. It never executes JavaScript, launch actions, or embedded files.

## 4. Page model

Future page descriptors are CRDT-friendly ordered items: stable page ID, source asset/page number, inserted image reference, page kind, rotation, crop, and dimensions. Kinds are original, imported PDF, blank, lined, grid, dotted, and image. Operations are insert, delete, move, duplicate, rotate, and replace. Original pages remain references and are not flattened on every edit.

## 5. Annotation model

Annotations are independent vector/rich-text operations keyed by stable IDs. Base coordinates are normalized PDF page coordinates so rendering is resolution independent. Types include highlight, underline, strikeout, note, ink, line, arrow, rectangle, ellipse, and polygon. Each operation stores author, timestamps, and a compact CRDT-visible payload.

## 6. Handwriting model

Ink is a platform-independent sequence of sampled points with x/y, pressure, timestamp, velocity, width, color, opacity, and tool. Mouse, touch, and stylus input are normalized by adapters. Undo/redo operates on completed strokes, not per-point document snapshots. Rendered bitmaps are caches only.

## 7. Synchronization

Only durable document state uses AppFlowy's existing transaction and CRDT pipeline: file metadata, workspace metadata, ordered page operations, annotation operations, and completed strokes. Viewer state and server job progress are not synchronized. Stable operation/page/annotation/stroke IDs make concurrent inserts and deletes deterministic.

## 8. Version history

PDF workspace operations enter the existing document revision stream. Import, page, annotation, stroke, and OCR metadata operations are compact deltas. Server OCR completion and large generated index data reference the initiating operation and are idempotent. Thumbnails and render caches are excluded.

## 9. Server-side processing

CPU-heavy work is asynchronous: text extraction, thumbnail generation, OCR, and flattened export. The production server API is versioned and permission checked. Jobs carry workspace/document/asset IDs, actor, status, attempts, progress, and immutable output references. Client rendering remains the default. The AppFlowy Cloud server currently lives in a separate repository and is not duplicated here.

## 10. Export

Exports are non-destructive projections. Original export returns a verified byte-for-byte asset. Annotated and flattened export compose original/imported pages, annotations, ink, and notes into a new immutable PDF without changing workspace state. An AppFlowy project export serializes the compact workspace model and asset references.

## 11. CI/CD

Existing Flutter and Rust workflows provide cross-platform analysis, builds, unit/integration tests, and cloud integration. PDF CI adds focused import validation tests; native build verification remains part of the existing platform matrix. Changes must pass formatting, linting, static analysis, tests, and platform builds before release.

## 12. Automatic releases

Existing desktop builds are tag-driven. Tagged artifacts are immutable and versioned. The release workflow now validates SemVer, supports prerelease tags, generates SHA-256 manifests, and publishes Docker artifacts only after release creation. Stable publication remains explicit. Nightly publishing is not enabled by this milestone; it requires a separate opt-in workflow so ordinary commits cannot become stable releases.

## Security and performance

Uploads are untrusted and bounded before parsing. Signature and MIME checks are defense in depth, not substitutes for parser validation. Rendering uses file/URI sources and progressive loading rather than eagerly reading a 500-page document. Cancellation disposes renderer resources. Production cloud viewing must use authenticated range-capable sources rather than unauthenticated launch URLs.

## Extension points

New tools implement small typed operations against the same store; new OCR engines implement a provider interface and return asynchronous text/index artifacts; new processors are queued idempotent jobs; new page kinds implement descriptor and renderer factories; new exporters consume the workspace projection without mutating it.

# Eagle PDFium 7543

This directory contains the reproducible patch and build entrypoint for the
custom PDFium dynamic libraries consumed by `scanlib-rs`.

The build is pinned to:

- `bblanchon/pdfium-binaries@a96196ffc32978819193fb82873bfb3afc089ef9`
- `pdfium@99c42f5a6508f738383b5f3ab641959231360353` (`chromium/7543`)
- `depot_tools@3d401c263f5b4ee534eacf967ac7234f7c4ee029`

`eagle_catalog_custom_stream.patch` adds a bounded
`FPDFCatalog_GetCustomStream()` API. It accepts unfiltered data or a single
`FlateDecode` filter without `DecodeParms`; other filter chains are rejected.
Both compressed input and decoded output are bounded by the caller's
`max_size`, with a hard upper limit of 1 MiB.

## Build and release

Native artifacts are built from the private `scanlib-client` repository so
untrusted code from this public repository never executes on shared
self-hosted runners. Its `Build Eagle PDFium` workflow uses these runner
classes:

- Linux: `self-hosted`, `Linux`, `ubuntu22.04`
- macOS: `self-hosted`, `macOS`, `ARM64`
- Windows: `self-hosted`, `Windows`, `X64`

The private workflow checks out an explicitly pinned `pdfium-render` commit,
builds and tests all configured targets, then creates a `pdfium-eagle-*` tag
and publishes the generated `.tgz` archives and SHA-256 files to this
repository's GitHub Release.

The Linux x64 runner also cross-compiles the Linux arm64 artifact, matching the
server release matrix without introducing a second Linux runner class.

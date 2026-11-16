# Changelog

## v1.0.1 — 2026-11-16

- Fixed numeric track ordering so track 2 is processed before track 10.
- Added two-phase track renaming to prevent files from overwriting one another.
- Added a Dreamcast boot-header check for `SEGA SEGAKATANA` on ISO data tracks.
- Added an optional `-StrictHeader` switch for users who want a missing header to fail the conversion.
- Added a warning when CDIRip extracts more files than the detected track count.
- Kept the concise English log format and automatic removal of incomplete CHD files.

## v1.0.0 — 2026-11-16

- First public standalone release.

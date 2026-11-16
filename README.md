**Current version: v1.0.1**

# Dreamcast-CDI-to-CHD

A simple Windows package for converting Dreamcast CDI images to CHD files for Flycast.

## One-click use

1. Extract this folder directly inside the folder that contains your `.cdi` files.
2. Double-click `Start-Dreamcast-CDI-to-CHD.cmd`.
3. The converter scans the parent folder, creates a `CHD` subfolder, and writes the converted files there.
4. Read `Dreamcast-CDI-to-CHD\journal\cdi2chd_log.txt` if anything fails.

For example:

```text
Roms\DC (Dreamcast)\
  Game 1.cdi
  Game 2.cdi
  Dreamcast-CDI-to-CHD\
    Start-Dreamcast-CDI-to-CHD.cmd
    cdi2chd.ps1
    tools\
      cdirip.exe
      chdman.exe
  CHD\
    Game 1.chd
```

A `journal` folder is created inside this package. The log is written to `journal\cdi2chd_log.txt`.

The original CDI files are never modified or deleted. A partial CHD is deleted when a conversion fails. The text log is kept in `Dreamcast-CDI-to-CHD\journal\cdi2chd_log.txt`. Normal chdman banners and percentage updates are intentionally omitted; only useful summaries and error diagnostics are recorded.

## Requirements

Windows PowerShell 5.1 or later. No installation is required.

## Legal notice

Use this tool only with images you are legally allowed to possess and convert. This project includes third-party tools; see `licenses\THIRD-PARTY-NOTICES.md`. It is not affiliated with Sega, Flycast, MAME, or the CDIRip authors.

## Support

GitHub Sponsors: https://github.com/sponsors/GrasQuiGame


For advanced diagnostics, `-StrictHeader` makes the conversion fail when no ISO data track starts with the Dreamcast boot header `SEGA SEGAKATANA`.

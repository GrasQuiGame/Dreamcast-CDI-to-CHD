# Troubleshooting

- Confirm that `tools\\cdirip.exe` and `tools\\chdman.exe` exist.
- Test with one CDI file first by adding `-Limit 1` when running the PowerShell script manually.
- Read `journal\cdi2chd_log.txt`.
- The log intentionally omits chdman percentage updates and normal tool banners. It keeps only conversion summaries and diagnostic lines when an error occurs.
- Keep the original CDI files until the CHD has been tested in Flycast.
- If a conversion fails, the incomplete CHD is deleted automatically.

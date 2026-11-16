# Usage

The normal workflow is a double-click on `Start-Dreamcast-CDI-to-CHD.cmd`. No command-line arguments are required.

The script uses the folder containing the package's parent as the CDI source folder and creates a sibling folder named `CHD`. Existing CHD files are skipped. Failed output files are removed, while the text log remains.

For advanced use, the script still accepts `-Src`, `-Out`, `-Tools`, `-Limit`, and `-DeleteTempOnError`.

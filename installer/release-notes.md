## Statera @VERSION@ (preview)

Statera is an open-source statistics package that aims to behave exactly like IBM SPSS Statistics. It uses the same syntax, reads and writes `.sav` files, and produces the same numbers. This is an early **preview**.

### What works
- Opening and saving `.sav` and `.zsav` files, plus a fast data grid (hundreds of thousands of cases).
- A syntax editor that runs `GET`, `SAVE`, `COMPUTE`, `SELECT IF`, `FILTER`, `WEIGHT`, `SORT CASES`, `SPLIT FILE` and `TEMPORARY`.
- Procedures: `FREQUENCIES`, `DESCRIPTIVES`, `CROSSTABS`, `MEANS`, `T-TEST`, `ONEWAY`, `CORRELATIONS` and linear `REGRESSION`. Their output matches SPSS 25 cell for cell in our golden tests.
- Output viewer with pivot tables. Copy any table, or export everything to HTML, Excel (XLSX) or CSV.
- Light, dark and follow-system themes.

### Install
| System | File | Notes |
|---|---|---|
| Windows 10/11 (x64) | `Statera-@VERSION@-windows-x64-setup.exe` | Unsigned, so SmartScreen may warn: choose *More info → Run anyway*. A portable `.zip` is also attached. |
| macOS 11+ (Apple Silicon) | `Statera-@VERSION@-macos-arm64.dmg` | Not notarized. Drag Statera to Applications, then right-click it and choose *Open* the first time. |
| Linux (x86-64) | `Statera-@VERSION@-linux-x86_64.AppImage` or `statera_*_amd64.deb` | AppImage: `chmod +x` and run. Debian/Ubuntu: `sudo apt install ./statera_*.deb`. |

Statera is an independent project. It is not affiliated with or endorsed by IBM. "SPSS" is a trademark of IBM Corp.

### SHA-256 checksums

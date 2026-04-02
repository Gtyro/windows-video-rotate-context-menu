# Video Rotate Context Menu for Windows

This project adds a per-user Windows Explorer context menu for common video
files and uses `ffmpeg` to write display rotation metadata without re-encoding
the streams.

It is designed for Windows 10 and Windows 11, with explicit compatibility work
for `Windows PowerShell 5.1` and Win11 classic context-menu behavior.
After installation, the project folder can be deleted because the runtime
scripts are deployed to a stable per-user location.

## Quick Start

Install:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\install-video-rotate-context-menu.ps1
```

Install with a fixed `ffmpeg.exe` path:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\install-video-rotate-context-menu.ps1 `
  -FfmpegPath "C:\path\to\ffmpeg.exe"
```

Uninstall:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\uninstall-video-rotate-context-menu.ps1
```

## Repository Layout

- `install-video-rotate-context-menu.ps1`
  Registers Explorer context-menu entries under `HKCU`.
- `invoke-video-display-rotation.ps1`
  Executes `ffmpeg` and writes rotation metadata to a new output file.
- `uninstall-video-rotate-context-menu.ps1`
  Removes installed registry entries.
- `docs/IMPLEMENTATION.md`
  Architecture, execution model, compatibility decisions, and design details.
- `docs/TROUBLESHOOTING.md`
  Validation commands, failure symptoms, diagnostics, and maintenance checks.

## Runtime Note

During installation, the runtime scripts are copied to:

```text
%LOCALAPPDATA%\VideoRotateContextMenu
```

The installed context-menu command then points to that deployed helper script by
absolute path. It does not resolve the helper from the current working
directory at click time.

This means the project folder is not required after installation. If you want to
change the deployment location, re-run the install script with `-DeploymentRoot`.

## Additional Documentation

- [Implementation](docs/IMPLEMENTATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

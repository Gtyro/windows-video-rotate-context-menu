# Video Rotate Context Menu

This package adds a Windows Explorer context menu for common video files:

- Counterclockwise 90 degrees
- Rotate 180 degrees
- Clockwise 90 degrees
- Clear rotation metadata (0 degrees)

It uses `ffmpeg` to change display rotation metadata only. It does not re-encode the video.

## Files

- `install-video-rotate-context-menu.ps1`
- `invoke-video-display-rotation.ps1`
- `uninstall-video-rotate-context-menu.ps1`

Keep these files in the same folder after you copy them to another computer.

## Install

If `ffmpeg.exe` is already available in `PATH` or already lives in a common install location, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-video-rotate-context-menu.ps1
```

The installer will try to find `ffmpeg.exe` immediately and pin the resolved path into the menu command when it can.

If `ffmpeg.exe` is not in `PATH`, pin its full path during install:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-video-rotate-context-menu.ps1 -FfmpegPath "D:\ffmpeg\bin\ffmpeg.exe"
```

The menu is installed per-user under `HKCU`, so administrator rights are not required.

If install cannot find `ffmpeg.exe`, it still installs the menu and prints a warning. In that case the helper script will keep trying `PATH` and the common locations listed below each time you click the menu, so installing `ffmpeg` later can still make the existing menu work.

## Use

1. Right-click a supported video file such as `.mp4`, `.mkv`, `.mov`, `.avi`, `.wmv`, `.webm`.
2. Open the installed rotation menu.
3. Choose the desired rotation.

On Windows 11, the menu may appear under `Show more options`.

## Output behavior

- Default output is a new file in the same folder.
- Example: `input.mp4` becomes `input.display-rot90.mp4`.
- Rotation values follow ffmpeg display metadata behavior:
  - `90` = counterclockwise 90 degrees
  - `180` = rotate 180 degrees
  - `270` = clockwise 90 degrees
  - `0` = clear rotation metadata

## How ffmpeg is found

If install was run without `-FfmpegPath`, the installer first tries to find `ffmpeg.exe` and pin the exact path. If nothing is found during install, the helper script tries these in order when you click the menu:

1. `ffmpeg.exe` from `PATH`
2. `%ProgramFiles%\ffmpeg\bin\ffmpeg.exe`
3. `%ProgramFiles%\FFmpeg\bin\ffmpeg.exe`
4. `%USERPROFILE%\scoop\apps\ffmpeg\current\bin\ffmpeg.exe`
5. `%SystemDrive%\ffmpeg\bin\ffmpeg.exe`
6. `%ChocolateyInstall%\bin\ffmpeg.exe` if Chocolatey exists

If install was run with `-FfmpegPath`, that exact path is stored into the menu command and used directly.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-video-rotate-context-menu.ps1
```

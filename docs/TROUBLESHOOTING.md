# Troubleshooting Guide

## 1. Validation Commands

Check that `ffmpeg.exe` is available:

```powershell
Get-Command ffmpeg.exe
```

Check the installed `.mp4` menu root:

```powershell
Get-ItemProperty `
  -LiteralPath 'HKCU:\Software\Classes\SystemFileAssociations\.mp4\shell\RotateVideoDisplayMetadata'
```

Check which helper-script path the installed menu actually calls:

```powershell
(Get-ItemProperty `
  -LiteralPath 'HKCU:\Software\Classes\SystemFileAssociations\.mp4\shell\RotateVideoDisplayMetadata\shell\Rotate90CCW\command'
).'(default)'
```

Verify output rotation metadata:

```powershell
ffprobe -hide_banner -loglevel error `
  -show_entries stream_tags=rotate:stream_side_data=rotation `
  -select_streams v:0 `
  -of default=noprint_wrappers=1 `
  "<output-file>"
```

Expected example output:

```text
rotation=90
```

## 2. Symptom: Menu Does Not Appear

Checks:

- Confirm the file extension is supported.
- On Windows 11, open `Show more options`.
- Verify the `.mp4` or target-extension registry key exists under
  `HKCU\Software\Classes\SystemFileAssociations`.

Actions:

- Re-run `install-video-rotate-context-menu.ps1`.
- Restart Explorer if the menu does not refresh immediately.

## 3. Symptom: The Wrong Helper Script Runs

Cause:

- The installed command stores an absolute helper-script path from installation
  time.

Checks:

- Read the installed command from the registry and inspect the `-File` value.

Actions:

- Check whether the installed command points to the deployed location under
  `%LOCALAPPDATA%\VideoRotateContextMenu` or to an older stale path.
- Re-run the install script to refresh the deployed files and registry command.

## 4. Symptom: Chinese Menu Text Is Garbled

Cause:

- Older versions of the install script depended on source-file encoding and were
  vulnerable to UTF-8 parsing issues in `Windows PowerShell 5.1`.

Actions:

- Use the current installer version.
- Reinstall the menu so the registry receives corrected labels.

## 5. Symptom: Only One File Extension Was Installed

Cause:

- Older logic used plain hashtables and could collapse the target set during
  unique sorting.

Actions:

- Use the current installer version.
- Reinstall the menu.

## 6. Symptom: `ffmpeg.exe` Was Not Found

Checks:

- Run `Get-Command ffmpeg.exe`.
- Confirm the executable exists in a common install location.

Actions:

- Add `ffmpeg.exe` to `PATH`.
- Reinstall with `-FfmpegPath`.

## 7. Symptom: Output File Was Not Created

Checks:

- Confirm the input file exists and is readable.
- Confirm the destination directory is writable.
- Inspect the `ffmpeg` error output and exit code.

Actions:

- Retry with a manual `-OutputPath`.
- Ensure no other process is locking the source or destination file.

## 8. Symptom: Menu Click Does Nothing or Fails Immediately

Checks:

- Confirm the registry command still points to an existing helper-script path.
- Confirm `powershell.exe` and `ffmpeg.exe` are accessible.
- Run the helper script manually with the same arguments to reproduce the error.

Manual reproduction template:

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "$env:LOCALAPPDATA\VideoRotateContextMenu\invoke-video-display-rotation.ps1" `
  -InputPath "<video-file>" `
  -Rotation 90
```

## 9. Symptom: Registry Access Is Denied

Checks:

- Confirm the script is running under the intended user account.
- Confirm the session can write to `HKCU\Software\Classes`.

Actions:

- Run PowerShell in the same user context as Explorer.
- Check endpoint security or enterprise policy restrictions.

## 10. Maintenance Checklist

After any future change to installation or runtime logic, verify at least the
following:

- `.mp4` menu root exists
- submenu commands exist
- registry command points to the intended helper-script path
- deployed runtime files exist under `%LOCALAPPDATA%\VideoRotateContextMenu`
- output file is created successfully
- `ffprobe` reports the expected rotation metadata
- Win11 behavior is acceptable under `Show more options`

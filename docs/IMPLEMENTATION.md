# Implementation Guide

## 1. Purpose

This document explains how the video rotation context-menu solution is designed,
how it executes at runtime, and which compatibility decisions were made for
Windows 10, Windows 11, and `Windows PowerShell 5.1`.

## 2. Components

- `install-video-rotate-context-menu.ps1`
  Registers the Explorer submenu and child commands.
- `invoke-video-display-rotation.ps1`
  Resolves paths and calls `ffmpeg`.
- `uninstall-video-rotate-context-menu.ps1`
  Removes the installed registry keys.

## 3. High-Level Flow

1. The install script resolves the helper-script path and optional `ffmpeg.exe`
   path.
2. It copies the runtime scripts to a stable deployment directory under the
   current user's profile.
3. It creates per-user registry entries for each supported video extension.
4. Each submenu item stores a complete command line that launches
   `powershell.exe` with the helper script and the selected rotation value.
5. When the user clicks a menu item, Explorer executes that stored command.
6. The helper script writes rotation metadata to a new output file by using
   stream copy mode in `ffmpeg`.

## 4. Registry Model

The menu is installed under:

```text
HKCU\Software\Classes\SystemFileAssociations\<extension>\shell\RotateVideoDisplayMetadata
```

Subcommands are created below:

```text
...\shell\Rotate90CCW
...\shell\Rotate180
...\shell\Rotate90CW
...\shell\Rotate0
```

This keeps the installation scoped to the current user and avoids requiring a
machine-wide installation.

The installer also writes lightweight installation state under:

```text
HKCU\Software\VideoRotateContextMenu
```

That state is used to track the deployment directory and uninstall path.

## 5. Deployment Model

By default, the installer copies runtime files to:

```text
%LOCALAPPDATA%\VideoRotateContextMenu
```

Deployed files:

- `invoke-video-display-rotation.ps1`
- `uninstall-video-rotate-context-menu.ps1`

This deployment model allows the source project folder to be deleted after
installation while keeping the Explorer menu functional.

## 6. Execution-Path Behavior

### 6.1 Which `invoke-video-display-rotation.ps1` Is Actually Executed

The helper script is deployed and resolved during installation, not during
right-click execution.

The install script does this:

```powershell
$resolvedDeploymentRoot = Resolve-DeploymentRoot -Candidate $DeploymentRoot
Copy-DeploymentFiles -SourceRoot $sourceScriptRoot -DestinationRoot $resolvedDeploymentRoot
$invokeScriptPath = Join-Path $resolvedDeploymentRoot "invoke-video-display-rotation.ps1"
$resolvedInvokeScriptPath = (Resolve-Path -LiteralPath $invokeScriptPath).Path
```

That resolved absolute path is then written into every registry command:

```powershell
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File "<absolute-path>\invoke-video-display-rotation.ps1" `
  -InputPath "%1" `
  -Rotation <value>
```

Operational consequence:

- The installed menu executes the deployed helper script, not the copy in the
  source project directory.
- The source project directory can be removed after installation.
- If the deployment location is changed intentionally, the install script must
  be run again so the registry points to the new deployed path.
- The command is not resolved from Explorer's working directory or the current
  shell session.

## 7. Command Construction

Each menu command is built with:

- `powershell.exe`
- `-NoLogo`
- `-NoProfile`
- `-ExecutionPolicy Bypass`
- `-File <absolute helper path>`
- `-InputPath "%1"`
- `-Rotation <0|90|180|270>`

If installation is performed with `-FfmpegPath`, that absolute path is also
embedded into the command.

## 8. Rotation Strategy

The helper script uses metadata rotation instead of pixel rotation.

Key `ffmpeg` arguments:

```powershell
-display_rotation:v:0 <rotation>
-map 0
-c copy
```

Benefits:

- No re-encoding
- Faster execution
- Lower risk of quality loss

Limitation:

- Some players ignore rotation metadata, so container metadata may not be
  honored everywhere.

## 9. Output-File Strategy

Unless `-OutputPath` is supplied, the helper script creates a sibling output
file in this pattern:

```text
<original-name>.display-rot<rotation>.<extension>
```

This avoids in-place modification of the original source file.

## 10. `ffmpeg.exe` Resolution

Resolution order:

1. Explicit `-FfmpegPath`
2. `PATH`
3. Common install paths under `Program Files`, `Scoop`, root drive, and
   `Chocolatey`

If no usable `ffmpeg.exe` is found, the helper script throws an error and does
not create an output file.

## 11. Compatibility Decisions

### 11.1 Windows PowerShell 5.1 Encoding

Default Chinese labels are not stored as raw UTF-8 literals. They are generated
from Unicode code points at runtime.

Reason:

- `Windows PowerShell 5.1` can misread UTF-8 without BOM as the local ANSI code
  page, which causes menu text mojibake.

### 11.2 PowerShell Object Type for Registry Targets

Registry target items are stored as `PSCustomObject`, not plain hashtables.

Reason:

- Earlier hashtable-based logic combined with `Sort-Object Path -Unique` could
  collapse the target set incorrectly and leave only part of the supported file
  extensions installed.

### 11.3 Windows 11 Shell Behavior

This implementation uses the classic shell verb model.
On Windows 11, the menu normally appears under:

- `Show more options`
- `Shift+F10`

This is expected and not a defect.

### 11.4 Source Folder Retention

The source project folder is not part of the runtime requirement after
installation because the helper and uninstall scripts are copied into the
deployment directory.

This specifically avoids the earlier operational requirement to keep the project
folder in place forever.

## 12. Supported Extensions

- `.3g2`
- `.3gp`
- `.asf`
- `.avi`
- `.flv`
- `.m2ts`
- `.m4v`
- `.mkv`
- `.mov`
- `.mp4`
- `.mpeg`
- `.mpg`
- `.mts`
- `.ts`
- `.vob`
- `.webm`
- `.wmv`

## 13. Current Stabilization Summary

The current version addresses two confirmed compatibility defects:

- Chinese menu labels no longer depend on source-file encoding.
- All supported extensions are now registered correctly instead of only a
  partial subset.
- The installed menu now points to a deployed helper location, so the source
  project folder can be deleted after installation.

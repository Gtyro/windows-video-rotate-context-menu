param(
  [string]$FfmpegPath = "",
  [string]$MenuText = "",
  [switch]$IncludeReset = $true
)

$ErrorActionPreference = "Stop"

function New-Text {
  param(
    [int[]]$CodePoints
  )

  return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Find-FfmpegPath {
  try {
    return (Get-Command ffmpeg.exe -ErrorAction Stop).Source
  } catch {
  }

  $commonCandidates = @(
    (Join-Path $env:ProgramFiles "ffmpeg\bin\ffmpeg.exe"),
    (Join-Path $env:ProgramFiles "FFmpeg\bin\ffmpeg.exe"),
    (Join-Path $env:USERPROFILE "scoop\apps\ffmpeg\current\bin\ffmpeg.exe"),
    (Join-Path $env:SystemDrive "ffmpeg\bin\ffmpeg.exe")
  )

  if ($env:ChocolateyInstall) {
    $commonCandidates += (Join-Path $env:ChocolateyInstall "bin\ffmpeg.exe")
  }

  foreach ($item in $commonCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($item) -and (Test-Path -LiteralPath $item)) {
      return (Resolve-Path -LiteralPath $item).Path
    }
  }

  return ""
}

function Get-InstallRoot {
  $basePath = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($basePath)) {
    $basePath = [Environment]::GetFolderPath("LocalApplicationData")
  }

  if ([string]::IsNullOrWhiteSpace($basePath)) {
    throw "LocalApplicationData could not be resolved."
  }

  return (Join-Path $basePath "VideoRotateContextMenu")
}

function Copy-InstalledFile {
  param(
    [Parameter(Mandatory)]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [string]$DestinationPath
  )

  $resolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
  $destinationParent = Split-Path -Parent $DestinationPath
  if (-not [string]::IsNullOrWhiteSpace($destinationParent) -and -not (Test-Path -LiteralPath $destinationParent)) {
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
  }

  if ((Test-Path -LiteralPath $DestinationPath) -and ((Resolve-Path -LiteralPath $DestinationPath).Path -eq $resolvedSourcePath)) {
    return $resolvedSourcePath
  }

  Copy-Item -LiteralPath $resolvedSourcePath -Destination $DestinationPath -Force
  return (Resolve-Path -LiteralPath $DestinationPath).Path
}

if ([string]::IsNullOrWhiteSpace($MenuText)) {
  $MenuText = New-Text -CodePoints @(0x65CB, 0x8F6C, 0x89C6, 0x9891)
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$invokeScriptPath = Join-Path $scriptRoot "invoke-video-display-rotation.ps1"
$uninstallScriptPath = Join-Path $scriptRoot "uninstall-video-rotate-context-menu.ps1"

if (-not (Test-Path -LiteralPath $invokeScriptPath)) {
  throw "Missing helper script: $invokeScriptPath"
}

if (-not (Test-Path -LiteralPath $uninstallScriptPath)) {
  throw "Missing uninstall script: $uninstallScriptPath"
}

$installRoot = Get-InstallRoot
$resolvedInvokeScriptPath = Copy-InstalledFile -SourcePath $invokeScriptPath -DestinationPath (Join-Path $installRoot "invoke-video-display-rotation.ps1")
$resolvedUninstallScriptPath = Copy-InstalledFile -SourcePath $uninstallScriptPath -DestinationPath (Join-Path $installRoot "uninstall-video-rotate-context-menu.ps1")
$pinnedFfmpegPath = ""
$detectedFfmpegPath = ""
$ffmpegPathSource = "runtime"

if (-not [string]::IsNullOrWhiteSpace($FfmpegPath)) {
  if (-not (Test-Path -LiteralPath $FfmpegPath)) {
    throw "Specified ffmpeg was not found: $FfmpegPath"
  }

  $pinnedFfmpegPath = (Resolve-Path -LiteralPath $FfmpegPath).Path
  $detectedFfmpegPath = $pinnedFfmpegPath
  $ffmpegPathSource = "explicit"
} else {
  $autoDetectedFfmpegPath = Find-FfmpegPath
  if (-not [string]::IsNullOrWhiteSpace($autoDetectedFfmpegPath)) {
    $detectedFfmpegPath = $autoDetectedFfmpegPath
    $ffmpegPathSource = "auto-detected"
  }
}

$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Get-VideoExtensions {
  return @(
    ".3g2", ".3gp", ".asf", ".avi", ".flv", ".m2ts", ".m4v", ".mkv",
    ".mov", ".mp4", ".mpeg", ".mpg", ".mts", ".ts", ".vob", ".webm", ".wmv"
  )
}

function Get-ExtensionProgId {
  param(
    [Parameter(Mandatory)]
    [string]$Extension
  )

  $userChoiceKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
    "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
  )
  if ($userChoiceKey) {
    try {
      $userChoiceProgId = $userChoiceKey.GetValue("ProgId", "")
      if (-not [string]::IsNullOrWhiteSpace($userChoiceProgId)) {
        return $userChoiceProgId
      }
    } finally {
      $userChoiceKey.Close()
    }
  }

  $extensionKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($Extension)
  if ($extensionKey) {
    try {
      $defaultProgId = $extensionKey.GetValue("", "")
      if (-not [string]::IsNullOrWhiteSpace($defaultProgId)) {
        return $defaultProgId
      }

      $openWithProgIdsKey = $extensionKey.OpenSubKey("OpenWithProgids")
      if ($openWithProgIdsKey) {
        try {
          foreach ($name in $openWithProgIdsKey.GetValueNames()) {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
              return $name
            }
          }
        } finally {
          $openWithProgIdsKey.Close()
        }
      }
    } finally {
      $extensionKey.Close()
    }
  }

  return ""
}

function New-VerbCommand {
  param(
    [int]$Rotation
  )

  $parts = @(
    '"' + $powerShellExe + '"',
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", '"' + $resolvedInvokeScriptPath + '"',
    "-InputPath", '"%1"',
    "-Rotation", $Rotation.ToString()
  )

  if (-not [string]::IsNullOrWhiteSpace($pinnedFfmpegPath)) {
    $parts += @("-FfmpegPath", '"' + $pinnedFfmpegPath + '"')
  }

  return ($parts -join " ")
}

function Set-RegistryStringValue {
  param(
    [Microsoft.Win32.RegistryKey]$Key,
    [string]$Name,
    [string]$Value
  )

  $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String)
}

function Set-RegistryDWordValue {
  param(
    [Microsoft.Win32.RegistryKey]$Key,
    [string]$Name,
    [int]$Value
  )

  $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::DWord)
}

function Refresh-ShellAssociations {
  if (-not ("Win32.NativeMethods" -as [type])) {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
"@
  }

  [Win32.NativeMethods]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Get-HkcrRelativePath {
  param(
    [Parameter(Mandatory)]
    [string]$SubKeyPath
  )

  $prefix = "Software\Classes\"
  if ($SubKeyPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $SubKeyPath.Substring($prefix.Length)
  }

  return $SubKeyPath
}

function Install-MenuAtSubKey {
  param(
    [string]$SubKeyPath,
    [hashtable[]]$Entries
  )

  $menuKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKeyPath)
  if (-not $menuKey) {
    throw "Failed to create registry key: HKCU\$SubKeyPath"
  }

  try {
    $menuKey.DeleteValue("", $false)
    Set-RegistryStringValue -Key $menuKey -Name "MUIVerb" -Value $MenuText
    Set-RegistryStringValue -Key $menuKey -Name "Icon" -Value "%SystemRoot%\System32\shell32.dll,133"
    Set-RegistryStringValue -Key $menuKey -Name "ExtendedSubCommandsKey" -Value (Get-HkcrRelativePath -SubKeyPath $SubKeyPath)
    Set-RegistryStringValue -Key $menuKey -Name "MultiSelectModel" -Value "Player"
    $menuKey.DeleteValue("SubCommands", $false)
    $menuKey.DeleteValue("CommandFlags", $false)
  } finally {
    $menuKey.Close()
  }

  foreach ($entry in $Entries) {
    $verbKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$SubKeyPath\shell\$($entry.Name)")
    if (-not $verbKey) {
      throw "Failed to create registry key: HKCU\$SubKeyPath\shell\$($entry.Name)"
    }

    try {
      $verbKey.DeleteValue("", $false)
      Set-RegistryStringValue -Key $verbKey -Name "MUIVerb" -Value $entry.Label
      Set-RegistryStringValue -Key $verbKey -Name "Icon" -Value "%SystemRoot%\System32\shell32.dll,133"

      if ($entry.ContainsKey("CommandFlags")) {
        Set-RegistryDWordValue -Key $verbKey -Name "CommandFlags" -Value $entry.CommandFlags
      } else {
        $verbKey.DeleteValue("CommandFlags", $false)
      }
    } finally {
      $verbKey.Close()
    }

    $commandKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$SubKeyPath\shell\$($entry.Name)\command")
    if (-not $commandKey) {
      throw "Failed to create registry key: HKCU\$SubKeyPath\shell\$($entry.Name)\command"
    }

    try {
      Set-RegistryStringValue -Key $commandKey -Name "" -Value (New-VerbCommand -Rotation $entry.Rotation)
    } finally {
      $commandKey.Close()
    }
  }
}

$menuEntries = @(
  @{
    Name = "Rotate90CCW"
    Label = (New-Text -CodePoints @(0x9006, 0x65F6, 0x9488)) + " 90" + [char]0x00B0
    Rotation = 90
  },
  @{
    Name = "Rotate180"
    Label = (New-Text -CodePoints @(0x65CB, 0x8F6C)) + " 180" + [char]0x00B0
    Rotation = 180
  },
  @{
    Name = "Rotate90CW"
    Label = (New-Text -CodePoints @(0x987A, 0x65F6, 0x9488)) + " 90" + [char]0x00B0
    Rotation = 270
  }
)

if ($IncludeReset) {
  $menuEntries += @{
    Name = "Rotate0"
    Label = (New-Text -CodePoints @(0x6E05, 0x9664, 0x65CB, 0x8F6C, 0x6807, 0x8BB0)) + " (0" + [char]0x00B0 + ")"
    Rotation = 0
  }
}

$targetMenuKeys = foreach ($extension in Get-VideoExtensions | Sort-Object -Unique) {
  $progId = Get-ExtensionProgId -Extension $extension

  if ([string]::IsNullOrWhiteSpace($progId)) {
    Write-Warning "No ProgID was found for $extension. Skipping this extension."
    continue
  }

  [pscustomobject]@{
    Path = "Software\Classes\$progId\shell\RotateVideoDisplayMetadata"
    Extension = $extension
    ProgId = $progId
  }
}

foreach ($target in $targetMenuKeys | Sort-Object Path -Unique) {
  Install-MenuAtSubKey -SubKeyPath $target.Path -Entries $menuEntries
}

Refresh-ShellAssociations

Write-Output "Installed per-user menu entries:"
foreach ($target in $targetMenuKeys | Sort-Object Path -Unique) {
  Write-Output "  HKCU\\$($target.Path) [$($target.Extension)]"
}
Write-Output "Installed runtime files: $installRoot"
Write-Output "Installed helper script: $resolvedInvokeScriptPath"
Write-Output "Installed uninstall script: $resolvedUninstallScriptPath"
Write-Output "To uninstall later, run:"
Write-Output "  powershell -ExecutionPolicy Bypass -File `"$resolvedUninstallScriptPath`""

switch ($ffmpegPathSource) {
  "explicit" {
    Write-Output "Pinned ffmpeg path: $pinnedFfmpegPath"
  }
  "auto-detected" {
    Write-Output "Detected ffmpeg during install: $detectedFfmpegPath"
    Write-Output "ffmpeg path was intentionally left unpinned so the runtime script can resolve it dynamically."
  }
  default {
    Write-Warning "ffmpeg.exe was not found during install. The menu was installed, but it will not work until ffmpeg is available on PATH or in a common install location, or until you reinstall with -FfmpegPath."
    Write-Output "ffmpeg path not pinned. The helper script will look in PATH/common locations at runtime."
  }
}

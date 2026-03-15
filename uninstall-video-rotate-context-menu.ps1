param()

$ErrorActionPreference = "Stop"

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

function Refresh-ShellAssociations {
  if (-not ("Win32.NativeMethods" -as [type])) {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
"@
  }

  [Win32.NativeMethods]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
}

$menuKeyNames = @(
  "RotateVideoDisplayMetadata",
  "RotateVideoDisplayMetadata10Rotate90CCW",
  "RotateVideoDisplayMetadata20Rotate180",
  "RotateVideoDisplayMetadata30Rotate90CW",
  "RotateVideoDisplayMetadata40Rotate0",
  "RotateVideoTest"
)

$subKeys = @()

foreach ($extension in Get-VideoExtensions) {
  foreach ($menuKeyName in $menuKeyNames) {
    $subKeys += "Software\Classes\SystemFileAssociations\$extension\shell\$menuKeyName"
  }
}

foreach ($menuKeyName in $menuKeyNames) {
  $subKeys += "Software\Classes\*\shell\$menuKeyName"
  $subKeys += "Software\Classes\SystemFileAssociations\video\shell\$menuKeyName"
}

foreach ($extension in Get-VideoExtensions) {
  $progId = Get-ExtensionProgId -Extension $extension
  if (-not [string]::IsNullOrWhiteSpace($progId)) {
    foreach ($menuKeyName in $menuKeyNames) {
      $subKeys += "Software\Classes\$progId\shell\$menuKeyName"
    }
  }
}

foreach ($subKey in $subKeys | Sort-Object -Unique) {
  $existingKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
  if ($existingKey) {
    $existingKey.Close()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subKey, $false)
    Write-Output "Removed: HKCU\\$subKey"
  }
}

$installRoot = Get-InstallRoot
$installedInvokeScriptPath = Join-Path $installRoot "invoke-video-display-rotation.ps1"
$installedUninstallScriptPath = Join-Path $installRoot "uninstall-video-rotate-context-menu.ps1"
$currentScriptPath = ""

if ($PSCommandPath) {
  try {
    $currentScriptPath = (Resolve-Path -LiteralPath $PSCommandPath).Path
  } catch {
    $currentScriptPath = $PSCommandPath
  }
}

if (Test-Path -LiteralPath $installedInvokeScriptPath) {
  Remove-Item -LiteralPath $installedInvokeScriptPath -Force -ErrorAction SilentlyContinue
  Write-Output "Removed installed helper script: $installedInvokeScriptPath"
}

if (
  (Test-Path -LiteralPath $installedUninstallScriptPath) -and
  ($currentScriptPath -ne (Resolve-Path -LiteralPath $installedUninstallScriptPath).Path)
) {
  Remove-Item -LiteralPath $installedUninstallScriptPath -Force -ErrorAction SilentlyContinue
  Write-Output "Removed installed uninstall script: $installedUninstallScriptPath"
}

if (Test-Path -LiteralPath $installRoot) {
  try {
    $remainingItems = @(Get-ChildItem -LiteralPath $installRoot -Force)
  } catch {
    $remainingItems = @()
  }

  if ($remainingItems.Count -eq 0) {
    Remove-Item -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue
    Write-Output "Removed install directory: $installRoot"
  } else {
    Write-Output "Install directory retained: $installRoot"
  }
}

Refresh-ShellAssociations

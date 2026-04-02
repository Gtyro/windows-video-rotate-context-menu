param(
  [string]$FfmpegPath = "",
  [string]$MenuText = "",
  [switch]$IncludeReset = $true,
  [string]$DeploymentRoot = ""
)

$ErrorActionPreference = "Stop"

function ConvertFrom-CodePoints {
  param(
    [int[]]$CodePoints
  )

  return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Set-RegistryStringValue {
  param(
    [Microsoft.Win32.RegistryKey]$Key,
    [string]$Name,
    [string]$Value
  )

  $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String)
}

function Get-VideoExtensions {
  return @(
    ".3g2", ".3gp", ".asf", ".avi", ".flv", ".m2ts", ".m4v", ".mkv",
    ".mov", ".mp4", ".mpeg", ".mpg", ".mts", ".ts", ".vob", ".webm", ".wmv"
  )
}

function Get-StateSubKeyPath {
  return "Software\VideoRotateContextMenu"
}

function Resolve-DeploymentRoot {
  param(
    [string]$Candidate
  )

  if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
    return [System.IO.Path]::GetFullPath($Candidate)
  }

  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw "LOCALAPPDATA is not available. Pass -DeploymentRoot explicitly."
  }

  return (Join-Path $env:LOCALAPPDATA "VideoRotateContextMenu")
}

function Copy-DeploymentFiles {
  param(
    [string]$SourceRoot,
    [string]$DestinationRoot
  )

  if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Source root does not exist: $SourceRoot"
  }

  New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

  $runtimeFiles = @(
    "invoke-video-display-rotation.ps1",
    "uninstall-video-rotate-context-menu.ps1"
  )

  foreach ($fileName in $runtimeFiles) {
    $sourcePath = Join-Path $SourceRoot $fileName
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw "Missing runtime file: $sourcePath"
    }

    $destinationPath = Join-Path $DestinationRoot $fileName
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
  }
}

function Write-InstallState {
  param(
    [string]$DeploymentRootPath,
    [string]$InvokeScriptPath,
    [string]$UninstallScriptPath,
    [string]$PinnedFfmpegPath
  )

  $stateKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Get-StateSubKeyPath))
  if (-not $stateKey) {
    throw "Failed to create registry key: HKCU\$(Get-StateSubKeyPath)"
  }

  try {
    Set-RegistryStringValue -Key $stateKey -Name "DeploymentRoot" -Value $DeploymentRootPath
    Set-RegistryStringValue -Key $stateKey -Name "InvokeScriptPath" -Value $InvokeScriptPath
    Set-RegistryStringValue -Key $stateKey -Name "UninstallScriptPath" -Value $UninstallScriptPath
    Set-RegistryStringValue -Key $stateKey -Name "FfmpegPath" -Value $PinnedFfmpegPath
    Set-RegistryStringValue -Key $stateKey -Name "InstalledAtUtc" -Value ([DateTime]::UtcNow.ToString("o"))
  } finally {
    $stateKey.Close()
  }
}

$defaultMenuText = ConvertFrom-CodePoints @(0x65CB, 0x8F6C, 0x89C6, 0x9891)
if ([string]::IsNullOrWhiteSpace($MenuText)) {
  $MenuText = $defaultMenuText
}

$sourceScriptRoot = Split-Path -Parent $PSCommandPath
$sourceInvokeScriptPath = Join-Path $sourceScriptRoot "invoke-video-display-rotation.ps1"
$sourceUninstallScriptPath = Join-Path $sourceScriptRoot "uninstall-video-rotate-context-menu.ps1"

if (-not (Test-Path -LiteralPath $sourceInvokeScriptPath)) {
  throw "Missing helper script: $sourceInvokeScriptPath"
}

if (-not (Test-Path -LiteralPath $sourceUninstallScriptPath)) {
  throw "Missing uninstall script: $sourceUninstallScriptPath"
}

$resolvedDeploymentRoot = Resolve-DeploymentRoot -Candidate $DeploymentRoot
Copy-DeploymentFiles -SourceRoot $sourceScriptRoot -DestinationRoot $resolvedDeploymentRoot

$resolvedInvokeScriptPath = (Resolve-Path -LiteralPath (Join-Path $resolvedDeploymentRoot "invoke-video-display-rotation.ps1")).Path
$resolvedDeployedUninstallScriptPath = (Resolve-Path -LiteralPath (Join-Path $resolvedDeploymentRoot "uninstall-video-rotate-context-menu.ps1")).Path
$resolvedFfmpegPath = ""

if (-not [string]::IsNullOrWhiteSpace($FfmpegPath)) {
  if (-not (Test-Path -LiteralPath $FfmpegPath)) {
    throw "Specified ffmpeg was not found: $FfmpegPath"
  }

  $resolvedFfmpegPath = (Resolve-Path -LiteralPath $FfmpegPath).Path
}

$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

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

  if (-not [string]::IsNullOrWhiteSpace($resolvedFfmpegPath)) {
    $parts += @("-FfmpegPath", '"' + $resolvedFfmpegPath + '"')
  }

  return ($parts -join " ")
}

function Install-MenuAtSubKey {
  param(
    [string]$SubKeyPath,
    [string]$AppliesTo = ""
  )

  $baseKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKeyPath)
  if (-not $baseKey) {
    throw "Failed to create registry key: HKCU\$SubKeyPath"
  }

  try {
    Set-RegistryStringValue -Key $baseKey -Name "" -Value ""
    Set-RegistryStringValue -Key $baseKey -Name "MUIVerb" -Value $MenuText
    Set-RegistryStringValue -Key $baseKey -Name "SubCommands" -Value ""
    Set-RegistryStringValue -Key $baseKey -Name "Icon" -Value "%SystemRoot%\System32\shell32.dll,133"

    if (-not [string]::IsNullOrWhiteSpace($AppliesTo)) {
      Set-RegistryStringValue -Key $baseKey -Name "AppliesTo" -Value $AppliesTo
    } else {
      $baseKey.DeleteValue("AppliesTo", $false)
    }
  } finally {
    $baseKey.Close()
  }

  foreach ($entry in $menuEntries) {
    $entryKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$SubKeyPath\shell\$($entry.Name)")
    if (-not $entryKey) {
      throw "Failed to create registry key: HKCU\$SubKeyPath\shell\$($entry.Name)"
    }

    try {
      Set-RegistryStringValue -Key $entryKey -Name "MUIVerb" -Value $entry.Label
      Set-RegistryStringValue -Key $entryKey -Name "Icon" -Value "%SystemRoot%\System32\shell32.dll,133"
    } finally {
      $entryKey.Close()
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
  [pscustomobject]@{ Name = "Rotate90CCW"; Label = (ConvertFrom-CodePoints @(0x9006, 0x65F6, 0x9488, 0x0020, 0x0039, 0x0030, 0x00B0)); Rotation = 90 },
  [pscustomobject]@{ Name = "Rotate180"; Label = (ConvertFrom-CodePoints @(0x65CB, 0x8F6C, 0x0020, 0x0031, 0x0038, 0x0030, 0x00B0)); Rotation = 180 },
  [pscustomobject]@{ Name = "Rotate90CW"; Label = (ConvertFrom-CodePoints @(0x987A, 0x65F6, 0x9488, 0x0020, 0x0039, 0x0030, 0x00B0)); Rotation = 270 }
)

if ($IncludeReset) {
  $menuEntries += [pscustomobject]@{ Name = "Rotate0"; Label = (ConvertFrom-CodePoints @(0x6E05, 0x9664, 0x65CB, 0x8F6C, 0x6807, 0x8BB0, 0x0020, 0x0028, 0x0030, 0x00B0, 0x0029)); Rotation = 0 }
}

$targetSubKeys = @()

foreach ($extension in Get-VideoExtensions) {
  $targetSubKeys += [pscustomobject]@{
    Path = "Software\Classes\SystemFileAssociations\$extension\shell\RotateVideoDisplayMetadata"
    AppliesTo = ""
  }
}

foreach ($target in $targetSubKeys | Sort-Object Path -Unique) {
  Install-MenuAtSubKey -SubKeyPath $target.Path -AppliesTo $target.AppliesTo
}

Write-InstallState `
  -DeploymentRootPath $resolvedDeploymentRoot `
  -InvokeScriptPath $resolvedInvokeScriptPath `
  -UninstallScriptPath $resolvedDeployedUninstallScriptPath `
  -PinnedFfmpegPath $resolvedFfmpegPath

Write-Output "Installed per-user menu entries:"
foreach ($target in $targetSubKeys | Sort-Object Path -Unique) {
  Write-Output "  HKCU\\$($target.Path)"
}

Write-Output "Deployment root: $resolvedDeploymentRoot"
Write-Output "Helper script: $resolvedInvokeScriptPath"
Write-Output "Uninstall script: $resolvedDeployedUninstallScriptPath"
Write-Output "The project folder is no longer required after installation."

if ([string]::IsNullOrWhiteSpace($resolvedFfmpegPath)) {
  Write-Output "ffmpeg path not pinned. The helper script will look in PATH/common locations at runtime."
} else {
  Write-Output "Pinned ffmpeg path: $resolvedFfmpegPath"
}

if ([Environment]::OSVersion.Version.Build -ge 22000) {
  Write-Output 'Windows 11 note: this menu uses the classic shell verb model and usually appears under "Show more options" (Shift+F10).'
}

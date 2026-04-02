param()

$ErrorActionPreference = "Stop"

function Get-VideoExtensions {
  return @(
    ".3g2", ".3gp", ".asf", ".avi", ".flv", ".m2ts", ".m4v", ".mkv",
    ".mov", ".mp4", ".mpeg", ".mpg", ".mts", ".ts", ".vob", ".webm", ".wmv"
  )
}

function Get-StateSubKeyPath {
  return "Software\VideoRotateContextMenu"
}

function Get-DefaultDeploymentRoot {
  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    return ""
  }

  return (Join-Path $env:LOCALAPPDATA "VideoRotateContextMenu")
}

function Get-InstallState {
  $stateKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey((Get-StateSubKeyPath))
  if (-not $stateKey) {
    return $null
  }

  try {
    return [pscustomobject]@{
      DeploymentRoot = [string]$stateKey.GetValue("DeploymentRoot", "")
      InvokeScriptPath = [string]$stateKey.GetValue("InvokeScriptPath", "")
      UninstallScriptPath = [string]$stateKey.GetValue("UninstallScriptPath", "")
    }
  } finally {
    $stateKey.Close()
  }
}

function Remove-InstallState {
  $statePath = Get-StateSubKeyPath
  $existingKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($statePath)
  if ($existingKey) {
    $existingKey.Close()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($statePath, $false)
    Write-Output "Removed: HKCU\\$statePath"
  }
}

function Test-IsWithinPath {
  param(
    [string]$ParentPath,
    [string]$ChildPath
  )

  if ([string]::IsNullOrWhiteSpace($ParentPath) -or [string]::IsNullOrWhiteSpace($ChildPath)) {
    return $false
  }

  $resolvedParentPath = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\')
  $resolvedChildPath = [System.IO.Path]::GetFullPath($ChildPath)

  return (
    $resolvedChildPath.Equals($resolvedParentPath, [System.StringComparison]::OrdinalIgnoreCase) -or
    $resolvedChildPath.StartsWith($resolvedParentPath + "\", [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Start-DeferredDeploymentCleanup {
  param(
    [string]$DeploymentRootPath
  )

  $cleanupScriptPath = Join-Path $env:TEMP ("video-rotate-context-menu-cleanup-{0}.ps1" -f [guid]::NewGuid().ToString("N"))
  $cleanupScriptContent = @(
    'param(',
    '  [Parameter(Mandatory)]',
    '  [string]$TargetPath,',
    '  [Parameter(Mandatory)]',
    '  [string]$SelfPath',
    ')',
    '$ErrorActionPreference = "SilentlyContinue"',
    'Start-Sleep -Seconds 2',
    'if (Test-Path -LiteralPath $TargetPath) {',
    '  Remove-Item -LiteralPath $TargetPath -Recurse -Force',
    '}',
    'if (Test-Path -LiteralPath $SelfPath) {',
    '  Remove-Item -LiteralPath $SelfPath -Force',
    '}'
  )

  Set-Content -LiteralPath $cleanupScriptPath -Value $cleanupScriptContent -Encoding Ascii

  $powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  Start-Process `
    -FilePath $powerShellExe `
    -ArgumentList @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $cleanupScriptPath,
      "-TargetPath", $DeploymentRootPath,
      "-SelfPath", $cleanupScriptPath
    ) `
    -WindowStyle Hidden | Out-Null
}

function Remove-DeploymentRoot {
  param(
    [string]$DeploymentRootPath
  )

  if ([string]::IsNullOrWhiteSpace($DeploymentRootPath)) {
    return
  }

  if (-not (Test-Path -LiteralPath $DeploymentRootPath)) {
    return
  }

  $resolvedDeploymentRootPath = [System.IO.Path]::GetFullPath($DeploymentRootPath)
  $expectedFiles = @(
    (Join-Path $resolvedDeploymentRootPath "invoke-video-display-rotation.ps1"),
    (Join-Path $resolvedDeploymentRootPath "uninstall-video-rotate-context-menu.ps1")
  )

  $containsExpectedFiles = $false
  foreach ($expectedFile in $expectedFiles) {
    if (Test-Path -LiteralPath $expectedFile) {
      $containsExpectedFiles = $true
      break
    }
  }

  if (-not $containsExpectedFiles) {
    Write-Warning "Skipping deployment directory cleanup because expected runtime files were not found: $resolvedDeploymentRootPath"
    return
  }

  $currentScriptPath = ""
  if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path -LiteralPath $PSCommandPath)) {
    $currentScriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
  }

  if (Test-IsWithinPath -ParentPath $resolvedDeploymentRootPath -ChildPath $currentScriptPath) {
    Start-DeferredDeploymentCleanup -DeploymentRootPath $resolvedDeploymentRootPath
    Write-Output "Scheduled deployment directory cleanup: $resolvedDeploymentRootPath"
    return
  }

  Remove-Item -LiteralPath $resolvedDeploymentRootPath -Recurse -Force
  Write-Output "Removed deployment directory: $resolvedDeploymentRootPath"
}

$menuKeyNames = @(
  "RotateVideoDisplayMetadata",
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

foreach ($subKey in $subKeys | Sort-Object -Unique) {
  $existingKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
  if ($existingKey) {
    $existingKey.Close()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subKey, $false)
    Write-Output "Removed: HKCU\\$subKey"
  }
}

$installState = Get-InstallState
$deploymentRoot = ""

if ($installState -and -not [string]::IsNullOrWhiteSpace($installState.DeploymentRoot)) {
  $deploymentRoot = $installState.DeploymentRoot
} else {
  $deploymentRoot = Get-DefaultDeploymentRoot
}

Remove-InstallState
Remove-DeploymentRoot -DeploymentRootPath $deploymentRoot

param(
  [Parameter(Mandatory)]
  [string]$InputPath,

  [Parameter(Mandatory)]
  [ValidateSet(0, 90, 180, 270)]
  [int]$Rotation,

  [string]$OutputPath = "",
  [string]$FfmpegPath = "",
  [switch]$Overwrite
)

$ErrorActionPreference = "Stop"

function Looks-LikeExecutablePath {
  param(
    [string]$Path
  )

  return (
    -not [string]::IsNullOrWhiteSpace($Path) -and
    [System.IO.Path]::IsPathRooted($Path) -and
    [System.IO.Path]::GetExtension($Path).Equals(".exe", [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Read-TextFileSafely {
  param(
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }

  try {
    if (Test-Path -LiteralPath $Path) {
      return ((Get-Content -LiteralPath $Path -Raw) -as [string]).Trim()
    }
  } catch {
  }

  return ""
}

function Show-ErrorDialog {
  param(
    [string]$Message
  )

  try {
    $shell = New-Object -ComObject WScript.Shell
    $null = $shell.Popup($Message, 0, "Video Rotate", 16)
  } catch {
  }
}

function Resolve-FfmpegPath {
  param(
    [string]$Candidate
  )

  if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
    try {
      if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        try {
          return (Resolve-Path -LiteralPath $Candidate).Path
        } catch {
          return $Candidate
        }
      }
    } catch [System.UnauthorizedAccessException] {
      if (Looks-LikeExecutablePath -Path $Candidate) {
        return $Candidate
      }
    } catch {
      if (Looks-LikeExecutablePath -Path $Candidate) {
        return $Candidate
      }
    }

    throw "Specified ffmpeg was not found: $Candidate"
  }

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

  if ($env:LOCALAPPDATA) {
    $commonCandidates += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe")

    $winGetPackageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    try {
      $ffmpegPackages = Get-ChildItem -LiteralPath $winGetPackageRoot -Directory -Filter "*FFmpeg*" -ErrorAction Stop
      foreach ($package in $ffmpegPackages | Sort-Object LastWriteTime -Descending) {
        try {
          $buildDirectories = Get-ChildItem -LiteralPath $package.FullName -Directory -Filter "ffmpeg*-build" -ErrorAction Stop
          foreach ($buildDirectory in $buildDirectories | Sort-Object LastWriteTime -Descending) {
            $commonCandidates += (Join-Path $buildDirectory.FullName "bin\ffmpeg.exe")
          }
        } catch {
        }
      }
    } catch {
    }
  }

  foreach ($item in $commonCandidates) {
    if ([string]::IsNullOrWhiteSpace($item)) {
      continue
    }

    try {
      if (Test-Path -LiteralPath $item -PathType Leaf) {
        try {
          return (Resolve-Path -LiteralPath $item).Path
        } catch {
          return $item
        }
      }
    } catch [System.UnauthorizedAccessException] {
      if (Looks-LikeExecutablePath -Path $item) {
        return $item
      }
    } catch {
    }
  }

  throw "ffmpeg.exe was not found. Put ffmpeg on PATH or pass -FfmpegPath."
}

function New-DefaultOutputPath {
  param(
    [string]$ResolvedInputPath,
    [int]$NormalizedRotation
  )

  $inputItem = Get-Item -LiteralPath $ResolvedInputPath
  $suffix = "display-rot$NormalizedRotation"
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputItem.Name)
  $extension = $inputItem.Extension
  return (Join-Path $inputItem.DirectoryName "$baseName.$suffix$extension")
}

try {
  $resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
  $resolvedFfmpegPath = Resolve-FfmpegPath -Candidate $FfmpegPath

  if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = New-DefaultOutputPath -ResolvedInputPath $resolvedInputPath -NormalizedRotation $Rotation
  }

  $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

  if ($resolvedInputPath -eq $resolvedOutputPath) {
    throw "Input and output paths must be different."
  }

  $outputDirectory = Split-Path -Parent $resolvedOutputPath
  if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  }

  $ffmpegArgs = @(
    "-hide_banner",
    "-loglevel", "error"
  )

  if ($Overwrite) {
    $ffmpegArgs += "-y"
  } else {
    $ffmpegArgs += "-n"
  }

  $ffmpegArgs += @(
    "-display_rotation:v:0", $Rotation.ToString(),
    "-i", $resolvedInputPath,
    "-map", "0",
    "-c", "copy",
    $resolvedOutputPath
  )

  $stderrLogPath = Join-Path $env:TEMP ("video-rotate-ffmpeg-" + [guid]::NewGuid().ToString("N") + ".log")

  try {
    & $resolvedFfmpegPath @ffmpegArgs 2> $stderrLogPath
    $ffmpegExitCode = $LASTEXITCODE
  } finally {
    $ffmpegErrorText = Read-TextFileSafely -Path $stderrLogPath
    Remove-Item -LiteralPath $stderrLogPath -Force -ErrorAction SilentlyContinue
  }

  if ($ffmpegExitCode -ne 0) {
    if ([string]::IsNullOrWhiteSpace($ffmpegErrorText)) {
      throw "ffmpeg exited with code $ffmpegExitCode."
    }

    throw "ffmpeg exited with code $ffmpegExitCode.`r`n$ffmpegErrorText"
  }

  if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
    throw "Output file was not created: $resolvedOutputPath"
  }

  $outputItem = Get-Item -LiteralPath $resolvedOutputPath
  if ($outputItem.Length -le 0) {
    throw "Output file is empty: $resolvedOutputPath"
  }

  Write-Output $outputItem.FullName
} catch {
  $message = $_.Exception.Message
  Show-ErrorDialog -Message $message
  Write-Error $message
  exit 1
}

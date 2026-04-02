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

function Resolve-FfmpegPath {
  param(
    [string]$Candidate
  )

  if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
    if (-not (Test-Path -LiteralPath $Candidate)) {
      throw "Specified ffmpeg was not found: $Candidate"
    }

    return (Resolve-Path -LiteralPath $Candidate).Path
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

  foreach ($item in $commonCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($item) -and (Test-Path -LiteralPath $item)) {
      return (Resolve-Path -LiteralPath $item).Path
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

& $resolvedFfmpegPath @ffmpegArgs

if ($LASTEXITCODE -ne 0) {
  throw "ffmpeg exited with code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $resolvedOutputPath)) {
  throw "Output file was not created: $resolvedOutputPath"
}

$outputItem = Get-Item -LiteralPath $resolvedOutputPath
if ($outputItem.Length -le 0) {
  throw "Output file is empty: $resolvedOutputPath"
}

Write-Output $outputItem.FullName

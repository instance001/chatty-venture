[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateRange(1, 2100000000)]
  [int]$BuildNumber,
  [string]$BuildName,
  [string]$ModelPath = 'assets/models/SmolLM2-360M-Instruct-Q4_K_M.gguf'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$modelFile = Join-Path $repoRoot $ModelPath
$marker = '    # LOCAL_PLAY_BUNDLE_MODEL -- injected temporarily by tool/build-play-bundled.ps1'
$assetLine = '    - assets/models/SmolLM2-360M-Instruct-Q4_K_M.gguf'

if (-not (Test-Path -LiteralPath $modelFile -PathType Leaf)) {
  throw "Bundled Play build stopped: model not found at $modelFile"
}

$originalPubspec = Get-Content -LiteralPath $pubspecPath -Raw
if (-not $originalPubspec.Contains($marker) -and $originalPubspec.Contains($assetLine)) {
  $originalPubspec = $originalPubspec.Replace($assetLine, $marker)
  Set-Content -LiteralPath $pubspecPath -Value $originalPubspec -NoNewline
}
if (-not $originalPubspec.Contains($marker)) {
  throw 'Bundled Play build stopped: pubspec asset marker is missing.'
}

try {
  Set-Content -LiteralPath $pubspecPath -Value $originalPubspec.Replace($marker, $assetLine) -NoNewline
  $arguments = @('build', 'appbundle', '--release', '--build-number', $BuildNumber)
  if ($BuildName) { $arguments += @('--build-name', $BuildName) }
  Push-Location $repoRoot
  try {
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter bundle build failed with exit code $LASTEXITCODE." }
  } finally {
    Pop-Location
  }
} finally {
  Set-Content -LiteralPath $pubspecPath -Value $originalPubspec -NoNewline
}

Write-Host "Bundled AAB ready: $(Join-Path $repoRoot 'build/app/outputs/bundle/release/app-release.aab')"

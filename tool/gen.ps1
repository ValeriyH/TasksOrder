# Code generation (drift, freezed, riverpod, json_serializable).
#   tool\gen.ps1          one-shot build
#   tool\gen.ps1 watch    rebuild on change
param([ValidateSet('build', 'watch')][string]$Mode = 'build')
Set-Location (Join-Path $PSScriptRoot '..')
dart run build_runner $Mode

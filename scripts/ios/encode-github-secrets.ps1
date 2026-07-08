$ErrorActionPreference = 'Stop'

$certDir = 'D:\Codex\ios-certs\com.taimingzhu.ymz'
$p12Path = Join-Path $certDir 'apple_distribution_com.taimingzhu.ymz.p12'
$passwordPath = Join-Path $certDir 'p12_password.txt'
$profilePath = Join-Path $certDir 'MingZhu_DaoJia_AppStore.mobileprovision'

if (!(Test-Path $p12Path)) { throw "Missing p12: $p12Path" }
if (!(Test-Path $passwordPath)) { throw "Missing p12 password: $passwordPath" }
if (!(Test-Path $profilePath)) { throw "Missing mobileprovision: $profilePath" }

$outputDir = Join-Path $certDir 'github-secrets'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

[IO.File]::WriteAllText(
  (Join-Path $outputDir 'IOS_P12_BASE64.txt'),
  [Convert]::ToBase64String([IO.File]::ReadAllBytes($p12Path)),
  [Text.Encoding]::ASCII
)

$password = (Get-Content -LiteralPath $passwordPath -Raw).Trim()
[IO.File]::WriteAllText(
  (Join-Path $outputDir 'IOS_P12_PASSWORD.txt'),
  $password,
  [Text.Encoding]::ASCII
)

[IO.File]::WriteAllText(
  (Join-Path $outputDir 'IOS_MOBILEPROVISION_BASE64.txt'),
  [Convert]::ToBase64String([IO.File]::ReadAllBytes($profilePath)),
  [Text.Encoding]::ASCII
)

Write-Host "Generated GitHub secret files:"
Get-ChildItem -LiteralPath $outputDir | Select-Object FullName, Length

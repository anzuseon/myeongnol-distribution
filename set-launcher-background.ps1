[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ImagePath,

    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
$rootDirectory = $PSScriptRoot
$sourceImage = Get-Item -LiteralPath $ImagePath
$extension = $sourceImage.Extension.ToLowerInvariant()
if($extension -notin '.png', '.jpg', '.jpeg', '.webp'){
    throw 'PNG, JPEG, WebP 파일을 지정하세요.'
}
if($sourceImage.Length -le 0 -or $sourceImage.Length -gt 20MB){
    throw '배경은 0바이트 초과, 20MiB 이하 파일이어야 합니다.'
}

Push-Location -LiteralPath $rootDirectory
try {
    $pending = @(git status --porcelain -- launcher)
    if($LASTEXITCODE -ne 0){ throw 'Git 상태 확인에 실패했습니다.' }
    if($pending.Count -gt 0){
        throw 'launcher 폴더에 아직 커밋하지 않은 변경이 있습니다. 먼저 정리한 뒤 실행하세요.'
    }
    $hash = (Get-FileHash -LiteralPath $sourceImage.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileName = "$hash$extension"
    $backgroundDirectory = Join-Path $rootDirectory 'launcher/backgrounds'
    New-Item -ItemType Directory -Path $backgroundDirectory -Force | Out-Null
    $destination = Join-Path $backgroundDirectory $fileName
    if(-not (Test-Path -LiteralPath $destination)){
        Copy-Item -LiteralPath $sourceImage.FullName -Destination $destination
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        background = [ordered]@{
            url = "https://raw.githubusercontent.com/anzuseon/myeongnol-distribution/main/launcher/backgrounds/$fileName"
            sha256 = $hash
        }
    }
    $manifestPath = Join-Path $rootDirectory 'launcher/appearance.json'
    $json = ($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))
    git add -- launcher/appearance.json "launcher/backgrounds/$fileName"
    if($LASTEXITCODE -ne 0){ throw '배경 Git 추가에 실패했습니다.' }
    git diff --cached --quiet -- launcher/appearance.json "launcher/backgrounds/$fileName"
    if($LASTEXITCODE -eq 0){
        Write-Host '이미 같은 배경이 지정되어 있습니다.'
        return
    }
    # Commit only these files; unrelated staged changes stay untouched.
    git commit --only -m "Update launcher background $($hash.Substring(0, 12))" -- launcher/appearance.json "launcher/backgrounds/$fileName"
    if($LASTEXITCODE -ne 0){ throw '배경 커밋에 실패했습니다.' }
    if(-not $NoPush){
        git push origin HEAD:main
        if($LASTEXITCODE -ne 0){ throw '배경 push에 실패했습니다. 원격 변경을 확인한 뒤 다시 push하세요.' }
    }
    Write-Host "배경 설정 완료: $fileName"
    Write-Host '런처 1.0.9 이상에서 시작 시와 실행 중 5분마다 반영합니다.'
} finally {
    Pop-Location
}


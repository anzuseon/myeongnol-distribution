# Large artifacts stay on disk for Nebula, but are downloaded from immutable Releases.
function Get-ReleaseArtifactUrl {
    param([string]$Repository, [string]$Sha256, [string]$FileName)
    return "https://github.com/$Repository/releases/download/artifact-$($Sha256.ToLowerInvariant())/$([uri]::EscapeDataString($FileName))"
}

function Get-GitHubReleaseHeaders {
    param([string]$Repository)
    $credentialLines = "protocol=https`nhost=github.com`npath=$Repository.git`n`n" | & git credential fill
    Assert-LastExitCode 'Reading GitHub credentials'
    $password = $credentialLines | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if(-not $password){ throw 'No GitHub credential found. Sign in to GitHub through Git first.' }
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $($password.Substring(9))"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Myeongnol-Modpack-Publisher'
    }
    $credentialLines = $null
    $password = $null
    return $headers
}

function Publish-ReleaseArtifact {
    param([string]$Repository, [string]$Branch, [string]$Path, [string]$Sha256, [hashtable]$Headers)
    $tag = "artifact-$($Sha256.ToLowerInvariant())"
    $apiRoot = "https://api.github.com/repos/$Repository"
    $item = Get-Item -LiteralPath $Path
    try {
        $release = Invoke-RestMethod -Uri "$apiRoot/releases/tags/$tag" -Headers $Headers
    } catch {
        if($null -eq $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 404){ throw }
        $payload = @{
            tag_name = $tag
            target_commitish = $Branch
            name = $item.Name
            body = "Launcher artifact: $($item.Name)`nSHA256: $Sha256`nSize: $($item.Length) bytes"
            draft = $false
            prerelease = $false
            make_latest = 'false'
        } | ConvertTo-Json
        $release = Invoke-RestMethod -Method Post -Uri "$apiRoot/releases" -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload))
    }
    if($release.draft){ throw "Artifact release is still a draft: $tag" }
    $existing = $release.assets | Where-Object { $_.name -eq $item.Name } | Select-Object -First 1
    if($existing){
        if([long]$existing.size -ne $item.Length -or $existing.state -ne 'uploaded'){
            throw "Existing release asset is incomplete or has a different size: $($item.Name)"
        }
        $digest = $existing.PSObject.Properties['digest']
        if($null -ne $digest -and $digest.Value){
            if([string]$digest.Value -ne "sha256:$($Sha256.ToLowerInvariant())"){
                throw "Existing release asset has a different SHA256: $($item.Name)"
            }
        } else {
            $temporary = [IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $existing.browser_download_url -OutFile $temporary
                if((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $Sha256){
                    throw "Existing release asset has a different SHA256: $($item.Name)"
                }
            } finally { Remove-Item -LiteralPath $temporary -Force }
        }
        return $existing.browser_download_url
    }
    Write-Step "Uploading large artifact to GitHub Releases: $($item.Name)"
    $uploadRoot = $release.upload_url -replace '\{\?name,label\}$', ''
    $uploaded = Invoke-RestMethod -Method Post -Uri "${uploadRoot}?name=$([uri]::EscapeDataString($item.Name))" -Headers $Headers -ContentType 'application/octet-stream' -InFile $Path -TimeoutSec 900
    if($uploaded.state -ne 'uploaded' -or [long]$uploaded.size -ne $item.Length){
        throw "Release upload did not complete: $($item.Name)"
    }
    $digest = $uploaded.PSObject.Properties['digest']
    if($null -ne $digest -and $digest.Value -and [string]$digest.Value -ne "sha256:$($Sha256.ToLowerInvariant())"){
        throw "Uploaded release asset SHA256 mismatch: $($item.Name)"
    }
    return $uploaded.browser_download_url
}

function Test-LargeArtifactChanges {
    param([string]$ServerDirectory, [string]$DistributionPath, [string]$ServerId)
    if(-not (Test-Path -LiteralPath $DistributionPath)){ return $true }
    $distro = Get-Content -LiteralPath $DistributionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $server = $distro.servers | Where-Object { $_.id -eq $ServerId } | Select-Object -First 1
    if($null -eq $server){ return $true }
    $largeFiles = @(Get-ChildItem -LiteralPath $ServerDirectory -Recurse -File | Where-Object { $_.Length -ge 100MB })
    foreach($file in $largeFiles){
        $modules = @($server.modules | Where-Object { ([uri]::UnescapeDataString(([uri]$_.artifact.url).AbsolutePath)).EndsWith('/' + $file.Name) })
        if($modules.Count -ne 1){ return $true }
        if([long]$modules[0].artifact.size -ne $file.Length -or [string]$modules[0].artifact.MD5 -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash){ return $true }
    }
    foreach($module in $server.modules){
        if(([string]$module.artifact.url) -like 'https://github.com/*/releases/download/artifact-*'){
            if(-not (Test-Path -LiteralPath (Resolve-ArtifactPath -Module $module -ServerDirectory $ServerDirectory))){ return $true }
        }
    }
    return $false
}

function Set-ReleaseArtifactUrls {
    param([object]$Server, [string]$ServerDirectory, [string]$RepositoryRoot, [string]$Repository, [string]$Branch, [switch]$SkipUpload)
    $headers = $null
    try {
        foreach($module in $Server.modules){
            $path = Resolve-ArtifactPath -Module $module -ServerDirectory $ServerDirectory
            if($null -eq $path){ continue }
            $item = Get-Item -LiteralPath $path
            if($item.Length -lt 100MB){ continue }
            if($item.Length -ge 2GB){ throw "Release artifact must be smaller than 2 GiB: $path" }
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if($SkipUpload){
                $module.artifact.url = Get-ReleaseArtifactUrl -Repository $Repository -Sha256 $hash -FileName $item.Name
                Write-Host "Release upload skipped (-NoPush): $($item.Name). Run normally with -Force before publishing."
            } else {
                if($null -eq $headers){ $headers = Get-GitHubReleaseHeaders -Repository $Repository }
                $module.artifact.url = Publish-ReleaseArtifact -Repository $Repository -Branch $Branch -Path $path -Sha256 $hash -Headers $headers
            }
            $relative = $item.FullName.Substring($RepositoryRoot.TrimEnd('\').Length + 1).Replace('\', '/')
            $ignorePath = Join-Path $RepositoryRoot '.gitignore'
            $ignoreLine = '/' + $relative
            $existing = [IO.File]::ReadAllText($ignorePath)
            if(($existing -split '\r?\n') -notcontains $ignoreLine){
                [IO.File]::AppendAllText($ignorePath, "`n$ignoreLine`n", (New-Object Text.UTF8Encoding($false)))
            }
            & git rm --cached --ignore-unmatch -- $relative
            Assert-LastExitCode 'Removing release artifact from Git index (local file retained)'
        }
    } finally { if($null -ne $headers){ $headers.Authorization = $null } }
}

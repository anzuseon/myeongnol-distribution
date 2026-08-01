[CmdletBinding()]
param(
    [ValidateSet('patch', 'minor', 'major', 'none')]
    [string]$Bump = 'patch',

    [string]$ServerId = 'Myeongnol-26.2',

    [string]$NebulaPath = 'D:\test\myeongnol-distribution',

    [string]$CommitMessage,

    [switch]$NoPush,

    [switch]$DryRun,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-LastExitCode {
    param([string]$Action)
    if($LASTEXITCODE -ne 0){
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

function Get-NextVersion {
    param(
        [string]$CurrentVersion,
        [string]$Mode
    )

    if($CurrentVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$'){
        throw "Server version must use MAJOR.MINOR.PATCH format. Found: $CurrentVersion"
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]

    switch($Mode){
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
        'none'  { }
    }

    return "$major.$minor.$patch"
}

function Resolve-ArtifactPath {
    param(
        [object]$Module,
        [string]$ServerDirectory
    )

    if($Module.type -eq 'FabricMod'){
        $uri = [uri]$Module.artifact.url
        $fileName = [uri]::UnescapeDataString([System.IO.Path]::GetFileName($uri.AbsolutePath))
        return Join-Path $ServerDirectory "fabricmods\required\$fileName"
    }

    if($Module.type -eq 'File'){
        $relativePath = ([string]$Module.artifact.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $filesRoot = [System.IO.Path]::GetFullPath((Join-Path $ServerDirectory 'files'))
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $filesRoot $relativePath))
        $allowedPrefix = $filesRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if(-not $resolved.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)){
            throw "File artifact escapes the server files directory: $relativePath"
        }
        return $resolved
    }

    return $null
}

function Test-DistributionArtifacts {
    param(
        [object]$Server,
        [string]$ServerDirectory
    )

    $checked = 0
    foreach($module in $Server.modules){
        $artifactPath = Resolve-ArtifactPath -Module $module -ServerDirectory $ServerDirectory
        if($null -eq $artifactPath){
            continue
        }

        if(-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)){
            throw "Artifact is missing: $artifactPath"
        }

        $item = Get-Item -LiteralPath $artifactPath
        if([long]$item.Length -ne [long]$module.artifact.size){
            throw "Artifact size mismatch: $artifactPath"
        }

        $actualMd5 = (Get-FileHash -LiteralPath $artifactPath -Algorithm MD5).Hash
        if($actualMd5 -ne ([string]$module.artifact.MD5).ToUpperInvariant()){
            throw "Artifact MD5 mismatch: $artifactPath"
        }

        $checked++
    }

    return $checked
}

$repositoryRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$serverDirectory = Join-Path $repositoryRoot "servers\$ServerId"
$serverMetaPath = Join-Path $serverDirectory 'servermeta.json'
$distributionPath = Join-Path $repositoryRoot 'distribution.json'

Write-Step 'Checking tools and repository'
foreach($commandName in @('git', 'node', 'npm.cmd')){
    if($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)){
        throw "Required command was not found: $commandName"
    }
}
if(-not (Test-Path -LiteralPath $serverMetaPath -PathType Leaf)){
    throw "Server metadata was not found: $serverMetaPath"
}
if(-not (Test-Path -LiteralPath (Join-Path $NebulaPath 'package.json') -PathType Leaf)){
    throw "Nebula was not found: $NebulaPath"
}

Push-Location $repositoryRoot
try {
    $gitRoot = (& git rev-parse --show-toplevel).Trim()
    Assert-LastExitCode 'Resolving Git repository'
    if([System.IO.Path]::GetFullPath($gitRoot) -ne $repositoryRoot.TrimEnd('\')){
        throw "Script must be located at the distribution repository root: $repositoryRoot"
    }

    $branch = (& git branch --show-current).Trim()
    Assert-LastExitCode 'Reading Git branch'
    if([string]::IsNullOrWhiteSpace($branch)){
        throw 'Cannot publish from a detached HEAD.'
    }

    $pendingServerChanges = @(& git status --porcelain --untracked-files=all -- "servers/$ServerId")
    Assert-LastExitCode 'Checking server changes'
    if($pendingServerChanges.Count -eq 0 -and -not $Force){
        Write-Host 'No modpack changes were found. Nothing was published.' -ForegroundColor Yellow
        exit 0
    }

    $meta = Get-Content -LiteralPath $serverMetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $currentVersion = [string]$meta.meta.version
    $nextVersion = Get-NextVersion -CurrentVersion $currentVersion -Mode $Bump

    Write-Host "Repository : $repositoryRoot"
    Write-Host "Branch     : $branch"
    Write-Host "Server     : $ServerId"
    Write-Host "Version    : $currentVersion -> $nextVersion"
    Write-Host 'Pending server changes:'
    $pendingServerChanges | ForEach-Object { Write-Host "  $_" }

    Write-Step 'Checking remote branch'
    & git fetch origin $branch
    Assert-LastExitCode 'Fetching origin'
    $behindCount = [int]((& git rev-list --count "HEAD..origin/$branch").Trim())
    Assert-LastExitCode 'Comparing remote branch'
    if($behindCount -gt 0){
        if($DryRun){
            Write-Host "Local branch is behind origin/$branch by $behindCount commit(s)." -ForegroundColor Yellow
            Write-Host 'A normal run will safely stash local changes, fast-forward, and restore them.' -ForegroundColor Yellow
        } else {
            Write-Step "Synchronizing $behindCount remote commit(s)"
            $workingChanges = @(& git status --porcelain --untracked-files=all)
            Assert-LastExitCode 'Checking working tree before synchronization'
            $stashCreated = $workingChanges.Count -gt 0
            $stashCommit = $null

            if($stashCreated){
                & git stash push --include-untracked --message "publish-modpack auto-sync $ServerId"
                Assert-LastExitCode 'Creating safety stash'
                $stashCommit = (& git rev-parse refs/stash).Trim()
                Assert-LastExitCode 'Reading safety stash'
            }

            & git pull --ff-only origin $branch
            $pullExitCode = $LASTEXITCODE
            if($pullExitCode -ne 0){
                if($stashCreated){
                    & git stash apply $stashCommit
                }
                throw "Fast-forwarding origin/$branch failed. Local changes are preserved in the safety stash."
            }

            if($stashCreated){
                & git stash apply $stashCommit
                if($LASTEXITCODE -ne 0){
                    throw 'Restoring local changes caused a conflict. The safety stash was kept for recovery.'
                }
                & git stash drop 'stash@{0}'
                Assert-LastExitCode 'Removing applied safety stash'
            }
        }
    }

    if($DryRun){
        Write-Host 'Dry run completed. No files were changed, committed, or pushed.' -ForegroundColor Green
        exit 0
    }

    if($Bump -ne 'none'){
        Write-Step "Updating server version to $nextVersion"
        $meta.meta.version = $nextVersion
        $json = $meta | ConvertTo-Json -Depth 100
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($serverMetaPath, "$json`n", $utf8WithoutBom)
    }

    Write-Step 'Generating distribution.json with Nebula'
    Push-Location $NebulaPath
    try {
        & npm.cmd run faststart -- generate distro
        Assert-LastExitCode 'Generating distribution.json'
    } finally {
        Pop-Location
    }

    if(-not (Test-Path -LiteralPath $distributionPath -PathType Leaf)){
        throw "Nebula did not create distribution.json: $distributionPath"
    }

    Write-Step 'Validating generated distribution'
    $distribution = Get-Content -LiteralPath $distributionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $server = $distribution.servers | Where-Object { $_.id -eq $ServerId } | Select-Object -First 1
    if($null -eq $server){
        throw "Generated distribution does not contain server: $ServerId"
    }
    if([string]$server.version -ne $nextVersion){
        throw "Generated server version is $($server.version), expected $nextVersion."
    }
    if(($null -eq $server.javaOptions) -or
        ([string]$server.javaOptions.supported -ne '>=25 <26') -or
        ([int]$server.javaOptions.suggestedMajor -ne 25)){
        throw 'Generated distribution must require Java 25 (supported: >=25 <26, suggestedMajor: 25).'
    }
    $checkedArtifacts = Test-DistributionArtifacts -Server $server -ServerDirectory $serverDirectory
    Write-Host "Validated $checkedArtifacts mod/file artifact(s)."

    Write-Step 'Staging distribution changes'
    & git add -- distribution.json "servers/$ServerId"
    Assert-LastExitCode 'Staging distribution changes'
    & git diff --cached --check
    Assert-LastExitCode 'Checking staged changes'

    & git diff --cached --quiet
    if($LASTEXITCODE -eq 0){
        Write-Host 'No publishable changes remained after generation.' -ForegroundColor Yellow
        exit 0
    }

    if([string]::IsNullOrWhiteSpace($CommitMessage)){
        $CommitMessage = "Update $ServerId modpack to $nextVersion"
    }

    Write-Step "Creating commit: $CommitMessage"
    & git commit -m $CommitMessage
    Assert-LastExitCode 'Creating Git commit'

    if(-not $NoPush){
        Write-Step "Pushing to origin/$branch"
        & git push origin $branch
        Assert-LastExitCode 'Pushing Git commit'
    }

    $commit = (& git rev-parse --short HEAD).Trim()
    Assert-LastExitCode 'Reading published commit'
    Write-Host "`nPublished successfully." -ForegroundColor Green
    Write-Host "Version : $nextVersion"
    Write-Host "Commit  : $commit"
    if($NoPush){
        Write-Host 'Push    : skipped (-NoPush)'
    } else {
        Write-Host "Push    : origin/$branch"
    }
} finally {
    Pop-Location
}

# Initialises a private GitHub repo for each project directory and pushes it.
#
# Each repo gets a .gitignore covering regenerable output (build dirs, package
# caches, virtualenvs). Without it these projects run to gigabytes — one is
# 2.5 GB of Flutter build output alone.
#
# Files over GitHub's 100 MB hard limit are excluded and reported: they cannot
# be pushed to a normal repo at all, so silently including them would just make
# the push fail after a long upload.

$ErrorActionPreference = 'Continue'

$GITIGNORE = @'
# Build output
build/
dist/
out/
target/
*.apk
*.aab

# Dependencies
node_modules/
.dart_tool/
.packages
.flutter-plugins
.flutter-plugins-dependencies
vendor/
__pycache__/
*.pyc
venv/
.venv/
env/

# Native / tooling
.gradle/
local.properties
*.jks
*.keystore
Pods/
.firebase/
firebase-debug.log

# KiCad generated / backups
*-backups/
fp-info-cache
*.kicad_prl
*.bak
*.000

# Editor / OS
.idea/
.vscode/
*.iml
.DS_Store
Thumbs.db
'@

function Publish-Project {
    param([string]$Path, [string]$RepoName)

    if (-not (Test-Path $Path)) { return [PSCustomObject]@{ Repo=$RepoName; Status='missing'; Note=$Path } }

    Push-Location $Path
    try {
        if (Test-Path (Join-Path $Path '.git')) {
            return [PSCustomObject]@{ Repo=$RepoName; Status='skipped'; Note='already a git repo' }
        }

        Set-Content -Path (Join-Path $Path '.gitignore') -Value $GITIGNORE -Encoding utf8

        git init -b main *>$null
        git config user.name  "Benard Phabian"      *>$null
        git config user.email "phabianbenard2019@gmail.com" *>$null
        git add -A *>$null

        # Drop anything GitHub will reject outright (100 MB per file).
        $oversize = @()
        git diff --cached --name-only | ForEach-Object {
            $f = Join-Path $Path $_
            if (Test-Path $f -PathType Leaf) {
                $len = (Get-Item $f -ErrorAction SilentlyContinue).Length
                if ($len -gt 100MB) {
                    $oversize += "$_ ($([math]::Round($len/1MB)) MB)"
                    git rm --cached -q -- $_ *>$null
                    Add-Content -Path (Join-Path $Path '.gitignore') -Value $_
                }
            }
        }
        if ($oversize.Count) { git add -A *>$null }

        $count = (git diff --cached --name-only | Measure-Object).Count
        if ($count -eq 0) {
            return [PSCustomObject]@{ Repo=$RepoName; Status='empty'; Note='nothing to commit' }
        }

        git commit -q -m "Initial commit: $RepoName" *>$null

        gh repo create $RepoName --private --source=. --remote=origin --push *>$null
        if ($LASTEXITCODE -ne 0) {
            return [PSCustomObject]@{ Repo=$RepoName; Status='FAILED'; Note='gh repo create/push failed' }
        }

        $note = "$count files"
        if ($oversize.Count) { $note += "; EXCLUDED >100MB: " + ($oversize -join ', ') }
        return [PSCustomObject]@{ Repo=$RepoName; Status='pushed'; Note=$note }
    }
    finally { Pop-Location }
}

$targets = @()
foreach ($d in Get-ChildItem 'c:\Users\user\WEB DEVELOPMENT' -Directory) {
    if ($d.Name -eq 'ekonnect') { continue }   # already published
    $targets += [PSCustomObject]@{ Path=$d.FullName; Name=($d.Name -replace '[^A-Za-z0-9._-]','-') }
}
foreach ($d in Get-ChildItem 'c:\Users\user\KICAD' -Directory) {
    $targets += [PSCustomObject]@{ Path=$d.FullName; Name=('kicad-' + ($d.Name -replace '[^A-Za-z0-9._-]','-')) }
}

$results = foreach ($t in $targets) {
    Write-Host "-> $($t.Name)"
    Publish-Project -Path $t.Path -RepoName $t.Name
}

""
"================ RESULTS ================"
$results | Format-Table -AutoSize -Wrap

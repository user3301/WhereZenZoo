#Requires -Version 7.0
<#
Adapted from https://github.com/ohmyzsh/ohmyzsh/blob/6010fb6260f359e71d99ba25f05f9215809b3ed2/plugins/git/git.plugin.zsh

MIT License

Copyright (c) 2009-2026 Robby Russell and contributors (https://github.com/ohmyzsh/ohmyzsh/contributors)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

function Get-GitCurrentBranch {
    $branch = & git symbolic-ref --quiet --short HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        $branch = & git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the current Git branch or commit.' }
    }
    $branch
}

function Get-GitMainBranch {
    & git rev-parse --git-dir *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Not inside a Git repository.' }

    foreach ($scope in @('refs/heads', 'refs/remotes/origin', 'refs/remotes/upstream')) {
        foreach ($branch in @('main', 'trunk', 'mainline', 'default', 'stable', 'master')) {
            & git show-ref --quiet --verify "$scope/$branch"
            if ($LASTEXITCODE -eq 0) { return $branch }
        }
    }
    foreach ($remote in @('origin', 'upstream')) {
        $ref = & git symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>$null
        if ($LASTEXITCODE -eq 0 -and $ref.StartsWith("$remote/")) {
            return $ref.Substring($remote.Length + 1)
        }
    }
    throw 'Cannot determine the main Git branch; set origin/HEAD or create a standard main branch.'
}

function Get-GitDevelopBranch {
    & git rev-parse --git-dir *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Not inside a Git repository.' }

    foreach ($branch in @('dev', 'devel', 'develop', 'development')) {
        & git show-ref --quiet --verify "refs/heads/$branch"
        if ($LASTEXITCODE -eq 0) { return $branch }
    }
    throw 'Cannot determine the develop Git branch.'
}

$gitLogDate = '--pretty=%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset'
$gitLogRelative = '--pretty=%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset'
$gitShortcuts = @{
    ga = 'add'
    gaa = 'add --all'
    gapa = 'add --patch'
    gau = 'add --update'
    gav = 'add --verbose'
    gam = 'am'
    gama = 'am --abort'
    gamc = 'am --continue'
    gamscp = 'am --show-current-patch'
    gams = 'am --skip'
    gap = 'apply'
    gapt = 'apply --3way'

    gbs = 'bisect'
    gbsb = 'bisect bad'
    gbsg = 'bisect good'
    gbsn = 'bisect new'
    gbso = 'bisect old'
    gbsr = 'bisect reset'
    gbss = 'bisect start'
    gbl = 'blame -w'
    gb = 'branch'
    gba = 'branch --all'
    gbd = 'branch --delete'
    gbdf = 'branch --delete --force'
    gbm = 'branch --move'
    gbnm = 'branch --no-merged'
    gbr = 'branch --remotes'
    ggsup = { @('branch', ("--set-upstream-to=origin/" + (Get-GitCurrentBranch))) }

    gco = 'checkout'
    gcor = 'checkout --recurse-submodules'
    gcb = 'checkout -b'
    gcbf = 'checkout -B'
    gcd = { @('checkout', (Get-GitDevelopBranch)) }
    gcp = 'cherry-pick'
    gcpa = 'cherry-pick --abort'
    gcpc = 'cherry-pick --continue'
    gclean = 'clean --interactive -d'
    gcl = 'clone --recurse-submodules'
    gclf = 'clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'

    gcam = 'commit --all --message'
    gcas = 'commit --all --signoff'
    gcasm = 'commit --all --signoff --message'
    gcss = 'commit --gpg-sign --signoff'
    gcssm = 'commit --gpg-sign --signoff --message'
    gcmsg = 'commit --message'
    gcsm = 'commit --signoff --message'
    gca = 'commit --verbose --all'
    'gca!' = 'commit --verbose --all --amend'
    'gcan!' = 'commit --verbose --all --no-edit --amend'
    'gcans!' = 'commit --verbose --all --signoff --no-edit --amend'
    'gcann!' = 'commit --verbose --all --date=now --no-edit --amend'
    'gc!' = 'commit --verbose --amend'
    gcn = 'commit --verbose --no-edit'
    'gcn!' = 'commit --verbose --no-edit --amend'
    gcf = 'config --list'
    gcfu = 'commit --fixup'

    gd = 'diff'
    gdca = 'diff --cached'
    gdcw = 'diff --cached --word-diff'
    gds = 'diff --staged'
    gdw = 'diff --word-diff'
    gdup = 'diff @{upstream}'
    gdt = 'diff-tree --no-commit-id --name-only -r'
    gf = 'fetch'
    gfa = 'fetch --all --tags --prune --jobs=10'
    gfo = 'fetch origin'
    gg = 'gui citool'
    gga = 'gui citool --amend'
    ghh = 'help'

    glgg = 'log --graph'
    glgga = 'log --graph --decorate --all'
    glgm = 'log --graph --max-count=10'
    glods = @('log', '--graph', $gitLogDate, '--date=short')
    glod = @('log', '--graph', $gitLogDate)
    glola = @('log', '--graph', $gitLogRelative, '--all')
    glols = @('log', '--graph', $gitLogRelative, '--stat')
    glol = @('log', '--graph', $gitLogRelative)
    glolm = { @('log', (Get-GitMainBranch), '--graph', $gitLogRelative) }
    glo = 'log --oneline --decorate'
    glog = 'log --oneline --decorate --graph'
    gloga = 'log --oneline --decorate --graph --all'
    glom = { @('log', '--oneline', '--decorate', '--color', ((Get-GitMainBranch) + '..')) }
    glg = 'log --stat'
    glgp = 'log --stat --patch'

    gma = 'merge --abort'
    gmc = 'merge --continue'
    gms = 'merge --squash'
    gmff = 'merge --ff-only'
    gmom = { @('merge', ('origin/' + (Get-GitMainBranch))) }
    gmum = { @('merge', ('upstream/' + (Get-GitMainBranch))) }
    gmtl = 'mergetool --no-prompt'
    gmtlvim = 'mergetool --no-prompt --tool=vimdiff'

    gpr = 'pull --rebase'
    gprv = 'pull --rebase -v'
    gpra = 'pull --rebase --autostash'
    gprav = 'pull --rebase --autostash -v'
    gprom = { @('pull', '--rebase', 'origin', (Get-GitMainBranch)) }
    gpromi = { @('pull', '--rebase=interactive', 'origin', (Get-GitMainBranch)) }
    gprum = { @('pull', '--rebase', 'upstream', (Get-GitMainBranch)) }
    gprumi = { @('pull', '--rebase=interactive', 'upstream', (Get-GitMainBranch)) }
    ggpull = { @('pull', 'origin', (Get-GitCurrentBranch)) }
    gluc = { @('pull', 'upstream', (Get-GitCurrentBranch)) }
    glum = { @('pull', 'upstream', (Get-GitMainBranch)) }

    gpd = 'push --dry-run'
    'gpf!' = 'push --force'
    gpf = 'push --force-with-lease --force-if-includes'
    gpsup = { @('push', '--set-upstream', 'origin', (Get-GitCurrentBranch)) }
    gpsupf = { @('push', '--set-upstream', 'origin', (Get-GitCurrentBranch), '--force-with-lease', '--force-if-includes') }
    gpod = 'push origin --delete'
    ggpush = { @('push', 'origin', (Get-GitCurrentBranch)) }
    gpu = 'push upstream'

    grb = 'rebase'
    grba = 'rebase --abort'
    grbc = 'rebase --continue'
    grbi = 'rebase --interactive'
    grbo = 'rebase --onto'
    grbs = 'rebase --skip'
    grbd = { @('rebase', (Get-GitDevelopBranch)) }
    grbm = { @('rebase', (Get-GitMainBranch)) }
    grbom = { @('rebase', ('origin/' + (Get-GitMainBranch))) }
    grbum = { @('rebase', ('upstream/' + (Get-GitMainBranch))) }
    grbmi = { @('rebase', (Get-GitMainBranch), '--interactive') }
    grbmia = { @('rebase', (Get-GitMainBranch), '--interactive', '--autosquash') }
    grf = 'reflog'
    gr = 'remote'
    grv = 'remote --verbose'
    gra = 'remote add'
    grrm = 'remote remove'
    grmv = 'remote rename'
    grset = 'remote set-url'
    grup = 'remote update'
    grh = 'reset'
    gru = 'reset --'
    grhh = 'reset --hard'
    grhk = 'reset --keep'
    grhs = 'reset --soft'
    groh = { @('reset', ('origin/' + (Get-GitCurrentBranch)), '--hard') }
    grs = 'restore'
    grss = 'restore --source'
    grst = 'restore --staged'
    grev = 'revert'
    greva = 'revert --abort'
    grevc = 'revert --continue'
    grm = 'rm'
    grmc = 'rm --cached'

    gcount = 'shortlog --summary --numbered'
    gsh = 'show'
    gshs = 'show --stat'
    gsps = 'show --pretty=short --show-signature'
    gstall = 'stash --all'
    gstaa = 'stash apply'
    gstc = 'stash clear'
    gstd = 'stash drop'
    gstl = 'stash list'
    gstp = 'stash pop'
    gsta = 'stash push'
    gsts = 'stash show --patch'
    gst = 'status'
    gss = 'status --short'
    gsb = 'status --short --branch'
    gsnut = 'status --untracked-files=no'
    gsi = 'submodule init'
    gsu = 'submodule update'
    gsuri = 'submodule update --recursive --init'
    gsd = 'svn dcommit'
    gsr = 'svn rebase'
    gsw = 'switch'
    gswc = 'switch --create'
    gswd = { @('switch', (Get-GitDevelopBranch)) }
    gswm = { @('switch', (Get-GitMainBranch)) }
    gta = 'tag --annotate'
    gts = 'tag --sign'
    gtv = 'tag --sort=v:refname'
    gignore = 'update-index --assume-unchanged'
    gunignore = 'update-index --no-assume-unchanged'
    gwch = 'log --patch --abbrev-commit --pretty=medium --raw'
    gwt = 'worktree'
    gwta = 'worktree add'
    gwtls = 'worktree list'
    gwtmv = 'worktree move'
    gwtrm = 'worktree remove'
    gstu = 'stash push --include-untracked'
}

function Invoke-GitShortcut {
    $name = $MyInvocation.InvocationName
    if (-not $gitShortcuts.ContainsKey($name)) { throw "Unknown Git shortcut: $name" }
    $command = $gitShortcuts[$name]
    if ($command -is [scriptblock]) {
        $fixed = @(& $command)
    } elseif ($command -is [string]) {
        $fixed = $command.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    } else {
        $fixed = @($command)
    }
    & git @fixed @args
}

function Invoke-GitOriginBranch {
    param([string[]]$Command, [string[]]$Branch)
    if ($Branch.Count -gt 1) { throw 'Expected at most one branch name.' }
    $name = if ($Branch.Count -eq 1) { $Branch[0] } else { Get-GitCurrentBranch }
    & git @Command origin $name
}

function ggu { Invoke-GitOriginBranch -Command @('pull', '--rebase') -Branch $args }
function ggl { Invoke-GitOriginBranch -Command @('pull') -Branch $args }
function ggp { Invoke-GitOriginBranch -Command @('push') -Branch $args }
function ggf { Invoke-GitOriginBranch -Command @('push', '--force') -Branch $args }
function ggfl { Invoke-GitOriginBranch -Command @('push', '--force-with-lease') -Branch $args }

function ggpnp {
    ggl @args
    if ($LASTEXITCODE -ne 0) { return }
    ggp @args
}

function grt {
    $root = & git rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the Git repository root.' }
    Set-Location -LiteralPath $root
}

function gwip {
    & git add -A
    if ($LASTEXITCODE -ne 0) { throw "git add failed (exit $LASTEXITCODE)." }
    & git commit --no-verify --no-gpg-sign --message '--wip-- [skip ci]' @args
}

function gbg {
    $previousLocale = $env:LC_ALL
    try {
        $env:LC_ALL = 'C'
        & git branch --no-color -vv | Where-Object { $_ -match ': gone\]' }
    } finally {
        $env:LC_ALL = $previousLocale
    }
}

function Get-GitGoneBranches {
    $previousLocale = $env:LC_ALL
    try {
        $env:LC_ALL = 'C'
        $refs = & git for-each-ref '--format=%(refname:short)%09%(upstream:track)' refs/heads
    } finally {
        $env:LC_ALL = $previousLocale
    }
    if ($LASTEXITCODE -ne 0) { throw "Cannot list local branches (git exit $LASTEXITCODE)." }
    foreach ($ref in $refs) {
        if ($ref -match "^(.*?)`t\[gone\]$") { $Matches[1] }
    }
}

function gbgd {
    $branches = @(Get-GitGoneBranches)
    if ($branches.Count) { & git branch -d @branches }
}

function gbgdf {
    $branches = @(Get-GitGoneBranches)
    if ($branches.Count) { & git branch -D @branches }
}

function gdct {
    $commit = & git rev-list --tags --max-count=1
    if ($LASTEXITCODE -ne 0 -or -not $commit) { throw 'Cannot find the latest tagged commit.' }
    & git describe --tags $commit @args
}

function Invoke-GitLogPrettily {
    if ($args.Count -lt 1) { throw 'Usage: glp <pretty-format> [git log arguments]' }
    $remaining = @()
    if ($args.Count -gt 1) { $remaining = @($args[1..($args.Count - 1)]) }
    & git log "--pretty=$($args[0])" @remaining
}

function gignored {
    & git ls-files -v | Where-Object { $_ -cmatch '^[a-z]' }
}

function gfg {
    if ($args.Count -ne 1) { throw 'Usage: gfg <regex>' }
    & git ls-files | Select-String -Pattern $args[0] -CaseSensitive |
        ForEach-Object Line
}

function gpoat {
    & git push origin --all
    if ($LASTEXITCODE -ne 0) { return }
    & git push origin --tags @args
}

function gpristine {
    & git reset --hard
    if ($LASTEXITCODE -ne 0) { return }
    & git clean --force -dfx @args
}

function gwipe {
    & git reset --hard
    if ($LASTEXITCODE -ne 0) { return }
    & git clean --force -df @args
}

function gunwip {
    $subject = & git log -1 --format=%s
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the latest Git commit.' }
    if ($subject -match '--wip--') { & git reset HEAD~1 @args }
}

function git-svn-dcommit-push {
    & git svn dcommit
    if ($LASTEXITCODE -ne 0) { return }
    & git push github ((Get-GitMainBranch) + ':svntrunk') @args
}

function gtl {
    if ($args.Count -gt 1) { throw 'Usage: gtl [tag-prefix]' }
    $prefix = if ($args.Count) { $args[0] } else { '' }
    & git tag --sort=-v:refname -n --list "$prefix*"
}

function gk {
    $gitk = Get-Command gitk -CommandType Application -ErrorAction Stop
    Start-Process -FilePath $gitk.Source -ArgumentList (@('--all', '--branches') + $args)
}

function gke {
    $commits = @(& git log --walk-reflogs --pretty=%h)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the Git reflog.' }
    $gitk = Get-Command gitk -CommandType Application -ErrorAction Stop
    Start-Process -FilePath $gitk.Source -ArgumentList (@('--all') + $commits + $args)
}

# Read-only PowerShell aliases gc, gcm, gcs, gl, gm, gp, and gpv are intentionally untouched.
# Command names ignore case, so gbD/gbgD/gcB use gbdf/gbgdf/gcbf instead.
Set-Alias -Name g -Value git
foreach ($name in $gitShortcuts.Keys) {
    Set-Alias -Name $name -Value Invoke-GitShortcut
}
Set-Alias -Name ggpur -Value ggu
Set-Alias -Name glp -Value Invoke-GitLogPrettily

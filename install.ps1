<#
.SYNOPSIS
    Installs the AGEX agents and slash commands for Claude Code on Windows.

.DESCRIPTION
    Links the AGEX agents and slash commands from a checkout of the repository
    into your Claude Code configuration directory (~\.claude\agents and
    ~\.claude\commands) so they are available in every project. When symbolic
    links are not permitted (Developer Mode off and not running as
    administrator), the files are copied instead.

    Run with -Help for all options and environment variables.

.PARAMETER Uninstall
    Remove the AGEX links and unmodified copies, restore files that -Force
    backed up, and leave the AGEX checkout in place.

.PARAMETER Force
    Move existing files that have the same names as AGEX files to
    CLAUDE_HOME\.agex-backup\<timestamp>\ and install the AGEX versions.

.PARAMETER Dir
    Use the AGEX checkout at this path instead of ~\.agex. It is cloned there
    if the directory does not exist.

.PARAMETER NoUpdate
    Do not run git pull on an existing checkout.

.PARAMETER Help
    Show usage information.

.EXAMPLE
    irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex

.EXAMPLE
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Force,
    [string]$Dir,
    [switch]$NoUpdate,
    [switch]$Help
)

# Compatible with Windows PowerShell 5.1 and PowerShell 7. The file is ASCII
# only because Windows PowerShell 5.1 reads files without a byte order mark in
# the system code page.
#
# All logic lives inside Invoke-AgexInstaller. "irm ... | iex" runs this script
# in the caller's scope, so keeping everything in one function leaves no
# preference variables or helper functions behind in the user's session, and
# failures are reported without closing the user's PowerShell window.

# The path of this file when it runs as a script (.\install.ps1 or -File).
# Code run by "irm ... | iex" or from a script block has no file, so this is
# empty then, even when "irm ... | iex" is itself used inside another script
# (where $MyInvocation would describe that other script).
$agexScriptPath = [string]({ }).File
# "irm ... | iex" binds no parameters and may not define $PSBoundParameters
# at all; test for it first so a session running Set-StrictMode is fine too.
$agexDirGiven = $false
if ((Test-Path -LiteralPath 'variable:PSBoundParameters') -and $null -ne $PSBoundParameters -and $PSBoundParameters.ContainsKey('Dir')) {
    $agexDirGiven = $true
}

function Invoke-AgexInstaller {
    param(
        [bool]$Uninstall,
        [bool]$Force,
        [bool]$DirGiven,
        [string]$Dir,
        [bool]$NoUpdate,
        [bool]$Help,
        [string]$ScriptPath
    )

    $ErrorActionPreference = 'Stop'

    # ------------------------------------------------------------------------
    # Output
    # ------------------------------------------------------------------------

    function Write-AgexText {
        param([string]$Text, [string]$Color, [switch]$NoNewline)
        if ($ctx.Color -and $Color) {
            Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewline
        }
        else {
            Write-Host $Text -NoNewline:$NoNewline
        }
    }

    function Write-AgexStep {
        param([string]$Text)
        Write-Host ''
        Write-AgexText '==> ' 'Blue' -NoNewline
        Write-Host $Text
    }

    function Write-AgexInfo {
        param([string]$Text)
        Write-Host ('    ' + $Text)
    }

    function Write-AgexOk {
        param([string]$Text)
        Write-AgexText '  + ' 'Green' -NoNewline
        Write-Host $Text
    }

    function Write-AgexNote {
        param([string]$Text)
        Write-AgexText '  - ' 'DarkGray' -NoNewline
        Write-Host $Text
    }

    function Write-AgexWarn {
        param([string]$Text)
        Write-AgexText 'warning: ' 'Yellow' -NoNewline
        Write-Host $Text
    }

    function Write-AgexError {
        param([string]$Text)
        Write-AgexText 'error: ' 'Red' -NoNewline
        Write-Host $Text
    }

    function Show-AgexBanner {
        $art = @(
            '    ___   ____________ _  __',
            '   /   | / ____/ ____/| |/ /',
            '  / /| |/ / __/ __/   |   /',
            ' / ___ / /_/ / /___  /   |',
            '/_/  |_\____/_____/ /_/|_|'
        )
        foreach ($line in $art) {
            Write-AgexText $line 'Magenta'
        }
        Write-Host ''
        Write-AgexText 'The Master Agent Orchestrator for Claude Code' 'Cyan'
    }

    function Show-AgexUsage {
        $usage = @'
AGEX installer for Windows PowerShell 5.1 and PowerShell 7

Links the AGEX agents and slash commands into your Claude Code configuration
(CLAUDE_HOME\agents and CLAUDE_HOME\commands) so they work in every project.
When symbolic links are not permitted (Developer Mode off and not running as
administrator), the files are copied instead; re-run the installer after each
AGEX update to refresh copies.

Usage:
  .\install.ps1 [-Uninstall] [-Force] [-Dir <path>] [-NoUpdate] [-Help]
  irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex

Parameters:
  -Uninstall     Remove the AGEX links and unmodified copies, restore files
                 that -Force backed up, and leave the AGEX checkout in place
  -Force         Move existing files that have the same names as AGEX files
                 to CLAUDE_HOME\.agex-backup\<timestamp>\, then install AGEX
  -Dir <path>    Use the AGEX checkout at <path> instead of ~\.agex
                 (it is cloned there if the directory does not exist)
  -NoUpdate      Do not run git pull on an existing checkout
  -Help          Show this help

Environment variables:
  AGEX_HOME       Checkout location (default: ~\.agex)
  AGEX_REPO       Repository to clone (default: https://github.com/saksham-eng560/agex.git)
  CLAUDE_HOME     Claude Code configuration directory (default: ~\.claude)
  NO_COLOR        Set to any non-empty value to disable colored output
  AGEX_UNINSTALL  Set to 1 to uninstall; "irm ... | iex" cannot pass parameters
  AGEX_FORCE      Set to 1 to act as if -Force was given
  AGEX_NO_UPDATE  Set to 1 to act as if -NoUpdate was given

Where the AGEX files come from, in order:
  1. -Dir <path>, when given
  2. the directory that contains this script, when it is run from an AGEX checkout
  3. AGEX_HOME: updated with git pull --ff-only when it exists, cloned when it does not

Existing files are never overwritten: without -Force they are skipped with a
warning. -Uninstall removes only links and unmodified copies that AGEX created
and never deletes the checkout. The plugin install is an alternative that
namespaces every agent as agex:<name>:
  claude plugin marketplace add saksham-eng560/agex
  claude plugin install agex@agex-marketplace

Examples:
  .\install.ps1                    Install, or refresh an existing install
  .\install.ps1 -NoUpdate          Refresh the links without pulling
  .\install.ps1 -Force             Replace same-named files (they are backed up)
  .\install.ps1 -Dir D:\src\agex   Link a checkout somewhere else
  .\install.ps1 -Uninstall         Remove AGEX from your Claude Code configuration

  Pass parameters to the one-line installer:
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1))) -Force

  Or use an environment variable:
  $env:AGEX_UNINSTALL = '1'; irm https://raw.githubusercontent.com/saksham-eng560/agex/main/install.ps1 | iex; Remove-Item Env:AGEX_UNINSTALL
'@
        Write-Host $usage
    }

    # ------------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------------

    function Test-AgexEnvFlag {
        param([string]$Name)
        $value = [System.Environment]::GetEnvironmentVariable($Name)
        if (-not $value) {
            return $false
        }
        return (@('1', 'true', 'yes', 'on') -contains $value.Trim().ToLowerInvariant())
    }

    function Get-AgexEnvValue {
        param([string]$Name)
        $value = [System.Environment]::GetEnvironmentVariable($Name)
        if ($null -eq $value) {
            return ''
        }
        return $value.Trim()
    }

    function Join-AgexPath {
        param([string]$Base, [string[]]$Parts)
        $result = $Base
        foreach ($part in $Parts) {
            $result = [System.IO.Path]::Combine($result, $part)
        }
        return $result
    }

    function Resolve-AgexFullPath {
        param([string]$Path)
        $p = $Path
        if ($p -eq '~') {
            $p = $HOME
        }
        elseif ($p.StartsWith('~/') -or $p.StartsWith('~\')) {
            $p = Join-Path -Path $HOME -ChildPath ($p.Substring(2))
        }
        if (-not [System.IO.Path]::IsPathRooted($p)) {
            $p = Join-Path -Path (Get-Location -PSProvider FileSystem).ProviderPath -ChildPath $p
        }
        $full = [System.IO.Path]::GetFullPath($p)
        $root = [System.IO.Path]::GetPathRoot($full)
        while ($full.Length -gt $root.Length -and ($full.EndsWith('\') -or $full.EndsWith('/'))) {
            $full = $full.Substring(0, $full.Length - 1)
        }
        return $full
    }

    function ConvertTo-AgexComparable {
        param([string]$Path)
        if (-not $Path) {
            return ''
        }
        $p = $Path
        if ($p.StartsWith('\\?\') -or $p.StartsWith('\??\')) {
            $p = $p.Substring(4)
        }
        $p = $p.Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)
        return $p.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    }

    function Test-AgexSamePath {
        param([string]$A, [string]$B)
        return [string]::Equals((ConvertTo-AgexComparable $A), (ConvertTo-AgexComparable $B), $ctx.PathComparison)
    }

    function Test-AgexPathUnder {
        # True when $Path is strictly inside directory $Parent.
        param([string]$Path, [string]$Parent)
        if (-not $Path -or -not $Parent) {
            return $false
        }
        $prefix = (ConvertTo-AgexComparable $Parent) + [System.IO.Path]::DirectorySeparatorChar
        return (ConvertTo-AgexComparable $Path).StartsWith($prefix, $ctx.PathComparison)
    }

    function Test-AgexListHas {
        param($List, [string]$Path)
        foreach ($item in $List) {
            if (Test-AgexSamePath $item $Path) {
                return $true
            }
        }
        return $false
    }

    function Format-AgexPath {
        # Show paths under the home directory with a leading ~ for readability.
        param([string]$Path)
        $homeDir = ConvertTo-AgexComparable $HOME
        $p = ConvertTo-AgexComparable $Path
        if ([string]::Equals($p, $homeDir, $ctx.PathComparison)) {
            return '~'
        }
        if (Test-AgexPathUnder $p $homeDir) {
            return '~' + $p.Substring($homeDir.Length)
        }
        return $p
    }

    function Format-AgexCommandPath {
        # A path ready to paste into PowerShell.
        param([string]$Path)
        $homeDir = ConvertTo-AgexComparable $HOME
        $p = ConvertTo-AgexComparable $Path
        if (Test-AgexPathUnder $p $homeDir) {
            $rest = $p.Substring($homeDir.Length)
            if ($rest -notmatch '[\$`"]') {
                return '"$HOME' + $rest + '"'
            }
        }
        return "'" + $p.Replace("'", "''") + "'"
    }

    function Get-AgexEntry {
        # The file, directory, or link at $Path, including broken links, or $null.
        param([string]$Path)
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        $leaf = [System.IO.Path]::GetFileName($Path)
        if (-not $parent -or -not $leaf -or -not [System.IO.Directory]::Exists($parent)) {
            return $null
        }
        $info = New-Object System.IO.DirectoryInfo -ArgumentList $parent
        foreach ($entry in $info.GetFileSystemInfos($leaf)) {
            if ([string]::Equals($entry.Name, $leaf, $ctx.PathComparison)) {
                return $entry
            }
        }
        return $null
    }

    function Test-AgexIsLink {
        param($Entry)
        if ($null -eq $Entry) {
            return $false
        }
        return ([string]$Entry.LinkType -eq 'SymbolicLink')
    }

    function Get-AgexLinkTarget {
        param($Entry)
        $target = @($Entry.Target) | Select-Object -First 1
        if ($null -eq $target) {
            return ''
        }
        return [string]$target
    }

    function Test-AgexCheckout {
        param([string]$Path)
        if (-not $Path) {
            return $false
        }
        $agent = Join-AgexPath $Path @('.claude', 'agents', 'orchestrator.md')
        $plugin = Join-AgexPath $Path @('.claude-plugin', 'plugin.json')
        return ((Test-Path -LiteralPath $agent -PathType Leaf) -and (Test-Path -LiteralPath $plugin -PathType Leaf))
    }

    function Get-AgexHash {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return ''
        }
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    function Get-AgexFrontmatterName {
        param([string]$Path)
        try {
            $lines = [System.IO.File]::ReadAllLines($Path)
        }
        catch {
            return ''
        }
        if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
            return ''
        }
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line.Trim() -eq '---') {
                return ''
            }
            if ($line -cmatch '^name[ \t]*:[ \t]*(.*?)[ \t]*$') {
                $value = $Matches[1]
                if ($value.Length -ge 2) {
                    $first = $value.Substring(0, 1)
                    $last = $value.Substring($value.Length - 1, 1)
                    if (($first -eq '"' -or $first -eq "'") -and $first -eq $last) {
                        $value = $value.Substring(1, $value.Length - 2)
                    }
                }
                return $value
            }
        }
        return ''
    }

    function Get-AgexPluginVersion {
        $file = Join-AgexPath $ctx.Src @('.claude-plugin', 'plugin.json')
        try {
            $json = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json
            if ($json.version) {
                return [string]$json.version
            }
        }
        catch {
            return ''
        }
        return ''
    }

    function Invoke-AgexGit {
        # Run git and capture its exit code, standard output (Output), and
        # standard error (ErrorText) separately, so warnings on stderr never
        # look like command output, and without letting stderr become a
        # terminating error under $ErrorActionPreference = 'Stop'.
        param([string[]]$Arguments)
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $stdout = New-Object 'System.Collections.Generic.List[string]'
        $stderr = New-Object 'System.Collections.Generic.List[string]'
        & git @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $stderr.Add([string]$_)
            }
            else {
                $stdout.Add([string]$_)
            }
        }
        $code = $LASTEXITCODE
        return New-Object PSObject -Property @{
            ExitCode  = $code
            Output    = ($stdout -join "`n").Trim()
            ErrorText = ($stderr -join "`n").Trim()
        }
    }

    function Write-AgexGitMessages {
        # Show what a failed git command printed.
        param($Result)
        foreach ($text in @($Result.ErrorText, $Result.Output)) {
            if ($text) {
                Write-Host $text
            }
        }
    }

    function Test-AgexGitAvailable {
        return ($null -ne (Get-Command git -CommandType Application -ErrorAction SilentlyContinue))
    }

    # ------------------------------------------------------------------------
    # Manifest
    # ------------------------------------------------------------------------

    function Read-AgexManifest {
        $ctx.ManifestFound = $false
        $ctx.ManifestSource = ''
        $ctx.ManifestLinks = New-Object 'System.Collections.Generic.List[string]'
        $ctx.ManifestCopies = @{}
        if (-not (Test-Path -LiteralPath $ctx.Manifest -PathType Leaf)) {
            return
        }
        $ctx.ManifestFound = $true
        foreach ($line in [System.IO.File]::ReadAllLines($ctx.Manifest)) {
            if (-not $line -or $line.StartsWith('#')) {
                continue
            }
            if ($line.StartsWith('source=')) {
                $ctx.ManifestSource = $line.Substring(7)
                continue
            }
            if ($line.StartsWith('copy:')) {
                # copy:<path><TAB><sha256 of the content AGEX wrote>
                $rest = $line.Substring(5)
                $hash = ''
                $tab = $rest.IndexOf("`t")
                if ($tab -ge 0) {
                    $hash = $rest.Substring($tab + 1).Trim()
                    $rest = $rest.Substring(0, $tab)
                }
                if ($rest -and [System.IO.Path]::IsPathRooted($rest)) {
                    $ctx.ManifestCopies[(ConvertTo-AgexComparable $rest)] = @{ Path = $rest; Hash = $hash }
                }
                continue
            }
            if ([System.IO.Path]::IsPathRooted($line)) {
                $ctx.ManifestLinks.Add($line)
            }
        }
    }

    function Get-AgexManifestCopy {
        param([string]$Path)
        $key = ConvertTo-AgexComparable $Path
        if ($ctx.ManifestCopies.ContainsKey($key)) {
            return $ctx.ManifestCopies[$key]
        }
        return $null
    }

    function Write-AgexManifest {
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add('# AGEX install manifest')
        $lines.Add('source=' + $ctx.Src)
        foreach ($item in $ctx.Installed) {
            $lines.Add($item)
        }
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllLines($ctx.Manifest, $lines.ToArray(), $encoding)
    }

    function Add-AgexInstalled {
        param([string]$Dest, [string]$Mode)
        if ($Mode -eq 'copy') {
            $ctx.Installed.Add('copy:' + $Dest + "`t" + (Get-AgexHash $Dest))
        }
        else {
            $ctx.Installed.Add($Dest)
        }
    }

    function Test-AgexOwnedLink {
        # True when a link points into the current checkout, or is recorded in
        # the manifest and points into the checkout the manifest was written for.
        param([string]$Dest, [string]$Target)
        if (Test-AgexPathUnder $Target (Join-AgexPath $ctx.Src @('.claude'))) {
            return $true
        }
        if ($ctx.ManifestSource -and (Test-AgexListHas $ctx.ManifestLinks $Dest) -and (Test-AgexPathUnder $Target (Join-AgexPath $ctx.ManifestSource @('.claude')))) {
            return $true
        }
        return $false
    }

    function Test-AgexPristineCopy {
        # True when a copy AGEX made still has the content AGEX wrote, or the
        # content of the matching file in one of the given checkouts.
        param([string]$Path, $Copy, [string[]]$Sources)
        $current = Get-AgexHash $Path
        if (-not $current) {
            return $false
        }
        if ($Copy -and $Copy.Hash -and $current -eq $Copy.Hash) {
            return $true
        }
        $kind = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($Path))
        $name = [System.IO.Path]::GetFileName($Path)
        foreach ($s in $Sources) {
            if (-not $s) {
                continue
            }
            $sourceFile = Join-AgexPath $s @('.claude', $kind, $name)
            if ($current -eq (Get-AgexHash $sourceFile)) {
                return $true
            }
        }
        return $false
    }

    # ------------------------------------------------------------------------
    # Source checkout
    # ------------------------------------------------------------------------

    function Get-AgexScriptCheckout {
        if (-not $ctx.ScriptPath) {
            return ''
        }
        $scriptDir = [System.IO.Path]::GetDirectoryName($ctx.ScriptPath)
        if ($scriptDir -and (Test-AgexCheckout $scriptDir)) {
            return (Resolve-AgexFullPath $scriptDir)
        }
        return ''
    }

    function Update-AgexCheckout {
        param([string]$Path)
        $shown = Format-AgexPath $Path
        if ($ctx.NoUpdate) {
            Write-AgexNote 'Not updating the checkout (-NoUpdate).'
            return
        }
        if (-not (Test-AgexGitAvailable)) {
            Write-AgexWarn 'git is not installed, so the checkout was not updated. Continuing with the files as they are.'
            return
        }
        $prefix = Invoke-AgexGit @('-C', $Path, 'rev-parse', '--show-prefix')
        if ($prefix.ExitCode -ne 0) {
            Write-AgexNote "$shown is not a git clone; using it as it is."
            return
        }
        if ($prefix.Output) {
            Write-AgexNote "$shown is inside another git repository; not updating it."
            return
        }
        $before = ''
        $head = Invoke-AgexGit @('-C', $Path, 'rev-parse', '--short', 'HEAD')
        if ($head.ExitCode -eq 0) {
            $before = $head.Output
        }
        $current = 'the current version'
        if ($before) {
            $current = "the current version ($before)"
        }
        $status = Invoke-AgexGit @('-C', $Path, 'status', '--porcelain', '--untracked-files=no')
        if ($status.ExitCode -eq 0 -and $status.Output) {
            Write-AgexWarn "$shown has uncommitted changes, so it was not updated. Continuing with $current. Commit or stash your changes to take updates."
            return
        }
        $upstream = Invoke-AgexGit @('-C', $Path, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
        if ($upstream.ExitCode -ne 0) {
            Write-AgexWarn "The current branch of $shown has no upstream branch, so it was not updated. Continuing with $current."
            return
        }
        Write-AgexInfo "Updating $shown with git pull --ff-only"
        $pull = Invoke-AgexGit @('-C', $Path, 'pull', '--ff-only', '--quiet')
        if ($pull.ExitCode -ne 0) {
            Write-AgexGitMessages $pull
            Write-AgexWarn "git pull failed (offline, or the local branch has diverged). Continuing with $current."
            return
        }
        $after = ''
        $head = Invoke-AgexGit @('-C', $Path, 'rev-parse', '--short', 'HEAD')
        if ($head.ExitCode -eq 0) {
            $after = $head.Output
        }
        if ($before -eq $after) {
            if ($after) {
                Write-AgexOk "Already up to date ($after)."
            }
            else {
                Write-AgexOk 'Already up to date.'
            }
        }
        else {
            if (-not $before) {
                $before = 'unknown'
            }
            if (-not $after) {
                $after = 'unknown'
            }
            Write-AgexOk "Updated $before -> $after."
        }
    }

    function New-AgexClone {
        param([string]$Path)
        if (-not (Test-AgexGitAvailable)) {
            throw 'git is required to download AGEX but was not found. Install Git for Windows from https://git-scm.com/download/win and run this installer again.'
        }
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        if ($parent -and -not [System.IO.Directory]::Exists($parent)) {
            $null = [System.IO.Directory]::CreateDirectory($parent)
        }
        Write-AgexInfo ('Cloning ' + $ctx.Repo + ' into ' + (Format-AgexPath $Path))
        $clone = Invoke-AgexGit @('clone', '--depth', '1', '--quiet', '--', $ctx.Repo, $Path)
        if ($clone.ExitCode -ne 0) {
            Write-AgexGitMessages $clone
            throw ('Could not clone ' + $ctx.Repo + '. Check your network connection and the AGEX_REPO value, then run the installer again.')
        }
        Write-AgexOk ('Cloned ' + (Format-AgexPath $Path) + '.')
    }

    function Use-AgexCheckoutDir {
        # Use (and, when needed, clone or update) the checkout at $Path.
        param([string]$Path, [string]$Label)
        if ([System.IO.Directory]::Exists($Path)) {
            if (Test-AgexCheckout $Path) {
                $ctx.Src = $Path
                Write-AgexOk ('Using the AGEX checkout at ' + (Format-AgexPath $Path) + ' (' + $Label + ').')
                Update-AgexCheckout $Path
                return
            }
            $children = @((New-Object System.IO.DirectoryInfo -ArgumentList $Path).GetFileSystemInfos())
            if ($children.Count -gt 0) {
                throw ($Path + ' exists but is not an AGEX checkout (no .claude\agents\orchestrator.md or .claude-plugin\plugin.json). Nothing was changed. Move it aside, or choose another location with -Dir <path> or AGEX_HOME.')
            }
            New-AgexClone $Path
        }
        elseif ($null -ne (Get-AgexEntry $Path)) {
            throw ($Path + ' exists and is not a directory. Nothing was changed. Choose another location with -Dir <path> or AGEX_HOME.')
        }
        else {
            New-AgexClone $Path
        }
        $ctx.Src = $Path
        if (-not (Test-AgexCheckout $Path)) {
            throw ('The repository cloned into ' + $Path + ' does not look like AGEX (no .claude\agents\orchestrator.md). Check AGEX_REPO (' + $ctx.Repo + '), remove ' + $Path + ', and try again.')
        }
    }

    function Resolve-AgexSource {
        if ($ctx.DirGiven) {
            Use-AgexCheckoutDir (Resolve-AgexFullPath $ctx.Dir) 'from -Dir'
            return
        }
        $self = Get-AgexScriptCheckout
        if ($self) {
            $ctx.Src = $self
            Write-AgexOk ('Using the AGEX checkout at ' + (Format-AgexPath $self) + ' (where this script lives).')
            Update-AgexCheckout $self
            return
        }
        Use-AgexCheckoutDir $ctx.AgexHome 'AGEX_HOME'
    }

    function Resolve-AgexSourceQuietly {
        # Best-effort source lookup for -Uninstall: never clones or updates.
        if ($ctx.DirGiven) {
            return (Resolve-AgexFullPath $ctx.Dir)
        }
        $self = Get-AgexScriptCheckout
        if ($self) {
            return $self
        }
        return $ctx.AgexHome
    }

    # ------------------------------------------------------------------------
    # Install
    # ------------------------------------------------------------------------

    function New-AgexLinkOrCopy {
        # Create a symbolic link at $Dest (which must be free); fall back to a
        # copy when symbolic links are not permitted. Returns 'link' or 'copy'.
        param([string]$Source, [string]$Dest)
        if (-not $ctx.UseCopies) {
            try {
                $null = New-Item -ItemType SymbolicLink -Path $Dest -Value $Source -ErrorAction Stop
                return 'link'
            }
            catch {
                $ctx.UseCopies = $true
                $leftover = Get-AgexEntry $Dest
                if ($null -ne $leftover) {
                    $leftover.Delete()
                }
                Write-AgexWarn ('Could not create a symbolic link: ' + $_.Exception.Message)
                Write-AgexWarn 'Copying the files instead. Symbolic links need Developer Mode or an administrator PowerShell. With copies, run this installer again after every AGEX update so the copies are refreshed.'
            }
        }
        Copy-Item -LiteralPath $Source -Destination $Dest -Force
        return 'copy'
    }

    function Backup-AgexItem {
        param($Entry, [string]$Kind)
        if (-not $ctx.BackupDir) {
            $stamp = [System.DateTime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
            $candidate = Join-AgexPath $ctx.ClaudeHome @('.agex-backup', $stamp)
            if ($null -ne (Get-AgexEntry $candidate)) {
                $candidate = $candidate + '-' + $PID
            }
            $ctx.BackupDir = $candidate
        }
        $kindDir = Join-AgexPath $ctx.BackupDir @($Kind)
        $null = [System.IO.Directory]::CreateDirectory($kindDir)
        $original = $Entry.FullName
        $target = Join-AgexPath $kindDir @($Entry.Name)
        $Entry.MoveTo($target)
        $ctx.BackedUp += 1
        Write-AgexNote ('Backed up ' + (Format-AgexPath $original) + ' to ' + (Format-AgexPath $target))
    }

    function Install-AgexFile {
        param([string]$Source, [string]$Kind)
        $name = [System.IO.Path]::GetFileName($Source)
        $dest = Join-AgexPath $ctx.ClaudeHome @($Kind, $name)
        $label = $Kind + '\' + $name
        $ctx.AgexDests.Add($dest)
        $entry = Get-AgexEntry $dest

        if (Test-AgexIsLink $entry) {
            $target = Get-AgexLinkTarget $entry
            if (Test-AgexSamePath $target $Source) {
                $ctx.Unchanged += 1
                $ctx.Installed.Add($dest)
                return
            }
            if (Test-AgexOwnedLink $dest $target) {
                $entry.Delete()
                $mode = New-AgexLinkOrCopy $Source $dest
                Add-AgexInstalled $dest $mode
                $ctx.Updated += 1
                Write-AgexOk ('Updated ' + $label)
                return
            }
        }
        elseif ($null -ne $entry -and $entry -is [System.IO.FileInfo]) {
            $copy = Get-AgexManifestCopy $dest
            if ($null -ne $copy) {
                $sources = @($ctx.Src, $ctx.ManifestSource)
                if (Test-AgexPristineCopy $dest $copy $sources) {
                    $sameContent = ((Get-AgexHash $dest) -eq (Get-AgexHash $Source))
                    $entry.Delete()
                    $mode = New-AgexLinkOrCopy $Source $dest
                    Add-AgexInstalled $dest $mode
                    if ($mode -eq 'copy' -and $sameContent) {
                        $ctx.Unchanged += 1
                    }
                    else {
                        $ctx.Updated += 1
                        Write-AgexOk ('Updated ' + $label)
                    }
                    return
                }
                Write-AgexWarn ((Format-AgexPath $dest) + ' was changed after AGEX copied it.')
            }
        }

        if ($null -ne $entry) {
            if ($ctx.Force) {
                Backup-AgexItem $entry $Kind
                $mode = New-AgexLinkOrCopy $Source $dest
                Add-AgexInstalled $dest $mode
                $ctx.Linked += 1
                Write-AgexOk ('Installed ' + $label + ' (replaced the previous file)')
                return
            }
            $ctx.Skipped += 1
            Write-AgexWarn ('Skipped ' + (Format-AgexPath $dest) + ': a file that AGEX did not create is already there.')
            return
        }

        $mode = New-AgexLinkOrCopy $Source $dest
        Add-AgexInstalled $dest $mode
        $ctx.Linked += 1
        if ($mode -eq 'copy') {
            Write-AgexOk ('Copied ' + $label)
        }
        else {
            Write-AgexOk ('Linked ' + $label)
        }
    }

    function Get-AgexSourceFiles {
        param([string]$Kind)
        $kindDir = Join-AgexPath $ctx.Src @('.claude', $Kind)
        if (-not [System.IO.Directory]::Exists($kindDir)) {
            return @()
        }
        return @(Get-ChildItem -LiteralPath $kindDir -Filter '*.md' -File | Where-Object { $_.Extension -eq '.md' } | Sort-Object Name)
    }

    function Install-AgexKind {
        param([string]$Kind)
        $before = $ctx.Linked + $ctx.Updated + $ctx.Unchanged
        $files = @(Get-AgexSourceFiles $Kind)
        foreach ($file in $files) {
            Install-AgexFile $file.FullName $Kind
        }
        $done = ($ctx.Linked + $ctx.Updated + $ctx.Unchanged) - $before
        $ctx.Counts[$Kind] = @{ Done = $done; Total = $files.Count }
    }

    function Remove-AgexStale {
        # Remove links and unmodified copies from a previous install whose
        # source file no longer exists (for example an agent removed upstream).
        $agentsDir = Join-AgexPath $ctx.ClaudeHome @('agents')
        $commandsDir = Join-AgexPath $ctx.ClaudeHome @('commands')
        $previous = New-Object 'System.Collections.Generic.List[string]'
        foreach ($link in $ctx.ManifestLinks) {
            $previous.Add($link)
        }
        foreach ($copy in $ctx.ManifestCopies.Values) {
            $previous.Add($copy.Path)
        }
        foreach ($path in $previous) {
            if (Test-AgexListHas $ctx.AgexDests $path) {
                continue
            }
            if (-not ((Test-AgexPathUnder $path $agentsDir) -or (Test-AgexPathUnder $path $commandsDir))) {
                continue
            }
            $entry = Get-AgexEntry $path
            if ($null -eq $entry) {
                continue
            }
            $remove = $false
            if (Test-AgexIsLink $entry) {
                $remove = Test-AgexOwnedLink $path (Get-AgexLinkTarget $entry)
            }
            elseif ($entry -is [System.IO.FileInfo]) {
                $copy = Get-AgexManifestCopy $path
                if ($null -ne $copy) {
                    $remove = Test-AgexPristineCopy $path $copy @($ctx.ManifestSource)
                }
            }
            if ($remove) {
                $entry.Delete()
                $ctx.Pruned += 1
                Write-AgexNote ('Removed stale ' + (Format-AgexPath $path))
            }
        }
    }

    function Test-AgexCollisions {
        $names = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in @(Get-AgexSourceFiles 'agents')) {
            $n = Get-AgexFrontmatterName $file.FullName
            if (-not $n) {
                $n = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            }
            $names.Add($n)
        }
        $agentsDir = Join-AgexPath $ctx.ClaudeHome @('agents')
        $found = 0
        $userFiles = @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.md' })
        foreach ($file in $userFiles) {
            if (Test-AgexListHas $ctx.AgexDests $file.FullName) {
                continue
            }
            $n = Get-AgexFrontmatterName $file.FullName
            if ($n -and $names.Contains($n)) {
                $found += 1
                Write-AgexWarn ((Format-AgexPath $file.FullName) + ' declares "name: ' + $n + '", the same name as the AGEX ' + $n + ' agent. Two user agents with one name conflict and only one of them is used. Rename one of them, or use the plugin install, which scopes AGEX agents as agex:' + $n + '.')
            }
        }
        return $found
    }

    function Show-AgexSummary {
        $version = Get-AgexPluginVersion
        $title = 'AGEX'
        if ($version) {
            $title = 'AGEX ' + $version
        }
        Write-Host ''
        if ($ctx.Skipped -gt 0) {
            Write-AgexText ('==> ' + $title + ' is installed, but ' + $ctx.Skipped + ' file(s) were skipped') 'Yellow'
        }
        else {
            Write-AgexText ('==> ' + $title + ' is installed') 'Green'
        }
        $agents = $ctx.Counts['agents']
        $commands = $ctx.Counts['commands']
        $mode = 'symbolic links'
        if ($ctx.UseCopies) {
            $mode = 'copies (symbolic links are not permitted for this account)'
        }
        Write-Host ('    Checkout   ' + (Format-AgexPath $ctx.Src))
        Write-Host ('    Agents     ' + (Format-AgexPath (Join-AgexPath $ctx.ClaudeHome @('agents'))) + ' (' + $agents.Done + ' of ' + $agents.Total + ' AGEX agents)')
        Write-Host ('    Commands   ' + (Format-AgexPath (Join-AgexPath $ctx.ClaudeHome @('commands'))) + ' (' + $commands.Done + ' of ' + $commands.Total + ' AGEX commands)')
        Write-Host ('    Installed  ' + $mode)
        $counts = '    Files      ' + $ctx.Linked + ' new, ' + $ctx.Updated + ' updated, ' + $ctx.Unchanged + ' unchanged, ' + $ctx.Skipped + ' skipped, ' + $ctx.BackedUp + ' backed up'
        if ($ctx.Pruned -gt 0) {
            $counts = $counts + ', ' + $ctx.Pruned + ' stale removed'
        }
        Write-Host $counts
        if ($ctx.BackedUp -gt 0) {
            Write-Host ('    Backups    ' + (Format-AgexPath $ctx.BackupDir) + ' (restored by -Uninstall)')
        }

        if ($ctx.Skipped -gt 0) {
            Write-Host ''
            Write-AgexText 'Skipped files were left untouched. Either:' 'Yellow'
            Write-Host ('  - re-run with -Force to move them to ' + (Format-AgexPath (Join-AgexPath $ctx.ClaudeHome @('.agex-backup'))) + '\<timestamp>\ and install the AGEX versions, or')
            Write-Host '  - install AGEX as a plugin instead; its agents are scoped as agex:<name> and never collide:'
            Write-Host '      claude plugin marketplace add saksham-eng560/agex'
            Write-Host '      claude plugin install agex@agex-marketplace'
        }

        $checkout = Format-AgexCommandPath $ctx.Src
        $installer = Format-AgexCommandPath (Join-AgexPath $ctx.Src @('install.ps1'))
        $docs = Join-AgexPath $ctx.Src @('docs', 'CUSTOMIZATION.md')
        if (Test-Path -LiteralPath $docs -PathType Leaf) {
            $docs = Format-AgexPath $docs
        }
        else {
            $docs = 'https://github.com/saksham-eng560/agex/blob/main/docs/CUSTOMIZATION.md'
        }

        Write-Host ''
        Write-Host 'Next steps'
        Write-Host '  Restart Claude Code (or start a new session) so it loads the new agents and commands.'
        Write-Host '  Then, inside any project:'
        Write-Host ''
        $examples = @(
            @('/agex Build a REST API with authentication', 'full multi-agent run'),
            @('/agex-plan Add OAuth login to the web app', 'plan only, nothing is executed'),
            @('/agex-review', 'review staged changes or the last commit'),
            @('/agex-secure', 'secrets and vulnerability audit'),
            @('/agex-status', 'agents, session log, project context'),
            @('claude --agent orchestrator', 'run a whole session as the orchestrator')
        )
        foreach ($example in $examples) {
            Write-Host '    ' -NoNewline
            Write-AgexText ($example[0].PadRight(45)) 'Cyan' -NoNewline
            Write-Host $example[1]
        }
        Write-Host ''
        if ($ctx.UseCopies) {
            Write-Host ('  Update:     git -C ' + $checkout + ' pull, then run this installer again to refresh the copies')
        }
        else {
            Write-Host ('  Update:     re-run this installer, or: git -C ' + $checkout + ' pull')
        }
        # "irm ... | iex" works under any execution policy, but running the
        # checkout's install.ps1 later does not: under Restricted or AllSigned
        # (the Windows PowerShell default is Restricted) suggest -ExecutionPolicy
        # Bypass, which relaxes the policy for that one process only.
        $policy = ''
        try {
            $policy = [string](Get-ExecutionPolicy)
        }
        catch {
            $policy = ''
        }
        if (@('Restricted', 'AllSigned', 'Undefined') -contains $policy) {
            $exe = 'powershell'
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $exe = 'pwsh'
            }
            Write-Host ('  Uninstall:  ' + $exe + ' -ExecutionPolicy Bypass -File ' + $installer + ' -Uninstall')
        }
        else {
            Write-Host ('  Uninstall:  & ' + $installer + ' -Uninstall')
        }
        Write-Host ('  Logging:    session-log hooks are not installed by this script; see ' + $docs)
    }

    function Invoke-AgexInstall {
        Show-AgexBanner

        Write-AgexStep 'Locating AGEX'
        Resolve-AgexSource

        Write-AgexStep ('Installing into ' + (Format-AgexPath $ctx.ClaudeHome))
        $null = [System.IO.Directory]::CreateDirectory((Join-AgexPath $ctx.ClaudeHome @('agents')))
        $null = [System.IO.Directory]::CreateDirectory((Join-AgexPath $ctx.ClaudeHome @('commands')))

        if (-not (Get-AgexEnvValue 'CLAUDE_HOME') -and (Get-AgexEnvValue 'CLAUDE_CONFIG_DIR')) {
            Write-AgexNote ('CLAUDE_CONFIG_DIR is set to ' + (Get-AgexEnvValue 'CLAUDE_CONFIG_DIR') + '. If Claude Code reads its configuration from there, run the installer again with CLAUDE_HOME set to that directory.')
        }

        Read-AgexManifest
        if ($ctx.ManifestFound) {
            if ($ctx.ManifestSource -and -not (Test-AgexSamePath $ctx.ManifestSource $ctx.Src)) {
                Write-AgexNote ('AGEX is already installed from ' + (Format-AgexPath $ctx.ManifestSource) + '; switching to ' + (Format-AgexPath $ctx.Src) + '.')
            }
            else {
                Write-AgexNote 'AGEX is already installed here; refreshing the existing files.'
            }
        }

        Install-AgexKind 'agents'
        Install-AgexKind 'commands'
        if ($ctx.Unchanged -gt 0) {
            Write-AgexNote ([string]$ctx.Unchanged + ' file(s) were already up to date.')
        }
        Remove-AgexStale
        Write-AgexManifest

        Write-AgexStep 'Checking for conflicts'
        $collisions = Test-AgexCollisions
        if ($collisions -eq 0) {
            Write-AgexOk ('No other agents in ' + (Format-AgexPath (Join-AgexPath $ctx.ClaudeHome @('agents'))) + ' use an AGEX agent name.')
        }
        $claude = @(Get-Command claude -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($null -ne $claude) {
            Write-AgexOk ('Found the Claude Code CLI at ' + $claude.Source + '.')
        }
        else {
            Write-AgexWarn 'The claude command is not on your PATH. Install Claude Code v2.1 or later to use AGEX.'
        }

        Show-AgexSummary
    }

    # ------------------------------------------------------------------------
    # Uninstall
    # ------------------------------------------------------------------------

    function Remove-AgexEmptyDir {
        # Best effort, like rmdir: a directory that cannot be removed stays.
        param([string]$Path)
        try {
            if ([System.IO.Directory]::Exists($Path) -and @([System.IO.Directory]::GetFileSystemEntries($Path)).Count -eq 0) {
                [System.IO.Directory]::Delete($Path)
            }
        }
        catch {
            Write-Verbose ('Could not remove the empty directory ' + $Path + ': ' + $_.Exception.Message)
        }
    }

    function Restore-AgexBackups {
        # Restore files that -Force backed up, newest backup first, wherever the
        # original location is free again.
        $root = Join-AgexPath $ctx.ClaudeHome @('.agex-backup')
        if (-not [System.IO.Directory]::Exists($root)) {
            return
        }
        $rootInfo = New-Object System.IO.DirectoryInfo -ArgumentList $root
        $backups = @($rootInfo.GetDirectories() | Sort-Object Name -Descending)
        foreach ($backup in $backups) {
            foreach ($kind in @('agents', 'commands')) {
                $kindDir = Join-AgexPath $backup.FullName @($kind)
                if (-not [System.IO.Directory]::Exists($kindDir)) {
                    continue
                }
                $kindInfo = New-Object System.IO.DirectoryInfo -ArgumentList $kindDir
                foreach ($item in @($kindInfo.GetFileSystemInfos())) {
                    $from = $item.FullName
                    $dest = Join-AgexPath $ctx.ClaudeHome @($kind, $item.Name)
                    if ($null -ne (Get-AgexEntry $dest)) {
                        $ctx.Kept += 1
                        Write-AgexWarn ('Kept the backup ' + (Format-AgexPath $from) + ': ' + (Format-AgexPath $dest) + ' is in use.')
                        continue
                    }
                    try {
                        $null = [System.IO.Directory]::CreateDirectory((Join-AgexPath $ctx.ClaudeHome @($kind)))
                        $item.MoveTo($dest)
                        $ctx.Restored += 1
                        Write-AgexOk ('Restored ' + (Format-AgexPath $dest) + ' from ' + (Format-AgexPath $backup.FullName))
                    }
                    catch {
                        $ctx.Kept += 1
                        Write-AgexWarn ('Could not restore ' + (Format-AgexPath $from) + ': ' + $_.Exception.Message)
                    }
                }
                Remove-AgexEmptyDir $kindDir
            }
            Remove-AgexEmptyDir $backup.FullName
        }
        Remove-AgexEmptyDir $root
    }

    function Invoke-AgexUninstall {
        Show-AgexBanner
        Write-AgexStep ('Uninstalling AGEX from ' + (Format-AgexPath $ctx.ClaudeHome))

        if (-not [System.IO.Directory]::Exists($ctx.ClaudeHome)) {
            Write-AgexOk ((Format-AgexPath $ctx.ClaudeHome) + ' does not exist; nothing to uninstall.')
            return
        }

        Read-AgexManifest
        $ctx.Src = Resolve-AgexSourceQuietly
        if ($ctx.ManifestFound) {
            $from = ''
            if ($ctx.ManifestSource) {
                $from = ' (installed from ' + (Format-AgexPath $ctx.ManifestSource) + ')'
            }
            Write-AgexNote ('Found the install manifest ' + (Format-AgexPath $ctx.Manifest) + $from + '.')
        }
        else {
            Write-AgexNote ('No install manifest found; looking for links into ' + (Format-AgexPath $ctx.Src) + '.')
        }

        $sources = New-Object 'System.Collections.Generic.List[string]'
        if ($ctx.Src) {
            $sources.Add($ctx.Src)
        }
        if ($ctx.ManifestSource -and -not (Test-AgexListHas $sources $ctx.ManifestSource)) {
            $sources.Add($ctx.ManifestSource)
        }
        $agentsDir = Join-AgexPath $ctx.ClaudeHome @('agents')
        $commandsDir = Join-AgexPath $ctx.ClaudeHome @('commands')

        # Manifest entries first, then any other link that points into a checkout.
        $candidates = New-Object 'System.Collections.Generic.List[string]'
        $recorded = New-Object 'System.Collections.Generic.List[string]'
        foreach ($link in $ctx.ManifestLinks) {
            $recorded.Add($link)
        }
        foreach ($copy in $ctx.ManifestCopies.Values) {
            $recorded.Add($copy.Path)
        }
        foreach ($path in $recorded) {
            if (((Test-AgexPathUnder $path $agentsDir) -or (Test-AgexPathUnder $path $commandsDir)) -and -not (Test-AgexListHas $candidates $path)) {
                $candidates.Add($path)
            }
        }
        foreach ($kindDir in @($agentsDir, $commandsDir)) {
            if (-not [System.IO.Directory]::Exists($kindDir)) {
                continue
            }
            $kindInfo = New-Object System.IO.DirectoryInfo -ArgumentList $kindDir
            foreach ($entry in @($kindInfo.GetFileSystemInfos())) {
                if (-not (Test-AgexIsLink $entry)) {
                    continue
                }
                if (Test-AgexListHas $candidates $entry.FullName) {
                    continue
                }
                $target = Get-AgexLinkTarget $entry
                foreach ($s in $sources) {
                    if (Test-AgexPathUnder $target (Join-AgexPath $s @('.claude'))) {
                        $candidates.Add($entry.FullName)
                        break
                    }
                }
            }
        }

        $removed = 0
        $left = 0
        foreach ($path in $candidates) {
            $entry = Get-AgexEntry $path
            if ($null -eq $entry) {
                continue
            }
            if (Test-AgexIsLink $entry) {
                $target = Get-AgexLinkTarget $entry
                $owned = $false
                foreach ($s in $sources) {
                    if (Test-AgexPathUnder $target (Join-AgexPath $s @('.claude'))) {
                        $owned = $true
                        break
                    }
                }
                if ($owned) {
                    $entry.Delete()
                    $removed += 1
                    Write-AgexOk ('Removed ' + (Format-AgexPath $path))
                }
                else {
                    $left += 1
                    Write-AgexWarn ('Left ' + (Format-AgexPath $path) + ' in place: it now points to ' + $target + ', not into an AGEX checkout.')
                }
                continue
            }
            $copy = Get-AgexManifestCopy $path
            if ($null -ne $copy -and $entry -is [System.IO.FileInfo]) {
                if (Test-AgexPristineCopy $path $copy ($sources.ToArray())) {
                    $entry.Delete()
                    $removed += 1
                    Write-AgexOk ('Removed ' + (Format-AgexPath $path))
                }
                else {
                    $left += 1
                    Write-AgexWarn ('Left ' + (Format-AgexPath $path) + ' in place: it was changed after AGEX copied it.')
                }
                continue
            }
            $left += 1
            Write-AgexWarn ('Left ' + (Format-AgexPath $path) + ' in place: it is not a link or copy that AGEX created.')
        }

        Restore-AgexBackups

        if ($ctx.ManifestFound) {
            [System.IO.File]::Delete($ctx.Manifest)
        }

        if (-not $ctx.ManifestFound -and $removed -eq 0 -and $left -eq 0 -and $ctx.Restored -eq 0 -and $ctx.Kept -eq 0) {
            Write-AgexOk ('Nothing to uninstall: no AGEX files were found in ' + (Format-AgexPath $ctx.ClaudeHome) + '.')
            return
        }

        Write-Host ''
        Write-AgexText '==> AGEX was uninstalled' 'Green'
        Write-Host ('    Removed    ' + $removed + ' file(s)')
        Write-Host ('    Restored   ' + $ctx.Restored + ' backed-up file(s)')
        if ($left -gt 0 -or $ctx.Kept -gt 0) {
            Write-Host ('    Left       ' + $left + ' file(s) AGEX did not create or that were changed, ' + $ctx.Kept + ' backup(s) whose original location is in use')
        }

        $checkout = $ctx.ManifestSource
        if (-not $checkout) {
            $checkout = $ctx.Src
        }
        if ($checkout -and [System.IO.Directory]::Exists($checkout) -and (Test-AgexCheckout $checkout)) {
            Write-Host ''
            if (Test-AgexSamePath $checkout $ctx.AgexHome) {
                Write-Host ('The AGEX checkout at ' + (Format-AgexPath $checkout) + ' was left in place. To delete it as well, run:')
                Write-Host ('    Remove-Item -Recurse -Force ' + (Format-AgexCommandPath $checkout))
            }
            else {
                Write-Host ('The AGEX checkout at ' + (Format-AgexPath $checkout) + ' was left in place.')
            }
        }
        Write-Host ''
        Write-Host 'Restart Claude Code (or start a new session) to stop loading the AGEX agents and commands.'
    }

    # ------------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------------

    $colorEnabled = -not (Get-AgexEnvValue 'NO_COLOR')
    try {
        if ([System.Console]::IsOutputRedirected) {
            $colorEnabled = $false
        }
    }
    catch {
        Write-Verbose 'Could not tell whether output is redirected; keeping colors on.'
    }

    $pathComparison = [System.StringComparison]::Ordinal
    if ($env:OS -eq 'Windows_NT') {
        $pathComparison = [System.StringComparison]::OrdinalIgnoreCase
    }

    $ctx = @{
        Color          = $colorEnabled
        PathComparison = $pathComparison
        Uninstall      = ($Uninstall -or (Test-AgexEnvFlag 'AGEX_UNINSTALL'))
        Force          = ($Force -or (Test-AgexEnvFlag 'AGEX_FORCE'))
        NoUpdate       = ($NoUpdate -or (Test-AgexEnvFlag 'AGEX_NO_UPDATE'))
        DirGiven       = $DirGiven
        Dir            = $Dir
        ScriptPath     = $ScriptPath
        Repo           = ''
        AgexHome       = ''
        ClaudeHome     = ''
        Manifest       = ''
        Src            = ''
        ManifestFound  = $false
        ManifestSource = ''
        ManifestLinks  = (New-Object 'System.Collections.Generic.List[string]')
        ManifestCopies = @{}
        Installed      = (New-Object 'System.Collections.Generic.List[string]')
        AgexDests      = (New-Object 'System.Collections.Generic.List[string]')
        Counts         = @{ agents = @{ Done = 0; Total = 0 }; commands = @{ Done = 0; Total = 0 } }
        UseCopies      = $false
        BackupDir      = ''
        Linked         = 0
        Updated        = 0
        Unchanged      = 0
        Skipped        = 0
        BackedUp       = 0
        Pruned         = 0
        Restored       = 0
        Kept           = 0
    }

    if ($Help) {
        Show-AgexUsage
        return 0
    }

    try {
        $version = $PSVersionTable.PSVersion
        if ($version.Major -lt 5 -or ($version.Major -eq 5 -and $version.Minor -lt 1)) {
            throw ('This installer needs Windows PowerShell 5.1 or PowerShell 7; this is PowerShell ' + $version + '.')
        }
        if ($ctx.DirGiven -and -not $ctx.Dir) {
            throw '-Dir needs a non-empty path, for example: -Dir D:\src\agex'
        }

        $ctx.Repo = Get-AgexEnvValue 'AGEX_REPO'
        if (-not $ctx.Repo) {
            $ctx.Repo = 'https://github.com/saksham-eng560/agex.git'
        }
        $agexHome = Get-AgexEnvValue 'AGEX_HOME'
        if (-not $agexHome) {
            $agexHome = Join-Path -Path $HOME -ChildPath '.agex'
        }
        $ctx.AgexHome = Resolve-AgexFullPath $agexHome
        $claudeHome = Get-AgexEnvValue 'CLAUDE_HOME'
        if (-not $claudeHome) {
            $claudeHome = Join-Path -Path $HOME -ChildPath '.claude'
        }
        $ctx.ClaudeHome = Resolve-AgexFullPath $claudeHome
        $ctx.Manifest = Join-AgexPath $ctx.ClaudeHome @('.agex-manifest')

        if ($ctx.Uninstall) {
            Invoke-AgexUninstall
        }
        else {
            Invoke-AgexInstall
        }
        return 0
    }
    catch {
        Write-AgexError $_.Exception.Message
        Write-Verbose $_.ScriptStackTrace
        return 1
    }
}

$agexExitCode = @(Invoke-AgexInstaller -Uninstall ([bool]$Uninstall) -Force ([bool]$Force) -DirGiven $agexDirGiven -Dir $Dir -NoUpdate ([bool]$NoUpdate) -Help ([bool]$Help) -ScriptPath $agexScriptPath)[-1]
if ($agexScriptPath) {
    # Exit with 0 on success too: otherwise a git command that failed inside
    # the installer (for example "no upstream branch") leaves a non-zero
    # $LASTEXITCODE behind, which fails CI steps and calling scripts.
    exit $agexExitCode
}
# "irm ... | iex" runs in the caller's session, where exit would close the
# window: report the result in $LASTEXITCODE and remove this script's variables.
$global:LASTEXITCODE = $agexExitCode
Remove-Variable -Name agexExitCode, agexScriptPath, agexDirGiven -ErrorAction SilentlyContinue

# PostToolUse hook: luacheck the file that was just edited.
#
# Closes the only window nothing else covers. CI runs luacheck on push; the game loads the
# working tree through the AddOns symlink. Between an edit and starting WoW there is no check
# at all -- and a mistyped global is silent in Lua until that exact line runs, which may be
# mid-raid.
#
# Silent on success. Reports on stderr with exit 2 so the finding reaches Claude.

# Two kinds of "do nothing" below, and they must stay apart:
#   exit 0 silently  -- this edit is none of our business (not Lua, not in this repo, vendored)
#   exit 2 loudly    -- the hook itself is broken
# A hook that fails quietly is worse than no hook: it reads as "checked, clean" forever.

function Fail-Loud($msg) {
    [Console]::Error.WriteLine("luacheck hook broken: $msg")
    exit 2
}

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { Fail-Loud "no hook input on stdin" }
try { $hook = $raw | ConvertFrom-Json } catch { Fail-Loud "hook input is not valid JSON: $_" }

$path = $hook.tool_input.file_path
if (-not $path) { exit 0 }          # some tools carry no file path; not our business
if ($path -notmatch '\.lua$') { exit 0 }

if (-not (Get-Command luacheck -ErrorAction SilentlyContinue)) {
    Fail-Loud "luacheck is not on PATH"
}

# repo root is two levels above this script (.claude/hooks/)
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$full = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
if (-not $full) { Fail-Loud "cannot resolve edited path: $path" }
if (-not $full.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { exit 0 }

$rel = $full.Path.Substring($root.Length).TrimStart('\', '/')

# vendored libraries are excluded in .luacheckrc; skip early so luacheck is not even started
if ($rel -like 'Libs\*') { exit 0 }

# run from the repo root so .luacheckrc and its per-file overrides apply
Push-Location $root
$out = & luacheck --no-color --codes -- $rel
$code = $LASTEXITCODE
Pop-Location

if ($code -eq 0) { exit 0 }

[Console]::Error.WriteLine("luacheck: $rel")
[Console]::Error.WriteLine(($out | Out-String).Trim())
exit 2

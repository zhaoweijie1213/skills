---
name: safe-utf8-file-edits
description: Prevent mojibake and encoding damage when an agent bulk edits or writes source files, especially repositories containing Simplified Chinese comments, strings, or documentation. Use before any PowerShell bulk rewrite, Get-Content/Set-Content pipeline, generated script that writes files, encoding repair, or large mechanical edit where UTF-8 preservation matters.
---

# Safe UTF-8 File Edits

Use this skill before any bulk file write, especially on Windows PowerShell and files containing Simplified Chinese.

## Rules

1. Prefer `apply_patch` for manual edits.
2. For bulk mechanical rewrites, use explicit .NET UTF-8 read/write APIs.
3. Do not use bare `Set-Content`, `Add-Content`, `Out-File`, `>`, or `>>` to write source files.
4. Do not pipe `Get-Content` directly into a write command for source files.
5. Write UTF-8 explicitly, preferably UTF-8 without BOM unless the repository requires preserving an existing BOM.
6. **Any `.ps1` helper you generate must be pure ASCII, or be saved as UTF-8 *with* BOM.** Windows PowerShell 5.1 parses a BOM-less script using the ANSI code page, so a script containing literal Chinese or literal mojibake characters corrupts itself before it ever runs. Express non-ASCII in scripts as `[char]0x6587` or regex `\uXXXX` escapes.
7. After writing, scan for mojibake markers before running build/tests.

## PowerShell Template

Use this pattern for bulk rewrites:

```powershell
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Get-ChildItem -Path 'src' -Recurse -File -Filter *.cs | ForEach-Object {
    $path = $_.FullName
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

    # Make deterministic text changes here.
    $newText = $text.Replace('old', 'new')

    if ($newText -ne $text) {
        [System.IO.File]::WriteAllText($path, $newText, $utf8NoBom)
    }
}
```

When the project requires preserving BOM, detect it and choose the output encoding deliberately:

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$encoding = if ($hasBom) { [System.Text.UTF8Encoding]::new($true) } else { [System.Text.UTF8Encoding]::new($false) }
[System.IO.File]::WriteAllText($path, $newText, $encoding)
```

## Validation

The bundled scanner is `scripts/scan-mojibake.ps1`, located next to this SKILL.md.
Resolve that directory from the skill's own install path (for example
`~/.claude/skills/safe-utf8-file-edits/scripts/scan-mojibake.ps1`) and pass it as an
absolute path. Do **not** rely on `$PSScriptRoot` from an interactive prompt  -  it is
empty outside a running script file.

Verify the scanner itself once after install or after editing it:

```powershell
powershell -ExecutionPolicy Bypass -File <skill-dir>\scripts\scan-mojibake.ps1 -SelfTest
```

Then run it from the repository root after any bulk write:

```powershell
powershell -ExecutionPolicy Bypass -File <skill-dir>\scripts\scan-mojibake.ps1 -Path .
```

Exit codes: `0` clean, `1` suspicious lines reported, `2` scanner error.

What it reports:

| Marker | Meaning |
|---|---|
| `UTF8-decoded-as-Latin1` | UTF-8 bytes were read as ISO-8859-1, then re-saved |
| `UTF8-decoded-as-CP1252` | UTF-8 bytes were read as Windows-1252, then re-saved |
| `ReplacementChar-U+FFFD` | Characters were lost irrecoverably during a decode |
| `NOT-VALID-UTF8` | File is not UTF-8 at all; likely written with an ANSI/GBK code page |

Useful parameters: `-Extension` to change the file types scanned, `-ExcludeDir` to change
the skipped directories (defaults already skip `.git`, `bin`, `obj`, `node_modules`, `dist`, `packages`, `.vs`).

If the scanner reports matches, inspect and repair them before continuing.

For .NET repositories, also run the repository-required checks after the encoding scan:

```powershell
dotnet build -c Release
dotnet test
```

## Repair Guidance

If mojibake appears:

1. Stop further edits.
2. Identify the command that wrote the files.
3. Restore text from git history, user-provided source, or a known-good copy.
4. Rewrite using the UTF-8 template above.
5. Re-run the scanner and normal test suite.

Do not attempt repeated blind transcoding. Mojibake repair is lossy unless the original byte path is known.

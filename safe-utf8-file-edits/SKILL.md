---
name: safe-utf8-file-edits
description: Prevent mojibake and encoding damage when Codex bulk edits or writes source files, especially repositories containing Simplified Chinese comments, strings, or documentation. Use before any PowerShell bulk rewrite, Get-Content/Set-Content pipeline, generated script that writes files, encoding repair, or large mechanical edit where UTF-8 preservation matters.
---

# Safe UTF-8 File Edits

Use this skill before any bulk file write, especially on Windows PowerShell and files containing Simplified Chinese.

## Rules

1. Prefer `apply_patch` for manual edits.
2. For bulk mechanical rewrites, use explicit .NET UTF-8 read/write APIs.
3. Do not use bare `Set-Content`, `Add-Content`, `Out-File`, `>`, or `>>` to write source files.
4. Do not pipe `Get-Content` directly into a write command for source files.
5. Write UTF-8 explicitly, preferably UTF-8 without BOM unless the repository requires preserving an existing BOM.
6. After writing, scan for common mojibake markers before running build/tests.

## PowerShell Template

Use this pattern for bulk rewrites:

```powershell
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Get-ChildItem -Path 'src' -Recurse -Filter *.cs | ForEach-Object {
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

Run the bundled scanner after any bulk write:

```powershell
# Run from the repository root — the script path is relative to where this skill is installed.
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\scripts\scan-mojibake.ps1" -Path .
```

If the scanner reports matches, inspect and repair them before continuing.

For .NET repositories, also run the repository-required checks after the encoding scan, such as:

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

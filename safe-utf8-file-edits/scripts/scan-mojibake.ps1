#Requires -Version 5.1
<#
.SYNOPSIS
    Scans source files for UTF-8 mojibake markers and invalid UTF-8 byte sequences.

.DESCRIPTION
    Detects the damage caused when UTF-8 bytes are decoded as Latin-1 / Windows-1252
    (or when a non-UTF-8 write path mangles Chinese text) and then re-saved as UTF-8.

    IMPORTANT: this file is deliberately 100% ASCII. Every non-ASCII character it
    looks for is expressed as a regex \uXXXX escape, never as a literal. That way the
    scanner cannot itself be corrupted by the very encoding bug it detects, and it
    parses identically under Windows PowerShell 5.1 (ANSI codepage) and PowerShell 7.
    Do not paste literal non-ASCII characters into this file.

.PARAMETER Path
    Root directory to scan.

.PARAMETER Extension
    File extensions to include. Defaults cover .NET, web and docs sources.

.PARAMETER ExcludeDir
    Directory names skipped anywhere in the tree.

.PARAMETER SelfTest
    Verify the scanner works (patterns compile, known mojibake is detected,
    clean Chinese text is not flagged) and exit. Run this once after install.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan-mojibake.ps1 -SelfTest

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scan-mojibake.ps1 -Path .

.OUTPUTS
    Exit code 0 = clean, 1 = findings reported, 2 = scanner error.
#>
[CmdletBinding(DefaultParameterSetName = 'Scan')]
param(
    [Parameter(ParameterSetName = 'Scan', Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter(ParameterSetName = 'Scan')]
    [string[]]$Extension = @(
        '.cs', '.csproj', '.props', '.targets', '.json', '.xml', '.config',
        '.md', '.txt', '.yaml', '.yml', '.sql', '.ps1', '.psm1',
        '.ts', '.js', '.vue', '.css', '.html', '.razor', '.cshtml'
    ),

    [Parameter(ParameterSetName = 'Scan')]
    [string[]]$ExcludeDir = @('.git', 'bin', 'obj', 'node_modules', 'dist', 'packages', '.vs'),

    [Parameter(ParameterSetName = 'SelfTest', Mandatory = $true)]
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# --- Marker definitions (ASCII source, Unicode via regex escapes) -------------

# Lead char: a UTF-8 lead byte (0xC2-0xF4) that was decoded as a single Latin-1 char.
$leadChar = '[\u00C2-\u00F4]'

# Continuation byte 0x80-0xBF decoded as Latin-1.
$latin1Tail = '[\u0080-\u00BF]'

# Continuation byte 0x80-0x9F decoded as Windows-1252 maps to these printable chars.
$cp1252Tail = '[\u20AC\u201A\u0192\u201E\u2026\u2020\u2021\u02C6\u2030\u0160\u2039' +
              '\u0152\u017D\u2018\u2019\u201C\u201D\u2022\u2013\u2014\u02DC\u2122' +
              '\u0161\u203A\u0153\u017E\u0178\u00A0-\u00BF]'

$markers = @(
    [PSCustomObject]@{ Name = 'UTF8-decoded-as-Latin1'; Pattern = "$leadChar$latin1Tail" }
    [PSCustomObject]@{ Name = 'UTF8-decoded-as-CP1252'; Pattern = "$leadChar$cp1252Tail" }
    [PSCustomObject]@{ Name = 'ReplacementChar-U+FFFD'; Pattern = '\uFFFD' }
)

$compiled = foreach ($m in $markers) {
    [PSCustomObject]@{
        Name  = $m.Name
        Regex = [regex]::new($m.Pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
    }
}

# --- Helpers -----------------------------------------------------------------

function Test-FileContent {
    <#
        Returns finding objects for one file. Reads raw bytes and decodes with a
        strict UTF-8 decoder so that files which are not valid UTF-8 at all are
        reported separately from files that are valid UTF-8 but contain mojibake.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath
    )

    $findings = @()
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -eq 0) { return $findings }

    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }

    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        return @([PSCustomObject]@{
            File    = $FilePath
            Line    = 0
            Marker  = 'NOT-VALID-UTF8'
            Snippet = 'File is not decodable as UTF-8. It was very likely written with an ANSI/GBK code page.'
        })
    }

    $lines = $text -split "`r`n|`n|`r"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrEmpty($line)) { continue }
        foreach ($c in $compiled) {
            $match = $c.Regex.Match($line)
            if ($match.Success) {
                $findings += [PSCustomObject]@{
                    File    = $FilePath
                    Line    = $i + 1
                    Marker  = $c.Name
                    Snippet = $line.Substring(0, [Math]::Min(120, $line.Length)).Trim()
                }
                break
            }
        }
    }

    return $findings
}

function Invoke-SelfTest {
    Write-Host 'Running scanner self-test...'

    $latin1 = [System.Text.Encoding]::GetEncoding(28591)   # ISO-8859-1, built in everywhere
    $utf8 = [System.Text.Encoding]::UTF8

    # U+6587 and U+9519 are two common Chinese characters. Built from code points so
    # this file stays ASCII.
    $clean = [string][char]0x6587 + [string][char]0x9519 + ' comment text'
    $broken = $latin1.GetString($utf8.GetBytes($clean))

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mojibake-selftest-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $failures = @()
    try {
        $cleanFile = Join-Path $tmp 'clean.cs'
        $brokenFile = Join-Path $tmp 'broken.cs'
        [System.IO.File]::WriteAllText($cleanFile, $clean, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($brokenFile, $broken, [System.Text.UTF8Encoding]::new($false))

        if ((Test-FileContent -FilePath $cleanFile).Count -ne 0) {
            $failures += 'FAIL: clean Chinese text was flagged as mojibake (false positive).'
        }
        else {
            Write-Host '  [OK] clean Chinese text is not flagged'
        }

        if ((Test-FileContent -FilePath $brokenFile).Count -eq 0) {
            $failures += 'FAIL: known mojibake sample was not detected (false negative).'
        }
        else {
            Write-Host '  [OK] known mojibake sample is detected'
        }

        # A file written with a GBK code page is not valid UTF-8 at all.
        $gbkBytes = $latin1.GetBytes([string][char]0x00C4 + [string][char]0x00E3)
        $rawFile = Join-Path $tmp 'raw.cs'
        [System.IO.File]::WriteAllBytes($rawFile, $gbkBytes)
        $rawResult = Test-FileContent -FilePath $rawFile
        if ($rawResult.Count -eq 0 -or $rawResult[0].Marker -ne 'NOT-VALID-UTF8') {
            $failures += 'FAIL: non-UTF-8 bytes were not reported as NOT-VALID-UTF8.'
        }
        else {
            Write-Host '  [OK] non-UTF-8 bytes are reported'
        }
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ("  [OK] " + $compiled.Count + " marker pattern(s) compiled")

    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { Write-Warning $_ }
        Write-Host 'Self-test FAILED.'
        return 2
    }

    Write-Host 'Self-test passed. Scanner is healthy.'
    return 0
}

# --- Main --------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'SelfTest') {
    exit (Invoke-SelfTest)
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Path not found: $Path"
    exit 2
}

$root = (Resolve-Path -LiteralPath $Path).ProviderPath
$extensionSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$Extension, [System.StringComparer]::OrdinalIgnoreCase)
$separator = [System.IO.Path]::DirectorySeparatorChar

$files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $extensionSet.Contains($_.Extension) }

# Directory exclusion is applied separately for clarity and 5.1 compatibility.
$files = $files | Where-Object {
    $relative = $_.FullName.Substring($root.Length).Trim($separator)
    $segments = $relative -split '[\\/]'
    $excluded = $false
    foreach ($segment in $segments) {
        if ($ExcludeDir -contains $segment) { $excluded = $true; break }
    }
    -not $excluded
}

$hits = @()
$scanned = 0
foreach ($file in $files) {
    $scanned++
    try {
        $hits += Test-FileContent -FilePath $file.FullName
    }
    catch {
        Write-Warning ("Could not scan " + $file.FullName + ": " + $_.Exception.Message)
    }
}

Write-Host ("Scanned " + $scanned + " file(s) under " + $root)

if ($hits.Count -eq 0) {
    Write-Host '[OK] No mojibake markers found.' -ForegroundColor Green
    exit 0
}

Write-Warning ("[WARN] Found " + $hits.Count + " suspicious line(s):")
$hits | Format-Table File, Line, Marker, Snippet -AutoSize -Wrap
Write-Host 'Do NOT blind-transcode. Restore from git history, then rewrite with the UTF-8 template.'
exit 1

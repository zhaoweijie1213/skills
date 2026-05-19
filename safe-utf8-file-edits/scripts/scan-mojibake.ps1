# scan-mojibake.ps1
# Scans source files under -Path for common UTF-8 mojibake markers
# that arise when Windows-1252 or GB2312 bytes are misread as Latin-1.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scan-mojibake.ps1 -Path <repo-root>

param(
    [Parameter(Mandatory)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

# Common mojibake sequences produced when Chinese UTF-8 bytes are decoded as Windows-1252 or Latin-1.
# Each entry is a regex pattern.
$markers = @(
    'Ã[€-ÿ]',          # 2-byte UTF-8 lead decoded as two Latin-1 chars
    'â€[œžŸ™š]',       # Smart quotes / em-dash mojibake
    '[\xC3\xC2][\x80-\xBF]',  # Raw byte range (if PS reads as byte strings)
    'æ\x96\x87',        # 文 → æ–‡ pattern
    'ç\x9B®',           # 目 → ç›® pattern
    'é\x94\x99',        # 错 → é"™ pattern
)

$pattern = ($markers | ForEach-Object { "($_)" }) -join '|'

$hits = @()

Get-ChildItem -Path $Path -Recurse -Include *.cs,*.json,*.xml,*.md,*.txt,*.yaml,*.yml |
    Where-Object { -not $_.PSIsContainer } |
    ForEach-Object {
        $file = $_.FullName
        $lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)
        $lineNum = 0
        foreach ($line in $lines) {
            $lineNum++
            if ($line -match $pattern) {
                $hits += [PSCustomObject]@{
                    File   = $file
                    Line   = $lineNum
                    Snippet = $line.Substring(0, [Math]::Min(120, $line.Length))
                }
            }
        }
    }

if ($hits.Count -eq 0) {
    Write-Host "✔ No mojibake markers found." -ForegroundColor Green
    exit 0
} else {
    Write-Warning "⚠ Found $($hits.Count) potential mojibake occurrence(s):"
    $hits | Format-Table -AutoSize
    exit 1
}

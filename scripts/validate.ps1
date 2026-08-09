$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host 'Validation de la syntaxe Python...'
$pythonCheck = @'
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
files = list((root / "raspberry").rglob("*.py"))
for path in files:
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
print(f"Python : {len(files)} fichier(s) valide(s)")
'@
$pythonCheck | python - $projectRoot
if ($LASTEXITCODE -ne 0) {
    throw 'La validation Python a échoué.'
}

Write-Host 'Validation de la syntaxe PowerShell...'
$parseErrors = @()
Get-ChildItem (Join-Path $projectRoot 'windows-agent') -Filter '*.ps1' -File |
    ForEach-Object {
        $tokens = $null
        $fileErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$fileErrors
        )
        $parseErrors += $fileErrors
    }

if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List
    throw 'La validation PowerShell a échoué.'
}

Write-Host 'Recherche de secrets littéraux...'
$secretPattern = 'BEGIN (RSA |OPENSSH )?PRIVATE KEY|cloudflared\.exe service install eyJ|Authorization:\s*Bearer\s+[A-Za-z0-9._-]{20,}'
$secretHits = & rg -l -i $secretPattern $projectRoot -g '!.git/**'
if ($LASTEXITCODE -eq 0 -and $secretHits) {
    $secretHits
    throw 'Un secret potentiel a été détecté.'
}
if ($LASTEXITCODE -notin 0, 1) {
    throw 'La recherche de secrets a échoué.'
}

Write-Host 'Validation terminée sans exécuter le serveur ni les actions PC Control.' -ForegroundColor Green

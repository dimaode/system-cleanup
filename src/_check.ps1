$srcDir = Split-Path $MyInvocation.MyCommand.Path
$files  = Get-ChildItem -Path $srcDir -Filter '*.ps1' | Where-Object { $_.Name -ne '_check.ps1' }
$allOk  = $true
foreach ($f in $files) {
    $errors = $null
    $null   = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        Write-Host "PASS: $($f.Name)" -ForegroundColor Green
    } else {
        $allOk = $false
        Write-Host "FAIL: $($f.Name)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" }
    }
}
if ($allOk) { Write-Host "`nAll scripts passed." -ForegroundColor Cyan }

$files = @(
    'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\cleanup.ps1',
    'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\monitor.ps1',
    'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\report.ps1'
)
foreach ($f in $files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        Write-Host "PASS: $f" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $f" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" }
    }
}

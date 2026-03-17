import subprocess, os, sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

src = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src'
files = sorted([f for f in os.listdir(src) if f.endswith('.ps1') and not f.startswith('_')])

all_ok = True
for fname in files:
    fpath = os.path.join(src, fname).replace('\\', '/')
    ps_cmd = (
        "$errors = $null; "
        f"$null = [System.Management.Automation.Language.Parser]::ParseFile('{fpath}', [ref]$null, [ref]$errors); "
        "Write-Output ('ERRCOUNT:' + $errors.Count); "
        "$errors | ForEach-Object { Write-Output ('  L' + $_.Extent.StartLineNumber + ': ' + $_.Message) }"
    )
    r = subprocess.run(['powershell', '-NoProfile', '-Command', ps_cmd],
                       capture_output=True)
    out = r.stdout.decode('utf-8', errors='replace').strip()
    has_err = False
    for line in out.splitlines():
        if line.startswith('ERRCOUNT:'):
            count = int(line.split(':')[1])
            has_err = count > 0
            if count == 0:
                print(f'PASS: {fname}')
            else:
                all_ok = False
                print(f'FAIL: {fname}  ({count} errors)')
        elif line.strip():
            print(f'     {line}')

if all_ok:
    print('\nAll scripts passed syntax check.')

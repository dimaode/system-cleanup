"""
Fix two issues in ps1 files:
1. Rewrite with UTF-8 BOM so PowerShell parser reads Chinese correctly
2. Replace backtick-wrapped code spans  `xxx` -> 'xxx' inside Write-Host strings
"""
import re, os, sys

src = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src'
targets = ['browser-cache.ps1', 'large-files.ps1', 'startup.ps1']

BOM = b'\xef\xbb\xbf'

for fname in targets:
    fpath = os.path.join(src, fname)
    with open(fpath, 'rb') as f:
        raw = f.read()

    # Strip existing BOM if present
    if raw.startswith(BOM):
        raw = raw[3:]

    text = raw.decode('utf-8', errors='replace')

    # Fix backtick code spans inside Write-Host lines:
    # Replace  `word`  with  'word'
    def fix_backticks(line):
        return re.sub(r'`([^`\n\t]+?)`', lambda x: "'" + x.group(1) + "'", line)

    lines = text.splitlines(keepends=True)
    fixed_lines = []
    for line in lines:
        if 'Write-Host' in line and '`' in line:
            line = fix_backticks(line)
        fixed_lines.append(line)

    fixed_text = ''.join(fixed_lines)

    # Write back with UTF-8 BOM
    with open(fpath, 'wb') as f:
        f.write(BOM + fixed_text.encode('utf-8'))

    print(f'Fixed: {fname}')

print('Done.')

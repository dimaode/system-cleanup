import sys
path = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\report.ps1'
with open(path, encoding='utf-8-sig') as f:
    lines = f.readlines()
for i, line in enumerate(lines[160:230], start=161):
    print(f'{i:3d}: {repr(line.rstrip())}')

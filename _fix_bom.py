import codecs, sys

path = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\report.ps1'

# Read the original UTF-8 content
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Re-write with UTF-8 BOM so PowerShell parser recognises encoding
with open(path, 'w', encoding='utf-8-sig') as f:
    f.write(content)

print('Done: re-written with UTF-8 BOM')

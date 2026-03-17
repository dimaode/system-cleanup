import sys
path = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\report.ps1'
with open(path, 'rb') as f:
    b = f.read(8)
print('First bytes hex:', b.hex())
print('UTF8-BOM:', b[:3] == bytes([0xef,0xbb,0xbf]))
# try read as utf-8
try:
    with open(path, encoding='utf-8') as f:
        content = f.read()
    print('UTF-8 read OK, length:', len(content))
    # find line 32
    lines = content.split('\n')
    print('Line 31:', repr(lines[30]))
    print('Line 32:', repr(lines[31]))
except Exception as e:
    print('UTF-8 read failed:', e)

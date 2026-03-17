import sys

path = r'C:\Users\Administrator\.openclaw\workspace\skills\system-cleanup\src\report.ps1'

with open(path, encoding='utf-8-sig') as f:
    content = f.read()

# Replace backtick-wrapped command strings inside double-quoted PS strings
# e.g. `openclaw run ...` -> 'openclaw run ...'  (single quotes are safe in PS double-quoted strings)
import re

# Pattern: backtick ... backtick inside a double-quoted AppendLine call
# Replace `cmd` with 'cmd' so backtick is not treated as PS escape char
content = re.sub(r'`([^`\n]+)`', r"'\1'", content)

with open(path, 'w', encoding='utf-8-sig') as f:
    f.write(content)

print('Done: replaced backtick-code-spans with single-quoted strings')

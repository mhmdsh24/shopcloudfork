import re

with open(r'c:\Users\Hussein\Desktop\shopcloud\services\catalog\scratch_update.py', 'r', encoding='utf-8') as f:
    code = f.read()

# Extract new_html from the scratch file itself
start_idx = code.find("new_html = r'''") + len("new_html = r'''")
end_idx = code.find("'''\n\nwith open")
new_html = code[start_idx:end_idx]

with open(r'c:\Users\Hussein\Desktop\shopcloud\services\catalog\app.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace using regex but pass a lambda to avoid escape processing
pattern = re.compile(r'_STOREFRONT_HTML\s*=\s*r"""<!doctype html>.*?</html>"""', re.DOTALL)
replacement = '_STOREFRONT_HTML = r"""' + new_html + '"""'
new_content = pattern.sub(lambda m: replacement, content)

with open(r'c:\Users\Hussein\Desktop\shopcloud\services\catalog\app.py', 'w', encoding='utf-8') as f:
    f.write(new_content)
print("Updated successfully")

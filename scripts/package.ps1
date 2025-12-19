$MOD_NAME = "PlumbingFixed"

Remove-Item -Recurse -Force -Path ./$MOD_NAME
New-Item -ItemType Directory -Force -Path ./$MOD_NAME
Copy-Item ./Contents -Recurse ./$MOD_NAME/Contents
Copy-Item ./preview.png ./$MOD_NAME/preview.png
Copy-Item ./workshop.txt ./$MOD_NAME/workshop.txt
# build 41 compat
Copy-Item ./Contents/mods/$MOD_NAME/42/media -Recurse ./$MOD_NAME/Contents/mods/$MOD_NAME/media
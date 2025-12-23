$MOD_NAME = "PlumbingFixed"

Remove-Item -Recurse -Force -Path ./$MOD_NAME
New-Item -ItemType Directory -Force -Path ./$MOD_NAME
Copy-Item ./Contents -Recurse ./$MOD_NAME/Contents
Copy-Item ./preview.png ./$MOD_NAME/preview.png
Copy-Item ./workshop.txt ./$MOD_NAME/workshop.txt
# build 41 compat
Copy-Item ./Contents/mods/$MOD_NAME/41/** -Recurse ./$MOD_NAME/Contents/mods/$MOD_NAME/
Remove-Item ./$MOD_NAME/Contents/mods/$MOD_NAME/41 -Recurse
Remove-Item ./$MOD_NAME/Contents/mods/$MOD_NAME/common/.gitkeep

Write-Output "Packaging complete for $MOD_NAME"
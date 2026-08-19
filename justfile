set shell := ["powershell.exe", "-c"]

# Install the toolchain, fetch the API types, build the harness sourcemap
setup:
    rokit install
    just globaltypes
    just sourcemap

# Fetch the Roblox API type definitions luau-lsp needs (not vendored: 20k generated lines)
globaltypes:
    curl -L -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau

# Regenerate the harness sourcemap (luau-lsp needs it to resolve @game/... requires)
sourcemap:
    rojo sourcemap .harness/default.project.json --output sourcemap.json

# Typecheck, lint, format check -- the entire safety net of this repo
#
# Roblox-side paths are listed one entry at a time rather than globbed. It is a
# line per entry, and it keeps the recipe readable, which matters more here than
# saving the line.
#
# Files under */tools/ run on Lune, whose standard library the Roblox
# definitions know nothing about, so they are linted and formatted but not
# analyzed. See docs/conventions.md for what typechecking them would take.
check:
    luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau remotes/game remotes/examples
    selene remotes
    selene remotes/tools
    stylua --check remotes

# Format in place
fmt:
    stylua remotes

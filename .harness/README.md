# .harness

Not a game. This is the smallest DataModel that lets `luau-lsp` resolve
`@game/...` requires so the entries and their examples can be typechecked.

Nothing here is meant to be copied, built into a place, or served to Studio.
It exists so that `just check` has something to analyze against.

Adding an entry means adding it to `default.project.json` and rerunning
`just sourcemap`. One line, and it states where the entry is meant to live in a
real place.

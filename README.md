# luau-cookbook

Luau modules worth copying, each with the reasoning that produced it.

This is **not a package**. Nothing here is published to Wally or pesde, and no
project depends on it. You open an entry, read why it is shaped the way it is,
copy the files you want into your own tree, and adapt them. The repository's
job is to answer one question: *which version of this is the current one, and
what was the thinking behind it.*

That question is the reason it exists. Before this repo, `RemoteTypes.luau`
existed in five copies across five projects, in four different folders, in four
mutually divergent versions ranging from 45 to 101 lines. Nothing was wrong
with any of them individually. What was missing was a place that says which one
is right today.

## Why copy instead of depend

For a module of 100 lines with no runtime, a dependency costs more than the
code. You would need Wally, `wally-package-types` so the types survive the
boundary, a current sourcemap, and a version to resolve, in exchange for a file
you would have adapted to your project anyway. Copying is the honest
arrangement, so it is the one this repo commits to.

The cost of copying is drift, and drift is what the conventions in
[`docs/conventions.md`](docs/conventions.md) exist to fight. In short: every
copyable file carries a provenance stamp saying where it came from and when,
every entry keeps its own changelog, and every claim an entry makes about the
type system is written as an example the CI typechecks.

## Entries

| Entry | What it is |
|---|---|
| [`remotes/`](remotes/) | Type shims for Roblox remotes that keep untrusted input untrusted, plus a generator that writes the instance files and the barrel from one declaration |

## Working on this repo

```sh
rokit install     # toolchain
just globaltypes  # fetch the Roblox API type definitions (not vendored)
just sourcemap    # the harness sourcemap luau-lsp needs
just check        # typecheck, lint, format check
```

`just check` is the whole safety net. An entry that stops typechecking is an
entry whose documentation has started lying.

## License

MIT. See [LICENSE](LICENSE).

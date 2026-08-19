# Conventions

The rules that keep a copy-from repository from rotting. They are short on
purpose: a convention nobody remembers is not a convention.

## What earns an entry

Two filters, both required.

**It already exists in three or more copies.** Not "it might be reusable", but
"I have written it three times". Three copies is the point where the question
"which one is right" starts costing real time, and it is the problem this repo
solves. A module written once and never reused belongs in the project that
needed it.

**It survives outside the author's layout.** An entry that assumes a particular
folder structure, alias scheme, or UI framework is not reusable, it is
transplantable at best. Those stay in the project or in a private repo. The
test is simple: could a stranger paste this into an unfamiliar codebase and
have it work after changing require paths only.

A module that passes the first filter and fails the second is not a failure of
the module. It is a signal that the reusable part, if there is one, is smaller
than the file.

## The shape of an entry

An entry is a directory named for the problem it solves, not for the module it
contains: `remotes/`, not `RemoteTypes/`. The problem outlives the
implementation.

```
<entry>/
  README.md      what it is, what it assumes, what it is not
  CHANGELOG.md   dated entries, newest first
  game/          files that end up inside the Roblox place
  tools/         files that stay on the developer's machine
  examples/      typechecked demonstrations, never required at runtime
```

`game/` and `tools/` exist only when an entry genuinely has both. A single-file
entry is a single file next to its README, and adding empty folders around it
would be ceremony.

The README carries a table of every file with its destination. This is the one
mandatory section, because sending a `tools/` file into `ReplicatedStorage` is
the mistake that actually happens.

## Provenance stamps

Every file under `game/` opens with:

```lua
-- luau-cookbook/remotes -- 2026-08-19
-- https://github.com/rbx-dev-tools/luau-cookbook/tree/main/remotes
-- Local edits are expected. Check the changelog before copying a newer version
-- over one you have modified.
```

The stamp travels with the copy. When you find a divergent version in a game
two years from now, the file itself tells you which entry it came from and how
old it is. That is the whole point, and it costs three lines.

The date is the entry's last changelog date, not the copy date. A copy is
either current or it is not; when it was taken changes nothing.

## Versioning

The repository has no version number, and never will. Entries are unrelated to
each other, so a single number over all of them would carry no information: a
fix to one entry would bump a version that means nothing to anyone reading
another.

Each entry keeps a `CHANGELOG.md` instead, dated rather than numbered. There is
no semver here because there is no resolver to negotiate with. Someone reading
the changelog wants to know what changed since the copy they hold, and a date
answers that directly.

## Examples are the test suite

Nothing in this repo runs, so nothing can be unit tested in the usual sense.
What can be verified is that the claims hold, and for a repo whose entries are
largely about types, most claims are type-level claims.

So each entry's assertions are written as a module under `examples/` that
`just check` typechecks. When an entry says "annotating this argument
concretely will not compile", the example contains that annotation, commented
out, next to the code that does compile. If Luau's behaviour changes, or if the
entry is edited carelessly, the check fails. A note in prose could not do that.

Examples are never required by anything. They exist to be analyzed.

## Adding an entry to the harness

`luau-lsp` needs the entry mapped into a DataModel to resolve `@game/...`
requires. Add it to `.harness/default.project.json` and rerun `just sourcemap`.
This is a manual step by design: it is one line, and it makes the entry's
intended location in a real place explicit.

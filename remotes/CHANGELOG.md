# Changelog -- remotes

Dated, newest first. See [../docs/conventions.md](../docs/conventions.md) for
why there are no version numbers.

## 2026-08-20

- The README gains "From declaration to use": the declaration you write, the
  command, the four files that come out, and the code that requires the barrel.
  Every option was documented and the cycle they serve was not, so the entry
  explained its parts and never showed the whole.
- `RemoteExample.luau` says what it is. It reads like a usage example, is named
  like one, and is not one -- it is the sheet of claims `just check` enforces.
  Its two oddities are now stated rather than left to be puzzled over: the types
  are redeclared because this repo cannot typecheck a cross-module require, and
  `(nil :: any) :: T` stands in for an instance the barrel would supply.

- `--instances-dir` and `--instances-path` added, splitting the one question
  `--instances` used to answer into the two it actually was: where the instance
  files land on disk, and how the barrel reaches them in the datamodel. Rojo
  maps one to the other however it likes, so neither can be derived from the
  other. Collecting every remote into `ReplicatedStorage.Remotes` is now
  possible; the barrel opens with the `GetService` line it needs.
- `--prune` now reads every declaration of the run before deleting anything.
  Pruning per declaration was correct only while each one owned its folder: in
  a shared folder it saw every other declaration's instances as orphans. It
  refuses a single-file target when `--instances-dir` is set, for the same
  reason -- one declaration cannot account for a folder it shares.
- `--barrel` added, naming the generated module outright instead of deriving it
  from the declaration. One declaration at a time: pointed at a directory,
  every barrel would be written over the same file. With it, `--schema-suffix`
  is no longer required to end in `Schema.luau`, since nothing is derived.
- `just sourcemap` passes `--include-non-scripts`. Without it the sourcemap
  described only the scripts, so the generated remote instances were absent
  from the DataModel `luau-lsp` analyses against.

Known, and not fixed here: `just check` resolves no cross-module require. Every
example is self-contained for that reason, and a fixture pairing a declaration
with its generated barrel cannot be typechecked until it is addressed. The
generator's behaviour was verified by running it against throwaway trees
instead.

## 2026-08-19

First entry in the cookbook, lifted from the project it grew in.

- `ToClient` and `ToServer`, named for their destination, carrying only the
  methods that direction allows.
- Every server-facing member takes `...unknown`: `OnServerEvent` on all event
  shims, and the argument list of `OnServerInvoke`. `OnServerInvoke` keeps its
  typed return.
- `UnreliableToClient` for the one direction unreliable remotes are actually
  used in. The mirror is deliberately absent until something needs it.
- Bidirectional `RemoteEvent` and `UnreliableRemoteEvent` are kept, marked as
  the rare case: two one-way remotes usually say more.
- `tools/generate.luau` decoupled from the layout it grew in. The instances
  folder and the root a bare feature name resolves against are now
  `--instances` and `--features-root`, defaulting to the previous hardcoded
  values, so an existing project passes nothing and behaves as before. Verified
  against an unrelated tree and, with defaults, against the original one.
- The generated barrel header no longer names a path or a task runner that only
  existed in the source project.
- `--schema-suffix` added, defaulting to the previous fixed `RemotesSchema.luau`.
  It is validated to end in `Schema.luau`, which keeps directory scanning and
  barrel naming from disagreeing. Before this, a declaration named
  `CombatNetSchema.luau` was invisible to a directory scan but generated
  correctly when pointed at directly.

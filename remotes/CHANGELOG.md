# Changelog -- remotes

Dated, newest first. See [../docs/conventions.md](../docs/conventions.md) for
why there are no version numbers.

## 2026-08-20

- The entry README opens with code. It opened with twenty-eight lines of
  argument, and the first line of code was three screens down: a reader had to
  take the reasoning on trust before seeing what using it looks like. The why is
  unchanged, it just no longer comes first.

- `--prune` rebuilt on a complete inventory. It deleted what the declarations of
  the *run* did not name, which is not the same set as what no declaration names
  the moment one folder has two declarations feeding it -- and that is the
  default whenever two are file siblings. Pointing it at one feature deleted
  another's instances; so did pointing it at one file among siblings. The
  inventory is now scanned from `--prune-root` (`.`), independent of what is
  being generated.
- Refuses to prune when a declaration cannot be read, rather than treating
  everything it owns as an orphan. A rename or a mid-edit file cost files
  before.
- Refuses a barrel name equal to the declaration's, which overwrote the one file
  nobody generates and reported it as an update. Reachable through `--barrel`,
  and without it through a declaration whose name has no trailing `Schema`.
- Refuses an `--instances-path` whose head is not a service. It became
  `game:GetService("Remotes")`, which threw the first time the barrel was
  required, in game, far from the generator.
- Warns when two declarations feeding one folder claim the same remote name.
  The second overwrote the first silently, and its class could differ.
- Directory keys are normalised, without which `./x/Remotes` and `x/Remotes`
  were different entries and the inventory lookup missed.

- `examples/` gains a real declaration and everything generated from it:
  `ShopRemotesSchema.luau`, the `ShopRemotes.luau` barrel, and four
  `Remotes/*.model.json`. The entry described the cycle in prose and shipped no
  file you could open, which made "where is the schema" a fair question with no
  answer. `just check` ignores the pair: the barrel requires its declaration,
  and no cross-module require resolves against this harness. An unchecked
  example beats an absent one, and the gap is the argument for fixing that.

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

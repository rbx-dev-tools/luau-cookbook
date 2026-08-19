# Changelog -- remotes

Dated, newest first. See [../docs/conventions.md](../docs/conventions.md) for
why there are no version numbers.

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

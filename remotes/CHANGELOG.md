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
- `tools/generate.luau` included as-is. It still assumes the layout of the
  project it came from and is not yet runnable against an arbitrary tree.

-- luau-cookbook/remotes -- 2026-08-19
-- https://github.com/rbx-dev-tools/luau-cookbook/tree/main/remotes
-- Local edits are expected. Check the changelog before copying a newer
-- version over one you have modified.

-- Derived from the `typed-remote` module of RbxUtil, MIT, (c) 2025 Stephen
-- Leitnick -- https://github.com/Sleitnick/RbxUtil. Notice in ../../THIRD-PARTY.md.

-- Types only. The module returns an empty table, and a "typed remote" here is a
-- cast that vanishes at compile time: it documents the contract, it does not
-- enforce it. Anything reaching a server handler still needs a runtime check.
--
-- Do not "fix" the `...unknown` below into `T...`. The client picks what it
-- sends, including how many arguments, so promising `T...` to a server handler
-- is a lie the compiler would then confirm. Sending stays typed both ways --
-- what you send is yours, and a mistake there is your bug, not an attack.
--
-- ../README.md has the reasoning. ../examples/RemoteExample.luau has it as
-- claims `just check` enforces.

type Signal<T...> = {
    Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    ConnectParallel: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    Once: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    Wait: (self: Signal<T...>) -> T...,
}

-- The player is prepended by the engine, so this cannot reuse Signal<T...>.
type PlayerSignal<T...> = {
    Connect: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
    ConnectParallel: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
    Once: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
    Wait: (self: PlayerSignal<T...>) -> (Player, T...),
}

-- Backed by a RemoteEvent instance, one way only.
export type ToClient<T...> = Instance & {
    OnClientEvent: Signal<T...>,
    FireClient: (self: ToClient<T...>, player: Player, T...) -> (),
    FireAllClients: (self: ToClient<T...>, T...) -> (),
}

-- Backed by a RemoteEvent instance, one way only.
export type ToServer<T...> = Instance & {
    FireServer: (self: ToServer<T...>, T...) -> (),
    OnServerEvent: PlayerSignal<...unknown>,
}

-- Both directions on one instance. Rare, and worth a second look when you reach
-- for it -- two one-way remotes usually say more.
export type RemoteEvent<T...> = Instance & {
    OnClientEvent: Signal<T...>,
    OnServerEvent: PlayerSignal<...unknown>,
    FireClient: (self: RemoteEvent<T...>, player: Player, T...) -> (),
    FireAllClients: (self: RemoteEvent<T...>, T...) -> (),
    FireServer: (self: RemoteEvent<T...>, T...) -> (),
}

-- Unreliable remotes are nearly always server -> client, so that is the only
-- direction given a shim. Add the mirror when something needs it.
export type UnreliableToClient<T...> = Instance & {
    OnClientEvent: Signal<T...>,
    FireClient: (self: UnreliableToClient<T...>, player: Player, T...) -> (),
    FireAllClients: (self: UnreliableToClient<T...>, T...) -> (),
}

export type UnreliableRemoteEvent<T...> = Instance & {
    OnClientEvent: Signal<T...>,
    OnServerEvent: PlayerSignal<...unknown>,
    FireClient: (self: UnreliableRemoteEvent<T...>, player: Player, T...) -> (),
    FireAllClients: (self: UnreliableRemoteEvent<T...>, T...) -> (),
    FireServer: (self: UnreliableRemoteEvent<T...>, T...) -> (),
}

-- Already one way by construction: the client asks, the server answers.
export type RemoteFunction<T..., R...> = Instance & {
    InvokeServer: (self: RemoteFunction<T..., R...>, T...) -> R...,
    OnServerInvoke: (player: Player, ...unknown) -> R...,
}

return {}

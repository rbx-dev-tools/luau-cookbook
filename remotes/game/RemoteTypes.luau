-- luau-cookbook/remotes -- 2026-08-19
-- https://github.com/rbx-dev-tools/luau-cookbook/tree/main/remotes
-- Local edits are expected. Check the changelog before copying a newer
-- version over one you have modified.

-- Type-only shims over Roblox's remote instances. There is no runtime here:
-- the module returns an empty table and every export is a type. A "typed
-- remote" in this repo is a `::` cast that vanishes at compile time, not a
-- wrapper object -- see the declaration example in this entry's README.
--
-- The trade this makes: the compiler believes the cast, so a client can still
-- fire whatever it wants. Types document the contract; they do not enforce it.
-- Anything reaching a server handler still needs a real runtime check.
--
-- Which is why every server-facing member below takes `...unknown` and not
-- `T...`. Trust is asymmetric: the server is reliable, the client is not, so a
-- signature promising `T...` to a server handler is a lie the compiler would
-- then confirm -- you index `payload.itemId` and nothing stops you. `...unknown`
-- is not a weaker type than `T...`, it is the accurate one; the client picks
-- what it sends, including how many arguments.
--
-- Sending stays typed on both sides: FireServer, FireClient and InvokeServer
-- describe what YOU send, and a mistake there is your bug, not an attack.
-- OnServerInvoke keeps its typed RETURN for the same reason.
--
-- DIRECTION. Prefer ToClient or ToServer over the plain RemoteEvent. They are
-- named for the destination, so there is no reading them backwards, and they
-- carry no method for the wrong direction -- so
--
--   BadgeAwarded:FireServer(1)               -- BadgeAwarded is server -> client
--   BadgeAwarded.OnServerEvent:Connect(...)
--
-- stop compiling instead of connecting to something that will never fire. That
-- mistake is silent otherwise: the remote exists, the call typechecks, and
-- nothing ever happens. Prose in a doc comment cannot catch it and neither can
-- a grep over use sites -- an alias (`local b = X.BadgeAwarded`) defeats both.
--
-- See examples/RemoteExample.luau for how to get from `unknown` back to a real
-- type, and for the mistakes this arrangement is supposed to catch.

type Signal<T...> = {
    Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    ConnectParallel: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    Once: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
    Wait: (self: Signal<T...>) -> T...,
}

-- The server always receives the firing player as a prepended argument, so the
-- server-facing signal cannot reuse Signal<T...>. It is instantiated only with
-- `...unknown` -- see the note at the top of the file.
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

-- Backed by a RemoteEvent instance, one way only. FireServer is typed because
-- it describes what you send; OnServerEvent is not, because it describes what
-- someone else sent.
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

-- Unreliable remotes are nearly always server -> client (positions, effects), so
-- that is the only direction given a shim. Add the mirror when something needs
-- it rather than before.
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

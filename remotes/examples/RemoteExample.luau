--> What `unknown` on the server side costs, and how to get real types back.
--
-- Nothing here runs -- no script requires this module. `just check` typechecks
-- it, and that is what makes it a test rather than a note: if a claim below
-- stops being true, the check fails.
--
-- The remote types are redeclared locally so this file stands on its own, but
-- they are game/RemoteTypes.luau's, with the two lines marked CHANGE. Copy those two
-- lines over when you want the real thing.

-- 1. The types ---------------------------------------------------------------

type Signal<T...> = {
    Connect: (self: Signal<T...>, fn: (T...) -> ()) -> RBXScriptConnection,
}

type PlayerSignal<T...> = {
    Connect: (self: PlayerSignal<T...>, fn: (player: Player, T...) -> ()) -> RBXScriptConnection,
}

type RemoteEvent<T...> = Instance & {
    OnClientEvent: Signal<T...>,
    -- CHANGE: was PlayerSignal<T...>. The client picks what it sends, including
    -- how many arguments, so no signature here can be trusted. `...unknown` is
    -- not a weaker type than T... -- it is the accurate one.
    OnServerEvent: PlayerSignal<...unknown>,
    FireClient: (self: RemoteEvent<T...>, player: Player, T...) -> (),
    FireAllClients: (self: RemoteEvent<T...>, T...) -> (),
    FireServer: (self: RemoteEvent<T...>, T...) -> (),
}

type RemoteFunction<T..., R...> = Instance & {
    InvokeServer: (self: RemoteFunction<T..., R...>, T...) -> R...,
    -- CHANGE: was (player: Player, T...) -> R...
    --
    -- Note the asymmetry inside one line: the arguments are untrusted, so they
    -- are unknown; the RETURN stays R..., because that value is yours. The
    -- compiler still holds you to what you promised the client.
    OnServerInvoke: (player: Player, ...unknown) -> R...,
}

-- Stand-ins for real instances. `(nil :: any) :: T` is the same cast the
-- generated barrel makes on a real one.
local BuyItemRemote = (nil :: any) :: RemoteEvent<string, number>
local GetBalanceRemote = (nil :: any) :: RemoteFunction<(), (number)>

-- 2. Reading an untrusted argument -------------------------------------------

-- No annotations on itemId/quantity: they are `unknown`, and writing that out
-- would be redundant. Annotating them CONCRETELY does not compile at all --
-- uncomment the block at the bottom of this file to watch it fail.
BuyItemRemote.OnServerEvent:Connect(function(player, itemId, quantity)
    -- Nothing is readable yet. `itemId .. ""` or `quantity + 1` are both
    -- rejected here, which is the entire point of the change.
    if typeof(itemId) ~= "string" or typeof(quantity) ~= "number" then
        return
    end

    -- Past the guard, Luau has narrowed both. These two lines are the proof:
    -- they only compile because the refinement happened.
    local name: string = itemId
    local count: number = quantity

    print(`{player.Name} bought {count} x {name}`)
end)

-- 3. Untrusted tables --------------------------------------------------------

-- `typeof(x) == "table"` narrows to a table, not to YOUR table. A payload with
-- named fields needs a real validator, and the honest signature for one is
-- `(unknown) -> T?` -- it either produces the shape or it does not.

export type BuyRequest = {
    itemId: string,
    quantity: number,
}

local function asBuyRequest(value: unknown): BuyRequest?
    if typeof(value) ~= "table" then
        return nil
    end

    -- A table of unknowns: the keys may be there, their values are still
    -- anybody's guess.
    local fields = value :: { [string]: unknown }
    local itemId = fields.itemId
    local quantity = fields.quantity

    if typeof(itemId) ~= "string" or typeof(quantity) ~= "number" then
        return nil
    end

    -- Rebuilt rather than cast, so what comes out has exactly the fields
    -- BuyRequest promises and no extras the client smuggled in.
    return {
        itemId = itemId,
        quantity = quantity,
    }
end

local BuyRequestRemote = (nil :: any) :: RemoteEvent<BuyRequest>

BuyRequestRemote.OnServerEvent:Connect(function(player, payload)
    local request = asBuyRequest(payload)
    if not request then
        -- A client that sends garbage gets dropped, not an error thrown inside
        -- your handler.
        return
    end

    print(`{player.Name} wants {request.quantity} x {request.itemId}`)
end)

-- 4. RemoteFunction ----------------------------------------------------------

-- Arguments unknown, return type enforced. Returning a string here is a
-- compile error, because R... is the promise you made the client.
--
-- The unknown arguments are simply not declared: a handler is free to ignore
-- what it was sent, and declaring `...: unknown` only to never read it is what
-- selene flags as an unused vararg.
local function onGetBalance(player: Player): number
    return #player.Name
end

GetBalanceRemote.OnServerInvoke = onGetBalance

-- 5. The client side is untouched --------------------------------------------

-- None of the above costs anything on the client, where the server IS trusted
-- and the payload type is the reason to have typed remotes at all.
BuyItemRemote.OnClientEvent:Connect(function(itemId, quantity)
    -- Typed straight away, no guard, no validator.
    local name: string = itemId
    local count: number = quantity
    print(name, count)
end)

BuyItemRemote:FireServer("sword", 1)

local balance: number = GetBalanceRemote:InvokeServer()
print(balance)

-- 6. What is supposed to fail ------------------------------------------------

-- Uncomment any block below and run `just check`. Each one is a claim this file
-- makes; if a block stops failing, the claim is stale.

-- Concrete annotations on an untrusted handler:
--
-- BuyItemRemote.OnServerEvent:Connect(function(player, itemId: string)
--     return player, itemId
-- end)
--
-- Expected: Expected this to be '(Player, ...unknown) -> ()'
--                  but got      '(Player, string) -> ()'

-- Using an untrusted argument before narrowing it:
--
-- BuyItemRemote.OnServerEvent:Connect(function(player, itemId)
--     local name: string = itemId
--     return player, name
-- end)
--
-- Expected: Expected this to be 'string', but got 'unknown'

-- Breaking the promise a RemoteFunction made:
--
-- GetBalanceRemote.OnServerInvoke = function(player: Player, ...: unknown): string
--     return player.Name
-- end
--
-- Expected: type mismatch on the return, 'string' where 'number' was declared

-- Firing with the wrong payload from the client:
--
-- BuyItemRemote:FireServer(42, 1)
--
-- Expected: Expected this to be 'string', but got 'number'

return {
    asBuyRequest = asBuyRequest,
}

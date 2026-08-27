--> A declaration, exactly as you would write one in a real place.
--
-- This is the only file of the four you write. Running
--
--   lune run remotes/tools/generate.luau -- remotes/examples/ShopRemotesSchema.luau
--
-- produces ShopRemotes.luau next to it and Remotes/*.model.json beside that.
-- All three are committed here so the whole cycle is visible without running
-- anything -- see ../README.md, "From declaration to use".
--
-- One remote per class the generator can emit, so the mapping from payload type
-- to className is shown end to end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteTypes = require(ReplicatedStorage.Libraries.RemoteTypes)

export type Remotes = {
    --[=[
        The server decides whether it can be afforded; the client is only
        expressing intent.
    ]=]
    BuyItem: RemoteTypes.ToServer<string, number>,
    StockChanged: RemoteTypes.ToClient<number>,
    GetBalance: RemoteTypes.RemoteFunction<(), (number)>,
    CrowdCheer: RemoteTypes.UnreliableToClient<number>,
}

return {}

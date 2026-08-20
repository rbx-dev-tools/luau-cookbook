-- Generated from ShopRemotesSchema.luau by luau-cookbook/remotes -- do not edit.
--
-- Add or remove a remote in ShopRemotesSchema.luau, then re-run the generator.

local ShopRemotesSchema = require(script.Parent.ShopRemotesSchema)

local remotes: ShopRemotesSchema.Remotes = {
    BuyItem = script.Parent.Remotes.BuyItem :: any,
    StockChanged = script.Parent.Remotes.StockChanged :: any,
    GetBalance = script.Parent.Remotes.GetBalance :: any,
    CrowdCheer = script.Parent.Remotes.CrowdCheer :: any,
}

return remotes

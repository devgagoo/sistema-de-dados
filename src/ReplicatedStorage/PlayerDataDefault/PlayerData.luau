local PlayerData = {}

function PlayerData.PlayerDataDefault()
    return {
        Coins = 0,
        Level = 1,
        Xp = 0,
        Version = 1,
        Inventory = {}
    }
end

return PlayerData

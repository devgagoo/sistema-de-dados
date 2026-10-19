local DadosService = require(script.Parent.DadosService)
local Players = game:GetService("Players")


local function aoEntrar(player: Player)
    DadosService:Carregar(player)
end

Players.PlayerAdded:Connect(aoEntrar)

for _, p in Players:GetPlayers() do
    aoEntrar(p)
end

Players.PlayerRemoving:Connect(function(player: Player)
    DadosService:Salvar(player)
end)

game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        DadosService:Salvar(player)
    end
end)


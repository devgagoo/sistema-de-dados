local DadosService = require(script.Parent.DadosService)
local Players = game:GetService("Players")




local INTERVALO_AUTOSAVE = 300
-- Autosave: de 5 em 5 minutos salva quem esta jogando. Chama SalvarPerfil (que NAO apaga a
-- memoria) e nao o Salvar (que e' o da saida). Com 30 jogadores da' 6 escritas por minuto,
-- contra um orcamento de 360 por minuto -- sobra folga. Os 5 minutos sao o quanto de dado o
-- jogador perde se o servidor cair.
task.spawn(function()
    while true do
        task.wait(INTERVALO_AUTOSAVE)
        for _, player in Players:GetPlayers() do
            if DadosService:TomarSessao(player) then
                DadosService:SalvarPerfil(player)
            end
            
        end
    end
end)

local function aoEntrar(player: Player)
    DadosService:Carregar(player)
end

Players.PlayerAdded:Connect(aoEntrar)

for _, p in Players:GetPlayers() do
    aoEntrar(p)
end


Players.PlayerRemoving:Connect(function(player : Player) 
   DadosService:Salvar(player)
end)



-- No fechamento o Roblox da' so 30 segundos. Um por um, com ate 3s de tentativa cada, 30
-- jogadores estourariam esse tempo e quem ficasse no fim perderia os dados. Por isso todos em
-- paralelo, e o laco do fim segura o servidor ate o contador zerar.
game:BindToClose(function()
    local pendentes = #Players:GetPlayers()
    if pendentes == 0 then
        return
    end


    for _, player in Players:GetPlayers() do
        task.spawn(function()
            DadosService:Salvar(player)
            pendentes -= 1
        end)
    end

    while pendentes > 0 do
        task.wait(0.1)
    end
end)


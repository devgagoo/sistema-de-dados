-- DadosService: guarda o perfil de cada jogador na memoria do servidor e conversa com o
-- DataStore (o banco do Roblox). O resto do jogo le o perfil por aqui.

local DataStoreService = game:GetService("DataStoreService")

-- O molde do perfil (os campos que todo jogador tem) vem desse modulo.
local PlayerData = require(game.ReplicatedStorage.PlayerDataDefault.PlayerData)

local DataStore = DataStoreService:GetDataStore("PlayerData")

local Dados = {}
Dados._perfis = {}   -- memoria do servidor: [jogador] = perfil


function Dados:Get(player: Player)
    return self._perfis[player]
end

-- A chave tem que ser unica por jogador. UserId serve porque e' fixo (o nome o jogador troca
-- quando quer), e o prefixo "User_" separa essas chaves de qualquer outra coisa nesse banco.
local function chaveDe(player: Player)
    return "User_"..player.UserId
end

-- Quanto esperar antes de tentar de novo.
-- Regra: orcamento zerado quer dizer que o problema NAO e' o tempo, e' o meu ritmo -- eu pedi
-- demais pro Roblox e ele comecou a barrar. Insistir rapido so piora. Entao espera o teto (8).
-- Com orcamento sobrando, segue a espera normal que o Try calculou.
local function esperaSugerida(orcamento, esperaNormal)
    if orcamento <= 0 then
        return 8

    else
        return esperaNormal
    end
end


-- Tenta ate N vezes. Devolve (true, resulcontado) se seguir e (false, motivo) se desistir.
-- Desiste antes do fim por um motivo so: erro que nao passa com o tempo (ninguem esta la pra
-- consertar naquele instante). Fora isso, gasta todas as tentativas.
-- "tipo" diz de qual orcamento estamos falando: GetAsync e SetAsync tem orcamentos separados.
local function Try(maxTentativas, tipo, fazer)
    local espera = 1
    local ultimoErro = nil
    local errocrucial = "Studio access to APIs is not allowed"


    for tentativa = 1, maxTentativas do
        -- pcall: se o fazer explodir, o erro vira um valor em vez de derrubar quem chamou
        local ok, resultado = pcall(fazer)
        if ok then
            return true, resultado
        end

        ultimoErro = resultado

        -- string.find procura o pedaco DENTRO da mensagem. Nao da pra usar == porque a
        -- mensagem vem com prefixo ("Arquivo:linha: ...") e nunca ia bater igual.
        if string.find(ultimoErro, errocrucial) then
            break
        end

        -- Lido aqui dentro de proposito: esse numero muda a cada requisicao feita
        local Orcamento = DataStoreService:GetRequestBudgetForRequestType(tipo)

        -- So espera se ainda existe uma tentativa depois -- a ultima nao tem o que esperar
        if tentativa < maxTentativas then
            -- um pensa (esperaSugerida devolve o numero) e o outro age (task.wait espera)
            task.wait(esperaSugerida(Orcamento, espera))
            espera = math.min(espera * 2, 8)   -- espera crescente com teto: 1, 2, 4, 8, 8...
        end
    end
    return false, ultimoErro

end


-- Falhou de vez: chuta o jogador com um motivo que ele entende no aviso do Roblox.
-- Esta separada do Carregar de proposito -- assim da pra testar passando um jogador de
-- mentira (uma tabela com Kick) em vez de precisar de um servidor de verdade.
local function desistirCarregamento(player: Player, motivo)
    warn("O player: ",player.Name, "Foi kickado pelo motivo: ", motivo)
    player:Kick(motivo)
end

function Dados:Carregar(player: Player)

    -- 7 tentativas = ~31s de espera no pior caso (1+2+4+8+8+8).
    -- Vale insistir tanto porque ninguem esta esperando o carregamento terminar.
    local ok, carrega = Try(7,Enum.DataStoreRequestType.GetAsync, function()
        return DataStore:GetAsync(chaveDe(player))
    end)

    if not ok then
        desistirCarregamento(player, carrega)
        return
    end

    -- Sem dado salvo (jogador novo) = comeca com o perfil padrao
    self._perfis[player] = carrega or PlayerData.PlayerDataDefault()
    print("Carregou", player.Name, "|", self._perfis[player])   -- print de debug, pode tirar depois
end


function Dados:Salvar(player: Player)
    local perfil = self:Get(player)

    -- Protecao importante: quem nao conseguiu carregar nao tem perfil aqui, e salvar sem
    -- perfil ia sobrescrever os dados de verdade do jogador com nada. Melhor nao salvar.
    if not perfil then
        return
    end

    -- So 3 tentativas = ~3s. O jogador ja saiu e o servidor pode estar fechando: na saida,
    -- segurar quem esta indo embora e' pior do que salvar mal.
    -- SetAsync cai no orcamento de "SetIncrementAsync" (todos os tipos de escrita dividem ele).
    local ok, erro = Try(3, Enum.DataStoreRequestType.SetIncrementAsync, function()
        -- O {player.UserId} amarra os dados ao jogador: e' assim que o Roblox sabe o que
        -- apagar se o jogador pedir pra remover tudo dele.
        DataStore:SetAsync(chaveDe(player), perfil, {player.UserId})
    end)

    if not ok then
        warn("Falhou ao salvar os dados de", player.Name, erro)
    else
        print("Salvou os dados de", player.Name)   -- print de debug, pode tirar depois
    end

    self._perfis[player] = nil   -- libera a memoria: esse perfil nao mora mais aqui

end

return Dados

-- DadosService: guarda o perfil de cada jogador na memoria do servidor e conversa com o
-- DataStore (o banco do Roblox). O resto do jogo le o perfil por aqui.

local DataStoreService = game:GetService("DataStoreService")

-- O molde do perfil (os campos que todo jogador tem) vem desse modulo.
local PlayerData = require(game.ReplicatedStorage.PlayerDataDefault.PlayerData)

local DataStore = DataStoreService:GetDataStore("PlayerData")
local DataStoreLock = DataStoreService:GetDataStore("SessionLock")

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

local function chaveLock(player: Player)
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

local LOCK_DURACAO = 1800

local function decidirLock(antigo, meuJobId, agora)

    if antigo == nil then
        return {jobId = meuJobId, tempo = agora}
    end

    if antigo.jobId == meuJobId then
        return {jobId = meuJobId, tempo = agora}
    end

    if agora - antigo.tempo >= LOCK_DURACAO then
        return {jobId = meuJobId, tempo = agora}
    end
   
   return nil
end


function Dados:TomarSessao(player) 
    local chavelock = chaveLock(player)

    local resultado

    local ok = pcall(function()
        resultado = DataStoreLock:UpdateAsync(chavelock, function(antigo) 

            return decidirLock(antigo, game.JobId, os.time())
        end)
    end)

    if not ok or resultado == nil then
        return false
    end

    return true

end

local function SoltarSessao(player)
    local chavelock = chaveLock(player)

    local ok, erro = pcall(function()
        DataStoreLock:RemoveAsync(chavelock)
    end)

    if not ok then 
        warn("Não consegui soltar a sessao de", player.Name, erro)
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

-- O UpdateAsync nao recebe um valor, recebe uma funcao: e ele quem a chama, passando o
-- que esta no banco (o "antigo"), e grava o que ela devolver. Por isso a transformar e
-- uma fabrica: voce a chama uma vez com o perfil da memoria e ela devolve a peca que o
-- UpdateAsync vai chamar. Hoje a peca ignora o antigo e devolve o nosso perfil; o antigo
-- so entra em jogo no passo 4 (sessao dupla), quando dois servidores salvam o mesmo jogador.
local function transformar(perfilNovo)
   return function(antigo)
        return perfilNovo
   end
end

-- Falhou de vez: chuta o jogador com um motivo que ele entende no aviso do Roblox.
-- Esta separada do Carregar de proposito -- assim da pra testar passando um jogador de
-- mentira (uma tabela com Kick) em vez de precisar de um servidor de verdade.
local function desistirCarregamento(player: Player, motivo)
    warn("O player: ",player.Name, "Foi kickado pelo motivo: ", motivo)
    player:Kick(motivo)
end




function Dados:Carregar(player: Player)

    
    
    if not self:TomarSessao(player) then
        desistirCarregamento(player, "Não consegui carregar seus dados agora. Tente de novo em alguns segundos")
        return
    end
    
    
    -- 7 tentativas = ~31s de espera no pior caso (1+2+4+8+8+8).
    -- Vale insistir tanto porque ninguem esta esperando o carregamento terminar.
    local ok, carrega = Try(7,Enum.DataStoreRequestType.GetAsync, function()
        return DataStore:GetAsync(chaveDe(player))
    end)

    if not ok then
        SoltarSessao(player)
        desistirCarregamento(player, carrega)
        return
    end

    -- Sem dado salvo (jogador novo) = comeca com o perfil padrao
    self._perfis[player] = carrega or PlayerData.PlayerDataDefault()
    print( "Carregou", self._perfis[player])   
end



function Dados:SalvarPerfil(player, banco)
    banco = banco or DataStore

    local perfil = self:Get(player)
    if not perfil then return false end 

   
      
    -- So 3 tentativas = ~3s. Quem chama pode ser a saida do jogador (o servidor pode estar
    -- fechando) ou o autosave de 5 em 5 minutos: segurar e' pior do que salvar mal.
    -- UpdateAsync em vez de SetAsync: o SetAsync escreve por cima as cegas, e dois servidores
    -- salvando o mesmo jogador se atropelavam. Aqui o Roblox entrega o que esta no banco pra
    -- nossa funcao e grava o que ela devolver.
    -- Se a funcao devolver nil, o UpdateAsync CANCELA o save: nao da erro, nao apaga, nao cria
    -- nada, e o Try acha que deu certo. Por isso a transformar nunca devolve nil.
    -- O {player.UserId} do SetAsync nao cabe aqui (o UpdateAsync nao aceita): ele marcava os
    -- dados como do jogador, pra ele pedir pra apagar (GDPR). Decisao: aceito perder essa marca,
    -- porque a seguranca contra varios servidores escrevendo vale mais.
    -- O "banco" e' um parametro pra poder trocar por um banco de mentira no teste; sem ele,
    -- usa o DataStore de verdade.
    local ok, erro = Try(3, Enum.DataStoreRequestType.SetIncrementAsync, function()
        banco:UpdateAsync(chaveDe(player), transformar(perfil))
    end)

    if not ok then
        warn("Salvamento de perfil falhou", erro)
    end
    
   return ok
    


end

function Dados:Salvar(player: Player)
  self:SalvarPerfil(player)
  SoltarSessao(player)
  self._perfis[player] = nil
end

return Dados

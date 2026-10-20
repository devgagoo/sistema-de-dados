# Sistema de Dados (DataStore)

Perfil do jogador guardado no **DataStore** (o banco de dados do Roblox): carrega quando o jogador
entra no jogo e salva quando ele sai ou quando o servidor fecha.

## Onde cada arquivo vai no Roblox

| Arquivo | Lugar no Roblox | Tipo |
|---|---|---|
| `DadosService.luau` | `ServerScriptService/Dados` | ModuleScript |
| `IniciarDados.server.luau` | `ServerScriptService/Dados` | Script |
| `PlayerData.luau` | `ReplicatedStorage/PlayerDataDefault` | ModuleScript |

O `IniciarDados` é quem dá a partida: `PlayerAdded` carrega, `PlayerRemoving` e `BindToClose`
salvam. O resto do jogo **nunca** fala com o DataStore direto — pede para o `DadosService`.

## Como funciona

**Carregar** (`Dados:Carregar(player)`)

- Antes de qualquer leitura, **toma a sessão** do jogador (ver a seção do lock abaixo). Se não
  conseguir, o jogador é kickado sem nem tentar carregar.
- Lê a chave `User_<UserId>` do DataStore (UserId em vez do nome, porque nome o jogador troca).
- Sem dado salvo (jogador novo) = começa com o perfil padrão do `PlayerData`.
- Insiste até 7 vezes com espera crescente: 1, 2, 4, 8, 8, 8 segundos (~31s no pior caso),
  porque ninguém está esperando o carregamento acabar.
- Erro que o tempo não conserta (ex.: "Studio access to APIs is not allowed") não é repetido —
  não adianta tentar de novo.
- Se falhar de vez, o jogador é **kickado** com o motivo, em vez de entrar num jogo sem dados.
  Como a sessão já tinha sido tomada, o lock é **apagado antes do kick** — se ficasse lá, o
  jogador não conseguiria entrar de novo por 30 minutos.

**Salvar** (`Dados:Salvar(player)`)

- Só 3 tentativas (~3s): na saída, segurar quem está indo embora é pior do que salvar mal.
- Quem não conseguiu carregar **não** é salvo (senão salvaria vazio por cima dos dados de verdade).
- Usa `UpdateAsync`: o Roblox entrega o que está no banco para a função e grava o que ela
  devolver. Dois servidores salvando o mesmo jogador deixam de se atropelar.
- Perda consciente: o `{player.UserId}` do `SetAsync` (a marca que deixa o jogador pedir para
  apagar os próprios dados) não existe no `UpdateAsync`. A proteção contra duas sessões valeu mais.

**Sessão única (lock)** — store separada `SessionLock`

Dois servidores com o mesmo jogador ao mesmo tempo corrompem o perfil: um salva por cima do
outro. O lock evita isso.

- Antes de carregar, o servidor grava na chave `User_<UserId>` da store `SessionLock`:
  `{ jobId = game.JobId, tempo = os.time() }` — ou seja, "quem está com o jogador e desde quando".
- Quando já existe um lock, a decisão (`decidirLock`) é uma função pura, testável sem servidor:

  | Lock encontrado | Decisão |
  |---|---|
  | vazio | **toma** (grava o seu) |
  | é do meu servidor | **mantém** (só atualiza o `tempo`) |
  | de outro servidor, **vencido** (>= 30 min) | **toma** (o dono anterior morreu) |
  | de outro servidor, **recente** | **cancela** (`nil`) — o jogador está em outro servidor |

- Devolver `nil` para o `UpdateAsync` **cancela** a escrita: nada é gravado e o jogador é kickado.
- Ao sair do jogo, o lock é apagado (`RemoveAsync`). Se o servidor **cair**, ninguém apaga — por
  isso existe a validade de 30 minutos (`LOCK_DURACAO`): o próximo servidor encontra o lock
  vencido e toma para si, em vez de deixar o jogador travado para sempre.

**Espera inteligente**: antes de tentar de novo, o código olha o
`GetRequestBudgetForRequestType` (o "orçamento" de requisições que o Roblox dá por minuto).
Orçamento sobrando = a falha é do outro lado, vale insistir. Orçamento zerado = o problema é o
seu próprio ritmo, então a espera vai para o teto de 8 segundos em vez de insistir rápido.

## Para testar no Studio

Precisa ligar o acesso à API: **Game Settings → Security → Enable Studio Access to API Services**
(sem isso o DataStore recusa toda chamada).

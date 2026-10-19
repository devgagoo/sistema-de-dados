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

- Lê a chave `User_<UserId>` do DataStore (UserId em vez do nome, porque nome o jogador troca).
- Sem dado salvo (jogador novo) = começa com o perfil padrão do `PlayerData`.
- Insiste até 7 vezes com espera crescente: 1, 2, 4, 8, 8, 8 segundos (~31s no pior caso),
  porque ninguém está esperando o carregamento acabar.
- Erro que o tempo não conserta (ex.: "Studio access to APIs is not allowed") não é repetido —
  não adianta tentar de novo.
- Se falhar de vez, o jogador é **kickado** com o motivo, em vez de entrar num jogo sem dados.

**Salvar** (`Dados:Salvar(player)`)

- Só 3 tentativas (~3s): na saída, segurar quem está indo embora é pior do que salvar mal.
- Quem não conseguiu carregar **não** é salvo (senão salvaria vazio por cima dos dados de verdade).
- Usa `SetAsync` com o terceiro argumento `{player.UserId}`, que amarra os dados ao jogador.

**Espera inteligente**: antes de tentar de novo, o código olha o
`GetRequestBudgetForRequestType` (o "orçamento" de requisições que o Roblox dá por minuto).
Orçamento sobrando = a falha é do outro lado, vale insistir. Orçamento zerado = o problema é o
seu próprio ritmo, então a espera vai para o teto de 8 segundos em vez de insistir rápido.

## Para testar no Studio

Precisa ligar o acesso à API: **Game Settings → Security → Enable Studio Access to API Services**
(sem isso o DataStore recusa toda chamada).

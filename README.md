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

**Salvar** (`Dados:SalvarPerfil(player)` e `Dados:Salvar(player)`)

São duas porque "salvar" tem dois momentos diferentes:

| função | quando roda | o que faz |
|---|---|---|
| `SalvarPerfil(player)` | no autosave, de 5 em 5 minutos | grava no banco e **mantém** o perfil na memória e o lock |
| `Salvar(player)` | o jogador saiu | grava, solta o lock e **apaga** da memória |

Misturar as duas quebra o jogo: usar `Salvar` no autosave apagaria o perfil da memória e, na
rodada seguinte, não haveria mais nada para salvar — e todo `Dados:Get(player)` do jogo passaria
a devolver `nil`.

- Só 3 tentativas (~3s): na saída, segurar quem está indo embora é pior do que salvar mal.
- Quem não conseguiu carregar **não** é salvo (senão salvaria vazio por cima dos dados de verdade).
- Usa `UpdateAsync`: o Roblox entrega o que está no banco para a função e grava o que ela
  devolver. Dois servidores salvando o mesmo jogador deixam de se atropelar.
- Perda consciente: o `{player.UserId}` do `SetAsync` (a marca que deixa o jogador pedir para
  apagar os próprios dados) não existe no `UpdateAsync`. A proteção contra duas sessões valeu mais.
- `SalvarPerfil` recebe o banco como **segundo parâmetro opcional** (`banco = banco or DataStore`).
  É uma costura de teste: dá para passar um banco de mentira e verificar a gravação sem tocar no
  DataStore de verdade.

**Autosave** (o laço vive no `IniciarDados.server.luau`)

- Laço em `task.spawn`: a cada **5 minutos** (`INTERVALO_AUTOSAVE = 300`), percorre quem está
  jogando, **renova o lock** (`TomarSessao`) e grava (`SalvarPerfil`).
- Renova **antes** de gravar: o lock precisa estar válido **durante** a escrita.
- Se o `TomarSessao` devolver `false`, este servidor **não é mais dono** da sessão (outro tomou,
  achando que este tinha morrido) e **não salva** — gravar aí sobrescreveria os dados de quem
  está com o jogador agora.
- Custo: 1 escrita por jogador a cada 5 minutos. Com 30 jogadores = **6/min**, contra um
  orçamento de **360/min**.
- Os 5 minutos são a escolha de **quanto dado o jogador perde** se o servidor cair no meio.

**Fechamento do servidor** (`BindToClose`)

- O Roblox dá só **30 segundos** no fechamento. Salvar um por um, com até 3s de tentativa cada,
  estouraria o prazo com muitos jogadores — e os últimos da fila perderiam os dados.
- Por isso todos são salvos **em paralelo** (`task.spawn`) e o laço final espera o contador de
  pendentes zerar antes de deixar o servidor morrer.

**Sessão única (lock)** — store separada `SessionLock`

Dois servidores com o mesmo jogador ao mesmo tempo corrompem o perfil: um salva por cima do
outro. O lock evita isso.

- Antes de carregar, o servidor grava na chave `User_<UserId>` da store `SessionLock`:
  `{ jobId = game.JobId, tempo = os.time() }` — ou seja, "quem está com o jogador e desde quando".
- Quando já existe um lock, a decisão (`decidirLock`) é uma função pura, testável sem servidor:

  | Lock encontrado | Decisão |
  |---|---|
  | vazio | **toma** (grava o seu) |
  | é do meu servidor | **mantém** (só atualiza o `tempo`) — é assim que a renovação funciona |
  | de outro servidor, **vencido** (>= 30 min) | **toma** (o dono anterior morreu) |
  | de outro servidor, **recente** | **cancela** (`nil`) — o jogador está em outro servidor |

- Devolver `nil` para o `UpdateAsync` **cancela** a escrita: nada é gravado e o jogador é kickado.
- Ao sair do jogo, o lock é apagado (`RemoveAsync`). Se o servidor **cair**, ninguém apaga — por
  isso existe a validade de 30 minutos (`LOCK_DURACAO`): o próximo servidor encontra o lock
  vencido e toma para si, em vez de deixar o jogador travado para sempre.
- **O lock é renovado a cada 5 minutos** pelo autosave. Sem isso, uma sessão com mais de 30
  minutos de duração pareceria "morta" e outro servidor tomaria a sessão com o dono ainda vivo —
  exatamente a corrida que o lock existe para evitar. Com a renovação, "vencido" significa de
  verdade "esse servidor parou de falar comigo há 30 minutos".

**Espera inteligente**: antes de tentar de novo, o código olha o
`GetRequestBudgetForRequestType` (o "orçamento" de requisições que o Roblox dá por minuto).
Orçamento sobrando = a falha é do outro lado, vale insistir. Orçamento zerado = o problema é o
seu próprio ritmo, então a espera vai para o teto de 8 segundos em vez de insistir rápido.

## Para testar no Studio

Precisa ligar o acesso à API: **Game Settings → Security → Enable Studio Access to API Services**
(sem isso o DataStore recusa toda chamada).

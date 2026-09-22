# Portal Gestão de Pneus — Frota Destro

Sistema web interno de **gestão de pneus, frota e auditoria de sulcos** para a Comercial Destro Ltda (filiais Destro Cascavel, Destro Foz, JD Home Center e JD Konstruir). Controla o ciclo de vida completo de cada pneu — compra, montagem, vistoria, recapagem e descarte — e o mapeamento visual de eixos de cada veículo da frota.

> Este README foi escrito para servir tanto a **pessoas** (novos devs, usuários avançados) quanto a **outras IAs/assistentes** que venham a dar manutenção neste código. Ele descreve a arquitetura real encontrada no código-fonte (`index.html`), não um planejamento — sempre que o comportamento do sistema mudar, atualize este arquivo junto.

---

## 1. Visão geral da arquitetura

Este é um **aplicativo de página única (SPA)**, 100% contido em **um único arquivo `index.html`** (~9 mil linhas): HTML + Tailwind (via CDN) + CSS customizado + JavaScript puro (vanilla, sem framework, sem build step). Não há backend próprio nesse repositório — toda persistência é delegada a um webhook externo.

```
Navegador (index.html)
        │
        │  fetch() → POST JSON  { action, operator, token, timestamp, data }
        ▼
  n8n (workflow)  →  N8N_WEBHOOK_URL = https://n8n.silens.com.br/webhook/gestao-pneus
        │
        ▼
  Banco de Dados PostgreSQL (tabelas: VEICULOS, PNEUS_CADASTRO, MOVIMENTACOES,
                              VISTORIAS_PATIO, USUARIOS)
```

**Não existe roteamento de página nem API REST tradicional**: existe **um único endpoint** (`N8N_WEBHOOK_URL`), e toda operação (login, salvar pneu, editar veículo, excluir usuário etc.) é um POST para essa mesma URL com um campo `action` diferente dentro do payload. O n8n é responsável por rotear a `action` para a query/lógica correta no Postgres.

### Por que isso importa para quem for mexer no código
- Não adianta procurar por várias rotas (`/api/veiculos`, `/api/pneus`...) — é tudo a mesma URL.
- Para adicionar uma nova operação de escrita, o padrão é sempre: criar uma nova `action` string, chamar `enviarRequisicaoN8n(action, data)` (função central, ver seção 5), e implementar o tratamento dessa `action` do lado do n8n (fora deste repositório).
- O front-end **não tem validação de servidor própria** — ele confia no que o n8n/Postgres devolve (`success`, `authenticated`, `sessionExpired`, `message`).

---

## 2. Stack técnica

| Camada        | Tecnologia                                                                 |
|---------------|------------------------------------------------------------------------------|
| Markup/estilo | HTML5 + [Tailwind CSS](https://tailwindcss.com) via CDN + CSS custom em `<style>` |
| Ícones        | Font Awesome 6.4.0 (CDN)                                                     |
| Tipografia    | Google Fonts — Inter (UI) + Fraunces (títulos editoriais)                    |
| Gráficos      | [Chart.js](https://www.chartjs.org/) (custo do pneu ao longo do tempo)       |
| Excel         | [SheetJS / xlsx.full.min.js](https://sheetjs.com/) (exportação de planilhas) |
| Backend       | Webhook n8n (`N8N_WEBHOOK_URL`) → PostgreSQL                                 |
| Persistência local | `sessionStorage` (apenas sessão de login — ver seção 4)                |

Não há `package.json`, bundler ou dependências instaladas: tudo é carregado via `<script src="https://cdn...">` no `<head>`. Basta abrir o `index.html` num navegador (ou hospedá-lo em qualquer servidor estático) para rodar.

---

## 3. Modelo de dados (entidades em memória)

Todas as entidades vivem como **arrays JavaScript globais**, populados a partir do backend e mantidos em RAM durante a sessão:

| Variável global   | Entidade               | Descrição |
|--------------------|------------------------|-----------|
| `caminhoes`        | Veículos da frota       | Cadastro mestre: `frota`, `placa`, `modelo`, `tipo`, `filial`, `cnpj`, `eixos_traseiros` |
| `pneus`            | Pneus                   | Cada pneu individual: `fogo` (nº de fogo/identificação), `marca`, `medida`, `mm_atual` (sulco em mm), `status_atual`, `caminhao_atual`, `posicao_atual`, `fornecedor`, custos, dados de recapagem etc. |
| `movimentacoes`    | Lançamentos/movimentações | Histórico de cada evento do pneu (instalação, retirada, recapagem, descarte) — com KM inicial/final, sulco de entrada/saída, custo, motivo |
| `vistorias`        | Vistorias de pátio       | Registros de auditoria periódica de sulco por eixo/posição |
| `usuarios` (via `usuariosCache`) | Usuários do sistema | Login, perfil, permissões granulares |

> **Atenção:** o array `caminhoes` vem com ~150 veículos **hardcoded diretamente no HTML** como estado inicial (linha ~2057 em diante). Isso funciona como um *cache offline* mostrado antes da primeira sincronização — mas ao sincronizar (`sincronizarBancoDeDados`), a linha `caminhoes = serverData.caminhoes` **substitui tudo** pelo que vier do Postgres. Se o banco tiver dados diferentes/desatualizados em relação a esse array embutido, é o banco que prevalece assim que a sincronização ocorrer.

### 3.1 Ciclo de vida de um pneu (`status_atual`)

```
ESTOQUE ──(instalar_pneu)──► RODANDO ──(retirar_pneu p/ recapagem)──► RECAPANDO
   ▲                             │                                        │
   │                     (retirar_pneu p/ descarte)                       │
   │                             ▼                                (recapar_pneu_retorno)
   └─────────────────────── DESCARTE                                      │
   └──────────────────────────────────────────────────────────────────────┘
```

- **ESTOQUE**: disponível no galpão para montagem.
- **RODANDO**: montado em um veículo, numa posição específica (`posicao_atual`).
- **RECAPANDO**: enviado para recapagem (fora da frota).
- **DESCARTE**: baixado definitivamente (fim de vida útil).

### 3.2 Sulco (profundidade do pneu, `mm_atual`) — limites usados na UI

| Faixa           | Classificação | Cor  |
|------------------|----------------|------|
| ≥ 6.0 mm         | Bom            | verde  |
| 3.0 mm – 6.0 mm  | Atenção        | âmbar  |
| < 3.0 mm (uso interno de alerta crítico usa **≤ 4.0 mm**) | Crítico | vermelho |
| ≤ 1.6 mm         | TWI (limite legal mínimo de uso) | — |

### 3.3 Tipos de veículo e mapeamento de eixos

O campo `tipo` do veículo determina quantos **eixos traseiros** (e portanto quantas rodas) o diagrama SVG desenha:

| `tipo`       | Eixos traseiros (mínimo) | Observação |
|--------------|---------------------------|------------|
| `TOCO`       | 1                         | |
| `3/4`        | 1                         | |
| `TRUCK`      | 2                         | Tração + Truck |
| `CARROCERIA` | 3                         | Tração + Truck + 3º eixo |
| `VAN`        | especial                  | só 4 rodas, sem o grupo de eixos duplos (ver `isVan` em `carregarVeiculoVisualizer`) |

A contagem final de eixos vem de `getEixosTraseirosVeiculo(caminhao)` (por volta da linha 4400). Essa função:
1. Calcula um **piso mínimo** a partir do `tipo` (tabela acima).
2. Se o veículo tiver um `eixos_traseiros` explícito no banco (ex.: um TRUCK especial com 3 eixos), usa esse valor — mas **nunca abaixo do piso do tipo**.

> Isso foi corrigido recentemente: antes, um valor `0`/`1`/`nulo` vindo do banco sobrescrevia silenciosamente o tipo do veículo, fazendo um `TRUCK` aparecer com 1 eixo só (visual de TOCO/3-4). Se esse sintoma voltar a aparecer, o primeiro lugar a checar é a coluna `eixos_traseiros` no Postgres para aquele veículo.

---

## 4. Autenticação, sessão e permissões

- **Login**: `realizarAutenticacao()` envia `{ action: "login", data: { user, pass } }` ao n8n. O backend responde com `authenticated`/`valid`, `token`, `perfil` e `permissoes`.
- **Sessão**: guardada em `sessionStorage` (chave `aconpneus_sessao`) — **de propósito não usa `localStorage`**, para não persistir login entre reaberturas do navegador em computadores compartilhados de pátio/oficina. Recarregar a página (F5) restaura a sessão via `restaurarSessaoStorage()`; fechar a aba/navegador derruba o login.
- **Token**: todo `enviarRequisicaoN8n` reenvia o `sessionToken` salvo. Se o backend responder `sessionExpired: true`, o front chama `forcarLogoutPorSessaoExpirada()` e derruba a sessão local automaticamente.

### Perfis (`perfilLogado`)
- `administrador` — acesso total, sempre passa em `temPermissao()`.
- `operador` — acesso padrão, permissões extras controladas individualmente.
- `aprendiz` — perfil restrito (menor aprendiz); tipicamente só registra vistorias, que ficam pendentes de revisão por um operador/admin (`revisarVistoria`).

### Permissões granulares (`permissoesLogado`, checadas via `temPermissao(chave)`)
| Chave                     | Permite |
|---------------------------|---------|
| `perm_excluir_veiculo`    | Excluir veículo da frota |
| `perm_excluir_pneu`       | Excluir pneu do cadastro |
| `perm_excluir_lancamento` | Excluir uma movimentação |
| `perm_editar_lancamento`  | Editar uma movimentação |
| `perm_revisar_vistoria`   | Aprovar/reprovar vistorias feitas por aprendizes |

Criar/excluir usuário é **sempre restrito a `administrador`**, independentemente dessas checkboxes.

---

## 5. Comunicação com o backend (`enviarRequisicaoN8n`)

Função central (linha ~3513) usada por **todas as escritas** no sistema:

```js
enviarRequisicaoN8n(action, data)
// → POST N8N_WEBHOOK_URL
// body: { action, operator: usuarioLogado, token: sessionToken, timestamp, data }
```

Trata 3 cenários de resposta:
1. **HTTP não-OK** → toast de erro + log + tenta ressincronizar (dados ficam só em RAM local).
2. **HTTP OK mas `success:false`/`authenticated:false`/`valid:false`** → ação recusada pelo backend (ex.: sem permissão); se `sessionExpired:true`, força logout.
3. **HTTP OK e aceito** → segue o fluxo normal (atualiza array local, loga, sincroniza).

### `action`s existentes hoje
`login`, `sync`, `save_pneu_compra_lote`, `save_veiculo`, `editar_veiculo`, `excluir_veiculo`, `instalar_pneu`, `retirar_pneu`, `registrar_vistoria`, `registrar_vistoria_completa`, `recapar_pneu_retorno`, `editar_pneu`, `excluir_pneu`, `revisar_vistoria`, `editar_lancamento`, `excluir_lancamento`, `listar_usuarios`, `save_usuario`, `excluir_usuario`.

Para adicionar uma nova operação de escrita: escolha um novo nome de `action` (padrão `verbo_substantivo` em snake_case/português), monte o `data` necessário e chame `enviarRequisicaoN8n`. A lógica correspondente precisa ser implementada no workflow n8n (não está neste arquivo).

### Sincronização
- **Manual**: botão de sync no header (ícone que gira) chama `sincronizarBancoDeDados(true)`.
- **Automática**: `setInterval` a cada **5 minutos**, só roda se houver usuário logado (linha ~8166).
- **Silenciosa**: também é disparada depois de qualquer escrita malsucedida, como tentativa de "curar" o estado local.

---

## 6. Estrutura de telas (abas / `tab-*`)

Toda a navegação é feita trocando a classe `.active` entre `<div class="tab-pane">`, sem reload de página (`changeTab()`, linha ~3597). Os títulos editoriais de cada aba estão centralizados em `TAB_EDITORIAL_INFO`.

| Aba (id)              | Título exibido            | Função principal |
|------------------------|----------------------------|-------------------|
| `dashboard`            | Dashboard Executivo         | KPIs, pneus críticos, telemetria de frota |
| `controle-frota`       | Controle de Frota            | **Mapeamento visual em SVG** dos eixos/pneus de cada veículo (`carregarVeiculoVisualizer`) — clique numa roda abre detalhes/instalação |
| `frota`                | Frotas Cadastradas           | CRUD de veículos (grid de cards, `renderizarGridFrota`) |
| `estoque`              | Estoque & Galpão             | Inventário de pneus disponíveis, paginado, exportável |
| `cadastro`             | Entrada & Cadastro           | Registro de pneus novos: unitário, em lote (grid) ou via **XML da NF-e** (`analisarDanfeXml`), ou modo **"Entrada por Balanço"** (inventário inicial sem nota fiscal) |
| `vistorias`            | Vistoria de Sulcos           | Auditoria periódica de sulco por posição/eixo, com fluxo de revisão para vistorias de aprendiz |
| `historico`            | Histórico & Vida do Pneu     | Ficha técnica + timeline + gráfico de custo (Chart.js) de um pneu específico |
| `logs`                 | Logs de Auditoria            | Trilha de segurança e integrações (drawer lateral + painel completo) |
| `usuarios`             | Usuários & Permissões        | CRUD de usuários e permissões (só admin) |

---

## 7. Funcionalidades de destaque

- **Mapeamento visual dinâmico (SVG)**: desenha o chassi, eixo dianteiro e de 1 a 4 eixos traseiros conforme o tipo do veículo, com cada roda clicável (mostra pneu montado ou permite instalar um pneu do estoque). Cores indicam a condição do sulco.
- **Importação de NF-e (DANFE XML)**: `analisarDanfeXml()` faz parsing do XML da nota fiscal para preencher automaticamente um lote de pneus comprados. Há um fallback local de leitura (`gerarLeituraLoteLocalFallback`) se o parsing completo falhar.
- **Entrada por Balanço**: modo de cadastro rápido para pneus de saldo de estoque, sem nota fiscal (preenche fornecedor/valor/NF automaticamente como "BALANÇO").
- **Exportações**: Excel (SheetJS) e PDF para Estoque, Frota e Histórico do pneu.
- **Busca global** (atalho de teclado — `inicializarAtalhoBuscaGlobal`): pula direto para um veículo ou pneu pelo nº de frota ou de fogo.
- **Modal de confirmação genérico** (`confirmarAcao` / `modalConfirmacao`) substitui o `confirm()` nativo do navegador em todas as exclusões.
- **Tema claro/escuro**: `inicializarTema()`/`alternarTema()`, com variáveis CSS (`--paper`, `--ink`, etc.) e persistência (verificar `aplicarTema`).
- **Responsividade**: tabelas viram cards empilhados em telas < 768px (`table.responsive-table`).
- **Logs de auditoria**: toda ação relevante (criação, edição, exclusão, erro de sync) passa por `adicionarLog(tipo, mensagem, detalhe)`.

---

## 8. Convenções de código encontradas (para manter consistência)

- **Idioma**: nomes de função, variável e comentários majoritariamente em **português**; strings de UI também em português (pt-BR).
- **Prefixos de posição de roda**: `LE_`/`LD_` (Lado Esquerdo/Direito) + grupo do eixo (`DIANTEIRO`, `TRAÇÃO`, `TRUCK`, `EIXO3`, `EIXO4`) + `_INTERNO`/`_EXTERNO` para rodas duplas. Ex.: `LD_TRUCK_EXTERNO`.
- **Toasts**: `mostrarToast(title, body, type)` — `type` ∈ `primary|success|warning|error|info`.
- **Sanitização**: qualquer valor vindo do usuário/banco que vai para `innerHTML` deve passar por `escapeHtml()` antes.
- **Escritas sempre via `enviarRequisicaoN8n`**: nunca escrever direto no array local sem também notificar o backend (senão o dado "morre" no próximo `sincronizarBancoDeDados`).
- **Paginação client-side**: padrão `paginaXAtual` + `ITENS_POR_PAGINA_X` + `irParaPaginaX(pagina)` (ver Estoque e Grid de Frota).

---

## 9. Como rodar / configurar

1. Não há instalação — é um arquivo estático. Basta abrir `index.html` num navegador ou servir a pasta com qualquer servidor HTTP estático.
2. Para apontar para outro ambiente/backend, altere a constante `N8N_WEBHOOK_URL` (linha ~2052).
3. Sem esse webhook respondendo corretamente às `action`s da seção 5, o sistema roda em "modo RAM": os dados existem só na memória do navegador até a página ser recarregada.

---

## 10. Pontos de atenção / dívidas técnicas conhecidas

- **Arquivo único gigante (~9 mil linhas)**: não há separação em módulos/componentes. Qualquer IA ou dev editando deve usar busca por função/id (`grep -n "function nomeDaFuncao"`) em vez de tentar ler o arquivo inteiro de uma vez.
- **Dados de frota hardcoded como estado inicial** (seção 3): fonte da verdade real é sempre o Postgres via `sync`; o array embutido é só um cache de partida.
- **Sem testes automatizados** neste arquivo.
- **Confiança no backend**: como não há schema/validação forte no front, qualquer inconsistência de dados vinda do n8n/Postgres (campo faltando, tipo errado) tende a se propagar direto para a tela — vale sempre checar o dado bruto retornado quando algo parecer "renderizado errado" (foi exatamente o caso do bug de eixos do TRUCK, corrigido em `getEixosTraseirosVeiculo`).
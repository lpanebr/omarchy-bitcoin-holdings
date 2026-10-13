# Bitcoin Holdings para Omarchy

Plugin para acompanhar o valor de uma quantidade fixa de Bitcoin na barra do Omarchy 4. Um clique abre um painel com gráfico, variação e os períodos móveis **Semana**, **Mês**, **Ano** e **5 anos**. BRL é a moeda inicial; USD e EUR também estão disponíveis.

Na primeira execução, clique em **Configurar BTC**, informe a quantidade e salve. O campo começa vazio: nenhum saldo é presumido. São aceitos ponto ou vírgula decimal, até oito casas e zero; quantidade negativa, notação científica e separadores de milhar são rejeitados. A quantidade é armazenada em satoshis inteiros, até o limite seguro de 9.007.199.254.740.991 satoshis.

O gráfico mostra quanto **a mesma quantidade configurada valeria em cada data**. Não representa compras, aportes, saldo passado da carteira ou rentabilidade desde uma compra. Alterar a quantidade recalcula os preços já carregados; alterar a moeda busca a série correspondente. A configuração fica exclusivamente neste computador.

## Instalação

Requisitos: Omarchy 4 / Quickshell, Python 3 padrão e acesso HTTPS às APIs públicas. Validado em Omarchy **4.0.2-1**. O plugin usa o contrato `schemaVersion: 1`, entrada `bar-widget`, posição inicial à direita e os componentes nativos de tema/painel. Não altera arquivos em `/usr/share/omarchy/` nem bindings do Hyprland.

Instale diretamente do repositório:

```bash
omarchy plugin add https://github.com/lpanebr/omarchy-bitcoin-holdings.git --enable
```

Para desenvolvimento local, execute na raiz deste checkout:

```bash
omarchy plugin validate .
mkdir -p "$HOME/.config/omarchy/plugins"
ln -s "$(pwd)" "$HOME/.config/omarchy/plugins/io.github.lpanebr.bitcoin-holdings"
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.lpanebr.bitcoin-holdings --section right
```

Se o destino já existir, inspecione a instalação existente antes de criar o link. O checkout deve permanecer nesse caminho enquanto o link estiver instalado. Esta implementação foi validada por esse método. Para garantir a aplicação de alterações no checkout ligado por symlink, execute `omarchy-shell shell rescanPlugins`. O plugin não foi publicado no marketplace.

Para abrir por IPC:

```bash
omarchy-shell shell summon io.github.lpanebr.bitcoin-holdings ''
```

Para ocultar o widget: `omarchy plugin disable io.github.lpanebr.bitcoin-holdings`. A configuração e o cache permanecem disponíveis.

## Uso e teclado

- Clique no valor para abrir ou fechar. Escape ou clique fora fecha o painel.
- **Configurar** permite alterar quantidade e moeda; Enter no campo da quantidade salva.
- Tab / Shift+Tab percorrem controles; Enter ou Espaço aciona os botões.
- No gráfico, clique ou use Tab para focar. Setas esquerda/direita consultam pontos; Home/End vão ao primeiro/último. Data e valor aparecem abaixo da linha, também ao mover o mouse.
- **Atualizar** consulta cotação e período selecionado, respeitando bloqueios do provedor.
- `*` na barra e **Dados antigos** no painel indicam a última cotação válida retida após falha. Falha sem cotação anterior aparece como indisponível, sem saldo zero fictício.

## Dados e atualização

**Binance** fornece BTC/BRL e BTC/EUR; **Bitstamp** fornece BTC/USD. Todas as consultas usam pares diretos, sem chave, conta ou assinatura. USD significa dólar fiduciário, não stablecoin. A fonte e o horário do último negócio aparecem no painel; o preço pode diferir de outras corretoras e de índices agregados como o Google.

A cotação é consultada a cada cinco minutos. Ao trocar período, o gráfico mostra imediatamente o histórico salvo daquela moeda/período e consulta uma atualização em seguida. Isso também funciona após recarregar o plugin: os históricos salvos são carregados junto com a configuração. Durante a consulta aparece **Atualizando…**, ou **Dados antigos · Atualizando…** quando o cache está vencido. Sem cache para o período, aparece **Carregando…**. Se a atualização falhar, o gráfico salvo permanece.

Ao abrir o painel e nas consultas automáticas, o cache tem validade de cinco minutos para semana/mês e uma hora para ano/cinco anos. Trocar período ou atualizar manualmente solicita dados novos, respeitando o backoff do provedor. O histórico tem fechamento horário para semana/mês e diário para ano/cinco anos, incluindo o candle em andamento. Não mostra todos os extremos intradiários em uma série diária.

Os períodos terminam no instante da consulta e começam sete dias, um mês, um ano ou cinco anos civis atrás, em UTC. Datas inexistentes são ajustadas ao último dia válido: 31 de março menos um mês resulta em 28/29 de fevereiro. A exibição usa o fuso local. O painel informa o intervalo efetivamente disponível; a variação usa seu primeiro e último ponto. Percentual com denominador zero é mostrado como não aplicável. Lacunas maiores que a resolução interrompem a linha, sem interpolação.

Documentação dos provedores, limitações, termos, paginação e resultados reais: [docs/data-provider.md](docs/data-provider.md). Cinco anos em BRL, EUR e USD foram testados em 13/10/2026. A cobertura e o acesso público podem mudar, inclusive por restrições regionais. A validação comprova disponibilidade nessa data; não há garantia de serviço ou licença irrestrita para redistribuição comercial.

## Arquivos locais e privacidade

- Configuração: `${XDG_CONFIG_HOME:-~/.config}/io.github.lpanebr.bitcoin-holdings/config.json`.
- Cache de mercado e controle de tentativas: `${XDG_CACHE_HOME:-~/.cache}/io.github.lpanebr.bitcoin-holdings/`.

Arquivos são gravados atomicamente com permissão `0600`; novos diretórios usam `0700`. Nenhum arquivo de configuração ou cache é salvo no checkout. Não copie a configuração para o Git. A configuração contém quantidade e moeda; o cache contém apenas preços de mercado. As APIs recebem somente o par e os parâmetros necessários ao período, nunca quantidade ou valor do saldo.

Um helper Python persistente recebe mensagens JSON pela entrada padrão, evitando expor quantidade nos argumentos de processos e executar subprocessos por tecla. As consultas são serializadas; instâncias em múltiplos monitores compartilham cache e bloqueio. Respostas atrasadas são ignoradas se a seleção mudou. Timeout de 12 segundos, respostas até 2 MiB, até 2.000 pontos e três páginas limitam consumo. Após falhas há backoff de 30 segundos a 15 minutos; `Retry-After` maior é respeitado. O cache válido é preservado em erro, offline ou resposta inválida.

## Validação

```bash
python3 -m unittest discover -s tests -v
qmllint -I /usr/share/omarchy/shell plugin/*.qml
omarchy plugin validate .
bash tests/run-qml-smoke.sh
```

O teste QML precisa de uma sessão Wayland e usa arquivos temporários, quantidade fictícia e bloqueio de rede isolado. Ele não acessa a configuração real. Os testes cobrem precisão, persistência, intervalos móveis, paginação, moeda incorreta, cache, offline, timeout, resposta inválida, 429 e redução de pontos sem perder extremos. A validação visual foi feita no desktop com a configuração inicial real e uma prévia de teste separada para o gráfico.

Para repetir a sondagem pública dos provedores: `python3 tools/probe_provider.py`. Ela não lê a configuração pessoal e atualiza apenas os resultados de mercado em `docs/provider-validation.json`.

Especificação e critérios de aceite: [SPEC.md](SPEC.md) e [issue #1](https://github.com/lpanebr/omarchy-bitcoin-holdings/issues/1).

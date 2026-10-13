# Implementar Bitcoin Holdings para Omarchy 4

## Objetivo

Criar um plugin pequeno para Luciano acompanhar quanto sua quantidade fixa de BTC vale na moeda escolhida. A barra mostra o valor total; um clique abre um gráfico com seleção de período. O usuário não pretende negociar Bitcoin nem gerenciar uma carteira de investimentos.

Nome do repositório: `omarchy-bitcoin-holdings`.
ID proposto do plugin: `io.github.lpanebr.bitcoin-holdings`.
Plataforma: Omarchy 4 (Quattro), Omarchy Shell / Quickshell.

Este repositório contém apenas a especificação inicial. Implementar em uma próxima sessão de agente dentro deste repositório.

## Experiência esperada

1. Na primeira execução, solicitar quantidade de BTC e moeda; a moeda começa em BRL e a quantidade fica vazia.
2. Após salvar, mostrar na barra um ícone de Bitcoin e o valor total na moeda escolhida, por exemplo `₿ R$ 1.234,56`. Esse valor é apenas ilustrativo.
3. Ao clicar, abrir um painel ancorado na barra, integrado ao tema atual.
4. No painel, mostrar quantidade configurada, valor total atual, horário da última atualização e gráfico de linha.
5. Oferecer botões `Semana`, `Mês`, `Ano` e `5 anos`. O período inicial é `Mês`.
6. Permitir editar quantidade e moeda em uma seção de configuração acessível no painel.
7. Fechar com Escape ou clique fora. Disponibilizar atualização manual e navegação por teclado.

## Configuração e cálculos

- Apenas duas configurações de produto: quantidade de BTC e moeda.
- Aceitar quantidade decimal com até oito casas, com vírgula ou ponto; rejeitar valores negativos, não finitos, caracteres indevidos e precisão superior a oito casas.
- Armazenar a quantidade em satoshis inteiros, verificando limites seguros da implementação; converter para BTC apenas para cálculo e exibição.
- Zero é uma configuração válida; ausência de configuração deve mostrar `Configurar BTC`, sem inventar saldo.
- BRL é o padrão. Incluir ao menos BRL, USD e EUR, desde que suportadas pelo provedor validado; listar apenas moedas realmente suportadas.
- Valor atual = quantidade fixa de BTC × cotação atual de BTC na moeda selecionada.
- Valor de cada ponto do gráfico = a mesma quantidade fixa de BTC × cotação histórica naquela moeda e data.
- O gráfico mostra quanto a quantidade configurada valeria em cada data. Não representa saldo histórico real, compras, aportes ou rentabilidade desde uma compra.
- Para conversão indireta, usar a taxa de câmbio histórica da data de cada ponto; não converter todo o passado pelo câmbio de hoje.
- Mudança da quantidade recalcula os valores sem solicitar novamente o mesmo histórico. Mudança da moeda invalida a cotação em exibição até haver dados correspondentes; nunca rotular dados de uma moeda como outra.

## Gráfico

- Linha simples de valor total, sem candles, indicadores de trading ou livro de ofertas.
- Eixo temporal e valores legíveis, moeda explícita e detalhe de data/valor ao apontar para um ponto, com alternativa por teclado.
- Períodos móveis até agora: semana = últimos 7 dias; mês = desde a mesma data do mês anterior; ano = desde a mesma data do ano anterior; cinco anos = desde a mesma data cinco anos atrás. Ajustar para o último dia válido quando necessário (por exemplo, 31 de março → 28/29 de fevereiro). Documentar limites e fuso usados.
- Escolher resolução adequada ao período: dados horários para períodos curtos quando disponíveis, diários para períodos longos. Reduzir pontos para renderização sem perder extremos relevantes.
- Tratar série vazia, um único ponto, valor constante, timestamps duplicados e lacunas. Ordenar e validar os dados; não inventar pontos nem esconder lacunas relevantes.
- Exibir variação monetária e percentual entre o primeiro e o último ponto disponível, indicando o intervalo efetivamente coberto; tratar denominador zero.

## Fonte de dados: primeira etapa obrigatória

Antes de implementar a interface, verificar e documentar uma API pública adequada para cotação atual e histórico de cinco anos, incluindo BRL. Preferir uso sem conta, chave ou assinatura, pois a proposta exige somente quantidade e moeda na configuração.

A pesquisa inicial não definiu o provedor. CoinGecko é uma referência possível, mas seu plano público limita o histórico a 365 dias; portanto não atende sozinho ao requisito de cinco anos. Referência oficial consultada em 2026-10-13: https://support.coingecko.com/hc/en-us/articles/4538747001881-What-granularity-do-you-support-for-historical-data

O agente deve verificar documentação atual, limites, termos de uso, cobertura real, moedas, paginação e qualidade do histórico; testar respostas reais para BTC/BRL nos quatro períodos e registrar o resultado em `docs/data-provider.md`.

Não assumir que uma API gratuita fornece cinco anos. Se nenhuma opção adequada atender sem credenciais ou custo, apresentar a limitação e uma decisão concreta ao usuário antes de reduzir o escopo ou introduzir assinatura/configuração adicional. Não recorrer silenciosamente a scraping ou endpoints não documentados.

## Atualização, persistência e falhas

- Atualizar a cotação aproximadamente a cada cinco minutos, respeitando limites e instruções do provedor.
- Buscar histórico ao abrir o painel ou trocar período; reaproveitar cache por moeda e período, com validade documentada.
- Salvar configuração e cache fora do checkout, em caminhos XDG apropriados, documentados no README.
- Quantidade de BTC e configuração permanecem locais. Enviar ao provedor apenas o ativo, a moeda e o intervalo necessários.
- Mostrar a fonte e o instante da última cotação. Distinguir carregamento, dados antigos, offline e indisponibilidade.
- Reter o último dado válido em falhas e identificá-lo como antigo. Não substituir falha por saldo zero.
- Implementar timeout, validação de resposta, backoff limitado e respeito a `Retry-After` para 429.
- Limitar tamanho de respostas/cache e chamadas concorrentes. Ignorar respostas antigas após mudança de moeda ou período.
- Sem subprocesso ou requisição por tecla. Se houver helper, preferir Python padrão com argumentos estruturados, sem montagem de shell.

## Integração

- Usar o contrato de plugins da instalação atual e um `manifest.json` com entrada `bar-widget` e posição padrão à direita.
- Consultar exemplos locais como `omarchy-rpn-calc`, `omarchy-books` e `omarchy-tuxedo-todo` para tema, painel e interação; não copiar funcionalidades alheias ao escopo.
- Fornecer instruções de instalação somente quando houver plugin funcional.
- Validar manifest e QML, carregar no Omarchy Shell, verificar logs e realizar teste visual real.
- Não precisa alterar bindings do Hyprland nem arquivos do repositório dotfiles para este MVP.

## Fora do escopo

- Compra e venda, saldo via carteira/corretora, autenticação e chaves privadas.
- Outras criptomoedas, múltiplas contas, ledger, custo de aquisição, impostos e alertas.
- Indicadores de mercado, sentimento, previsões e recomendações de investimento.

## Critérios de aceite

- [ ] Provedor documentado e testado com cotação atual e histórico real de cinco anos em BRL.
- [ ] Configuração inicial pede quantidade; BRL é padrão; valores inválidos não são salvos.
- [ ] Quantidade e moeda sobrevivem ao reinício e não aparecem em arquivos versionados ou requisições.
- [ ] Barra exibe o valor total configurado, com formatação monetária correta.
- [ ] Clique abre painel e os quatro períodos exibem a série correspondente com datas e moeda claras.
- [ ] Quantidade alterada recalcula barra e gráfico; moeda alterada busca dados corretos.
- [ ] Cache, offline, timeout, resposta inválida e 429 preservam dados válidos e mostram estado correto.
- [ ] Respostas atrasadas não sobrescrevem a seleção atual; lacunas não viram dados fictícios.
- [ ] Testes relevantes cobrem precisão/validação, cálculos, moeda histórica, intervalos e falhas do provedor.
- [ ] Manifest e QML validados; painel e tema conferidos no desktop, sem erros QML.
- [ ] README final explica configuração, fonte, atualização, histórico hipotético da quantidade fixa e instalação.

## Ordem de implementação sugerida

1. Validar o provedor e a cobertura de dados.
2. Implementar modelo, configuração, cache e testes relevantes.
3. Implementar widget, painel, gráfico e configuração.
4. Integrar e testar visualmente no Omarchy Shell.
5. Atualizar README com instruções reais e registrar a validação no issue.

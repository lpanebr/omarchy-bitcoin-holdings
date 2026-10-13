# Validação da implementação

Executada em 13/10/2026, Omarchy 4.0.2-1.

- Provedores pesquisados e sondados antes da interface: cotação atual e quatro períodos para BRL, EUR e USD, incluindo cinco anos completos em BRL.
- Helper implementado: quinze consultas reais aprovadas (três cotações e doze históricos), com cache temporário. [Resultado](runtime-validation.json).
- Testes Python: precisão em satoshis, validação, cálculo decimal, persistência e permissões, privacidade de requisições, períodos móveis, paginação, moedas incorretas, cache, backoff, offline, timeout, respostas inválidas e `Retry-After`.
- Teste QML isolado com os componentes reais do Omarchy: primeira execução vazia, rejeição de quantidade inválida, salvamento de quantidade fictícia/zero, formatação, redução mantendo extremos e rejeição de respostas atrasadas/de outra moeda ou período.
- `qmllint` e `omarchy plugin validate .`: aprovados.
- Desktop real: widget instalado por symlink à direita, painel inicial conferido, sem erros QML atribuídos ao plugin. Gráfico de mês e cinco anos inspecionado visualmente em host temporário com configuração fictícia identificada e separada. Semana/ano/cinco anos carregaram as séries correspondentes nesse host; Escape fechou o painel.
- Luciano informou que adicionou sua quantidade e mudou a posição do widget, e que tudo parece funcionar. A quantidade pessoal não foi lida nem registrada neste relatório.

Configuração real permanece fora do checkout. Capturas de desktop ficam apenas em `/tmp`; não são artefatos versionados. Não houve publicação no marketplace nem release. Após a validação e o ajuste de cache, Luciano autorizou commit, push e fechamento do issue.

## Troca de período com cache imediato

Ajuste solicitado após o uso inicial: os históricos persistidos são carregados junto com a configuração e mantidos em memória por moeda/período. A troca mostra o gráfico salvo imediatamente e solicita dados novos em seguida, respeitando backoff. Dados vencidos ficam identificados durante a consulta. Sem cache para o período, a interface mostra carregamento; falha preserva a série salva.

14 testes Python aprovados, incluindo restauração de todos os períodos vencidos sem rede e rejeição de cache de outra moeda. Teste QML cobre cache mostrado de forma síncrona, atualização agendada, cache vencido, trocas rápidas, resposta atrasada, falha preservando série e período sem cache. `qmllint` aprovado.

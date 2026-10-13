# Fontes de dados validadas

Validação executada em 13/10/2026, antes da interface. O resultado completo está em [provider-validation.json](provider-validation.json); repetir com `python3 tools/probe_provider.py` (somente consultas públicas, sem quantidade de BTC).

## Decisão

Usar pares reais de Bitcoin contra moeda fiduciária: Binance BTCBRL/BTCEUR e Bitstamp BTCUSD. Não há conta, chave, assinatura ou conversão cambial indireta. USD não é USDT/USDC. O preço é o último negócio daquela corretora, não um índice agregado como o resultado do Google. Fontes diferentes podem ter preços diferentes.

| Moeda | Semana (horária) | Mês (horária) | Ano (diária) | Cinco anos (diária) |
|---|---:|---:|---:|---:|
| BRL | 168 | 720 | 365 | 1.826 |
| EUR | 168 | 720 | 365 | 1.826 |
| USD | 168 | 720 | 365 | 1.826 |

As doze séries responderam sem timestamps faltantes ou preços não positivos. Cinco anos exigiram duas páginas por moeda; os outros períodos, uma. BTC/BRL cobre outubro de 2021 a outubro de 2026, incluindo cotação atual. Isso comprova cobertura na data do teste, sem garantir disponibilidade futura. Uma resposta válida da corretora pode incluir candles sem negócios, com preço carregado pelo próprio provedor; não são adicionados pontos pelo plugin.

Depois da implementação, as mesmas quinze consultas (três cotações e doze históricos) passaram pelo helper real, com cache temporário: [runtime-validation.json](runtime-validation.json). Nesse resultado há 169/721/366/1.827 pontos, porque o helper atribui a cotação ao encerramento de cada candle e inclui o candle em andamento; a sondagem inicial contava pelo início do candle. Todas as respostas ficaram prontas, sem lacunas. O instante final do candle em andamento é o início da consulta, não uma previsão do fechamento futuro.

## Contratos públicos e limites

- [Binance: URLs somente de dados públicos](https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md): `https://data-api.binance.vision`, sem autenticação. Usar `/api/v3/ticker/24hr` para preço e horário do último negócio e `/api/v3/klines` para histórico. [Contrato dos endpoints](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market): até 1.000 candles por página, timestamps em milissegundos, intervalos `1h` e `1d`, UTC. Klines têm peso 2; ticker de um símbolo tem peso 2. Limites por IP podem mudar; observar 429 e `Retry-After`, sem insistir durante bloqueio.
- [Bitstamp: API pública](https://www.bitstamp.net/api/): `/api/v2/ticker/btcusd/` e `/api/v2/ohlc/btcusd/`; até 1.000 candles por página, `step=3600` ou `86400`, timestamps em segundos. Paginar com `start`; não enviar `end` junto, pois ele tem precedência. A documentação informa 400 chamadas/s e 10.000/10 minutos; o plugin fica muito abaixo disso.
- [Termos Binance](https://www.binance.com/en/terms) e [termos Bitstamp](https://www.bitstamp.net/terms-of-use/): sujeitos a alterações e restrições regionais. O plugin faz consulta local para uso pessoal; não redistribui nem hospeda os dados. A documentação Bitstamp exige acordo próprio para uso comercial dos dados. API pública não equivale a licença irrestrita ou SLA. A página dinâmica de termos Bitstamp não forneceu texto extraível neste ambiente; não afirmar permissões além das descritas na documentação pública. Marketplace e distribuição comercial não fazem parte desta implementação.

## Alternativas verificadas

- CoinGecko: o limite público de 365 dias registrado na especificação não atende cinco anos sozinho.
- CryptoCompare: teste de histórico público sem chave retornou HTTP 401.
- Mercado Bitcoin: endpoints v4 documentados de candles e tickers retornaram HTTP 403 neste ambiente. O ticker legado respondeu, mas isso não comprovou histórico suficiente. Não usado como fallback silencioso.

## Semântica, cache e limites locais

Os períodos são móveis até agora, calculados em UTC: 7 dias, um mês civil atrás, um ano civil atrás ou cinco anos civis atrás, limitando o dia ao último válido no mês de destino. Datas são apresentadas no fuso local do desktop. O histórico usa fechamento do candle, no seu horário de encerramento; o candle em andamento usa o instante da consulta. Uma resolução diária não representa os extremos intradiários. Intervalo efetivo e lacunas são mostrados, sem interpolar lacunas maiores que a resolução.

Cotação e históricos de semana/mês têm cache de cinco minutos; ano/cinco anos, uma hora. Cada cache é separado por moeda e período e contém somente preços de mercado, não saldo. Ao trocar período, o gráfico exibe imediatamente o cache disponível e depois solicita dados novos. Os históricos salvos são carregados na inicialização para evitar aguardar uma consulta em andamento antes de mostrar o cache. Trocar período ou atualizar manualmente ignora validade, mas respeita bloqueio do provedor. Última resposta válida permanece disponível como antiga se a consulta falhar.

O helper usa Python padrão, uma requisição de cada vez, timeout de 12 segundos, respostas de até 2 MiB, histórico de até 2.000 pontos e no máximo três páginas. Estado de falhas aplica backoff de 30 segundos até 15 minutos; `Retry-After` pode exigir espera maior. A configuração é local e nunca entra nos parâmetros HTTP.

# Instruções para agentes

- Ler `SPEC.md` e o issue de implementação antes de começar.
- Este é um plugin novo para Omarchy 4 / Quickshell. Não é um fork do Bitcoin Pulse.
- Usar a skill `omarchy` para integração com o desktop e verificar o contrato de plugins da versão instalada.
- Não editar arquivos empacotados em `/usr/share/omarchy/`.
- Não inventar a quantidade de BTC do usuário. A primeira execução deve pedir a configuração.
- Manter quantidade e configuração localmente; não enviá-las ao provedor de cotações nem incluí-las no Git.
- Documentação e mensagens de commit em português.
- Validar o provedor de dados e o histórico de cinco anos antes de construir a interface. Documentar limitações reais e evitar prometer dados que o plano disponível não entrega.
- Não publicar no marketplace nem criar versões de lançamento sem solicitação explícita.

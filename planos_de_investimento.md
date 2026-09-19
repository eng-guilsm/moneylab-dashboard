# 🇧🇷 Planos de Investimento e Acumulação Patrimonial MoneyLab — Arquitetura Quantitativa v21.0 (Cenário B, Lotes Proporcionais, LINK e NEAR Ativos)

> *"Um ecossistema quantitativo unificado governado pelo Harmonicus e pelo Gatekeeper LabPolice, integrando 17 motores estatísticos com dimensionamento dinâmico de lotes proporcional ao patrimônio vivo, grid multi-tranche, Phase Bet Sizing por Hilbert (\(\theta_t\)), Trailing Stop por Desaceleração (\(d^2Z/dt^2\)), Ciclo Dominante \(T_0\), Cointegração Causal VECM, Difusão de Langevin com Ruído Espectral \(\sigma\), Trava 6 Breakeven Lock FIFO por Lote em Aberto, Quarentena Bruce Wayne de 12 horas, Banda Ratchet Anti-Venda de Fundo (-1,5% a -4,5%), Subtrava 2.2 Teto Global de 80% em Criptos e Altcoins, Cenário B de Corredores (USDT 40%-60% e BRL 10%-20% com Válvula de Dip Cripto Opção 2 e Varredura Anti-Ócio), Rotação para Hedges Americanos (NVDA, XLE, TLT, BITI/SH) e Acumulação Sistemática em Dólar e Ouro com Simple Earn Flexível."*

---

## 1. Diagnóstico Patrimonial e Baseline Auditada Oficial (Referência Histórica)

* **Baseline de Aportes em Espécie (SSOT Auditada):** Ponto de partida histórico auditado de **3.230,00 reais** em espécie (3.030,00 reais via depósitos bancários Fiat PIX/TED [11 ordens auditadas] + 200,00 reais via P2P/C2C Ordem `22847032801593081856` em 20/01/2026). Novos aportes de capital injetados via PIX ou P2P expandem essa base de cálculo dinamicamente sem valores nominais fixos.
* **Patrimônio Total em Custódia Real (Valuation Dinâmico Multi-Wallet):** Apurado em tempo real somando Spot (deduplicado de LD*), Simple Earn flexível e Funding, sem limites artificiais fixos. Todas as travas de alocação, corredores e lotes operam como **percentuais estritos do patrimônio consolidado vivo**.
* **Classificação Estrutural de Ativos:**
  * **Criptos e Altcoins (Teto Global de 80%):** `BTC`, `ETH`, `SOL`, `LINK`, `BNB`, `ADA`, `NEAR`, `AVAX`, `DOGE`.
  * **Não-Cripto / Hedges / Moeda Fiduciária (100% Isentos do Teto Cripto):** `BRL` (Caixa), `USDT` (Dólar/FX), `PAXG` (Ouro Físico LBMA) e Ativos TradFi US (`NVDA`, `XLE`, `TLT`, `BITI`, `SH`, `SP500`, `WTI`).

---

## 2. A Matriz dos 17 Motores Quantitativos & Classificação Tecnológica de Camadas (Versão 21.0 Oficial)

Cada um dos 17 motores opera sob isolamento estatístico, governado pelo Gatekeeper LabPolice com dimensionamento proporcional de lote:
* **Camada A:** **Z-Score Composto (\(Z_{\text{comp}}\))** — Fusão multi-escala intradiária rápida com ressonância macro de Fourier (6h a 72h).
* **Camada B:** **Aceleração Cinemática (\(d^2Z/dt^2\))** — Acelerômetro de segunda derivada que veta compras precoces em vales e dispara saídas na exaustão.
* **Camada C:** **VECM / Equação de Langevin com Ruído Espectral (\(\sigma\))** — Correção de erros cointegrada com o Bitcoin e previsor de vale de 6 horas (\(\Delta P \le -3\%\)).
* **Camada D:** **Blindagem de Crise & Quarentena** — Quarentena antitransbordo de 12 horas e Banda Ratchet (-1,5% a -4,5%).
* **Camada E:** **Hedge Macro TradFi & Alfa Descorrelacionado** — Operação em Backed Equities Spot na Binance (`NVDABUSDT`, `SPYBUSDT`, `SQQQBUSDT`) com opções diretas em Dólar USDT e Reais BRL.
* **Camada F:** **Coordenação Anti-Canibalização Flecha vs Escudo** — Subtrava 2.3 impedindo compras simultâneas de BTC no mesmo candle de 5 minutos (< 300s).
* **Camada G:** **Dimensionamento Proporcional Dinâmico** — Lotes calculados no tick vivo como percentual do patrimônio consolidado real.

| # | Estratégia | Par / Ativo | Alocação Base (% Patr. / Valor Ref.) | Racional Quantitativo Intradiário (Calibração 5m Empírica) | Status em Produção |
| :-: | :--- | :---: | :---: | :--- | :--- |
| **1** | **Plano Guiana Brasileira** | `PAXG <-> BTC` | **4,6%** (~150 reais) | Arbitragem de spread adaptativo desengasgada (piso BTC 30 reais). Período 60, Z <= -1,00 / Z >= +0,95, Trava 6 >= +0,40%. Lucro: **4,35 reais/mês** (Posse: 123,3h). | Ativo (Desengasgado) |
| **2** | ⭐ **Plano Escudo de Aquiles** | `BRL -> BTC` | **9,3%** (~300 reais) | Compra anti-pânico com VIX >= 21 ou Z <= -0,60, d2Z >= +0,014, Trava 6 >= +0,57%. Lucro: **1,74 reais/mês** (Posse: 176,0h, DAS Fundo 90,6%). | Ativo (+18,76 reais / DAS 90,6%) |
| **3** | ⭐ **Plano Pátria Volátil** | `BRL <-> USDT` | **8,1%** (~260 reais) | Sentinela Cambial Swing 24h: Dip Z <= -1,50, Saída Z >= +0,40, Trava 6 >= +0,40% e Simple Earn 6,88% a.a. Varredura automática de excesso de BRL > 20%. Lucro: **+7,54 a +10,45 reais/mês (+0,37% a +0,515%/m)**. | Ativo (Cenário B & Anti-Ócio) |
| **4** | 🇺🇸 ⭐ **Plano Titã do Silício** | `USDT <-> NVDAB` | **8,1%** (~260 reais / 45 USDT) | Tech Alpha intradiário Spot em NVDAB com entrada em Duplo Z (Dip 35 USDT / Crash 55 USDT). Janela 5h, Trava 6 >= +0,60%. Lucro: **+26,93 reais/mês (+1,33%/m)** (Posse: 33,6h, Ócio: 3,8h). | Ativo (Duplo Z Homologado) |
| **5** | ⭐ **Plano Ouro Líquido** | `USDT <-> PAXG` | **4,8%** (~155 reais / 30 USDT) | Arbitragem intradiária de spread adaptativo PAXG/USDT. Janela 4h, Z <= -0,50, d2Z >= +0,010, Z_out >= +0,40, Trava 6 >= +0,60%. Lote base 30 USDT. Lucro: **+4,57 reais/mês (+0,225%/m)**. Preserva corredor de ouro (Piso 10% / Teto 20%). | Ativo (Homologado) |
| **6** | 🇺🇸 🛡️ **Plano Choque Energético** | `USDT <-> XLE` | **2,8%** (~90 reais / 17 USDT) | Hedge de Petróleo/Energia (Corr: -0,35 vs BTC). Período 60, Z <= -1,17, Trava 6 >= +0,43%. Lucro: **1,48 reais/mês** (Posse: 475,5h). | Ativo (Calibrado G500) |
| **7** | ⭐ **Plano Duelo de Titãs** | `BTC -> ETH -> BRL` | **2,0%** (~65 reais) | Cointegração do ratio ETH/BTC com giro dinâmico de BTC (Modelo A: Hub de Alta Velocidade) e realização BRL. Período 12, Z <= -1,10, Trava 6 >= +0,53%. Lucro: **1,30 reais/mês** (Posse: 310,0h). | Ativo (Calibrado G500) |
| **8** | ⭐ **Plano Flecha de Sagarana** | `BRL <-> BTC` | **10,0%** (~320 reais) | Dip hunter intradiário em BTC. Período 48, Z <= -0,60, d2Z >= +0,014, Trava 6 >= +0,57%. Lucro: **1,91 reais/mês** (Posse: 176,0h). | Ativo (+8,32 reais em 10 dias) |
| **9** | ⭐ **Plano Sentinela do Sol** | `BRL <-> SOL` | **4,5%** (~145 reais) | Mean-reversion 1h (12 candles de 5m) com Inflexão Cinemática e Saída Ágil (Z <= -0,65, d2Z >= 0,0, saída Z >= +0,15, Trava 6 Breakeven Dual FIFO >= +0,50%, pré-filtro >= +0,55%). Simulação contínua 2026 (67k candles): **5,4 a 13,3 trades/mês**, lucro médio **+11,83 a +14,27 reais/mês** (+0,37% a +0,45%/mês), posse mediana reduzida para **3,6 a 5,2 horas** (queda de 88% no tempo de ócio), Win Rate **100,0%**, Drawdown Médio MTM **-2,12%** (pior histórico de posições fechadas -24,4%). Teto prudencial de 250,00 reais. | Ativo (Alta Frequência & Ágil) |
| **10** | ⭐ **Plano Sentinela de Minas** | `BRL <-> BNB` | **3,7%** (~120 reais) | Mean-reversion 1h (12 candles de 5m) e economia perpétua de 25% em taxas Binance. Z <= -0,85, d2Z >= 0,0, saída Z >= +0,15, Trava 6 Breakeven FIFO >= +0,50% e pré-filtro de margem (+0,50%). Simulação 180k candles (20,6m): **18,8 trades/mês**, lucro médio **+7,23 a +13,97 reais/mês** (+0,23% a +0,44%/mês), posse média **4,3 horas**, Win Rate **100,0%**. | Ativo (+13,97 reais / DAS 79,5%) |
| **11** | 🇺🇸 🛡️ **Plano Escudo de Washington** | `USDT <-> TLT` | **2,5%** (~80 reais / 15 USDT) | T-Bonds Soberanos de 20 anos. Flight to safety contra bear market cripto. Período 60, d2Z >= +0,015, Trava 6 >= +0,52%. Lucro: **0,23 reais/mês**. | Ativo (Hedge Soberano) |
| **12** | 🇺🇸 🐻 ⭐ **Plano Sentinela Antifrágil** | `USDT <-> SQQQB`| **8,5%** (~274 reais / 53 USDT) | Mean-reversion 1h (12 candles de 5m) com Inflexão Cinemática (\(Z \le -0,60\), \(d^2Z \ge 0,0\), gatilho secundário choque BTC \(\le -0,35\%\), saída Take Profit Trava 6 \(\ge +0,85\%\) líquido ou saída ágil \(Z \ge +0,20\) com \(\ge +0,50\%\)). Simulação empírica contínua 5m: **25,0 trades/mês**, lucro médio **+32,44 reais/mês (+1,004%/m do patrimônio total)**, ROIC sobre lote **+11,84%/m**, posse mediana **2,33 horas** (giro ultrarrápido), Win Rate **100,0%**, Drawdown Médio MTM **-1,30%** (pior -5,73%). | Ativo (Meta 1%/m Atingida) |
| **13** | 🦇 **Plano Bruce Wayne** | `Altcoins -> BRL` | 300 reais | Circuit breaker com Quarentena de 12h, janela macro 30d e VWAP. | ⏸️ **Desativado Temporariamente** |
| **14** | 🇺🇸 **Plano Sentinela Wall Street**| `USDT <-> SPYB` | **8,1%** (~260 reais / 45 USDT) | S&P 500 ETF Trust em SPYBUSDT Spot com entrada em Duplo Z (Dip 35 USDT / Crash 55 USDT). Janela 1h, Trava 6 >= +0,60%. Lucro: **+4,74 reais/mês (+0,23%/m)** (Posse: 33,6h, Ócio: 1,8h). | Ativo (Duplo Z Homologado) |
| **15** | 🎩 🚪 **Plano Adeus, Perry** | `PAXG/Legados -> USDT/BRL`| Tranche 35 USDT (~180 reais) | Desova cirúrgica de excesso de Ouro PAXG acima de 20% do patrimônio em tranches de 35 USDT (~180 reais) sob a Trava 6 Breakeven FIFO (>= +0,40% sobre VWAP de 23.576 BRL) para Dólar USDT (Simple Earn 6,88%), além de liquidação de legados. | Ativo (Desova de Excesso sob Lucro) |
| **16** | 🏺 ⭐ **Plano Caboclo dos Oráculos** | `BRL <-> LINK` | **4,5%** (~145 reais) | Mean-reversion 4h (48 candles de 5m) com Inflexão de Sagarana (Z <= -0,70, d2Z >= 0,0, saída Z >= +0,20, Trava 6 Breakeven FIFO >= +0,50% e pré-filtro de margem (+0,50%)). Simulação 180k candles (20,6m): **26,3 trades/mês**, lucro médio **+17,13 a +30,60 reais/mês** (+0,54% a +0,96%/mês), posse média **2,6 horas** (anula tempo de ócio), Win Rate **100,0%**, Correlação BTC: **0,315**. | Ativo (Homologado em Produção) |
| **17** | 🏮 ⭐ **Plano Farol de Near** | `BRL <-> NEAR` | **3,5%** (~112 reais) | Mean-reversion 6h com Inflexão de Sagarana (\(Z \le -1,00\), \(d^2Z \ge 0\), Trava 6 Breakeven FIFO Dual \(\ge +0,50\%\) e pré-filtro \(P \ge P_{\text{compra}} \times 1,006\)). Calibrado em 180k candles (20,6m). Posse relâmpago de **4,8h (anula tempo de ócio)**, menor correlação histórica com BTC (**0,267**), Win Rate: **100,0%**. Lucro: **+17,34 reais/mês (+0,54%/m)**. | Ativo (Homologado em Produção) |

---

## 3. Governança de Custódia e Travas do Gatekeeper

1. **Trava 6 (Breakeven Lock FIFO Estrita com Proteção Dual FIFO/VWAP):**
   * Nenhuma ordem de venda de rotina pode ser executada com retorno líquido inferior a **+0,40%** (ou a meta do plano, ex: **+0,50%** em NEAR, LINK e BNB) sobre a referência segura de custo: \(P_{\text{entrada}} = \max(P_{\text{FIFO}}, P_{\text{VWAP}})\). Isso blinda matematicamente a carteira contra o descasamento de execução na Binance (elimina o arrasto de taxas de corretagem e veta micro-prejuízos como o do Trade 2). Além disso, os geradores de sinal implementam pré-filtro de margem (\(P_{\text{mercado}} \ge P_{\text{compra}} \times 1,005\)) antes de emitir o gatilho.
2. **Subtrava 2.2 (Teto Global de 80% em Criptos e Altcoins):**
   * A exposição acumulada em criptos voláteis (`BTC`, `ETH`, `SOL`, `LINK`, `BNB`, `ADA`, `NEAR`) não pode ultrapassar **80% do patrimônio total consolidado**. Se ultrapassar, **qualquer nova compra de cripto é terminantemente vetada**; vendas para BRL, USDT ou PAXG permanecem 100% livres para desestocagem.
3. **Trava 2.6 & Corredor Dinâmico de Ouro (Piso 10% / Teto 20%):**
   * **Piso Estrutural Inviolável de 10% (Reserva Intocável):** Pelo menos 10% do patrimônio consolidado dinâmico permanece obrigatoriamente alocado em Ouro Físico PAXG como reserva contra choques inflacionários e cambiais. É expressamente vetada qualquer venda ou arbitragem que fure esse piso.
   * **Teto Operacional de 20%:** A exposição total em Ouro não deve exceder 20% da carteira. Frações entre 10% e 20% giram livremente nas arbitragens de spread intradiário (Guiana Brasileira e Ouro Líquido).
   * **Desova Controlada de Excesso via Adeus, Perry (SOMENTE COM LUCRO):** Quando a custódia de ouro estiver acima do teto de 20%, o `Plano Adeus, Perry` executa a poda do excedente em tranches de **35 USDT** (~180 reais) direcionadas para Dólar USDT (alimentando o Simple Earn a 6,88% a.a.), sob a condição indispensável de retorno $\ge +0,40\%$ sobre o VWAP de aquisição (23.576,00 BRL).
4. **Trava 2.7 & Corredor Dinâmico de Dólar USDT (Piso 40% / Teto 60% — Cenário B):**
   * **Piso Estrutural de 40% (Colchão Defensivo Simple Earn a 6,88% a.a.):** No mínimo 40% do patrimônio consolidado dinâmico apurado em tempo real permanece obrigatoriamente alocado em Dólar USDT (rendendo juros compostos diários). Nenhuma ordem de venda para BRL ou compra de ações pode reduzir a custódia total de USDT abaixo desse piso, **garantindo que o capital em dólares NUNCA zera**.
   * **Teto Operacional de 60%:** A exposição total em Dólar não deve exceder 60% da carteira para evitar hiperconcentração cambial. Excedentes são direcionados para realizações lucrativas em BRL via Pátria Volátil ou Alpha em ações.
   * **Resgate Cirúrgico & Sweep Automático:** Em vendas de USDT, o Gatekeeper prioriza o saldo livre na Spot e resgata do Simple Earn estritamente o déficit necessário da ordem, jamais resgatando tudo (`redeemAll`). Sobras na Spot são automaticamente varridas de volta para o Simple Earn.
5. **Trava 2.8 & Corredor Dinâmico de Caixa Fiduciário BRL (Piso 10% / Teto 20% com Válvula de Dip Cripto Opção 2 e Varredura Anti-Ócio):**
   * **Piso de Caixa de 10% (Reserva de Oportunidade Anti-Pânico):** No mínimo 10% do patrimônio consolidado permanece preservado em Reais (BRL) como amortecedor anti-pânico contra rotinas fiduciárias e dolarização automática (`BRL -> USDT` no Pátria Volátil, que nunca pode furar esse piso).
   * **Válvula Perfurável Exclusiva para Dips de Cripto (Opção 2):** Quando estratégias quantitativas autorizadas de compra em queda de criptoativos (`PLANO_FLECHA_DE_SAGARANA`, `PLANO_ESCUDO_DE_AQUILES`, `PLANO_SENTINELA_DO_SOL`, `PLANO_SENTINELA_DE_MINAS`, `PLANO_CABOCLO_DOS_ORACULOS`, `PLANO_FAROL_DE_NEAR`) identificam oportunidades reais em `BTC`, `SOL`, `BNB`, `LINK`, `ETH` ou `NEAR`, o piso de 10% torna-se operacionalmente perfurável, permitindo a utilização do caixa líquido preservado até uma margem residual de segurança de **20,00 reais** (teto notional mínimo da Binance).
   * **Teto de Caixa de 20% & Varredura Anti-Ócio:** Como o saldo em Reais na corretora tem rendimento de 0% a.a., se o caixa fiduciário exceder 20% da carteira (cenário de novos aportes como o recente de 1.000 reais), a rotina do Pátria Volátil executa varredura do excedente (`caixa_brl - 20%`) convertendo-o para USDT no Simple Earn (6,88% a.a.), eliminando o ócio financeiro.
6. **Subtrava 2.3 (Coordenação Anti-Canibalização Flecha vs Escudo):**
   * Se o Plano Flecha ou o Plano Escudo tentar comprar Bitcoin no mesmo candle de 5 minutos (< 300 segundos) em que o outro comprou, a nova entrada é automaticamente vetada para impedir sobreposição destrutiva de lotes.
7. **Quarentena Bruce Wayne (Subtrava 2.0):**
   * Após qualquer acionamento do Bruce Wayne, é decretado um **veto total de recompras daquele ativo específico por 12 horas** e congelamento de compras em Reais (`origem == 'BRL'`) para preservar o caixa líquido.
8. **Banda Ratchet Anti-Venda de Fundo:**
   * O Bruce Wayne só pode estancar perdas se o prejuízo calculado via VWAP estiver entre **-1,5% e -4,5%** e houver estresse macro comprovado (VIX >= 24 ou PC1 >= 0,40). Se a perda já for maior que **-5,0%**, a venda é vetada para evitar torrar dinheiro no fundo do poço.
9. **Regra SSOT de Deduplicação de Simple Earn & Valuation Dinâmico:**
   * O endpoint `/api/v3/account` lista Simple Earn sob o prefixo `LD*` (`LDUSDT`, `LDPAXG`, `LDLINK`). É terminantemente proibido somar `/sapi/v1/simple-earn` sem expurgar o saldo duplicado. O patrimônio consolidado é apurado dinamicamente em tempo real via API somando todas as carteiras.
10. **Realidade do Simple Earn: Dólar USDT (6,88% a.a.) vs Ouro PAXG (0,01% a.a. - Carrego Nulo):**
   * O único motor de renda passiva relevante via Simple Earn é o Dólar USDT (com taxa bonificada de 6,18% a 6,88% a.a.). O Ouro PAXG rende míseros 0,01% a.a. (apenas 0,008 reais acumulados em semanas), sendo proibido tratar Simple Earn de PAXG como mitigador de risco ou fonte de yield. Ouro gera custo de oportunidade quando retido em excesso.
11. **Auto-Resgate e Auto-Subscrição em USDT e Criptos:**
   * O sentinela `LabPolice.R` executa auto-resgate transparente antes de vendas para Reais e mantém o capital defensivo em USDT rendendo **6,88% a.a.** no Simple Earn Flexível (`USDT001`).

---

## 3.1. Matriz de Tetos de Alocação para Novos Aportes de Capital (Cenário B Oficial)

Com base nas simulações intradiárias multi-cenário realizadas sobre 153.773 candles contínuos de 5 minutos, a governança estabelece a seguinte matriz alvo para a destinação de novos aportes de capital:

| Classe de Ativo / Destino | Teto Recomendado (% do Capital) | Função Estratégica no Ecossistema |
| :--- | :---: | :--- |
| 🇺🇸 **Ações e ETFs Americanos Backed Equities** (`NVDAB`, `SPYB`, `SQQQB`, `TLT`) | **30% a 35%** | Tech Alpha de alto giro intradiário e hedges de choque macro, operados em par direto com USDT. |
| 🪙 **Criptos Voláteis** (`BTC`, `ETH`, `SOL`, `BNB`, `LINK`, `NEAR`) | **25% a 30%** | Captura de dips acelerados de mercado e arbitragem de cointegração estatística (Flecha, Escudo, Titãs, Caboclo, Near). |
| 💵 **USDT Simple Earn Flexível (Cenário B)** | **40% a 50%** | Colchão de segurança defensivo rendendo 6,88% a.a., irrigando a livre rotação de lotes americanos e blindagem cambial. |
| 🇧🇷 **Caixa BRL Spot Livre (Cenário B)** | **10% a 15%** | Liquidez imediata para compras de oportunidade intradiária com válvula de dip até 20 reais. |
| 🎟️ **BNB Fee Cushion** | **2% a 3%** | Economia perpétua de 25% em todas as taxas de corretagem da Binance. |
---

## 4. Negociação Nativa de Backed Equities na Binance Spot & Gestão de Colchão USDT

A partir de junho de 2026, a Binance disponibilizou oficialmente a negociação Spot de ações e ETFs americanos via tokens garantidos (*Backed Equities*), cotados em `USDT`. 

### Padrão Operacional Oficial de Dólar Exclusivo:
1. **Execução Direta em Dólar (`USDT <-> Ação`):**
   - As ordens de compra e venda de ativos americanos (`NVDABUSDT`, `SPYBUSDT`, `SQQQBUSDT`, `TLT`) são executadas **estritamente em Dólar (`USDT`)**, eliminando bitributação de corretagem e spread de conversão com Reais.
2. **Piso de 40% no Simple Earn Flexível (Cenário B — Reserva Intocável):**
   - É mandatório reter permanentemente no mínimo **40% do saldo total de USDT** rendendo juros compostos a **6,88% a.a.** no produto `USDT001`. Nenhuma compra de ações pode reduzir a custódia total de USDT abaixo desse piso.
3. **Livre Rotação de até 60% com Lotes Proporcionais:**
   - Até **60% do saldo de USDT** pode transitar com total autonomia entre os ativos de Tech Alpha e Hedge:
     - **Plano Titã do Silício (`NVDAB`):** Lote de **8,1%** (~45,00 USDT / ~260,00 reais) com Take Profit $\ge +0,60\%$ sob a Trava 6.
     - **Plano Sentinela Wall Street (`SPYB`):** Lote de **8,1%** (~45,00 USDT / ~260,00 reais) com Take Profit $\ge +0,60\%$ sob a Trava 6.
     - **Plano Sentinela Antifrágil (`SQQQB`):** Lote de **8,5%** (~53,00 USDT / ~274,00 reais) com Take Profit $\ge +0,85\%$ sob a Trava 6 (Meta de 1% ao mês / +32,44 reais/mês).
     - **Plano Escudo de Washington (`TLT`):** Lote de **2,5%** (~15,00 USDT / ~80,00 reais) com Take Profit $\ge +0,52\%$ sob a Trava 6.
4. **Garantia Anti-Bloqueio pelo Simple Earn:**
   - O Simple Earn NUNCA impede operações dentro do limite autorizado. O Gatekeeper `LabPolice` executa auto-resgate transparente da quantia necessária para a conta Spot segundos antes da compra, e ao realizar o lucro da venda, subscreve o saldo imediatamente de volta ao Simple Earn.

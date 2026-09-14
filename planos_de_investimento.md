# 🇧🇷 Planos de Investimento e Acumulação Patrimonial MoneyLab — Arquitetura Quantitativa v19.0 (Hedge US TradFi)

> *"Um ecossistema quantitativo unificado governado pelo Harmonicus e pelo Gatekeeper LabPolice, integrando 15 motores estatísticos com grid multi-tranche, Phase Bet Sizing por Hilbert (\(\theta_t\)), Trailing Stop por Desaceleração (\(d^2Z/dt^2\)), Ciclo Dominante \(T_0\), Cointegração Causal VECM, Difusão de Langevin com Ruído Espectral \(\sigma\), Trava 6 Breakeven Lock FIFO por Lote em Aberto, Quarentena Bruce Wayne de 12 horas, Banda Ratchet Anti-Venda de Fundo (-1,5% a -4,5%), Subtrava 2.2 Teto Global de 80% em Criptos e Altcoins, Rotação para Hedges Americanos (NVDA, XLE, TLT, BITI/SH) e Acumulação Sistemática em Dólar e Ouro com Simple Earn Flexível."*

---

## 1. Diagnóstico Patrimonial e Baseline Auditada Oficial (Referência Histórica)

* **Baseline de Aportes em Espécie (SSOT Auditada):** Ponto de partida histórico auditado de **2.230,00 reais** em espécie (2.030,00 reais via depósitos bancários Fiat PIX + 200,00 reais via P2P/C2C Ordem `22847032801593081856` em 20/01/2026). Novos aportes de capital injetados via PIX ou P2P expandem essa base de cálculo dinamicamente sem valores nominais fixos.
* **Patrimônio Total em Custódia Real (Valuation Dinâmico Multi-Wallet):** Apurado em tempo real somando Spot (deduplicado de LD*), Simple Earn flexível e Funding, sem limites artificiais fixos. Todas as travas de alocação e pisos operam como **percentuais estritos do patrimônio consolidado vivo**.
* **Classificação Estrutural de Ativos:**
  * **Criptos e Altcoins (Teto Global de 80%):** `BTC`, `ETH`, `SOL`, `LINK`, `BNB`, `ADA`, `NEAR`, `AVAX`, `DOGE`.
  * **Não-Cripto / Hedges / Moeda Fiduciária (100% Isentos do Teto Cripto):** `BRL` (Caixa), `USDT` (Dólar/FX), `PAXG` (Ouro Físico LBMA) e Ativos TradFi US (`NVDA`, `XLE`, `TLT`, `BITI`, `SH`, `SP500`, `WTI`).

---

## 2. A Matriz dos 15 Motores Quantitativos & Classificação Tecnológica de Camadas (Versão 20.0 Calibrada G500)

Cada um dos 15 motores opera sob isolamento estatístico, governado pelo Gatekeeper LabPolice:
* **Camada A:** **Z-Score Composto (\(Z_{\text{comp}}\))** — Fusão multi-escala intradiária rápida com ressonância macro de Fourier (10h a 72h).
* **Camada B:** **Aceleração Cinemática (\(d^2Z/dt^2\))** — Acelerômetro de segunda derivada que veta compras precoces em vales e dispara saídas na exaustão.
* **Camada C:** **VECM / Equação de Langevin com Ruído Espectral (\(\sigma\))** — Correção de erros cointegrada com o Bitcoin e previsor de vale de 6 horas (\(\Delta P \le -3\%\)).
* **Camada D:** **Blindagem de Crise & Quarentena** — Quarentena antitransbordo de 12 horas e Banda Ratchet (-1,5% a -4,5%).
* **Camada E:** **Hedge Macro TradFi & Alfa Descorrelacionado** — Operação em Backed Equities Spot na Binance (`NVDABUSDT`, `SPYBUSDT`, `SQQQBUSDT`) com opções diretas em Dólar USDT e Reais BRL.
* **Camada F:** **Coordenação Anti-Canibalização Flecha vs Escudo** — Subtrava 2.3 impedindo compras simultâneas de BTC no mesmo candle de 5 minutos (< 300s).

| # | Estratégia | Par / Ativo | Alocação Base | Racional Quantitativo Intradiário (Calibração G500) | Status em Produção |
| :-: | :--- | :---: | :---: | :--- | :--- |
| **1** | **Plano Guiana Brasileira** | `PAXG <-> BTC` | 150 reais | Arbitragem de spread adaptativo desengasgada (piso BTC 30 reais). Período 60, Z <= -1,00 / Z >= +0,95, Trava 6 >= +0,40%. Lucro: **4,35 reais/mês** (Posse: 123,3h). | Ativo (Desengasgado) |
| **2** | ⭐ **Plano Escudo de Aquiles** | `BRL -> BTC` | 200 reais | Compra anti-pânico com VIX >= 21 ou Z <= -0,60, d2Z >= +0,014, Trava 6 >= +0,57%. Lucro: **1,74 reais/mês** (Posse: 176,0h). | Ativo (Calibrado G500) |
| **3** | ⭐ **Plano Pátria Volátil** | `BRL <-> USDT` | 180 reais | Sentinela Cambial Swing 24h: Dip Z <= -1,50, Saída Z >= +0,40, Trava 6 >= +0,40% e Simple Earn 6,88% a.a. Lucro Homologado: **+7,54 a +10,45 reais/mês (+0,37% a +0,515%/m)** (Posse: 487,6h, Max DD MTM: -2,56%). | Ativo (Calibrado 24h) |
| **4** | 🇺🇸 ⭐ **Plano Titã do Silício** | `USDT <-> NVDAB` | 180 reais | Tech Alpha intradiário Spot em NVDAB com entrada em Duplo Z (Dip 35 USDT / Crash 55 USDT). Janela 5h, Trava 6 >= +0,60%. Lucro Homologado: **+26,93 reais/mês (+1,33%/m)** (Posse: 33,6h, Ócio: 3,8h). | Ativo (Duplo Z Homologado) |
| **5** | ⭐ **Plano Ouro Líquido** | `USDT <-> PAXG` | 155 reais | Arbitragem intradiária de spread adaptativo PAXG/USDT. Janela 4h, Z <= -0,50, d2Z >= +0,010, Z_out >= +0,40, Trava 6 >= +0,60%. Lote base 30 USDT (~155 reais). Lucro Homologado: **+4,57 reais/mês (+0,225%/m)** (Posse: 98,5h, Ócio: 4,1h). Preserva corredor dinâmico de ouro (Piso 10% / Teto 20%). | Ativo (Homologado) |
| **6** | 🇺🇸 🛡️ **Plano Choque Energético** | `USDT <-> XLE` | 90 reais | Hedge de Petróleo/Energia (Corr: -0,35 vs BTC). Período 60, Z <= -1,17, Trava 6 >= +0,43%. Lucro: **1,48 reais/mês** (Posse: 475,5h). | Ativo (Calibrado G500) |
| **7** | ⭐ **Plano Duelo de Titãs** | `BTC -> ETH -> BRL` | 65 reais | Cointegração do ratio ETH/BTC com giro dinâmico de BTC (Modelo A: Hub de Alta Velocidade) e realização BRL. Período 12, Z <= -1,10, Trava 6 >= +0,53%. Lucro: **1,30 reais/mês** (Posse: 310,0h). | Ativo (Calibrado G500) |
| **8** | ⭐ **Plano Flecha de Sagarana** | `BRL <-> BTC` | 220 reais | Dip hunter intradiário em BTC. Período 48, Z <= -0,60, d2Z >= +0,014, Trava 6 >= +0,57%. Lucro: **1,91 reais/mês** (Posse: 176,0h). | Ativo (Calibrado G500) |
| **9** | ⭐ **Plano Sentinela do Sol** | `BRL <-> SOL` | 60 reais | Mean-reversion 3h em Solana Spot (sigma 0,257%/5m). Z <= -1,15, d2Z >= +0,012, Trava 6 >= +0,75%. Lucro: **2,10 a 18,22 reais/mês** (Posse: 42,7h). Elimina ociosidade do caixa BRL. | Ativo (Calibrado G500) |
| **10** | ⭐ **Plano Sentinela de Minas** | `BRL <-> BNB` | 90 reais | Mean-reversion 15m e economia de 25% em taxas Binance. Período 36, Z <= -1,15, Trava 6 >= +0,86%. Lucro: **1,86 reais/mês**. | Ativo (Calibrado G500) |
| **11** | 🇺🇸 🛡️ **Plano Escudo de Washington** | `USDT <-> TLT` | 80 reais | T-Bonds Soberanos de 20 anos. Flight to safety contra bear market cripto. Período 60, d2Z >= +0,015, Trava 6 >= +0,52%. Lucro: **0,23 reais/mês**. | Ativo (Recalibrado) |
| **12** | 🇺🇸 🐻 **Plano Sentinela Antifrágil** | `USDT <-> SQQQB`| 90 reais | ProShares UltraPro Short QQQ Spot. Período 12, choque ret_btc_5m <= -0,35%, Trava 6 >= +0,52%. Lucro: **0,14 reais/mês** (Posse: 4,9h). | Ativo (Recalibrado) |
| **13** | 🦇 **Plano Bruce Wayne** | `Altcoins -> BRL` | 300 reais | Circuit breaker com Quarentena de 12h, janela macro 30d e VWAP. | ⏸️ **Desativado Temporariamente** |
| **14** | 🇺🇸 **Plano Sentinela Wall Street**| `USDT <-> SPYB` | 180 reais | S&P 500 ETF Trust em SPYBUSDT Spot com entrada em Duplo Z (Dip 35 USDT / Crash 55 USDT). Janela 1h, Trava 6 >= +0,60%. Lucro Homologado: **+4,74 reais/mês (+0,23%/m)** (Posse: 33,6h, Ócio: 1,8h). | Ativo (Duplo Z Homologado) |
| **15** | 🎩 🚪 **Plano Adeus, Perry** | `PAXG/Legados -> USDT/BRL`| Tranche 35 USDT | Desova cirúrgica de excesso de Ouro PAXG acima de 20% do patrimônio em tranches de 35 USDT (~180 reais) sob a Trava 6 Breakeven FIFO (>= +0,40% sobre VWAP de aquisição) para Dólar USDT (Simple Earn 6,88%), além de liquidação de legados. | Ativo (Desova de Excesso sob Lucro) |
| **16** | 🏺 🧪 **Plano Caboclo dos Oráculos** | `BRL <-> LINK` | 180 reais | Mean-reversion 10h com Inflexão de Sagarana (\(Z \le -0,80\), \(d^2Z \ge +0,010\), Trava 6 \(\ge +0,80\%\)). Lucro: **+3,49 reais/mês (+0,160%/m)** (Posse: 13,5h, 1,6 trades/mês). | 🧪 **Ativo em Simulação** |

---

## 3. Governança de Custódia e Travas do Gatekeeper

1. **Trava 6 (Breakeven Lock FIFO Soberana):**
   * Nenhuma ordem de venda de rotina pode ser enviada com retorno líquido inferior a **+0,40%** sobre o preço médio ponderado (VWAP) de aquisição do lote aberto.
2. **Subtrava 2.2 (Teto Global de 80% em Criptos e Altcoins):**
   * A exposição acumulada em criptos voláteis não pode ultrapassar **80% do patrimônio total consolidado**. Se ultrapassar, **qualquer nova compra de cripto é terminantemente vetada**; vendas para BRL, USDT ou PAXG permanecem 100% livres para desestocagem.
3. **Trava 2.6 & Corredor Dinâmico de Ouro (Piso 10% / Teto 20%):**
   * **Piso Estrutural Inviolável de 10% (Reserva Intocável):** Pelo menos 10% do patrimônio consolidado dinâmico permanece obrigatoriamente alocado em Ouro Físico PAXG como reserva contra choques inflacionários e cambiais. É expressamente vetada qualquer venda ou arbitragem que fure esse piso.
   * **Teto Operacional de 20%:** A exposição total em Ouro não deve exceder 20% da carteira. Frações entre 10% e 20% giram livremente nas arbitragens de spread intradiário (Guiana Brasileira e Ouro Líquido).
   * **Desova Controlada de Excesso via Adeus, Perry (SOMENTE COM LUCRO):** Quando a custódia de ouro estiver acima do teto de 20% (cenário histórico onde o ouro atingiu ~34,4% por compras legadas), o `Plano Adeus, Perry` executa a poda do excedente em tranches de **35 USDT** (~180 reais) direcionadas para Dólar USDT (alimentando o Simple Earn a 6,88% a.a.), sob a condição indispensável de retorno $\ge +0,40\%$ sobre o VWAP de aquisição (23.576,00 BRL). Se o mercado estiver abaixo do VWAP, o bot aguarda a recuperação ou a diluição natural por novos aportes.
4. **Subtrava 2.3 (Coordenação Anti-Canibalização Flecha vs Escudo):**
   * Se o Plano Flecha ou o Plano Escudo tentar comprar Bitcoin no mesmo candle de 5 minutos (< 300 segundos) em que o outro comprou, a nova entrada é automaticamente vetada para impedir sobreposição destrutiva de lotes.
5. **Quarentena Bruce Wayne (Subtrava 2.0):**
   * Após qualquer acionamento do Bruce Wayne, é decretado um **veto total de recompras daquele ativo específico por 12 horas** e congelamento de compras em Reais (`origem == 'BRL'`) para preservar o caixa líquido.
6. **Banda Ratchet Anti-Venda de Fundo:**
   * O Bruce Wayne só pode estancar perdas se o prejuízo calculado via VWAP estiver entre **-1,5% e -4,5%** e houver estresse macro comprovado (VIX >= 24 ou PC1 >= 0,40). Se a perda já for maior que **-5,0%**, a venda é vetada para evitar torrar dinheiro no fundo do poço.
7. **Regra SSOT de Deduplicação de Simple Earn & Valuation Dinâmico:**
   * O endpoint `/api/v3/account` lista Simple Earn sob o prefixo `LD*` (`LDUSDT`, `LDPAXG`, `LDLINK`). É terminantemente proibido somar `/sapi/v1/simple-earn` sem expurgar o saldo duplicado. O patrimônio consolidado é apurado dinamicamente em tempo real via API somando todas as carteiras.
8. **Realidade do Simple Earn: Dólar USDT (6,88% a.a.) vs Ouro PAXG (0,01% a.a. - Carrego Nulo):**
   * O único motor de renda passiva relevante via Simple Earn é o Dólar USDT (com taxa bonificada de 6,18% a 6,88% a.a.). O Ouro PAXG rende míseros 0,01% a.a. (apenas 0,008 reais acumulados em semanas), sendo proibido tratar Simple Earn de PAXG como mitigador de risco ou fonte de yield. Ouro gera custo de oportunidade quando retido em excesso.
9. **Auto-Resgate e Auto-Subscrição em USDT e Criptos:**
   * O sentinela `LabPolice.R` executa auto-resgate transparente antes de vendas para Reais e mantém o capital defensivo em USDT rendendo **6,88% a.a.** no Simple Earn Flexível (`USDT001`).

---

## 3.1. Matriz de Tetos de Alocação para Novos Aportes de Capital (Simulação Oficial 17,8m)

Com base nas simulações intradiárias multi-cenário realizadas sobre 156.356 candles contínuos de 5 minutos, a governança estabelece a seguinte matriz alvo para a destinação de novos aportes de capital:

| Classe de Ativo / Destino | Teto Recomendado (% do Capital) | Função Estratégica no Ecossistema |
| :--- | :---: | :--- |
| 🇺🇸 **Ações e ETFs Americanos Backed Equities** (`NVDAB`, `SPYB`, `SQQQB`, `TLT`) | **35% a 40%** | Tech Alpha de alto giro intradiário e hedges de choque macro, operados em par direto com USDT. |
| 🪙 **Criptos Voláteis** (`BTC`, `ETH`, `SOL`, `BNB`, `LINK`) | **20% a 25%** | Captura de dips acelerados de mercado e arbitragem de cointegração estatística (Flecha, Escudo, Titãs). |
| 💵 **USDT Simple Earn Flexível** | **20% a 25%** | Colchão de segurança defensivo rendendo 6,88% a.a., irrigando a livre rotação de lotes americanos. |
| 🇧🇷 **Caixa BRL Spot Livre** | **12% a 15%** | Liquidez imediata para compras de oportunidade intradiária sem bitributação ou fricção cambial. |
| 🎟️ **BNB Fee Cushion** | **2% a 3%** | Economia perpétua de 25% em todas as taxas de corretagem da Binance. |
| 🥇 **PAXG Ouro Físico** | **0% de novos aportes** | Diluição natural do estoque existente até a convergência para a faixa ideal de **10% (piso) a 20% (teto)**. |

---

## 4. Negociação Nativa de Backed Equities na Binance Spot & Gestão de Colchão USDT

A partir de junho de 2026, a Binance disponibilizou oficialmente a negociação Spot de ações e ETFs americanos via tokens garantidos (*Backed Equities*), cotados em `USDT`. 

### Padrão Operacional Oficial de Dólar Exclusivo:
1. **Execução Direta em Dólar (`USDT <-> Ação`):**
   - As ordens de compra e venda de ativos americanos (`NVDABUSDT`, `SPYBUSDT`, `SQQQBUSDT`, `TLT`) são executadas **estritamente em Dólar (`USDT`)**, eliminando bitributação de corretagem e spread de conversão com Reais.
2. **Piso de 30% no Simple Earn Flexível (Reserva Intocável):**
   - É mandatório reter permanentemente no mínimo **30% do saldo total de USDT** (como no snapshot de referência onde 52,05 USDT estavam retidos de um saldo total de 173,48 USDT) rendendo juros compostos a **6,88% a.a.** no produto `USDT001`.
3. **Livre Rotação de 70% com Lotes Maximizados:**
   - Os **70% restantes** transitam com total autonomia entre os ativos de Tech Alpha e Hedge:
     - **Plano Titã do Silício (`NVDAB`):** Lote de **40,00 USDT** (~205,00 reais) com Take Profit $\ge +0,90\%$ sob a Trava 6.
     - **Plano Sentinela Wall Street (`SPYB`):** Lote de **35,00 USDT** (~180,00 reais) com Take Profit $\ge +0,85\%$ sob a Trava 6.
     - **Plano Sentinela Antifrágil (`SQQQB`):** Lote de **25,00 USDT** (~128,00 reais) com Take Profit $\ge +0,90\%$ sob a Trava 6.
     - **Plano Escudo de Washington (`TLT`):** Lote de **20,00 USDT** (~102,00 reais) com Take Profit $\ge +0,80\%$ sob a Trava 6.
4. **Garantia Anti-Bloqueio pelo Simple Earn:**
   - O Simple Earn NUNCA impede operações dentro do limite livre de 70%. O Gatekeeper `LabPolice` executa auto-resgate transparente da quantia necessária para a conta Spot segundos antes da compra, e ao realizar o lucro da venda, subscreve o saldo imediatamente de volta ao Simple Earn.


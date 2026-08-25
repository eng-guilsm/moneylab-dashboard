# ==============================================================================
# LABTRADER v7.0 - MOTOR QUÂNTICO DINÂMICO & RADAR DE DISPARO (8 PLANOS)
# Alinhado com a enciclopédia quantitativa de Granger & Hatanaka (1964)
# ==============================================================================

library(httr)
library(jsonlite)
library(RSQLite)
library(dplyr)

# Carregar credenciais se disponíveis
if (file.exists("config_auth.R")) {
  tryCatch(source("config_auth.R", encoding = "UTF-8"), error = function(e) NULL)
}

# --- PARÂMETROS DE VOLUME HARMONICUS ULTRA-DEEP ---
VALOR_GUIANA_BRL   <- 150.00 # Guiana: 2 slots de R$ 150 (Teto R$ 300)
VALOR_VIX_BRL      <- 300.00 # Escudo de Aquiles: 1 slot de R$ 300
VALOR_PEG_BRL      <- 250.00 # Pátria Volátil: 2 slots de R$ 250
VALOR_LINK_BRL     <- 120.00 # Caboclo dos Oráculos: 2 slots de R$ 120 (Teto R$ 240)
VALOR_SPILL_BRL    <- 120.00 # Gravidade Zero: 2 slots de R$ 120 (Teto R$ 240)
VALOR_CORISCO_BRL  <- 100.00 # Corisco da Solana: 2 slots de R$ 100 (Teto R$ 200)
VALOR_TITAS_BRL    <- 150.00 # Duelo de Titãs: 2 slots de R$ 150 (Teto R$ 300)
VALOR_SAGARANA_BRL <- 120.00 # Flecha de Sagarana: 2 slots de R$ 120
VALOR_MIDAS_BRL    <- 50.00  # Cofre de Midas: DCA R$ 50 a cada 48h (Simple Earn)

obter_preco_binance <- function(symbol) {
  url <- paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)
  tryCatch({
    res <- GET(url, timeout(5))
    if (status_code(res) == 200) {
      return(as.numeric(content(res, "parsed")$price))
    }
  }, error = function(e) NULL)
  return(NULL)
}

obter_ultimo_vix <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT VIX_Index FROM Historico_macro WHERE VIX_Index IS NOT NULL ORDER BY Data DESC LIMIT 1;")
    if (nrow(df) > 0) return(as.numeric(df$VIX_Index[1]))
  }, error = function(e) NULL)
  return(16.09)
}

obter_ultimo_usd_comercial <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT USD_BRL FROM Historico_rapido WHERE USD_BRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1;")
    if (nrow(df) > 0) return(as.numeric(df$USD_BRL[1]))
  }, error = function(e) NULL)
  return(5.0115)
}

obter_stats_guiana_72h <- function(p_gold = 4639.0) {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL, USDTBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 4320;")
    if (nrow(df) >= 60) {
      ratios <- (df$USDTBRL * p_gold) / df$BTCBRL
      return(list(media = mean(ratios, na.rm = TRUE), sd = max(0.0001, sd(ratios, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 0.05920, sd = 0.00350))
}

obter_stats_link_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT LINKBRL FROM Historico_binance WHERE LINKBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
    if (nrow(df) >= 15) {
      return(list(media = mean(df$LINKBRL, na.rm = TRUE), sd = max(0.05, sd(df$LINKBRL, na.rm = TRUE)), serie = rev(df$LINKBRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 59.50, sd = 0.30, serie = rep(59.50, 16)))
}

obter_stats_sol_btc_72h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SOLBRL, BTCBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 4320;")
    if (nrow(df) >= 60) {
      ratios <- df$SOLBRL / df$BTCBRL
      return(list(media = mean(ratios, na.rm = TRUE), sd = max(0.00002, sd(ratios, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 0.00122, sd = 0.00008))
}

obter_stats_sol_15m <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SOLBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 30;")
    if (nrow(df) >= 5) {
      return(list(media = mean(df$SOLBRL[1:min(15, nrow(df))], na.rm = TRUE), sd = max(0.05, sd(df$SOLBRL[1:min(15, nrow(df))], na.rm = TRUE)), serie = rev(df$SOLBRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 487.50, sd = 2.50, serie = rep(487.50, 16)))
}

obter_dsp_ativo <- function(vetor_precos) {
  if (is.null(vetor_precos) || length(vetor_precos) < 6) {
    return(list(theta = 0.0, T0 = 24.0, dZ = 0.0, d2Z = 0.0))
  }
  p <- as.numeric(tail(vetor_precos, 16))
  n <- length(p)
  smooth <- mean(p[max(1, n-3):n])
  detrend <- p - smooth
  I <- detrend[n]
  Q <- (detrend[n] - detrend[max(1, n-4)]) * 0.707
  theta <- atan2(Q, I + 1e-9)
  
  dZ <- (p[n] - p[n-1]) / (p[n-1] + 1e-9)
  d2Z <- if (n >= 3) ((p[n] - p[n-1]) - (p[n-1] - p[n-2])) / (p[n-1] + 1e-9) else 0.0
  
  prev_detrend <- detrend[n-1]
  prev_Q <- (detrend[n-1] - detrend[max(1, n-5)]) * 0.707
  ang_prev <- atan2(prev_Q, prev_detrend + 1e-9)
  ang_diff <- abs(theta - ang_prev)
  if (is.na(ang_diff) || ang_diff < 0.05) ang_diff <- 0.2618
  T0 <- max(6.0, min(60.0, (2 * pi) / ang_diff))
  
  return(list(theta = theta, T0 = T0, dZ = dZ, d2Z = d2Z))
}

obter_stats_eth_btc_24h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT ETHBRL, BTCBRL FROM Historico_binance WHERE ETHBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1440;")
    if (nrow(df) >= 30) {
      ratios <- df$ETHBRL / df$BTCBRL
      return(list(media = mean(ratios, na.rm = TRUE), sd = max(0.0001, sd(ratios, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 0.03140, sd = 0.00050))
}

obter_retorno_btc_5m <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 6;")
    if (nrow(df) >= 6) {
      p_agora <- df$BTCBRL[1]
      p_passado <- df$BTCBRL[nrow(df)]
      return((p_agora / p_passado) - 1)
    }
  }, error = function(e) NULL)
  return(0.0)
}

obter_ultimo_harmonicus <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT * FROM Harmonicus_Metricas_Globais ORDER BY Data_Hora DESC LIMIT 1;")
    if (nrow(df) > 0) return(as.list(df[1, ]))
  }, error = function(e) NULL)
  return(list(Razao_Absorcao_PC1 = 0.3939, Entropia_Espectral = 1.75, Fluxo_Informacao_STE = 0.13, Energia_Wavelet_Morlet = 5.0))
}

# ==============================================================================
# EXECUÇÃO DO RADAR COMPLETO (8 MOTORES QUANT)
# ==============================================================================
executar_radar_labtrader <- function() {
  agora_ts <- Sys.time()
  agora_str <- format(agora_ts, "%Y-%m-%d %H:%M:%S")
  
  if (file.exists("solicitacao.rds")) {
    cat(sprintf("[%s] ⏳ [LABTRADER] Solicitação anterior ainda em processamento pelo LabPolice.\n", agora_str))
    return(NULL)
  }
  
  # 1. Cotações Binance em Tempo Real
  p_btc_brl   <- obter_preco_binance("BTCBRL")
  p_paxg_usdt <- obter_preco_binance("PAXGUSDT")
  p_usdt_brl  <- obter_preco_binance("USDTBRL")
  p_sol_brl   <- obter_preco_binance("SOLBRL")
  p_eth_brl   <- obter_preco_binance("ETHBRL")
  p_link_brl  <- obter_preco_binance("LINKBRL")
  
  if (is.null(p_btc_brl) || is.null(p_paxg_usdt) || is.null(p_usdt_brl)) {
    cat(sprintf("[%s] ⚠️ [LABTRADER] Cotações temporariamente indisponíveis na API.\n", agora_str))
    return(NULL)
  }
  
  p_paxg_brl   <- p_paxg_usdt * p_usdt_brl
  vix_atual    <- obter_ultimo_vix()
  usd_oficial  <- obter_ultimo_usd_comercial()
  harm_atual   <- obter_ultimo_harmonicus()
  pc1_atual    <- as.numeric(harm_atual$Razao_Absorcao_PC1)
  ent_atual    <- as.numeric(harm_atual$Entropia_Espectral)
  ste_atual    <- ifelse(!is.null(harm_atual$Fluxo_Informacao_STE) && !is.na(harm_atual$Fluxo_Informacao_STE), as.numeric(harm_atual$Fluxo_Informacao_STE), 0.0)
  w_energy     <- ifelse(!is.null(harm_atual$Energia_Wavelet_Morlet) && !is.na(harm_atual$Energia_Wavelet_Morlet), as.numeric(harm_atual$Energia_Wavelet_Morlet), 5.0)
  
  stats_guiana  <- obter_stats_guiana_72h(p_paxg_usdt)
  stats_link    <- obter_stats_link_1h()
  stats_sol_btc <- obter_stats_sol_btc_72h()
  stats_sol_15m <- obter_stats_sol_15m()
  stats_eth_btc <- obter_stats_eth_btc_24h()
  ret_btc_5m    <- obter_retorno_btc_5m()
  
  # Modulação Dinâmica de Lote Harmonicus Ultra-Deep
  fator_lote   <- ifelse(ste_atual >= 0.02 && pc1_atual <= 0.38 && w_energy < 50.0, 1.35, 
                        ifelse(w_energy >= 55.0, 0.50, 1.0))
  
  # Cálculo de Custódia e Peso de Bitcoin em Tempo Real
  df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
  saldo_btc_brl   <- 0
  saldo_caixa_brl <- 0
  saldo_paxg_brl  <- 0
  saldo_sol_brl   <- 0
  saldo_eth_brl   <- 0
  saldo_link_brl  <- 0
  saldo_usdt_brl  <- 0
  
  if (!is.null(df_w) && is.data.frame(df_w) && nrow(df_w) > 0) {
    if ("BTC" %in% df_w$asset)  saldo_btc_brl   <- sum(df_w$free[df_w$asset == "BTC"], na.rm = TRUE) * p_btc_brl
    if ("BRL" %in% df_w$asset)  saldo_caixa_brl <- sum(df_w$free[df_w$asset == "BRL"], na.rm = TRUE)
    if (any(df_w$asset %in% c("PAXG", "LDPAXG"))) saldo_paxg_brl <- sum(df_w$free[df_w$asset %in% c("PAXG", "LDPAXG")], na.rm = TRUE) * p_paxg_brl
    if ("SOL" %in% df_w$asset)  saldo_sol_brl   <- sum(df_w$free[df_w$asset == "SOL"], na.rm = TRUE) * p_sol_brl
    if ("ETH" %in% df_w$asset)  saldo_eth_brl   <- sum(df_w$free[df_w$asset == "ETH"], na.rm = TRUE) * p_eth_brl
    if ("LINK" %in% df_w$asset) saldo_link_brl  <- sum(df_w$free[df_w$asset == "LINK"], na.rm = TRUE) * p_link_brl
    if ("USDT" %in% df_w$asset) saldo_usdt_brl  <- sum(df_w$free[df_w$asset == "USDT"], na.rm = TRUE) * p_usdt_brl
  }
  
  total_patrimonio_est <- saldo_caixa_brl + saldo_btc_brl + saldo_paxg_brl + saldo_sol_brl + saldo_eth_brl + saldo_link_brl + saldo_usdt_brl
  peso_btc <- ifelse(total_patrimonio_est > 0, saldo_btc_brl / total_patrimonio_est, 0.35)
  
  pedido <- NULL
  
  # ----------------------------------------------------------------------------
  # MOTOR 1: PLANO GUIANA BRASILEIRA (PAXG <-> BTC | R$ 150 - Janela 72h)
  # ----------------------------------------------------------------------------
  ratio_guiana <- p_paxg_brl / p_btc_brl
  z_guiana     <- (ratio_guiana - stats_guiana$media) / stats_guiana$sd
  
  if (z_guiana <= -0.75 && w_energy < 55.0 && saldo_btc_brl >= 45.0 && saldo_paxg_brl < 450.0) {
    # Bitcoin eufórico / Ouro barato -> Drenagem lucrativa: Vende BTC e compra PAXG
    lucro_proj <- max(1.40, ((stats_guiana$media / ratio_guiana) - 1) * 100 - 0.15)
    lote_g <- min(VALOR_GUIANA_BRL * fator_lote, saldo_btc_brl * 0.40)
    if (lote_g >= 42.0) {
      pedido <- list(
        estrategia = "PLANO_GUIANA_BRASILEIRA",
        origem = "BTC", destino = "PAXG",
        valor_brl = lote_g, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  } else if (z_guiana >= 1.00 && w_energy < 55.0 && peso_btc < 0.55 && saldo_paxg_brl >= 40.0) {
    # Ouro caro / Bitcoin com grande desconto -> Vende PAXG e compra BTC
    lucro_proj <- max(1.40, ((ratio_guiana / stats_guiana$media) - 1) * 100 - 0.15)
    pedido <- list(
      estrategia = "PLANO_GUIANA_BRASILEIRA",
      origem = "PAXG", destino = "BTC",
      valor_brl = min(VALOR_GUIANA_BRL * fator_lote, saldo_paxg_brl * 0.50),
      lucro_esperado_pct = lucro_proj, timestamp = agora_ts
    )
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 2: PLANO ESCUDO DE AQUILES (BRL -> BTC no Pânico / BTC -> BRL no Repique | R$ 300)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    # Ponta A: Compra BTC somente em estresse real (VIX >= 21.0 e saldo livre)
    if (vix_atual >= 21.00 && (pc1_atual >= 0.38 || ent_atual <= 1.80) && w_energy < 55.0 && peso_btc < 0.55 && saldo_caixa_brl >= 100.0) {
      pedido <- list(
        estrategia = "PLANO_ESCUDO_DE_AQUILES",
        origem = "BRL", destino = "BTC",
        valor_brl = min(VALOR_VIX_BRL * fator_lote, saldo_caixa_brl * 0.40), 
        lucro_esperado_pct = 2.00, timestamp = agora_ts
      )
    } else if (vix_atual < 18.50 && ret_btc_5m >= 0.0050 && saldo_btc_brl >= 50.0 && peso_btc > 0.18) {
      # Ponta B: Normalização do VIX com BTC em repique -> Realização de volta para Caixa BRL
      pedido <- list(
        estrategia = "PLANO_ESCUDO_DE_AQUILES",
        origem = "BTC", destino = "BRL",
        valor_brl = min(VALOR_VIX_BRL * 0.60 * fator_lote, saldo_btc_brl * 0.35),
        lucro_esperado_pct = 1.80, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 3: PLANO PÁTRIA VOLÁTIL (BRL <-> USDT | R$ 250 - 2 Slots)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(usd_oficial) && usd_oficial > 0) {
    spread_peg <- p_usdt_brl - usd_oficial
    
    if (spread_peg <= -0.0200 && saldo_caixa_brl >= 100.0 && saldo_usdt_brl < 500.0) {
      lucro_proj <- max(0.40, (abs(spread_peg) / usd_oficial) * 100)
      pedido <- list(
        estrategia = "PLANO_PATRIA_VOLATIL",
        origem = "BRL", destino = "USDT",
        valor_brl = min(VALOR_PEG_BRL * fator_lote, saldo_caixa_brl * 0.35),
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (spread_peg >= 0.0200 && saldo_usdt_brl >= 30.0) {
      lucro_proj <- max(0.40, (spread_peg / usd_oficial) * 100)
      pedido <- list(
        estrategia = "PLANO_PATRIA_VOLATIL",
        origem = "USDT", destino = "BRL",
        valor_brl = min(VALOR_PEG_BRL * fator_lote, saldo_usdt_brl),
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 4: PLANO CABOCLO DOS ORÁCULOS (BRL <-> LINK 1h | R$ 120 - 2 Slots)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_link_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_link <- (p_link_brl - stats_link$media) / stats_link$sd
    dsp_link <- obter_dsp_ativo(stats_link$serie)
    
    # Compra seletiva com Phase Bet Sizing: amplifica lote no vale de fase de Hilbert
    if (z_link <= -1.35 && saldo_caixa_brl >= 100.0 && saldo_link_brl < 260.0) {
      lote_base <- VALOR_LINK_BRL
      if (dsp_link$theta < -0.2 && dsp_link$theta > -2.8) lote_base <- 145.0
      if (z_link <= -1.75) lote_base <- 175.0
      
      lote_l <- min(lote_base * fator_lote, max(50.0, saldo_caixa_brl * 0.25))
      lucro_proj <- max(1.20, ((stats_link$media / p_link_brl) - 1) * 100)
      
      pedido <- list(
        estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
        origem = "BRL", destino = "LINK",
        valor_brl = lote_l,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_link_brl >= 30.0) {
      # Saída Dinâmica Harmonicus: Trailing por Desaceleração (d2Z < 0), Topo de Fase (theta > 0.85) ou Reversão
      cond_trailing <- (dsp_link$d2Z < 0 || dsp_link$theta > 0.85)
      cond_reversao <- (z_link >= 0.45)
      
      if (cond_trailing || cond_reversao) {
        lucro_proj <- max(0.65, ((p_link_brl / stats_link$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
          origem = "LINK", destino = "BRL",
          valor_brl = saldo_link_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 5: PLANO GRAVIDADE ZERO (BTC -> SOL e SOL -> BRL | R$ 120 - Janela 72h)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_sol_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75 && ste_atual >= -0.02) {
    ratio_sol_btc <- p_sol_brl / p_btc_brl
    z_sol_btc     <- (ratio_sol_btc - stats_sol_btc$media) / stats_sol_btc$sd
    
    if (z_sol_btc <= -1.00 && saldo_btc_brl >= 45.0 && saldo_sol_brl < 220.0) {
      lucro_proj <- max(2.00, ((stats_sol_btc$media / ratio_sol_btc) - 1) * 100)
      pedido <- list(
        estrategia = "PLANO_GRAVIDADE_ZERO",
        origem = "BTC", destino = "SOL",
        valor_brl = min(VALOR_SPILL_BRL * fator_lote, saldo_btc_brl * 0.30),
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (z_sol_btc >= 1.00 && saldo_sol_brl >= 25.0) {
      # Ponta B: Realização de topo de Solana para BRL
      lucro_proj <- max(1.40, ((ratio_sol_btc / stats_sol_btc$media) - 1) * 100)
      pedido <- list(
        estrategia = "PLANO_GRAVIDADE_ZERO",
        origem = "SOL", destino = "BRL",
        valor_brl = saldo_sol_brl,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 6: PLANO CORISCO DA SOLANA (BRL <-> SOL 1h/15m | R$ 100 - 2 Slots)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_sol_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_sol_15m <- (p_sol_brl - stats_sol_15m$media) / stats_sol_15m$sd
    dsp_sol   <- obter_dsp_ativo(stats_sol_15m$serie)
    
    # Trava de Teto de Custódia com Phase Bet Sizing: Permite até R$ 240 acumulados
    if (z_sol_15m <= -1.35 && saldo_caixa_brl >= 80.0 && saldo_sol_brl < 240.0) {
      lote_base_s <- VALOR_CORISCO_BRL
      if (dsp_sol$theta < -0.2 && dsp_sol$theta > -2.8) lote_base_s <- 130.0
      if (z_sol_15m <= -1.75) lote_base_s <- 160.0
      
      lote_s <- min(lote_base_s * fator_lote, max(50.0, saldo_caixa_brl * 0.25))
      lucro_proj <- max(1.20, ((stats_sol_15m$media / p_sol_brl) - 1) * 100)
      
      pedido <- list(
        estrategia = "PLANO_CORISCO_DA_SOLANA",
        origem = "BRL", destino = "SOL",
        valor_brl = lote_s,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_sol_brl >= 20.0) {
      # Saída Dinâmica Harmonicus: Trailing por Desaceleração, Topo de Fase ou Reversão
      cond_trailing_s <- (dsp_sol$d2Z < 0 || dsp_sol$theta > 0.85)
      cond_reversao_s <- (z_sol_15m >= 0.35)
      
      if (cond_trailing_s || cond_reversao_s) {
        lucro_proj <- max(0.60, ((p_sol_brl / stats_sol_15m$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_CORISCO_DA_SOLANA",
          origem = "SOL", destino = "BRL",
          valor_brl = saldo_sol_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 7: PLANO DUELO DE TITÃS (BTC -> ETH e ETH -> BRL | R$ 150 - 2 Slots)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_eth_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75) {
    ratio_eth_btc <- p_eth_brl / p_btc_brl
    z_eth_btc     <- (ratio_eth_btc - stats_eth_btc$media) / stats_eth_btc$sd
    
    if (z_eth_btc <= -1.00 && saldo_btc_brl >= 45.0 && saldo_eth_brl < 300.0) {
      lucro_proj <- max(1.20, ((stats_eth_btc$media / ratio_eth_btc) - 1) * 100)
      valor_req <- min(VALOR_TITAS_BRL * fator_lote, saldo_btc_brl * 0.30)
      if (valor_req >= 42.0) {
        pedido <- list(
          estrategia = "PLANO_DUELO_DE_TITAS",
          origem = "BTC", destino = "ETH",
          valor_brl = valor_req,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    } else if (z_eth_btc >= 0.85 && saldo_eth_brl >= 25.0) {
      # Ponta B: ETH Caro / BTC Barato -> Realização de ETH para Caixa BRL
      lucro_proj <- max(1.20, ((ratio_eth_btc / stats_eth_btc$media) - 1) * 100)
      pedido <- list(
        estrategia = "PLANO_DUELO_DE_TITAS",
        origem = "ETH", destino = "BRL",
        valor_brl = saldo_eth_brl,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 8: PLANO FLECHA DE SAGARANA (BRL -> BTC micro dip / BTC -> BRL Take Profit)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    if (ret_btc_5m <= -0.0035 && w_energy < 55.0 && saldo_caixa_brl >= 100.0 && peso_btc < 0.50) {
      # Compra seletiva em micro-dip
      pedido <- list(
        estrategia = "PLANO_FLECHA_DE_SAGARANA",
        origem = "BRL", destino = "BTC",
        valor_brl = min(VALOR_SAGARANA_BRL * fator_lote, max(50.0, saldo_caixa_brl * 0.20)),
        lucro_esperado_pct = 0.85, timestamp = agora_ts
      )
    } else if (ret_btc_5m >= 0.0035 && saldo_btc_brl >= 45.0 && peso_btc > 0.18) {
      # Take Profit de Micro-Repique: Vende BTC e guarda Reais no Caixa Livre
      pedido <- list(
        estrategia = "PLANO_FLECHA_DE_SAGARANA",
        origem = "BTC", destino = "BRL",
        valor_brl = min(VALOR_SAGARANA_BRL * fator_lote, saldo_btc_brl * 0.30),
        lucro_esperado_pct = 0.85, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 9: PLANO COFRE DE MIDAS (BRL -> PAXG | DCA Sistemático R$ 50 a cada 48h)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    hist_exec_file <- "ordens_executadas.rds"
    horas_desde_midas <- 999.0
    if (file.exists(hist_exec_file)) {
      hist_exec_tmp <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
      if (!is.null(hist_exec_tmp) && nrow(hist_exec_tmp) > 0 && "Estrategia" %in% names(hist_exec_tmp)) {
        hist_midas <- hist_exec_tmp[hist_exec_tmp$Estrategia == "PLANO_COFRE_DE_MIDAS", ]
        if (nrow(hist_midas) > 0) {
          ultimo_midas_ts <- as.POSIXct(tail(hist_midas$Data_Hora, 1))
          horas_desde_midas <- as.numeric(difftime(Sys.time(), ultimo_midas_ts, units = "hours"))
        }
      }
    }
    
    # Condição DCA: 48h completas + Caixa livre >= R$ 150 + Sem tempestade de volatilidade
    if (horas_desde_midas >= 48.0 && saldo_caixa_brl >= 150.0 && w_energy < 55.0) {
      pedido <- list(
        estrategia = "PLANO_COFRE_DE_MIDAS",
        origem = "BRL", destino = "PAXG",
        valor_brl = VALOR_MIDAS_BRL,
        lucro_esperado_pct = 3.50, # Rendimento anualizado Simple Earn Flexible
        timestamp = agora_ts
      )
    }
  }
  
  # Log do Radar em labtrader_radar.log
  log_line <- sprintf("[%s] RADAR: Z_Guiana=%.2f | VIX=%.2f | SpreadPeg=%.4f | Z_Link=%.2f | Z_SOL=%.2f | Z_SOL15m=%.2f | Z_ETH=%.2f | RetBTC5m=%.2f%% | Disparo=%s\n",
                      agora_str, z_guiana, vix_atual, ifelse(!is.null(usd_oficial), p_usdt_brl - usd_oficial, 0),
                      (p_link_brl - stats_link$media) / stats_link$sd,
                      (p_sol_brl / p_btc_brl - stats_sol_btc$media) / stats_sol_btc$sd,
                      (p_sol_brl - stats_sol_15m$media) / stats_sol_15m$sd,
                      (p_eth_brl / p_btc_brl - stats_eth_btc$media) / stats_eth_btc$sd,
                      ret_btc_5m * 100,
                      ifelse(!is.null(pedido), pedido$estrategia, "NENHUM"))
  cat(log_line, file = "labtrader_radar.log", append = TRUE)
  
  # Envio para o Gatekeeper se houver disparo
  if (!is.null(pedido)) {
    saveRDS(pedido, "solicitacao.rds")
    cat(sprintf("[%s] 🎯 [DISPARO LABTRADER] Ordem gerada: %s (%s -> %s | R$ %.2f). Enviando ao LabPolice...\n",
                agora_str, pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl))
  }
  
  return(pedido)
}
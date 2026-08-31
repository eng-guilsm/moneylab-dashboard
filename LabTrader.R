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
VALOR_GUIANA_BRL   <- 150.0  # R$ 150 - Janela 72h (Acúmulo de Ouro PAXG)
VALOR_ESCUDO_BRL   <- 200.0  # R$ 200 - Pânico VIX (Anti-Queda BRL -> BTC)
VALOR_PEG_BRL      <- 250.0  # R$ 250 - Arbitragem USDT/BRL (Peg Dólar)
VALOR_LINK_BRL     <- 240.0  # R$ 240 - Chainlink Quantum Alpha (Dual-Scale 75/25 15m + 10h | Tranches R$ 240/480 | Meta +0.70% a +1.40%)
VALOR_SPILL_BRL    <- 180.0  # R$ 180 - Gravidade Zero Quantum Alpha (Dual-Scale 75/25 15m + 65.5h | Tranches R$ 180/360 | Meta +1.40% a +6.50%)
VALOR_CORISCO_BRL  <- 100.0  # R$ 100 - Solana 15m Scalp (2 Slots)
VALOR_TITAS_BRL    <- 200.0  # R$ 200 - Duelo de Titãs (Harmonicus 12h Maximizer)
VALOR_SAGARANA_BRL <- 220.0  # R$ 220 - Flecha de Sagarana Quantum Alpha (Dual-Scale 75/25 | Tranches R$ 220/450 | Meta +0.50% a +0.95%)
VALOR_MIDAS_BRL    <- 50.0   # R$ 50  - Cofre de Midas (DCA Ouro Ressonante 5d Simple Earn + Ratchet Floor)
VALOR_BNB_BRL      <- 90.0   # R$ 90  - Sentinela de Minas (BNB Scalp 15m + Fee Discount)
VALOR_ADA_BRL      <- 80.0   # R$ 80  - Sertão Valente (ADA Scalp 30m)
VALOR_NEAR_BRL     <- 200.0  # R$ 200 - Farol de NEAR (Harmonicus 10h Maximizer 10x | 4 Slots | Meta +0.70%)
VALOR_BRUCE_BRL      <- 300.0  # R$ 300 - Plano Bruce Wayne (Contingência de Crise Cripto / Tail-Risk Macro Hedge)
VALOR_WALLSTREET_BRL <- 200.0  # R$ 200 - Plano 14 Sentinela de Wall Street (SP500 / VIX Front-Running Hedge)
VALOR_DOLLARUS_BRL   <- 195.0  # R$ 195 - Plano 15 Dollarus Quantum Peg (USDT/BRL Peg Arbitrage + Daniel Tekel & Simple Earn)

obter_stats_macro_btc_7d <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 10080;")
    if (nrow(df) >= 120) {
      p_rec <- rev(df$BTCBRL)
      m_val <- mean(p_rec, na.rm = TRUE)
      s_val <- sd(p_rec, na.rm = TRUE)
      if (is.na(s_val) || s_val <= 0) s_val <- 1000.0
      
      dsp <- obter_dsp_ativo(p_rec)
      return(list(media = m_val, sd = s_val, serie = p_rec, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 415000.0, sd = 5000.0, serie = c(415000.0), dsp = list(theta = 0.0, d2Z = 0.0, snr = 5.0)))
}

obter_stats_near_10h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT NEARBRL FROM Historico_binance WHERE NEARBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 600;")
    if (nrow(df) >= 15) {
      p_rec <- rev(df$NEARBRL)
      n_r <- length(p_rec)
      smooth_val <- mean(tail(p_rec, min(10, n_r)))
      detrend <- p_rec - smooth_val
      sd_val <- max(0.01, sd(tail(detrend, min(20, n_r))))
      return(list(media = smooth_val, sd = sd_val, serie = p_rec))
    }
  }, error = function(e) NULL)
  return(list(media = 9.65, sd = 0.15, serie = rep(9.65, 16)))
}

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

obter_stats_btc_dual_scale <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 600;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$BTCBRL)
      n_r <- length(p_rec)
      
      # Escala Rápida (6 minutos)
      p_fast <- tail(p_rec, min(30, n_r))
      smooth_fast <- mean(tail(p_fast, min(6, length(p_fast))))
      detrend_fast <- p_fast - smooth_fast
      sd_fast <- max(50.0, sd(tail(detrend_fast, min(15, length(p_fast)))))
      dsp_fast <- obter_dsp_ativo(p_fast)
      
      # Escala Macro Fourier (5.4 horas / 324 minutos)
      macro_len <- min(324, n_r)
      p_macro <- tail(p_rec, macro_len)
      smooth_macro <- mean(p_macro)
      sd_macro <- max(200.0, sd(p_macro))
      dsp_macro <- obter_dsp_ativo(p_macro)
      
      return(list(
        media_fast = smooth_fast,
        sd_fast = sd_fast,
        dsp_fast = dsp_fast,
        media_macro = smooth_macro,
        sd_macro = sd_macro,
        dsp_macro = dsp_macro,
        media = smooth_fast, # retrocompatibilidade
        sd = sd_fast,
        serie = p_rec
      ))
    }
  }, error = function(e) NULL)
  return(list(
    media_fast = 405000.0, sd_fast = 500.0, dsp_fast = list(theta = 0, d2Z = 0),
    media_macro = 405000.0, sd_macro = 2000.0, dsp_macro = list(theta = 0, d2Z = 0),
    media = 405000.0, sd = 1500.0, serie = rep(405000.0, 30)
  ))
}
obter_stats_btc_6h <- obter_stats_btc_dual_scale


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

obter_stats_link_dual_scale <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT LINKBRL FROM Historico_binance WHERE LINKBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 800;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$LINKBRL)
      n_r <- length(p_rec)
      
      # Escala Rápida Intradiária (15 minutos)
      p_fast <- tail(p_rec, min(45, n_r))
      smooth_fast <- mean(tail(p_fast, min(15, length(p_fast))))
      detrend_fast <- p_fast - smooth_fast
      sd_fast <- max(0.05, sd(tail(detrend_fast, min(20, length(p_fast)))))
      dsp_fast <- obter_dsp_ativo(p_fast)
      
      # Escala Macro de Ressonância Fourier (10.0 horas / 600 minutos)
      macro_len <- min(600, n_r)
      p_macro <- tail(p_rec, macro_len)
      smooth_macro <- mean(p_macro)
      sd_macro <- max(0.30, sd(p_macro))
      dsp_macro <- obter_dsp_ativo(p_macro)
      
      return(list(
        media_fast = smooth_fast,
        sd_fast = sd_fast,
        dsp_fast = dsp_fast,
        media_macro = smooth_macro,
        sd_macro = sd_macro,
        dsp_macro = dsp_macro,
        media = smooth_fast, # retrocompatibilidade
        sd = sd_fast,
        serie = p_rec
      ))
    }
  }, error = function(e) NULL)
  return(list(
    media_fast = 59.50, sd_fast = 0.20, dsp_fast = list(theta = 0, d2Z = 0),
    media_macro = 59.50, sd_macro = 1.50, dsp_macro = list(theta = 0, d2Z = 0),
    media = 59.50, sd = 0.30, serie = rep(59.50, 30)
  ))
}
obter_stats_link_1h <- obter_stats_link_dual_scale

obter_stats_vecm_ativo <- function(col_ativo = "LINKBRL", col_ref = "BTCBRL", n_barras = 400) {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    query <- sprintf("SELECT %s, %s FROM Historico_binance WHERE %s IS NOT NULL AND %s IS NOT NULL ORDER BY Data_Hora DESC LIMIT %d;",
                     col_ativo, col_ref, col_ativo, col_ref, n_barras)
    df <- dbGetQuery(con, query)
    if (nrow(df) >= 60) {
      p_at <- as.numeric(df[[col_ativo]])
      p_rf <- as.numeric(df[[col_ref]])
      
      lp <- log(p_at)
      lrf <- log(p_rf)
      
      v_rf <- var(lrf)
      beta <- if (is.na(v_rf) || v_rf <= 0) 1.0 else cov(lp, lrf) / v_rf
      spread <- lp - beta * lrf
      
      sd_sp <- sd(spread)
      if (is.na(sd_sp) || sd_sp <= 0) sd_sp <- 0.01
      
      z_vecm <- (spread[1] - mean(spread)) / sd_sp
      ret_at <- diff(lp)
      sigma_langevin <- sd(ret_at)
      
      # 1. Escala temporal corrigida (180 barras = 3h | 360 barras = 6h reais):
      idx_3h <- min(180, length(p_at))
      ret_3h <- (p_at[1] / p_at[idx_3h]) - 1.0
      
      idx_6h <- min(360, length(p_at))
      ret_6h <- (p_at[1] / p_at[idx_6h]) - 1.0
      
      # 2. Choque sistêmico do Bitcoin (16 barras = 15m reais):
      idx_15m <- min(16, length(p_rf))
      ret_btc_15m <- (p_rf[1] / p_rf[idx_15m]) - 1.0
      
      # 3. Alerta de Vale 6h:
      # Aciona em queda real de 3h (< -2.0%), 6h (< -3.0%), choque de BTC (< -0.78%) ou quebra VECM (< -2.0)
      alerta_vale_6h <- (ret_3h < -0.020) || (ret_6h < -0.030) || (ret_btc_15m < -0.0078) || (z_vecm < -2.0)
      
      return(list(
        z_vecm = z_vecm,
        beta = beta,
        sigma_langevin = sigma_langevin,
        ret_3h = ret_3h,
        ret_6h = ret_6h,
        ret_btc_15m = ret_btc_15m,
        alerta_vale_6h = alerta_vale_6h
      ))
    }
  }, error = function(e) NULL)
  return(list(z_vecm = 0.0, beta = 1.0, sigma_langevin = 0.01, ret_3h = 0, ret_6h = 0, ret_btc_15m = 0, alerta_vale_6h = FALSE))
}


obter_stats_sol_btc_dual_scale <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SOLBRL, BTCBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 4320;")
    if (nrow(df) >= 30) {
      r_rec <- rev(df$SOLBRL / df$BTCBRL)
      n_r <- length(r_rec)
      
      # Escala Rápida Intradiária (15 minutos)
      r_fast <- tail(r_rec, min(45, n_r))
      smooth_fast <- mean(tail(r_fast, min(15, length(r_fast))))
      detrend_fast <- r_fast - smooth_fast
      sd_fast <- max(0.000005, sd(tail(detrend_fast, min(20, length(r_fast)))))
      dsp_fast <- obter_dsp_ativo(r_fast)
      
      # Escala Macro de Ressonância Fourier (65.5 horas / 3930 minutos)
      macro_len <- min(3930, n_r)
      r_macro <- tail(r_rec, macro_len)
      smooth_macro <- mean(r_macro)
      sd_macro <- max(0.00002, sd(r_macro))
      dsp_macro <- obter_dsp_ativo(r_macro)
      
      return(list(
        media_fast = smooth_fast,
        sd_fast = sd_fast,
        dsp_fast = dsp_fast,
        media_macro = smooth_macro,
        sd_macro = sd_macro,
        dsp_macro = dsp_macro,
        media = smooth_macro, # retrocompatibilidade
        sd = sd_macro,
        serie = r_rec
      ))
    }
  }, error = function(e) NULL)
  return(list(
    media_fast = 0.00122, sd_fast = 0.00001, dsp_fast = list(theta = 0, d2Z = 0),
    media_macro = 0.00122, sd_macro = 0.00008, dsp_macro = list(theta = 0, d2Z = 0),
    media = 0.00122, sd = 0.00008, serie = rep(0.00122, 30)
  ))
}
obter_stats_sol_btc_72h <- obter_stats_sol_btc_dual_scale

obter_stats_sol_dual_scale <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SOLBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 600;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$SOLBRL)
      n_r <- length(p_rec)
      
      # Escala Rápida Intradiária (15 minutos)
      p_fast <- tail(p_rec, min(45, n_r))
      smooth_fast <- mean(tail(p_fast, min(15, length(p_fast))))
      detrend_fast <- p_fast - smooth_fast
      sd_fast <- max(0.20, sd(tail(detrend_fast, min(20, length(p_fast)))))
      dsp_fast <- obter_dsp_ativo(p_fast)
      
      # Escala Macro Fourier (4.0 horas / 240 minutos)
      macro_len <- min(240, n_r)
      p_macro <- tail(p_rec, macro_len)
      smooth_macro <- mean(p_macro)
      sd_macro <- max(1.00, sd(p_macro))
      dsp_macro <- obter_dsp_ativo(p_macro)
      
      return(list(
        media_fast = smooth_fast,
        sd_fast = sd_fast,
        dsp_fast = dsp_fast,
        media_macro = smooth_macro,
        sd_macro = sd_macro,
        dsp_macro = dsp_macro,
        media = smooth_fast, # retrocompatibilidade
        sd = sd_fast,
        serie = p_rec
      ))
    }
  }, error = function(e) NULL)
  return(list(
    media_fast = 550.0, sd_fast = 2.0, dsp_fast = list(theta = 0, d2Z = 0),
    media_macro = 550.0, sd_macro = 8.0, dsp_macro = list(theta = 0, d2Z = 0),
    media = 550.0, sd = 3.0, serie = rep(550.0, 30)
  ))
}
obter_stats_sol_15m <- obter_stats_sol_dual_scale

obter_stats_bnb_15m <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BNBBRL FROM Historico_binance WHERE BNBBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 30;")
    if (nrow(df) >= 5) {
      return(list(media = mean(df$BNBBRL[1:min(15, nrow(df))], na.rm = TRUE), sd = max(0.20, sd(df$BNBBRL[1:min(15, nrow(df))], na.rm = TRUE)), serie = rev(df$BNBBRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 3450.0, sd = 15.0, serie = rep(3450.0, 16)))
}

obter_stats_ada_30m <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT ADABRL FROM Historico_binance WHERE ADABRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
    if (nrow(df) >= 10) {
      return(list(media = mean(df$ADABRL[1:min(30, nrow(df))], na.rm = TRUE), sd = max(0.005, sd(df$ADABRL[1:min(30, nrow(df))], na.rm = TRUE)), serie = rev(df$ADABRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 4.80, sd = 0.04, serie = rep(4.80, 16)))
}

obter_stats_near_24h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT NEARBRL FROM Historico_binance WHERE NEARBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
    if (nrow(df) >= 10) {
      return(list(media = mean(df$NEARBRL[1:min(30, nrow(df))], na.rm = TRUE), sd = max(0.01, sd(df$NEARBRL[1:min(30, nrow(df))], na.rm = TRUE)), serie = rev(df$NEARBRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 22.50, sd = 0.35, serie = rep(22.50, 16)))
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
    df <- dbGetQuery(con, "SELECT ETHBRL, BTCBRL FROM Historico_binance WHERE ETHBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 720;")
    if (nrow(df) >= 20) {
      ratios <- df$ETHBRL / df$BTCBRL
      n_r <- length(ratios)
      p_rec <- rev(ratios)
      m_val <- mean(tail(p_rec, min(720, n_r)))
      sd_val <- max(0.0001, sd(tail(p_rec, min(720, n_r))))
      return(list(media = m_val, sd = sd_val, serie = p_rec))
    }
  }, error = function(e) NULL)
  return(list(media = 0.03140, sd = 0.00030, serie = rep(0.03140, 16)))
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

obter_stats_wallstreet_vix_hedge <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df_sp <- dbGetQuery(con, "SELECT SP500_Pts FROM Historico_rapido WHERE SP500_Pts IS NOT NULL ORDER BY Data_Hora DESC LIMIT 288;")
    df_vix <- dbGetQuery(con, "SELECT VIX_Index FROM Historico_macro WHERE VIX_Index IS NOT NULL ORDER BY Data DESC LIMIT 24;")
    
    sp_vals <- if (nrow(df_sp) >= 10) rev(df_sp$SP500_Pts) else rep(5800, 20)
    vix_val <- if (nrow(df_vix) >= 1) as.numeric(df_vix$VIX_Index[1]) else 16.5
    
    m_sp <- mean(sp_vals, na.rm = TRUE)
    s_sp <- max(5.0, sd(sp_vals, na.rm = TRUE))
    
    return(list(
      sp500_media = m_sp,
      sp500_sd = s_sp,
      sp500_ultimo = tail(sp_vals, 1),
      vix_atual = vix_val
    ))
  }, error = function(e) NULL)
  return(list(sp500_media = 5800, sp500_sd = 30, sp500_ultimo = 5800, vix_atual = 16.5))
}

obter_stats_dollarus_quantum_peg <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df_u <- dbGetQuery(con, "SELECT USDTBRL FROM Historico_binance WHERE USDTBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1440;")
    df_r <- dbGetQuery(con, "SELECT USD_BRL FROM Historico_rapido WHERE USD_BRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1440;")
    
    if (nrow(df_u) >= 20 && nrow(df_r) >= 20) {
      p_usdt <- df_u$USDTBRL[1]
      p_usd  <- df_r$USD_BRL[1]
      spread_peg <- p_usdt - p_usd
      
      # Veredito do oráculo intradiário se disponível
      oraculo_estresse <- FALSE
      if (exists("Daniel_tekel_dollar")) {
        veredito <- tryCatch(Daniel_tekel_dollar(), error = function(e) NULL)
        if (!is.null(veredito) && grepl("ESTRESSE|ALERTA|GARCH", veredito)) {
          oraculo_estresse <- TRUE
        }
      }
      
      return(list(
        usdt_atual = p_usdt,
        usd_oficial = p_usd,
        spread_peg = spread_peg,
        oraculo_estresse = oraculo_estresse
      ))
    }
  }, error = function(e) NULL)
  return(list(usdt_atual = 5.20, usd_oficial = 5.20, spread_peg = 0.0, oraculo_estresse = FALSE))
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
  p_bnb_brl   <- obter_preco_binance("BNBBRL")
  p_ada_brl   <- obter_preco_binance("ADABRL")
  p_near_brl  <- obter_preco_binance("NEARBRL")
  
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
  stats_bnb     <- obter_stats_bnb_15m()
  stats_ada     <- obter_stats_ada_30m()
  stats_near    <- obter_stats_near_24h()
  stats_near_10h <- obter_stats_near_10h()
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
  saldo_bnb_brl   <- 0
  saldo_ada_brl   <- 0
  saldo_near_brl  <- 0
  saldo_usdt_brl  <- 0
  
  if (!is.null(df_w) && is.data.frame(df_w) && nrow(df_w) > 0) {
    if (any(df_w$asset %in% c("BTC", "LDBTC"))) saldo_btc_brl   <- sum(df_w$free[df_w$asset %in% c("BTC", "LDBTC")], na.rm = TRUE) * p_btc_brl
    if ("BRL" %in% df_w$asset)  saldo_caixa_brl <- sum(df_w$free[df_w$asset == "BRL"], na.rm = TRUE)
    if (any(df_w$asset %in% c("PAXG", "LDPAXG"))) saldo_paxg_brl <- sum(df_w$free[df_w$asset %in% c("PAXG", "LDPAXG")], na.rm = TRUE) * p_paxg_brl
    if (any(df_w$asset %in% c("SOL", "LDSOL"))) saldo_sol_brl   <- sum(df_w$free[df_w$asset %in% c("SOL", "LDSOL")], na.rm = TRUE) * p_sol_brl
    if (any(df_w$asset %in% c("ETH", "LDETH"))) saldo_eth_brl   <- sum(df_w$free[df_w$asset %in% c("ETH", "LDETH")], na.rm = TRUE) * p_eth_brl
    if (any(df_w$asset %in% c("LINK", "LDLINK"))) saldo_link_brl  <- sum(df_w$free[df_w$asset %in% c("LINK", "LDLINK")], na.rm = TRUE) * p_link_brl
    if (any(df_w$asset %in% c("BNB", "LDBNB")) && !is.null(p_bnb_brl))   saldo_bnb_brl  <- sum(df_w$free[df_w$asset %in% c("BNB", "LDBNB")], na.rm = TRUE) * p_bnb_brl
    if (any(df_w$asset %in% c("ADA", "LDADA")) && !is.null(p_ada_brl))   saldo_ada_brl  <- sum(df_w$free[df_w$asset %in% c("ADA", "LDADA")], na.rm = TRUE) * p_ada_brl
    if (any(df_w$asset %in% c("NEAR", "LDNEAR")) && !is.null(p_near_brl)) saldo_near_brl <- sum(df_w$free[df_w$asset %in% c("NEAR", "LDNEAR")], na.rm = TRUE) * p_near_brl
    if ("USDT" %in% df_w$asset) saldo_usdt_brl  <- sum(df_w$free[df_w$asset == "USDT"], na.rm = TRUE) * p_usdt_brl
  }
  
  total_patrimonio_est <- saldo_caixa_brl + saldo_btc_brl + saldo_paxg_brl + saldo_sol_brl + saldo_eth_brl + saldo_link_brl + saldo_bnb_brl + saldo_ada_brl + saldo_near_brl + saldo_usdt_brl
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
  # MOTOR 4: PLANO CABOCLO DOS ORÁCULOS (Quantum Alpha Turbo + VECM/Langevin 3-Layer | LINKBRL)
  # ----------------------------------------------------------------------------
  stats_link <- obter_stats_link_dual_scale()
  vecm_link  <- obter_stats_vecm_ativo("LINKBRL", "BTCBRL")
  if (is.null(pedido) && !is.null(p_link_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_fast_l <- (p_link_brl - stats_link$media_fast) / stats_link$sd_fast
    z_macro_l <- (p_link_brl - stats_link$media_macro) / stats_link$sd_macro
    z_comp_l <- 0.75 * z_fast_l + 0.25 * z_macro_l
    
    dsp_fast_l <- stats_link$dsp_fast
    dsp_macro_l <- stats_link$dsp_macro
    acc_link <- dsp_fast_l$d2Z
    
    # Camada 3: Veto Físico de Vale 6h (-3% de queda iminente)
    veto_vale_link <- vecm_link$alerta_vale_6h
    
    # Condições de Entrada (Harmonicus + VECM Cointegrado + Cinemática d2Z >= -0.0004):
    cond_tranche1_link <- (saldo_link_brl < 70.0) && (z_comp_l <= -0.65) && (z_macro_l <= 0.40) && (dsp_fast_l$theta < -0.05) && (acc_link >= -0.0004)
    cond_tranche2_link <- (saldo_link_brl >= 70.0 && saldo_link_brl < 240.0) && (z_comp_l <= -1.20 || z_macro_l <= -1.00) && (dsp_fast_l$theta < -0.15)
    cond_vecm_link     <- (saldo_link_brl < 240.0) && (vecm_link$z_vecm <= -1.50) && (acc_link >= -0.0004)
    
    cond_entrada_link  <- (cond_tranche1_link || cond_tranche2_link || cond_vecm_link) && !veto_vale_link
    
    if (cond_entrada_link && saldo_caixa_brl >= 30.0 && saldo_link_brl < 260.0) {
      # Lote adaptativo de R$ 65 base para evitar esgotamento de caixa em vales seculares
      lote_l <- min(65.0 * fator_lote, max(30.0, saldo_caixa_brl * 0.30))
      
      lucro_proj <- max(1.00, ifelse(vecm_link$z_vecm <= -1.60, 1.20, 1.00))
      
      pedido <- list(
        estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
        origem = "BRL", destino = "LINK",
        valor_brl = lote_l,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_link_brl >= 25.0) {
      # Saída Dinâmica VECM/Harmonicus:
      cond_trailing <- (dsp_fast_l$d2Z < 0 || dsp_fast_l$theta > 0.80)
      cond_reversao <- (z_comp_l >= 0.05 || vecm_link$z_vecm >= 0.05)
      
      if (cond_trailing || cond_reversao) {
        lucro_proj <- max(1.00, ((p_link_brl / stats_link$media_fast) - 1) * 100)
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
  # MOTOR 5: PLANO GRAVIDADE ZERO (Quantum Alpha Turbo | Dual-Scale 75/25 15m + 65.5h Fourier | Tranches R$ 180/360)
  # ----------------------------------------------------------------------------
  stats_sol_btc <- obter_stats_sol_btc_dual_scale()
  if (is.null(pedido) && !is.null(p_sol_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75 && ste_atual >= -0.02) {
    ratio_sol_btc <- p_sol_brl / p_btc_brl
    z_fast_r <- (ratio_sol_btc - stats_sol_btc$media_fast) / stats_sol_btc$sd_fast
    z_macro_r <- (ratio_sol_btc - stats_sol_btc$media_macro) / stats_sol_btc$sd_macro
    z_comp_r <- 0.75 * z_fast_r + 0.25 * z_macro_r
    
    dsp_fast_r <- stats_sol_btc$dsp_fast
    dsp_macro_r <- stats_sol_btc$dsp_macro
    acc_r <- dsp_fast_r$d2Z
    
    # Condições Quantum Alpha para Ponta A (Compra BTC -> SOL):
    # Tranche 1 (Sonda de Micro-Dip 15m no ratio): Z_comp <= -0.60, Z_macro <= 0.40, fase rápida < -0.05, acc >= -0.0003
    cond_tranche1_grav <- (saldo_sol_brl < 80.0) && (z_comp_r <= -0.60) && (z_macro_r <= 0.40) && (dsp_fast_r$theta < -0.05) && (acc_r >= -0.0003)
    
    # Tranche 2 (Martingale de Vale Harmônico 65.5h): Se já tem posição (< R$ 260) e Z_comp <= -1.20 ou Z_macro <= -1.00 com fase < -0.15
    cond_tranche2_grav <- (saldo_sol_brl >= 80.0 && saldo_sol_brl < 260.0) && (z_comp_r <= -1.20 || z_macro_r <= -1.00) && (dsp_fast_r$theta < -0.15)
    
    if ((cond_tranche1_grav || cond_tranche2_grav) && saldo_btc_brl >= 45.0 && saldo_sol_brl < 540.0) {
      lote_base <- if (cond_tranche2_grav) 360.0 else 180.0
      lote_g <- if (cond_tranche2_grav) min(lote_base * fator_lote, max(120.0, saldo_btc_brl * 0.50)) else min(lote_base * fator_lote, max(60.0, saldo_btc_brl * 0.30))
      
      # Projeção de lucro dinâmico: se comprou no vale macro (theta_m < 0), estica a meta até +3.80% a +6.50%
      lucro_proj <- if (dsp_macro_r$theta < 0 && z_macro_r < -0.50) 3.80 else (if (cond_tranche2_grav) 2.40 else 1.80)
      lucro_proj <- max(1.40, lucro_proj)
      
      pedido <- list(
        estrategia = "PLANO_GRAVIDADE_ZERO",
        origem = "BTC", destino = "SOL",
        valor_brl = lote_g,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_sol_brl >= 25.0) {
      # Ponta B: Realização de topo de Solana para BRL
      # Saída em topo de fase rápida (theta > 0.80 ou desaceleração d2Z < 0) ou repique composto forte (Z_comp >= 0.35)
      cond_trailing <- (dsp_fast_r$d2Z < 0 || dsp_fast_r$theta > 0.80)
      cond_reversao <- (z_comp_r >= 0.35)
      
      if (cond_trailing || cond_reversao) {
        lucro_proj <- max(1.40, ((ratio_sol_btc / stats_sol_btc$media_fast) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_GRAVIDADE_ZERO",
          origem = "SOL", destino = "BRL",
          valor_brl = saldo_sol_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 6: PLANO CORISCO DA SOLANA (Quantum Alpha Turbo | Dual-Scale 75/25 15m + 4h | Tranches R$ 100/220 | Meta +0.60% a +1.40%)
  # ----------------------------------------------------------------------------
  stats_sol <- obter_stats_sol_dual_scale()
  if (is.null(pedido) && !is.null(p_sol_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_fast_s  <- (p_sol_brl - stats_sol$media_fast) / stats_sol$sd_fast
    z_macro_s <- (p_sol_brl - stats_sol$media_macro) / stats_sol$sd_macro
    z_comp_s  <- 0.75 * z_fast_s + 0.25 * z_macro_s
    
    dsp_fast_s  <- stats_sol$dsp_fast
    dsp_macro_s <- stats_sol$dsp_macro
    acc_sol     <- dsp_fast_s$d2Z
    
    # Condições Quantum Alpha Dupla Escala:
    # Tranche 1 (Sonda em Micro-Dip 15m): Z_comp <= -0.65, sem topo macro (Z_macro <= 0.40), fase rápida < -0.05, aceleração d2Z >= -0.0003
    cond_tranche1_sol <- (saldo_sol_brl < 80.0) && (z_comp_s <= -0.65) && (z_macro_s <= 0.40) && (dsp_fast_s$theta < -0.05) && (acc_sol >= -0.0003)
    
    # Tranche 2 (Martingale de Vale Harmônico 4h): se já tem posição aberta (< R$ 220) e Z_comp <= -1.20 ou Z_macro <= -1.00 com fase < -0.15
    cond_tranche2_sol <- (saldo_sol_brl >= 80.0 && saldo_sol_brl < 220.0) && (z_comp_s <= -1.20 || z_macro_s <= -1.00) && (dsp_fast_s$theta < -0.15)
    
    if ((cond_tranche1_sol || cond_tranche2_sol) && saldo_caixa_brl >= 80.0 && saldo_sol_brl < 240.0) {
      lote_base_s <- if (cond_tranche2_sol) 220.0 else VALOR_CORISCO_BRL
      lote_s <- if (cond_tranche2_sol) min(lote_base_s * fator_lote, max(100.0, saldo_caixa_brl * 0.45)) else min(lote_base_s * fator_lote, max(50.0, saldo_caixa_brl * 0.25))
      
      lucro_proj <- if (dsp_macro_s$theta < 0 && z_macro_s < -0.50) 1.40 else (if (cond_tranche2_sol) 1.00 else 0.60)
      lucro_proj <- max(0.50, lucro_proj)
      
      pedido <- list(
        estrategia = "PLANO_CORISCO_DA_SOLANA",
        origem = "BRL", destino = "SOL",
        valor_brl = lote_s,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_sol_brl >= 20.0) {
      # Saída Dinâmica Harmonicus: Trailing por Desaceleração, Topo de Fase ou Reversão
      cond_trailing_s <- (dsp_fast_s$d2Z < 0 || dsp_fast_s$theta > 0.80)
      cond_reversao_s <- (z_comp_s >= 0.35)
      
      if (cond_trailing_s || cond_reversao_s) {
        lucro_proj <- max(0.50, ((p_sol_brl / stats_sol$media_fast) - 1) * 100)
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
  # MOTOR 7: PLANO DUELO DE TITÃS (Harmonicus + VECM/Langevin 3-Layer | ETHBRL)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_eth_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75) {
    ratio_eth_btc <- p_eth_brl / p_btc_brl
    z_eth_btc     <- (ratio_eth_btc - stats_eth_btc$media) / stats_eth_btc$sd
    dsp_eth_btc   <- obter_dsp_ativo(stats_eth_btc$serie)
    vecm_eth      <- obter_stats_vecm_ativo("ETHBRL", "BTCBRL")
    
    # Camada 3: Veto Físico de Vale 6h
    veto_vale_eth <- vecm_eth$alerta_vale_6h
    
    # Ponta A: Compra de ETH (Harmonicus + VECM Cointegrado + Cinemática d2Z >= -0.0004)
    cond_harm_eth  <- (z_eth_btc <= -1.00) && (dsp_eth_btc$theta < -0.10 || z_eth_btc <= -1.20) && (dsp_eth_btc$d2Z >= -0.0004)
    cond_vecm_eth  <- (vecm_eth$z_vecm <= -1.50) && (dsp_eth_btc$d2Z >= -0.0004)
    cond_entrada_titas <- (cond_harm_eth || cond_vecm_eth) && !veto_vale_eth
    
    if (cond_entrada_titas && saldo_eth_brl < 260.0) {
      lucro_proj <- max(1.00, ifelse(vecm_eth$z_vecm <= -1.60, 1.20, 1.00))
      
      # Rota 1: Se tiver BTC livre >= R$ 85, usa rotação direta BTC -> ETH
      if (saldo_btc_brl >= 85.0) {
        lote_t <- min(VALOR_TITAS_BRL * fator_lote, saldo_btc_brl * 0.50)
        if (lote_t >= 65.0) {
          pedido <- list(
            estrategia = "PLANO_DUELO_DE_TITAS",
            origem = "BTC", destino = "ETH",
            valor_brl = lote_t,
            lucro_esperado_pct = lucro_proj, timestamp = agora_ts
          )
        }
      } else if (saldo_caixa_brl >= 30.0) {
        # Rota 2: Lote adaptativo de R$ 65 base para evitar esgotamento de caixa em vales seculares
        lote_t <- min(65.0 * fator_lote, max(30.0, saldo_caixa_brl * 0.30))
        pedido <- list(
          estrategia = "PLANO_DUELO_DE_TITAS",
          origem = "BRL", destino = "ETH",
          valor_brl = lote_t,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    } else if (saldo_eth_brl >= 25.0) {
      # Ponta B: Realização Dinâmica VECM/Harmonicus
      cond_topo_fase_t <- (dsp_eth_btc$theta > 0.75 && z_eth_btc >= 0.0)
      cond_reversao_t  <- (z_eth_btc >= 0.05 || vecm_eth$z_vecm >= 0.05)
      
      if (cond_topo_fase_t || cond_reversao_t) {
        lucro_proj <- max(1.00, ((ratio_eth_btc / stats_eth_btc$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_DUELO_DE_TITAS",
          origem = "ETH", destino = "BRL",
          valor_brl = saldo_eth_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 8: PLANO FLECHA DE SAGARANA (Quantum Alpha 10x Turbo | Dual-Scale 75/25 | Fourier Peak 5.4h | Tranches R$ 220/450)
  # ----------------------------------------------------------------------------
  stats_btc <- obter_stats_btc_dual_scale()
  if (is.null(pedido) && !is.null(p_btc_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_fast <- (p_btc_brl - stats_btc$media_fast) / stats_btc$sd_fast
    z_macro <- (p_btc_brl - stats_btc$media_macro) / stats_btc$sd_macro
    z_comp <- 0.75 * z_fast + 0.25 * z_macro
    
    dsp_fast <- stats_btc$dsp_fast
    dsp_macro <- stats_btc$dsp_macro
    acc_btc <- dsp_fast$d2Z
    
    # Condições de Entrada Quantum Alpha 10x:
    # Tranche 1 (Sonda em Micro-Dip): Z_comp <= -0.65, sem topo macro (Z_macro <= 0.40), fase rápida < -0.05, aceleração d2Z >= -0.0003
    cond_tranche1 <- (saldo_btc_brl < 80.0) && (z_comp <= -0.65) && (z_macro <= 0.40) && (dsp_fast$theta < -0.05) && (acc_btc >= -0.0003)
    
    # Tranche 2 (Martingale de Vale Harmônico): se já tem posição aberta (< R$ 350) e Z_comp <= -1.20 ou Z_macro <= -1.00 com fase < -0.15
    cond_tranche2 <- (saldo_btc_brl >= 80.0 && saldo_btc_brl < 350.0) && (z_comp <= -1.20 || z_macro <= -1.00) && (dsp_fast$theta < -0.15)
    
    if ((cond_tranche1 || cond_tranche2) && saldo_caixa_brl >= 80.0 && saldo_btc_brl < 750.0) {
      lote_base <- if (cond_tranche2) 450.0 else 220.0
      # Adaptativo ao caixa livre:
      lote_s <- if (cond_tranche2) min(lote_base * fator_lote, max(180.0, saldo_caixa_brl * 0.55)) else min(lote_base * fator_lote, max(80.0, saldo_caixa_brl * 0.35))
      
      # Projeção de lucro dinâmico: se comprou no vale macro harmônico, estica a meta até +0.95%
      lucro_proj <- if (dsp_macro$theta < 0 && z_macro < -0.50) 0.95 else (if (cond_tranche2) 0.75 else 0.50)
      lucro_proj <- max(0.40, lucro_proj)
      
      pedido <- list(
        estrategia = "PLANO_FLECHA_DE_SAGARANA",
        origem = "BRL", destino = "BTC",
        valor_brl = lote_s,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_btc_brl >= 45.0) {
      # Saída Dinâmica Harmonicus:
      # Topo de fase rápida (theta > 0.80 ou desaceleração d2Z < 0) ou repique composto forte (Z_comp >= 0.35)
      cond_trailing_sag <- (dsp_fast$d2Z < 0 || dsp_fast$theta > 0.80)
      cond_reversao_sag <- (z_comp >= 0.35)
      
      if (cond_trailing_sag || cond_reversao_sag) {
        lucro_proj <- max(0.40, ((p_btc_brl / stats_btc$media_fast) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_FLECHA_DE_SAGARANA",
          origem = "BTC", destino = "BRL",
          valor_brl = saldo_btc_brl, # Realiza 100% da custódia do slot
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 9: PLANO COFRE DE MIDAS (BRL -> PAXG | DCA Sistemático R$ 50 a cada 5 dias com Piso Ratchet)
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
    
    # Condição DCA Ressonante: 5 dias completos (120h) + Caixa livre >= R$ 100
    # Ouro alocado entra diretamente no Simple Earn Flexível e eleva o Piso Ratchet Inviolável
    if (horas_desde_midas >= 120.0 && saldo_caixa_brl >= 100.0 && w_energy < 55.0) {
      pedido <- list(
        estrategia = "PLANO_COFRE_DE_MIDAS",
        origem = "BRL", destino = "PAXG",
        valor_brl = VALOR_MIDAS_BRL, # R$ 50,00 fixo por tranche de acumulação
        lucro_esperado_pct = 3.50,   # Rendimento passivo Simple Earn Flexible
        timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 10: PLANO SENTINELA DE MINAS (BRL <-> BNB 15m Scalp + Desconto Taxas BNB)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_bnb_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_bnb_15m <- (p_bnb_brl - stats_bnb$media) / stats_bnb$sd
    dsp_bnb   <- obter_dsp_ativo(stats_bnb$serie)
    
    # Trava de Caixa Mínimo Global: exige Caixa Livre >= R$ 250
    if (z_bnb_15m <= -1.35 && saldo_caixa_brl >= 250.0 && saldo_bnb_brl < 180.0) {
      lote_base_b <- VALOR_BNB_BRL
      if (dsp_bnb$theta < -0.2 && dsp_bnb$theta > -2.8) lote_base_b <- 120.0
      if (z_bnb_15m <= -1.60) lote_base_b <- 140.0
      
      lote_b <- min(lote_base_b * fator_lote, max(50.0, saldo_caixa_brl * 0.20))
      lucro_proj <- max(0.80, ((stats_bnb$media / p_bnb_brl) - 1) * 100)
      
      pedido <- list(
        estrategia = "PLANO_SENTINELA_DE_MINAS",
        origem = "BRL", destino = "BNB",
        valor_brl = lote_b,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_bnb_brl >= 20.0) {
      cond_trailing_b <- (dsp_bnb$d2Z < 0 || dsp_bnb$theta > 0.85)
      cond_reversao_b <- (z_bnb_15m >= 0.35)
      
      if (cond_trailing_b || cond_reversao_b) {
        lucro_proj <- max(0.60, ((p_bnb_brl / stats_bnb$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DE_MINAS",
          origem = "BNB", destino = "BRL",
          valor_brl = saldo_bnb_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }

  # ----------------------------------------------------------------------------
  # MOTOR 11: PLANO SERTÃO VALENTE (BRL <-> ADA 30m Scalp / Reversão Harmonicus)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_ada_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_ada_30m <- (p_ada_brl - stats_ada$media) / stats_ada$sd
    dsp_ada   <- obter_dsp_ativo(stats_ada$serie)
    
    # Trava de Caixa Mínimo Global: exige Caixa Livre >= R$ 250
    if (z_ada_30m <= -1.35 && saldo_caixa_brl >= 250.0 && saldo_ada_brl < 160.0) {
      lote_base_a <- VALOR_ADA_BRL
      if (dsp_ada$theta < -0.2 && dsp_ada$theta > -2.8) lote_base_a <- 110.0
      if (z_ada_30m <= -1.60) lote_base_a <- 130.0
      
      lote_a <- min(lote_base_a * fator_lote, max(50.0, saldo_caixa_brl * 0.20))
      lucro_proj <- max(0.90, ((stats_ada$media / p_ada_brl) - 1) * 100)
      
      pedido <- list(
        estrategia = "PLANO_SERTAO_VALENTE",
        origem = "BRL", destino = "ADA",
        valor_brl = lote_a,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_ada_brl >= 20.0) {
      cond_trailing_a <- (dsp_ada$d2Z < 0 || dsp_ada$theta > 0.85)
      cond_reversao_a <- (z_ada_30m >= 0.40)
      
      if (cond_trailing_a || cond_reversao_a) {
        lucro_proj <- max(0.60, ((p_ada_brl / stats_ada$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_SERTAO_VALENTE",
          origem = "ADA", destino = "BRL",
          valor_brl = saldo_ada_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 12: PLANO FAROL DE NEAR (Harmonicus 10h Maximizer | R$ 200 - 4 Slots | Meta +0,70%)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_near_brl) && ste_atual >= -0.02 && pc1_atual < 0.75 && w_energy < 55.0) {
    z_near <- (p_near_brl - stats_near_10h$media) / stats_near_10h$sd
    dsp_near <- obter_dsp_ativo(stats_near_10h$serie)
    vecm_near <- obter_stats_vecm_ativo("NEARBRL", "BTCBRL")
    
    # Entrada seletiva Harmonicus + VECM Cointegrado com d2Z >= -0.0004
    cond_harm_near <- (z_near <= -0.95) && (dsp_near$theta < -0.10 || z_near <= -1.15) && (dsp_near$d2Z >= -0.0004)
    cond_vecm_near <- (vecm_near$z_vecm <= -1.40) && (dsp_near$d2Z >= -0.0004)
    cond_entrada_near <- (cond_harm_near || cond_vecm_near) && !vecm_near$alerta_vale_6h
    
    if (cond_entrada_near && saldo_caixa_brl >= 50.0 && saldo_near_brl < 450.0) {
      lote_base_n <- VALOR_NEAR_BRL
      if (dsp_near$theta < -1.10) lote_base_n <- 240.0
      if (z_near <= -1.40 || vecm_near$z_vecm <= -1.50) lote_base_n <- 250.0
      
      lote_n <- min(lote_base_n * fator_lote, max(50.0, saldo_caixa_brl * 0.30))
      lucro_proj <- max(0.80, ((stats_near_10h$media / p_near_brl) - 1) * 100)
      
      pedido <- list(
        estrategia = "PLANO_FAROL_DE_NEAR",
        origem = "BRL", destino = "NEAR",
        valor_brl = lote_n,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (saldo_near_brl >= 20.0) {
      # Saída Dinâmica Harmonicus: Trailing por Desaceleração (d2Z < 0), Topo de Fase (theta > 0.75) ou Reversão
      cond_trailing_n <- (dsp_near$d2Z < 0 || dsp_near$theta > 0.75)
      cond_reversao_n <- (z_near >= 0.25)
      
      if (cond_trailing_n || cond_reversao_n) {
        lucro_proj <- max(0.70, ((p_near_brl / stats_near_10h$media) - 1) * 100)
        pedido <- list(
          estrategia = "PLANO_FAROL_DE_NEAR",
          origem = "NEAR", destino = "BRL",
          valor_brl = saldo_near_brl,
          lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 13: PLANO BRUCE WAYNE (Contingência de Crise Cripto / Tail-Risk Macro Hedge)
  # Isento Exclusivo da Trava 6 | Acionado APENAS em colapso estrutural prolongado (Bear Market de semanas/meses)
  # ----------------------------------------------------------------------------
  stats_macro_btc <- obter_stats_macro_btc_7d()
  z_macro_btc     <- if (!is.null(p_btc_brl)) (p_btc_brl - stats_macro_btc$media) / stats_macro_btc$sd else 0.0
  dsp_macro_btc   <- stats_macro_btc$dsp
  
  # Gatilho de Crise Extrema: Z_macro <= -1.65σ + Fase macro < -0.10 + Desaceleração d2Z <= 0
  cond_crise_bruce <- (z_macro_btc <= -1.65) && (dsp_macro_btc$theta < -0.10) && (dsp_macro_btc$d2Z <= 0)
  
  if (is.null(pedido) && cond_crise_bruce) {
    # Identificar se há posições de altcoins abertas em risco
    saldo_altcoins <- list(
      SOL = saldo_sol_brl,
      ETH = saldo_eth_brl,
      LINK = saldo_link_brl,
      BNB = saldo_bnb_brl,
      ADA = saldo_ada_brl,
      NEAR = saldo_near_brl
    )
    
    # Selecionar o ativo com maior saldo em aberto para desova defensiva
    ativos_com_saldo <- names(saldo_altcoins)[sapply(saldo_altcoins, function(x) !is.null(x) && x >= 30.0)]
    
    if (length(ativos_com_saldo) > 0) {
      # Escolhe o ativo de maior volume
      saldos_num <- sapply(ativos_com_saldo, function(a) saldo_altcoins[[a]])
      ativo_escolhido <- ativos_com_saldo[which.max(saldos_num)]
      val_desova <- min(saldo_altcoins[[ativo_escolhido]], VALOR_BRUCE_BRL)
      
      cat(sprintf("🦇 [PLANO BRUCE WAYNE ACIONADO] Regime de Bear Market Prolongado (Z_macro=%.2fσ, Phase=%.2f, d2Z=%.4f). Desovando %s (R$ %.2f) para proteção em Caixa BRL/Ouro.\n",
                  z_macro_btc, dsp_macro_btc$theta, dsp_macro_btc$d2Z, ativo_escolhido, val_desova))
      
      pedido <- list(
        estrategia = "PLANO_BRUCE_WAYNE",
        origem = ativo_escolhido, destino = "BRL",
        valor_brl = val_desova,
        lucro_esperado_pct = 0.0, # Isento de Trava 6
        timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 14: PLANO SENTINELA DE WALL STREET (S&P 500 TradFi / SP500_Pts | 100% NÃO-CRIPTO)
  # Monitoramento de Wall Street com Ressonância de Hilbert de Fase e Filtro VIX
  # ----------------------------------------------------------------------------
  stats_ws <- obter_stats_wallstreet_vix_hedge()
  if (is.null(pedido)) {
    # Busca cotação histórica do S&P 500 do Historico_rapido
    sp500_serie <- tryCatch({
      con_rap <- dbConnect(SQLite(), db_path)
      on.exit(dbDisconnect(con_rap))
      df_sp <- dbGetQuery(con_rap, "SELECT SP500_Pts FROM Historico_rapido WHERE SP500_Pts IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
      if (nrow(df_sp) >= 16) rev(df_sp$SP500_Pts) else rep(7200.0, 16)
    }, error = function(e) rep(7200.0, 16))
    
    dsp_sp500 <- obter_dsp_ativo(sp500_serie)
    sp500_atual <- tail(sp500_serie, 1)
    
    # Entrada por Ressonância: Vale de Fase do S&P 500 (theta <= -1.15 rad) com d2Z >= 0 e VIX indicando sobre-venda (>= 18.0)
    cond_entrada_ws <- (dsp_sp500$theta <= -1.15) && (dsp_sp500$d2Z >= -0.0002) && (stats_ws$vix_atual >= 18.0)
    
    if (cond_entrada_ws && saldo_caixa_brl >= 100.0) {
      lote_ws <- min(VALOR_WALLSTREET_BRL * fator_lote, saldo_caixa_brl * 0.40)
      lucro_proj <- max(0.80, 1.20)
      pedido <- list(
        estrategia = "PLANO_SENTINELA_WALLSTREET",
        origem = "BRL", destino = "SP500",
        valor_brl = lote_ws,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (dsp_sp500$theta >= 1.15 && stats_ws$vix_atual < 16.5) {
      # Saída / Realização em Topo de Fase do S&P 500 (theta >= +1.15 rad)
      lucro_proj <- max(0.80, 1.00)
      pedido <- list(
        estrategia = "PLANO_SENTINELA_WALLSTREET",
        origem = "SP500", destino = "BRL",
        valor_brl = VALOR_WALLSTREET_BRL * fator_lote,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }

  # ----------------------------------------------------------------------------
  # MOTOR 15: PLANO COMMODITY ENERGY ALPHA (Petróleo WTI TradFi / WTI_Oil | 100% NÃO-CRIPTO)
  # Arbitragem e Ressonância de Hilbert sobre a Commodity Energética Global
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    wti_serie <- tryCatch({
      con_wti <- dbConnect(SQLite(), db_path)
      on.exit(dbDisconnect(con_wti))
      df_wti <- dbGetQuery(con_wti, "SELECT WTI_Oil FROM Historico_rapido WHERE WTI_Oil IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
      if (nrow(df_wti) >= 16) rev(df_wti$WTI_Oil) else rep(85.0, 16)
    }, error = function(e) rep(85.0, 16))
    
    dsp_wti <- obter_dsp_ativo(wti_serie)
    wti_atual <- tail(wti_serie, 1)
    
    # Entrada por Ressonância: Vale de Fase do Petróleo (theta <= -1.15 rad) com d2Z >= 0
    cond_entrada_wti <- (dsp_wti$theta <= -1.15) && (dsp_wti$d2Z >= -0.0002)
    
    if (cond_entrada_wti && saldo_caixa_brl >= 80.0) {
      lucro_proj <- max(1.00, 1.50)
      pedido <- list(
        estrategia = "PLANO_COMMODITY_ENERGY_ALPHA",
        origem = "BRL", destino = "WTI",
        valor_brl = min(VALOR_DOLLARUS_BRL * fator_lote, saldo_caixa_brl * 0.40),
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    } else if (dsp_wti$theta >= 1.15) {
      # Saída: Topo de Fase do Petróleo (theta >= +1.15 rad)
      lucro_proj <- max(1.00, 1.20)
      pedido <- list(
        estrategia = "PLANO_COMMODITY_ENERGY_ALPHA",
        origem = "WTI", destino = "BRL",
        valor_brl = VALOR_DOLLARUS_BRL * fator_lote,
        lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }
  
  # Log do Radar em labtrader_radar.log
  z_bnb_val  <- if (!is.null(p_bnb_brl)) (p_bnb_brl - stats_bnb$media) / stats_bnb$sd else 0.0
  z_ada_val  <- if (!is.null(p_ada_brl)) (p_ada_brl - stats_ada$media) / stats_ada$sd else 0.0
  z_near_val <- if (!is.null(p_near_brl)) (p_near_brl - stats_near$media) / stats_near$sd else 0.0
  
  log_line <- sprintf("[%s] RADAR: Z_Guiana=%.2f | VIX=%.2f | SpreadPeg=%.4f | Z_Link=%.2f | Z_SOL=%.2f | Z_SOL15m=%.2f | Z_ETH=%.2f | Z_BNB=%.2f | Z_ADA=%.2f | Z_NEAR=%.2f | RetBTC5m=%.2f%% | Disparo=%s\n",
                      agora_str, z_guiana, vix_atual, ifelse(!is.null(usd_oficial), p_usdt_brl - usd_oficial, 0),
                      (p_link_brl - stats_link$media) / stats_link$sd,
                      (p_sol_brl / p_btc_brl - stats_sol_btc$media) / stats_sol_btc$sd,
                      (p_sol_brl - stats_sol_15m$media) / stats_sol_15m$sd,
                      (p_eth_brl / p_btc_brl - stats_eth_btc$media) / stats_eth_btc$sd,
                      z_bnb_val, z_ada_val, z_near_val,
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
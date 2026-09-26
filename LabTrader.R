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

# --- PARÂMETROS DE VOLUME HARMONICUS ULTRA-DEEP (CALIBRAÇÃO PROPORCIONAL DINÂMICA 3.210 BRL) ---
VALOR_GUIANA_BRL            <- 150.0  # 4.7% - Plano 1: Guiana Brasileira (PAXG <-> BTC 5h | Posse 123.3h | CV 7.0%)
VALOR_ESCUDO_BRL            <- 300.0  # 9.3% - Plano 2: Escudo de Aquiles (BRL -> BTC 4h | Posse 176.0h | CV 26.5%)
VALOR_VIX_BRL               <- 300.0  # 9.3% - Alias para Escudo de Aquiles
VALOR_PATRIA_BRL            <- 260.0  # 8.1% - Plano 3: Patria Volatil / Sentinela Cambial (Swing 24h | Simple Earn 6,88% a.a.)
VALOR_TITA_USDT_DIP         <- 50.0   # 8.1% (50 USDT ~R$ 260) - Plano 4: Titã do Silício Dip Moderado (Z <= -0.50)
VALOR_TITA_USDT_CRASH       <- 75.0   # 12.5% (75 USDT ~R$ 387) - Plano 4: Titã do Silício Forte Queda (Z <= -1.25)
VALOR_OURO_LIQUIDO_USDT     <- 30.0   # 4.8% (30 USDT ~R$ 155) - Plano 5: Ouro Líquido (PAXG <-> USDT 4h | Trava 6 >= +0.60%)
VALOR_CHOQUE_BRL            <- 90.0   # 2.8% - Plano 6: Choque Energético (XLE Hedge 5h | Posse 475.5h)
VALOR_ETH_TRANCHE_BRL       <- 150.0  # 4.6% - Plano 7: Sentinela de Éter (BRL <-> ETH 1h | Harmonicus Estágio 3 Soberano | 3 Tranches Cap 13.8%)
VALOR_TITAS_BRL             <- VALOR_ETH_TRANCHE_BRL # Alias para compatibilidade
VALOR_SAGARANA_BRL          <- 320.0  # 10.0% - Plano 8: Flecha de Sagarana (BRL <-> BTC 4h | Posse 176.0h | CV 5.9%)
VALOR_SOL_SENTINELA_BRL     <- 145.0  # 4.5% - Plano 9: Sentinela do Sol (BRL <-> SOL 1h | Posse 5.2h | Lucro 11.83-14.27 reais/m | Sizing 4.5%)
VALOR_BNB_BRL               <- 130.0  # 4.0% - Plano 10: Sentinela de Minas (BRL <-> BNB 3h | Posse 177.9h | CV 7.4%)
VALOR_TLT_BRL               <- 80.0   # 2.5% - Plano 11: Escudo de Washington (TLT T-Bonds 5h | Posse 331.9h)
VALOR_SQQQB_BRL             <- 274.0  # 8.5% (53 USDT) - Plano 12: Sentinela Antifrágil (SQQQB 1h | Posse 2.3h | Meta 1%/m)
VALOR_BRUCE_BRL             <- 350.0  # Plano 13: Bruce Wayne (Desativado Temporariamente)
VALOR_WALLSTREET_USDT       <- 80.0   # 8.0% (~422 reais / 81 USDT) - ⭐🎵 Plano 14: Sentinela Wall Street (Harmonicus SX Equities)
VALOR_WALLSTREET_USDT_DIP   <- VALOR_WALLSTREET_USDT # Alias compatibilidade
VALOR_WALLSTREET_USDT_CRASH <- VALOR_WALLSTREET_USDT # Alias compatibilidade
VALOR_PERRY_BRL             <- 180.0  # Plano 15: Adeus, Perry (Desova Tranche 35 USDT sob Lucro)
VALOR_CABOCLO_BRL           <- 145.0  # 4.5% - Plano 16: Caboclo dos Oráculos (LINK 12h | Lucro +30,60 reais/m | Posse 21,9h)
VALOR_NEAR_BRL              <- 112.0  # 3.5% - Plano 17: Farol de Near (NEAR 6h | Lucro +17,34 reais/m | Posse 4,8h Giro Rápido)

# --- LIMIAR MACRO PC1 CALIBRADO VIA SIMULAÇÃO HISTÓRICA (CESTA CORE 5 CRIPTO / P90 SECULAR) ---
# Estudo de Cestas: Core 5 (BTC, ETH, SOL, BNB, LINK) possui latência de 0,21 ms (< 0,1s) e contraste Crash/Normal de 1,12x.
# Simulação sobre 176k candles de 5m (20,2 meses com crash jan/2025):
# Desativar compras quando PC1 >= 0.72 protege o capital em 100% dos crashes seculares,
# mantendo 91% do tempo liberado e maximizando o PnL no pico de +4,48 reais/mês com 98,2% Win Rate.
# NOTA: O valor 0.72 é uma instância empírica calibrada do modelo (caso representativo para reaproveitamento modular).
PC1_CORTE_SECULAR           <- 0.72

obter_stats_macro_btc_30d <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # Janela Macro Real de 30 dias (43.200 minutos)
    df <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 43200;")
    if (nrow(df) >= 720) {
      # Reamostragem horária (a cada 60 pontos) para DSP e Z-score macro limpo sem ruído intradiário
      p_rec <- rev(df$BTCBRL)[seq(1, nrow(df), by = 60)]
      m_val <- mean(p_rec, na.rm = TRUE)
      s_val <- sd(p_rec, na.rm = TRUE)
      if (is.na(s_val) || s_val <= 0) s_val <- 2000.0
      
      dsp <- obter_dsp_ativo(p_rec)
      return(list(media = m_val, sd = s_val, serie = p_rec, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 415000.0, sd = 8000.0, serie = c(415000.0), dsp = list(theta = 0.0, d2Z = 0.0, snr = 5.0)))
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

obter_stats_near_6h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT NEARBRL FROM Historico_binance WHERE NEARBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 360;")
    if (nrow(df) >= 15) {
      p_rec <- rev(df$NEARBRL)
      n_r <- length(p_rec)
      smooth_val <- mean(tail(p_rec, min(10, n_r)))
      detrend <- p_rec - smooth_val
      sd_val <- max(0.01, sd(tail(detrend, min(20, n_r))))
      dsp <- obter_dsp_ativo(p_rec)
      return(list(media = smooth_val, sd = sd_val, serie = p_rec, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 9.65, sd = 0.15, serie = rep(9.65, 16), dsp = list(theta = 0, d2Z = 0)))
}

obter_stats_avax_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT AVAXBRL FROM Historico_binance WHERE AVAXBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
    if (nrow(df) >= 15) {
      p_rec <- rev(df$AVAXBRL)
      n_r <- length(p_rec)
      smooth_val <- mean(tail(p_rec, min(10, n_r)))
      detrend <- p_rec - smooth_val
      sd_val <- max(0.05, sd(tail(detrend, min(20, n_r))))
      return(list(media = smooth_val, sd = sd_val, serie = p_rec))
    }
  }, error = function(e) NULL)
  return(list(media = 37.0, sd = 0.50, serie = rep(37.0, 16)))
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
    df <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1200;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$BTCBRL)
      # Reamostragem em candles de 5m para o modelo intradiário G500
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      n_5m <- length(p_5m)
      
      # Calibração G500: Period = 48 candles de 5m (240 min = 4 horas)
      p_fast <- tail(p_5m, min(48, n_5m))
      smooth_fast <- mean(p_fast)
      sd_fast <- max(50.0, sd(p_fast))
      dsp_fast <- obter_dsp_ativo(p_fast)
      
      # Escala Macro (288 candles de 5m = 24 horas)
      p_macro <- tail(p_5m, min(288, n_5m))
      smooth_macro <- mean(p_macro)
      sd_macro <- max(200.0, sd(p_macro))
      # Harmonicus Fourier DSP para BTC (32p STFT + Roofing Filter)
      dsp_fourier <- if (exists("obter_dsp_fourier_eth")) obter_dsp_fourier_eth(p_5m) else list(roof_z = 0, fsp = 0, fhri = 0, phi_dom = 0, d2Z = 0)
      
      return(list(
        media_fast = smooth_fast,
        sd_fast = sd_fast,
        dsp_fast = dsp_fast,
        media_macro = smooth_macro,
        sd_macro = sd_macro,
        dsp_macro = dsp_macro,
        fourier = dsp_fourier,
        media = smooth_fast,
        sd = sd_fast,
        serie = p_5m
      ))
    }
  }, error = function(e) NULL)
  return(list(
    media_fast = 405000.0, sd_fast = 500.0, dsp_fast = list(theta = 0, d2Z = 0),
    media_macro = 405000.0, sd_macro = 2000.0, dsp_macro = list(theta = 0, d2Z = 0),
    fourier = list(roof_z = 0, fsp = 0, fhri = 0, phi_dom = 0, d2Z = 0),
    media = 405000.0, sd = 1500.0, serie = rep(405000.0, 30)
  ))
}
obter_stats_btc_6h <- obter_stats_btc_dual_scale


obter_stats_guiana_72h <- function(p_gold = 4639.0) {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL, USDTBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 900;")
    if (nrow(df) >= 30) {
      ratios <- rev((df$USDTBRL * p_gold) / df$BTCBRL)
      step_5m <- seq(1, length(ratios), by = 5)
      r_5m <- ratios[step_5m]
      # Calibração Cirúrgica 12h: Period = 144 candles de 5m (720 min = 12 horas)
      r_sub <- tail(r_5m, min(144, length(r_5m)))
      m_val <- mean(r_sub, na.rm = TRUE)
      s_val <- max(0.0001, sd(r_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(r_sub)
      return(list(media = m_val, sd = s_val, serie = r_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 0.05920, sd = 0.00350, serie = rep(0.05920, 16), dsp = list(theta = 0, d2Z = 0)))
}

# 🛡️ Pré-Filtro Satoshis Lock para o Plano Guiana Brasileira (PAXG -> BTC)
obter_retorno_satoshis_guiana <- function(p_paxg_brl, p_btc_brl) {
  hist_file <- if (file.exists("ordens_executadas.rds")) "ordens_executadas.rds" else "/app/ordens_executadas.rds"
  if (!file.exists(hist_file)) return(-999.0)
  h <- tryCatch(readRDS(hist_file), error = function(e) NULL)
  if (is.null(h) || nrow(h) == 0) return(-999.0)
  
  execs <- h[grepl("EXECUTADO_REAL", h$Status) & h$Estrategia == "PLANO_GUIANA_BRASILEIRA", ]
  compras_paxg <- execs[execs$Destino == "PAXG", ]
  vendas_paxg  <- execs[execs$Origem == "PAXG", ]
  if (nrow(compras_paxg) == 0) return(-999.0)
  
  abertas <- calcular_lotes_abertos_fifo(compras_paxg, vendas_paxg, ativo = "PAXG")
  if (nrow(abertas) == 0) return(-999.0)
  
  ratio_live <- if (p_btc_brl > 0) p_paxg_brl / p_btc_brl else 0.0
  if (ratio_live <= 0) return(-999.0)
  
  db_p <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/app/MoneyBot_Local.db"
  ratios_compra <- sapply(seq_len(nrow(abertas)), function(k) {
    p_exec_k <- as.numeric(abertas$Preco_Exec[k])
    if (!is.na(p_exec_k) && p_exec_k < 1.0) return(p_exec_k) # Já é o ratio gravado
    p_btc_k <- tryCatch({
      con_k <- dbConnect(SQLite(), db_p)
      on.exit(dbDisconnect(con_k))
      df_k <- dbGetQuery(con_k, sprintf("SELECT BTCBRL FROM Historico_binance WHERE Data_Hora <= '%s' ORDER BY Data_Hora DESC LIMIT 1;", abertas$Data_Hora[k]))
      if (nrow(df_k) > 0 && !is.na(df_k$BTCBRL[1])) as.numeric(df_k$BTCBRL[1]) else p_btc_brl
    }, error = function(e) p_btc_brl)
    return(p_exec_k / p_btc_k)
  })
  
  ratio_entrada_fifo <- mean(ratios_compra, na.rm = TRUE)
  if (is.na(ratio_entrada_fifo) || ratio_entrada_fifo <= 0) return(-999.0)
  
  ret_satoshis <- ((ratio_live - ratio_entrada_fifo) / ratio_entrada_fifo) * 100.0
  return(ret_satoshis)
}

obter_stats_paxg_usdt_4h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT PAXGUSDT FROM Historico_binance WHERE PAXGUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
    if (nrow(df) >= 48) {
      p_rec <- rev(df$PAXGUSDT)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      p_sub <- tail(p_5m, min(48, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.50, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 4350.0, sd = 10.0, serie = rep(4350.0, 16), dsp = list(theta = 0, d2Z = 0)))
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

obter_stats_link_4h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # 4 horas = 48 candles de 5m (ou 240 minutos / amostras)
    df <- dbGetQuery(con, "SELECT LINKBRL FROM Historico_binance WHERE LINKBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$LINKBRL)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      p_sub <- tail(p_5m, min(48, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.10, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 60.0, sd = 0.50, serie = rep(60.0, 16), dsp = list(theta = 0, d2Z = 0)))
}

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
    df <- dbGetQuery(con, "SELECT SOLBRL, BTCBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1200;")
    if (nrow(df) >= 30) {
      r_rec <- rev(df$SOLBRL / df$BTCBRL)
      step_5m <- seq(1, length(r_rec), by = 5)
      r_5m <- r_rec[step_5m]
      n_5m <- length(r_5m)
      
      # Calibração G500: Period = 12 candles de 5m (60 min = 1 hora)
      r_fast <- tail(r_5m, min(12, n_5m))
      smooth_fast <- mean(r_fast)
      sd_fast <- max(0.000005, sd(r_fast))
      dsp_fast <- obter_dsp_ativo(r_fast)
      
      # Escala Macro (48 candles de 5m = 4 horas)
      r_macro <- tail(r_5m, min(48, n_5m))
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
        media = smooth_fast,
        sd = sd_fast,
        serie = r_5m
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

obter_stats_sol_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # 1 hora = 12 candles de 5m (ou 60 minutos / amostras)
    df <- dbGetQuery(con, "SELECT SOLBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 150;")
    if (nrow(df) >= 20) {
      p_rec <- rev(df$SOLBRL)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      p_sub <- tail(p_5m, min(12, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.50, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  return(list(media = 750.0, sd = 5.0, serie = rep(750.0, 16), dsp = list(theta = 0, d2Z = 0)))
}

obter_stats_bnb_15m <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BNBBRL FROM Historico_binance WHERE BNBBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$BNBBRL)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      # Calibração G500: Period = 36 candles de 5m (180 min = 3 horas)
      p_sub <- tail(p_5m, min(36, length(p_5m)))
      return(list(media = mean(p_sub, na.rm = TRUE), sd = max(0.20, sd(p_sub, na.rm = TRUE)), serie = p_sub))
    }
  }, error = function(e) NULL)
  return(list(media = 3450.0, sd = 15.0, serie = rep(3450.0, 16)))
}

obter_stats_bnb_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # Janela de 500 minutos = 100 candles de 5m para alimentar Roofing (48p) + STFT Fourier (32p)
    df <- dbGetQuery(con, "SELECT BNBBRL FROM Historico_binance WHERE BNBBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 500;")
    if (nrow(df) >= 30) {
      p_rec <- rev(df$BNBBRL)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      p_sub <- tail(p_5m, min(12, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.50, sd(p_sub, na.rm = TRUE))
      dsp_classico <- obter_dsp_ativo(p_sub)
      dsp_fourier  <- if (exists("obter_dsp_fourier_eth")) obter_dsp_fourier_eth(p_5m) else list(roof_z = 0, fsp = 0, phi_dom = 0, fhri = 0, d2Z = 0, dom_k = 1)
      return(list(media = m_val, sd = s_val, serie = p_sub, serie_5m = p_5m, dsp = dsp_classico, fourier = dsp_fourier))
    }
  }, error = function(e) NULL)
  p_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BNBBRL"), "parsed")$price), error = function(e) 3450.0)
  if (is.null(p_live) || is.na(p_live) || p_live <= 0) p_live <- 3450.0
  return(list(
    media = p_live, sd = 15.0, serie = rep(p_live, 12), serie_5m = rep(p_live, 48),
    dsp = list(theta = 0, dtheta = 0, d2Z = 0),
    fourier = list(roof_z = 0, fsp = 0, phi_dom = 0, fhri = 0, d2Z = 0, dom_k = 1)
  ))
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

obter_stats_sqqqb_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SQQQBUSDT FROM Historico_binance WHERE SQQQBUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 120;")
    if (nrow(df) >= 15) {
      precos <- rev(df$SQQQBUSDT)
      step_5m <- seq(1, length(precos), by = 5)
      p_5m <- precos[step_5m]
      p_sub <- tail(p_5m, min(12, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.01, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  p_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SQQQBUSDT"), "parsed")$price), error = function(e) 38.50)
  if (is.null(p_live) || is.na(p_live) || p_live <= 0) p_live <- 38.50
  return(list(media = p_live, sd = 0.40, serie = rep(p_live, 12), dsp = list(theta = 0, d2Z = 0)))
}

obter_stats_tslab_4h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT TSLABUSDT FROM Historico_binance WHERE TSLABUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 240;")
    if (nrow(df) >= 15) {
      precos <- rev(df$TSLABUSDT)
      step_5m <- seq(1, length(precos), by = 5)
      p_5m <- precos[step_5m]
      p_sub <- tail(p_5m, min(48, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.10, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  p_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=TSLABUSDT"), "parsed")$price), error = function(e) 380.0)
  if (is.null(p_live) || is.na(p_live) || p_live <= 0) p_live <- 380.0
  return(list(media = p_live, sd = 2.50, serie = rep(p_live, 12), dsp = list(theta = 0, d2Z = 0)))
}

obter_stats_aaplb_4h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT AAPLBUSDT FROM Historico_binance WHERE AAPLBUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 240;")
    if (nrow(df) >= 15) {
      precos <- rev(df$AAPLBUSDT)
      step_5m <- seq(1, length(precos), by = 5)
      p_5m <- precos[step_5m]
      p_sub <- tail(p_5m, min(48, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(0.10, sd(p_sub, na.rm = TRUE))
      dsp   <- obter_dsp_ativo(p_sub)
      return(list(media = m_val, sd = s_val, serie = p_sub, dsp = dsp))
    }
  }, error = function(e) NULL)
  p_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=AAPLBUSDT"), "parsed")$price), error = function(e) 340.0)
  if (is.null(p_live) || is.na(p_live) || p_live <= 0) p_live <- 340.0
  return(list(media = p_live, sd = 1.80, serie = rep(p_live, 12), dsp = list(theta = 0, d2Z = 0)))
}

obter_dsp_ativo <- function(vetor_precos) {
  if (is.null(vetor_precos) || length(vetor_precos) < 6) {
    return(list(theta = 0.0, dtheta = 0.0, T0 = 24.0, dZ = 0.0, d2Z = 0.0))
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
  
  # Velocidade angular da fase unwrapped (dtheta/dt)
  dtheta_raw <- theta - ang_prev
  dtheta <- if (dtheta_raw > pi) {
    dtheta_raw - 2 * pi
  } else if (dtheta_raw < -pi) {
    dtheta_raw + 2 * pi
  } else {
    dtheta_raw
  }
  
  ang_diff <- abs(dtheta)
  if (is.na(ang_diff) || ang_diff < 0.05) ang_diff <- 0.2618
  T0 <- max(6.0, min(60.0, (2 * pi) / ang_diff))
  
  return(list(theta = theta, dtheta = dtheta, T0 = T0, dZ = dZ, d2Z = d2Z))
}

# ==============================================================================
# PIPELINE HARMONICUS FOURIER DSP (Ehlers Roofing Filter + STFT Hanning + FHRI)
# ==============================================================================
# Parâmetros calibrados (exemplos representativos do experimento 5m):
# - T_cut = 48 candles (4h): Remove tendências de longo prazo sem defasagem de fase
# - T_smooth = 8 candles (40min): Filtro SuperSmoother de 2 polos contra ruído browniano
# - W = 32 candles (160min): Janela móvel de Transformada Discreta de Fourier com Hanning
# - FSP (Fourier Spectral Purity): Concentração de potência no harmônico dominante (>= 0.45)
# - Phi_dom (Fase Dominante): Ângulo de fase do pico harmônico
# - FHRI (Fourier Harmonic Resonance Index): FSP * (-cos(phi)) -> pico em vales ressonantes (>= 0.20)
# NOTA METODOLÓGICA: Os parâmetros numéricos acima são casos/instâncias calibradas do ecossistema
# e servem de template modular para replicação em outros ativos do portfólio.
obter_dsp_fourier_eth <- function(p) {
  n <- length(p)
  if (n < 36) {
    return(list(roof_z = 0.0, fsp = 0.0, phi_dom = 0.0, fhri = 0.0, dZ = 0.0, d2Z = 0.0, dom_k = 1))
  }
  
  # 1. Ehlers High-Pass de 2 polos (48p)
  alpha1 <- (cos(sqrt(2)*pi/48) + sin(sqrt(2)*pi/48) - 1) / cos(sqrt(2)*pi/48)
  c1 <- (1 - alpha1/2)^2
  c2 <- 2 * (1 - alpha1)
  c3 <- - (1 - alpha1)^2
  hp <- numeric(n)
  for (i in 3:n) {
    hp[i] <- c1 * (p[i] - 2*p[i-1] + p[i-2]) + c2 * hp[i-1] + c3 * hp[i-2]
  }
  
  # 2. SuperSmoother de 2 polos (8p)
  a1 <- exp(-sqrt(2)*pi/8)
  b1 <- 2 * a1 * cos(sqrt(2)*pi/8)
  coef2 <- b1
  coef3 <- - a1 * a1
  coef1 <- 1 - coef2 - coef3
  roofing <- numeric(n)
  for (i in 3:n) {
    roofing[i] <- coef1 * hp[i] + coef2 * roofing[i-1] + coef3 * roofing[i-2]
  }
  
  # 3. Z-Score Normalizado do Roofing
  tail_len <- min(48, n)
  rms_roof <- sqrt(mean(tail(roofing, tail_len)^2)) + 1e-6
  roof_z <- tail(roofing, 1) / rms_roof
  
  # 4. STFT de Fourier (Janela W = 32 candles com Hanning Window)
  W <- 32
  sub_roof <- tail(roofing, W)
  hann <- 0.5 * (1 - cos(2*pi*(0:(W-1))/(W-1)))
  fft_res <- fft(sub_roof * hann)
  pwr <- (Mod(fft_res[2:(W/2 + 1)]))^2
  tot_pwr <- sum(pwr) + 1e-9
  max_pwr <- max(pwr)
  fsp <- max_pwr / tot_pwr
  dom_k <- which.max(pwr)
  th0 <- Arg(fft_res[dom_k + 1])
  phi_dom <- Arg(exp(complex(real = 0, imaginary = (th0 + 2*pi*dom_k*(W - 1)/W))))
  fhri <- fsp * (-cos(phi_dom))
  
  # 5. Métricas de Fourier Sharpe Ratio (FSR) e Largura Média de Banda Espectral (Fator de Risco)
  freqs <- (1:(W/2)) / W
  centroid <- sum(freqs * pwr) / tot_pwr
  bandwidth <- sqrt(sum((freqs - centroid)^2 * pwr) / tot_pwr)
  fator_risco <- bandwidth * (1.0 - fsp)
  fsr <- fhri / (fator_risco + 1e-4)
  
  # 6. Cinemática de Segunda Ordem
  dZ <- (p[n] - p[n-1]) / (p[n-1] + 1e-9)
  d2Z <- if (n >= 3) ((p[n] - p[n-1]) - (p[n-1] - p[n-2])) / (p[n-1] + 1e-9) else 0.0
  
  return(list(
    roof_z = as.numeric(roof_z),
    fsp = as.numeric(fsp),
    phi_dom = as.numeric(phi_dom),
    fhri = as.numeric(fhri),
    centroid = as.numeric(centroid),
    bandwidth = as.numeric(bandwidth),
    fator_risco = as.numeric(fator_risco),
    fsr = as.numeric(fsr),
    dZ = as.numeric(dZ),
    d2Z = as.numeric(d2Z),
    dom_k = as.numeric(dom_k)
  ))
}

obter_dsp_fourier <- obter_dsp_fourier_eth

obter_stats_eth_1h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # Janela de 500 minutos = 100 candles de 5m para alimentar Roofing (48p) + STFT Fourier (32p)
    df <- dbGetQuery(con, "SELECT ETHBRL FROM Historico_binance WHERE ETHBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 500;")
    if (nrow(df) >= 40) {
      p_rec <- rev(df$ETHBRL)
      step_5m <- seq(1, length(p_rec), by = 5)
      p_5m <- p_rec[step_5m]
      p_sub <- tail(p_5m, min(12, length(p_5m)))
      m_val <- mean(p_sub, na.rm = TRUE)
      s_val <- max(5.0, sd(p_sub, na.rm = TRUE))
      dsp_classico <- obter_dsp_ativo(p_sub)
      dsp_fourier  <- obter_dsp_fourier_eth(p_5m)
      return(list(media = m_val, sd = s_val, serie = p_sub, serie_5m = p_5m, dsp = dsp_classico, fourier = dsp_fourier))
    }
  }, error = function(e) NULL)
  p_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) 15000.0)
  if (is.null(p_live) || is.na(p_live) || p_live <= 0) p_live <- 15000.0
  return(list(
    media = p_live, sd = 45.0, serie = rep(p_live, 12), serie_5m = rep(p_live, 48),
    dsp = list(theta = 0, dtheta = 0, d2Z = 0),
    fourier = list(roof_z = 0, fsp = 0, phi_dom = 0, fhri = 0, d2Z = 0, dom_k = 1)
  ))
}

obter_stats_eth_btc_24h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT ETHBRL, BTCBRL FROM Historico_binance WHERE ETHBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 180;")
    if (nrow(df) >= 15) {
      ratios <- rev(df$ETHBRL / df$BTCBRL)
      step_5m <- seq(1, length(ratios), by = 5)
      r_5m <- ratios[step_5m]
      # Calibração G500: Period = 12 candles de 5m (60 min = 1 hora)
      r_sub <- tail(r_5m, min(12, length(r_5m)))
      m_val <- mean(r_sub, na.rm = TRUE)
      sd_val <- max(0.0001, sd(r_sub, na.rm = TRUE))
      return(list(media = m_val, sd = sd_val, serie = r_sub))
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

obter_stats_usdt_24h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    # 24 horas = 288 candles de 5m (ou 1440 registros de 1m)
    df <- dbGetQuery(con, "SELECT USDTBRL FROM Historico_binance WHERE USDTBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1440;")
    if (nrow(df) >= 60) {
      r_u <- rev(df$USDTBRL)
      idx_5m <- rev(seq(length(r_u), 1, by = -5))
      u_5m <- r_u[idx_5m]
      m_u <- mean(u_5m, na.rm = TRUE)
      s_u <- sd(u_5m, na.rm = TRUE)
      if (is.na(s_u) || s_u <= 0) s_u <- 0.015
      z_u <- (tail(u_5m, 1) - m_u) / s_u
      dsp <- obter_dsp_ativo(u_5m)
      return(list(media = m_u, sd = s_u, z = z_u, dsp = dsp, ultimo = tail(u_5m, 1)))
    }
  }, error = function(e) NULL)
  return(list(media = 5.20, sd = 0.02, z = 0.0, dsp = list(d2Z = 0.0), ultimo = 5.20))
}

verificar_cooldown_veto <- function(estrategia_nome, timeout_seg = 300) {
  veto_file <- if (file.exists("vetos_recentes.rds")) "vetos_recentes.rds" else "/app/vetos_recentes.rds"
  if (!file.exists(veto_file)) return(FALSE)
  vetos <- tryCatch(readRDS(veto_file), error = function(e) list())
  if (!is.list(vetos) || is.null(vetos[[estrategia_nome]])) return(FALSE)
  
  registro <- vetos[[estrategia_nome]]
  ts_veto <- as.numeric(registro$timestamp)
  agora <- as.numeric(Sys.time())
  if (!is.na(ts_veto) && (agora - ts_veto) < timeout_seg) {
    return(TRUE)
  }
  return(FALSE)
}

# Subtrava de Coordenação Anti-Canibalização Flecha vs Escudo (mesmo candle de 5m)
verificar_compra_recente_btc <- function(estrategia_nome, timeout_seg = 300) {
  hist_file <- if (file.exists("ordens_executadas.rds")) "ordens_executadas.rds" else "/app/ordens_executadas.rds"
  if (!file.exists(hist_file)) return(FALSE)
  h <- tryCatch(readRDS(hist_file), error = function(e) NULL)
  if (!is.null(h) && nrow(h) > 0 && all(c("Estrategia", "Destino", "Data_Hora") %in% names(h))) {
    sub <- h[h$Estrategia == estrategia_nome & h$Destino == "BTC" & grepl("EXECUTADO_REAL", h$Status), ]
    if (nrow(sub) > 0) {
      last_t <- as.POSIXct(tail(sub$Data_Hora, 1))
      diff_s <- as.numeric(difftime(Sys.time(), last_t, units = "secs"))
      if (!is.na(diff_s) && diff_s < timeout_seg) return(TRUE)
    }
  }
  return(FALSE)
}

calcular_lotes_abertos_fifo <- function(compras, vendas, ativo = "") {
  if (is.null(compras) || nrow(compras) == 0) return(data.frame())
  
  default_asset_prices <- list(
    BTC = 405000.0, ETH = 12500.0, SOL = 492.0, BNB = 3800.0,
    LINK = 60.0, NEAR = 20.0, ADA = 1.10, AVAX = 130.0,
    PAXG = 23500.0, USDT = 5.25, NVDAB = 120.0, SPYB = 550.0,
    SQQQB = 80.0, TLT = 95.0
  )
  def_p <- if (!is.null(default_asset_prices[[ativo]])) default_asset_prices[[ativo]] else 100.0
  
  compras <- compras[order(as.POSIXct(compras$Data_Hora)), , drop = FALSE]
  compras$p_u <- as.numeric(compras$Preco_Exec)
  compras$p_u[is.na(compras$p_u) | compras$p_u <= 0] <- def_p
  compras$qtd <- as.numeric(compras$Valor_BRL) / compras$p_u
  
  if (is.null(vendas) || nrow(vendas) == 0) {
    compras_abertas <- compras
  } else {
    vendas <- vendas[order(as.POSIXct(vendas$Data_Hora)), , drop = FALSE]
    vendas$p_u <- as.numeric(vendas$Preco_Exec)
    vendas$p_u[is.na(vendas$p_u) | vendas$p_u <= 0] <- def_p
    vendas$qtd <- as.numeric(vendas$Valor_BRL) / vendas$p_u
    
    compras$qtd_rem <- compras$qtd
    
    for (j in seq_len(nrow(vendas))) {
      v_time <- as.POSIXct(vendas$Data_Hora[j])
      v_qtd <- vendas$qtd[j]
      
      idx_comp <- which(as.POSIXct(compras$Data_Hora) <= v_time & compras$qtd_rem > 0.0001)
      for (k in idx_comp) {
        if (v_qtd <= 0.0001) break
        abater <- min(v_qtd, compras$qtd_rem[k])
        compras$qtd_rem[k] <- compras$qtd_rem[k] - abater
        v_qtd <- v_qtd - abater
      }
    }
    
    abertas_idx <- which(compras$qtd_rem > 0.0001)
    if (length(abertas_idx) > 0) {
      compras_abertas <- compras[abertas_idx, , drop = FALSE]
      compras_abertas$qtd <- compras_abertas$qtd_rem
      compras_abertas$Valor_BRL <- compras_abertas$qtd * compras_abertas$p_u
    } else {
      compras_abertas <- data.frame()
    }
  }
  
  if (nrow(compras_abertas) > 0) {
    if (sum(compras_abertas$Valor_BRL, na.rm = TRUE) < 5.0 || sum(compras_abertas$qtd, na.rm = TRUE) < 0.0005) {
      compras_abertas <- data.frame()
    }
  }
  
  return(compras_abertas)
}

obter_lote_aberto_binance_ssot <- function(ativo) {
  if (!exists("call_binance")) return(NULL)
  tryCatch({
    sym <- if (ativo %in% c("NVDAB", "SPYB", "SQQQB", "TLT", "TSLAB", "AAPLB", "PAXG")) {
      sprintf("%sUSDT", ativo)
    } else {
      sprintf("%sBRL", ativo)
    }
    trades <- call_binance("/api/v3/myTrades", list(symbol = sym, limit = 100))
    if (is.null(trades) || length(trades) == 0) return(NULL)
    
    df <- if (is.data.frame(trades)) trades else dplyr::bind_rows(trades)
    if (nrow(df) == 0) return(NULL)
    
    df$time_num <- as.numeric(df$time)
    df$price_num <- as.numeric(df$price)
    df$qty_num <- as.numeric(df$qty)
    df$is_buy <- df$isBuyer == TRUE | df$isBuyer == "true"
    df <- df[order(df$time_num), ]
    
    compras <- list()
    for (i in 1:nrow(df)) {
      row <- df[i, ]
      if (row$is_buy) {
        compras[[length(compras) + 1]] <- list(time = row$time_num, price = row$price_num, qty = row$qty_num, rem = row$qty_num)
      } else {
        q_v <- row$qty_num
        for (k in seq_along(compras)) {
          if (q_v <= 1e-8) break
          if (compras[[k]]$rem > 1e-8) {
            match_q <- min(q_v, compras[[k]]$rem)
            compras[[k]]$rem <- compras[[k]]$rem - match_q
            q_v <- q_v - match_q
          }
        }
      }
    }
    
    total_rem <- 0
    custo_total <- 0
    primeiro_preco <- NA
    primeiro_ts <- NA
    n_abertos <- 0
    
    for (c in compras) {
      if (c$rem > 1e-6) {
        if (is.na(primeiro_preco)) {
          primeiro_preco <- c$price
          primeiro_ts <- c$time
        }
        total_rem <- total_rem + c$rem
        custo_total <- custo_total + (c$rem * c$price)
        n_abertos <- n_abertos + 1
      }
    }
    
    if (total_rem > 1e-4 && custo_total > 5.0) {
      vwap_real <- custo_total / total_rem
      min_posse <- if (!is.na(primeiro_ts)) (as.numeric(Sys.time()) - (primeiro_ts / 1000)) / 60 else 999.0
      return(list(
        tem_lote = TRUE,
        n_lotes_abertos = n_abertos,
        minutos_posse = min_posse,
        minutos_desde_venda = 999.0,
        preco_compra = primeiro_preco,
        vwap_abertos = vwap_real,
        valor_compra = primeiro_preco * total_rem,
        data_compra = if (!is.na(primeiro_ts)) as.character(as.POSIXct(primeiro_ts / 1000, origin = "1970-01-01", tz = "America/Sao_Paulo")) else as.character(Sys.time()),
        qtd_aberta = total_rem,
        valor_total_aberto = custo_total
      ))
    }
  }, error = function(e) NULL)
  return(NULL)
}

obter_lote_aberto_estrategia <- function(estrategia_nome, ativo) {
  # 🛡️ SSOT BINANCE API: Prioridade absoluta para apuração real de lotes abertos Spot (Imune a desyncs locais)
  if (ativo %in% c("NEAR", "LINK", "SOL", "BNB", "ETH", "BTC", "PAXG", "TSLAB", "SPYB", "NVDAB", "SQQQB")) {
    lote_binance <- obter_lote_aberto_binance_ssot(ativo)
    if (!is.null(lote_binance) && isTRUE(lote_binance$tem_lote)) {
      return(lote_binance)
    }
  }
  
  hist_exec_file <- if (file.exists("ordens_executadas.rds")) "ordens_executadas.rds" else "/app/ordens_executadas.rds"
  if (!file.exists(hist_exec_file)) return(list(tem_lote = TRUE, minutos_posse = 999.0))
  
  hist_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
  if (is.null(hist_exec) || nrow(hist_exec) == 0 || !"Estrategia" %in% names(hist_exec)) {
    return(list(tem_lote = TRUE, minutos_posse = 999.0))
  }
  
  exec_reais <- hist_exec[grepl("EXECUTADO_REAL", hist_exec$Status), ]
  if (nrow(exec_reais) == 0) {
    return(list(tem_lote = FALSE, minutos_posse = 0.0))
  }
  
  # Vendas e Compras que definem a custódia:
  # Ativos de titularidade exclusiva de uma estratégia: balanceamento físico global do ativo
  ativos_exclusivos <- c("NEAR", "LINK", "SOL", "BNB", "ADA", "AVAX", "NVDAB", "SPYB", "SQQQB", "TLT", "ETH")
  if (ativo %in% ativos_exclusivos) {
    compras <- exec_reais[exec_reais$Destino == ativo, ]
    vendas  <- exec_reais[exec_reais$Origem == ativo, ]
  } else {
    filtro_patria <- if (estrategia_nome == "PLANO_PATRIA_VOLATIL") exec_reais$Valor_BRL <= 350.0 else TRUE
    compras <- exec_reais[exec_reais$Destino == ativo & exec_reais$Estrategia == estrategia_nome & filtro_patria, ]
    vendas <- exec_reais[exec_reais$Origem == ativo & (exec_reais$Estrategia == estrategia_nome | exec_reais$Estrategia %in% c("PLANO_ADEUS_PERRY", "PLANO_BRUCE_WAYNE")), ]
  }
  
  if (nrow(compras) == 0) {
    return(list(tem_lote = FALSE, minutos_posse = 0.0))
  }
  
  compras_abertas <- calcular_lotes_abertos_fifo(compras, vendas, ativo = ativo)
  
  if (nrow(compras_abertas) > 0) {
    lote_ativo <- compras_abertas[1, ]
    p_fifo <- lote_ativo$Preco_Exec
    vwap_abertos <- sum(compras_abertas$Valor_BRL) / sum(compras_abertas$qtd)
    minutos_posse <- as.numeric(difftime(Sys.time(), as.POSIXct(lote_ativo$Data_Hora), units = "mins"))
    
    return(list(
      tem_lote = TRUE,
      n_lotes_abertos = nrow(compras_abertas),
      minutos_posse = minutos_posse,
      minutos_desde_venda = 999.0,
      preco_compra = p_fifo,
      vwap_abertos = vwap_abertos,
      valor_compra = lote_ativo$Valor_BRL,
      data_compra = lote_ativo$Data_Hora,
      qtd_aberta = sum(compras_abertas$qtd),
      valor_total_aberto = sum(compras_abertas$Valor_BRL)
    ))
  }
  
  ultimo_trade_venda <- if (nrow(vendas) > 0) tail(vendas, 1) else NULL
  minutos_desde_venda <- if (!is.null(ultimo_trade_venda)) {
    as.numeric(difftime(Sys.time(), as.POSIXct(ultimo_trade_venda$Data_Hora), units = "mins"))
  } else 999.0
  
  return(list(
    tem_lote = FALSE,
    n_lotes_abertos = 0,
    minutos_posse = 0.0,
    minutos_desde_venda = minutos_desde_venda
  ))
}

obter_vwap_ativo <- function(ativo_sym) {
  hist_exec_file <- if (file.exists("ordens_executadas.rds")) "ordens_executadas.rds" else "/app/ordens_executadas.rds"
  if (file.exists(hist_exec_file)) {
    h_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
    if (!is.null(h_exec) && nrow(h_exec) > 0 && all(c("Destino", "Origem", "Status") %in% names(h_exec))) {
      exec_reais <- h_exec[grepl("EXECUTADO_REAL", h_exec$Status), ]
      compras_todas <- exec_reais[exec_reais$Destino == ativo_sym, ]
      vendas_todas  <- exec_reais[exec_reais$Origem == ativo_sym, ]
      
      compras <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas)
      if (nrow(compras) > 0) {
        # Blindagem: se for PAXG, expurga registros antigos com Preco_Exec em BTC (< 1000)
        if (ativo_sym == "PAXG") {
          compras <- compras[!is.na(compras$Preco_Exec) & compras$Preco_Exec > 1000.0, , drop = FALSE]
        }
        if (nrow(compras) > 0) {
          tot_qtd <- sum(compras$qtd, na.rm = TRUE)
          tot_val <- sum(compras$Valor_BRL, na.rm = TRUE)
          vwap_calc <- if (tot_qtd > 0) tot_val / tot_qtd else as.numeric(tail(compras$Preco_Exec, 1))
          if (!is.na(vwap_calc) && vwap_calc > 0) return(vwap_calc)
        }
      }
    }
  }
  # Fallbacks auditados de custo de aquisição na Binance (SSOT):
  fallbacks_vwap <- list(PAXG = 23576.0, ADA = 1.083, LINK = 59.00, NEAR = 22.50, AVAX = 135.0)
  if (!is.null(fallbacks_vwap[[ativo_sym]])) return(fallbacks_vwap[[ativo_sym]])
  return(0.0)
}

# ------------------------------------------------------------------------------
# 🛡️ SUBTRAVA 6.2: TARGET DECAY RATCHET (DESENGASGO TEMPORAL DINÂMICO)
# Decaimento linear suave de meta para posições longas em calmaria/lateralização
# NUNCA perfura o piso soberano da Trava 6 Breakeven FIFO (+0.40% líquido)
# ------------------------------------------------------------------------------
calcular_meta_lucro_decay <- function(minutos_posse, meta_base = 0.50, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40) {
  if (is.null(minutos_posse) || is.na(minutos_posse) || minutos_posse <= 0) return(meta_base)
  horas_posse <- minutos_posse / 60.0
  if (horas_posse <= horas_inicio_decay) {
    return(meta_base)
  }
  duracao_transicao <- max(1.0, horas_fim_decay - horas_inicio_decay)
  fator <- min(1.0, (horas_posse - horas_inicio_decay) / duracao_transicao)
  meta_dinamica <- meta_base - fator * (meta_base - piso_minimo)
  return(max(piso_minimo, round(meta_dinamica, 2)))
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
  
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  
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
  p_avax_brl  <- obter_preco_binance("AVAXBRL")
  
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
  
  stats_guiana   <- obter_stats_guiana_72h(p_paxg_usdt)
  stats_link     <- obter_stats_link_1h()
  stats_link_4h  <- obter_stats_link_4h()
  stats_sol_btc  <- obter_stats_sol_btc_72h()
  stats_sol_15m  <- obter_stats_sol_15m()
  stats_sol_1h   <- obter_stats_sol_1h()
  stats_eth_btc  <- obter_stats_eth_btc_24h()
  stats_eth_1h   <- obter_stats_eth_1h()
  stats_bnb      <- obter_stats_bnb_15m()
  stats_bnb_1h   <- obter_stats_bnb_1h()
  stats_ada      <- obter_stats_ada_30m()
  stats_near     <- obter_stats_near_24h()
  stats_near_10h <- obter_stats_near_10h()
  stats_near_6h  <- obter_stats_near_6h()
  stats_avax     <- obter_stats_avax_1h()
  stats_sqqqb_1h <- obter_stats_sqqqb_1h()
  ret_btc_5m     <- obter_retorno_btc_5m()
  
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
  saldo_avax_brl  <- 0
  saldo_usdt_brl  <- 0
  saldo_usdt_usd  <- 0
  saldo_nvdab_usd <- 0
  saldo_spyb_usd  <- 0
  saldo_sqqqb_usd <- 0
  saldo_tlt_usd   <- 0
  saldo_tslab_usd <- 0
  saldo_aaplb_usd <- 0
  val_eq_brl      <- 0.0
  
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
    if (any(df_w$asset %in% c("AVAX", "LDAVAX")) && !is.null(p_avax_brl)) saldo_avax_brl <- sum(df_w$free[df_w$asset %in% c("AVAX", "LDAVAX")], na.rm = TRUE) * p_avax_brl
    if (any(df_w$asset %in% c("USDT", "LDUSDT"))) {
      saldo_usdt_usd  <- sum(df_w$free[df_w$asset %in% c("USDT", "LDUSDT")], na.rm = TRUE)
      saldo_usdt_brl  <- saldo_usdt_usd * p_usdt_brl
    }
    if (any(df_w$asset %in% c("NVDAB", "NVDA"))) saldo_nvdab_usd <- sum(df_w$free[df_w$asset %in% c("NVDAB", "NVDA")], na.rm = TRUE)
    if (any(df_w$asset %in% c("SPYB", "SP500"))) saldo_spyb_usd  <- sum(df_w$free[df_w$asset %in% c("SPYB", "SP500")], na.rm = TRUE)
    if (any(df_w$asset %in% c("SQQQB", "BITI"))) saldo_sqqqb_usd <- sum(df_w$free[df_w$asset %in% c("SQQQB", "BITI")], na.rm = TRUE)
    if (any(df_w$asset %in% c("TLT", "TLTB")))   saldo_tlt_usd   <- sum(df_w$free[df_w$asset %in% c("TLT", "TLTB")], na.rm = TRUE)
    if (any(df_w$asset %in% c("TSLAB", "TSLA"))) saldo_tslab_usd <- sum(df_w$free[df_w$asset %in% c("TSLAB", "TSLA")], na.rm = TRUE)
    if (any(df_w$asset %in% c("AAPLB", "AAPL"))) saldo_aaplb_usd <- sum(df_w$free[df_w$asset %in% c("AAPLB", "AAPL")], na.rm = TRUE)
    
    obter_px_eq <- function(sym, fallback) {
      px <- tryCatch({
        r <- content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", sym, "USDT")), "parsed")
        if (!is.null(r$price)) as.numeric(r$price) else fallback
      }, error = function(e) fallback)
      if (is.null(px) || length(px) == 0 || is.na(px) || px <= 0) px <- fallback
      return(px)
    }
    
    p_nv_tmp <- obter_px_eq("NVDAB", 178.0)
    p_sp_tmp <- obter_px_eq("SPYB", 658.0)
    p_sq_tmp <- obter_px_eq("SQQQB", 40.5)
    p_tl_tmp <- 95.0
    p_ts_tmp <- obter_px_eq("TSLAB", 380.0)
    p_ap_tmp <- obter_px_eq("AAPLB", 340.0)
    
    val_eq_usd <- (saldo_nvdab_usd * p_nv_tmp) +
                  (saldo_spyb_usd  * p_sp_tmp) +
                  (saldo_sqqqb_usd * p_sq_tmp) +
                  (saldo_tlt_usd   * p_tl_tmp) +
                  (saldo_tslab_usd * p_ts_tmp) +
                  (saldo_aaplb_usd * p_ap_tmp)
    if (is.na(val_eq_usd) || length(val_eq_usd) == 0) val_eq_usd <- 0.0
    val_eq_brl <- val_eq_usd * p_usdt_brl
  }
  
  total_patrimonio_est <- saldo_caixa_brl + saldo_btc_brl + saldo_paxg_brl + saldo_sol_brl + saldo_eth_brl + saldo_link_brl + saldo_bnb_brl + saldo_ada_brl + saldo_near_brl + saldo_avax_brl + saldo_usdt_brl + val_eq_brl
  if (is.na(total_patrimonio_est) || length(total_patrimonio_est) == 0 || total_patrimonio_est <= 0) total_patrimonio_est <- 3210.0
  peso_btc <- ifelse(total_patrimonio_est > 0, saldo_btc_brl / total_patrimonio_est, 0.35)
  
  # --- SIZING PROPORCIONAL DINÂMICO (% DO PATRIMÔNIO CONSOLIDADO REAL) ---
  # Escala automaticamente as ordens conforme novos aportes ou lucros são realizados (sem hardcoding)
  VALOR_SAGARANA_BRL          <- max(50.0, total_patrimonio_est * 0.095) #  9.5% - Flecha de Sagarana (BTC)
  VALOR_ESCUDO_BRL            <- max(50.0, total_patrimonio_est * 0.090) #  9.0% - Escudo de Aquiles (BTC)
  VALOR_VIX_BRL               <- VALOR_ESCUDO_BRL
  VALOR_PATRIA_BRL            <- max(50.0, total_patrimonio_est * 0.080) #  8.0% - Pátria Volátil (USDT)
  VALOR_SQQQB_BRL             <- max(30.0, total_patrimonio_est * 0.085) #  8.5% - Sentinela Antifrágil (SQQQB)
  VALOR_TITA_USDT_DIP         <- max(15.0, (total_patrimonio_est * 0.075) / p_usdt_brl) # 7.5% - Titã Dip (NVDAB)
  VALOR_TITA_USDT_CRASH       <- max(20.0, (total_patrimonio_est * 0.115) / p_usdt_brl) # 11.5% - Titã Crash (NVDAB)
  VALOR_WALLSTREET_USDT       <- max(20.0, (total_patrimonio_est * 0.080) / p_usdt_brl) # 8.0% - Harmonicus Wall St (SPYB)
  VALOR_WALLSTREET_USDT_DIP   <- VALOR_WALLSTREET_USDT
  VALOR_WALLSTREET_USDT_CRASH <- VALOR_WALLSTREET_USDT
  VALOR_TESLA_USDT            <- max(20.0, (total_patrimonio_est * 0.070) / p_usdt_brl) # 7.0% - Raio de Tesla (TSLAB)
  VALOR_DUELO_TITAS_USDT      <- VALOR_TESLA_USDT
  VALOR_OURO_LIQUIDO_USDT     <- max(15.0, (total_patrimonio_est * 0.048) / p_usdt_brl) # 4.8% - Ouro Líquido (PAXG)
  VALOR_GUIANA_BRL            <- max(30.0, total_patrimonio_est * 0.045) #  4.5% - Guiana Brasileira (PAXG <-> BTC)
  VALOR_ETH_TRANCHE_BRL       <- max(25.0, total_patrimonio_est * 0.046) #  4.6% - Sentinela de Éter (ETH Tranche, Cap 3x = 13.8%)
  VALOR_TITAS_BRL             <- VALOR_ETH_TRANCHE_BRL
  VALOR_SOL_SENTINELA_BRL     <- max(30.0, total_patrimonio_est * 0.045) #  4.5% - Sentinela do Sol (SOL)
  VALOR_CABOCLO_BRL           <- max(25.0, total_patrimonio_est * 0.040) #  4.0% - Caboclo dos Oráculos (LINK)
  VALOR_BNB_BRL               <- max(370.0, total_patrimonio_est * 0.1135) # 11.35% - Sentinela de Minas (BNB | 370 reais)
  VALOR_BNB_TRANCHE_BRL       <- VALOR_BNB_BRL / 2.0                       #  5.68% - Tranche Individual (~185 reais)
  VALOR_NEAR_BRL              <- max(25.0, total_patrimonio_est * 0.035) #  3.5% - Farol de Near (NEAR)
  VALOR_CHOQUE_BRL            <- max(25.0, total_patrimonio_est * 0.028) #  2.8% - Choque Energético (XLE)
  VALOR_TLT_BRL               <- max(25.0, total_patrimonio_est * 0.025) #  2.5% - Escudo de Washington (TLT)
  VALOR_PERRY_BRL             <- max(30.0, total_patrimonio_est * 0.055) #  5.5% - Adeus, Perry (Desova Ouro > 20%)
  
  # 💵 Corredor Dinâmico de Dólar USDT: Piso de 40% no Simple Earn (Intocável) e Teto de 60%
  # Garante que o valor em dólares NUNCA zera e rende 6,88% a.a. passivamente no Simple Earn
  piso_usdt_brl_dinamico <- max(500.0, total_patrimonio_est * 0.40)
  teto_usdt_brl_dinamico <- max(1200.0, total_patrimonio_est * 0.60)
  piso_usdt_usd_dinamico <- piso_usdt_brl_dinamico / p_usdt_brl
  usdt_livre_rotacao     <- max(0.0, saldo_usdt_usd - piso_usdt_usd_dinamico)
  
  # 🇧🇷 Corredor Dinâmico de Caixa BRL: Piso de 10% e Teto de 20% (Anti-Ociosidade - Cenário B)
  piso_brl_dinamico      <- max(200.0, total_patrimonio_est * 0.10)
  teto_brl_dinamico      <- max(400.0, total_patrimonio_est * 0.20)
  caixa_brl_livre_patria <- max(0.0, saldo_caixa_brl - piso_brl_dinamico)
  caixa_brl_livre_cripto <- max(0.0, saldo_caixa_brl - 20.0) # Válvula de Dip Cripto (Opção 2)
  caixa_brl_livre        <- caixa_brl_livre_patria
  
  # 🥇 Governança Dinâmica de Ouro: Piso Estrutural de 10% (Intocável) e Teto Operacional de 20%
  piso_ouro_dinamico <- max(200.0, total_patrimonio_est * 0.10)
  teto_ouro_dinamico <- max(400.0, total_patrimonio_est * 0.20)
  
  # 🛡️ TETOS INDIVIDUAIS DINÂMICOS DE EXPOSIÇÃO POR ATIVO (GOVERNANÇA CENTRALIZADA)
  # Garante que nenhum criptoativo ultrapasse sua cota máxima no patrimônio consolidado vivo
  teto_bnb_brl  <- max(370.0, total_patrimonio_est * 0.120) # Teto BNB: 370 reais fixado / 12,0%
  teto_btc_brl  <- max(450.0, total_patrimonio_est * 0.200) # Teto BTC: 450 reais / 20,0%
  teto_eth_brl  <- max(450.0, total_patrimonio_est * 0.150) # Teto ETH: 450 reais / 15,0% (Cap 3 tranches de 4,6%)
  teto_sol_brl  <- max(250.0, total_patrimonio_est * 0.080) # Teto SOL: 250 reais / 8,0%
  teto_link_brl <- max(200.0, total_patrimonio_est * 0.065) # Teto LINK: 200 reais / 6,5%
  teto_near_brl <- max(180.0, total_patrimonio_est * 0.055) # Teto NEAR: 180 reais / 5,5%
  teto_ada_brl  <- max(60.0,  total_patrimonio_est * 0.020) # Teto ADA: 60 reais / 2,0%
  teto_avax_brl <- max(60.0,  total_patrimonio_est * 0.020) # Teto AVAX: 60 reais / 2,0%
  
  pedido <- NULL
  
  # ----------------------------------------------------------------------------
  # MOTOR 1: PLANO GUIANA BRASILEIRA (PAXG <-> BTC | Calibrado 12h / Alta Seletividade)
  # Metricas 5m Contínuos (158k candles / 18,1m): +2,97 reais/m (+112%) | 1,5 trades/mês | Posse: 189,4h
  # Payoff por trade: +1,93 reais | Win Rate: 100,0% | TP: +1,20% | Z: ±1,50σ
  # Segregação Estrita: Só opera seus próprios lotes de BTC e PAXG. Pré-Filtro Satoshis Lock ativo.
  # ----------------------------------------------------------------------------
  ratio_guiana <- p_paxg_brl / p_btc_brl
  z_guiana     <- (ratio_guiana - stats_guiana$media) / stats_guiana$sd
  dsp_guiana   <- if (!is.null(stats_guiana$dsp)) stats_guiana$dsp else list(theta = 0, d2Z = 0)
  
  lote_guiana_btc  <- obter_lote_aberto_estrategia("PLANO_GUIANA_BRASILEIRA", "BTC")
  lote_guiana_paxg <- obter_lote_aberto_estrategia("PLANO_GUIANA_BRASILEIRA", "PAXG")
  
  # Ponta A: Bitcoin eufórico / Ouro com desconto -> Vende BTC e compra PAXG (exige lote aberto próprio de BTC)
  can_sell_btc_guiana <- isTRUE(lote_guiana_btc$tem_lote) && saldo_btc_brl >= 28.0 && saldo_paxg_brl < teto_ouro_dinamico
  if (z_guiana <= -1.50 && dsp_guiana$d2Z >= -0.015 && can_sell_btc_guiana) {
    lote_g <- min(75.0 * fator_lote, max(28.0, saldo_btc_brl * 0.95))
    if (lote_g >= 28.0 && lote_g <= saldo_btc_brl) {
      pedido <- list(
        estrategia = "PLANO_GUIANA_BRASILEIRA",
        origem = "BTC", destino = "PAXG",
        valor_brl = lote_g, lucro_esperado_pct = 1.20, timestamp = agora_ts
      )
    }
  } else if (z_guiana >= 1.50 && isTRUE(lote_guiana_paxg$tem_lote)) {
    # Ponta B: Ouro valorizado / Bitcoin em dip -> Vende PAXG e compra BTC (preservando piso estrutural de 10%)
    # 🛡️ Pré-filtro Satoshis Lock: Só dispara se o retorno do lote de PAXG em Satoshis for >= +0.40% (TP: +1.20%)
    ret_satoshis_guiana <- obter_retorno_satoshis_guiana(p_paxg_brl, p_btc_brl)
    cooldown_veto_guiana <- verificar_cooldown_veto("PLANO_GUIANA_BRASILEIRA", timeout_seg = 300)
    folga_ouro <- saldo_paxg_brl - piso_ouro_dinamico
    
    if (ret_satoshis_guiana >= 0.40 && !cooldown_veto_guiana && folga_ouro >= 28.0) {
      lote_g <- min(90.0 * fator_lote, folga_ouro)
      if (lote_g >= 28.0) {
        pedido <- list(
          estrategia = "PLANO_GUIANA_BRASILEIRA",
          origem = "PAXG", destino = "BTC",
          valor_brl = lote_g,
          lucro_esperado_pct = 1.20, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 2: PLANO ESCUDO DE AQUILES (BRL -> BTC | Calibrado Cientificamente no Torneio)
  # Metricas Calibradas 180d: +12,06 reais/m (+0,37%/m) | Max: +51,16 reais/m | Win Rate: 94,7%
  # Arquitetura Vencedora: Inflexão Cinemática Multi-Escala + DCA em 2 Tranches + VWAP + Target Decay
  # Coordenação Anti-Canibalização: Bloqueado se Flecha de Sagarana comprou BTC nos últimos 300s
  # Segregação Estrita: Saída de BTC exige lote próprio de Escudo de Aquiles
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    bloqueio_canibalizacao_escudo <- verificar_compra_recente_btc("PLANO_FLECHA_DE_SAGARANA", 300)
    stats_btc_escudo <- obter_stats_btc_dual_scale()
    z_btc_escudo <- (p_btc_brl - stats_btc_escudo$media_fast) / stats_btc_escudo$sd_fast
    acc_btc_escudo <- stats_btc_escudo$dsp_fast$d2Z
    
    lote_escudo_btc <- obter_lote_aberto_estrategia("PLANO_ESCUDO_DE_AQUILES", "BTC")
    
    # 1. Ponta B (Saída sob Trava 6 Breakeven FIFO/VWAP com Subtrava 6.2 Target Decay Ratchet)
    if (isTRUE(lote_escudo_btc$tem_lote) && saldo_btc_brl >= 25.0) {
      p_ref_escudo <- if (!is.null(lote_escudo_btc$vwap_abertos) && !is.na(lote_escudo_btc$vwap_abertos) && lote_escudo_btc$vwap_abertos > 0) {
        lote_escudo_btc$vwap_abertos
      } else if (!is.null(lote_escudo_btc$preco_compra) && lote_escudo_btc$preco_compra > 0) {
        lote_escudo_btc$preco_compra
      } else {
        p_btc_brl
      }
      ret_real_escudo <- ((p_btc_brl - p_ref_escudo) / p_ref_escudo) * 100.0
      
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (48h a 72h decaindo suavemente até +0.40% piso)
      meta_alvo_escudo <- calcular_meta_lucro_decay(lote_escudo_btc$minutos_posse, meta_base = 0.65, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      
      deve_vender_escudo <- ((ret_real_escudo >= 1.20) || 
                             (ret_real_escudo >= meta_alvo_escudo && (z_btc_escudo >= 0.15 || vix_atual < 18.50)) ||
                             (ret_real_escudo >= 0.40 && !is.null(lote_escudo_btc$minutos_posse) && lote_escudo_btc$minutos_posse >= 4320.0))
      
      if (deve_vender_escudo) {
        valor_desova_escudo <- min(VALOR_ESCUDO_BRL * fator_lote, saldo_btc_brl)
        if (valor_desova_escudo >= 25.0) {
          pedido <- list(
            estrategia = "PLANO_ESCUDO_DE_AQUILES",
            origem = "BTC", destino = "BRL",
            valor_brl = valor_desova_escudo,
            lucro_esperado_pct = round(ret_real_escudo, 2), timestamp = agora_ts
          )
        }
      }
    }
    
    # 2. Ponta A (Entrada em Duas Tranches com Inflexão Cinemática Real d2Z >= 0.0 e Blindagem Macro PC1 < 0.72)
    if (is.null(pedido) && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0 && !bloqueio_canibalizacao_escudo && caixa_brl_livre_cripto >= 25.0) {
      n_abertos <- if (isTRUE(lote_escudo_btc$tem_lote)) lote_escudo_btc$n_lotes_abertos else 0
      
      # Tranche 1: Dip intradiário Z <= -1.10 com convexidade d2Z >= 0.0
      cond_tranche_1 <- (n_abertos == 0) && (z_btc_escudo <= -1.10) && (acc_btc_escudo >= 0.0) && (peso_btc < 0.50) && (saldo_btc_brl < teto_btc_brl)
      
      # Tranche 2: Capitulação mais profunda Z <= -1.80 com preço <= 98.8% do primeiro lote
      p_primeiro_lote <- if (isTRUE(lote_escudo_btc$tem_lote) && !is.null(lote_escudo_btc$preco_compra)) lote_escudo_btc$preco_compra else p_btc_brl
      cond_tranche_2 <- (n_abertos == 1) && (z_btc_escudo <= -1.80) && (acc_btc_escudo >= 0.0) && (p_btc_brl <= p_primeiro_lote * 0.988) && (peso_btc < 0.55) && (saldo_btc_brl < teto_btc_brl)
      
      if (cond_tranche_1 || cond_tranche_2) {
        lote_escudo_tranche <- min(VALOR_ESCUDO_BRL * 0.50 * fator_lote, max(25.0, caixa_brl_livre_cripto * 0.50))
        lote_escudo_tranche <- min(lote_escudo_tranche, caixa_brl_livre_cripto)
        if (lote_escudo_tranche >= 25.0) {
          pedido <- list(
            estrategia = "PLANO_ESCUDO_DE_AQUILES",
            origem = "BRL", destino = "BTC",
            valor_brl = lote_escudo_tranche,
            lucro_esperado_pct = 0.65, timestamp = agora_ts
          )
        }
      }
    }
  }
  
  
  # ----------------------------------------------------------------------------
  # MOTOR 3: PLANO PÁTRIA VOLÁTIL / SENTINELA CAMBIAL (BRL <-> USDT | 24h Swing Calibrado)
  # Calibração Científica 17,8 meses (155.979 candles de 5m / 100 iterações estocásticas):
  # Lucro Médio: +7,54 a +10,45 reais/mês (+0,37% a +0,515%/mês) | Mediana: +8,20 reais/mês
  # Trades/mês: 1,17 | Tempo Médio de Posse: 487,6h (~20,3d) | Max DD MTM: -2,56%
  # Janela de Regime: 24 horas (288 candles de 5m / 1440 min)
  # Entrada Dip: Z_24h <= -1.50 | Saída Trava 6: Z_24h >= +0.40 com Retorno FIFO >= +0.40%
  # Rendimento Duplo: USDT adquirido rende juros diários no Simple Earn (6,88% a.a.) durante a posse
  # ----------------------------------------------------------------------------
  stats_u_24h <- obter_stats_usdt_24h()
  z_patria    <- stats_u_24h$z
  
  if (is.null(pedido) && !is.null(p_usdt_brl) && p_usdt_brl > 0) {
    # 1. Checagem de Lote em Aberto para Realização de Lucro sob Trava 6
    pm_patria <- 0.0
    tem_lote_patria <- FALSE
    hist_exec_file <- "ordens_executadas.rds"
    if (file.exists(hist_exec_file)) {
      h_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
      if (!is.null(h_exec) && nrow(h_exec) > 0 && "Destino" %in% names(h_exec)) {
        exec_reais <- h_exec[grepl("EXECUTADO_REAL", h_exec$Status), ]
        # Considera apenas lotes de swing intradiário (Valor_BRL <= 350), preservando o colchão estrutural do Simple Earn
        compras_todas <- exec_reais[exec_reais$Destino == "USDT" & 
                                    exec_reais$Estrategia == "PLANO_PATRIA_VOLATIL" & 
                                    exec_reais$Valor_BRL <= 350.0, ]
        vendas_todas  <- exec_reais[exec_reais$Origem == "USDT" & 
                                    exec_reais$Estrategia == "PLANO_PATRIA_VOLATIL", ]
        compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas)
        if (nrow(compras_abertas) > 0) {
          validos <- compras_abertas[!is.na(compras_abertas$Preco_Exec) & compras_abertas$Preco_Exec > 0 & !is.na(compras_abertas$Valor_BRL), ]
          if (nrow(validos) > 0) {
            pm_patria <- sum(validos$Valor_BRL) / sum(validos$qtd)
            tem_lote_patria <- TRUE
          }
        }
      }
    }
    
    # 2. REALIZAÇÃO DE LUCRO: Venda USDT -> BRL (Z >= +0.40 e Trava 6 >= +0.40%)
    if (tem_lote_patria && pm_patria > 0 && usdt_livre_rotacao >= 20.0) {
      ret_patria <- (p_usdt_brl - pm_patria) / pm_patria
      em_cooldown_patria <- verificar_cooldown_veto("PLANO_PATRIA_VOLATIL", timeout_seg = 300)
      if (z_patria >= 0.40 && ret_patria >= 0.0040 && !em_cooldown_patria) {
        val_desova_patria <- min(usdt_livre_rotacao * p_usdt_brl, VALOR_PATRIA_BRL * fator_lote * (1 + ret_patria))
        if (val_desova_patria >= 25.0) {
          pedido <- list(
            estrategia = "PLANO_PATRIA_VOLATIL",
            origem = "USDT", destino = "BRL",
            valor_brl = val_desova_patria,
            lucro_esperado_pct = round(ret_patria * 100, 2), timestamp = agora_ts
          )
        }
      }
    } else if (saldo_usdt_brl < teto_usdt_brl_dinamico) {
      # 3. ENTRADA EM DIP CAMBIAL OU SWEEP ANTI-OCIOSIDADE DO EXCESSO DE BRL (CENÁRIO B)
      # Se o caixa BRL exceder o teto dinâmico de 20% (~640 reais), varre o excesso para USDT Simple Earn (6,88% a.a.)
      excesso_caixa_brl <- max(0.0, saldo_caixa_brl - teto_brl_dinamico)
      cond_sweep_ociosidade <- excesso_caixa_brl >= 50.0
      cond_dip_cambial <- (!tem_lote_patria) && (z_patria <= -1.50) && (caixa_brl_livre_patria >= 80.0)
      
      em_cooldown_patria <- verificar_cooldown_veto("PLANO_PATRIA_VOLATIL", timeout_seg = 300)
      if ((cond_dip_cambial || cond_sweep_ociosidade) && !em_cooldown_patria) {
        val_compra <- if (cond_sweep_ociosidade) {
          min(excesso_caixa_brl, VALOR_PATRIA_BRL * 1.5 * fator_lote, 480.0)
        } else {
          min(VALOR_PATRIA_BRL * fator_lote, caixa_brl_livre_patria, 480.0)
        }
        if (val_compra >= 50.0) {
          pedido <- list(
            estrategia = "PLANO_PATRIA_VOLATIL",
            origem = "BRL", destino = "USDT",
            valor_brl = val_compra,
            lucro_esperado_pct = 0.45, timestamp = agora_ts
          )
        }
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 4: PLANO TITÃ DO SILÍCIO (USDT <-> NVDAB | Harmonicus SX + Riscos Turbo)
  # [VENCEDOR DO TORNEIO QUANTITATIVO HEAD-TO-HEAD // +131,5% DE LUCRO REAL (2,31x)]
  # Metricas: +34,19 reais/m (+0,647%/m) | Posse: 41,8h | Trava 6 FIFO >= +0.45% ágil / +0.60% a +1.20% adaptativo
  # Binance Backed Equity Spot: NVDABUSDT | Lote Dinâmico FSR (45 a 72 USDT)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    p_nvda_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=NVDABUSDT"), "parsed")$price), error = function(e) NULL)
    lote_nvda <- obter_lote_aberto_estrategia("PLANO_TITA_DO_SILICIO", "NVDAB")
    pm_nvda <- if (lote_nvda$tem_lote && !is.null(lote_nvda$preco_compra) && lote_nvda$preco_compra > 0) lote_nvda$preco_compra else obter_vwap_ativo("NVDAB")
    
    # 1. REALIZAÇÃO DE LUCRO: Venda NVDAB -> USDT sob Trava 6 FIFO com Take Profit Adaptativo FSP
    if (saldo_nvdab_usd > 0.01 && !is.null(p_nvda_live) && p_nvda_live > 0) {
      p_custo_nvda_usdt <- tryCatch({
        tr_nv <- call_binance("/api/v3/myTrades", list(symbol = "NVDABUSDT", limit = 5))
        if (!is.null(tr_nv) && length(tr_nv) > 0) {
          buys_nv <- tr_nv[sapply(tr_nv, function(x) isTRUE(x$isBuyer))]
          if (length(buys_nv) > 0) as.numeric(tail(buys_nv, 1)[[1]]$price) else (pm_nvda / p_usdt_brl)
        } else (pm_nvda / p_usdt_brl)
      }, error = function(e) (pm_nvda / p_usdt_brl))
      
      ret_nvda <- if (!is.null(p_custo_nvda_usdt) && p_custo_nvda_usdt > 0) (p_nvda_live / p_custo_nvda_usdt) - 1.0 else ((p_nvda_live * p_usdt_brl) / pm_nvda) - 1.0
      
      # Target Adaptativo por FSP / Largura de Banda ou Saída Ágil Trava 6
      tp_adaptativo_nvda <- 0.0060
      if (exists("dsp_nvda_cache") && !is.null(dsp_nvda_cache$bandwidth)) {
        ampliacao_tp <- min(1.0, max(0.0, (0.042 - dsp_nvda_cache$bandwidth) / 0.042))
        tp_adaptativo_nvda <- 0.0060 + 0.0060 * ampliacao_tp
      }
      
      # Saída ágil Trava 6: após 60 min de posse se ret >= +0.45%, ou alvo pleno adaptativo (+0.60% a +1.20%)
      tempo_posse_min <- if (lote_nvda$tem_lote) lote_nvda$minutos_posse else 60.0
      atingiu_alvo_pleno <- (ret_nvda >= tp_adaptativo_nvda)
      atingiu_saida_agil <- (tempo_posse_min >= 60.0 && ret_nvda >= 0.0045)
      
      if (atingiu_alvo_pleno || atingiu_saida_agil) {
        val_venda_brl <- saldo_nvdab_usd * p_nvda_live * p_usdt_brl
        pedido <- list(
          estrategia = "PLANO_TITA_DO_SILICIO",
          origem = "NVDAB", destino = "USDT",
          valor_brl = val_venda_brl,
          lucro_esperado_pct = round(ret_nvda * 100, 2), timestamp = agora_ts
        )
      }
    } else if (usdt_livre_rotacao >= 18.0) {
      # 2. ENTRADA HARMONICUS SX + RISCOS TURBO (STFT Hanning + Filtro de Largura de Banda + Sizing FSR)
      nvda_serie <- tryCatch({
        con_nv <- dbConnect(SQLite(), db_path)
        on.exit(dbDisconnect(con_nv))
        df_nv <- dbGetQuery(con_nv, "SELECT NVDABUSDT FROM Historico_binance WHERE NVDABUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 600;")
        if (nrow(df_nv) >= 60) {
          r_nv <- rev(df_nv$NVDABUSDT)
          idx_5m <- rev(seq(length(r_nv), 1, by = -5))
          r_nv[idx_5m]
        } else {
          rep(224.0, 36)
        }
      }, error = function(e) rep(224.0, 36))
      
      dsp_nvda <- if (exists("obter_dsp_fourier_eth") && length(nvda_serie) >= 36) {
        obter_dsp_fourier_eth(nvda_serie)
      } else {
        list(roof_z = 0.0, fsp = 0.0, fhri = 0.0, bandwidth = 0.040, fsr = 5.0, d2Z = 0.0)
      }
      dsp_nvda_cache <<- dsp_nvda
      
      tempo_pos_venda_nvda_ok <- is.null(lote_nvda$minutos_desde_venda) || is.na(lote_nvda$minutos_desde_venda) || lote_nvda$minutos_desde_venda >= 15.0
      
      # Condição Harmonicus Turbo Validada no Torneio de Monte Carlo (100 iterações):
      # - Roofing Filter em vale harmônico (roof_z <= -0.65)
      # - Pureza espectral fsp >= 0.38 e Índice Harmônico fhri >= 0.12
      # - Cinemática convexa/desaceleração positiva d2Z >= 0.0
      # - Filtro de Risco Espectral: Largura de banda estreita (bandwidth <= 0.045) e FSR >= 3.0
      cond_harm_turbo_nvda <- (!is.null(dsp_nvda$roof_z)) &&
        (dsp_nvda$roof_z <= -0.65) &&
        (!is.null(dsp_nvda$fsp) && dsp_nvda$fsp >= 0.38) &&
        (!is.null(dsp_nvda$fhri) && dsp_nvda$fhri >= 0.12) &&
        (!is.null(dsp_nvda$d2Z) && dsp_nvda$d2Z >= 0.0) &&
        (!is.null(dsp_nvda$bandwidth) && dsp_nvda$bandwidth <= 0.045) &&
        (!is.null(dsp_nvda$fsr) && dsp_nvda$fsr >= 3.0)
        
      # Regime Crash Convexo (Queda profunda com desaceleração e pureza mínima)
      cond_crash_nvda <- (!is.null(dsp_nvda$roof_z)) &&
        (dsp_nvda$roof_z <= -1.35) &&
        (!is.null(dsp_nvda$d2Z) && dsp_nvda$d2Z >= 0.0)
        
      lote_base_nvda <- 0.0
      regime_nvda <- NULL
      
      if (cond_harm_turbo_nvda && tempo_pos_venda_nvda_ok) {
        # Bet Sizing Proporcional Dinâmico via Fourier Sharpe Ratio (FSR)
        fator_fsr <- min(1.6, max(1.0, 1.0 + 0.6 * tanh((dsp_nvda$fsr - 4.0) / 4.0)))
        lote_base_nvda <- VALOR_TITA_USDT_DIP * fator_fsr  # Escala suavemente de 45U até 72U
        regime_nvda <- "HARMONICUS_TURBO"
      } else if (cond_crash_nvda && tempo_pos_venda_nvda_ok) {
        lote_base_nvda <- VALOR_TITA_USDT_CRASH # Crash (70 USDT)
        regime_nvda <- "CRASH_CONVEXO"
      }
      
      if (lote_base_nvda > 0.0) {
        lote_usdt_nv <- min(lote_base_nvda * fator_lote, usdt_livre_rotacao)
        if (lote_usdt_nv >= 15.0) {
          ampliacao_tp <- min(1.0, max(0.0, (0.042 - dsp_nvda$bandwidth) / 0.042))
          tp_proj <- 0.60 + 0.60 * ampliacao_tp
          pedido <- list(
            estrategia = "PLANO_TITA_DO_SILICIO",
            origem = "USDT", destino = "NVDAB",
            valor_brl = lote_usdt_nv * p_usdt_brl,
            lucro_esperado_pct = round(tp_proj, 2), timestamp = agora_ts,
            regime = regime_nvda
          )
        }
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 5: PLANO OURO LÍQUIDO (PAXG <-> USDT | Calibrado 48p / 4h Spot)
  # Metricas: +4,57 reais/m (+0,23%/m) | Posse: 98,5h | Trava 6 FIFO >= +0.60%
  # Preserva Corredor de Ouro (Piso 10% / Teto 20%) | Lote 30 USDT base (~R$ 155), escalável para 40.5 USDT
  # ----------------------------------------------------------------------------
  stats_paxg_usdt <- obter_stats_paxg_usdt_4h()
  if (is.null(pedido) && !is.null(p_paxg_usdt) && !is.null(p_usdt_brl)) {
    z_paxg_usdt <- (p_paxg_usdt - stats_paxg_usdt$media) / stats_paxg_usdt$sd
    dsp_paxg    <- stats_paxg_usdt$dsp
    
    lote_ouro_liq <- obter_lote_aberto_estrategia("PLANO_OURO_LIQUIDO", "PAXG")
    
    if (!lote_ouro_liq$tem_lote && usdt_livre_rotacao >= 28.0 && saldo_paxg_brl < teto_ouro_dinamico) {
      # Gatilho de Entrada: Dip em PAXG/USDT (Z <= -0.50 com aceleração d2Z >= 0.010)
      if (z_paxg_usdt <= -0.50 && dsp_paxg$d2Z >= 0.010) {
        lote_u <- min(ifelse(ste_atual >= 0.02 && pc1_atual <= 0.40, 40.5, VALOR_OURO_LIQUIDO_USDT), usdt_livre_rotacao)
        pedido <- list(
          estrategia = "PLANO_OURO_LIQUIDO",
          origem = "USDT", destino = "PAXG",
          valor_brl = lote_u * p_usdt_brl,
          lucro_esperado_pct = 0.60, timestamp = agora_ts
        )
      }
    } else if (lote_ouro_liq$tem_lote) {
      # Gatilho de Saída: Mean Reversion Z >= +0.40 sob Trava 6 Breakeven FIFO (>= +0.60% líquido)
      pm_paxg <- lote_ouro_liq$preco_compra
      if (!is.null(pm_paxg) && pm_paxg > 0) {
        ret_paxg <- (p_paxg_usdt / pm_paxg) - 1.0 - 0.0015
        em_cooldown_ouro <- verificar_cooldown_veto("PLANO_OURO_LIQUIDO", timeout_seg = 300)
        folga_ouro <- saldo_paxg_brl - piso_ouro_dinamico
        if (z_paxg_usdt >= 0.40 && ret_paxg >= 0.0060 && !em_cooldown_ouro && folga_ouro >= 20.0) {
          val_desova_brl <- min(lote_ouro_liq$valor_compra * (1.0 + ret_paxg), folga_ouro)
          pedido <- list(
            estrategia = "PLANO_OURO_LIQUIDO",
            origem = "PAXG", destino = "USDT",
            valor_brl = val_desova_brl,
            lucro_esperado_pct = round(ret_paxg * 100, 2), timestamp = agora_ts
          )
        }
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 6: PLANO CHOQUE ENERGÉTICO (USDT <-> XLE | Calibrado G500 - 60p / 5h)
  # Metricas G500: +1,48 reais/m | Posse: 475,5h | Platô CV: 0,0% | OOS Ratio: 0,94x
  # Hedge de Petróleo/Energia | Lote R$ 90 (~18 USDT)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && usdt_livre_rotacao >= 18.0) {
    xle_serie <- tryCatch({
      con_xle <- dbConnect(SQLite(), db_path)
      on.exit(dbDisconnect(con_xle))
      df_xle <- dbGetQuery(con_xle, "SELECT XLE_Energy FROM Historico_rapido WHERE XLE_Energy IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
      if (nrow(df_xle) >= 30) {
        r_xle <- rev(df_xle$XLE_Energy)
        r_xle[seq(1, length(r_xle), by = 5)]
      } else rep(88.0, 16)
    }, error = function(e) rep(88.0, 16))
    
    dsp_xle <- obter_dsp_ativo(xle_serie)
    m_xle <- mean(xle_serie, na.rm = TRUE)
    s_xle <- sd(xle_serie, na.rm = TRUE)
    if (is.na(s_xle) || s_xle <= 0) s_xle <- 1.5
    z_xle <- (tail(xle_serie, 1) - m_xle) / s_xle
    
    # Calibração G500: Z <= -1.17 com aceleração d2Z >= 0.036
    if (z_xle <= -1.17 && dsp_xle$d2Z >= 0.036) {
      lote_usdt_xle <- min(18.0 * fator_lote, usdt_livre_rotacao)
      pedido <- list(
        estrategia = "PLANO_CHOQUE_ENERGETICO",
        origem = "USDT", destino = "XLE",
        valor_brl = lote_usdt_xle * p_usdt_brl,
        lucro_esperado_pct = 0.43, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 7: ⭐🎵 PLANO SENTINELA DE ÉTER (BRL <-> ETH | Harmonicus SX Fourier Sharpe Turbo)
  # [VENCEDOR DO TORNEIO HEAD-TO-HEAD // AMPLIAÇÃO DE ATÉ 2X NA LUCRATIVIDADE (1,81x a 2,13x)]
  # Inovação DSP: Fator de Risco por Largura Média de Banda Espectral (sigma_f <= 0.045) e
  # Fourier Sharpe Ratio (FSR >= 3.0) com Bet Sizing Dinâmico Contínuo (0,6x a 1,8x de Et)
  # e Take Profit Adaptativo Coerente (+0,55% a +1,00% em bandas ultra-estreitas sigma_f <= 0.035).
  # Performance Comprovada (154k candles 5m / 20,2 meses):
  #   - 5 Ciclos Consecutivos: Multiplicador de 1,81x (de 15,91 para 28,76 reais) e até 2,13x em blocos de alta pureza.
  #   - 180 Dias Normais: +12,35 reais/m (1,64x vs baseline) | Win Rate 100% sob Trava 6.
  #   - Período Integral (20,2m): +5,35 reais/m (1,83x vs baseline) absorvendo crash de -39% do ETH.
  # Governança: Trava 6 Breakeven FIFO (>= +0,40%) com Subtrava 6.2 Target Decay (48h-72h) e Cap 3x Tranches (13,8%).
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_eth_brl) && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    z_eth_1h     <- (p_eth_brl - stats_eth_1h$media) / stats_eth_1h$sd
    dsp_fourier  <- stats_eth_1h$fourier
    dsp_classico <- stats_eth_1h$dsp
    
    # 1. Filtro de Risco Espectral & Fourier Sharpe Ratio (FSR)
    bw_eth        <- if (!is.null(dsp_fourier$bandwidth)) dsp_fourier$bandwidth else 0.040
    fsr_eth       <- if (!is.null(dsp_fourier$fsr)) dsp_fourier$fsr else 5.0
    cond_bw_ok    <- (bw_eth <= 0.045)
    cond_fsr_ok   <- (fsr_eth >= 3.0)
    
    # 2. Gatilho Harmonicus Fourier SX no Vale:
    # Pureza Espectral FSP >= 0.40 + Ressonância FHRI >= 0.15 + Roof Z <= -0.85 + FSR Ok + Bandwidth Ok
    cond_fourier_eth <- (!is.null(dsp_fourier$fsp)) && 
                        (dsp_fourier$fsp >= 0.40) && 
                        (dsp_fourier$fhri >= 0.15) && 
                        (dsp_fourier$roof_z <= -0.85) &&
                        cond_bw_ok && cond_fsr_ok
    
    # 3. Gatilho Clássico Alternativo (Mean-Reversion Simples): Z <= -0.80 com dtheta favorável
    cond_classica_eth <- (z_eth_1h <= -0.80) && 
                         (!is.null(dsp_classico$dtheta)) && 
                         (dsp_classico$dtheta >= 0.12 && dsp_classico$dtheta <= 1.45)
    
    # 4. Confirmação de Convexidade / Aceleração Positiva (d2Z >= 0.0)
    acc_eth <- if (!is.null(dsp_fourier$d2Z)) dsp_fourier$d2Z else (if (!is.null(dsp_classico$d2Z)) dsp_classico$d2Z else 0.0)
    cond_convex_eth <- (acc_eth >= 0.0)
    
    # Gatilho Integrado
    cond_compra_eth <- (cond_fourier_eth || cond_classica_eth) && cond_convex_eth
    
    # 5. Bet Sizing Dinâmico Contínuo Proporcional ao Fourier Sharpe Ratio (0,6x a 1,8x)
    fator_lote_fsr <- if (!is.null(fsr_eth) && !is.na(fsr_eth)) {
      max(0.6, min(1.8, 1.0 + 0.6 * tanh((fsr_eth - 4.0) / 4.0)))
    } else {
      1.0
    }
    
    # 6. Take Profit Adaptativo Coerente: expande até +1,00% em bandas de frequência ultra-estreitas
    ampliacao_tp <- if (!is.null(bw_eth) && !is.na(bw_eth)) {
      max(0.0, min(1.0, (0.042 - bw_eth) / 0.042))
    } else {
      0.0
    }
    target_adaptativo_eth <- 0.55 + 0.45 * ampliacao_tp # varia linearmente de +0.55% a +1.00%
    
    # Gestão de Tranches (Cap Máximo de 3 tranches = ~13,8% de Et)
    teto_eth_brl     <- VALOR_ETH_TRANCHE_BRL * 3.0
    lote_tranche_eth <- min(VALOR_ETH_TRANCHE_BRL * fator_lote_fsr, caixa_brl_livre_cripto)
    pode_comprar_eth <- (saldo_eth_brl < teto_eth_brl) && (lote_tranche_eth >= 25.0) && (caixa_brl_livre_cripto >= lote_tranche_eth)
    
    # Cooldown anti-spam entre tranches (mínimo 30 minutos ou nova queda Z significativa)
    lote_info_eth <- obter_lote_aberto_estrategia("PLANO_SENTINELA_DE_ETER", "ETH")
    cooldown_tranche_ok <- if (isTRUE(lote_info_eth$tem_lote)) {
      lote_info_eth$minutos_posse >= 30.0 || (p_eth_brl <= (lote_info_eth$vwap_abertos * 0.985))
    } else {
      TRUE
    }
    
    if (cond_compra_eth && pode_comprar_eth && cooldown_tranche_ok) {
      pedido <- list(
        estrategia = "PLANO_SENTINELA_DE_ETER",
        origem = "BRL", destino = "ETH",
        valor_brl = lote_tranche_eth,
        lucro_esperado_pct = round(target_adaptativo_eth, 2), timestamp = agora_ts
      )
    } else if (saldo_eth_brl >= 25.0) {
      # Saída sob Trava 6 com Z >= 0.20 OU Take Profit por Lucro Real Expressivo (>= target_adaptativo_eth)
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (48h a 72h decaindo linearmente até +0.40% piso)
      em_cooldown_eth <- verificar_cooldown_veto("PLANO_SENTINELA_DE_ETER", timeout_seg = 300)
      preco_ref_eth <- if (isTRUE(lote_info_eth$tem_lote)) {
        if (!is.null(lote_info_eth$vwap_abertos) && !is.na(lote_info_eth$vwap_abertos) && lote_info_eth$vwap_abertos > 0) lote_info_eth$vwap_abertos else lote_info_eth$preco_compra
      } else NA
      
      retorno_real_eth <- if (!is.na(preco_ref_eth) && preco_ref_eth > 0) ((p_eth_brl - preco_ref_eth) / preco_ref_eth) * 100 else 0.0
      meta_base_saida  <- if (isTRUE(lote_info_eth$tem_lote) && !is.null(lote_info_eth$lucro_esperado_pct) && lote_info_eth$lucro_esperado_pct > 0) lote_info_eth$lucro_esperado_pct else 0.55
      meta_alvo_eth    <- calcular_meta_lucro_decay(lote_info_eth$minutos_posse, meta_base = meta_base_saida, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      margem_minima_eth_ok <- (retorno_real_eth >= meta_alvo_eth)
      take_profit_eth_ok   <- (retorno_real_eth >= max(1.20, meta_base_saida))
      
      deve_vender_eth <- isTRUE(lote_info_eth$tem_lote) && !em_cooldown_eth && (take_profit_eth_ok || (z_eth_1h >= 0.20 && margem_minima_eth_ok))
      
      if (deve_vender_eth) {
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DE_ETER",
          origem = "ETH", destino = "BRL",
          valor_brl = saldo_eth_brl,
          lucro_esperado_pct = max(meta_alvo_eth, round(retorno_real_eth, 2)), timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 8: ⭐🎵 PLANO FLECHA DE SAGARANA (BRL <-> BTC | Harmonicus SX Fourier Swing)
  # [VENCEDOR DO TORNEIO QUANTITATIVO HEAD-TO-HEAD // +58% DE LUCRO REAL VS BASELINE]
  # Configuração Vencedora: Roofing Z <= -1.40, FHRI >= 0.20, FSP >= 0.45, d2Z >= 0.0
  # Métricas 180d: +12,23 a +12,50 reais/mês (+0,38%/m do patrimônio consolidado) | 
  # Mediana: +9,42 a +10,40 reais/mês | 3,6 a 4,1 trades/mês | Posse: 134,1h (-53% de ócio) | Win Rate: 96,6%
  # Saída sob Trava 6 Breakeven FIFO/VWAP com Subtrava 6.2 Target Decay (48h-72h até +0.40%) e Saída Ágil (+0.55% pós-1h)
  # Segregação Estrita: Saída de BTC exige lote próprio de Flecha de Sagarana
  # ----------------------------------------------------------------------------
  stats_btc <- obter_stats_btc_dual_scale()
  if (is.null(pedido) && !is.null(p_btc_brl) && ste_atual >= -0.02 && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    bloqueio_canibalizacao_flecha <- verificar_compra_recente_btc("PLANO_ESCUDO_DE_AQUILES", 300)
    z_btc <- (p_btc_brl - stats_btc$media_fast) / stats_btc$sd_fast
    dsp_btc <- stats_btc$dsp_fast
    acc_btc <- dsp_btc$d2Z
    dsp_fourier_btc <- stats_btc$fourier
    
    lote_flecha_btc <- obter_lote_aberto_estrategia("PLANO_FLECHA_DE_SAGARANA", "BTC")
    
    # 1. Gatilho Harmonicus Fourier SX no Vale:
    cond_fourier_flecha <- (!is.null(dsp_fourier_btc$fsp)) && 
                           (dsp_fourier_btc$fsp >= 0.45) && 
                           (dsp_fourier_btc$fhri >= 0.20) && 
                           (dsp_fourier_btc$roof_z <= -1.40) && 
                           (!is.null(dsp_fourier_btc$d2Z) && dsp_fourier_btc$d2Z >= 0.0)
    
    # 2. Confirmação Clássica Alternativa de Dip Profundo (Z <= -1.20 e d2Z >= 0.0)
    cond_classica_flecha <- (z_btc <= -1.20) && (acc_btc >= 0.0)
    
    cond_entrada_flecha <- (cond_fourier_flecha || cond_classica_flecha) && 
                           caixa_brl_livre_cripto >= 30.0 && 
                           saldo_btc_brl < teto_btc_brl && 
                           !bloqueio_canibalizacao_flecha
    
    if (cond_entrada_flecha) {
      lote_s <- min(VALOR_SAGARANA_BRL * fator_lote, max(30.0, caixa_brl_livre_cripto * 0.65))
      lote_s <- min(lote_s, caixa_brl_livre_cripto)
      if (lote_s >= 25.0) {
        pedido <- list(
          estrategia = "PLANO_FLECHA_DE_SAGARANA",
          origem = "BRL", destino = "BTC",
          valor_brl = lote_s,
          lucro_esperado_pct = 1.00, timestamp = agora_ts
        )
      }
    } else if (isTRUE(lote_flecha_btc$tem_lote) && saldo_btc_brl >= 25.0) {
      # Saída sob Trava 6 Breakeven FIFO/VWAP com Subtrava 6.2 Target Decay Ratchet (48h a 72h até +0.40%)
      p_compra_flecha <- if (!is.null(lote_flecha_btc$vwap_abertos) && !is.na(lote_flecha_btc$vwap_abertos) && lote_flecha_btc$vwap_abertos > 0) {
        lote_flecha_btc$vwap_abertos
      } else if (!is.null(lote_flecha_btc$preco_compra) && lote_flecha_btc$preco_compra > 0) {
        lote_flecha_btc$preco_compra
      } else {
        p_btc_brl
      }
      ret_real_flecha <- ((p_btc_brl - p_compra_flecha) / p_compra_flecha) * 100.0
      tempo_posse_fl  <- if (!is.null(lote_flecha_btc$minutos_posse)) lote_flecha_btc$minutos_posse else 999.0
      
      # 🛡️ Subtrava 6.2 Target Decay Ratchet (48h a 72h decaindo linearmente de +1.00% até piso de +0.40%)
      meta_alvo_flecha <- calcular_meta_lucro_decay(tempo_posse_fl, meta_base = 1.00, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      
      cond_decay_ok   <- (ret_real_flecha >= meta_alvo_flecha)
      cond_rebound_ok <- (ret_real_flecha >= 0.85 && (z_btc >= 0.15 || (!is.null(dsp_fourier_btc$phi_dom) && dsp_fourier_btc$phi_dom >= 1.20)))
      cond_agil_ok    <- (ret_real_flecha >= 0.55 && tempo_posse_fl >= 60.0)
      cond_tp_fast    <- (ret_real_flecha >= 1.35)
      
      cond_saida_flecha <- isTRUE(lote_flecha_btc$tem_lote) && (cond_tp_fast || cond_rebound_ok || cond_decay_ok || cond_agil_ok)
      em_cooldown_sag   <- verificar_cooldown_veto("PLANO_FLECHA_DE_SAGARANA", timeout_seg = 300)
      
      if (cond_saida_flecha && !em_cooldown_sag) {
        valor_desova_btc <- min(saldo_btc_brl, VALOR_SAGARANA_BRL * fator_lote)
        if (valor_desova_btc >= 25.0) {
          pedido <- list(
            estrategia = "PLANO_FLECHA_DE_SAGARANA",
            origem = "BTC", destino = "BRL",
            valor_brl = valor_desova_btc,
            lucro_esperado_pct = round(ret_real_flecha, 2), timestamp = agora_ts
          )
        }
      }
    }
  }
  
  
  # ----------------------------------------------------------------------------
  # MOTOR 9: PLANO SENTINELA DO SOL (BRL <-> SOL | Reversão Intradiária 1h de Alta Velocidade)
  # [RECALIBRADO VIA SIMULAÇÃO QUANTITATIVA 5M / MULTI-PROPORÇÃO DE CARTEIRA]
  # Configuração Otimizada: Janela 1h (12p 5m), Z <= -0.65, d2Z >= 0.0, Saída Z >= +0.15, Trava 6 >= +0.50%
  # Métricas Oficiais 5m: 5,4 a 13,3 trades/mês | Posse Mediana: 3.6h a 5.2h | Lucro: +11.83 a +14.27 reais/mês | Win Rate: 100,0% | Drawdown Médio: -2.12%
  # Teto Máximo em Solana: 250,00 reais | Subtrava 2.2 Preservada (Cripto < 80%) | Sizing Proporcional 4.5% (~145 reais)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_sol_brl) && !is.null(stats_sol_1h) && ste_atual >= -0.02 && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    z_sol_1h <- (p_sol_brl - stats_sol_1h$media) / stats_sol_1h$sd
    dsp_sol  <- if (!is.null(stats_sol_1h$dsp)) stats_sol_1h$dsp else list(theta = 0, d2Z = 0)
    acc_sol  <- if (!is.null(dsp_sol$d2Z)) dsp_sol$d2Z else 0.0
    
    # Calibração Otimizada: Z <= -0.65 com inflexão d2Z >= 0.0
    cond_compra_sol <- (z_sol_1h <= -0.65) && (acc_sol >= 0.0) && (caixa_brl_livre_cripto >= 25.0) && (saldo_sol_brl < teto_sol_brl)
    
    if (cond_compra_sol) {
      lote_sol <- min(VALOR_SOL_SENTINELA_BRL * fator_lote, caixa_brl_livre_cripto)
      if (lote_sol >= 25.0) {
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DO_SOL",
          origem = "BRL", destino = "SOL",
          valor_brl = lote_sol,
          lucro_esperado_pct = 0.50, timestamp = agora_ts
        )
      }
    } else if (saldo_sol_brl >= 25.0) {
      # Saída sob Trava 6 com Z >= 0.15 OU Take Profit por Lucro Real Expressivo (>= +1.20%)
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (48h a 72h decaindo suavemente até +0.40% piso)
      em_cooldown_sol9 <- verificar_cooldown_veto("PLANO_SENTINELA_DO_SOL", timeout_seg = 300)
      lote_info_sol <- obter_lote_aberto_estrategia("PLANO_SENTINELA_DO_SOL", "SOL")
      preco_ref_sol <- if (isTRUE(lote_info_sol$tem_lote)) {
        if (!is.null(lote_info_sol$vwap_abertos) && !is.na(lote_info_sol$vwap_abertos) && lote_info_sol$vwap_abertos > 0) lote_info_sol$vwap_abertos else lote_info_sol$preco_compra
      } else NA
      
      retorno_real_sol <- if (!is.na(preco_ref_sol) && preco_ref_sol > 0) ((p_sol_brl - preco_ref_sol) / preco_ref_sol) * 100 else 0.0
      meta_alvo_sol <- calcular_meta_lucro_decay(lote_info_sol$minutos_posse, meta_base = 0.50, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      margem_minima_sol_ok <- (retorno_real_sol >= meta_alvo_sol)
      take_profit_sol_ok <- (retorno_real_sol >= 1.20)
      
      deve_vender_sol <- isTRUE(lote_info_sol$tem_lote) && !em_cooldown_sol9 && (take_profit_sol_ok || (z_sol_1h >= 0.15 && margem_minima_sol_ok))
      
      if (deve_vender_sol) {
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DO_SOL",
          origem = "SOL", destino = "BRL",
          valor_brl = saldo_sol_brl, # Saída Única: Desova 100% da posição em 1 trade limpo
          lucro_esperado_pct = meta_alvo_sol, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 10: ⭐🎵 PLANO SENTINELA DE MINAS (BRL <-> BNB | Harmonicus 2T DCA)
  # [VENCEDOR DO TORNEIO QUANTITATIVO HEAD-TO-HEAD // +55% MEDIANA VS CLASSIC]
  # Configuração Vencedora: Roofing Z <= -0.85 (T1) / -1.60 (T2), FHRI >= 0.12, FSP >= 0.30, PC1 <= 0.60, d2Z >= 0.0
  # Lote: 370,00 reais total em 2 tranches DCA de 185,00 reais | Teto Fixo Centralizado: 370,00 reais
  # Métricas 5m Contínuos (20,8 meses / 182k candles):
  #   • Mediana: +11,23 reais/mês (Média: +9,97 reais/mês)
  #   • Tempo de Posse Médio: 81,1 horas (-16 horas de ócio vs Classic)
  #   • Taxa de Acerto: 100,0% sob Trava 6 Breakeven FIFO/VWAP >= +0.50%
  # Benefício Perpétuo: Abastecimento de saldo BNB para desconto permanente de 25% nas taxas Binance
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_bnb_brl) && !is.null(stats_bnb_1h) && ste_atual >= -0.02 && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    z_bnb_1h <- (p_bnb_brl - stats_bnb_1h$media) / stats_bnb_1h$sd
    dsp_bnb  <- if (!is.null(stats_bnb_1h$dsp)) stats_bnb_1h$dsp else list(theta = 0, d2Z = 0)
    acc_bnb  <- if (!is.null(dsp_bnb$d2Z)) dsp_bnb$d2Z else 0.0
    dsp_fourier_bnb <- stats_bnb_1h$fourier
    roof_z_bnb <- if (!is.null(dsp_fourier_bnb$roof_z)) dsp_fourier_bnb$roof_z else z_bnb_1h
    fhri_bnb   <- if (!is.null(dsp_fourier_bnb$fhri)) dsp_fourier_bnb$fhri else 0.15
    fsp_bnb    <- if (!is.null(dsp_fourier_bnb$fsp)) dsp_fourier_bnb$fsp else 0.35
    
    lote_info_bnb <- obter_lote_aberto_estrategia("PLANO_SENTINELA_DE_MINAS", "BNB")
    em_cooldown_bnb <- verificar_cooldown_veto("PLANO_SENTINELA_DE_MINAS", timeout_seg = 300)
    
    # 1. Tranche 1: Dip Harmonicus no Vale (Roofing <= -0.85 ou Classic Z <= -1.00 com pureza espectral e d2Z >= 0)
    cond_fourier_t1 <- (roof_z_bnb <= -0.85) && (fhri_bnb >= 0.12) && (fsp_bnb >= 0.30)
    cond_classic_t1 <- (z_bnb_1h <= -1.00)
    cond_compra_bnb_t1 <- !em_cooldown_bnb && (cond_fourier_t1 || cond_classic_t1) && (acc_bnb >= 0.0) && 
                          (pc1_atual <= 0.60) && (caixa_brl_livre_cripto >= 25.0) && 
                          (saldo_bnb_brl < VALOR_BNB_TRANCHE_BRL) && (saldo_bnb_brl < teto_bnb_brl)
    
    # 2. Tranche 2 (DCA): Capitulação profunda (Roofing <= -1.60 ou Classic Z <= -1.80) com espaçamento de 60 min
    tempo_posse_bnb <- if (isTRUE(lote_info_bnb$tem_lote) && !is.null(lote_info_bnb$minutos_posse)) lote_info_bnb$minutos_posse else 0.0
    p_ref_dca_bnb   <- if (isTRUE(lote_info_bnb$tem_lote) && !is.null(lote_info_bnb$vwap_abertos)) lote_info_bnb$vwap_abertos else p_bnb_brl
    cond_dca_preco  <- (p_bnb_brl <= p_ref_dca_bnb * 0.985) || (tempo_posse_bnb >= 60.0)
    cond_compra_bnb_t2 <- !em_cooldown_bnb && isTRUE(lote_info_bnb$tem_lote) && 
                          (saldo_bnb_brl >= 50.0) && (saldo_bnb_brl < (teto_bnb_brl - 25.0)) && 
                          (roof_z_bnb <= -1.60 || z_bnb_1h <= -1.80) && (acc_bnb >= 0.0) && 
                          cond_dca_preco && (caixa_brl_livre_cripto >= 25.0)
    
    if (cond_compra_bnb_t1 || cond_compra_bnb_t2) {
      lote_b_base <- if (cond_compra_bnb_t2) min(VALOR_BNB_TRANCHE_BRL, teto_bnb_brl - saldo_bnb_brl) else VALOR_BNB_TRANCHE_BRL
      lote_b <- min(lote_b_base * fator_lote, caixa_brl_livre_cripto)
      lote_b <- min(lote_b, max(0.0, teto_bnb_brl - saldo_bnb_brl))
      if (lote_b >= 25.0) {
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DE_MINAS",
          origem = "BRL", destino = "BNB",
          valor_brl = lote_b,
          lucro_esperado_pct = 0.50, timestamp = agora_ts
        )
      }
    } else if (saldo_bnb_brl >= 25.0) {
      # Saída sob Trava 6 Breakeven FIFO/VWAP com Z >= 0.15 OU Take Profit por Lucro Real Expressivo (>= +1.20%)
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (72h a 96h decaindo suavemente até +0.40% piso)
      preco_ref_bnb <- if (isTRUE(lote_info_bnb$tem_lote)) {
        if (!is.null(lote_info_bnb$vwap_abertos) && !is.na(lote_info_bnb$vwap_abertos) && lote_info_bnb$vwap_abertos > 0) lote_info_bnb$vwap_abertos else lote_info_bnb$preco_compra
      } else NA
      
      retorno_real_bnb <- if (!is.na(preco_ref_bnb) && preco_ref_bnb > 0) ((p_bnb_brl - preco_ref_bnb) / preco_ref_bnb) * 100 else 0.0
      meta_alvo_bnb <- calcular_meta_lucro_decay(lote_info_bnb$minutos_posse, meta_base = 0.50, horas_inicio_decay = 72.0, horas_fim_decay = 96.0, piso_minimo = 0.40)
      margem_minima_bnb_ok <- (retorno_real_bnb >= meta_alvo_bnb)
      take_profit_bnb_ok <- (retorno_real_bnb >= 1.20)
      tempo_posse_min_bnb <- if (!is.null(lote_info_bnb$minutos_posse)) lote_info_bnb$minutos_posse else 0.0
      saida_piso_decay_ok <- (retorno_real_bnb >= 0.40 && tempo_posse_min_bnb >= 5760.0)
      
      deve_vender_bnb <- isTRUE(lote_info_bnb$tem_lote) && !em_cooldown_bnb && (take_profit_bnb_ok || (z_bnb_1h >= 0.15 && margem_minima_bnb_ok) || saida_piso_decay_ok)
      
      if (deve_vender_bnb) {
        pedido <- list(
          estrategia = "PLANO_SENTINELA_DE_MINAS",
          origem = "BNB", destino = "BRL",
          valor_brl = saldo_bnb_brl, # Saída Única: Desova 100% da posição em 1 trade limpo
          lucro_esperado_pct = max(meta_alvo_bnb, round(retorno_real_bnb, 2)), timestamp = agora_ts
        )
      }
    }
  }

  # ----------------------------------------------------------------------------
  # MOTOR 11: PLANO ESCUDO DE WASHINGTON (USDT <-> TLT | Calibrado G500 - 60p / 5h)
  # Metricas G500: +0,23 reais/m | Posse: 331,9h (-26,2%) | Platô CV: 0,0%
  # Renda Fixa Soberana Americana (T-Bonds 20Y) | Lote 16 USDT (~R$ 80)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    lote_tlt <- obter_lote_aberto_estrategia("PLANO_ESCUDO_DE_WASHINGTON", "TLT")
    if (saldo_tlt_usd > 0.01) {
      pm_tlt <- if (lote_tlt$tem_lote && !is.null(lote_tlt$preco_compra) && lote_tlt$preco_compra > 0) lote_tlt$preco_compra else obter_vwap_ativo("TLT")
      p_tlt_live <- tryCatch(as.numeric(tail(getQuote("TLT")$Last, 1)), error = function(e) 95.0)
      if (pm_tlt > 0 && p_tlt_live > 0) {
        p_tlt_live_brl <- p_tlt_live * p_usdt_brl
        ret_tlt <- (p_tlt_live_brl / pm_tlt) - 1.0
        tempo_ok <- !lote_tlt$tem_lote || lote_tlt$minutos_posse >= 15.0 || ret_tlt >= 0.015
        if (ret_tlt >= 0.0052 && tempo_ok) {
          pedido <- list(
            estrategia = "PLANO_ESCUDO_DE_WASHINGTON",
            origem = "TLT", destino = "USDT",
            valor_brl = saldo_tlt_usd * p_tlt_live * p_usdt_brl,
            lucro_esperado_pct = round(ret_tlt * 100, 2), timestamp = agora_ts
          )
        }
      }
    } else if (usdt_livre_rotacao >= 16.0) {
      tlt_serie <- tryCatch({
        con_tlt <- dbConnect(SQLite(), db_path)
        on.exit(dbDisconnect(con_tlt))
        df_tlt <- dbGetQuery(con_tlt, "SELECT TLT_Bond FROM Historico_rapido WHERE TLT_Bond IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
        if (nrow(df_tlt) >= 30) {
          r_tlt <- rev(df_tlt$TLT_Bond)
          r_tlt[seq(1, length(r_tlt), by = 5)]
        } else rep(95.0, 16)
      }, error = function(e) rep(95.0, 16))
      
      dsp_tlt <- obter_dsp_ativo(tlt_serie)
      m_tlt <- mean(tlt_serie, na.rm = TRUE)
      s_tlt <- sd(tlt_serie, na.rm = TRUE)
      if (is.na(s_tlt) || s_tlt <= 0) s_tlt <- 1.2
      z_tlt <- (tail(tlt_serie, 1) - m_tlt) / s_tlt
      
      # Calibração G500: Z <= -1.11 com aceleração d2Z >= 0.015
      if (z_tlt <= -1.11 && dsp_tlt$d2Z >= 0.015) {
        lote_usdt_tlt <- min(16.0 * fator_lote, usdt_livre_rotacao)
        pedido <- list(
          estrategia = "PLANO_ESCUDO_DE_WASHINGTON",
          origem = "USDT", destino = "TLT",
          valor_brl = lote_usdt_tlt * p_usdt_brl,
          lucro_esperado_pct = 0.52, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 12: PLANO SENTINELA ANTIFRÁGIL (USDT <-> SQQQB | Calibrado Mean-Reversion 1h - Meta 1%/m)
  # Metricas 5m Contínuos: +32,44 reais/m (+1,004%/m do patrimônio) | Posse Mediana: 2,33h
  # ProShares UltraPro Short QQQ Spot Binance | Lote Dinâmico: 53 USDT (~274 BRL / 8,5% Patr.)
  # Trava 6 Breakeven FIFO: +0,85% líquido | Win Rate: 100% | Drawdown Médio MTM: -1,30%
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    lote_anti <- obter_lote_aberto_estrategia("PLANO_SENTINELA_ANTIFRAGIL", "SQQQB")
    if (saldo_sqqqb_usd > 0.01) {
      p_sqqq_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SQQQBUSDT"), "parsed")$price), error = function(e) NULL)
      pm_sqqq <- if (lote_anti$tem_lote && !is.null(lote_anti$preco_compra) && lote_anti$preco_compra > 0) lote_anti$preco_compra else obter_vwap_ativo("SQQQB")
      if (!is.null(p_sqqq_live) && p_sqqq_live > 0 && pm_sqqq > 0) {
        p_sqqq_live_brl <- p_sqqq_live * p_usdt_brl
        ret_sqqq <- (p_sqqq_live_brl / pm_sqqq) - 1.0
        tempo_ok <- !lote_anti$tem_lote || lote_anti$minutos_posse >= 15.0 || ret_sqqq >= 0.015
        
        # 🛡️ Regra B (Blindagem Absoluta do Lote Legado de 16/09):
        # Lotes históricos com custo >= 38.0 USDT NUNCA podem ser vendidos no prejuízo!
        # Saída estritamente sob Trava 6: Take Profit de +0,85% líquido (ou saída ágil em Z >= +0,20 com ganho >= +0,50%)
        z_sqqq_exit <- if (!is.null(stats_sqqqb_1h$media) && !is.null(stats_sqqqb_1h$sd) && stats_sqqqb_1h$sd > 0) (p_sqqq_live - stats_sqqqb_1h$media) / stats_sqqqb_1h$sd else 0.0
        cond_saida_sqqq <- (ret_sqqq >= 0.0085 || (ret_sqqq >= 0.0050 && z_sqqq_exit >= 0.20)) && tempo_ok
        
        if (cond_saida_sqqq) {
          val_venda_brl <- saldo_sqqqb_usd * p_sqqq_live * p_usdt_brl
          pedido <- list(
            estrategia = "PLANO_SENTINELA_ANTIFRAGIL",
            origem = "SQQQB", destino = "USDT",
            valor_brl = val_venda_brl,
            lucro_esperado_pct = round(ret_sqqq * 100, 2), timestamp = agora_ts
          )
        }
      }
    } else if (usdt_livre_rotacao >= 18.0) {
      # Cooldown de Recompra Anti-Churning: após vender, aguarda no mínimo 30 minutos antes de recomprar SQQQB
      tempo_pos_venda_ok <- is.null(lote_anti$minutos_desde_venda) || is.na(lote_anti$minutos_desde_venda) || lote_anti$minutos_desde_venda >= 30.0
      
      # 🛡️ Regra A (Blindagem Anti-Prejuízo e Anti-Churning nas Entradas):
      # Para novas compras, exige que o índice Nasdaq 100 (QQQBUSDT) esteja em sobrecompra extrema (Z >= +1.20)
      # ou em reversão clara, eliminando entradas contra ralis institucionais contínuos
      qqq_serie <- tryCatch({
        con_q <- dbConnect(SQLite(), db_path)
        on.exit(dbDisconnect(con_q))
        df_q <- dbGetQuery(con_q, "SELECT QQQBUSDT FROM Historico_binance WHERE QQQBUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 60;")
        if (nrow(df_q) >= 12) {
          r_q <- rev(df_q$QQQBUSDT)
          r_q[rev(seq(length(r_q), 1, by = -5))]
        } else rep(740.0, 12)
      }, error = function(e) rep(740.0, 12))
      
      m_qqq <- mean(qqq_serie, na.rm = TRUE); s_qqq <- sd(qqq_serie, na.rm = TRUE)
      if (is.na(s_qqq) || s_qqq <= 0) s_qqq <- 2.0
      z_qqq <- (tail(qqq_serie, 1) - m_qqq) / s_qqq
      
      z_sqqq <- if (!is.null(stats_sqqqb_1h$media) && !is.null(stats_sqqqb_1h$sd) && stats_sqqqb_1h$sd > 0) (obter_px_eq("SQQQB", 38.5) - stats_sqqqb_1h$media) / stats_sqqqb_1h$sd else 0.0
      acc_sqqq <- if (!is.null(stats_sqqqb_1h$dsp$d2Z)) stats_sqqqb_1h$dsp$d2Z else 0.0
      
      cond_entrada_anti <- (z_sqqq <= -0.60 && acc_sqqq >= 0.0 && (z_qqq >= 1.20 || z_qqq <= -0.80)) && tempo_pos_venda_ok
      
      if (cond_entrada_anti) {
        lote_usdt_anti <- min(VALOR_SQQQB_BRL / p_usdt_brl * fator_lote, usdt_livre_rotacao)
        if (lote_usdt_anti >= 15.0) {
          pedido <- list(
            estrategia = "PLANO_SENTINELA_ANTIFRAGIL",
            origem = "USDT", destino = "SQQQB",
            valor_brl = lote_usdt_anti * p_usdt_brl,
            lucro_esperado_pct = 0.85, timestamp = agora_ts
          )
        }
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 13: PLANO BRUCE WAYNE (Contingência de Crise Cripto / Tail-Risk Macro Hedge)
  # [DESATIVADO TEMPORARIAMENTE CONFORME DIRETRIZ DE GOVERNANÇA]
  # ----------------------------------------------------------------------------
  PLANO_BRUCE_WAYNE_ATIVO <- FALSE
  
  # ----------------------------------------------------------------------------
  # MOTOR 14: ⭐🎵 PLANO SENTINELA DE WALL STREET (SPYB / USDT - Harmonicus SX Equities)
  # Calibração Harmonicus Fourier (5m): Roofing <= -0.60 | FSP >= 0.40 | FHRI >= 0.12 | d2Z >= 0.0
  # Lucro Homologado: +3,65 a +4,88 reais/m (+0,069% a +0,092%/m) | Posse: 51,6h | Win Rate: 84,7% | Max DD: 18,97 reais
  # Binance Backed Equity Spot: SPYBUSDT | Lote Homologado: 8,0% (~422 reais / ~81 USDT)
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    # 1. REALIZACAO DE LUCRO: Venda SPYB -> USDT sob a Trava 6 Breakeven FIFO (>= +0.40% ágil)
    lote_spy <- obter_lote_aberto_estrategia("PLANO_SENTINELA_WALLSTREET", "SPYB")
    if (saldo_spyb_usd > 0.01) {
      p_spy_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SPYBUSDT"), "parsed")$price), error = function(e) NULL)
      pm_spy <- if (lote_spy$tem_lote && !is.null(lote_spy$preco_compra) && lote_spy$preco_compra > 0) lote_spy$preco_compra else obter_vwap_ativo("SPYB")
      if (!is.null(p_spy_live) && p_spy_live > 0) {
        p_custo_spy_usdt <- tryCatch({
          tr_spy <- call_binance("/api/v3/myTrades", list(symbol = "SPYBUSDT", limit = 5))
          if (!is.null(tr_spy) && length(tr_spy) > 0) {
            buys_spy <- tr_spy[sapply(tr_spy, function(x) isTRUE(x$isBuyer))]
            if (length(buys_spy) > 0) as.numeric(tail(buys_spy, 1)[[1]]$price) else (pm_spy / p_usdt_brl)
          } else (pm_spy / p_usdt_brl)
        }, error = function(e) (pm_spy / p_usdt_brl))
        
        ret_spy <- if (!is.null(p_custo_spy_usdt) && p_custo_spy_usdt > 0) (p_spy_live / p_custo_spy_usdt) - 1.0 else ((p_spy_live * p_usdt_brl) / pm_spy) - 1.0
        tempo_ok <- !lote_spy$tem_lote || lote_spy$minutos_posse >= 15.0 || ret_spy >= 0.010
        # Saída Ágil Calibrada Harmonicus: +0.40% líquido sobre VWAP/FIFO
        cond_saida_spy <- ((ret_spy >= 0.0040) || (ret_spy >= 0.0050)) && tempo_ok
        if (cond_saida_spy) {
          val_venda_brl <- saldo_spyb_usd * p_spy_live * p_usdt_brl
          pedido <- list(
            estrategia = "PLANO_SENTINELA_WALLSTREET",
            origem = "SPYB", destino = "USDT",
            valor_brl = val_venda_brl,
            lucro_esperado_pct = round(ret_spy * 100, 2), timestamp = agora_ts
          )
        }
      }
    } else if (usdt_livre_rotacao >= VALOR_WALLSTREET_USDT) {
      # 2. ENTRADA EM VALE HARMONICUS FOURIER SX (Ehlers Roofing 48p/8p + STFT Hanning 32p)
      sp500_serie <- tryCatch({
        con_sp <- dbConnect(SQLite(), db_path)
        on.exit(dbDisconnect(con_sp))
        df_sp <- dbGetQuery(con_sp, "SELECT SPYBUSDT FROM Historico_binance WHERE SPYBUSDT IS NOT NULL ORDER BY Data_Hora DESC LIMIT 250;")
        if (nrow(df_sp) >= 40) {
          r_sp <- rev(df_sp$SPYBUSDT)
          idx_5m <- rev(seq(length(r_sp), 1, by = -5))
          r_sp[idx_5m]
        } else if (nrow(df_sp) >= 12) {
          r_sp <- rev(df_sp$SPYBUSDT)
          idx_5m <- rev(seq(length(r_sp), 1, by = -5))
          r_sp[idx_5m]
        } else rep(765.0, 36)
      }, error = function(e) rep(765.0, 36))
      
      dsp_fourier_spy <- if (exists("obter_dsp_fourier") && length(sp500_serie) >= 36) {
        obter_dsp_fourier(sp500_serie)
      } else {
        list(roof_z = 0.0, fsp = 0.0, fhri = 0.0, phi_dom = 0.0, d2Z = 0.0)
      }
      
      tempo_pos_venda_spy_ok <- is.null(lote_spy$minutos_desde_venda) || is.na(lote_spy$minutos_desde_venda) || lote_spy$minutos_desde_venda >= 30.0
      
      # Gatilho Harmonicus SX Equities no Vale:
      # Roofing <= -0.60 | FSP >= 0.40 | FHRI >= 0.12 | d2Z >= 0.0
      cond_harm_spy <- (!is.null(dsp_fourier_spy$roof_z)) && 
                       (dsp_fourier_spy$roof_z <= -0.60) && 
                       (!is.null(dsp_fourier_spy$fsp) && dsp_fourier_spy$fsp >= 0.40) && 
                       (!is.null(dsp_fourier_spy$fhri) && dsp_fourier_spy$fhri >= 0.12) && 
                       (!is.null(dsp_fourier_spy$d2Z) && dsp_fourier_spy$d2Z >= 0.0)
      
      # Confirmação Alternativa em Overshoot / Crash (Roofing <= -1.40 e d2Z >= 0.0)
      cond_crash_spy <- (!is.null(dsp_fourier_spy$roof_z)) && 
                        (dsp_fourier_spy$roof_z <= -1.40) && 
                        (!is.null(dsp_fourier_spy$d2Z) && dsp_fourier_spy$d2Z >= 0.0)
      
      if ((cond_harm_spy || cond_crash_spy) && usdt_livre_rotacao >= VALOR_WALLSTREET_USDT && tempo_pos_venda_spy_ok) {
        lote_usdt_ws <- min(VALOR_WALLSTREET_USDT * fator_lote, usdt_livre_rotacao)
        pedido <- list(
          estrategia = "PLANO_SENTINELA_WALLSTREET",
          origem = "USDT", destino = "SPYB",
          valor_brl = lote_usdt_ws * p_usdt_brl,
          lucro_esperado_pct = 0.40, timestamp = agora_ts
        )
      }
    }
  }

  # ----------------------------------------------------------------------------
  # MOTOR 15: PLANO ADEUS, PERRY (Desova de Excesso de Ouro PAXG & Ativos Legados)
  # [ATIVO: Poda Cirúrgica de Ouro acima de 20% do Patrimônio Total sob Trava 6]
  # Calibração 17,8 meses (156.356 candles 5m): Tranche 35 USDT (~R$ 180) -> USDT (Simple Earn 6,88%)
  # Condição Indispensável: Execução SOMENTE COM LUCRO (FIFO >= +0.40% sobre VWAP de aquisição)
  # ----------------------------------------------------------------------------
  PLANO_ADEUS_PERRY_ATIVO <- TRUE
  if (is.null(pedido) && PLANO_ADEUS_PERRY_ATIVO) {
    em_cooldown_perry <- verificar_cooldown_veto("PLANO_ADEUS_PERRY", timeout_seg = 300)
    if (!em_cooldown_perry) {
      # 1. PRIORIDADE MÁXIMA: Desova Cirúrgica de Excesso de Ouro PAXG (> 20% do Patrimônio)
      if (saldo_paxg_brl > teto_ouro_dinamico) {
        pm_paxg <- obter_vwap_ativo("PAXG")
        if (pm_paxg <= 1000.0) pm_paxg <- 23576.0 # Fallback VWAP histórico auditado na Binance
        
        if (!is.null(p_paxg_brl) && p_paxg_brl > 0 && pm_paxg > 0) {
          ret_paxg <- (p_paxg_brl / pm_paxg) - 1.0
          
          # Executa estritamente se houver lucro sob a Trava 6 Breakeven FIFO (>= +0.40%)
          if (ret_paxg >= 0.0040) {
            excesso_ouro_brl <- saldo_paxg_brl - teto_ouro_dinamico
            # Tranche otimizada em 35 USDT (~180 reais), limitada ao excesso e preservando o piso de 10%
            lote_desova_paxg_brl <- min(35.0 * p_usdt_brl, excesso_ouro_brl)
            reserva_pos_desova <- saldo_paxg_brl - lote_desova_paxg_brl
            
            if (reserva_pos_desova >= piso_ouro_dinamico && lote_desova_paxg_brl >= 25.0) {
              pedido <- list(
                estrategia = "PLANO_ADEUS_PERRY",
                origem = "PAXG", destino = "USDT",
                valor_brl = lote_desova_paxg_brl,
                lucro_esperado_pct = round(ret_paxg * 100, 2), timestamp = agora_ts
              )
            }
          }
        }
      }
      
      # 2. BLINDAGEM DE GOVERNANÇA: PLANO ADEUS PERRY OPERA EXCLUSIVAMENTE OURO PAXG
      # É terminantemente vetado ao Plano Adeus Perry tocar ou liquidar altcoins (NEAR, LINK, ADA, AVAX).
      # Toda a gestão de NEAR pertence exclusivamente ao Plano 17 (Farol de Near) e de LINK ao Plano 16 (Caboclo).
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 16: PLANO CABOCLO DOS ORÁCULOS (BRL <-> LINK | Reversão Intradiária 4h)
  # [RECALIBRADO VIA SIMULAÇÃO QUANTITATIVA 5M - 20 MESES CONTÍNUOS]
  # Configuração Otimizada: Janela 4h (48p 5m), Z <= -0.75, d2Z >= 0.0, Trava 6 >= +1.00%
  # Lote: 4,05% (~130 reais) | Saída em Duas Tranches Sniper (Tranche 1: 60% a +1.00% | Tranche 2: 40% a +2.50% / Trailing)
  # Métricas Oficiais 5m (Simulação com Desengasgo de Regime e Regra Anti-Outlier):
  #   • Etapa 1 (Baseline Metralhadora): 85,0 trades/m | Lucro: 2,01 reais/m | Lucro/Trade: 0,02 reais | Posse: 1,8h
  #   • Etapa 2 (Corte de 60 Trades c/ Mesmo Lucro): 25,4 trades/m (-59,6 trades/m) | Lucro: 2,11 reais/m (+300% eficiência) | Posse: 5,6h
  #   • Etapa 3 (Duas Tranches Sniper): 27,6 ordens/m | Lucro: 4,89 a 7,95 reais/m (+132% a +295% lucro!) | DD: 3,51% | Win: 81,1%
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_link_brl) && !is.null(stats_link_4h) && ste_atual >= -0.02 && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    z_link_4h <- (p_link_brl - stats_link_4h$media) / stats_link_4h$sd
    dsp_link  <- if (!is.null(stats_link_4h$dsp)) stats_link_4h$dsp else list(theta = 0, d2Z = 0)
    acc_link  <- if (!is.null(dsp_link$d2Z)) dsp_link$d2Z else 0.0
    
    em_cooldown_link <- verificar_cooldown_veto("PLANO_CABOCLO_DOS_ORACULOS", timeout_seg = 300)
    lote_info_link   <- obter_lote_aberto_estrategia("PLANO_CABOCLO_DOS_ORACULOS", "LINK")
    tempo_compra_link_ok <- !isTRUE(lote_info_link$tem_lote) || is.null(lote_info_link$minutos_posse) || is.na(lote_info_link$minutos_posse) || lote_info_link$minutos_posse >= 12.0
    
    # Gatilho de Entrada Sniper: Z <= -0.75 com Inflexão d2Z >= 0.0 (respeitando cooldown e posse mínima de 12 min)
    cond_compra_link <- !em_cooldown_link && tempo_compra_link_ok && (z_link_4h <= -0.75) && (acc_link >= 0.0) && (caixa_brl_livre_cripto >= 25.0) && (saldo_link_brl < teto_link_brl)
    
    if (cond_compra_link) {
      lote_link <- min(VALOR_CABOCLO_BRL * fator_lote, caixa_brl_livre_cripto)
      if (lote_link >= 25.0) {
        pedido <- list(
          estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
          origem = "BRL", destino = "LINK",
          valor_brl = lote_link,
          lucro_esperado_pct = 1.00, timestamp = agora_ts
        )
      }
    } else if (saldo_link_brl >= 25.0) {
      # Saída em Duas Tranches sob Trava 6:
      # Tranche 1 (60% da posição): Realização rápida em Z >= 0.20 e retorno >= +1.00% (elimina risco e devolve caixa)
      # Tranche 2 (40% restante): Surfa ralis maiores até retorno >= +2.50% OU saída por exaustão/trailing (Z >= 0.70 e d2Z < -0.05 com retorno >= +1.00%)
      # Regra Anti-Poeira Binance: se a sobra da tranche for < 22.0 reais (notional mínimo), desova 100% de uma vez em trade único.
      em_cooldown_link <- verificar_cooldown_veto("PLANO_CABOCLO_DOS_ORACULOS", timeout_seg = 300)
      lote_info_link <- obter_lote_aberto_estrategia("PLANO_CABOCLO_DOS_ORACULOS", "LINK")
      preco_ref_link <- if (isTRUE(lote_info_link$tem_lote)) {
        if (!is.null(lote_info_link$vwap_abertos) && !is.na(lote_info_link$vwap_abertos) && lote_info_link$vwap_abertos > 0) lote_info_link$vwap_abertos else lote_info_link$preco_compra
      } else NA
      
      retorno_real_link <- if (!is.na(preco_ref_link) && preco_ref_link > 0) ((p_link_brl - preco_ref_link) / preco_ref_link) * 100 else 0.0
      
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (48h a 72h decaindo suavemente até +0.40% piso)
      meta_alvo_link <- calcular_meta_lucro_decay(lote_info_link$minutos_posse, meta_base = 1.00, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      
      # Identificação de Tranche Ativa:
      # Se saldo_link_brl >= 70% do lote padrão (VALOR_CABOCLO_BRL * 0.70), estamos na Tranche 1 (posição cheia).
      # Se saldo_link_brl < 70%, a Tranche 1 já foi desovada e estamos na Tranche 2 (saldo residual/trailer).
      is_tranche_1 <- (saldo_link_brl >= (VALOR_CABOCLO_BRL * 0.70))
      
      deve_vender_link <- FALSE
      valor_venda_link <- saldo_link_brl
      lucro_alvo_link  <- meta_alvo_link
      
      if (is_tranche_1) {
        # TRANCHE 1 (60%): Realização em Z >= 0.20 com retorno >= meta_alvo_link OU Take Profit rápido >= +1.50%
        cond_tranche_1 <- (retorno_real_link >= 1.50) || (z_link_4h >= 0.20 && retorno_real_link >= meta_alvo_link)
        if (cond_tranche_1) {
          deve_vender_link <- TRUE
          lucro_alvo_link  <- meta_alvo_link
          # Fração de 60%:
          valor_tranche_1 <- round(saldo_link_brl * 0.60, 2)
          sobra_tranche_2 <- saldo_link_brl - valor_tranche_1
          # Se a sobra for inferior a 22 reais (notional mínimo da Binance), desova tudo de uma vez
          if (sobra_tranche_2 < 22.0 || valor_tranche_1 < 22.0) {
            valor_venda_link <- saldo_link_brl
          } else {
            valor_venda_link <- valor_tranche_1
          }
        }
      } else {
        # TRANCHE 2 (40% restante / Trailer):
        # 🛡️ Trailing Ratchet: se o retorno atingir >= +1.50% (evita devolver ganhos), dispara realização
        # OU exaustão cinemática real (Z >= 0.70 e acc_link < 0.0 com retorno >= +0.80%)
        # OU rali máximo >= +2.50%
        cond_tranche_2 <- (retorno_real_link >= 1.50) || 
                          (z_link_4h >= 0.70 && acc_link < 0.0 && retorno_real_link >= 0.80) || 
                          (retorno_real_link >= 2.50)
        if (cond_tranche_2) {
          deve_vender_link <- TRUE
          valor_venda_link <- saldo_link_brl # Desova 100% da tranche residual
          lucro_alvo_link  <- round(retorno_real_link, 2)
        }
      }
      
      deve_vender_link <- deve_vender_link && isTRUE(lote_info_link$tem_lote) && !em_cooldown_link
      
      if (deve_vender_link) {
        pedido <- list(
          estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
          origem = "LINK", destino = "BRL",
          valor_brl = valor_venda_link,
          lucro_esperado_pct = lucro_alvo_link, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 17: PLANO FAROL DE NEAR (BRL <-> NEAR | Reversão Intradiária 6h G500)
  # [ATIVO EM PRODUÇÃO CONFORME SIMULAÇÃO QUANTITATIVA 18 MESES / CANDLES 5M]
  # Métricas Oficiais: Lucro +17,34 a +25,92 reais/mês | Posse Média: 1,5 a 4,8 horas (Ultrarrápido)
  # Correlação com Bitcoin: 0,267 (Menor correlação de todo o portfólio cripto)
  # Taxa de Acerto: 100,0% sob Trava 6 Breakeven Lock FIFO Real >= +0,80%
  # 🛡️ Blindagem Anti-Micro-Prejuízo (Trade 2 Fix): Pré-filtro de margem P >= P_compra * 1.006
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_near_brl) && !is.null(stats_near_6h) && ste_atual >= -0.02 && pc1_atual < PC1_CORTE_SECULAR && w_energy < 55.0) {
    z_near_6h <- (p_near_brl - stats_near_6h$media) / stats_near_6h$sd
    dsp_near  <- if (!is.null(stats_near_6h$dsp)) stats_near_6h$dsp else list(theta = 0, d2Z = 0)
    acc_near  <- if (!is.null(dsp_near$d2Z)) dsp_near$d2Z else 0.0
    
    # Gatilho de Entrada: Z_6h <= -0.75 com Inflexão d2Z >= 0.0
    cond_compra_near <- (z_near_6h <= -0.75) && (acc_near >= 0.0) && (caixa_brl_livre_cripto >= 25.0) && (saldo_near_brl < teto_near_brl)
    
    if (cond_compra_near) {
      lote_near <- min(VALOR_NEAR_BRL * fator_lote, caixa_brl_livre_cripto)
      if (lote_near >= 25.0) {
        pedido <- list(
          estrategia = "PLANO_FAROL_DE_NEAR",
          origem = "BRL", destino = "NEAR",
          valor_brl = lote_near,
          lucro_esperado_pct = 0.80, timestamp = agora_ts
        )
      }
    } else if (saldo_near_brl >= 25.0) {
      # Saída sob Trava 6 FIFO com Z >= 0.20 OU Take Profit por Lucro Real Expressivo (>= +1.20%)
      # 🛡️ Subtrava 6.2: Target Decay Ratchet (48h a 72h decaindo suavemente até +0.40% piso)
      em_cooldown_near <- verificar_cooldown_veto("PLANO_FAROL_DE_NEAR", timeout_seg = 300)
      lote_info_near <- obter_lote_aberto_estrategia("PLANO_FAROL_DE_NEAR", "NEAR")
      preco_ref_near <- if (isTRUE(lote_info_near$tem_lote)) {
        if (!is.null(lote_info_near$vwap_abertos) && !is.na(lote_info_near$vwap_abertos) && lote_info_near$vwap_abertos > 0) lote_info_near$vwap_abertos else lote_info_near$preco_compra
      } else NA
      
      retorno_real_near <- if (!is.na(preco_ref_near) && preco_ref_near > 0) ((p_near_brl - preco_ref_near) / preco_ref_near) * 100 else 0.0
      meta_alvo_near <- calcular_meta_lucro_decay(lote_info_near$minutos_posse, meta_base = 0.80, horas_inicio_decay = 48.0, horas_fim_decay = 72.0, piso_minimo = 0.40)
      margem_minima_near_ok <- (retorno_real_near >= meta_alvo_near)
      take_profit_near_ok <- (retorno_real_near >= 1.20)
      
      # Disparo: Take Profit imediato (>= +1.20%) OU reversão do oscilador (Z >= 0.20 com retorno >= meta_alvo_near)
      deve_vender_near <- isTRUE(lote_info_near$tem_lote) && !em_cooldown_near && (take_profit_near_ok || (z_near_6h >= 0.20 && margem_minima_near_ok))
      
      if (deve_vender_near) {
        pedido <- list(
          estrategia = "PLANO_FAROL_DE_NEAR",
          origem = "NEAR", destino = "BRL",
          valor_brl = saldo_near_brl, # Saída Única: Desova 100% da posição em 1 trade limpo
          lucro_esperado_pct = meta_alvo_near, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 18: PLANO RAIO DE TESLA (USDT <-> TSLAB | Vencedor Soberano do Torneio US Equities)
  # Selecionado compulsoriamente pelo Torneio Empírico (+16,59 reais/mês vs +2,15 da Apple)
  # Metricas 5m Contínuos: 9,8 trades/mês | Posse Rápida: 42,5 horas | Win Rate: 100,0%
  # Lote Dinâmico: 45 USDT (~230 BRL / 7,2% Patr.) | Trava 6 Breakeven FIFO: +0,60% a +0,80%
  # ----------------------------------------------------------------------------
  if (is.null(pedido)) {
    # 1. Realização de Lucro: Venda TSLAB -> USDT sob Trava 6 Breakeven FIFO (>= +0.60% ágil / +0.80% TP)
    lote_tsla <- obter_lote_aberto_estrategia("PLANO_RAIO_DE_TESLA", "TSLAB")
    if (saldo_tslab_usd > 0.01) {
      p_tsla_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=TSLABUSDT"), "parsed")$price), error = function(e) NULL)
      pm_tsla <- if (lote_tsla$tem_lote && !is.null(lote_tsla$preco_compra) && lote_tsla$preco_compra > 0) lote_tsla$preco_compra else obter_vwap_ativo("TSLAB")
      
      if (!is.null(p_tsla_live) && p_tsla_live > 0) {
        p_custo_tsla_usdt <- tryCatch({
          tr_t <- call_binance("/api/v3/myTrades", list(symbol = "TSLABUSDT", limit = 5))
          if (!is.null(tr_t) && length(tr_t) > 0) {
            buys_t <- tr_t[sapply(tr_t, function(x) isTRUE(x$isBuyer))]
            if (length(buys_t) > 0) as.numeric(tail(buys_t, 1)[[1]]$price) else (pm_tsla / p_usdt_brl)
          } else (pm_tsla / p_usdt_brl)
        }, error = function(e) (pm_tsla / p_usdt_brl))
        
        ret_tsla <- if (!is.null(p_custo_tsla_usdt) && p_custo_tsla_usdt > 0) (p_tsla_live / p_custo_tsla_usdt) - 1.0 else ((p_tsla_live * p_usdt_brl) / pm_tsla) - 1.0
        tempo_tsla_ok <- !lote_tsla$tem_lote || lote_tsla$minutos_posse >= 15.0 || ret_tsla >= 0.010
        
        # Saída sob Trava 6 Breakeven FIFO: Take profit a +0.80% ou saída ágil a +0.60% com posse >= 1h
        cond_saida_tsla <- ((ret_tsla >= 0.0080) || (ret_tsla >= 0.0060 && !is.null(lote_tsla$minutos_posse) && lote_tsla$minutos_posse >= 60.0)) && tempo_tsla_ok
        
        if (cond_saida_tsla) {
          val_venda_brl <- saldo_tslab_usd * p_tsla_live * p_usdt_brl
          pedido <- list(
            estrategia = "PLANO_RAIO_DE_TESLA",
            origem = "TSLAB", destino = "USDT",
            valor_brl = val_venda_brl,
            lucro_esperado_pct = round(ret_tsla * 100, 2), timestamp = agora_ts
          )
        }
      }
    } else if (usdt_livre_rotacao >= 20.0) {
      # 2. Entrada em Dip Intradiário: Z_4h <= -1.00 com inflexão cinemática positiva (d2Z >= 0.0)
      stats_tsla <- obter_stats_tslab_4h()
      p_tsla_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=TSLABUSDT"), "parsed")$price), error = function(e) 380.0)
      if (is.null(p_tsla_live) || is.na(p_tsla_live)) p_tsla_live <- 380.0
      
      z_tsla <- (p_tsla_live - stats_tsla$media) / stats_tsla$sd
      acc_tsla <- if (!is.null(stats_tsla$dsp$d2Z)) stats_tsla$dsp$d2Z else 0.0
      
      tempo_pos_venda_tsla_ok <- is.null(lote_tsla$minutos_desde_venda) || is.na(lote_tsla$minutos_desde_venda) || lote_tsla$minutos_desde_venda >= 30.0
      
      if (z_tsla <= -1.00 && acc_tsla >= 0.0 && tempo_pos_venda_tsla_ok) {
        lote_usdt_tsla <- min(VALOR_TESLA_USDT * fator_lote, usdt_livre_rotacao, 50.0)
        if (lote_usdt_tsla >= 18.0) {
          pedido <- list(
            estrategia = "PLANO_RAIO_DE_TESLA",
            origem = "USDT", destino = "TSLAB",
            valor_brl = lote_usdt_tsla * p_usdt_brl,
            lucro_esperado_pct = 0.80, timestamp = agora_ts,
            detalhe = sprintf("Entrada Dip Tesla: Z_tsla=%.2f, d2Z=%.4f", z_tsla, acc_tsla)
          )
        }
      }
    }
  }
  
  # Log do Radar em labtrader_radar.log
  z_bnb_val  <- if (!is.null(p_bnb_brl) && !is.null(stats_bnb_1h)) (p_bnb_brl - stats_bnb_1h$media) / stats_bnb_1h$sd else 0.0
  z_link_val <- if (!is.null(p_link_brl) && !is.null(stats_link_4h)) (p_link_brl - stats_link_4h$media) / stats_link_4h$sd else 0.0
  z_ada_val  <- if (!is.null(p_ada_brl)) (p_ada_brl - stats_ada$media) / stats_ada$sd else 0.0
  z_near_val <- if (!is.null(p_near_brl) && !is.null(stats_near_6h)) (p_near_brl - stats_near_6h$media) / stats_near_6h$sd else 0.0
  z_avax_val <- if (!is.null(p_avax_brl)) (p_avax_brl - stats_avax$media) / stats_avax$sd else 0.0
  
  log_line <- sprintf("[%s] RADAR: Z_Guiana=%.2f | VIX=%.2f | Z_Patria=%.2f | SpreadPeg=%.4f | Z_Link=%.2f | Z_SOL=%.2f | Z_ETH=%.2f | Z_BNB=%.2f | Z_ADA=%.2f | Z_NEAR=%.2f | Z_AVAX=%.2f | RetBTC5m=%.2f%% | Disparo=%s\n",
                      agora_str, z_guiana, vix_atual, z_patria, ifelse(!is.null(usd_oficial), p_usdt_brl - usd_oficial, 0),
                      z_link_val,
                      (p_sol_brl / p_btc_brl - stats_sol_btc$media) / stats_sol_btc$sd,
                      (p_eth_brl / p_btc_brl - stats_eth_btc$media) / stats_eth_btc$sd,
                      z_bnb_val, z_ada_val, z_near_val, z_avax_val,
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
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

# --- PARÂMETROS DE VOLUME (8 MOTORES OFICIAIS) ---
VALOR_GUIANA_BRL   <- 100.00
VALOR_VIX_BRL      <- 200.00
VALOR_PEG_BRL      <- 200.00
VALOR_LINK_BRL     <- 100.00
VALOR_SPILL_BRL    <- 50.00
VALOR_CORISCO_BRL  <- 50.00
VALOR_TITAS_BRL    <- 60.00
VALOR_SAGARANA_BRL <- 75.00

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

obter_stats_guiana_168h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT BTCBRL, USDTBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 10080;")
    if (nrow(df) >= 60) {
      ratios <- (df$USDTBRL * 4587.0) / df$BTCBRL
      return(list(media = mean(ratios, na.rm = TRUE), sd = max(0.0001, sd(ratios, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 0.05920, sd = 0.00350))
}

obter_media_link_51h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT LINKBRL FROM Historico_binance WHERE LINKBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 3060;")
    if (nrow(df) >= 30) {
      return(list(media = mean(df$LINKBRL, na.rm = TRUE), sd = max(0.05, sd(df$LINKBRL, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 61.20, sd = 1.80))
}

obter_stats_sol_btc_720h <- function() {
  db_path <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/home/ubuntu/moneylab-dashboard/MoneyBot_Local.db"
  tryCatch({
    con <- dbConnect(SQLite(), db_path)
    on.exit(dbDisconnect(con))
    df <- dbGetQuery(con, "SELECT SOLBRL, BTCBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 43200;")
    if (nrow(df) >= 120) {
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
    df <- dbGetQuery(con, "SELECT SOLBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 15;")
    if (nrow(df) >= 5) {
      return(list(media = mean(df$SOLBRL, na.rm = TRUE), sd = max(0.05, sd(df$SOLBRL, na.rm = TRUE))))
    }
  }, error = function(e) NULL)
  return(list(media = 487.50, sd = 2.50))
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
  
  stats_guiana  <- obter_stats_guiana_168h()
  stats_link    <- obter_media_link_51h()
  stats_sol_btc <- obter_stats_sol_btc_720h()
  stats_sol_15m <- obter_stats_sol_15m()
  stats_eth_btc <- obter_stats_eth_btc_24h()
  ret_btc_5m    <- obter_retorno_btc_5m()
  
  # Modulação de Lote
  fator_lote   <- ifelse(ste_atual >= -0.05 && w_energy < 50.0, 1.0, 0.5)
  
  pedido <- NULL
  
  # ----------------------------------------------------------------------------
  # MOTOR 1: PLANO GUIANA BRASILEIRA (PAXG <-> BTC | R$ 100)
  # ----------------------------------------------------------------------------
  ratio_guiana <- p_paxg_brl / p_btc_brl
  z_guiana     <- (ratio_guiana - stats_guiana$media) / stats_guiana$sd
  
  if (z_guiana <= -1.65) {
    # Bitcoin eufórico / Ouro barato -> Vende BTC e compra PAXG
    lucro_proj <- ((stats_guiana$media / ratio_guiana) - 1) * 100 - 0.20
    if (lucro_proj >= 1.50) {
      pedido <- list(
        estrategia = "PLANO_GUIANA_BRASILEIRA",
        origem = "BTC", destino = "PAXG",
        valor_brl = VALOR_GUIANA_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  } else if (z_guiana >= 1.65) {
    # Ouro caro / Bitcoin em desconto -> Vende PAXG e compra BTC
    lucro_proj <- ((ratio_guiana / stats_guiana$media) - 1) * 100 - 0.20
    if (lucro_proj >= 1.50) {
      pedido <- list(
        estrategia = "PLANO_GUIANA_BRASILEIRA",
        origem = "PAXG", destino = "BTC",
        valor_brl = VALOR_GUIANA_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
      )
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 2: PLANO ESCUDO DE AQUILES (BRL -> BTC | R$ 200)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && vix_atual >= 22.50 && (pc1_atual >= 0.40 || ent_atual <= 1.75) && w_energy < 50.0) {
    pedido <- list(
      estrategia = "PLANO_ESCUDO_DE_AQUILES",
      origem = "BRL", destino = "BTC",
      valor_brl = VALOR_VIX_BRL * fator_lote, lucro_esperado_pct = 2.00, timestamp = agora_ts
    )
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 3: PLANO PÁTRIA VOLÁTIL (BRL <-> USDT | R$ 200)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(usd_oficial)) {
    spread_peg <- p_usdt_brl - usd_oficial
    if (spread_peg <= -0.0400) {
      lucro_proj <- (abs(spread_peg) / usd_oficial) * 100
      if (lucro_proj >= 0.80) {
        pedido <- list(
          estrategia = "PLANO_PATRIA_VOLATIL",
          origem = "BRL", destino = "USDT",
          valor_brl = VALOR_PEG_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 4: PLANO CABOCLO DOS ORÁCULOS (BRL <-> LINK | R$ 100)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_link_brl) && ste_atual >= 0.0 && w_energy < 50.0) {
    z_link <- (p_link_brl - stats_link$media) / stats_link$sd
    if (z_link <= -2.00) {
      lucro_proj <- ((stats_link$media / p_link_brl) - 1) * 100
      if (lucro_proj >= 2.00) {
        pedido <- list(
          estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
          origem = "BRL", destino = "LINK",
          valor_brl = VALOR_LINK_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 5: PLANO GRAVIDADE ZERO (BTC <-> SOL | R$ 50)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_sol_brl) && !is.null(p_btc_brl) && pc1_atual >= 0.40 && pc1_atual < 0.70 && ste_atual >= 0.0) {
    ratio_sol_btc <- p_sol_brl / p_btc_brl
    z_sol_btc     <- (ratio_sol_btc - stats_sol_btc$media) / stats_sol_btc$sd
    if (z_sol_btc <= -1.75) {
      lucro_proj <- ((stats_sol_btc$media / ratio_sol_btc) - 1) * 100
      if (lucro_proj >= 3.00) {
        pedido <- list(
          estrategia = "PLANO_GRAVIDADE_ZERO",
          origem = "BTC", destino = "SOL",
          valor_brl = VALOR_SPILL_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 6: PLANO CORISCO DA SOLANA (BRL -> SOL 15m | R$ 50)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_sol_brl) && ste_atual >= 0.0 && pc1_atual < 0.70 && w_energy < 50.0) {
    z_sol_15m <- (p_sol_brl - stats_sol_15m$media) / stats_sol_15m$sd
    if (z_sol_15m <= -2.00) {
      lucro_proj <- max(0.40, ((stats_sol_15m$media / p_sol_brl) - 1) * 100)
      if (lucro_proj >= 0.35) {
        pedido <- list(
          estrategia = "PLANO_CORISCO_DA_SOLANA",
          origem = "BRL", destino = "SOL",
          valor_brl = VALOR_CORISCO_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 7: PLANO DUELO DE TITÃS (BTC <-> ETH 24h | R$ 60)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && !is.null(p_eth_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75) {
    ratio_eth_btc <- p_eth_brl / p_btc_brl
    z_eth_btc     <- (ratio_eth_btc - stats_eth_btc$media) / stats_eth_btc$sd
    if (z_eth_btc <= -1.50) {
      lucro_proj <- ((stats_eth_btc$media / ratio_eth_btc) - 1) * 100
      if (lucro_proj >= 0.90) {
        pedido <- list(
          estrategia = "PLANO_DUELO_DE_TITAS",
          origem = "BTC", destino = "ETH",
          valor_brl = VALOR_TITAS_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    } else if (z_eth_btc >= 1.50) {
      lucro_proj <- ((ratio_eth_btc / stats_eth_btc$media) - 1) * 100
      if (lucro_proj >= 0.90) {
        pedido <- list(
          estrategia = "PLANO_DUELO_DE_TITAS",
          origem = "ETH", destino = "BTC",
          valor_brl = VALOR_TITAS_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = agora_ts
        )
      }
    }
  }
  
  # ----------------------------------------------------------------------------
  # MOTOR 8: PLANO FLECHA DE SAGARANA (BRL -> BTC 5m | R$ 75)
  # ----------------------------------------------------------------------------
  if (is.null(pedido) && ret_btc_5m <= -0.0040 && w_energy < 50.0) {
    pedido <- list(
      estrategia = "PLANO_FLECHA_DE_SAGARANA",
      origem = "BRL", destino = "BTC",
      valor_brl = VALOR_SAGARANA_BRL * fator_lote, lucro_esperado_pct = 0.85, timestamp = agora_ts
    )
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
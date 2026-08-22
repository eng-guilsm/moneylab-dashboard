# ==============================================================================
# LABTRADER v6.3 - MOTOR QUANTICO INTEGRAL (8 MOTORES OFICIAIS MONEYLAB)
# ==============================================================================
# 🛡️ BLOCO 1: ESTRUTURAIS DE BAIXO RISCO
# 🥇 1. Plano Guiana Brasileira (PAXG <-> BTC | R$ 100,00)
# 🛡️ 2. Plano Escudo de Aquiles (VIX Dip-Hunter | R$ 200,00)
# 💵 3. Plano Pátria Volátil (Dollar-Peg PTAX Spread | R$ 200,00)
# 🌐 4. Plano Caboclo dos Oráculos (Infraestrutura LINK | R$ 100,00)
# 🪐 5. Plano Gravidade Zero (Spillover Macro SOL | R$ 50,00)
#
# ⚡ BLOCO 2: TÁTICOS INTRADIÁRIOS DE MÉDIO RISCO
# ⚡ 6. Plano Corisco da Solana (SOL Bounce 15m | R$ 50,00)
# ⚔️ 7. Plano Duelo de Titãs (Micro-Pairs ETH/BTC 24h | R$ 60,00)
# 🏹 8. Plano Flecha de Sagarana (BTC Micro-Dip 5m | R$ 75,00)
# ==============================================================================

library(httr)
library(jsonlite)
library(RSQLite)

# --- PARÂMETROS METROLÓGICOS (8 MOTORES) ---
VALOR_GUIANA_BRL   <- 100.00
MEDIA_PAXG_BTC     <- 0.06554
SIGMA_PAXG_BTC     <- 0.00590
Z_UPPER_PAXG       <- 1.65
Z_LOWER_PAXG       <- -1.65

VALOR_VIX_BRL      <- 200.00
VIX_PICO_ALERTA    <- 22.50

VALOR_PEG_BRL      <- 200.00
SIGMA_PEG_DESVIO   <- 0.0400
LUCRO_MIN_PEG      <- 0.80

VALOR_LINK_BRL     <- 100.00
LUCRO_MIN_LINK     <- 2.20

VALOR_SPILL_BRL    <- 50.00
MEDIA_SOL_BTC      <- 0.00220

VALOR_CORISCO_BRL  <- 50.00
VALOR_TITAS_BRL    <- 60.00
VALOR_SAGARANA_BRL <- 75.00

DELAY_LOOP         <- 30

cat("\n🤖 [LABTRADER v6.3] Motor Quântico Integral (8 Motores Oficiais) Inicializado.\n")
cat("----------------------------------------------------------------------\n")
cat("🥇 1. Plano Guiana Brasileira (PAXG <-> BTC | R$ 100,00)\n")
cat("🛡️ 2. Plano Escudo de Aquiles (BRL -> BTC | R$ 200,00)\n")
cat("💵 3. Plano Pátria Volátil (BRL <-> USDT | R$ 200,00)\n")
cat("🌐 4. Plano Caboclo dos Oráculos (BRL <-> LINK | R$ 100,00)\n")
cat("🪐 5. Plano Gravidade Zero (BTC <-> SOL | R$ 50,00)\n")
cat("⚡ 6. Plano Corisco da Solana (BRL -> SOL | R$ 50,00)\n")
cat("⚔️ 7. Plano Duelo de Titãs (BTC <-> ETH | R$ 60,00)\n")
cat("🏹 8. Plano Flecha de Sagarana (BRL -> BTC | R$ 75,00)\n")
cat("----------------------------------------------------------------------\n")

obter_preco_binance <- function(symbol) {
  url <- paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)
  tryCatch({
    resp <- content(GET(url, timeout(5)), as = "text")
    as.numeric(fromJSON(resp)$price)
  }, error = function(e) NULL)
}

obter_ultimo_vix <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT VIX_Index FROM Historico_macro WHERE VIX_Index IS NOT NULL ORDER BY Data DESC LIMIT 1;")
      dbDisconnect(con)
      if (nrow(res) > 0) return(as.numeric(res$VIX_Index[1]))
    }
  }, error = function(e) NULL)
  return(15.0)
}

obter_ultimo_usd_comercial <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT USD_BRL FROM Historico_rapido WHERE USD_BRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1;")
      dbDisconnect(con)
      if (nrow(res) > 0) return(as.numeric(res$USD_BRL[1]))
    }
  }, error = function(e) NULL)
  return(NULL)
}

obter_media_link_51h <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT LINKBRL FROM Historico_binance WHERE LINKBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 3060;")
      dbDisconnect(con)
      if (nrow(res) >= 100) return(list(media = mean(res$LINKBRL), sd = sd(res$LINKBRL)))
    }
  }, error = function(e) NULL)
  return(list(media = 65.0, sd = 2.50))
}

obter_stats_sol_15m <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT SOLBRL FROM Historico_binance WHERE SOLBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 300;")
      dbDisconnect(con)
      if (nrow(res) >= 30) {
        idx_15m <- seq(1, nrow(res), by = 15)
        amostras <- res$SOLBRL[idx_15m]
        return(list(media = mean(amostras), sd = sd(amostras)))
      }
    }
  }, error = function(e) NULL)
  return(list(media = 480.0, sd = 10.0))
}

obter_stats_eth_btc_24h <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT ETHBRL, BTCBRL FROM Historico_binance WHERE ETHBRL IS NOT NULL AND BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 1440;")
      dbDisconnect(con)
      if (nrow(res) >= 60) {
        ratios <- res$ETHBRL / res$BTCBRL
        return(list(media = mean(ratios), sd = sd(ratios)))
      }
    }
  }, error = function(e) NULL)
  return(list(media = 0.0310, sd = 0.0010))
}

obter_retorno_btc_5m <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT BTCBRL FROM Historico_binance WHERE BTCBRL IS NOT NULL ORDER BY Data_Hora DESC LIMIT 6;")
      dbDisconnect(con)
      if (nrow(res) >= 6) {
        return((res$BTCBRL[1] / res$BTCBRL[nrow(res)]) - 1)
      }
    }
  }, error = function(e) NULL)
  return(0.0)
}

obter_ultimo_harmonicus <- function() {
  tryCatch({
    db_file <- "MoneyBot_Local.db"
    if (file.exists(db_file)) {
      con <- dbConnect(SQLite(), db_file)
      res <- dbGetQuery(con, "SELECT Razao_Absorcao_PC1, Entropia_Espectral, Energia_Total_Fourier, Energia_Wavelet_Morlet, Fluxo_Informacao_STE, Regime_Topologico FROM Harmonicus_Metricas_Globais ORDER BY Data_Hora DESC LIMIT 1;")
      dbDisconnect(con)
      if (nrow(res) > 0) return(res[1, ])
    }
  }, error = function(e) NULL)
  return(list(Razao_Absorcao_PC1 = 0.30, Entropia_Espectral = 2.00, Energia_Total_Fourier = 25.0, Energia_Wavelet_Morlet = 5.0, Fluxo_Informacao_STE = 0.0, Regime_Topologico = "TURBULENCIA_LOCAL"))
}

while(TRUE) {
  tryCatch({
    if (file.exists("solicitacao.rds")) {
      cat("⏳ [LABTRADER] Aguardando LabPolice processar ordem anterior...\n")
      Sys.sleep(5)
      next
    }
    
    hora_str <- format(Sys.time(), "%H:%M:%S")
    pedido <- NULL
    
    # 1. Cotações Binance em Tempo Real
    p_btc_brl   <- obter_preco_binance("BTCBRL")
    p_paxg_usdt <- obter_preco_binance("PAXGUSDT")
    p_usdt_brl  <- obter_preco_binance("USDTBRL")
    p_sol_usdt  <- obter_preco_binance("SOLUSDT")
    p_eth_usdt  <- obter_preco_binance("ETHUSDT")
    p_link_brl  <- obter_preco_binance("LINKBRL")
    p_sol_brl   <- obter_preco_binance("SOLBRL")
    p_eth_brl   <- obter_preco_binance("ETHBRL")
    
    if (is.null(p_btc_brl) || is.null(p_paxg_usdt) || is.null(p_usdt_brl)) {
      cat("⚠️ [FEED] Cotações temporariamente indisponíveis. Aguardando...\n")
      Sys.sleep(10)
      next
    }
    
    p_paxg_brl   <- p_paxg_usdt * p_usdt_brl
    vix_atual    <- obter_ultimo_vix()
    usd_oficial  <- obter_ultimo_usd_comercial()
    harm_atual   <- obter_ultimo_harmonicus()
    pc1_atual    <- as.numeric(harm_atual$Razao_Absorcao_PC1)
    ent_atual    <- as.numeric(harm_atual$Entropia_Espectral)
    ste_atual    <- ifelse(!is.null(harm_atual$Fluxo_Informacao_STE) && !is.na(harm_atual$Fluxo_Informacao_STE), as.numeric(harm_atual$Fluxo_Informacao_STE), 0.0)
    w_energy     <- ifelse(!is.null(harm_atual$Energia_Wavelet_Morlet) && !is.na(harm_atual$Energia_Wavelet_Morlet), as.numeric(harm_atual$Energia_Wavelet_Morlet), 5.0)
    stats_link   <- obter_media_link_51h()
    stats_sol_15m <- obter_stats_sol_15m()
    stats_eth_btc <- obter_stats_eth_btc_24h()
    ret_btc_5m   <- obter_retorno_btc_5m()
    
    # Modulação Dinâmica de Lote por Entropia de Transferência e Wavelet
    fator_lote   <- ifelse(ste_atual >= -0.05 && w_energy < 50.0, 1.0, 0.5)
    
    # --- MOTOR 1: PLANO GUIANA BRASILEIRA (PAXG <-> BTC | R$ 100) ---
    ratio_ouro_btc <- p_paxg_brl / p_btc_brl
    z_ouro_btc     <- (ratio_ouro_btc - MEDIA_PAXG_BTC) / SIGMA_PAXG_BTC
    
    cat(sprintf("[%s] [PAXG/BTC]: Ratio: %.5f (Z: %+.2fσ) | [PC1]: %.1f%% | [STE]: %+.4f | [Modulação]: %.0f%%\n",
                hora_str, ratio_ouro_btc, z_ouro_btc, pc1_atual * 100, ste_atual, fator_lote * 100))
    
    if (z_ouro_btc >= Z_UPPER_PAXG) {
      lucro_proj <- ((ratio_ouro_btc / MEDIA_PAXG_BTC) - 1) * 100 - 0.20
      if (lucro_proj >= 1.50) {
        pedido <- list(
          estrategia = "PLANO_GUIANA_BRASILEIRA",
          origem = "PAXG", destino = "BTC",
          valor_brl = VALOR_GUIANA_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
        )
      }
    }
    
    if (is.null(pedido) && z_ouro_btc <= Z_LOWER_PAXG) {
      lucro_proj <- ((MEDIA_PAXG_BTC / ratio_ouro_btc) - 1) * 100 - 0.20
      if (lucro_proj >= 1.50) {
        pedido <- list(
          estrategia = "PLANO_GUIANA_BRASILEIRA",
          origem = "BTC", destino = "PAXG",
          valor_brl = VALOR_GUIANA_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
        )
      }
    }
    
    # --- MOTOR 2: PLANO ESCUDO DE AQUILES (BRL -> BTC | R$ 200) ---
    if (is.null(pedido) && vix_atual >= VIX_PICO_ALERTA && (pc1_atual >= 0.40 || ent_atual <= 1.75) && w_energy < 50.0) {
      lucro_proj <- 2.50
      pedido <- list(
        estrategia = "PLANO_ESCUDO_DE_AQUILES",
        origem = "BRL", destino = "BTC",
        valor_brl = VALOR_VIX_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
      )
    }
    
    # --- MOTOR 3: PLANO PÁTRIA VOLÁTIL (BRL <-> USDT | R$ 200) ---
    if (is.null(pedido) && !is.null(usd_oficial)) {
      delta_peg <- p_usdt_brl - usd_oficial
      if (delta_peg <= -SIGMA_PEG_DESVIO) {
        lucro_proj <- (abs(delta_peg) / usd_oficial) * 100
        if (lucro_proj >= LUCRO_MIN_PEG) {
          pedido <- list(
            estrategia = "PLANO_PATRIA_VOLATIL",
            origem = "BRL", destino = "USDT",
            valor_brl = VALOR_PEG_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      }
    }
    
    # --- MOTOR 4: PLANO CABOCLO DOS ORÁCULOS (BRL <-> LINK | R$ 100) ---
    if (is.null(pedido) && !is.null(p_link_brl) && ste_atual >= 0.0 && w_energy < 50.0) {
      z_link <- (p_link_brl - stats_link$media) / stats_link$sd
      if (z_link <= -2.00) {
        lucro_proj <- ((stats_link$media / p_link_brl) - 1) * 100
        if (lucro_proj >= LUCRO_MIN_LINK) {
          pedido <- list(
            estrategia = "PLANO_CABOCLO_DOS_ORACULOS",
            origem = "BRL", destino = "LINK",
            valor_brl = VALOR_LINK_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      }
    }
    
    # --- MOTOR 5: PLANO GRAVIDADE ZERO (BTC <-> SOL | R$ 50) ---
    if (is.null(pedido) && !is.null(p_sol_usdt) && pc1_atual >= 0.40 && pc1_atual < 0.70 && ste_atual >= 0.0) {
      ratio_sol_btc <- (p_sol_usdt * p_usdt_brl) / p_btc_brl
      if (ratio_sol_btc <= (MEDIA_SOL_BTC * 0.94)) {
        lucro_proj <- ((MEDIA_SOL_BTC / ratio_sol_btc) - 1) * 100
        if (lucro_proj >= 3.00) {
          pedido <- list(
            estrategia = "PLANO_GRAVIDADE_ZERO",
            origem = "BTC", destino = "SOL",
            valor_brl = VALOR_SPILL_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      }
    }
    
    # --- MOTOR 6: PLANO CORISCO DA SOLANA (BRL -> SOL 15m | R$ 50) ---
    if (is.null(pedido) && !is.null(p_sol_brl) && ste_atual >= 0.0 && pc1_atual < 0.70 && w_energy < 50.0) {
      z_sol_15m <- (p_sol_brl - stats_sol_15m$media) / stats_sol_15m$sd
      if (z_sol_15m <= -2.00) {
        lucro_proj <- ((stats_sol_15m$media / p_sol_brl) - 1) * 100
        if (lucro_proj >= 0.90) {
          pedido <- list(
            estrategia = "PLANO_CORISCO_DA_SOLANA",
            origem = "BRL", destino = "SOL",
            valor_brl = VALOR_CORISCO_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      }
    }
    
    # --- MOTOR 7: PLANO DUELO DE TITÃS (BTC <-> ETH 24h | R$ 60) ---
    if (is.null(pedido) && !is.null(p_eth_brl) && !is.null(p_btc_brl) && pc1_atual < 0.75) {
      ratio_eth_btc_now <- p_eth_brl / p_btc_brl
      z_eth_btc_24h     <- (ratio_eth_btc_now - stats_eth_btc$media) / stats_eth_btc$sd
      if (z_eth_btc_24h <= -1.50) {
        lucro_proj <- ((stats_eth_btc$media / ratio_eth_btc_now) - 1) * 100
        if (lucro_proj >= 1.00) {
          pedido <- list(
            estrategia = "PLANO_DUELO_DE_TITAS",
            origem = "BTC", destino = "ETH",
            valor_brl = VALOR_TITAS_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      } else if (z_eth_btc_24h >= 1.50) {
        lucro_proj <- ((ratio_eth_btc_now / stats_eth_btc$media) - 1) * 100
        if (lucro_proj >= 1.00) {
          pedido <- list(
            estrategia = "PLANO_DUELO_DE_TITAS",
            origem = "ETH", destino = "BTC",
            valor_brl = VALOR_TITAS_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
          )
        }
      }
    }
    
    # --- MOTOR 8: PLANO FLECHA DE SAGARANA (BRL -> BTC 5m | R$ 75) ---
    if (is.null(pedido) && ret_btc_5m <= -0.0040 && w_energy < 50.0) {
      lucro_proj <- 0.85
      pedido <- list(
        estrategia = "PLANO_FLECHA_DE_SAGARANA",
        origem = "BRL", destino = "BTC",
        valor_brl = VALOR_SAGARANA_BRL * fator_lote, lucro_esperado_pct = lucro_proj, timestamp = Sys.time()
      )
    }
    
    # 2. Envio da Solicitação ao Gatekeeper
    if (!is.null(pedido)) {
      saveRDS(pedido, "solicitacao.rds")
      cat(sprintf("📨 [LABTRADER] Solicitação [%s | %s -> %s | R$ %.2f] enviada ao LabPolice.\n",
                  pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl))
      Sys.sleep(15)
    }
    
    Sys.sleep(DELAY_LOOP)
    
  }, error = function(e) {
    cat("❌ [LABTRADER ERROR]:", conditionMessage(e), "\n")
    Sys.sleep(10)
  })
}
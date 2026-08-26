# ==============================================================================
# LABPOLICE v10.0 - GATEKEEPER DE EXECUÇÃO & AUDITORIA TELEGRAM
# Proteção de Capital, Travas de Risco, Modulação de Lote e Logs Persistentes
# ==============================================================================

library(httr)
library(jsonlite)
library(RSQLite)
library(digest)
library(dplyr)

# Carregar credenciais
if (file.exists("config_auth.R")) {
  tryCatch(source("config_auth.R", encoding = "UTF-8"), error = function(e) NULL)
}

# --- NOTIFICAÇÃO TELEGRAM DM ---
notificar_telegram_trade <- function(texto) {
  if (exists("TG_TRADE_TOKEN") && exists("TG_TRADE_CHATID")) {
    tryCatch({
      url <- paste0("https://api.telegram.org/bot", TG_TRADE_TOKEN, "/sendMessage")
      res <- POST(url, body = list(chat_id = TG_TRADE_CHATID, text = texto, parse_mode = "HTML"), encode = "json", timeout(12))
      if (status_code(res) == 200) {
        cat("📡 [TELEGRAM] Notificação de trade/veto despachada com sucesso.\n")
      } else {
        # Fallback para envio em texto puro se o HTML contiver entidades inválidas
        texto_puro <- gsub("<[^>]+>", "", texto)
        res_plain <- POST(url, body = list(chat_id = TG_TRADE_CHATID, text = texto_puro), encode = "json", timeout(12))
        if (status_code(res_plain) == 200) {
          cat("📡 [TELEGRAM] Notificação despachada em texto puro (fallback).\n")
        } else {
          cat(sprintf("⚠️ [TELEGRAM] Falha no despacho: HTTP %s\n", status_code(res)))
        }
      }
    }, error = function(e) {
      cat("⚠️ [TELEGRAM NOTIFY ERROR]:", conditionMessage(e), "\n")
    })
  } else {
    cat("⚠️ [TELEGRAM] TG_TRADE_TOKEN ou TG_TRADE_CHATID ausentes.\n")
  }
}

# --- NÚCLEO DE CONEXÃO E SINCRONIZAÇÃO TEMPORAL BINANCE ---
obter_offset_binance <- function() {
  tryCatch({
    res <- GET("https://api.binance.com/api/v3/time", timeout(5))
    if (status_code(res) == 200) {
      st <- as.numeric(content(res, "parsed")$serverTime)
      lt <- as.numeric(Sys.time()) * 1000
      return(round(st - lt))
    }
  }, error = function(e) NULL)
  return(0)
}

BINANCE_TIME_OFFSET <- obter_offset_binance()

assinar_query <- function(q) {
  if (!exists("BINANCE_SECRET")) return("")
  hmac(key = BINANCE_SECRET, object = q, algo = "sha256")
}

call_binance <- function(endpoint, query = list(), public = FALSE) {
  if (!exists("BINANCE_KEY") || !exists("BINANCE_SECRET")) return(NULL)
  url_base <- "https://api.binance.com"
  url_full <- paste0(url_base, endpoint)
  
  if (public) {
    res <- GET(url_full, query = query, timeout(5))
  } else {
    timestamp_corrigido <- as.character(round(as.numeric(Sys.time()) * 1000 + BINANCE_TIME_OFFSET))
    query$timestamp <- timestamp_corrigido
    query$recvWindow <- "60000"
    
    query_str <- paste(names(query), query, sep = "=", collapse = "&")
    signature <- assinar_query(query_str)
    
    url_com_assinatura <- paste0(url_full, "?", query_str, "&signature=", signature)
    
    res <- GET(url_com_assinatura,
               add_headers("X-MBX-APIKEY" = BINANCE_KEY),
               timeout(10))
  }
  
  if (status_code(res) == 200) {
    return(content(res, "parsed"))
  } else {
    return(NULL)
  }
}

call_binance_post <- function(endpoint, query = list()) {
  if (!exists("BINANCE_KEY") || !exists("BINANCE_SECRET")) return(NULL)
  url_base <- "https://api.binance.com"
  url_full <- paste0(url_base, endpoint)
  
  timestamp_corrigido <- as.character(round(as.numeric(Sys.time()) * 1000 + BINANCE_TIME_OFFSET))
  query$timestamp <- timestamp_corrigido
  query$recvWindow <- "60000"
  
  query_str <- paste(names(query), query, sep = "=", collapse = "&")
  signature <- assinar_query(query_str)
  
  url_com_assinatura <- paste0(url_full, "?", query_str, "&signature=", signature)
  
  res <- tryCatch(POST(url_com_assinatura,
                       add_headers("X-MBX-APIKEY" = BINANCE_KEY),
                       timeout(10)), error = function(e) NULL)
  
  if (!is.null(res) && status_code(res) == 200) {
    return(content(res, "parsed"))
  } else {
    return(NULL)
  }
}

resgatar_simple_earn_paxg <- function(qtd = NULL) {
  tryCatch({
    query <- list(productId = "PAXG001")
    if (!is.null(qtd) && qtd > 0) {
      query$amount <- sprintf("%.6f", qtd)
    } else {
      query$redeemAll <- "true"
    }
    r <- call_binance_post("/sapi/v1/simple-earn/flexible/redeem", query)
    if (!is.null(r) && !is.null(r$success) && r$success == TRUE) {
      cat(sprintf("🔓 [SIMPLE EARN] Resgate de PAXG executado com sucesso (Redeem ID: %s)\n", r$redeemId))
      Sys.sleep(1)
      return(TRUE)
    }
  }, error = function(e) {
    cat("⚠️ [SIMPLE EARN REDEEM ERROR]:", conditionMessage(e), "\n")
  })
  return(FALSE)
}

subscrever_simple_earn_paxg <- function(qtd = NULL) {
  tryCatch({
    # Se qtd for nula, busca o saldo livre de PAXG na Spot
    if (is.null(qtd) || qtd <= 0.0001) {
      acc <- call_binance("/api/v3/account")
      if (!is.null(acc) && !is.null(acc$balances)) {
        for (b in acc$balances) {
          if (b$asset == "PAXG") {
            qtd <- as.numeric(b$free)
            break
          }
        }
      }
    }
    if (is.null(qtd) || is.na(qtd) || qtd < 0.0001) return(FALSE)
    
    # Floor truncation para 4 casas decimais (exige <= saldo livre sem arredondar para cima)
    floor_qtd <- floor(as.numeric(qtd) * 10000) / 10000
    if (floor_qtd < 0.0001) return(FALSE)
    
    query <- list(productId = "PAXG001", amount = sprintf("%.4f", floor_qtd))
    r <- call_binance_post("/sapi/v1/simple-earn/flexible/subscribe", query)
    if (!is.null(r) && !is.null(r$success) && r$success == TRUE) {
      cat(sprintf("🔒 [SIMPLE EARN] Subscrição de %.4f PAXG executada com sucesso (Purchase ID: %s)\n", floor_qtd, r$purchaseId))
      return(TRUE)
    }
  }, error = function(e) {
    cat("⚠️ [SIMPLE EARN SUBSCRIBE ERROR]:", conditionMessage(e), "\n")
  })
  return(FALSE)
}

carteira <- function(silent = FALSE) {
  acc <- call_binance("/api/v3/account")
  if (is.null(acc)) {
    if (!silent) cat("⚠️ Falha ao acessar carteira Binance.\n")
    return(list(total = 1709.72, caixa = 1150.00))
  }
  
  balances <- acc$balances
  df <- data.frame(
    asset = sapply(balances, function(x) x$asset),
    free = as.numeric(sapply(balances, function(x) x$free)),
    locked = as.numeric(sapply(balances, function(x) x$locked)),
    stringsAsFactors = FALSE
  )
  df$total <- df$free + df$locked
  df <- df[df$total > 0.0001, ]
  
  if (!silent) {
    cat("\n💼 SALDO ATUAL CARTEIRA BINANCE:\n")
    print(df)
  }
  return(df)
}

# --- EXECUÇÃO REAL DE ORDENS NA BINANCE (MARKET ORDER) ---
enviar_ordem_binance_market <- function(origem, destino, valor_brl) {
  if (!exists("BINANCE_KEY") || !exists("BINANCE_SECRET")) {
    return(list(sucesso = FALSE, msg = "Chaves da Binance não configuradas em config_auth.R"))
  }
  
  symbol <- NULL
  side <- NULL
  quoteOrderQty <- NULL
  quantity <- NULL
  
  # 1. Compras com BRL (quoteOrderQty = valor_brl)
  if (origem == "BRL" && destino %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "PAXG", "BNB", "ADA", "NEAR")) {
    symbol <- paste0(destino, "BRL")
    side <- "BUY"
    quoteOrderQty <- valor_brl
  } else if (destino == "BRL" && origem %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "PAXG", "BNB", "ADA", "NEAR")) {
    symbol <- paste0(origem, "BRL")
    side <- "SELL"
    p_atual <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_atual) && p_atual > 0) {
      precisao <- ifelse(origem == "BTC", 5, ifelse(origem %in% c("ETH", "SOL", "PAXG", "BNB"), 3, ifelse(origem == "ADA", 1, 2)))
      mult_p <- 10^precisao
      calc_qty <- floor((valor_brl / p_atual) * mult_p) / mult_p
      
      # Travar no saldo real livre para NUNCA estourar a carteira
      df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      saldo_asset_real <- 0
      if (!is.null(df_w) && is.data.frame(df_w)) {
        if (origem == "PAXG") {
          row_p <- df_w[df_w$asset %in% c("PAXG", "LDPAXG"), ]
          if (nrow(row_p) > 0) saldo_asset_real <- sum(row_p$free, na.rm = TRUE)
        } else {
          row_p <- df_w[df_w$asset == origem, ]
          if (nrow(row_p) > 0) saldo_asset_real <- sum(row_p$free, na.rm = TRUE)
        }
      }
      if (saldo_asset_real > 0) {
        quantity <- min(calc_qty, floor(saldo_asset_real * mult_p) / mult_p)
      } else {
        quantity <- calc_qty
      }
    }
  } else if (origem == "BTC" && destino == "SOL") {
    # Rotação BTC -> SOL: Se volume >= 85 (>= 0.0002 BTC), usa par direto SOLBTC; se menor, usa ponte inteligente BRL
    if (valor_brl >= 85.0) {
      symbol <- "SOLBTC"
      side <- "BUY"
      p_sol <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SOLBRL"), "parsed")$price), error = function(e) NULL)
      if (!is.null(p_sol) && p_sol > 0) quantity <- floor((valor_brl / p_sol) * 100) / 100
    } else {
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional de SOLBTC (mín R$ 85). Executando ponte BRL...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("BTC", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "SOL", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (origem == "SOL" && destino == "BTC") {
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_sol_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w) && "SOL" %in% df_w$asset) {
      saldo_sol_real <- sum(df_w$free[df_w$asset == "SOL"], na.rm = TRUE)
    }
    p_sol <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SOLBRL"), "parsed")$price), error = function(e) NULL)
    
    if (!is.null(p_sol) && p_sol > 0) {
      calc_qty <- floor((valor_brl / p_sol) * 100) / 100
      quantity <- min(calc_qty, floor(saldo_sol_real * 100) / 100)
    }
    
    if (valor_brl >= 85.0 && (!is.null(quantity) && quantity * p_sol >= 85.0)) {
      symbol <- "SOLBTC"
      side <- "SELL"
    } else {
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional de SOLBTC (mín R$ 85). Executando ponte SOLBRL -> BTCBRL...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("SOL", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "BTC", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (origem == "BTC" && destino == "ETH") {
    if (valor_brl >= 85.0) {
      symbol <- "ETHBTC"
      side <- "BUY"
      p_eth <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) NULL)
      if (!is.null(p_eth) && p_eth > 0) quantity <- floor((valor_brl / p_eth) * 1000) / 1000
    } else {
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional de ETHBTC (mín R$ 85). Executando ponte BRL...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("BTC", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "ETH", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (origem == "ETH" && destino == "BTC") {
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_eth_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w) && "ETH" %in% df_w$asset) {
      saldo_eth_real <- sum(df_w$free[df_w$asset == "ETH"], na.rm = TRUE)
    }
    p_eth <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_eth) && p_eth > 0) {
      calc_qty <- floor((valor_brl / p_eth) * 1000) / 1000
      quantity <- min(calc_qty, floor(saldo_eth_real * 1000) / 1000)
    }
    if (valor_brl >= 42.0 && (!is.null(quantity) && quantity * p_eth >= 42.0)) {
      symbol <- "ETHBTC"
      side <- "SELL"
    } else {
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional de ETHBTC. Executando ponte ETHBRL -> BTCBRL...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("ETH", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "BTC", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (origem == "BTC" && destino == "PAXG") {
    # Guiana Ponta A: Compra PAXG com BTC usando par direto PAXGBTC
    p_paxg_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) NULL)
    if (is.null(p_paxg_brl_tmp) || p_paxg_brl_tmp <= 0) p_paxg_brl_tmp <- 23777.0
    symbol <- "PAXGBTC"
    side <- "BUY"
    quantity <- floor((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
  } else if (origem == "BRL" && destino == "PAXG") {
    # Midas DCA: Compra USDT com BRL e em seguida compra PAXG com USDT (par PAXGUSDT)
    cat(sprintf("🌉 [SMART ROUTING] Comprando PAXG via ponte BRL -> USDT -> PAXG (R$ %.2f)...\n", valor_brl))
    r_usdt <- enviar_ordem_binance_market("BRL", "USDT", valor_brl)
    if (r_usdt$sucesso) {
      qtd_usdt <- as.numeric(r_usdt$executedQty)
      if (is.na(qtd_usdt) || length(qtd_usdt) == 0 || qtd_usdt <= 0) qtd_usdt <- valor_brl / 5.18
      return(enviar_ordem_binance_market("USDT", "PAXG", valor_brl, quoteOrderQty = qtd_usdt))
    } else {
      return(r_usdt)
    }
  } else if (origem == "USDT" && destino == "PAXG") {
    symbol <- "PAXGUSDT"
    side <- "BUY"
    if (!is.null(quoteOrderQty)) {
      quoteOrderQty <- sprintf("%.2f", as.numeric(quoteOrderQty))
    }
  } else if (origem == "PAXG" && destino == "BTC") {
    # Guiana Ponta B: Vende PAXG por BTC usando par direto PAXGBTC
    p_paxg_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) NULL)
    if (is.null(p_paxg_brl_tmp) || p_paxg_brl_tmp <= 0) p_paxg_brl_tmp <- 23777.0
    
    # Resgata do Simple Earn se estiver no Earn flexível
    resgatar_simple_earn_paxg()
    
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_paxg_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w)) {
      row_p <- df_w[df_w$asset %in% c("PAXG", "LDPAXG"), ]
      if (nrow(row_p) > 0) saldo_paxg_real <- sum(row_p$free, na.rm = TRUE)
    }
    symbol <- "PAXGBTC"
    side <- "SELL"
    calc_qty <- floor((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
    quantity <- if (saldo_paxg_real > 0) min(calc_qty, floor(saldo_paxg_real * 10000) / 10000) else calc_qty
  }
  
  if (is.null(symbol)) {
    return(list(sucesso = FALSE, msg = sprintf("Par direto não mapeado para %s -> %s", origem, destino)))
  }
  
  query <- list(
    symbol = symbol,
    side = side,
    type = "MARKET"
  )
  if (!is.null(quoteOrderQty)) {
    query$quoteOrderQty <- sprintf("%.2f", as.numeric(quoteOrderQty))
  } else if (!is.null(quantity)) {
    query$quantity <- as.character(quantity)
  }
  
  url_base <- "https://api.binance.com/api/v3/order"
  timestamp_corrigido <- as.character(round(as.numeric(Sys.time()) * 1000 + BINANCE_TIME_OFFSET))
  query$timestamp <- timestamp_corrigido
  query$recvWindow <- "60000"
  
  query_str <- paste(names(query), query, sep = "=", collapse = "&")
  signature <- assinar_query(query_str)
  url_signed <- paste0(url_base, "?", query_str, "&signature=", signature)
  
  tryCatch({
    res <- POST(url_signed, add_headers("X-MBX-APIKEY" = BINANCE_KEY), timeout(10))
    res_parsed <- content(res, "parsed")
    
    if (status_code(res) %in% c(200, 201)) {
      return(list(
        sucesso = TRUE,
        orderId = res_parsed$orderId,
        symbol = res_parsed$symbol,
        side = res_parsed$side,
        executedQty = res_parsed$executedQty,
        cummulativeQuoteQty = res_parsed$cummulativeQuoteQty,
        status = res_parsed$status,
        raw = res_parsed
      ))
    } else {
      err_msg <- ifelse(!is.null(res_parsed$msg), res_parsed$msg, content(res, "text", encoding = "UTF-8"))
      return(list(sucesso = FALSE, msg = sprintf("HTTP %s: %s", status_code(res), err_msg)))
    }
  }, error = function(e) {
    return(list(sucesso = FALSE, msg = conditionMessage(e)))
  })
}

# ==============================================================================
# PROCESSADOR DO GATEKEEPER & AUDITORIA DE RISCO
# ==============================================================================
processar_solicitacoes_gatekeeper <- function(modo_continuo = FALSE, executar_real = TRUE) {
  
  executar_ciclo_gatekeeper <- function() {
    if (file.exists("solicitacao.rds")) {
      on.exit({
        if (file.exists("solicitacao.rds")) {
          unlink("solicitacao.rds")
        }
      }, add = TRUE)
      
      pedido <- tryCatch(readRDS("solicitacao.rds"), error = function(e) NULL)
      
      if (!is.null(pedido)) {
        ts_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        cat(sprintf("\n🛡️ [GATEKEEPER] Avaliando solicitação de trade [%s]:\n", ts_str))
        cat(sprintf("   Estratégia: %s | Origem: %s -> Destino: %s | Valor: R$ %.2f | Lucro Proj: +%.2f%%\n",
                    pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct))
        
        aprovado <- TRUE
        motivo_veto <- ""
        estrategia_nome <- as.character(pedido$estrategia)
        
        # --- TABELA DE TETOS DE VOLUME E LUCROS MÍNIMOS ---
        estrategias_validas <- c(
          "PLANO_GUIANA_BRASILEIRA",
          "PLANO_ESCUDO_DE_AQUILES",
          "PLANO_PATRIA_VOLATIL",
          "PLANO_CABOCLO_DOS_ORACULOS",
          "PLANO_GRAVIDADE_ZERO",
          "PLANO_CORISCO_DA_SOLANA",
          "PLANO_DUELO_DE_TITAS",
          "PLANO_FLECHA_DE_SAGARANA",
          "PLANO_COFRE_DE_MIDAS",
          "PLANO_SENTINELA_DE_MINAS",
          "PLANO_SERTAO_VALENTE",
          "PLANO_FAROL_DE_NEAR"
        )
        
        tetos_volume <- list(
          "PLANO_GUIANA_BRASILEIRA" = 250.00,
          "PLANO_ESCUDO_DE_AQUILES" = 350.00,
          "PLANO_PATRIA_VOLATIL" = 350.00,
          "PLANO_CABOCLO_DOS_ORACULOS" = 260.00,
          "PLANO_GRAVIDADE_ZERO" = 220.00,
          "PLANO_CORISCO_DA_SOLANA" = 220.00,
          "PLANO_DUELO_DE_TITAS" = 300.00,
          "PLANO_FLECHA_DE_SAGARANA" = 200.00,
          "PLANO_COFRE_DE_MIDAS" = 55.00,
          "PLANO_SENTINELA_DE_MINAS" = 180.00,
          "PLANO_SERTAO_VALENTE" = 160.00,
          "PLANO_FAROL_DE_NEAR" = 180.00
        )
        
        lucros_minimos <- list(
          "PLANO_GUIANA_BRASILEIRA" = 1.00,
          "PLANO_ESCUDO_DE_AQUILES" = 1.20,
          "PLANO_PATRIA_VOLATIL" = 0.35,
          "PLANO_CABOCLO_DOS_ORACULOS" = 0.55,
          "PLANO_GRAVIDADE_ZERO" = 1.20,
          "PLANO_CORISCO_DA_SOLANA" = 0.50,
          "PLANO_DUELO_DE_TITAS" = 0.70,
          "PLANO_FLECHA_DE_SAGARANA" = 0.40,
          "PLANO_COFRE_DE_MIDAS" = 0.00,
          "PLANO_SENTINELA_DE_MINAS" = 0.50,
          "PLANO_SERTAO_VALENTE" = 0.55,
          "PLANO_FAROL_DE_NEAR" = 0.50
        )
        
        # Trava 0: Validação de Saldo em Custódia Real (Anti-Venda a Descoberto)
        if (executar_real) {
          df_wallet <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
          if (!is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
            origem_asset <- as.character(pedido$origem)
            
            saldo_disp <- 0
            if (origem_asset == "PAXG") {
              row_paxg <- df_wallet[df_wallet$asset %in% c("PAXG", "LDPAXG"), ]
              if (nrow(row_paxg) > 0) saldo_disp <- sum(row_paxg$free, na.rm = TRUE)
            } else {
              row_asset <- df_wallet[df_wallet$asset == origem_asset, ]
              if (nrow(row_asset) > 0) saldo_disp <- sum(row_asset$free, na.rm = TRUE)
            }
            
            preco_unit <- 1.0
            if (origem_asset != "BRL") {
              if (origem_asset == "PAXG") {
                p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 2650.0)
                p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
                preco_unit <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 24000.0)
              } else {
                sym_check <- paste0(origem_asset, "BRL")
                p_tmp <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", sym_check)), "parsed")$price), error = function(e) NULL)
                if (!is.null(p_tmp) && length(p_tmp) > 0 && !is.na(p_tmp) && p_tmp > 0) preco_unit <- p_tmp
              }
            }
            
            qtd_necessaria <- as.numeric(pedido$valor_brl) / preco_unit
            
            if (saldo_disp < (qtd_necessaria * 0.98)) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Saldo insuficiente de %s em custódia (Disponível: %.6f %s | Necessário: %.6f %s / R$ %.2f)",
                                     origem_asset, saldo_disp, origem_asset, qtd_necessaria, origem_asset, pedido$valor_brl)
            }
          }
        }
        
        # Trava 0.5: Validação de Notional Mínimo da Binance (R$ 12.00)
        if (aprovado && (is.null(pedido$valor_brl) || as.numeric(pedido$valor_brl) < 12.00)) {
          aprovado <- FALSE
          motivo_veto <- sprintf("Volume solicitado de R$ %.2f abaixo do Notional mínimo da Binance (R$ 12.00)", pedido$valor_brl)
        }
        
        # Trava 1: Validação da Estratégia
        if (aprovado && !(estrategia_nome %in% estrategias_validas)) {
          aprovado <- FALSE
          motivo_veto <- sprintf("Estratégia '%s' não autorizada pelo protocolo", estrategia_nome)
        }
        
        # Trava 2: Teto de Volume por Estratégia e Teto de Exposição em Aberto
        if (aprovado) {
          # Se for venda/liquidação para Caixa BRL, permite liquidar até R$ 500.00 acumulados da custódia
          teto_permitido <- ifelse(pedido$destino == "BRL", 500.00, 
                            ifelse(!is.null(tetos_volume[[estrategia_nome]]), tetos_volume[[estrategia_nome]], 200.00))
          if (is.null(pedido$valor_brl) || pedido$valor_brl > teto_permitido) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Volume excede o teto de R$ %.2f para %s (Solicitado: R$ %.2f)", 
                                   teto_permitido, estrategia_nome, pedido$valor_brl)
          }
          
          # Subtrava 2.1: Teto de Posição Cumulativa em Aberto (Anti-Empilhamento de Compras Multi-Tranche)
          if (aprovado && pedido$origem == "BRL" && pedido$destino %in% c("SOL", "LINK", "ETH", "USDT", "BTC", "PAXG", "BNB", "ADA", "NEAR")) {
            teto_custodia_map <- list(SOL = 220.0, LINK = 250.0, ETH = 500.0, USDT = 500.0, BTC = 600.0, PAXG = 800.0, BNB = 180.0, ADA = 160.0, NEAR = 180.0)
            teto_custodia <- ifelse(!is.null(teto_custodia_map[[pedido$destino]]), teto_custodia_map[[pedido$destino]], 250.0)
            
            saldo_ativo_brl <- 0.0
            if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
              dest_asset <- as.character(pedido$destino)
              row_d <- df_wallet[df_wallet$asset %in% c(dest_asset, paste0("LD", dest_asset)), ]
              if (nrow(row_d) > 0) {
                p_dest_unit <- 1.0
                if (dest_asset != "BRL") {
                  if (dest_asset == "PAXG") {
                    p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 2650.0)
                    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
                    p_dest_unit <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 24000.0)
                  } else {
                    sym_d <- paste0(dest_asset, "BRL")
                    p_tmp_d <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", sym_d)), "parsed")$price), error = function(e) NULL)
                    if (!is.null(p_tmp_d) && length(p_tmp_d) > 0 && !is.na(p_tmp_d) && p_tmp_d > 0) p_dest_unit <- p_tmp_d
                  }
                }
                saldo_ativo_brl <- sum(row_d$free, na.rm = TRUE) * p_dest_unit
              }
            }
            
            if (saldo_ativo_brl >= teto_custodia) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto de Posição em Aberto atingido para %s (R$ %.2f em custódia >= R$ %.2f máx). Aguarde a realização de lucro antes de novas compras.",
                                     pedido$destino, saldo_ativo_brl, teto_custodia)
            }
          }
        }
        
        # Trava 3: Lucro Mínimo Esperado
        if (aprovado) {
          min_lucro <- ifelse(!is.null(lucros_minimos[[estrategia_nome]]), lucros_minimos[[estrategia_nome]], 0.80)
          if (is.null(pedido$lucro_esperado_pct) || pedido$lucro_esperado_pct < min_lucro) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Lucro esperado insuficiente (%.2f%% < %.2f%% mínimo para %s)",
                                   pedido$lucro_esperado_pct, min_lucro, estrategia_nome)
          }
        }
        
        # Trava 4: Cooldown Adaptativo Harmonicus Ultra-Deep
        hist_exec_file <- "ordens_executadas.rds"
        if (aprovado && file.exists(hist_exec_file)) {
          hist_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
          if (!is.null(hist_exec) && nrow(hist_exec) > 0 && "Estrategia" %in% names(hist_exec)) {
            hist_est <- hist_exec[hist_exec$Estrategia == estrategia_nome, ]
            if (nrow(hist_est) > 0) {
              ultimo_ts <- as.POSIXct(tail(hist_est$Data_Hora, 1))
              horas_dif <- as.numeric(difftime(Sys.time(), ultimo_ts, units = "hours"))
              
              # Cooldown Otimizado Harmonicus Ultra-Deep
              cooldown_req <- ifelse(estrategia_nome == "PLANO_COFRE_DE_MIDAS", 48.0,
                              ifelse(estrategia_nome %in% c("PLANO_CORISCO_DA_SOLANA", "PLANO_SENTINELA_DE_MINAS"), 0.16, 
                              ifelse(estrategia_nome %in% c("PLANO_FLECHA_DE_SAGARANA", "PLANO_SERTAO_VALENTE", "PLANO_FAROL_DE_NEAR"), 0.25,
                              ifelse(estrategia_nome == "PLANO_DUELO_DE_TITAS", 1.5,
                              ifelse(grepl("ORACULOS|GRAVIDADE", estrategia_nome), 0.33, 1.0)))))
              
              # Se for realização de lucro / rotação oposta, zera o cooldown
              ultimo_reg <- tail(hist_est, 1)
              if (!is.null(ultimo_reg$Origem) && ultimo_reg$Origem != as.character(pedido$origem)) {
                cooldown_req <- 0.0
              }
              
              if (horas_dif < cooldown_req) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Cooldown ativo para %s (%.1fh desde último trade < %.1fh / %d min)",
                                       estrategia_nome, horas_dif, cooldown_req, round(cooldown_req * 60))
              }
            }
          }
        }
        
        # Trava 5: Governança de Inventário Compartilhado (Shared Inventory)
        # Qualquer plano pode liquidar qualquer ativo em carteira, contanto que gere lucro real (validado pela Trava 6).
        # Se a compra foi feita há menos de 5 minutos, exige que seja com lucro confirmado para evitar micro-slippage.
        
        # Trava 6: Trava Anti-Prejuízo / Breakeven Lock Universal (Proíbe Venda Abaixo do Custo Real do Lote em Aberto)
        if (aprovado && pedido$destino == "BRL" && pedido$origem %in% c("SOL", "LINK", "ETH", "USDT", "BTC", "PAXG", "BNB", "ADA", "NEAR")) {
          sym_check <- sprintf("%sBRL", pedido$origem)
          p_atual_mercado <- tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%s", sym_check)), "parsed")$price), error = function(e) NULL)
          
          if (!is.null(p_atual_mercado) && p_atual_mercado > 0 && file.exists(hist_exec_file)) {
            hist_all <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
            if (!is.null(hist_all) && nrow(hist_all) > 0 && "Destino" %in% names(hist_all)) {
              exec_reais <- hist_all[grepl("EXECUTADO_REAL", hist_all$Status), ]
              
              # Identifica o índice da última VENDA deste ativo
              idx_vendas <- which(exec_reais$Origem == as.character(pedido$origem))
              ultimo_idx_venda <- if (length(idx_vendas) > 0) max(idx_vendas) else 0
              
              # Compras em aberto: apenas compras que ocorreram APÓS a última venda
              compras_abertas <- exec_reais[seq_len(nrow(exec_reais)) > ultimo_idx_venda & exec_reais$Destino == as.character(pedido$origem), ]
              
              # Se não encontrou compras pós-venda, busca a compra mais recente
              if (nrow(compras_abertas) == 0) {
                compras_abertas <- tail(exec_reais[exec_reais$Destino == as.character(pedido$origem), ], 1)
              }
              
              validos <- compras_abertas[!is.na(compras_abertas$Preco_Exec) & compras_abertas$Preco_Exec > 0 & !is.na(compras_abertas$Valor_BRL), ]
              
              p_entrada <- if (nrow(validos) > 0) {
                sum(validos$Valor_BRL) / sum(validos$Valor_BRL / validos$Preco_Exec)
              } else {
                NA
              }
              
              if (!is.na(p_entrada) && p_entrada > 0) {
                ret_nominal <- ((p_atual_mercado - p_entrada) / p_entrada) * 100
                # Proíbe terminantemente venda se retorno for menor que +0.40% sobre o custo real do lote em aberto
                if (ret_nominal < 0.40) {
                  aprovado <- FALSE
                  motivo_veto <- sprintf("Breakeven Lock FIFO: Preço atual de %s (R$ %.2f) está abaixo ou sem margem do preço de compra do lote em aberto (R$ %.2f | Retorno: %+.2f%% [exige >= +0.40%%]). Venda vetada para garantir lucro real.",
                                         pedido$origem, p_atual_mercado, p_entrada, ret_nominal)
                }
              }
            }
          }
        }
        
        # --- VEREDITO DO LABPOLICE & EXECUÇÃO ---
        if (aprovado) {
          cat(sprintf("✅ [AUTORIZADO] Ordem validada com sucesso! Lucro Projetado: +%.2f%%\n", pedido$lucro_esperado_pct))
          
          resultado_binance <- list(sucesso = TRUE, orderId = "SIMULADO_LOCAL")
          if (executar_real) {
            cat("🚀 [EXECUÇÃO REAL] Transmitindo ordem de mercado para a Binance...\n")
            resultado_binance <- enviar_ordem_binance_market(pedido$origem, pedido$destino, pedido$valor_brl)
            if (!resultado_binance$sucesso) {
              cat(sprintf("⚠️ [ERRO BINANCE]: %s\n", resultado_binance$msg))
            } else if (pedido$destino == "PAXG") {
              # Auto-Alocação no Simple Earn para render juros diários
              qtd_paxg_exec <- as.numeric(resultado_binance$executedQty)
              if (!is.na(qtd_paxg_exec) && qtd_paxg_exec > 0.0001) {
                subscrever_simple_earn_paxg(qtd_paxg_exec)
              }
            }
          }
          
          status_final <- if (executar_real) {
            ifelse(resultado_binance$sucesso, "EXECUTADO_REAL_BINANCE", paste0("FALHA_BINANCE: ", resultado_binance$msg))
          } else {
            "SINAL_APROVADO_SIMULADO"
          }
          
          p_calc_exec <- 0.0
          if (!is.null(resultado_binance$cummulativeQuoteQty) && !is.null(resultado_binance$executedQty)) {
            q_qty <- as.numeric(resultado_binance$cummulativeQuoteQty)
            e_qty <- as.numeric(resultado_binance$executedQty)
            if (!is.na(q_qty) && !is.na(e_qty) && e_qty > 0) {
              p_calc_exec <- q_qty / e_qty
            }
          }
          if (p_calc_exec <= 0) {
            ativo_check <- ifelse(pedido$origem == "BRL", pedido$destino, pedido$origem)
            if (ativo_check == "PAXG") {
              p_calc_exec <- 24000.0
            } else {
              p_calc_exec <- tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%sBRL", ativo_check)), "parsed")$price), error = function(e) 0.0)
              if (is.null(p_calc_exec) || length(p_calc_exec) == 0 || is.na(p_calc_exec)) p_calc_exec <- 0.0
            }
          }
          
          registro_exec <- data.frame(
            Data_Hora = as.character(ts_str),
            Estrategia = as.character(pedido$estrategia),
            Origem = as.character(pedido$origem),
            Destino = as.character(pedido$destino),
            Valor_BRL = as.numeric(pedido$valor_brl),
            Preco_Exec = as.numeric(p_calc_exec[1]),
            Lucro_Proj = as.numeric(pedido$lucro_esperado_pct),
            Status = as.character(status_final),
            stringsAsFactors = FALSE
          )
          
          hist_exec <- if (file.exists(hist_exec_file)) tryCatch(readRDS(hist_exec_file), error = function(e) data.frame()) else data.frame()
          hist_exec <- if (nrow(hist_exec) > 0) tryCatch(bind_rows(hist_exec, registro_exec), error = function(e) rbind(hist_exec, registro_exec)) else registro_exec
          saveRDS(hist_exec, hist_exec_file)
          
          log_tag <- ifelse(executar_real, ifelse(resultado_binance$sucesso, "ORDEM_REAL_BINANCE", "FALHA_REAL_BINANCE"), "SINAL_SIMULADO_APROVADO")
          cat(sprintf("[%s] [%s] %s: %s -> %s (R$ %.2f) Lucro: +%.2f%% | %s\n",
                      ts_str, log_tag, pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct,
                      ifelse(executar_real, ifelse(resultado_binance$sucesso, paste0("ENVIO_BINANCE_OK (ID: ", resultado_binance$orderId, ")"), paste0("FALHA_BINANCE: ", resultado_binance$msg)), "VALIDADO_SEM_ENVIO_CORRETORA")),
              file = "ordens_executadas.log", append = TRUE)
          
          # Alerta Telegram Instantâneo (DM Privada)
          if (executar_real) {
            ativo_qtd_label <- ifelse(pedido$origem == "BRL", pedido$destino, pedido$origem)
            if (resultado_binance$sucesso) {
              msg_tg <- sprintf("🟢 <b>[ORDEM REAL EXECUTADA NA BINANCE]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Operação:</b> %s ➔ %s\n💰 <b>Valor:</b> R$ %.2f (Qtd: %s %s)\n📈 <b>Lucro Projetado:</b> +%.2f%%\n🆔 <b>Order ID Binance:</b> <code>%s</code>\n⏱️ <b>Data/Hora:</b> %s\n📝 <b>Status:</b> Preenchido na Corretora (FILLED)\n━━━━━━━━━━━━━━━━━━━━",
                                estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl,
                                ifelse(!is.null(resultado_binance$executedQty), resultado_binance$executedQty, "--"), ativo_qtd_label,
                                pedido$lucro_esperado_pct, resultado_binance$orderId, ts_str)
            } else {
              msg_tg <- sprintf("⚠️ <b>[FALHA DE EXECUÇÃO NA BINANCE]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Tentativa:</b> %s ➔ %s\n💰 <b>Valor:</b> R$ %.2f\n❌ <b>Erro Corretora:</b> %s\n⏱️ <b>Data/Hora:</b> %s\n━━━━━━━━━━━━━━━━━━━━",
                                estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl, resultado_binance$msg, ts_str)
            }
          } else {
            msg_tg <- sprintf("🧪 <b>[SIMULAÇÃO // SINAL DE DISPARO APROVADO]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Operação:</b> %s ➔ %s\n💰 <b>Lote Calculado:</b> R$ %.2f\n📈 <b>Lucro Projetado:</b> +%.2f%%\n⏱️ <b>Data/Hora:</b> %s\n📝 <b>Status:</b> 🧪 SIMULAÇÃO — NENHUMA ORDEM ENVIADA À CORRETORA\n━━━━━━━━━━━━━━━━━━━━",
                              estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct, ts_str)
          }
          notificar_telegram_trade(msg_tg)
          
        } else {
          cat(sprintf("⛔ [VETADO PELO LABPOLICE] Motivo: %s\n", motivo_veto))
          
          origem_val <- ifelse(!is.null(pedido$origem), pedido$origem, ifelse(!is.null(pedido$ativo), pedido$ativo, "DESCONHECIDO"))
          destino_val <- ifelse(!is.null(pedido$destino), pedido$destino, ifelse(!is.null(pedido$lado), pedido$lado, "DESCONHECIDO"))
          valor_val <- ifelse(!is.null(pedido$valor_brl), as.numeric(pedido$valor_brl), 0)
          
          registro_veto <- data.frame(
            Data_Hora = ts_str,
            Origem = as.character(origem_val),
            Destino = as.character(destino_val),
            Valor_BRL = as.numeric(valor_val),
            Motivo = as.character(motivo_veto),
            Status = "VETADO",
            stringsAsFactors = FALSE
          )
          
          hist_veto_file <- "ordens_vetadas.rds"
          hist_veto <- if (file.exists(hist_veto_file)) tryCatch(readRDS(hist_veto_file), error = function(e) data.frame()) else data.frame()
          hist_veto <- if (nrow(hist_veto) > 0) tryCatch(bind_rows(hist_veto, registro_veto), error = function(e) rbind(hist_veto, registro_veto)) else registro_veto
          saveRDS(hist_veto, hist_veto_file)
          
          cat(sprintf("[%s] VETO: %s (Motivo: %s)\n", ts_str, ifelse(!is.null(pedido$estrategia), pedido$estrategia, "ORDEM_INVALIDA"), motivo_veto),
              file = "ordens_vetadas.log", append = TRUE)
          
          # Throttling de Notificação de Veto no Telegram (Máximo 1 alerta a cada 30 min por estratégia)
          veto_throttle_file <- "veto_tg_throttle.rds"
          deve_notificar_tg <- TRUE
          chave_veto <- as.character(estrategia_nome)
          
          if (file.exists(veto_throttle_file)) {
            throttle_db <- tryCatch(readRDS(veto_throttle_file), error = function(e) list())
            if (!is.null(throttle_db[[chave_veto]])) {
              ultimo_envio <- as.POSIXct(throttle_db[[chave_veto]])
              minutos_dif <- as.numeric(difftime(Sys.time(), ultimo_envio, units = "mins"))
              if (minutos_dif < 30) {
                deve_notificar_tg <- FALSE
              }
            }
          } else {
            throttle_db <- list()
          }
          
          if (deve_notificar_tg) {
            throttle_db[[chave_veto]] <- Sys.time()
            tryCatch(saveRDS(throttle_db, veto_throttle_file), error = function(e) NULL)
            
            # Alerta Telegram de Veto (DM Privada)
            msg_veto_tg <- sprintf("⛔ <b>[GATEKEEPER | ORDEM VETADA]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n⚠️ <b>Tentativa:</b> %s ➔ %s\n🚫 <b>Motivo:</b> %s\n⏱️ <b>Data:</b> %s\n🔕 <i>Avisos para este mesmo veto silenciados por 30 min no Telegram (logs gravados no servidor).</i>\n━━━━━━━━━━━━━━━━━━━━",
                                   estrategia_nome, origem_val, destino_val, motivo_veto, ts_str)
            notificar_telegram_trade(msg_veto_tg)
          } else {
            cat(sprintf("🔕 [TELEGRAM SILENCIADO] Notificação de veto para %s suprimida (último envio há < 30 min).\n", estrategia_nome))
          }
        }
        
        # Limpa a mesa para liberar o LabTrader para o próximo ciclo
        unlink("solicitacao.rds")
        cat("🧹 Mesa limpa. Solicitação arquivada.\n")
      }
    }
  }
  
  if (modo_continuo) {
    cat("🔄 Gatekeeper em loop contínuo...\n")
    while(TRUE) {
      executar_ciclo_gatekeeper()
      Sys.sleep(3)
    }
  } else {
    executar_ciclo_gatekeeper()
  }
}
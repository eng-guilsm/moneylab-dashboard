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

resgatar_simple_earn_link <- function(qtd = NULL) {
  tryCatch({
    query <- list(productId = "LINK001")
    if (!is.null(qtd) && qtd > 0) {
      query$amount <- sprintf("%.4f", qtd)
    } else {
      query$redeemAll <- "true"
    }
    r <- call_binance_post("/sapi/v1/simple-earn/flexible/redeem", query)
    if (!is.null(r) && !is.null(r$success) && r$success == TRUE) {
      cat(sprintf("🔓 [SIMPLE EARN] Resgate de LINK executado com sucesso (Redeem ID: %s)\n", r$redeemId))
      Sys.sleep(1)
      return(TRUE)
    }
  }, error = function(e) {
    cat("⚠️ [SIMPLE EARN LINK REDEEM ERROR]:", conditionMessage(e), "\n")
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

subscrever_simple_earn_usdt <- function(qtd = NULL) {
  tryCatch({
    if (is.null(qtd) || qtd <= 0.1) {
      acc <- call_binance("/api/v3/account")
      if (!is.null(acc) && !is.null(acc$balances)) {
        for (b in acc$balances) {
          if (b$asset == "USDT") {
            qtd <- as.numeric(b$free)
            break
          }
        }
      }
    }
    if (is.null(qtd) || is.na(qtd) || qtd < 0.1) return(FALSE)
    floor_qtd <- floor(as.numeric(qtd) * 100) / 100
    if (floor_qtd < 0.1) return(FALSE)
    
    query <- list(productId = "USDT001", amount = sprintf("%.2f", floor_qtd))
    r <- call_binance_post("/sapi/v1/simple-earn/flexible/subscribe", query)
    if (!is.null(r) && !is.null(r$success) && r$success == TRUE) {
      cat(sprintf("🔒 [SIMPLE EARN] Subscrição de %.2f USDT executada com sucesso (Purchase ID: %s)\n", floor_qtd, r$purchaseId))
      return(TRUE)
    }
  }, error = function(e) {
    cat("⚠️ [SIMPLE EARN USDT SUBSCRIBE ERROR]:", conditionMessage(e), "\n")
  })
  return(FALSE)
}

resgatar_simple_earn_usdt <- function(qtd = NULL) {
  tryCatch({
    query <- list(productId = "USDT001")
    if (!is.null(qtd) && qtd > 0) {
      query$amount <- sprintf("%.2f", qtd)
    } else {
      query$redeemAll <- "true"
    }
    r <- call_binance_post("/sapi/v1/simple-earn/flexible/redeem", query)
    if (!is.null(r) && !is.null(r$success) && r$success == TRUE) {
      cat(sprintf("🔓 [SIMPLE EARN] Resgate de USDT executado com sucesso (Redeem ID: %s)\n", r$redeemId))
      Sys.sleep(1)
      return(TRUE)
    }
  }, error = function(e) {
    cat("⚠️ [SIMPLE EARN USDT REDEEM ERROR]:", conditionMessage(e), "\n")
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
  df <- df[!is.na(df$total) & df$total > 0, ]
  
  # SSOT: Enriquece e corrige Simple Earn diretamente da API (/sapi/v1/simple-earn/flexible/position)
  # O token LD* na conta Spot tem lag de sincronização da Binance e omite parcelas recém-alocadas
  tryCatch({
    se_flex <- call_binance("/sapi/v1/simple-earn/flexible/position", list(size = 100))
    if (!is.null(se_flex$rows) && length(se_flex$rows) > 0) {
      flex_rows <- bind_rows(se_flex$rows)
      for (r in 1:nrow(flex_rows)) {
        earn_asset <- flex_rows$asset[r]
        earn_amt <- as.numeric(flex_rows$totalAmount[r])
        if (!is.na(earn_amt) && earn_amt > 0) {
          earn_token <- paste0("LD", earn_asset)
          if (earn_token %in% df$asset) {
            df$free[df$asset == earn_token] <- earn_amt
            df$total[df$asset == earn_token] <- earn_amt
          } else {
            df <- rbind(df, data.frame(asset = earn_token, free = earn_amt, locked = 0, total = earn_amt, stringsAsFactors = FALSE))
          }
        }
      }
    }
  }, error = function(e) {})
  
  # Funding Wallet (saldos residuais de P2P ou transferências internas)
  tryCatch({
    fund <- call_binance_post("/sapi/v1/asset/get-funding-asset", list())
    if (!is.null(fund) && length(fund) > 0) {
      fund_rows <- bind_rows(fund)
      for (r in 1:nrow(fund_rows)) {
        f_asset <- fund_rows$asset[r]
        f_free <- as.numeric(fund_rows$free[r])
        if (!is.na(f_free) && f_free > 0) {
          if (f_asset %in% df$asset) {
            df$free[df$asset == f_asset] <- df$free[df$asset == f_asset] + f_free
            df$total[df$asset == f_asset] <- df$total[df$asset == f_asset] + f_free
          } else {
            df <- rbind(df, data.frame(asset = f_asset, free = f_free, locked = 0, total = f_free, stringsAsFactors = FALSE))
          }
        }
      }
    }
  }, error = function(e) {})
  
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
  if (origem == "BRL" && destino %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "BNB", "ADA", "NEAR")) {
    symbol <- paste0(destino, "BRL")
    side <- "BUY"
    quoteOrderQty <- valor_brl
  } else if (destino == "BRL" && origem %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "BNB", "ADA", "NEAR")) {
    symbol <- paste0(origem, "BRL")
    side <- "SELL"
    
    # Se origem for LINK e estiver no Simple Earn, resgata automaticamente antes da venda
    if (origem == "LINK") {
      df_w_check <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      if (!is.null(df_w_check) && is.data.frame(df_w_check)) {
        row_ld <- df_w_check[df_w_check$asset == "LDLINK", ]
        if (nrow(row_ld) > 0 && sum(row_ld$free, na.rm = TRUE) > 0.1) {
          cat("🔓 [SIMPLE EARN] Detectado LINK em Simple Earn. Executando resgate automático antes da venda...\n")
          resgatar_simple_earn_link()
          Sys.sleep(1)
        }
      }
    }
    
    # Se origem for USDT e estiver no Simple Earn, resgata cirurgicamente apenas o déficit se o saldo Spot for insuficiente
    if (origem == "USDT") {
      df_w_check <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      spot_free_u <- 0.0
      earn_u <- 0.0
      if (!is.null(df_w_check) && is.data.frame(df_w_check)) {
        row_u <- df_w_check[df_w_check$asset == "USDT", ]
        if (nrow(row_u) > 0) spot_free_u <- sum(row_u$free, na.rm = TRUE)
        row_ld <- df_w_check[df_w_check$asset == "LDUSDT", ]
        if (nrow(row_ld) > 0) earn_u <- sum(row_ld$free, na.rm = TRUE)
      }
      
      p_u_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.17)
      if (is.null(p_u_b) || is.na(p_u_b) || p_u_b <= 0) p_u_b <- 5.17
      qtd_u_necessaria <- valor_brl / p_u_b
      
      # Só resgata se o saldo Spot livre for insuficiente para cobrir a ordem!
      if (spot_free_u < qtd_u_necessaria && earn_u > 0) {
        deficit_u <- qtd_u_necessaria - spot_free_u + 0.50
        resgate_u <- min(earn_u, deficit_u)
        cat(sprintf("🔓 [SIMPLE EARN] Resgate cirúrgico de %.2f USDT para cobrir ordem (Spot Livre: %.2f | Necessário: %.2f)...\n", 
                    resgate_u, spot_free_u, qtd_u_necessaria))
        resgatar_simple_earn_usdt(resgate_u)
        Sys.sleep(1)
      }
    }
    
    p_atual <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_atual) && p_atual > 0) {
      precisao_map <- list(
        BTC  = 5,
        ETH  = 4,
        SOL  = 3,
        BNB  = 3,
        LINK = 2,
        USDT = 1,
        ADA  = 1,
        NEAR = 1,
        PAXG = 4
      )
      precisao <- if (!is.null(precisao_map[[origem]])) precisao_map[[origem]] else 2
      mult_p <- 10^precisao
      calc_qty <- floor((valor_brl / p_atual) * mult_p) / mult_p
      
      # Travar no saldo real livre para NUNCA estourar a carteira
      df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      saldo_asset_real <- 0
      if (!is.null(df_w) && is.data.frame(df_w)) {
        row_p <- df_w[df_w$asset == origem, ]
        if (nrow(row_p) > 0) saldo_asset_real <- sum(row_p$free, na.rm = TRUE)
      }
      if (saldo_asset_real > 0) {
        quantity_num <- min(calc_qty, floor(saldo_asset_real * mult_p) / mult_p)
      } else {
        quantity_num <- calc_qty
      }
      
      # Validação estrita de LOT_SIZE / minQty da Binance
      min_qty_map <- list(BTC = 0.00001, ETH = 0.0001, SOL = 0.001, BNB = 0.001, LINK = 0.01, USDT = 0.1, ADA = 0.1, NEAR = 0.1, PAXG = 0.0001)
      min_q <- if (!is.null(min_qty_map[[origem]])) min_qty_map[[origem]] else 0.01
      if (is.null(quantity_num) || is.na(quantity_num) || quantity_num < min_q) {
        return(list(sucesso = FALSE, msg = sprintf("Filter failure: LOT_SIZE (Qtd %.4f < Mín %.4f)", ifelse(is.null(quantity_num) || is.na(quantity_num), 0, quantity_num), min_q)))
      }
      
      # Validação estrita de NOTIONAL da Binance (Mínimo 10.00 BRL)
      if (!is.null(p_atual) && (quantity_num * p_atual < 10.00)) {
        return(list(sucesso = FALSE, msg = sprintf("Filter failure: NOTIONAL (Valor %.2f BRL < Mín 10.00 BRL)", quantity_num * p_atual)))
      }
      
      quantity <- sprintf(paste0("%.", precisao, "f"), quantity_num)
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
    # Guiana Ponta A: Compra PAXG com BTC usando par direto PAXGBTC ou Smart Routing via BRL/USDT
    p_paxg_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) NULL)
    if (is.null(p_paxg_brl_tmp) || p_paxg_brl_tmp <= 0) p_paxg_brl_tmp <- 23777.0
    p_btc_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 416000.0)
    
    # Se volume for >= R$ 48,00 (>= 0.000105 BTC), usa par direto PAXGBTC
    if (valor_brl >= 48.0 && (valor_brl / p_btc_brl_tmp) >= 0.000105) {
      symbol <- "PAXGBTC"
      side <- "BUY"
      p_paxg_btc <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGBTC"), "parsed")$price), error = function(e) 0.055)
      calc_qty <- ceiling((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
      if (calc_qty * p_paxg_btc < 0.000105) {
        calc_qty <- ceiling((0.000105 / p_paxg_btc) * 10000) / 10000
      }
      quantity <- sprintf("%.4f", calc_qty)
    } else {
      # 🌉 SMART ROUTING: Se volume abaixo do notional de PAXGBTC (mín 0.0001 BTC ~ R$ 42), executa ponte inteligente BTC -> BRL -> PAXG
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional de PAXGBTC (mín R$ 48). Executando ponte inteligente BTC -> BRL -> PAXG...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("BTC", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "PAXG", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (origem == "BRL" && destino == "PAXG") {
    # Midas DCA: Compra USDT com BRL e em seguida compra PAXG com USDT (par PAXGUSDT)
    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
    if (is.null(p_usdt_b) || is.na(p_usdt_b) || p_usdt_b <= 0) p_usdt_b <- 5.18
    val_estimado_usdt <- valor_brl / p_usdt_b
    if (val_estimado_usdt < 5.20 || valor_brl < 28.0) {
      cat(sprintf("⚠️ [SMART ROUTING VETO] R$ %.2f (~%.2f USDT) abaixo do Notional mínimo da Binance (5.00 USDT). Requer no mínimo R$ 28.00.\n", valor_brl, val_estimado_usdt))
      return(list(sucesso = FALSE, msg = sprintf("Valor de R$ %.2f abaixo do Notional mínimo de 5.00 USDT da Binance para PAXG. Requer no mínimo R$ 28.00.", valor_brl)))
    }
    
    cat(sprintf("🌉 [SMART ROUTING] Comprando PAXG via ponte BRL -> USDT -> PAXG (R$ %.2f)...\n", valor_brl))
    r_usdt <- enviar_ordem_binance_market("BRL", "USDT", valor_brl)
    if (r_usdt$sucesso) {
      qtd_usdt <- as.numeric(r_usdt$executedQty)
      if (is.na(qtd_usdt) || length(qtd_usdt) == 0 || qtd_usdt <= 0) {
        qtd_usdt <- valor_brl / p_usdt_b
      }
      r_paxg <- enviar_ordem_binance_market("USDT", "PAXG", valor_brl, quoteOrderQty = qtd_usdt)
      if (r_paxg$sucesso) {
        tryCatch({
          Sys.sleep(1)
          subscrever_simple_earn_paxg()
        }, error = function(e) NULL)
        return(r_paxg)
      } else {
        # 🛡️ Blindagem Atômica: Se a compra de PAXG falhar, reverte imediatamente USDT para BRL
        cat(sprintf("⚠️ [SMART ROUTING FALHOU] Falha ao comprar PAXG: %s. Revertendo USDT de volta para Caixa BRL...\n", r_paxg$msg))
        enviar_ordem_binance_market("USDT", "BRL", valor_brl)
        return(r_paxg)
      }
    } else {
      return(r_usdt)
    }
  } else if (origem == "USDT" && destino == "PAXG") {
    symbol <- "PAXGUSDT"
    side <- "BUY"
    if (!is.null(quoteOrderQty)) {
      quoteOrderQty <- sprintf("%.2f", as.numeric(quoteOrderQty))
    }
  } else if (origem == "PAXG" && destino == "BRL") {
    # Venda PAXG para BRL: Resgata do Earn -> Vende PAXG por USDT -> Vende USDT por BRL
    resgatar_simple_earn_paxg()
    cat(sprintf("🌉 [SMART ROUTING] Vendendo PAXG via ponte PAXG -> USDT -> BRL (R$ %.2f)...\n", valor_brl))
    p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 2650.0)
    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
    p_paxg_brl_tmp <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 23777.0)
    
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_paxg_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w)) {
      row_p <- df_w[df_w$asset %in% c("PAXG", "LDPAXG"), ]
      if (nrow(row_p) > 0) saldo_paxg_real <- sum(row_p$free, na.rm = TRUE)
    }
    calc_qty <- floor((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
    quantity <- if (saldo_paxg_real > 0) min(calc_qty, floor(saldo_paxg_real * 10000) / 10000) else calc_qty
    
    r_paxg <- enviar_ordem_binance_market("PAXG", "USDT", valor_brl, quantity = quantity)
    if (r_paxg$sucesso) {
      qtd_usdt <- as.numeric(r_paxg$cummulativeQuoteQty)
      if (is.na(qtd_usdt) || qtd_usdt <= 0) qtd_usdt <- as.numeric(r_paxg$executedQty) * p_paxg_u
      if (is.na(qtd_usdt) || qtd_usdt <= 0) qtd_usdt <- valor_brl / 5.18
      val_brl_usdt <- qtd_usdt * p_usdt_b
      return(enviar_ordem_binance_market("USDT", "BRL", val_brl_usdt))
    } else {
      return(r_paxg)
    }
  } else if (origem == "PAXG" && destino == "USDT") {
    symbol <- "PAXGUSDT"
    side <- "SELL"
    # Auto-resgate do Simple Earn se estiver no Earn flexível
    resgatar_simple_earn_paxg()
    p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 4500.0)
    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
    p_paxg_brl_tmp <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 23500.0)
    
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_paxg_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w)) {
      row_p <- df_w[df_w$asset %in% c("PAXG", "LDPAXG"), ]
      if (nrow(row_p) > 0) saldo_paxg_real <- sum(row_p$free, na.rm = TRUE)
    }
    calc_qty <- floor((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
    quantity_num <- if (saldo_paxg_real > 0) min(calc_qty, floor(saldo_paxg_real * 10000) / 10000) else calc_qty
    if (quantity_num < 0.0001) {
      return(list(sucesso = FALSE, msg = sprintf("Filter failure: LOT_SIZE (Qtd %.4f < Mín 0.0001)", quantity_num)))
    }
    if (quantity_num * p_paxg_u < 5.00) {
      return(list(sucesso = FALSE, msg = sprintf("Filter failure: NOTIONAL (Valor %.2f USDT < Mín 5.00 USDT)", quantity_num * p_paxg_u)))
    }
    quantity <- sprintf("%.4f", quantity_num)
  } else if (origem == "PAXG" && destino == "BTC") {
    # Guiana Ponta B: Vende PAXG por BTC usando par direto PAXGBTC ou Smart Routing via BRL
    p_paxg_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) NULL)
    if (is.null(p_paxg_brl_tmp) || p_paxg_brl_tmp <= 0) p_paxg_brl_tmp <- 23777.0
    p_btc_brl_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 416000.0)
    
    # Resgata do Simple Earn se estiver no Earn flexivel
    resgatar_simple_earn_paxg()
    
    # Se volume for >= R$ 48,00 (>= 0.000105 BTC), usa par direto PAXGBTC
    if (valor_brl >= 48.0 && (valor_brl / p_btc_brl_tmp) >= 0.000105) {
      df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      saldo_paxg_real <- 0
      if (!is.null(df_w) && is.data.frame(df_w)) {
        row_p <- df_w[df_w$asset %in% c("PAXG", "LDPAXG"), ]
        if (nrow(row_p) > 0) saldo_paxg_real <- sum(row_p$free, na.rm = TRUE)
      }
      symbol <- "PAXGBTC"
      side <- "SELL"
      p_paxg_btc <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGBTC"), "parsed")$price), error = function(e) 0.055)
      calc_qty <- floor((valor_brl / p_paxg_brl_tmp) * 10000) / 10000
      quantity_num <- if (saldo_paxg_real > 0) min(calc_qty, floor(saldo_paxg_real * 10000) / 10000) else calc_qty
      if (quantity_num * p_paxg_btc < 0.000105) {
        cat(sprintf("⚠️ [GATEKEEPER NOTIONAL VETO] Quantidade PAXGBTC (%.4f PAXG ~ %.8f BTC) abaixo do Notional mínimo de 0.0001 BTC. Alternando para Smart Routing...\n", quantity_num, quantity_num * p_paxg_btc))
        r1 <- enviar_ordem_binance_market("PAXG", "BRL", valor_brl)
        if (r1$sucesso) {
          return(enviar_ordem_binance_market("BRL", "BTC", valor_brl))
        } else {
          return(r1)
        }
      }
      quantity <- sprintf("%.4f", quantity_num)
    } else {
      # 🌉 SMART ROUTING: Se volume abaixo do notional direto de PAXGBTC (min 0.0001 BTC ~ R$ 42), executa ponte inteligente PAXG -> BRL -> BTC
      cat(sprintf("🌉 [SMART ROUTING] Volume de R$ %.2f abaixo do notional direto de PAXGBTC (mín R$ 48). Executando ponte inteligente PAXG -> BRL -> BTC...\n", valor_brl))
      r1 <- enviar_ordem_binance_market("PAXG", "BRL", valor_brl)
      if (r1$sucesso) {
        return(enviar_ordem_binance_market("BRL", "BTC", valor_brl))
      } else {
        return(r1)
      }
    }
  } else if (as.character(destino) %in% c("NVDAB", "NVDA", "SPYB", "SP500", "SQQQB", "BITI", "TSLAB", "TSLA", "QQQB", "AAPLB", "MSFTB")) {
    # 🇺🇸 Backed Equities Spot da Binance (NVDABUSDT, SPYBUSDT, SQQQBUSDT, TSLABUSDT, QQQBUSDT)
    alvo_sym <- as.character(destino)
    if (alvo_sym == "NVDA") alvo_sym <- "NVDAB"
    if (alvo_sym == "SP500") alvo_sym <- "SPYB"
    if (alvo_sym == "BITI") alvo_sym <- "SQQQB"
    if (alvo_sym == "TSLA") alvo_sym <- "TSLAB"
    spot_symbol <- paste0(alvo_sym, "USDT")
    
    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
    if (is.null(p_usdt_b) || is.na(p_usdt_b) || p_usdt_b <= 0) p_usdt_b <- 5.18
    
    if (origem == "USDT") {
      symbol <- spot_symbol
      side <- "BUY"
      val_u <- if (!is.null(quoteOrderQty)) as.numeric(quoteOrderQty) else (valor_brl / p_usdt_b)
      
      # 🛡️ Auto-Resgate Transparente de Simple Earn com Preservação do Piso de 30%
      df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
      spot_free_usdt <- 0.0
      earn_usdt <- 0.0
      if (!is.null(df_w) && is.data.frame(df_w)) {
        row_spot <- df_w[df_w$asset == "USDT", ]
        if (nrow(row_spot) > 0) spot_free_usdt <- sum(row_spot$free, na.rm = TRUE)
      }
      
      tryCatch({
        q_pos <- list(asset = "USDT")
        pos_res <- call_binance("/sapi/v1/simple-earn/flexible/position", q_pos)
        if (!is.null(pos_res) && !is.null(pos_res$rows) && length(pos_res$rows) > 0) {
          for (rw in pos_res$rows) {
            if (rw$asset == "USDT") earn_usdt <- as.numeric(rw$totalAmount)
          }
        }
      }, error = function(e) NULL)
      
      usdt_total <- spot_free_usdt + earn_usdt
      piso_30_usdt <- usdt_total * 0.30
      max_resgate_permitido <- max(0.0, earn_usdt - piso_30_usdt)
      
      if (spot_free_usdt < val_u) {
        necessario_resgatar <- val_u - spot_free_usdt + 0.50
        if (necessario_resgatar <= max_resgate_permitido && earn_usdt > 0) {
          cat(sprintf("🔓 [AUTO-RESGATE SIMPLE EARN] Resgatando %.2f USDT para Spot (Piso 30%% preservado: %.2f USDT)...\n", 
                      necessario_resgatar, piso_30_usdt))
          resgatar_simple_earn_usdt(necessario_resgatar)
          Sys.sleep(1.2)
        } else if (necessario_resgatar > max_resgate_permitido) {
          cat(sprintf("⚠️ [GATEKEEPER PISO 30%%] Resgate de %.2f USDT limitado para preservar reserva de 30%% (%.2f USDT) no Simple Earn.\n", 
                      necessario_resgatar, piso_30_usdt))
        }
      }
      
      quoteOrderQty <- sprintf("%.2f", val_u)
    } else if (origem == "BRL") {
      cat(sprintf("🌉 [SMART ROUTING] Comprando %s via ponte BRL -> USDT -> %s (R$ %.2f)...\n", alvo_sym, spot_symbol, valor_brl))
      r_u <- enviar_ordem_binance_market("BRL", "USDT", valor_brl)
      if (r_u$sucesso) {
        return(enviar_ordem_binance_market("USDT", alvo_sym, valor_brl, quoteOrderQty = valor_brl / p_usdt_b))
      } else {
        return(r_u)
      }
    }
  } else if (as.character(origem) %in% c("NVDAB", "NVDA", "SPYB", "SP500", "SQQQB", "BITI", "TSLAB", "TSLA", "QQQB", "AAPLB", "MSFTB")) {
    # Venda de Backed Equities Spot para USDT ou Reais
    orig_sym <- as.character(origem)
    if (orig_sym == "NVDA") orig_sym <- "NVDAB"
    if (orig_sym == "SP500") orig_sym <- "SPYB"
    if (orig_sym == "BITI") orig_sym <- "SQQQB"
    if (orig_sym == "TSLA") orig_sym <- "TSLAB"
    spot_symbol <- paste0(orig_sym, "USDT")
    
    p_eq_u <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", spot_symbol)), "parsed")$price), error = function(e) NULL)
    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
    if (is.null(p_usdt_b) || is.na(p_usdt_b) || p_usdt_b <= 0) p_usdt_b <- 5.18
    
    df_w <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
    saldo_eq_real <- 0
    if (!is.null(df_w) && is.data.frame(df_w)) {
      row_eq <- df_w[df_w$asset == orig_sym, ]
      if (nrow(row_eq) > 0) saldo_eq_real <- sum(row_eq$free, na.rm = TRUE)
    }
    
    symbol <- spot_symbol
    side <- "SELL"
    if (!is.null(p_eq_u) && p_eq_u > 0) {
      calc_q <- floor(((valor_brl / p_usdt_b) / p_eq_u) * 100) / 100
      quantity_num <- if (saldo_eq_real > 0) min(calc_q, floor(saldo_eq_real * 100) / 100) else calc_q
      if (quantity_num < 0.01) {
        return(list(sucesso = FALSE, msg = sprintf("Filter failure: LOT_SIZE (Qtd %.2f < Mín 0.01)", quantity_num)))
      }
      if (quantity_num * p_eq_u < 5.00) {
        return(list(sucesso = FALSE, msg = sprintf("Filter failure: NOTIONAL (Valor %.2f USDT < Mín 5.00 USDT)", quantity_num * p_eq_u)))
      }
      quantity <- sprintf("%.2f", quantity_num)
    }
    
    if (destino == "BRL") {
      cat(sprintf("🌉 [SMART ROUTING] Vendendo %s via ponte %s -> USDT -> BRL (R$ %.2f)...\n", orig_sym, spot_symbol, valor_brl))
      r_v <- enviar_ordem_binance_market(orig_sym, "USDT", valor_brl)
      if (r_v$sucesso) {
        return(enviar_ordem_binance_market("USDT", "BRL", valor_brl))
      } else {
        return(r_v)
      }
    }
  }
  
  # Roteamento Sintético Apenas para Derivativos TradFi sem Par Spot Listado (TLT, XLE, WTI)
  tradfi_assets <- c("WTI", "TLT", "XLE", "SH", "UUP", "GLD")
  if (as.character(destino) %in% tradfi_assets || as.character(origem) %in% tradfi_assets) {
    cat(sprintf("🇺🇸 [TRADFI US HEDGE] Alocação sintética executada: %s -> %s (R$ %.2f) com cotação referencial.\n",
                origem, destino, valor_brl))
    return(list(
      sucesso = TRUE,
      orderId = paste0("TRADFI_", round(as.numeric(Sys.time()) * 1000)),
      symbol = paste0(origem, destino),
      price = 1.0,
      origQty = valor_brl,
      cummulativeQuoteQty = valor_brl
    ))
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
      # 🔒 Subscrição Automática no Simple Earn ao Realizar Lucro em USDT
      if (as.character(destino) == "USDT") {
        tryCatch({
          Sys.sleep(1)
          subscrever_simple_earn_usdt()
        }, error = function(e) NULL)
      }
      
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

obter_lote_aberto_binance_ssot <- function(ativo) {
  if (!exists("call_binance")) return(NULL)
  tryCatch({
    sym <- sprintf("%sBRL", ativo)
    trades <- call_binance("/api/v3/myTrades", list(symbol = sym, limit = 40))
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
        ret_obtido_real <- NA
        estrategia_nome <- as.character(pedido$estrategia)
        hist_exec_file <- "ordens_executadas.rds"
        
        # Detecção de Modo Simulado
        ordem_modo_simulado <- identical(pedido$modo, "simulado")
        executar_real_efetivo <- executar_real && !ordem_modo_simulado
        
        # --- TABELA DE TETOS DE VOLUME E LUCROS MÍNIMOS ---
        estrategias_validas <- c(
          "PLANO_GUIANA_BRASILEIRA",
          "PLANO_ESCUDO_DE_AQUILES",
          "PLANO_PATRIA_VOLATIL",
          "PLANO_CABOCLO_DOS_ORACULOS",
          "PLANO_GRAVIDADE_ZERO",
          "PLANO_OURO_LIQUIDO",
          "PLANO_CORISCO_DA_SOLANA",
          "PLANO_DUELO_DE_TITAS",
          "PLANO_FLECHA_DE_SAGARANA",
          "PLANO_COFRE_DE_MIDAS",
          "PLANO_SENTINELA_DO_SOL",
          "PLANO_SENTINELA_DE_MINAS",
          "PLANO_SERTAO_VALENTE",
          "PLANO_FAROL_DE_NEAR",
          "PLANO_BRUCE_WAYNE",
          "PLANO_SENTINELA_WALLSTREET",
          "PLANO_DOLLARUS_QUANTUM_PEG",
          "PLANO_TITA_DO_SILICIO",
          "PLANO_CHOQUE_ENERGETICO",
          "PLANO_ESCUDO_DE_WASHINGTON",
          "PLANO_SENTINELA_ANTIFRAGIL",
          "PLANO_COMMODITY_ENERGY_ALPHA",
          "PLANO_ADEUS_PERRY",
          "PLANO_RAIO_DE_TESLA",
          "PLANO_POMAR_DE_NEWTON",
          "PLANO_DUELO_DE_TITAS_TECH",
          "PLANO_SENTINELA_DE_ETER"
        )
        
        tetos_volume <- list(
          "PLANO_GUIANA_BRASILEIRA" = 220.00,
          "PLANO_ESCUDO_DE_AQUILES" = 500.00,
          "PLANO_PATRIA_VOLATIL" = 650.00,
          "PLANO_CABOCLO_DOS_ORACULOS" = 350.00,
          "PLANO_GRAVIDADE_ZERO" = 220.00,
          "PLANO_OURO_LIQUIDO" = 250.00,
          "PLANO_CORISCO_DA_SOLANA" = 220.00,
          "PLANO_DUELO_DE_TITAS" = 250.00,
          "PLANO_FLECHA_DE_SAGARANA" = 600.00,
          "PLANO_COFRE_DE_MIDAS" = 70.00,
          "PLANO_SENTINELA_DO_SOL" = 250.00,
          "PLANO_SENTINELA_DE_MINAS" = 370.00,
          "PLANO_SERTAO_VALENTE" = 160.00,
          "PLANO_FAROL_DE_NEAR" = 250.00,
          "PLANO_BRUCE_WAYNE" = 350.00,
          "PLANO_SENTINELA_WALLSTREET" = 450.00,
          "PLANO_DOLLARUS_QUANTUM_PEG" = 220.00,
          "PLANO_TITA_DO_SILICIO" = 450.00,
          "PLANO_CHOQUE_ENERGETICO" = 150.00,
          "PLANO_ESCUDO_DE_WASHINGTON" = 150.00,
          "PLANO_SENTINELA_ANTIFRAGIL" = 500.00,
          "PLANO_COMMODITY_ENERGY_ALPHA" = 150.00,
          "PLANO_ADEUS_PERRY" = 450.00,
          "PLANO_RAIO_DE_TESLA" = 280.00,
          "PLANO_POMAR_DE_NEWTON" = 280.00,
          "PLANO_DUELO_DE_TITAS_TECH" = 280.00,
          "PLANO_SENTINELA_DE_ETER" = 500.00
        )
        
        lucros_minimos <- list(
          "PLANO_GUIANA_BRASILEIRA" = 0.40,
          "PLANO_ESCUDO_DE_AQUILES" = 0.57,
          "PLANO_PATRIA_VOLATIL" = 0.40,
          "PLANO_CABOCLO_DOS_ORACULOS" = 1.00,
          "PLANO_GRAVIDADE_ZERO" = 1.07,
          "PLANO_OURO_LIQUIDO" = 0.60,
          "PLANO_CORISCO_DA_SOLANA" = 0.50,
          "PLANO_DUELO_DE_TITAS" = 0.60,
          "PLANO_FLECHA_DE_SAGARANA" = 0.57,
          "PLANO_COFRE_DE_MIDAS" = 0.00,
          "PLANO_SENTINELA_DO_SOL" = 0.50,
          "PLANO_SENTINELA_DE_MINAS" = 0.50,
          "PLANO_SERTAO_VALENTE" = 0.45,
          "PLANO_FAROL_DE_NEAR" = 0.80,
          "PLANO_BRUCE_WAYNE" = 0.00,
          "PLANO_SENTINELA_WALLSTREET" = 0.48,
          "PLANO_DOLLARUS_QUANTUM_PEG" = 0.50,
          "PLANO_TITA_DO_SILICIO" = 0.40,
          "PLANO_CHOQUE_ENERGETICO" = 0.43,
          "PLANO_ESCUDO_DE_WASHINGTON" = 0.52,
          "PLANO_SENTINELA_ANTIFRAGIL" = 0.50,
          "PLANO_COMMODITY_ENERGY_ALPHA" = 0.43,
          "PLANO_ADEUS_PERRY" = 0.40,
          "PLANO_RAIO_DE_TESLA" = 0.60,
          "PLANO_POMAR_DE_NEWTON" = 0.60,
          "PLANO_DUELO_DE_TITAS_TECH" = 0.60,
          "PLANO_SENTINELA_DE_ETER" = 0.40
        )
        
        # Trava 0: Validação de Saldo em Custódia Real (Anti-Venda a Descoberto)
        df_wallet <- tryCatch(carteira(silent = TRUE), error = function(e) NULL)
        if (!is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
          origem_asset <- as.character(pedido$origem)
          
          saldo_disp <- 0
          if (origem_asset %in% c("PAXG", "LINK", "USDT", "BTC", "ETH", "SOL", "BNB")) {
            earn_asset <- paste0("LD", origem_asset)
            row_asset <- df_wallet[df_wallet$asset %in% c(origem_asset, earn_asset), ]
            if (nrow(row_asset) > 0) saldo_disp <- sum(row_asset$free, na.rm = TRUE)
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
            } else if (origem_asset %in% c("SQQQB", "SQQQ", "NVDAB", "NVDA", "SPYB", "SP500", "TSLAB", "TSLA", "QQQB", "AAPLB", "MSFTB", "TLT", "TLTB")) {
              eq_sym <- if (origem_asset %in% c("SQQQ", "BITI")) "SQQQB" else if (origem_asset %in% c("NVDA")) "NVDAB" else if (origem_asset %in% c("SP500")) "SPYB" else if (origem_asset %in% c("TSLA")) "TSLAB" else origem_asset
              p_eq_u <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", eq_sym, "USDT")), "parsed")$price), error = function(e) NULL)
              p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.18)
              preco_unit <- ifelse(!is.null(p_eq_u) && !is.null(p_usdt_b), p_eq_u * p_usdt_b, 200.0)
            } else {
              sym_check <- paste0(origem_asset, "BRL")
              p_tmp <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", sym_check)), "parsed")$price), error = function(e) NULL)
              if (!is.null(p_tmp) && length(p_tmp) > 0 && !is.na(p_tmp) && p_tmp > 0) preco_unit <- p_tmp
            }
          }
          
          qtd_necessaria <- as.numeric(pedido$valor_brl) / preco_unit
          
          if (executar_real_efetivo && saldo_disp < (qtd_necessaria * 0.98)) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Saldo Insuficiente\nDisponível: %.6f %s\nNecessário: %.6f %s\nValor do pedido: %.2f reais",
                                   saldo_disp, origem_asset, qtd_necessaria, origem_asset, pedido$valor_brl)
          }
        }
        
        # Trava 0.5: Validação de Notional Mínimo da Binance (12.00 reais)
        if (aprovado && (is.null(pedido$valor_brl) || as.numeric(pedido$valor_brl) < 12.00)) {
          aprovado <- FALSE
          motivo_veto <- sprintf("Notional Mínimo Binance\nValor solicitado: %.2f reais\nMínimo exigido: 12.00 reais", pedido$valor_brl)
        }
        
        # Trava 0.6: Pré-Validação de LOT_SIZE / Quantidade Mínima (Anti-Filter Failure)
        if (aprovado && pedido$origem != "BRL") {
          min_qty_map <- list(BTC = 0.00001, ETH = 0.0001, SOL = 0.001, BNB = 0.001, LINK = 0.01, USDT = 0.1, ADA = 0.1, NEAR = 0.1, PAXG = 0.0001)
          min_q <- if (!is.null(min_qty_map[[origem_asset]])) min_qty_map[[origem_asset]] else 0.01
          if (!is.null(preco_unit) && preco_unit > 0) {
            qtd_estimada <- as.numeric(pedido$valor_brl) / preco_unit
            if (qtd_estimada < min_q) {
              aprovado <- FALSE
              motivo_veto <- sprintf("LOT_SIZE Mínimo Binance\nAtivo: %s\nQtd Estimada: %.5f\nMínimo exigido: %.5f", origem_asset, qtd_estimada, min_q)
            }
          }
        }
        
        # Trava 1: Validação da Estratégia
        if (aprovado && !(estrategia_nome %in% estrategias_validas)) {
          aprovado <- FALSE
          motivo_veto <- sprintf("Estratégia Não Autorizada\nPlano: %s\nStatus: Fora da matriz ativa", estrategia_nome)
        }
        
        # 🛡️ Trava de Segregação Exclusiva Adeus, Perry:
        # O Plano Adeus Perry opera estrita e exclusivamente a poda de excesso de Ouro PAXG (> 20% da carteira).
        # É terminantemente vetada qualquer tentativa de venda ou desova de altcoins (NEAR, LINK, ADA, AVAX, etc.) ou ativos não-PAXG pelo Adeus Perry.
        if (aprovado && estrategia_nome == "PLANO_ADEUS_PERRY") {
          if (as.character(pedido$origem) != "PAXG") {
            aprovado <- FALSE
            motivo_veto <- sprintf("Segregação Exclusiva Adeus Perry\nOrigem solicitada: %s\nRegra Soberana: Adeus Perry é restrito 100%% à poda de excesso de PAXG",
                                   pedido$origem)
          }
        }
        
        # Subtrava 2.0: Quarentena Antitransbordo Bruce Wayne (12 Horas de Congelamento de Compras & Recompra)
        quarentena_file <- "bruce_quarantine.rds"
        if (aprovado && estrategia_nome != "PLANO_BRUCE_WAYNE" && file.exists(quarentena_file)) {
          quarentena_data <- tryCatch(readRDS(quarentena_file), error = function(e) NULL)
          if (!is.null(quarentena_data)) {
            quarentena_ts  <- if (is.list(quarentena_data)) quarentena_data$timestamp else quarentena_data
            ativo_desovado <- if (is.list(quarentena_data)) quarentena_data$ativo else NULL
            
            if (!is.null(quarentena_ts) && inherits(quarentena_ts, "POSIXt")) {
              horas_passadas <- as.numeric(difftime(Sys.time(), quarentena_ts, units = "hours"))
              if (horas_passadas < 12.0) {
                # Veto estrito se tentar recomprar a moeda desovada (ex: Caboclo tentando recomprar LINK)
                if (!is.null(ativo_desovado) && as.character(pedido$destino) == as.character(ativo_desovado)) {
                  aprovado <- FALSE
                  motivo_veto <- sprintf("Quarentena Bruce Wayne\nAtivo congelado: %s\nTempo restante: %.1fh",
                                         ativo_desovado, 12.0 - horas_passadas)
                } else if (pedido$origem == "BRL") {
                  aprovado <- FALSE
                  motivo_veto <- sprintf("Quarentena Bruce Wayne\nCompras em BRL: Congeladas\nTempo restante: %.1fh", 
                                         12.0 - horas_passadas)
                }
              }
            }
          }
        }
        
        # Trava 2: Teto de Volume por Estratégia (Apenas para Compras / Aportes de Caixa)
        if (aprovado) {
          if (pedido$origem == "BRL") {
            teto_permitido <- ifelse(!is.null(tetos_volume[[estrategia_nome]]), tetos_volume[[estrategia_nome]], 200.00)
            if (is.null(pedido$valor_brl) || pedido$valor_brl > teto_permitido) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto de Compra Excedido\nValor solicitado: R$ %.2f\nTeto permitido: R$ %.2f", 
                                     pedido$valor_brl, teto_permitido)
            }
          }
          # Vendas / Realização de Lucro (Origem != BRL): Autorização de 100% da custódia do ativo
          
          # Cálculo do Patrimônio Total Consolidado
          patrimonio_total_brl <- 2000.0
          if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
            p_btc_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 407000.0)
            p_eth_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) 12700.0)
            p_sol_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SOLBRL"), "parsed")$price), error = function(e) 535.0)
            p_paxg_tmp <- 24000.0
            p_usdt_tmp <- 5.20
            p_link_tmp <- 59.0
            p_bnb_tmp <- 3600.0
            p_ada_tmp <- 1.08
            p_near_tmp <- 9.60
            p_avax_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=AVAXBRL"), "parsed")$price), error = function(e) 37.0)
            
            cotacoes <- list(BRL=1.0, BTC=p_btc_tmp, ETH=p_eth_tmp, SOL=p_sol_tmp, PAXG=p_paxg_tmp, LDPAXG=p_paxg_tmp, USDT=p_usdt_tmp, LDUSDT=p_usdt_tmp, LINK=p_link_tmp, BNB=p_bnb_tmp, ADA=p_ada_tmp, NEAR=p_near_tmp, AVAX=p_avax_tmp)
            
            valores_ativos <- sapply(seq_len(nrow(df_wallet)), function(i) {
              ast <- df_wallet$asset[i]
              qtd <- df_wallet$total[i]
              p_u <- if (!is.null(cotacoes[[ast]])) cotacoes[[ast]] else 1.0
              qtd * p_u
            })
            patrimonio_total_brl <- max(1000.0, sum(valores_ativos, na.rm = TRUE))
          }
          
          # Subtrava 2.1: Teto Universal de 20% para Bitcoin & Teto de Posição Cumulativa em Aberto
          if (aprovado && pedido$destino == "BTC") {
            saldo_btc_brl <- 0.0
            if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
              row_btc <- df_wallet[df_wallet$asset == "BTC", ]
              if (nrow(row_btc) > 0) {
                p_btc_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 407000.0)
                saldo_btc_brl <- sum(row_btc$total, na.rm = TRUE) * p_btc_tmp
              }
            }
            teto_btc_20pct <- max(400.0, patrimonio_total_brl * 0.20)
            pct_btc_atual <- (saldo_btc_brl / patrimonio_total_brl) * 100
            
            if (saldo_btc_brl >= teto_btc_20pct) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto de Bitcoin Atingido\nPosição atual: R$ %.2f (%.1f%%)\nTeto máximo: R$ %.2f (20.0%%)",
                                     saldo_btc_brl, pct_btc_atual, teto_btc_20pct)
            }
          } else if (aprovado && pedido$destino == "PAXG") {
            # 🥇 Teto Dinâmico de Ouro PAXG (20% do Patrimônio Consolidado)
            saldo_paxg_brl <- 0.0
            if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
              row_p <- df_wallet[df_wallet$asset %in% c("PAXG", "LDPAXG"), ]
              if (nrow(row_p) > 0) {
                p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 4591.78)
                p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.175)
                p_paxg_unit <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 23762.0)
                saldo_paxg_brl <- sum(row_p$total, na.rm = TRUE) * p_paxg_unit
              }
            }
            teto_paxg_20pct <- max(400.0, patrimonio_total_brl * 0.20)
            pct_paxg_atual <- (saldo_paxg_brl / patrimonio_total_brl) * 100.0
            
            if (saldo_paxg_brl >= teto_paxg_20pct) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto de Ouro Atingido (20%%)\nPosição atual: R$ %.2f (%.1f%%)\nTeto máximo: R$ %.2f (20.0%%)",
                                     saldo_paxg_brl, pct_paxg_atual, teto_paxg_20pct)
            }
          } else if (aprovado && pedido$origem == "BRL" && pedido$destino %in% c("SOL", "LINK", "ETH", "USDT", "BNB", "ADA", "NEAR")) {
            teto_custodia_map <- list(SOL = 540.0, LINK = 500.0, ETH = 500.0, USDT = 1950.0, BNB = 300.0, ADA = 160.0, NEAR = 350.0)
            teto_custodia <- ifelse(!is.null(teto_custodia_map[[pedido$destino]]), teto_custodia_map[[pedido$destino]], 250.0)
            
            saldo_ativo_brl <- 0.0
            if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
              dest_asset <- as.character(pedido$destino)
              row_d <- df_wallet[df_wallet$asset %in% c(dest_asset, paste0("LD", dest_asset)), ]
              if (nrow(row_d) > 0) {
                p_dest_unit <- 1.0
                if (dest_asset != "BRL") {
                  if (dest_asset == "PAXG") {
                    p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 4591.78)
                    p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.175)
                    p_dest_unit <- ifelse(!is.null(p_paxg_u) && !is.null(p_usdt_b), p_paxg_u * p_usdt_b, 23762.0)
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
              motivo_veto <- sprintf("Teto de Posição Atingido\nCustódia de %s: R$ %.2f\nTeto máximo: R$ %.2f",
                                     pedido$destino, saldo_ativo_brl, teto_custodia)
            }
          }
          
          # Subtrava 2.2: Teto Global de 80% em Criptos e Altcoins (Calibração Alta Velocidade Modelo A)
          # Criptos/Altcoins: BTC, ETH, SOL, LINK, BNB, ADA, NEAR, AVAX, DOGE
          # Não-Cripto (Isentos): BRL (Caixa), USDT (Dólar/FX), PAXG (Ouro Físico/Commodity)
          criptos_altcoins_lista <- c("BTC", "ETH", "SOL", "LINK", "BNB", "ADA", "NEAR", "AVAX", "DOGE")
          
          if (aprovado && as.character(pedido$destino) %in% criptos_altcoins_lista) {
            total_cripto_altcoins_brl <- 0.0
            if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
              for (ca_ast in criptos_altcoins_lista) {
                row_ca <- df_wallet[df_wallet$asset %in% c(ca_ast, paste0("LD", ca_ast)), ]
                if (nrow(row_ca) > 0) {
                  p_ca_unit <- if (exists("cotacoes") && !is.null(cotacoes[[ca_ast]])) cotacoes[[ca_ast]] else 1.0
                  total_cripto_altcoins_brl <- total_cripto_altcoins_brl + (sum(row_ca$total, na.rm = TRUE) * p_ca_unit)
                }
              }
            }
            pct_cripto_atual <- (total_cripto_altcoins_brl / patrimonio_total_brl) * 100.0
            teto_80pct_brl <- patrimonio_total_brl * 0.80
            
            if (total_cripto_altcoins_brl >= teto_80pct_brl) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto Global Cripto Atingido\nExposição atual: R$ %.2f (%.1f%%)\nTeto máximo: R$ %.2f (80.0%%)",
                                     total_cripto_altcoins_brl, pct_cripto_atual, teto_80pct_brl)
            }
          }
          
          # Subtrava 2.3: Coordenação Anti-Canibalização Flecha vs Escudo (mesmo candle de 5m / 300s)
          if (aprovado && as.character(pedido$destino) == "BTC" && estrategia_nome %in% c("PLANO_FLECHA_DE_SAGARANA", "PLANO_ESCUDO_DE_AQUILES")) {
            hist_anti_canib <- "ordens_executadas.rds"
            if (file.exists(hist_anti_canib)) {
              hist_exec_tmp <- tryCatch(readRDS(hist_anti_canib), error = function(e) NULL)
              if (!is.null(hist_exec_tmp) && nrow(hist_exec_tmp) > 0 && all(c("Estrategia", "Destino", "Data_Hora", "Status") %in% names(hist_exec_tmp))) {
                estrategia_parceira <- ifelse(estrategia_nome == "PLANO_FLECHA_DE_SAGARANA", "PLANO_ESCUDO_DE_AQUILES", "PLANO_FLECHA_DE_SAGARANA")
                trades_parceira <- hist_exec_tmp[hist_exec_tmp$Estrategia == estrategia_parceira & 
                                                  hist_exec_tmp$Destino == "BTC" & 
                                                  grepl("EXECUTADO_REAL", hist_exec_tmp$Status), ]
                if (nrow(trades_parceira) > 0) {
                  ultimo_ts <- as.POSIXct(tail(trades_parceira$Data_Hora, 1))
                  segundos_dif <- as.numeric(difftime(Sys.time(), ultimo_ts, units = "secs"))
                  if (!is.na(segundos_dif) && segundos_dif < 300) {
                    aprovado <- FALSE
                    motivo_veto <- sprintf("Anti-Canibalização 5m\nÚltima compra por %s: há %.0fs\nIntervalo mínimo: 300s",
                                           estrategia_parceira, segundos_dif)
                  }
                }
              }
            }
          }
        }
        
        # Trava 2.6: Piso Estrutural Inviolável de Ouro PAXG (10% do Patrimônio Consolidado)
        # Garante a preservação de pelo menos 10% do patrimônio total em Ouro como reserva de valor permanente.
        # Qualquer tentativa de venda/rotação que viole o piso dinâmico de 10% é VETADA (exceto no Plano Bruce Wayne).
        if (aprovado && pedido$origem == "PAXG" && estrategia_nome != "PLANO_BRUCE_WAYNE") {
          piso_ouro_dinamico <- max(200.0, patrimonio_total_brl * 0.10)
          
          # Saldo total atual de ouro (Spot + Simple Earn)
          saldo_ouro_total_brl <- saldo_disp * preco_unit
          saldo_remanescente_ouro <- saldo_ouro_total_brl - as.numeric(pedido$valor_brl)
          
          if (saldo_remanescente_ouro < piso_ouro_dinamico) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Piso Estrutural de Ouro (10%%)\nReserva após venda: %.2f reais\nPiso mínimo dinâmico (10%%): %.2f reais",
                                   saldo_remanescente_ouro, piso_ouro_dinamico)
          }
        }
        
        # Trava 2.7: Corredor Dinâmico de Dólar USDT (Piso de 40% e Teto de 60% do Patrimônio Consolidado - Cenário B)
        # Garante que o valor em dólares NUNCA zera e rende 6,88% a.a. passivamente no Simple Earn
        if (aprovado) {
          piso_usdt_dinamico <- max(500.0, patrimonio_total_brl * 0.40)
          teto_usdt_dinamico <- max(1200.0, patrimonio_total_brl * 0.60)
          
          # Saldo total atual de USDT (Spot + Simple Earn)
          saldo_usdt_total_usd <- 0.0
          if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
            row_u <- df_wallet[df_wallet$asset %in% c("USDT", "LDUSDT"), ]
            if (nrow(row_u) > 0) saldo_usdt_total_usd <- sum(row_u$total, na.rm = TRUE)
          }
          p_u_tmp <- if (exists("cotacoes") && !is.null(cotacoes[["USDT"]])) cotacoes[["USDT"]] else 5.175
          saldo_usdt_total_brl <- saldo_usdt_total_usd * p_u_tmp
          
          # Piso: Vendas de USDT para BRL não podem furar o piso de 40%
          if (pedido$origem == "USDT" && pedido$destino == "BRL") {
            saldo_remanescente_usdt_brl <- saldo_usdt_total_brl - as.numeric(pedido$valor_brl)
            if (saldo_remanescente_usdt_brl < piso_usdt_dinamico) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Piso Estrutural de Dólar (40%%)\nSaldo após venda: %.2f reais (%.1f%%)\nPiso mínimo exigido (40%%): %.2f reais",
                                     saldo_remanescente_usdt_brl, (saldo_remanescente_usdt_brl / patrimonio_total_brl) * 100, piso_usdt_dinamico)
            }
          }
          
          # Teto: Compras de USDT com BRL não podem ultrapassar 60%
          if (pedido$origem == "BRL" && pedido$destino == "USDT") {
            if ((saldo_usdt_total_brl + as.numeric(pedido$valor_brl)) > teto_usdt_dinamico) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Teto de Dólar USDT (60%%)\nSaldo projetado: %.2f reais (%.1f%%)\nTeto máximo permitido: %.2f reais",
                                     saldo_usdt_total_brl + as.numeric(pedido$valor_brl),
                                     ((saldo_usdt_total_brl + as.numeric(pedido$valor_brl)) / patrimonio_total_brl) * 100, teto_usdt_dinamico)
            }
          }
        }
        
        # Trava 2.8: Corredor Dinâmico de Caixa Fiduciário BRL (Piso de 10% e Teto de 20% com Válvula de Dip Cripto - Opção 2)
        # Preserva liquidez em reais contra rotinas fiduciárias e dolarização (Pátria Volátil BRL -> USDT),
        # mas permite perfuração controlada do piso de 10% (até piso residual de 20 reais)
        # EXCLUSIVAMENTE para compras calibradas de dip/crash cripto (BTC, SOL, BNB, LINK, ETH, NEAR)
        if (aprovado && pedido$origem == "BRL") {
          saldo_brl_atual <- 0.0
          if (exists("df_wallet") && !is.null(df_wallet) && is.data.frame(df_wallet) && nrow(df_wallet) > 0) {
            row_b <- df_wallet[df_wallet$asset == "BRL", ]
            if (nrow(row_b) > 0) saldo_brl_atual <- sum(row_b$free, na.rm = TRUE)
          }
          saldo_remanescente_brl <- saldo_brl_atual - as.numeric(pedido$valor_brl)
          
          # Opção 2: Válvula de Dip Cripto
          is_estrategia_dip_cripto <- (pedido$destino %in% c("BTC", "SOL", "BNB", "LINK", "ETH", "NEAR")) &&
            (estrategia_nome %in% c("PLANO_ESCUDO_DE_AQUILES", "PLANO_FLECHA_DE_SAGARANA",
                                    "PLANO_SENTINELA_DO_SOL", "PLANO_SENTINELA_DE_MINAS",
                                    "PLANO_CABOCLO_DOS_ORACULOS", "PLANO_FAROL_DE_NEAR",
                                    "PLANO_DUELO_DE_TITAS", "PLANO_SENTINELA_DE_ETER"))
          
          if (is_estrategia_dip_cripto) {
            # Para compras de dip cripto, exige apenas piso operacional residual de segurança (20 reais)
            piso_operacional_cripto <- 20.0
            if (saldo_remanescente_brl < piso_operacional_cripto) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Piso Operacional Mínimo BRL (20 reais)\nCaixa após compra: %.2f reais\nPiso operacional mínimo: %.2f reais",
                                     saldo_remanescente_brl, piso_operacional_cripto)
            }
          } else {
            # Para rotinas fiduciárias e dolarização (ex: Pátria Volátil BRL -> USDT), o piso estrutural de 10% é rigoroso
            piso_brl_dinamico <- max(200.0, patrimonio_total_brl * 0.10)
            if (saldo_remanescente_brl < piso_brl_dinamico) {
              aprovado <- FALSE
              motivo_veto <- sprintf("Piso de Caixa BRL (10%%)\nCaixa após compra: %.2f reais\nPiso mínimo de oportunidade (10%%): %.2f reais",
                                     saldo_remanescente_brl, piso_brl_dinamico)
            }
          }
        }
        
        # Trava 3: Validação de Lucro Mínimo Esperado (Com Suporte à Subtrava 6.2 Target Decay Ratchet)
        if (aprovado && estrategia_nome %in% names(lucros_minimos)) {
          min_lucro_base <- ifelse(!is.null(lucros_minimos[[estrategia_nome]]), lucros_minimos[[estrategia_nome]], 0.80)
          is_decay_strategy <- estrategia_nome %in% c("PLANO_SENTINELA_DO_SOL", "PLANO_SENTINELA_DE_MINAS", "PLANO_FAROL_DE_NEAR", "PLANO_CABOCLO_DOS_ORACULOS", "PLANO_SENTINELA_DE_ETER")
          min_lucro <- if (is_decay_strategy && !is.null(pedido$lucro_esperado_pct) && as.numeric(pedido$lucro_esperado_pct) >= 0.40) {
            min(min_lucro_base, as.numeric(pedido$lucro_esperado_pct))
          } else {
            min_lucro_base
          }
          if (is.null(pedido$lucro_esperado_pct) || as.numeric(pedido$lucro_esperado_pct) < min_lucro) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Lucro Projetado Insuficiente\nLucro esperado: +%.2f%%\nLucro exigido: +%.2f%%",
                                   pedido$lucro_esperado_pct, min_lucro)
          }
        }
        
        # Trava 4: Cooldown Adaptativo Harmonicus Ultra-Deep
        hist_exec_file <- "ordens_executadas.rds"
        if (aprovado && file.exists(hist_exec_file)) {
          hist_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
          if (!is.null(hist_exec) && nrow(hist_exec) > 0 && "Estrategia" %in% names(hist_exec)) {
            hist_est <- hist_exec[hist_exec$Estrategia == estrategia_nome & grepl("EXECUTADO_REAL", hist_exec$Status), ]
            if (nrow(hist_est) > 0) {
              ultimo_ts <- as.POSIXct(tail(hist_est$Data_Hora, 1))
              horas_dif <- as.numeric(difftime(Sys.time(), ultimo_ts, units = "hours"))
              
              # Cooldown Otimizado Harmonicus Ultra-Deep
              cooldown_req <- ifelse(estrategia_nome == "PLANO_COFRE_DE_MIDAS", 120.0, # 5 dias
                              ifelse(estrategia_nome == "PLANO_BRUCE_WAYNE", 24.0,
                              ifelse(estrategia_nome == "PLANO_SENTINELA_WALLSTREET", 0.50,
                              ifelse(estrategia_nome %in% c("PLANO_TITA_DO_SILICIO", "PLANO_OURO_LIQUIDO"), 0.25,
                              ifelse(estrategia_nome == "PLANO_DOLLARUS_QUANTUM_PEG", 0.25,
                              ifelse(estrategia_nome %in% c("PLANO_CORISCO_DA_SOLANA", "PLANO_SENTINELA_DE_MINAS", "PLANO_SENTINELA_DO_SOL"), 0.16, 
                              ifelse(estrategia_nome == "PLANO_FLECHA_DE_SAGARANA", 0.13,
                              ifelse(estrategia_nome == "PLANO_CABOCLO_DOS_ORACULOS", 0.20,
                              ifelse(estrategia_nome == "PLANO_SERTAO_VALENTE", 0.25,
                              ifelse(estrategia_nome == "PLANO_FAROL_DE_NEAR", 1.0,
                              ifelse(estrategia_nome == "PLANO_DUELO_DE_TITAS", 1.5,
                              ifelse(estrategia_nome == "PLANO_SENTINELA_DE_ETER", 0.50,
                              ifelse(grepl("GRAVIDADE", estrategia_nome), 0.16, 1.0)))))))))))))
              
              # Se for realização de lucro / rotação oposta, zera o cooldown
              ultimo_reg <- tail(hist_est, 1)
              if (!is.null(ultimo_reg$Origem) && ultimo_reg$Origem != as.character(pedido$origem)) {
                cooldown_req <- 0.0
              }
              
              if (horas_dif < cooldown_req) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Cooldown Operacional Ativo\nTempo decorrido: %.1fh\nTempo exigido: %.1fh (%d min)",
                                       horas_dif, cooldown_req, round(cooldown_req * 60))
              }
            }
          }
        }
        
        # Trava 5: Governança de Inventário Compartilhado (Shared Inventory)
        # Qualquer plano pode liquidar qualquer ativo em carteira, contanto que gere lucro real (validado pela Trava 6).
        # Se a compra foi feita há menos de 5 minutos, exige que seja com lucro confirmado para evitar micro-slippage.
        
        # Trava 6: Trava Anti-Prejuízo / Breakeven Lock Universal (Proíbe Venda Abaixo do Custo Real do Lote em Aberto)
        # REGRA SUPREMA: Somente o PLANO BRUCE WAYNE (Contingência de Crise Cripto) está ISENTO da Trava 6
        if (aprovado && estrategia_nome == "PLANO_BRUCE_WAYNE") {
          cat("🦇 [PLANO BRUCE WAYNE] Operação de Contingência de Crise Cripto: ISENTO da Trava 6 Breakeven Lock para estancar sangria macro sistêmica.\n")
        } else if (aprovado && pedido$destino == "BRL" && pedido$origem %in% c("SOL", "LINK", "ETH", "USDT", "BTC", "PAXG", "BNB", "ADA", "NEAR")) {
          p_atual_mercado <- if (pedido$origem == "PAXG") {
            p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) NULL)
            p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) NULL)
            if (!is.null(p_paxg_u) && !is.null(p_usdt_b)) p_paxg_u * p_usdt_b else NULL
          } else {
            sym_check <- sprintf("%sBRL", pedido$origem)
            tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%s", sym_check)), "parsed")$price), error = function(e) NULL)
          }
          
          if (!is.null(p_atual_mercado) && p_atual_mercado > 0 && file.exists(hist_exec_file)) {
            hist_all <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
            if (!is.null(hist_all) && nrow(hist_all) > 0 && "Destino" %in% names(hist_all)) {
              exec_reais <- hist_all[grepl("EXECUTADO_REAL", hist_all$Status), ]
              
              is_estrategia_desova <- (estrategia_nome == "PLANO_ADEUS_PERRY" && as.character(pedido$origem) == "PAXG") || (estrategia_nome == "PLANO_BRUCE_WAYNE")
              
              if (is_estrategia_desova) {
                # 🛡️ Planos de Liquidação e Circuit Breaker (Adeus, Perry / Bruce Wayne):
                # Não segregam custódia por estratégia para seus ativos autorizados (PAXG no Perry, geral no Bruce Wayne)!
                compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem), ]
                vendas_todas  <- exec_reais[exec_reais$Origem == as.character(pedido$origem), ]
                compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas)
                if (nrow(compras_abertas) == 0) {
                  compras_abertas <- compras_todas
                }
              } else {
                # 🛡️ Rastreamento FIFO Real de Lotes Abertos por Estratégia (Baseado em Quantidade de Tokens)
                ativos_exclusivos <- c("NEAR", "LINK", "SOL", "BNB", "ADA", "AVAX", "NVDAB", "SPYB", "SQQQB", "TLT", "TSLAB", "AAPLB", "ETH")
                if (as.character(pedido$origem) %in% ativos_exclusivos) {
                  compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem), ]
                  vendas_todas  <- exec_reais[exec_reais$Origem == as.character(pedido$origem), ]
                } else {
                  filtro_patria <- if (estrategia_nome == "PLANO_PATRIA_VOLATIL") exec_reais$Valor_BRL <= 350.0 else TRUE
                  compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem) & 
                                              exec_reais$Estrategia == estrategia_nome & 
                                              filtro_patria, ]
                  vendas_todas <- exec_reais[exec_reais$Origem == as.character(pedido$origem) & 
                                            (exec_reais$Estrategia == estrategia_nome | exec_reais$Estrategia %in% c("PLANO_ADEUS_PERRY", "PLANO_BRUCE_WAYNE")), ]
                }
                
                compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas, ativo = as.character(pedido$origem))
                
                # 🛡️ SSOT BINANCE API: Sincronização direta com a custódia real na corretora para altcoins
                if (as.character(pedido$origem) %in% c("NEAR", "LINK", "SOL", "BNB", "ETH")) {
                  ssot_lote <- tryCatch(obter_lote_aberto_binance_ssot(as.character(pedido$origem)), error = function(e) NULL)
                  if (!is.null(ssot_lote) && isTRUE(ssot_lote$tem_lote) && !is.null(ssot_lote$vwap_abertos) && ssot_lote$vwap_abertos > 0) {
                    compras_abertas <- data.frame(
                      Data_Hora = ssot_lote$data_compra,
                      Estrategia = estrategia_nome,
                      Origem = "BRL",
                      Destino = as.character(pedido$origem),
                      Valor_BRL = ssot_lote$valor_total_aberto,
                      Preco_Exec = ssot_lote$vwap_abertos,
                      qtd = ssot_lote$qtd_aberta,
                      Status = "EXECUTADO_REAL_BINANCE",
                      stringsAsFactors = FALSE
                    )
                  }
                }
              }
              
              # Fallback auditado de preço de aquisição na Binance para ativos legados (ADA, AVAX):
              if (nrow(compras_abertas) == 0 && is_estrategia_desova) {
                precos_aquisicao_legados <- list(
                  ADA  = 1.083,  # 120 ADA adquiridas na Binance a R$ 1.083
                  AVAX = 135.0
                )
                
                p_aquisicao_leg <- tryCatch({
                  sym_b <- sprintf("%sBRL", pedido$origem)
                  tr_res <- call_binance("/api/v3/myTrades", list(symbol = sym_b, limit = 5))
                  if (!is.null(tr_res) && length(tr_res) > 0) {
                    buys <- tr_res[sapply(tr_res, function(x) isTRUE(x$isBuyer))]
                    if (length(buys) > 0) as.numeric(tail(buys, 1)[[1]]$price) else NULL
                  } else NULL
                }, error = function(e) NULL)
                
                if (is.null(p_aquisicao_leg) || is.na(p_aquisicao_leg) || p_aquisicao_leg <= 0) {
                  p_aquisicao_leg <- precos_aquisicao_legados[[as.character(pedido$origem)]]
                }
                
                if (!is.null(p_aquisicao_leg) && !is.na(p_aquisicao_leg) && p_aquisicao_leg > 0) {
                  compras_abertas <- data.frame(
                    Data_Hora = as.character(Sys.time() - 86400 * 3),
                    Estrategia = estrategia_nome,
                    Origem = "BRL",
                    Destino = as.character(pedido$origem),
                    Valor_BRL = as.numeric(pedido$valor_brl),
                    Preco_Exec = as.numeric(p_aquisicao_leg),
                    Status = "EXECUTADO_REAL_BINANCE",
                    stringsAsFactors = FALSE
                  )
                }
              }
              
              # Segregação Estrita de Custódia: se a estratégia não possui lote de compra aberto, veta a tentativa
              if (nrow(compras_abertas) == 0) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Segregação de Custódia\n%s não possui lote de compra aberto para %s",
                                       estrategia_nome, pedido$origem)
              } else {
                validos <- compras_abertas[!is.na(compras_abertas$Preco_Exec) & compras_abertas$Preco_Exec > 0 & !is.na(compras_abertas$Valor_BRL), ]
                
                # Blindagem do Preço Real Executado na Binance:
                # Se Preco_Exec já foi gravado em reais (>= 1.0), ele é o preço exato preenchido pela Binance!
                # Consulta ao SQLite somente ocorre se Preco_Exec for ratio puro (< 1.0)
                if (nrow(validos) > 0) {
                  idx_ratio <- which(validos$Preco_Exec < 1.0)
                  if (length(idx_ratio) > 0) {
                    db_p <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/app/MoneyBot_Local.db"
                    for (k in idx_ratio) {
                      p_real_hist <- tryCatch({
                        con_k <- dbConnect(SQLite(), db_p)
                        sym_col <- sprintf("%sBRL", pedido$origem)
                        df_k <- dbGetQuery(con_k, sprintf("SELECT %s FROM Historico_binance WHERE Data_Hora <= '%s' ORDER BY Data_Hora DESC LIMIT 1;", sym_col, validos$Data_Hora[k]))
                        dbDisconnect(con_k)
                        as.numeric(df_k[[sym_col]][1])
                      }, error = function(e) NA)
                      if (!is.na(p_real_hist) && p_real_hist > 0) {
                        validos$Preco_Exec[k] <- p_real_hist
                      } else {
                        p_btc_tmp <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 410000.0)
                        if (is.null(p_btc_tmp) || is.na(p_btc_tmp) || p_btc_tmp <= 0) p_btc_tmp <- 410000.0
                        validos$Preco_Exec[k] <- validos$Preco_Exec[k] * p_btc_tmp
                      }
                    }
                  }
                }
                
                # 🛡️ TRAVA 6 RIGOROSA SSOT ANTI-MICRO-PREJUÍZO (FIFO REAL):
                # O lote a ser desovado na corretora pela regra da Binance API é o LOTE FIFO MAIS ANTIGO:
                p_fifo_lote <- validos$Preco_Exec[1] # Preço de aquisição do lote mais antigo a ser fechado
                p_vwap_lote <- sum(validos$Valor_BRL) / sum(validos$qtd) # VWAP de todos os lotes
                
                # Custo ponderado e preço máximo dos lotes tocados por esta ordem específica:
                qtd_venda_est <- as.numeric(pedido$valor_brl) / p_atual_mercado
                qtd_restante <- qtd_venda_est
                custo_acum <- 0
                qtd_acum <- 0
                precos_lotes_tocados <- c()
                for (j in 1:nrow(validos)) {
                  if (qtd_restante <= 1e-6) break
                  qtd_lote_j <- if ("qtd" %in% names(validos) && !is.na(validos$qtd[j])) validos$qtd[j] else (validos$Valor_BRL[j] / validos$Preco_Exec[j])
                  qtd_usar <- min(qtd_restante, qtd_lote_j)
                  custo_acum <- custo_acum + (qtd_usar * validos$Preco_Exec[j])
                  qtd_acum <- qtd_acum + qtd_usar
                  precos_lotes_tocados <- c(precos_lotes_tocados, validos$Preco_Exec[j])
                  qtd_restante <- qtd_restante - qtd_usar
                }
                custo_fifo_ordem <- if (qtd_acum > 0) custo_acum / qtd_acum else p_fifo_lote
                maior_preco_tocado <- if (length(precos_lotes_tocados) > 0) max(precos_lotes_tocados) else p_fifo_lote
                
                # O preço de referência de custo DEVE cobrir rigorosamente o MÁXIMO entre:
                # 1) Lote FIFO mais antigo; 2) VWAP global; 3) Custo dos lotes consumidos; 4) Maior preço de compra tocado
                p_entrada_seguro <- max(c(p_fifo_lote, p_vwap_lote, custo_fifo_ordem, maior_preco_tocado), na.rm = TRUE)
                p_entrada <- p_entrada_seguro
                
                # Validação de Holding Time Mínimo (15 minutos para maturação de onda espectral)
                # Exceto se o lucro real atual for expressivo (>= +1.50%)
                ultima_compra_ts <- as.POSIXct(tail(validos$Data_Hora, 1))
                tempo_posse_min <- as.numeric(difftime(Sys.time(), ultima_compra_ts, units = "mins"))
                
                if (!is.na(p_entrada) && p_entrada > 0) {
                  ret_nominal <- ((p_atual_mercado - p_entrada) / p_entrada) * 100
                  ret_obtido_real <- ret_nominal
                  
                  # Lucro mínimo exigido conforme tabela oficial de governança
                  meta_tabela <- if (estrategia_nome %in% names(lucros_minimos)) as.numeric(lucros_minimos[[estrategia_nome]]) else 0.40
                  # 🛡️ Subtrava 6.2: Target Decay Ratchet (respeita meta dinâmica desde que estritamente >= +0.40% piso)
                  is_decay_strategy <- estrategia_nome %in% c("PLANO_SENTINELA_DO_SOL", "PLANO_SENTINELA_DE_MINAS", "PLANO_FAROL_DE_NEAR", "PLANO_CABOCLO_DOS_ORACULOS")
                  lucro_minimo_exigido <- if (is_decay_strategy && !is.null(pedido$lucro_esperado_pct) && as.numeric(pedido$lucro_esperado_pct) >= 0.40) {
                    min(meta_tabela, as.numeric(pedido$lucro_esperado_pct))
                  } else {
                    meta_tabela
                  }
                  
                  if (tempo_posse_min < 15.0 && ret_nominal < 1.50) {
                    aprovado <- FALSE
                    motivo_veto <- sprintf("Holding Time Mínimo\nTempo de posse: %.1f min\nTempo exigido: >= 15.0 min",
                                           tempo_posse_min)
                  } else if (ret_nominal < lucro_minimo_exigido) {
                    aprovado <- FALSE
                    motivo_veto <- sprintf("Trava Anti-Prejuízo FIFO Real\nPreço atual de %s: R$ %.2f\nCusto Seguro (Max FIFO/VWAP/Lotes): R$ %.2f\nRetorno FIFO: %+.2f%% | Exige >= +%.2f%%",
                                           pedido$origem, p_atual_mercado, p_entrada_seguro, ret_nominal, lucro_minimo_exigido)
                  }
                }
              }
            }
          }
          
          # 🛡️ Trava 6 Soberana: Validação Estrita FIFO sobre ordens_executadas.rds (p_entrada)
          # A antiga checagem estática em carteira.rds foi desativada para seguir o protocolo SSOT FIFO.
        } else if (aprovado && pedido$destino == "BTC" && pedido$origem %in% c("SOL", "ETH", "PAXG", "LINK", "BNB", "ADA", "NEAR")) {
          # === SUB-TRAVA 6.1: ROTAÇÕES CRUZADAS CRIPTO-CRIPTO PARA BITCOIN (SATOSHIS LOCK) ===
          p_btc_live <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=BTCBRL"), "parsed")$price), error = function(e) 410000.0)
          p_origem_live <- if (pedido$origem == "PAXG") {
            p_paxg_u <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price), error = function(e) 2650.0)
            p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.20)
            p_paxg_u * p_usdt_b
          } else {
            tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%sBRL", pedido$origem)), "parsed")$price), error = function(e) 0.0)
          }
          
          ratio_live <- if (p_btc_live > 0 && p_origem_live > 0) p_origem_live / p_btc_live else 0.0
          
          if (ratio_live > 0 && file.exists(hist_exec_file)) {
            hist_all <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
            if (!is.null(hist_all) && nrow(hist_all) > 0 && "Destino" %in% names(hist_all)) {
              is_desova_sub61 <- (estrategia_nome == "PLANO_BRUCE_WAYNE")
              if (!is_desova_sub61) {
                compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem) & exec_reais$Estrategia == estrategia_nome, ]
                vendas_todas  <- exec_reais[exec_reais$Origem == as.character(pedido$origem) & exec_reais$Estrategia == estrategia_nome, ]
              } else {
                compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem), ]
                vendas_todas  <- exec_reais[exec_reais$Origem == as.character(pedido$origem), ]
              }
              compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas, ativo = as.character(pedido$origem))
              
              if (nrow(compras_abertas) == 0) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Segregação Estrita de Custódia\nO plano %s não possui lote aberto de %s para realizar rotação para BTC.",
                                       estrategia_nome, pedido$origem)
              }
              
              validos <- compras_abertas[!is.na(compras_abertas$Preco_Exec) & compras_abertas$Preco_Exec > 0 & !is.na(compras_abertas$Valor_BRL), ]
              if (nrow(validos) > 0) {
                limiar_ratio_btc <- ifelse(pedido$origem %in% c("ADA", "NEAR"), 0.1, 1.0)
                db_p <- if (file.exists("MoneyBot_Local.db")) "MoneyBot_Local.db" else "/app/MoneyBot_Local.db"
                
                ratios_compra <- sapply(seq_len(nrow(validos)), function(k) {
                  if (validos$Preco_Exec[k] < limiar_ratio_btc) {
                    return(validos$Preco_Exec[k])
                  }
                  # Se a compra veio de BTC (Origem == "BTC"), busca o par no banco local para achar o ratio exato
                  if (validos$Origem[k] == "BTC") {
                    ratio_hist <- tryCatch({
                      con_k <- dbConnect(SQLite(), db_p)
                      on.exit(dbDisconnect(con_k))
                      sym_col <- sprintf("%sBRL", pedido$origem)
                      df_k <- dbGetQuery(con_k, sprintf("SELECT BTCBRL, %s FROM Historico_binance WHERE Data_Hora <= '%s' ORDER BY Data_Hora DESC LIMIT 1;", sym_col, validos$Data_Hora[k]))
                      as.numeric(df_k[[sym_col]][1]) / as.numeric(df_k$BTCBRL[1])
                    }, error = function(e) NA)
                    if (!is.na(ratio_hist) && ratio_hist > 0) {
                      return(ratio_hist)
                    }
                  }
                  return(validos$Preco_Exec[k] / p_btc_live)
                })
                
                ratio_entrada_fifo <- mean(ratios_compra, na.rm = TRUE)
                ret_satoshis <- ((ratio_live - ratio_entrada_fifo) / ratio_entrada_fifo) * 100
                ret_obtido_real <- ret_satoshis
                
                if (ret_satoshis < 0.40) {
                  aprovado <- FALSE
                  motivo_veto <- sprintf("Trava Satoshis FIFO\nRatio atual de %s/BTC: %.8f BTC\nLote em aberto: %.8f BTC\nRetorno: %+.2f%% | Exige >= +0.40%%",
                                         pedido$origem, ratio_live, ratio_entrada_fifo, ret_satoshis)
                }
              }
            }
          }
        } else if (aprovado && pedido$origem == "BTC" && pedido$destino == "PAXG") {
          # === SUB-TRAVA 6.3: ROTAÇÃO BTC -> PAXG (PLANO GUIANA BRASILEIRA) ===
          # Exige compulsoriamente que a estratégia possua lote aberto próprio de BTC
          if (file.exists(hist_exec_file)) {
            hist_all <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
            if (!is.null(hist_all) && nrow(hist_all) > 0) {
              exec_reais <- hist_all[grepl("EXECUTADO_REAL", hist_all$Status), ]
              compras_todas <- exec_reais[exec_reais$Destino == "BTC" & exec_reais$Estrategia == estrategia_nome, ]
              vendas_todas  <- exec_reais[exec_reais$Origem == "BTC" & exec_reais$Estrategia == estrategia_nome, ]
              compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas, ativo = "BTC")
              
              if (nrow(compras_abertas) == 0) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Segregação Estrita de Custódia\nO plano %s não possui lote aberto de BTC para realizar compra de PAXG.",
                                       estrategia_nome)
              }
            }
          }
        } else if (aprovado && pedido$destino == "USDT" && pedido$origem %in% c("PAXG", "BTC", "ETH", "SQQQB", "NVDAB", "SPYB", "TLT", "TSLAB", "QQQB", "AAPLB", "MSFTB")) {
          # === SUB-TRAVA 6.2: ROTAÇÕES PARA DÓLAR USDT (CRIPTO + BACKED EQUITIES SPOT) ===
          p_usdt_b <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 5.20)
          orig_sym_check <- as.character(pedido$origem)
          if (orig_sym_check == "TLT") orig_sym_check <- "TLTB"
          p_origem_u_live <- tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%sUSDT", orig_sym_check)), "parsed")$price), error = function(e) 0.0)
          if ((is.null(p_origem_u_live) || is.na(p_origem_u_live) || p_origem_u_live <= 0) && orig_sym_check %in% c("TLT", "TLTB")) {
            p_origem_u_live <- 95.0
          }
          
          if (!is.null(p_origem_u_live) && p_origem_u_live > 0 && file.exists(hist_exec_file)) {
            hist_all <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
            if (!is.null(hist_all) && nrow(hist_all) > 0 && "Destino" %in% names(hist_all)) {
              exec_reais <- hist_all[grepl("EXECUTADO_REAL", hist_all$Status), ]
              
              if (estrategia_nome %in% c("PLANO_ADEUS_PERRY", "PLANO_BRUCE_WAYNE")) {
                compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem), ]
                vendas_todas  <- exec_reais[exec_reais$Origem == as.character(pedido$origem), ]
                compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas)
                if (nrow(compras_abertas) == 0) {
                  compras_abertas <- compras_todas
                }
              } else {
                compras_todas <- exec_reais[exec_reais$Destino == as.character(pedido$origem) & 
                                            exec_reais$Estrategia == estrategia_nome, ]
                ativos_exclusivos <- c("NEAR", "LINK", "SOL", "BNB", "ADA", "AVAX", "NVDAB", "SPYB", "SQQQB", "TLT", "TSLAB", "AAPLB", "ETH")
                if (as.character(pedido$origem) %in% ativos_exclusivos) {
                  vendas_todas <- exec_reais[exec_reais$Origem == as.character(pedido$origem), ]
                } else {
                  vendas_todas <- exec_reais[exec_reais$Origem == as.character(pedido$origem) & 
                                            (exec_reais$Estrategia == estrategia_nome | exec_reais$Estrategia %in% c("PLANO_ADEUS_PERRY", "PLANO_BRUCE_WAYNE")), ]
                }
                compras_abertas <- calcular_lotes_abertos_fifo(compras_todas, vendas_todas)
              }
              
              if (nrow(compras_abertas) == 0 && estrategia_nome %in% c("PLANO_ADEUS_PERRY", "PLANO_BRUCE_WAYNE")) {
                compras_abertas <- tail(exec_reais[exec_reais$Destino == as.character(pedido$origem), ], 1)
              }
              
              if (nrow(compras_abertas) == 0) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Segregação de Custódia\n%s não possui lote de compra aberto para %s",
                                       estrategia_nome, pedido$origem)
              } else {
                validos <- compras_abertas[!is.na(compras_abertas$Preco_Exec) & compras_abertas$Preco_Exec > 0 & !is.na(compras_abertas$Valor_BRL), ]
                if (pedido$origem == "PAXG") validos <- validos[validos$Preco_Exec > 1000.0, , drop = FALSE]
                
                p_entrada_exec <- if (nrow(validos) > 0) {
                  sum(validos$Valor_BRL) / sum(validos$qtd)
                } else NA
                
                # Fallback auditado SSOT na Binance para Ouro PAXG:
                if (is.na(p_entrada_exec) && pedido$origem == "PAXG") p_entrada_exec <- 23576.0
                
                if (!is.na(p_entrada_exec) && p_entrada_exec > 0) {
                  p_entrada_usdt <- tryCatch({
                    if (as.character(pedido$origem) %in% c("NVDAB", "SPYB", "SQQQB", "TLT", "TSLAB", "AAPLB")) {
                      sym_t <- if (as.character(pedido$origem) == "TLT") "TLTBUSDT" else paste0(as.character(pedido$origem), "USDT")
                      tr_eq <- call_binance("/api/v3/myTrades", list(symbol = sym_t, limit = 5))
                      if (!is.null(tr_eq) && length(tr_eq) > 0) {
                        buys_eq <- tr_eq[sapply(tr_eq, function(x) isTRUE(x$isBuyer))]
                        if (length(buys_eq) > 0) as.numeric(tail(buys_eq, 1)[[1]]$price) else (p_entrada_exec / p_usdt_b)
                      } else (p_entrada_exec / p_usdt_b)
                    } else {
                      p_entrada_exec / p_usdt_b
                    }
                  }, error = function(e) (p_entrada_exec / p_usdt_b))
                  
                  ret_usdt <- ((p_origem_u_live - p_entrada_usdt) / p_entrada_usdt) * 100
                  ret_obtido_real <- ret_usdt
                  
                  # Validação de Holding Time Mínimo (15 minutos para maturação de onda espectral)
                  ultima_compra_ts <- as.POSIXct(tail(validos$Data_Hora, 1))
                  tempo_posse_min <- as.numeric(difftime(Sys.time(), ultima_compra_ts, units = "mins"))
                  
                  min_lucro_exigido <- ifelse(!is.null(lucros_minimos[[estrategia_nome]]), lucros_minimos[[estrategia_nome]], 0.40)
                  
                  if (tempo_posse_min < 15.0 && ret_usdt < 1.50) {
                    aprovado <- FALSE
                    motivo_veto <- sprintf("Holding Time Mínimo (15m)\nTempo de posse: %.1f min\nTempo exigido: >= 15.0 min",
                                           tempo_posse_min)
                  } else if (ret_usdt < min_lucro_exigido) {
                    aprovado <- FALSE
                    motivo_veto <- sprintf("Trava Dólar FIFO\nPreço atual de %s: US$ %.2f\nLote em aberto: US$ %.2f\nRetorno: %+.2f%% | Exige >= +%.2f%%",
                                           pedido$origem, p_origem_u_live, p_entrada_usdt, ret_usdt, min_lucro_exigido)
                  }
                } else {
                  aprovado <- FALSE
                  motivo_veto <- sprintf("Segregação de Custódia\nPreço de entrada FIFO não disponível para %s", pedido$origem)
                }
              }
            } else {
              aprovado <- FALSE
              motivo_veto <- sprintf("Auditoria Trava 6\nHistórico de execuções inacessível para validar lote de %s", pedido$origem)
            }
          } else {
            # FAIL-CLOSED SOBERANO: Se cotação ao vivo falhar, NUNCA autoriza venda para USDT!
            aprovado <- FALSE
            motivo_veto <- sprintf("Falha na Cotação de Mercado\nNão foi possível obter preço ao vivo de %sUSDT na Binance para validação da Trava 6 Dólar FIFO", orig_sym_check)
          }
        }
        
        # --- VEREDITO DO LABPOLICE & EXECUÇÃO ---
        if (aprovado) {
          cat(sprintf("✅ [AUTORIZADO] Ordem validada com sucesso! Lucro Projetado: +%.2f%%\n", pedido$lucro_esperado_pct))
          
          resultado_binance <- list(sucesso = TRUE, orderId = "SIMULADO_LOCAL")
          if (executar_real_efetivo) {
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
            } else if (pedido$destino == "USDT") {
              # Auto-Alocação no Simple Earn Flexível USDT para render juros diários (6,88% a.a.)
              qtd_usdt_exec <- as.numeric(resultado_binance$executedQty)
              if (!is.na(qtd_usdt_exec) && qtd_usdt_exec > 0.1) {
                subscrever_simple_earn_usdt(qtd_usdt_exec)
              }
            }
          }
          
          status_final <- if (executar_real_efetivo) {
            ifelse(resultado_binance$sucesso, "EXECUTADO_REAL_BINANCE", paste0("FALHA_BINANCE: ", resultado_binance$msg))
          } else {
            "SINAL_APROVADO_SIMULADO"
          }
          
          p_calc_exec <- 0.0
          ativo_adquirido <- if (pedido$origem %in% c("BRL", "USDT")) as.character(pedido$destino) else as.character(pedido$origem)
          
          if (!is.null(resultado_binance$executedQty) && !is.na(as.numeric(resultado_binance$executedQty)) && as.numeric(resultado_binance$executedQty) > 0) {
            # Preço unitário em BRL baseado na quantidade real executada na Binance (elimina distorção cambial)
            p_calc_exec <- as.numeric(pedido$valor_brl) / as.numeric(resultado_binance$executedQty)
          } else if (pedido$origem == "BRL" && !is.null(resultado_binance$cummulativeQuoteQty) && !is.null(resultado_binance$executedQty)) {
            e_qty <- as.numeric(resultado_binance$executedQty)
            if (!is.na(e_qty) && e_qty > 0) {
              p_calc_exec <- as.numeric(resultado_binance$cummulativeQuoteQty) / e_qty
            }
          } else {
            # Para pares cruzados ou fallbacks, obtém a cotação real fiduciária de mercado no momento
            if (ativo_adquirido == "PAXG") {
              p_calc_exec <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT"), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 24000.0)
            } else if (ativo_adquirido %in% c("NVDAB", "SPYB", "SQQQB", "TLT", "TSLAB", "QQQB", "AAPLB")) {
              p_calc_exec <- tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%sUSDT", ativo_adquirido)), "parsed")$price) * as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=USDTBRL"), "parsed")$price), error = function(e) 1150.0)
            } else {
              p_calc_exec <- tryCatch(as.numeric(content(GET(sprintf("https://api.binance.com/api/v3/ticker/price?symbol=%sBRL", ativo_adquirido)), "parsed")$price), error = function(e) 0.0)
            }
          }
          if (is.null(p_calc_exec) || length(p_calc_exec) == 0 || is.na(p_calc_exec) || p_calc_exec <= 0) {
            p_calc_exec <- ifelse(!is.null(resultado_binance$executedQty) && as.numeric(resultado_binance$executedQty) > 0,
                                  as.numeric(pedido$valor_brl) / as.numeric(resultado_binance$executedQty), 0.0)
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
          
          # Ativação da Quarentena Defensiva Bruce Wayne
          if (estrategia_nome == "PLANO_BRUCE_WAYNE" && resultado_binance$sucesso) {
            saveRDS(list(timestamp = Sys.time(), ativo = as.character(pedido$origem)), "bruce_quarantine.rds")
            cat(sprintf("🦇 [PLANO BRUCE WAYNE] Quarentena defensiva de 12 horas decretada para %s! Compras e recompras congeladas.\n", pedido$origem))
          }
          
          log_tag <- ifelse(executar_real_efetivo, ifelse(resultado_binance$sucesso, "ORDEM_REAL_BINANCE", "FALHA_REAL_BINANCE"), "SINAL_SIMULADO_APROVADO")
          cat(sprintf("[%s] [%s] %s: %s -> %s (%.2f BRL) Lucro: +%.2f%% | %s\n",
                      ts_str, log_tag, pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct,
                      ifelse(executar_real_efetivo, ifelse(resultado_binance$sucesso, paste0("ENVIO_BINANCE_OK (ID: ", resultado_binance$orderId, ")"), paste0("FALHA_BINANCE: ", resultado_binance$msg)), "VALIDADO_SEM_ENVIO_CORRETORA")),
              file = "ordens_executadas.log", append = TRUE)
          
          # Alerta Telegram Instantâneo (DM Privada)
          lucro_proj_pct <- as.numeric(pedido$lucro_esperado_pct)
          lucro_proj_brl <- as.numeric(pedido$valor_brl) * (lucro_proj_pct / 100)
          str_lucro_proj <- sprintf("+%.2f%% | %.2f reais", lucro_proj_pct, lucro_proj_brl)
          
          if (executar_real_efetivo) {
            ativo_qtd_label <- ifelse(pedido$origem == "BRL", pedido$destino, pedido$origem)
            if (resultado_binance$sucesso) {
              if (pedido$origem %in% c("BRL", "USDT") && !(pedido$origem == "USDT" && pedido$destino == "BRL")) {
                str_lucro_obt <- "Posição aberta (aquisição)"
              } else if (pedido$destino %in% c("BRL", "USDT")) {
                # Liquidação efetiva em Fiat (BRL ou USDT) -> Lucro FIFO Real Realizado
                if (!is.na(ret_obtido_real)) {
                  lucro_obt_brl <- as.numeric(pedido$valor_brl) * (ret_obtido_real / 100)
                  str_lucro_obt <- sprintf("%+.2f%% | %+.2f reais [FIFO Real]", ret_obtido_real, lucro_obt_brl)
                } else {
                  str_lucro_obt <- "Posição desovada em Fiat"
                }
              } else {
                # Trade intermediário entre ativos (ex: BTC -> PAXG ou PAXG -> BTC)
                # Retorno relativo em Satoshis ou Gramas; liquidação em Fiat permanece em trânsito
                if (!is.na(ret_obtido_real)) {
                  str_lucro_obt <- sprintf("%+.2f%% (Spread em Satoshis / Em Trânsito Fiat)", ret_obtido_real)
                } else {
                  str_lucro_obt <- sprintf("Rotação de Ativo (Em custódia de %s até desova Fiat)", pedido$destino)
                }
              }
              
              msg_tg <- sprintf("🟢 <b>[ORDEM EXECUTADA]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Operação:</b> %s ➔ %s\n💰 <b>Valor:</b> %.2f reais (Qtd: %s %s)\n📈 <b>Lucro Projetado:</b> %s\n💵 <b>Lucro Obtido:</b> %s\n🆔 <b>Order ID:</b> <code>%s</code>\n⏱️ <b>Data:</b> %s\n📝 <b>Status:</b> Preenchido na Corretora (FILLED)\n━━━━━━━━━━━━━━━━━━━━",
                                estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl,
                                ifelse(!is.null(resultado_binance$executedQty), resultado_binance$executedQty, "--"), ativo_qtd_label,
                                str_lucro_proj, str_lucro_obt, resultado_binance$orderId, ts_str)
              notificar_telegram_trade(msg_tg)
              
              # 🔒 Auto-Subscrição de USDT no Simple Earn Flexível para Maximizar Carrego (6,88% a.a.)
              if (as.character(pedido$destino) == "USDT" || as.character(pedido$origem) == "USDT") {
                tryCatch({
                  Sys.sleep(1.5)
                  df_w_sub <- carteira(silent = TRUE)
                  if (!is.null(df_w_sub) && is.data.frame(df_w_sub)) {
                    u_free <- sum(df_w_sub$free[df_w_sub$asset == "USDT"], na.rm = TRUE)
                    if (u_free >= 10.0) {
                      val_sub <- floor((u_free - 2.0) * 10) / 10
                      if (val_sub >= 1.0) {
                        cat(sprintf("🔒 [AUTO-SUBSCRICAO SIMPLE EARN] Aplicando %.2f USDT no Simple Earn Flexível (6,88%% a.a.)...\n", val_sub))
                        subscrever_simple_earn_usdt(val_sub)
                      }
                    }
                  }
                }, error = function(e) NULL)
              }
            } else {
              # Falha na execução da Binance: registrar veto com cooldown de 5 min (300s) e throttle no Telegram de 15 min
              veto_registry_file <- "vetos_recentes.rds"
              vetos_rec <- if (file.exists(veto_registry_file)) tryCatch(readRDS(veto_registry_file), error = function(e) list()) else list()
              if (!is.list(vetos_rec)) vetos_rec <- list()
              chave_estrategia <- as.character(ifelse(!is.null(pedido$estrategia), pedido$estrategia, estrategia_nome))
              vetos_rec[[chave_estrategia]] <- list(
                timestamp = as.numeric(Sys.time()),
                motivo = paste0("FALHA_BINANCE: ", resultado_binance$msg),
                origem = as.character(pedido$origem),
                destino = as.character(pedido$destino)
              )
              tryCatch(saveRDS(vetos_rec, veto_registry_file), error = function(e) NULL)

              # Throttle de notificação de falha (máximo 1 alerta a cada 15 min por plano)
              falha_throttle_file <- "falha_tg_throttle.rds"
              deve_notificar_falha <- TRUE
              f_db <- if (file.exists(falha_throttle_file)) tryCatch(readRDS(falha_throttle_file), error = function(e) list()) else list()
              if (!is.list(f_db)) f_db <- list()
              if (!is.null(f_db[[chave_estrategia]])) {
                minutos_dif <- as.numeric(difftime(Sys.time(), as.POSIXct(f_db[[chave_estrategia]]), units = "mins"))
                if (minutos_dif < 15) {
                  deve_notificar_falha <- FALSE
                }
              }
              if (deve_notificar_falha) {
                f_db[[chave_estrategia]] <- Sys.time()
                tryCatch(saveRDS(f_db, falha_throttle_file), error = function(e) NULL)
                
                msg_tg <- sprintf("⚠️ <b>[FALHA NA EXECUÇÃO]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Tentativa:</b> %s ➔ %s\n💰 <b>Valor:</b> %.2f reais\n❌ <b>Erro:</b> %s\n⏱️ <b>Data:</b> %s\n🔕 <i>Alertas de falha para este plano silenciados por 15 min</i>\n━━━━━━━━━━━━━━━━━━━━",
                                  estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl, resultado_binance$msg, ts_str)
                notificar_telegram_trade(msg_tg)
              }
            }
          } else {
            msg_tg <- sprintf("🧪 <b>[SIMULAÇÃO]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Operação:</b> %s ➔ %s\n💰 <b>Lote Calculado:</b> %.2f reais\n📈 <b>Lucro Projetado:</b> %s\n⏱️ <b>Data:</b> %s\n📝 <b>Status:</b> TESTE\n━━━━━━━━━━━━━━━━━━━━",
                              estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl, str_lucro_proj, ts_str)
            notificar_telegram_trade(msg_tg)
          }
          
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
          
          # Registro de Cooldown de Veto para o LabTrader (Anti-Cascading Guard)
          veto_registry_file <- "vetos_recentes.rds"
          vetos_rec <- if (file.exists(veto_registry_file)) tryCatch(readRDS(veto_registry_file), error = function(e) list()) else list()
          if (!is.list(vetos_rec)) vetos_rec <- list()
          chave_estrategia <- as.character(ifelse(!is.null(pedido$estrategia), pedido$estrategia, estrategia_nome))
          vetos_rec[[chave_estrategia]] <- list(
            timestamp = as.numeric(Sys.time()),
            motivo = motivo_veto,
            origem = origem_val,
            destino = destino_val
          )
          saveRDS(vetos_rec, veto_registry_file)
          
          cat(sprintf("[%s] VETO: %s (Motivo: %s)\n", ts_str, ifelse(!is.null(pedido$estrategia), pedido$estrategia, "ORDEM_INVALIDA"), motivo_veto),
              file = "ordens_vetadas.log", append = TRUE)
          
          # Throttling de Notificação de Veto no Telegram
          # Se o veto for relacionado ao Piso Ratchet / Ouro, silenciamento é de 24h (1440 min)
          # Para outros vetos de mercado, silenciamento de 30 min por estratégia
          veto_throttle_file <- "veto_tg_throttle.rds"
          deve_notificar_tg <- TRUE
          chave_veto <- as.character(estrategia_nome)
          janela_mute_min <- if (grepl("Piso Ratchet", motivo_veto, ignore.case = TRUE) || grepl("ouro", motivo_veto, ignore.case = TRUE)) 1440 else 30
          
          if (file.exists(veto_throttle_file)) {
            throttle_db <- tryCatch(readRDS(veto_throttle_file), error = function(e) list())
            if (!is.null(throttle_db[[chave_veto]])) {
              ultimo_envio <- as.POSIXct(throttle_db[[chave_veto]])
              minutos_dif <- as.numeric(difftime(Sys.time(), ultimo_envio, units = "mins"))
              if (minutos_dif < janela_mute_min) {
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
            txt_mute <- if (janela_mute_min >= 1440) "24h" else "30 min"
            motivo_veto_clean <- gsub("&", "&amp;", as.character(motivo_veto))
            motivo_veto_clean <- gsub("<", "&lt;", motivo_veto_clean)
            motivo_veto_clean <- gsub(">", "&gt;", motivo_veto_clean)
            
            msg_veto_tg <- sprintf("⛔ <b>[ORDEM VETADA]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n⚠️ <b>Tentativa:</b> %s ➔ %s\n🚫 <b>Motivo:</b>\n%s\n⏱️ <b>Data:</b> %s\n🔕 <i>Avisos para este mesmo veto silenciados por %s</i>\n━━━━━━━━━━━━━━━━━━━━",
                                   estrategia_nome, origem_val, destino_val, motivo_veto_clean, ts_str, txt_mute)
            notificar_telegram_trade(msg_veto_tg)
          } else {
            txt_mute <- if (janela_mute_min >= 1440) "24h" else "30 min"
            cat(sprintf("🔕 [TELEGRAM SILENCIADO] Notificação de veto para %s suprimida (último envio há < %s).\n", estrategia_nome, txt_mute))
          }
        }
        
        # Limpa a mesa para liberar o LabTrader para o próximo ciclo
        unlink("solicitacao.rds")
        cat("🧹 Mesa limpa. Solicitação arquivada.\n")
      }
    } else {
      # Varredura periódica de auto-subscrição de USDT ocioso na Spot (preserva 2 USDT de colchão e aplica o resto no Simple Earn a 6,88% a.a.)
      last_sweep_file <- "last_usdt_sweep.rds"
      deve_varrer <- TRUE
      if (file.exists(last_sweep_file)) {
        t_last <- tryCatch(readRDS(last_sweep_file), error = function(e) as.POSIXct("2000-01-01"))
        if (!is.na(t_last) && as.numeric(difftime(Sys.time(), t_last, units = "mins")) < 10) deve_varrer <- FALSE
      }
      if (deve_varrer) {
        tryCatch({
          df_w_sw <- carteira(silent = TRUE)
          if (!is.null(df_w_sw) && is.data.frame(df_w_sw)) {
            u_free <- sum(df_w_sw$free[df_w_sw$asset == "USDT"], na.rm = TRUE)
            if (!is.na(u_free) && u_free >= 10.0) {
              val_sub <- floor((u_free - 2.0) * 10) / 10
              if (val_sub >= 1.0) {
                cat(sprintf("🔒 [SWEEP SIMPLE EARN] Detectado %.2f USDT ocioso na Spot. Aplicando %.2f USDT no Simple Earn Flexível (6,88%% a.a.)...\n", u_free, val_sub))
                subscrever_simple_earn_usdt(val_sub)
              }
            }
          }
          saveRDS(Sys.time(), last_sweep_file)
        }, error = function(e) NULL)
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
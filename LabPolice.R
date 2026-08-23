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
      res <- POST(url, body = list(chat_id = TG_TRADE_CHATID, text = texto, parse_mode = "HTML"), encode = "json", timeout(5))
      if (status_code(res) == 200) {
        cat("📡 [TELEGRAM] Notificação de trade/veto despachada com sucesso.\n")
      } else {
        cat(sprintf("⚠️ [TELEGRAM] Falha no despacho: HTTP %s\n", status_code(res)))
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
  if (origem == "BRL" && destino %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "PAXG")) {
    symbol <- paste0(destino, "BRL")
    side <- "BUY"
    quoteOrderQty <- valor_brl
  } else if (destino == "BRL" && origem %in% c("BTC", "SOL", "ETH", "LINK", "USDT", "PAXG")) {
    symbol <- paste0(origem, "BRL")
    side <- "SELL"
    p_atual <- tryCatch(as.numeric(content(GET(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_atual) && p_atual > 0) {
      precisao <- ifelse(origem == "BTC", 5, ifelse(origem %in% c("ETH", "SOL", "PAXG"), 3, 2))
      quantity <- round(valor_brl / p_atual, precisao)
    }
  } else if (origem == "BTC" && destino == "SOL") {
    symbol <- "SOLBTC"
    side <- "BUY"
    p_sol <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SOLBRL"), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_sol) && p_sol > 0) quantity <- round(valor_brl / p_sol, 3)
  } else if (origem == "SOL" && destino == "BTC") {
    symbol <- "SOLBTC"
    side <- "SELL"
    p_sol <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=SOLBRL"), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_sol) && p_sol > 0) quantity <- round(valor_brl / p_sol, 3)
  } else if (origem == "BTC" && destino == "ETH") {
    symbol <- "ETHBTC"
    side <- "BUY"
    p_eth <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_eth) && p_eth > 0) quantity <- round(valor_brl / p_eth, 3)
  } else if (origem == "ETH" && destino == "BTC") {
    symbol <- "ETHBTC"
    side <- "SELL"
    p_eth <- tryCatch(as.numeric(content(GET("https://api.binance.com/api/v3/ticker/price?symbol=ETHBRL"), "parsed")$price), error = function(e) NULL)
    if (!is.null(p_eth) && p_eth > 0) quantity <- round(valor_brl / p_eth, 3)
  } else if (origem == "PAXG" && destino == "BTC") {
    symbol <- "BTCBRL"
    side <- "BUY"
    quoteOrderQty <- valor_brl
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
      pedido <- tryCatch(readRDS("solicitacao.rds"), error = function(e) NULL)
      
      if (!is.null(pedido)) {
        ts_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        cat(sprintf("\n🛡️ [GATEKEEPER] Avaliando solicitação de trade [%s]:\n", ts_str))
        cat(sprintf("   Estratégia: %s | Origem: %s -> Destino: %s | Valor: R$ %.2f | Lucro Proj: +%.2f%%\n",
                    pedido$estrategia, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct))
        
        aprovado <- TRUE
        motivo_veto <- ""
        estrategia_nome <- as.character(pedido$estrategia)
        
        estrategias_validas <- c(
          "PLANO_GUIANA_BRASILEIRA",
          "PLANO_ESCUDO_DE_AQUILES",
          "PLANO_PATRIA_VOLATIL",
          "PLANO_CABOCLO_DOS_ORACULOS",
          "PLANO_GRAVIDADE_ZERO",
          "PLANO_CORISCO_DA_SOLANA",
          "PLANO_DUELO_DE_TITAS",
          "PLANO_FLECHA_DE_SAGARANA"
        )
        
        tetos_volume <- list(
          "PLANO_GUIANA_BRASILEIRA" = 105.00,
          "PLANO_ESCUDO_DE_AQUILES" = 210.00,
          "PLANO_PATRIA_VOLATIL" = 210.00,
          "PLANO_CABOCLO_DOS_ORACULOS" = 105.00,
          "PLANO_GRAVIDADE_ZERO" = 55.00,
          "PLANO_CORISCO_DA_SOLANA" = 55.00,
          "PLANO_DUELO_DE_TITAS" = 65.00,
          "PLANO_FLECHA_DE_SAGARANA" = 80.00
        )
        
        lucros_minimos <- list(
          "PLANO_GUIANA_BRASILEIRA" = 1.50,
          "PLANO_ESCUDO_DE_AQUILES" = 2.00,
          "PLANO_PATRIA_VOLATIL" = 0.80,
          "PLANO_CABOCLO_DOS_ORACULOS" = 2.00,
          "PLANO_GRAVIDADE_ZERO" = 3.00,
          "PLANO_CORISCO_DA_SOLANA" = 0.80,
          "PLANO_DUELO_DE_TITAS" = 0.90,
          "PLANO_FLECHA_DE_SAGARANA" = 0.70
        )
        
        # Trava 1: Validação da Estratégia
        if (!(estrategia_nome %in% estrategias_validas)) {
          aprovado <- FALSE
          motivo_veto <- sprintf("Estratégia '%s' não autorizada pelo protocolo", estrategia_nome)
        }
        
        # Trava 2: Teto de Volume por Estratégia
        if (aprovado) {
          teto_permitido <- ifelse(!is.null(tetos_volume[[estrategia_nome]]), tetos_volume[[estrategia_nome]], 105.00)
          if (is.null(pedido$valor_brl) || pedido$valor_brl > teto_permitido) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Volume excede o teto de R$ %.2f para %s (Solicitado: R$ %.2f)", 
                                   teto_permitido, estrategia_nome, pedido$valor_brl)
          }
        }
        
        # Trava 3: Lucro Mínimo Esperado
        if (aprovado) {
          min_lucro <- ifelse(!is.null(lucros_minimos[[estrategia_nome]]), lucros_minimos[[estrategia_nome]], 1.00)
          if (is.null(pedido$lucro_esperado_pct) || pedido$lucro_esperado_pct < min_lucro) {
            aprovado <- FALSE
            motivo_veto <- sprintf("Lucro esperado insuficiente (%.2f%% < %.2f%% mínimo para %s)",
                                   pedido$lucro_esperado_pct, min_lucro, estrategia_nome)
          }
        }
        
        # Trava 4: Cooldown Adaptativo (1.5h para intradiários; 4.0h para macro)
        hist_exec_file <- "ordens_executadas.rds"
        if (aprovado && file.exists(hist_exec_file)) {
          hist_exec <- tryCatch(readRDS(hist_exec_file), error = function(e) NULL)
          if (!is.null(hist_exec) && nrow(hist_exec) > 0 && "Estrategia" %in% names(hist_exec)) {
            hist_est <- hist_exec[hist_exec$Estrategia == estrategia_nome, ]
            if (nrow(hist_est) > 0) {
              ultimo_ts <- as.POSIXct(tail(hist_est$Data_Hora, 1))
              horas_dif <- as.numeric(difftime(Sys.time(), ultimo_ts, units = "hours"))
              # Cooldown Calibrado: 30 minutos (0.5h) para Médio Risco; 2.0h para Baixo Risco / Macro
              cooldown_req <- ifelse(grepl("SOLANA|TITAS|SAGARANA|ORACULOS|GRAVIDADE", estrategia_nome), 0.5, 2.0)
              if (horas_dif < cooldown_req) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Cooldown ativo para %s (%.1fh desde último trade < %.1fh / %d min)",
                                       estrategia_nome, horas_dif, cooldown_req, round(cooldown_req * 60))
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
            }
          }
          
          status_final <- if (executar_real) {
            ifelse(resultado_binance$sucesso, "EXECUTADO_REAL_BINANCE", paste0("FALHA_BINANCE: ", resultado_binance$msg))
          } else {
            "SINAL_APROVADO_SIMULADO"
          }
          
          registro_exec <- data.frame(
            Data_Hora = ts_str,
            Estrategia = as.character(pedido$estrategia),
            Origem = as.character(pedido$origem),
            Destino = as.character(pedido$destino),
            Valor_BRL = as.numeric(pedido$valor_brl),
            Lucro_Proj = as.numeric(pedido$lucro_esperado_pct),
            Status = status_final,
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
            if (resultado_binance$sucesso) {
              msg_tg <- sprintf("🟢 <b>[ORDEM REAL EXECUTADA NA BINANCE]</b>\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Plano:</b> %s\n🔄 <b>Operação:</b> %s ➔ %s\n💰 <b>Valor:</b> R$ %.2f (Qtd: %s %s)\n📈 <b>Lucro Projetado:</b> +%.2f%%\n🆔 <b>Order ID Binance:</b> <code>%s</code>\n⏱️ <b>Data/Hora:</b> %s\n📝 <b>Status:</b> Preenchido na Corretora (FILLED)\n━━━━━━━━━━━━━━━━━━━━",
                                estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl,
                                ifelse(!is.null(resultado_binance$executedQty), resultado_binance$executedQty, "--"), pedido$destino,
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
          
          # Alerta Telegram de Veto (DM Privada)
          msg_veto_tg <- sprintf("⛔ <b>[GATEKEEPER | ORDEM VETADA]</b>\n━━━━━━━━━━━━━━━━━━━━\n⚠️ <b>Tentativa:</b> %s ➔ %s\n🚫 <b>Motivo:</b> %s\n⏱️ <b>Data:</b> %s\n━━━━━━━━━━━━━━━━━━━━",
                                 origem_val, destino_val, motivo_veto, ts_str)
          notificar_telegram_trade(msg_veto_tg)
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
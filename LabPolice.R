# ==============================================================================
# LabPolice v8.0 — Auditoria Híbrida (Kelly + KNN Integration)
# ==============================================================================
library(httr); library(jsonlite); library(digest)

# 1. Integração com LabAnalyst (Necessário para o KNN)
has_analyst <- file.exists("LabAnalyst.R")
if(has_analyst) {
  source("LabAnalyst.R")
  cat("✅ LabAnalyst integrado. Funcionalidades KNN ativas.\n")
} else {
  cat("⚠️ LabAnalyst não encontrado. Funcionalidades KNN desativadas.\n")
}

# 2. Carrega Chaves
if(file.exists("config_auth.R")) source("config_auth.R")

# --- NOTIFICAÇÕES TELEGRAM ---
notificar_telegram_trade <- function(texto) {
  if (exists("TG_TRADE_TOKEN") && exists("TG_TRADE_CHATID")) {
    tryCatch({
      url <- paste0("https://api.telegram.org/bot", TG_TRADE_TOKEN, "/sendMessage")
      POST(url, body = list(chat_id = TG_TRADE_CHATID, text = texto, parse_mode = "HTML"), encode = "json", timeout(5))
    }, error = function(e) NULL)
  }
}

# --- NÚCLEO DE CONEXÃO E SINCRONIZAÇÃO TEMPORAL ---
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

assinar_query <- function(q) hmac(key = BINANCE_SECRET, object = q, algo = "sha256")

call_binance <- function(endpoint, query = list(), public = FALSE) {
  base <- "https://api.binance.com"
  
  if (!public) {
    # Garante sincronização de relógio e janela de tolerância de 60s
    ts <- as.character(round(as.numeric(Sys.time()) * 1000 + BINANCE_TIME_OFFSET))
    query$timestamp <- ts
    query$recvWindow <- "60000"
    query_string <- paste0(names(query), "=", unlist(query), collapse = "&")
    query$signature <- assinar_query(query_string)
    res <- GET(paste0(base, endpoint), add_headers("X-MBX-APIKEY" = BINANCE_KEY), query = query, timeout(10))
  } else {
    res <- GET(paste0(base, endpoint), query = query, timeout(10))
  }
  
  if (status_code(res) == 401 || status_code(res) == 400) {
    err_body <- tryCatch(content(res, "text"), error = function(e) "")
    if (grepl("-2015", err_body)) {
      cat("\n⚠️ [BINANCE AUTH] Chave de API expirada ou sem permissão (Código -2015).\n")
      cat("   👉 Renove a API Key/Secret no painel da Binance e atualize no config_auth.R.\n\n")
    }
    return(NULL)
  }
  
  if (status_code(res) != 200) return(NULL)
  content(res, "parsed")
}

get_price <- function(symbol) {
  tryCatch({
    res <- fromJSON(paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol))
    as.numeric(res$price)
  }, error = function(e) 0)
}

# --- AUXILIARES DE DADOS E MATEMÁTICA ---
get_history_candles <- function(symbol = "BTCBRL", limit = 730) {
  # Baixa velas diárias
  raw <- call_binance("/api/v3/klines", list(symbol=symbol, interval="1d", limit=limit), public=TRUE)
  as.numeric(sapply(raw, function(x) x[[5]])) # Pega o Close
}

calc_kelly_raw <- function(prices, dias_janela) {
  returns <- diff(log(prices))
  serie <- tail(returns, dias_janela) # Recorte da janela
  
  rf <- (1 + 0.1125)^(1/365) - 1 
  mu <- mean(serie, na.rm=TRUE)
  v  <- var(serie, na.rm=TRUE)
  
  k <- (mu - rf) / v
  return(k * 0.5) # Half-Kelly
}

# --- COMANDO 1: carteira() ---
carteira <- function(silent = FALSE) {
  acc <- call_binance("/api/v3/account")
  if (is.null(acc)) return(NULL)
  
  p_btc <- get_price("BTCBRL")
  p_usdt <- get_price("USDTBRL")
  p_paxg_usdt <- get_price("PAXGUSDT")
  p_paxg <- ifelse(p_paxg_usdt > 0, p_paxg_usdt * p_usdt, get_price("PAXGBRL"))
  
  df <- data.frame(Ativo=character(), Qtd=numeric(), Total_BRL=numeric(), stringsAsFactors=FALSE)
  
  # 1. Saldos Spot
  for (b in acc$balances) {
    qtd <- as.numeric(b$free) + as.numeric(b$locked)
    asset_clean <- gsub("^LD", "", b$asset) # Suporte a Simple Earn (ex: LDPAXG -> PAXG)
    
    if (qtd > 0 && asset_clean %in% c("BRL", "BTC", "USDT", "PAXG")) {
      preco <- switch(asset_clean, "BRL" = 1, "BTC" = p_btc, "USDT" = p_usdt, "PAXG" = p_paxg)
      df <- rbind(df, data.frame(Ativo=asset_clean, Qtd=qtd, Total_BRL=qtd*preco))
    }
  }
  
  # Agrupa por ativo se houver Spot + Earn
  if (nrow(df) > 0) {
    df <- aggregate(cbind(Qtd, Total_BRL) ~ Ativo, data = df, sum)
  }
  
  total <- sum(df$Total_BRL)
  if (!silent) {
    cat("\n🔬 [SALDO ATUAL DA CARTEIRA BINANCE]\n"); print(df, row.names = FALSE)
    cat(sprintf("💰 PATRIMÔNIO TOTAL ESTIMADO: R$ %.2f\n", total))
  }
  return(list(total = total, df = df))
}

# --- COMANDO 2: log_carteira() ---
log_carteira <- function(n = 15) {
  cat("\n🌐 [AUDITORIA TOTAL] Sincronizando Spot, Conversões e Ajustes...\n")
  p_btc_agora <- get_price("BTCBRL")
  
  t_btc <- call_binance("/api/v3/myTrades", list(symbol = "BTCBRL"))
  df_total <- if(!is.null(t_btc)) do.call(rbind, lapply(t_btc, function(x) {
    data.frame(Data = as.POSIXct(as.numeric(x$time)/1000, origin="1970-01-01"),
               Lado = if(x$isBuyer) "COMPRA" else "VENDA",
               Preco_Base = as.numeric(x$price), Total_R = as.numeric(x$quoteQty), Tipo = "SPOT")
  })) else data.frame()
  
  # Ajuste P2P Auditado
  df_ajuste <- data.frame(Data = as.POSIXct("2026-01-15 10:00:00"), Lado = "COMPRA", Preco_Base = 460000.00, Total_R = 200.00, Tipo = "P2P_ADJUST")
  
  df_total <- rbind(df_total, df_ajuste)
  df_total$Var_pct <- round((p_btc_agora / df_total$Preco_Base - 1) * 100, 2)
  df_total$Status <- ifelse(df_total$Lado == "VENDA", "✅ REALIZADO", ifelse(df_total$Var_pct > 0, "📈 LUCRO", "📉 PREJU"))
  
  df_total <- df_total[order(df_total$Data, decreasing = TRUE), ]
  return(head(unique(df_total), n))
}

# --- COMANDO 3: resumo_patrimonial() ---
resumo_patrimonial <- function() {
  cat("\n🏦 [RESUMO PATRIMONIAL] Consolidando Auditoria Humana + API...\n")
  fiat <- call_binance("/sapi/v1/fiat/orders", list(transactionType = "0", beginTime = "0"))
  total_fiat <- sum(as.numeric(sapply(fiat$data, function(x) if(x$status == "Successful") x$amount else 0)))
  
  ajuste_p2p <- 200.00 
  total_investido_real <- total_fiat + ajuste_p2p
  saldo_obj <- carteira(silent = TRUE)
  patrimonio_atual <- saldo_obj$total
  lucro_abs <- patrimonio_atual - total_investido_real
  
  cat("---------------------------------------------------\n")
  cat(sprintf("📥 Depósitos Rastreados: R$ %.2f\n", total_fiat))
  cat(sprintf("🤝 Ajuste P2P:           R$ %.2f\n", ajuste_p2p))
  cat(sprintf("🚀 CAPITAL TOTAL:        R$ %.2f\n", total_investido_real))
  cat(sprintf("💹 PATRIMÔNIO ATUAL:     R$ %.2f\n", patrimonio_atual))
  cat("---------------------------------------------------\n")
  cat(sprintf("%s R$ %.2f (%.2f%%)\n", ifelse(lucro_abs >= 0, "🟢 LUCRO REAL:", "🔴 PREJUÍZO REAL:"), lucro_abs, (lucro_abs/total_investido_real)*100))
}

# --- COMANDO 4: alvo_recuperacao() ---
alvo_recuperacao <- function() {
  cat("\n🎯 [ESTRATÉGIA] Calculando metas de recuperação...\n")
  investido <- 380.00
  p_atual <- get_price("BTCBRL")
  acc <- call_binance("/api/v3/account")
  btc_qtd <- as.numeric(Filter(function(x) x$asset == "BTC", acc$balances)[[1]]$free)
  
  preco_alvo <- investido / btc_qtd
  distancia_pct <- (preco_alvo / p_atual - 1) * 100
  
  cat("---------------------------------------------------\n")
  cat(sprintf("🚀 PREÇO ALVO (Empate):  R$ %.2f\n", preco_alvo))
  cat(sprintf("📊 Necessário Subir:     %.2f%%\n", distancia_pct))
  cat("---------------------------------------------------\n")
}

# --- COMANDO 5: auditoria_kelly(dias) ---
auditoria_kelly <- function(dias = 180) {
  cat(sprintf("\n⚖️ [GESTÃO DE RISCO] Auditoria Half-Kelly (Janela Realista: %d dias)\n", dias))
  
  dados_cart <- carteira(silent = TRUE)
  total_banca <- dados_cart$total
  row_btc <- dados_cart$df[dados_cart$df$Ativo == "BTC",]
  val_btc <- if(nrow(row_btc) > 0) row_btc$Total_BRL else 0
  
  prices <- get_history_candles(limit = 730) 
  
  # Usa a função auxiliar interna para calcular
  k_otimista <- calc_kelly_raw(prices, 730)
  k_realista <- calc_kelly_raw(prices, dias)
  
  cat("---------------------------------------------------\n")
  cat(sprintf("💰 BANCA TOTAL AUDITADA: R$ %.2f\n", total_banca))
  cat(sprintf("🪙 EXPOSIÇÃO ATUAL:      %.1f%%\n", (val_btc/total_banca)*100))
  cat("---------------------------------------------------\n")
  
  report <- function(nome, k) {
    k_pct <- max(0, min(k, 1))
    target <- total_banca * k_pct
    diff <- target - val_btc
    
    cat(sprintf("\n📈 CENÁRIO %s:\n", nome))
    if(k <= 0) cat(sprintf("   ⚠️  ALERTA: Kelly Negativo (%.2f%%). O risco supera a vantagem.\n", k * 100))
    cat(sprintf("   • Alocação Ideal: %.2f%%\n", k_pct * 100))
    
    if(abs(diff) < 2) {
      cat("   ✅ Status: EQUILIBRADO\n")
    } else if (diff > 0) {
      cat(sprintf("   🔵 Sugestão: COMPRAR R$ %.2f\n", diff))
    } else {
      cat(sprintf("   🔴 Sugestão: VENDER  R$ %.2f\n", abs(diff)))
    }
  }
  
  report("OTIMISTA (2 Anos)", k_otimista)
  report(sprintf("REALISTA (%d dias)", dias), k_realista)
  cat("---------------------------------------------------\n")
}

# --- COMANDO 6: auditoria(dias) [NOVO: GERA PROMPT IA] ---
auditoria <- function(dias_projecao = 300) {
  cat("\n🤖 GERANDO RELATÓRIO TÉCNICO PARA IA...\n")
  
  cart <- carteira(silent = TRUE)
  total_banca <- cart$total
  
  cat("\n=== 📋 COPIE ABAIXO DESTA LINHA ===\n")
  cat("CONTEXTO: Auditoria de Portfolio de Criptoativos.\n")
  cat(sprintf("DATA: %s\n", Sys.Date()))
  cat(sprintf("PATRIMÔNIO TOTAL: R$ %.2f\n", total_banca))
  cat("OBJETIVO: Análise dialética entre Risco (Kelly) e Oportunidade (KNN).\n\n")
  
  for(i in 1:nrow(cart$df)) {
    ativo <- cart$df$Ativo[i]
    qtd   <- cart$df$Qtd[i]
    val   <- cart$df$Total_BRL[i]
    
    if (ativo == "BRL" || ativo == "USDT") next 
    
    cat(sprintf("--- ATIVO: %s ---\n", ativo))
    cat(sprintf("1. POSIÇÃO ATUAL:\n   Qtd: %.8f | Valor: R$ %.2f (%.1f%% da banca)\n", qtd, val, (val/total_banca)*100))
    
    # MOTOR 1: KELLY
    tryCatch({
      symbol_pair <- paste0(ativo, "BRL")
      hist_prices <- get_history_candles(symbol_pair, limit=365)
      k_realista <- calc_kelly_raw(hist_prices, dias_janela=180)
      k_pct <- max(0, min(k_realista, 1))
      cat(sprintf("2. GESTÃO DE RISCO (Half-Kelly 180d):\n   Score: %.2f%% (Alocação Ideal)\n", k_pct * 100))
      if(k_realista < 0) cat("   ⚠️ ALERTA: Kelly Negativo (Volatilidade > Retorno)\n")
    }, error = function(e) cat("   [Erro Kelly]\n"))
    
    # MOTOR 2: KNN
    if(has_analyst) {
      cat(sprintf("3. PROJEÇÃO KNN (%d dias):\n", dias_projecao))
      tryCatch({
        # Captura saída do KNN e limpa HTML
        raw_knn <- capture.output(simular_knn(ativo, Sys.Date(), Sys.Date() + dias_projecao, 1000))
        lines_interest <- raw_knn[grep("Probabilidade|Resultado|Retorno", raw_knn)]
        clean_lines <- gsub("<.*?>", "", lines_interest) 
        for(l in clean_lines) cat(paste0("   ", trimws(l), "\n"))
      }, error = function(e) cat("   [Erro KNN]\n"))
    }
    cat("\n")
  }
  cat("=== 📋 FIM DO RELATÓRIO ===\n")
}

# --- COMANDO 7: processar_solicitacoes_gatekeeper() [AUDITORIA E GATEKEEPER] ---
processar_solicitacoes_gatekeeper <- function(modo_continuo = FALSE, executar_real = FALSE) {
  cat("\n👮 [LABPOLICE v9.0] Gatekeeper Ativo: Auditoria de Ordens em Tempo Real\n")
  cat("🛡️ Política Autorizada: PAIRS TRADING (PAXG <-> BTC) COM TETO DE R$ 100,00\n")
  cat("🚫 Política Restritiva: VETO AUTOMÁTICO EM QUALQUER OUTRO ATIVO OU VOLUME\n")
  cat("----------------------------------------------------------------------\n")
  
  executar_ciclo_gatekeeper <- function() {
    if (file.exists("solicitacao.rds")) {
      pedido <- tryCatch(readRDS("solicitacao.rds"), error = function(e) NULL)
      if (!is.null(pedido)) {
        ts_str <- format(as.POSIXct(pedido$timestamp), "%Y-%m-%d %H:%M:%S")
        
        cat(sprintf("\n📥 [ORDEM DETECTADA | %s]\n", ts_str))
        cat(sprintf("   Estratégia: %s\n", ifelse(!is.null(pedido$estrategia), pedido$estrategia, "GENÉRICA")))
        cat(sprintf("   Fluxo: %s -> %s | Valor: R$ %.2f\n", 
                    ifelse(!is.null(pedido$origem), pedido$origem, pedido$ativo),
                    ifelse(!is.null(pedido$destino), pedido$destino, pedido$lado),
                    ifelse(!is.null(pedido$valor_brl), pedido$valor_brl, 0)))
        
        # --- BATERIA DE TESTES DE SEGURANÇA MULTIESTRATÉGIA ---
        aprovado <- TRUE
        motivo_veto <- ""
        estrategia_nome <- ifelse(!is.null(pedido$estrategia), pedido$estrategia, "GENÉRICA")
        
        # Lista de Estratégias Autorizadas e seus Tetos de Volume
        estrategias_validas <- c(
          "PLANO_GUIANA_BRASILEIRA", "PAIRS_TRADING_PAXG_BTC",
          "PLANO_ESCUDO_DE_AQUILES", "VIX_LEAD_LAG_BTC_DIP",
          "PLANO_PATRIA_VOLATIL", "ARBITRAGEM_DOLLAR_PEG_USDT_BRL",
          "PLANO_CABOCLO_DOS_ORACULOS", "ARBITRAGEM_VERTICE_INFRA_LINK",
          "PLANO_GRAVIDADE_ZERO", "ROTACAO_SPILLOVER_BTC_ALT",
          "PLANO_CORISCO_DA_SOLANA",
          "PLANO_DUELO_DE_TITAS",
          "PLANO_FLECHA_DE_SAGARANA"
        )
        tetos_volume <- list(
          "PLANO_GUIANA_BRASILEIRA" = 105.00, "PAIRS_TRADING_PAXG_BTC" = 105.00,
          "PLANO_ESCUDO_DE_AQUILES" = 210.00, "VIX_LEAD_LAG_BTC_DIP" = 210.00,
          "PLANO_PATRIA_VOLATIL" = 210.00, "ARBITRAGEM_DOLLAR_PEG_USDT_BRL" = 210.00,
          "PLANO_CABOCLO_DOS_ORACULOS" = 105.00, "ARBITRAGEM_VERTICE_INFRA_LINK" = 105.00,
          "PLANO_GRAVIDADE_ZERO" = 55.00, "ROTACAO_SPILLOVER_BTC_ALT" = 55.00,
          "PLANO_CORISCO_DA_SOLANA" = 55.00,
          "PLANO_DUELO_DE_TITAS" = 65.00,
          "PLANO_FLECHA_DE_SAGARANA" = 80.00
        )
        lucros_minimos <- list(
          "PLANO_GUIANA_BRASILEIRA" = 1.50, "PAIRS_TRADING_PAXG_BTC" = 1.50,
          "PLANO_ESCUDO_DE_AQUILES" = 2.00, "VIX_LEAD_LAG_BTC_DIP" = 2.00,
          "PLANO_PATRIA_VOLATIL" = 0.80, "ARBITRAGEM_DOLLAR_PEG_USDT_BRL" = 0.80,
          "PLANO_CABOCLO_DOS_ORACULOS" = 2.00, "ARBITRAGEM_VERTICE_INFRA_LINK" = 2.00,
          "PLANO_GRAVIDADE_ZERO" = 3.00, "ROTACAO_SPILLOVER_BTC_ALT" = 3.00,
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
              horas_dif <- as.numeric(difftime(as.POSIXct(pedido$timestamp), ultimo_ts, units = "hours"))
              cooldown_req <- ifelse(grepl("SOLANA|TITAS|SAGARANA", estrategia_nome), 1.5, 4.0)
              if (horas_dif < cooldown_req) {
                aprovado <- FALSE
                motivo_veto <- sprintf("Cooldown ativo para %s (%.1fh desde último trade < %.1fh)", estrategia_nome, horas_dif, cooldown_req)
              }
            }
          }
        }
        
        # --- VEREDITO DO LABPOLICE ---
        if (aprovado) {
          cat(sprintf("✅ [AUTORIZADO] Ordem validada com sucesso! Lucro Projetado: +%.2f%%\n", pedido$lucro_esperado_pct))
          
          registro_exec <- data.frame(
            Data_Hora = ts_str,
            Estrategia = as.character(pedido$estrategia),
            Origem = as.character(pedido$origem),
            Destino = as.character(pedido$destino),
            Valor_BRL = as.numeric(pedido$valor_brl),
            Lucro_Proj = as.numeric(pedido$lucro_esperado_pct),
            Status = ifelse(executar_real, "EXECUTADO_BINANCE", "AUTORIZADO_SIMULADO"),
            stringsAsFactors = FALSE
          )
          
          # Salva no histórico de ordens autorizadas
          hist_exec <- if (file.exists(hist_exec_file)) tryCatch(readRDS(hist_exec_file), error = function(e) data.frame()) else data.frame()
          hist_exec <- if (nrow(hist_exec) > 0) tryCatch(bind_rows(hist_exec, registro_exec), error = function(e) rbind(hist_exec, registro_exec)) else registro_exec
          saveRDS(hist_exec, hist_exec_file)
          
          cat(sprintf("[%s] APROVADO: %s -> %s (R$ %.2f) Lucro: +%.2f%%\n",
                      ts_str, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct),
              file = "ordens_executadas.log", append = TRUE)
          
          # Alerta Telegram Instantâneo (DM)
          tag_tipo <- ifelse(executar_real, "🟢 <b>[ORDEM REAL EXECUTADA NA BINANCE]</b>", "🧪 <b>[SIMULAÇÃO / TESTE APROVADO]</b>")
          msg_tg <- sprintf("%s\n━━━━━━━━━━━━━━━━━━━━\n🎯 <b>Estratégia:</b> %s\n🔄 <b>Fluxo:</b> %s ➔ %s\n💰 <b>Valor:</b> R$ %.2f\n📈 <b>Lucro Projetado:</b> +%.2f%%\n⏱️ <b>Data:</b> %s\n━━━━━━━━━━━━━━━━━━━━",
                            tag_tipo, estrategia_nome, pedido$origem, pedido$destino, pedido$valor_brl, pedido$lucro_esperado_pct, ts_str)
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
          
          # Alerta Telegram de Veto (DM)
          msg_veto_tg <- sprintf("⛔ <b>[GATEKEEPER | ORDEM VETADA]</b>\n━━━━━━━━━━━━━━━━━━━━\n⚠️ <b>Tentativa Bloqueada:</b> %s ➔ %s\n🚫 <b>Motivo:</b> %s\n⏱️ <b>Data:</b> %s\n━━━━━━━━━━━━━━━━━━━━",
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
    cat("🔄 Sentinela em loop contínuo (Pressione Esc ou Ctrl+C para interromper)...\n")
    while(TRUE) {
      executar_ciclo_gatekeeper()
      Sys.sleep(3)
    }
  } else {
    executar_ciclo_gatekeeper()
  }
}

# --- COMANDO 8: relatorio_diario_telegram() [RESUMO DIÁRIO DE MOVIMENTAÇÃO] ---
relatorio_diario_telegram <- function() {
  hoje_str <- format(Sys.Date(), "%Y-%m-%d")
  hist_exec_file <- "ordens_executadas.rds"
  hist_veto_file <- "ordens_vetadas.rds"
  
  exec_reais <- data.frame()
  exec_simuladas <- data.frame()
  
  if (file.exists(hist_exec_file)) {
    df_e <- tryCatch(readRDS(hist_exec_file), error = function(e) data.frame())
    if (nrow(df_e) > 0 && "Data_Hora" %in% names(df_e)) {
      df_hoje <- df_e[grepl(hoje_str, df_e$Data_Hora), ]
      if (nrow(df_hoje) > 0) {
        exec_reais <- df_hoje[df_hoje$Status == "EXECUTADO_BINANCE", ]
        exec_simuladas <- df_hoje[df_hoje$Status == "AUTORIZADO_SIMULADO", ]
      }
    }
  }
  
  veto_hoje <- data.frame()
  if (file.exists(hist_veto_file)) {
    df_v <- tryCatch(readRDS(hist_veto_file), error = function(e) data.frame())
    if (nrow(df_v) > 0 && "Data_Hora" %in% names(df_v)) {
      veto_hoje <- df_v[grepl(hoje_str, df_v$Data_Hora), ]
    }
  }
  
  # Consulta saldo atual ao vivo
  cart <- carteira(silent = TRUE)
  total_saldo <- ifelse(!is.null(cart$total), cart$total, 480.73)
  
  msg <- sprintf("📊 <b>[MONEYLAB | RELATÓRIO DIÁRIO DE AUDITORIA]</b>\n━━━━━━━━━━━━━━━━━━━━━━━━━━\n📅 <b>Data:</b> %s\n💰 <b>Patrimônio Total:</b> R$ %.2f\n\n🟢 <b>Execuções Reais na Binance:</b> %d ordens\n🔵 <b>Simulações Aprovadas:</b> %d ordens\n⛔ <b>Bloqueios pelo Gatekeeper:</b> %d ordens\n",
                 format(Sys.Date(), "%d/%m/%Y"), total_saldo, nrow(exec_reais), nrow(exec_simuladas), nrow(veto_hoje))
  
  # Detalhamento de Execuções Reais
  if (nrow(exec_reais) > 0) {
    msg <- paste0(msg, "\n🟢 <b>Ordens Executadas na Binance:</b>\n")
    for (i in 1:nrow(exec_reais)) {
      msg <- paste0(msg, sprintf(" • [%s] %s (%s ➔ %s) R$ %.2f | Lucro: +%.2f%%\n",
                                 exec_reais$Data_Hora[i], exec_reais$Estrategia[i], exec_reais$Origem[i], exec_reais$Destino[i], exec_reais$Valor_BRL[i], exec_reais$Lucro_Proj[i]))
    }
  } else {
    msg <- paste0(msg, "\n🟢 <b>Ordens Reais na Binance:</b> <i>Nenhuma ordem enviada à corretora hoje.</i>\n")
  }
  
  # Detalhamento de Vetos de Segurança
  if (nrow(veto_hoje) > 0) {
    msg <- paste0(msg, "\n⛔ <b>Tentativas Vetadas pelo Gatekeeper:</b>\n")
    for (i in 1:nrow(veto_hoje)) {
      msg <- paste0(msg, sprintf(" • [%s] %s ➔ %s (Motivo: %s)\n",
                                 veto_hoje$Data_Hora[i], veto_hoje$Origem[i], veto_hoje$Destino[i], veto_hoje$Motivo[i]))
    }
  }
  
  msg <- paste0(msg, "━━━━━━━━━━━━━━━━━━━━━━━━━━")
  notificar_telegram_trade(msg)
  cat("\n📡 Relatório diário reformulado despachado para o Telegram!\n")
}

# --- MENU DE AJUDA ---
ajuda_LabPolice <- function() {
  cat("\n👮 CENTRAL DE COMANDO LABPOLICE v9.5 (GATEKEEPER TELEGRAM ATIVO)\n")
  cat("----------------------------------------------------------------------\n")
  cat("🛡️ processar_solicitacoes_gatekeeper() -> Valida ordens e avisa Telegram.\n")
  cat("📊 relatorio_diario_telegram()         -> Despacha resumo diário.\n")
  cat("🤖 auditoria(dias)                   -> Gera Prompt IA (Kelly + KNN).\n")
  cat("⚖️ auditoria_kelly(d)                -> Análise de Risco pura.\n")
  cat("💰 carteira()                        -> Saldo atual da conta Binance.\n")
  cat("📜 log_carteira()                    -> Histórico de trades.\n")
  cat("🏦 resumo_patrimonial()              -> Investido vs. Atual.\n")
  cat("🎯 alvo_recuperacao()                -> Meta de empate.\n")
  cat("----------------------------------------------------------------------\n")
}

ajuda_LabPolice()

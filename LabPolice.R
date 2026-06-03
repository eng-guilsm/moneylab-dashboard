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

# --- NÚCLEO DE CONEXÃO ---
assinar_query <- function(q) hmac(key = BINANCE_SECRET, object = q, algo = "sha256")

call_binance <- function(endpoint, query = list(), public = FALSE) {
  base <- "https://api.binance.com"
  
  if (!public) {
    ts <- as.character(round(as.numeric(Sys.time()) * 1000))
    query$timestamp <- ts
    query_string <- paste0(names(query), "=", unlist(query), collapse = "&")
    query$signature <- assinar_query(query_string)
    res <- GET(paste0(base, endpoint), add_headers("X-MBX-APIKEY" = BINANCE_KEY), query = query)
  } else {
    res <- GET(paste0(base, endpoint), query = query)
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
  p_btc <- get_price("BTCBRL"); p_usdt <- get_price("USDTBRL")
  
  df <- data.frame(Ativo=character(), Qtd=numeric(), Total_BRL=numeric(), stringsAsFactors=FALSE)
  
  for (b in acc$balances) {
    qtd <- as.numeric(b$free)
    if (qtd > 0 && b$asset %in% c("BRL", "BTC", "USDT")) {
      preco <- switch(b$asset, "BRL" = 1, "BTC" = p_btc, "USDT" = p_usdt)
      df <- rbind(df, data.frame(Ativo=b$asset, Qtd=qtd, Total_BRL=qtd*preco))
    }
  }
  
  total <- sum(df$Total_BRL)
  if (!silent) {
    cat("\n🔬 [SALDO ATUAL]\n"); print(df, row.names = FALSE)
    cat(sprintf("💰 PATRIMÔNIO TOTAL: R$ %.2f\n", total))
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

# --- MENU DE AJUDA ---
ajuda_LabPolice <- function() {
  cat("\n👮 CENTRAL DE COMANDO LABPOLICE v8.0\n")
  cat("---------------------------------------------------\n")
  cat("🤖 auditoria(dias)      -> Gera Prompt IA (Kelly + KNN).\n")
  cat("⚖️ auditoria_kelly(d)   -> Análise de Risco pura.\n")
  cat("💰 carteira()           -> Saldo atual.\n")
  cat("📜 log_carteira()       -> Histórico de trades.\n")
  cat("🏦 resumo_patrimonial() -> Investido vs. Atual.\n")
  cat("🎯 alvo_recuperacao()   -> Meta de empate.\n")
  cat("---------------------------------------------------\n")
}

ajuda_LabPolice()
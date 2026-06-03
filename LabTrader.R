# ==============================================================================
# BLOCO 1: CONFIGURAÇÃO E AMBIENTE
# ==============================================================================
library(httr)
library(jsonlite)

# --- PARÂMETROS DA ESTRATÉGIA ---
ALVO_LUCRO    <- 1.008  # Vende se lucrar 0.8% (Scalping rápido)
ALVO_RECOMPRA <- 0.950  # Compra se cair 2% abaixo do PM (Preço Médio)

# Tempo de espera entre varreduras (segundos)
DELAY_LOOP <- 30 

cat("\n🤖 LabTrader v2.0 Iniciado.\n")
cat("🎯 Estratégia: Venda +0.8% | Recompra -2.0%\n")
cat("---------------------------------------------------\n")

# ==============================================================================
# BLOCO 2: UTILITÁRIOS DE COTAÇÃO
# ==============================================================================
obter_preco_atual <- function(symbol) {
  url <- paste0("https://api.binance.com/api/v3/ticker/price?symbol=", symbol)
  
  resp <- tryCatch({
    content(GET(url, timeout(10)), as="text")
  }, error = function(e) return(NULL))
  
  if (is.null(resp)) return(NULL)
  
  json <- fromJSON(resp)
  return(as.numeric(json$price))
}

# ==============================================================================
# BLOCO 3: NÚCLEO DE DECISÃO (LOOP ESTRATÉGICO)
# ==============================================================================
while(TRUE) {
  tryCatch({
    # 3.1 Verificação de "Mesa Limpa"
    # Se já existe um pedido na mesa, o Trader espera o Police trabalhar
    if (file.exists("solicitacao.rds")) {
      cat("⏳ Aguardando LabPolice processar ordem anterior...\n")
      Sys.sleep(5)
      next # Pula para o próximo ciclo
    }
    
    # 3.2 Leitura da Carteira
    if (!file.exists("carteira.rds")) {
      cat("⚠️ carteira.rds não encontrado. Aguardando sincronização...\n")
      Sys.sleep(10)
      next
    }
    
    carteira <- readRDS("carteira.rds")
    ativos_monitorados <- names(carteira) # Lista automática (Ex: "BTC", "USDT", "ETH")
    
    cat("\n🔍 Varrendo Mercado [", format(Sys.time(), "%H:%M:%S"), "]...\n")
    
    # ==========================================================================
    # BLOCO 4: ITERAÇÃO DINÂMICA POR ATIVO
    # ==========================================================================
    for (ativo in ativos_monitorados) {
      
      # Ignora se for apenas um marcador de sistema ou BRL
      if (ativo == "BRL") next 
      
      # Dados do Ativo na Carteira
      dados_ativo <- carteira[[ativo]]
      pm_atual <- as.numeric(dados_ativo$pm)
      
      # Se PM for zero ou nulo (erro de dados), pula
      if (is.null(pm_atual) || pm_atual <= 0) next
      
      # Obtém cotação em tempo real
      par <- paste0(ativo, "BRL")
      preco_mercado <- obter_preco_atual(par)
      
      if (is.null(preco_mercado)) {
        cat("⚠️ Falha ao obter preço de", par, "\n")
        next
      }
      
      # --- CÁLCULO DE DISTÂNCIA (%) ---
      ratio <- preco_mercado / pm_atual
      lucro_pct <- (ratio - 1) * 100
      
      cat(sprintf("   > %s: R$ %.2f (PM: %.2f) | Var: %+.2f%%\n", 
                  ativo, preco_mercado, pm_atual, lucro_pct))
      
      # --- LÓGICA DE GATILHO ---
      acao <- NULL
      
      # 1. Regra de VENDA (Gain)
      if (preco_mercado >= pm_atual * ALVO_LUCRO) {
        cat("   💎 ALVO ATINGIDO! Lucro detectado em", ativo, "\n")
        acao <- "SELL"
      }
      
      # 2. Regra de COMPRA (DCA/Recompra)
      if (preco_mercado <= pm_atual * ALVO_RECOMPRA) {
        cat("   📉 QUEDA OPORTUNA! Preço abaixo do alvo em", ativo, "\n")
        acao <- "BUY"
      }
      
      # --- ENVIO DO PEDIDO ---
      if (!is.null(acao)) {
        pedido <- list(
          ativo = ativo,
          lado = acao,
          preco_atual = preco_mercado,
          timestamp = Sys.time()
        )
        
        saveRDS(pedido, "solicitacao.rds")
        cat("📨 Ordem de", acao, "enviada para o LabPolice. Pausando Trader...\n")
        
        # Pausa longa para garantir que o Police pegue e processe
        Sys.sleep(15) 
        break # Sai do loop 'for' para não mandar duas ordens ao mesmo tempo
      }
    }
    
    Sys.sleep(DELAY_LOOP)
    
  }, error = function(e) {
    cat("❌ Erro Crítico no Loop:", conditionMessage(e), "\n")
    Sys.sleep(10)
  })
}
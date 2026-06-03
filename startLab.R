# ==============================================================================
# SISTEMA CENTRAL: startLab.R (Orquestrador do MoneyLab)
# Versão: 12.0 | Status: Ordem de Escopo e Proteção de Fila Corrigidas
# ==============================================================================
message(">>> [SISTEMA CENTRAL] Iniciando orquestração unificada...")

# Forçar pacotes essenciais para evitar conflito de namespace
options(repos = c(CRAN = "https://cloud.r-project.org"), xts.warn_dplyr_breaks_lag = FALSE)

# Check if running in Docker container
if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
  LOCAL_R_LIB <- file.path(getwd(), "r-lib")
  if(!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
  .libPaths(unique(c(LOCAL_R_LIB, .libPaths())))
}

pkgs_start <- c("dplyr", "tidyr", "jsonlite", "quantmod", "lubridate")
invisible(lapply(pkgs_start, function(p) {
  if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
    if(!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p, quiet = TRUE)
  }
  library(p, character.only = TRUE)
}))

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO INVERSO DE DEPENDÊNCIAS (FIX DE NAMESPACE)
# ------------------------------------------------------------------------------
# Carregamos primeiro a inteligência e os coletores, e por ÚLTIMO o Front-End (Bot),
# garantindo que todas as funções matemáticas já existam na memória da máquina.
source("LabFariaLimer.R") 
source("LabAnalyst.R")   
source("LabInvest.R")    

# ------------------------------------------------------------------------------
# 1.1 LIMPEZA DE FILA DO TELEGRAM (RASTREIO EXTERNO DE ID)
# ------------------------------------------------------------------------------
message(">>> [TELEGRAM] Limpando mensagens antigas para evitar loop...")

# Garantido como tipo numérico estável para evitar estouro de pilha
tg_last_update_id <- 0

tryCatch({
  last_update <- updater$bot$get_updates(offset = -1L, limit = 1L, timeout = 5L)
  
  if (length(last_update) > 0) {
    tg_last_update_id <- as.numeric(last_update[[1]]$update_id)
    message("    ✅ Fila limpa. Último ID registrado: ", tg_last_update_id)
  } else {
    message("    ✅ Fila já estava vazia.")
  }
}, error = function(e) {
  message("    ⚠️ Aviso: Falha na limpeza da fila inicial. Assumindo ID 0. Erro: ", conditionMessage(e))
})

# ------------------------------------------------------------------------------
# 2. INICIALIZAÇÃO DOS CRONÔMETROS
# ------------------------------------------------------------------------------
agora <- Sys.time()

if(!exists("TIMER_BINANCE"))    TIMER_BINANCE    <- 60
if(!exists("TIMER_RAPIDO"))     TIMER_RAPIDO     <- 300
if(!exists("TIMER_MACRO"))      TIMER_MACRO      <- 3600
if(!exists("TIMER_SENTIMENTO")) TIMER_SENTIMENTO <- 1800 

last_run_binance    <- agora - TIMER_BINANCE
last_run_rapido     <- agora - TIMER_RAPIDO
last_run_macro      <- agora - TIMER_MACRO
last_run_sentimento <- agora - TIMER_SENTIMENTO 

if(exists("user_env")) rm(list = ls(user_env), envir = user_env)

message(">>> [SISTEMA] Motor Principal Ativo. Iniciando Event Loop.")

# ==============================================================================
# SUPER LOOP (EVENT LOOP MESTRE)
# ==============================================================================
repeat {
  agora <- Sys.time()
  
  # ----------------------------------------------------------------------------
  # MÓDULO 1: LabFariaLimer (Coleta de Dados Puros)
  # ----------------------------------------------------------------------------
  if(difftime(agora, last_run_binance, units = "secs") >= TIMER_BINANCE) {
    cat("\n🔶 [BINANCE] Tick Data...\n")
    all_prices <- tryCatch(binance_ticker_all_prices(), error = function(e) NULL)
    
    if(!is.null(all_prices)) {
      meus_dados <- all_prices %>%
        dplyr::filter(symbol %in% ORDEM_ATIVOS) %>%
        dplyr::mutate(Data_Hora = format(agora, "%Y-%m-%d %H:%M:%S"), Price = as.numeric(price)) %>%
        dplyr::select(Data_Hora, Symbol = symbol, Price) %>%
        tidyr::pivot_wider(names_from = Symbol, values_from = Price)
      
      if(db_safe_append("Historico_binance", meus_dados)) cat("    ✅ DB: Binance OK.\n")
    }
    last_run_binance <- Sys.time()
  }
  
  if(difftime(agora, last_run_rapido, units = "secs") >= TIMER_RAPIDO) {
    cat("\n⚡ [MICRO] Yahoo & AwesomeAPI...\n")
    tryCatch({
      json_moedas <- fromJSON("https://economia.awesomeapi.com.br/json/last/USD-BRL,BTC-BRL,ETH-BRL,EUR-BRL")
      quotes <- get_safe_quote(c("^BVSP", "^GSPC", "EWZ", "QQQ", "CL=F"))
      
      df_rapido <- data.frame(
        Data_Hora = format(agora, "%Y-%m-%d %H:%M:%S"),
        BTC_BRL   = as.numeric(json_moedas$BTCBRL$bid),
        ETH_BRL   = as.numeric(json_moedas$ETHBRL$bid),
        USD_BRL   = as.numeric(json_moedas$USDBRL$bid),
        EUR_BRL   = as.numeric(json_moedas$EURBRL$bid),
        IBOV_Pts  = if(!is.null(quotes)) quotes["^BVSP", "Last"] else NA,
        SP500_Pts = if(!is.null(quotes)) quotes["^GSPC", "Last"] else NA,
        EWZ_Bolsa = if(!is.null(quotes)) quotes["EWZ", "Last"] else NA,
        QQQ_Tech  = if(!is.null(quotes)) quotes["QQQ", "Last"] else NA,
        WTI_Oil   = if(!is.null(quotes)) quotes["CL=F", "Last"] else NA
      )
      
      if(!is.na(df_rapido$BTC_BRL)) {
        db_safe_append("Historico_rapido", df_rapido)
        cat("    ✅ DB: Rápido OK.\n")
      }
    }, error = function(e) cat("    ❌ Erro no Bloco Rápido:", conditionMessage(e), "\n"))
    last_run_rapido <- Sys.time()
  }
  
  if(difftime(agora, last_run_macro, units = "secs") >= TIMER_MACRO) {
    cat("\n🌍 [MACRO] Variáveis de Estado...\n")
    tryCatch({
      q_macro <- get_safe_quote(c("BZ=F", "GC=F", "^VIX", "^TNX", "DX-Y.NYB", "HG=F"))
      
      df_macro <- data.frame(
        Data = format(agora,"%Y-%m-%d %H:%M:%S"),
        Petroleo_Brent = if(!is.null(q_macro)) q_macro["BZ=F", "Last"] else 0,
        Ouro_USD = if(!is.null(q_macro)) q_macro["GC=F", "Last"] else 0,
        VIX_Index = if(!is.null(q_macro)) q_macro["^VIX", "Last"] else 0,
        Treasury_10Y = if(!is.null(q_macro)) q_macro["^TNX", "Last"] else 0,
        DXY_Index = if(!is.null(q_macro)) q_macro["DX-Y.NYB", "Last"] else 0,
        Copper_Index = if(!is.null(q_macro)) q_macro["HG=F", "Last"] else 0
      )
      
      if(db_safe_append("Historico_macro", df_macro)) cat("    ✅ DB: Macro OK.\n")
    }, error = function(e) cat("    ❌ Erro no Bloco Macro:", conditionMessage(e), "\n"))
    last_run_macro <- Sys.time()
  }
  
  # ----------------------------------------------------------------------------
  # MÓDULO 2: LabAnalyst (Tracker Alt-Data / Sentimento RSS)
  # ----------------------------------------------------------------------------
  if(difftime(agora, last_run_sentimento, units = "secs") >= TIMER_SENTIMENTO) {
    cat("\n📰 [ALT-DATA] Varrendo feeds RSS por ruídos de mercado...\n")
    last_run_sentimento <- Sys.time() 
    
    feeds_alvo <- c(
      "https://agenciabrasil.ebc.com.br/rss/politica/feed.xml",
      "https://agenciabrasil.ebc.com.br/rss/economia/feed.xml",
      "https://g1.globo.com/rss/g1/politica/",
      "https://g1.globo.com/rss/g1/economia/",
      "https://feeds.bbci.co.uk/portuguese/rss.xml",
      "https://www.reutersagency.com/feed/?best-topics=political-general&post_type=best",
      "https://www.reutersagency.com/feed/?best-topics=business-finance&post_type=best"
    )
    
    tryCatch({
      executar_etl_sentimento(urls_rss = feeds_alvo, tipo = "politico_global", janela_horas = 4)
      executar_etl_sentimento(urls_rss = feeds_alvo, tipo = "cripto", janela_horas = 2)
    }, error = function(e) {
      cat("    ❌ ERRO CRÍTICO no Tracker de Sentimento:", conditionMessage(e), "\n")
    })
  }
  
  # ----------------------------------------------------------------------------
  # MÓDULO 3: LabInvest (Mensageria Telegram - AMARRAÇÃO DE ESCOPO LOCAL)
  # ----------------------------------------------------------------------------
  tryCatch({
    # Aumentado o timeout para 2s para mitigar falsos positivos de queda de rede
    updates <- updater$bot$get_updates(offset = tg_last_update_id + 1, timeout = 2L)
    
    if (length(updates) > 0) {
      for (update in updates) {
        updater$dispatcher$process_update(update)
        # Atribuição local padrão e segura
        tg_last_update_id <- as.numeric(update$update_id)
      }
    }
  }, error = function(e) {
    cat("❌ [MÓDULO 3 | TELEGRAM ERROR]:", conditionMessage(e), "\n")
    # Avanço defensivo utilizando atribuição local consistente
    tg_last_update_id <- tg_last_update_id + 1
  })
  
  # ----------------------------------------------------------------------------
  # Heartbeat (Descanso Otimizado do Processador)
  # ----------------------------------------------------------------------------
  Sys.sleep(2) 
}

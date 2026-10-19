# ==============================================================================
# SISTEMA CENTRAL: startLab.R (Orquestrador Unificado do MoneyLab)
# Versão: 13.0 | Status: LabTrader + LabPolice Gatekeeper Integrados no Loop
# ==============================================================================
message(">>> [SISTEMA CENTRAL] Iniciando orquestração unificada...")

# Forçar pacotes essenciais para evitar conflito de namespace e proibir notação científica (Falha 4)
options(repos = c(CRAN = "https://cloud.r-project.org"), xts.warn_dplyr_breaks_lag = FALSE, scipen = 999, timeout = 12)

# Check if running in Docker container
if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
  LOCAL_R_LIB <- file.path(getwd(), "r-lib")
  if(!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
  .libPaths(unique(c(LOCAL_R_LIB, .libPaths())))
}

pkgs_start <- c("dplyr", "tidyr", "jsonlite", "quantmod", "lubridate", "httr", "RSQLite", "digest")
invisible(lapply(pkgs_start, function(p) {
  if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
    if(!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p, quiet = TRUE)
  }
  library(p, character.only = TRUE)
}))

# Blindagem global anti-hang de socket TCP/SSL (impede que telegram.bot::get_updates trave em half-open socket)
httr::set_config(httr::config(connecttimeout = 5L, timeout = 12L, tcp_keepalive = 1L))

# ------------------------------------------------------------------------------
# 1. CARREGAMENTO DOS MÓDULOS INTELIGENTES
# ------------------------------------------------------------------------------
source("LabFariaLimer.R") 
source("LabAnalyst.R")   
source("LabInvest.R")
source("LabPolice.R")
source("LabTrader.R")

# Rastreio de modificação de arquivos para Hot-Reload Inteligente sem sobrecarga de CPU (Falha 6)
last_mtime_trader <- if (file.exists("LabTrader.R")) file.info("LabTrader.R")$mtime else Sys.time()
last_mtime_police <- if (file.exists("LabPolice.R")) file.info("LabPolice.R")$mtime else Sys.time()

# ------------------------------------------------------------------------------
# 1.1 LIMPEZA DE FILA DO TELEGRAM (RASTREIO EXTERNO DE ID)
# ------------------------------------------------------------------------------
message(">>> [TELEGRAM] Verificando fila de mensagens...")

tg_last_update_id <- 0

tryCatch({
  last_update <- updater$bot$get_updates(offset = -1L, limit = 1L, timeout = 5L)
  
  if (length(last_update) > 0) {
    ult_id <- as.numeric(last_update[[1]]$update_id)
    msg_ts <- tryCatch(as.numeric(last_update[[1]]$message$date), error = function(e) 0)
    idade_seg <- if (!is.null(msg_ts) && length(msg_ts) > 0 && !is.na(msg_ts) && msg_ts > 0) (as.numeric(Sys.time()) - msg_ts) else 99999
    if (idade_seg <= 900) {
      tg_last_update_id <- ult_id - 1
      message("    📩 Mensagem recente detectada (", round(idade_seg), "s atrás). Será respondida imediatamente! ID: ", ult_id)
    } else {
      tg_last_update_id <- ult_id
      message("    ✅ Fila antiga limpa. Último ID registrado: ", tg_last_update_id)
    }
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
if(!exists("TIMER_HARMONICUS")) TIMER_HARMONICUS <- 3600
if(!exists("TIMER_RADAR"))      TIMER_RADAR      <- 30

last_run_binance    <- agora - TIMER_BINANCE
last_run_rapido     <- agora - TIMER_RAPIDO
last_run_macro      <- agora - TIMER_MACRO
last_run_sentimento <- agora - TIMER_SENTIMENTO 
last_run_harmonicus <- agora - TIMER_HARMONICUS 
last_run_radar      <- agora - TIMER_RADAR

if(exists("user_env")) rm(list = ls(user_env), envir = user_env)

message(">>> [SISTEMA] Motor Principal Ativo (Coletores, Analista, Trader, Polícia e Telegram).")

# ==============================================================================
# SUPER LOOP (EVENT LOOP MESTRE)
# ==============================================================================
repeat {
  agora <- Sys.time()
  
  # ----------------------------------------------------------------------------
  # MÓDULO 1: LabFariaLimer (Coletores de Preço)
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
      
      meus_dados$Origem_Dado <- "TICK_REAL_FARIALIMER"
      if(db_safe_append("Historico_binance", meus_dados)) cat("    ✅ DB: Binance OK (Tag: TICK_REAL_FARIALIMER).\n")
    }
    last_run_binance <- Sys.time()
  }
  
  if(difftime(agora, last_run_rapido, units = "secs") >= TIMER_RAPIDO) {
    cat("\n⚡ [MICRO] Yahoo & AwesomeAPI...\n")
    
    usd_val <- NA
    eth_val <- NA
    btc_val <- NA
    eur_val <- NA
    
    # 1. Tenta AwesomeAPI
    tryCatch({
      json_moedas <- fromJSON("https://economia.awesomeapi.com.br/json/last/USD-BRL,BTC-BRL,ETH-BRL,EUR-BRL")
      usd_val <- as.numeric(json_moedas$USDBRL$bid)
      eth_val <- as.numeric(json_moedas$ETHBRL$bid)
      btc_val <- as.numeric(json_moedas$BTCBRL$bid)
      eur_val <- as.numeric(json_moedas$EURBRL$bid)
    }, error = function(e) {
      cat("    ⚠️ AwesomeAPI falhou. Tentando fallbacks...\n")
    })
    
    # 2. Fallback moedas fiduciárias via Yahoo Finance
    if (is.na(usd_val) || is.na(eur_val)) {
      tryCatch({
        fallback_quotes <- get_safe_quote(c("USDBRL=X", "EURBRL=X"))
        if (!is.null(fallback_quotes)) {
          if (is.na(usd_val)) usd_val <- as.numeric(fallback_quotes["USDBRL=X", "Last"])
          if (is.na(eur_val)) eur_val <- as.numeric(fallback_quotes["EURBRL=X", "Last"])
          cat("    ✅ Fallback Yahoo Finance fiduciárias OK!\n")
        }
      }, error = function(e) NULL)
    }
    
    # 3. Fallback criptomoedas via Yahoo Finance
    if (is.na(btc_val) || is.na(eth_val)) {
      tryCatch({
        fallback_usd_crypto <- get_safe_quote(c("BTC-USD", "ETH-USD"))
        if (!is.null(fallback_usd_crypto) && !is.na(usd_val)) {
          if (is.na(btc_val)) btc_val <- as.numeric(fallback_usd_crypto["BTC-USD", "Last"]) * usd_val
          if (is.na(eth_val)) eth_val <- as.numeric(fallback_usd_crypto["ETH-USD", "Last"]) * usd_val
          cat("    ✅ Fallback Yahoo Finance cripto OK!\n")
        }
      }, error = function(e) NULL)
    }
    
    # 4. Outros índices, commodities e Ativos de Hedge US (NVDA, XLE, TLT, BITI)
    quotes <- get_safe_quote(c("^BVSP", "^GSPC", "EWZ", "QQQ", "CL=F", "NVDA", "XLE", "TLT", "BITI"))
    
    tryCatch({
      df_rapido <- data.frame(
        Data_Hora   = format(agora, "%Y-%m-%d %H:%M:%S"),
        BTC_BRL     = btc_val,
        ETH_BRL     = eth_val,
        USD_BRL     = usd_val,
        EUR_BRL     = eur_val,
        IBOV_Pts    = if(!is.null(quotes) && "^BVSP" %in% rownames(quotes)) quotes["^BVSP", "Last"] else NA,
        SP500_Pts   = if(!is.null(quotes) && "^GSPC" %in% rownames(quotes)) quotes["^GSPC", "Last"] else NA,
        EWZ_Bolsa   = if(!is.null(quotes) && "EWZ" %in% rownames(quotes)) quotes["EWZ", "Last"] else NA,
        QQQ_Tech    = if(!is.null(quotes) && "QQQ" %in% rownames(quotes)) quotes["QQQ", "Last"] else NA,
        WTI_Oil     = if(!is.null(quotes) && "CL=F" %in% rownames(quotes)) quotes["CL=F", "Last"] else NA,
        NVDA_Stock  = if(!is.null(quotes) && "NVDA" %in% rownames(quotes)) quotes["NVDA", "Last"] else NA,
        XLE_Energy  = if(!is.null(quotes) && "XLE" %in% rownames(quotes)) quotes["XLE", "Last"] else NA,
        TLT_Bond    = if(!is.null(quotes) && "TLT" %in% rownames(quotes)) quotes["TLT", "Last"] else NA,
        BITI_Short  = if(!is.null(quotes) && "BITI" %in% rownames(quotes)) quotes["BITI", "Last"] else NA
      )
      df_rapido$Origem_Dado <- "TICK_REAL_FARIALIMER"
      
      if(!is.na(df_rapido$BTC_BRL) && !is.na(df_rapido$USD_BRL)) {
        db_safe_append("Historico_rapido", df_rapido)
        cat("    ✅ DB: Rápido OK (Tag: TICK_REAL_FARIALIMER | Hedge US Ingerido).\n")
      }
    }, error = function(e) cat("    ❌ Erro no Bloco Rápido:", conditionMessage(e), "\n"))
    
    last_run_rapido <- Sys.time()
  }
  
  if(difftime(agora, last_run_macro, units = "secs") >= TIMER_MACRO) {
    cat("\n🌍 [MACRO] Variáveis de Estado (Yahoo Finance Live Sync)...\n")
    tryCatch({
      # 1. Executa sincronizador robusto Python para Yahoo Finance API
      cmd_py <- if (.Platform$OS.type == "windows") "python" else "python3"
      sync_script <- file.path("scratch", "sync_macro_vix_data.py")
      if (file.exists(sync_script)) {
        system(sprintf('%s "%s"', cmd_py, sync_script), intern = FALSE, ignore.stdout = TRUE)
        cat("    ✅ DB: Macro sincronizado via Yahoo Finance API.\n")
      } else {
        # Fallback R nativo
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
        if(db_safe_append("Historico_macro", df_macro)) cat("    ✅ DB: Macro OK (Fallback).\n")
      }
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
  # MÓDULO 2.1: LabAnalyst (Harmonicus Spectral Pipeline 1h)
  # ----------------------------------------------------------------------------
  if(difftime(agora, last_run_harmonicus, units = "secs") >= TIMER_HARMONICUS) {
    cat("\n🎼 [HARMONICUS] Processando Decomposição Espectral e Topologia...\n")
    tryCatch({
      executar_pipeline_harmonicus("MoneyBot_Local.db")
    }, error = function(e) {
      cat("    ⚠️ Aviso: Falha segura no pipeline Harmonicus:", conditionMessage(e), "\n")
    })
    last_run_harmonicus <- Sys.time()
  }
  
  # ----------------------------------------------------------------------------
  # MÓDULO 3: LabTrader (Radar de Estratégias Quant) & LabPolice (Gatekeeper)
  # ----------------------------------------------------------------------------
  if(difftime(agora, last_run_radar, units = "secs") >= TIMER_RADAR) {
    tryCatch({
      # Hot-reload inteligente sob demanda (Falha 6: recarrega apenas quando o arquivo muda no disco)
      if (file.exists("LabTrader.R")) {
        mt_t <- file.info("LabTrader.R")$mtime
        if (!is.na(mt_t) && mt_t > last_mtime_trader) {
          source("LabTrader.R")
          last_mtime_trader <- mt_t
          cat("🔄 [HOT-RELOAD] LabTrader.R atualizado recarregado com sucesso.\n")
        }
      }
      if (file.exists("LabPolice.R")) {
        mt_p <- file.info("LabPolice.R")$mtime
        if (!is.na(mt_p) && mt_p > last_mtime_police) {
          source("LabPolice.R")
          last_mtime_police <- mt_p
          cat("🔄 [HOT-RELOAD] LabPolice.R atualizado recarregado com sucesso.\n")
        }
      }
      
      # Limpeza de segurança se solicitacao.rds ou solicitacao_processing.rds ficar órfã por mais de 90 segundos (Falha 2)
      for (f_ipc in c("solicitacao.rds", "solicitacao_processing.rds")) {
        if (file.exists(f_ipc)) {
          info_sol <- file.info(f_ipc)
          if (!is.na(info_sol$mtime) && as.numeric(difftime(Sys.time(), info_sol$mtime, units = "secs")) > 90) {
            unlink(f_ipc)
          }
        }
      }
      
      # 1. Executa radar dos motores quânticos e gera solicitacao.rds atomicamente se houver disparo
      executar_radar_labtrader()
      
      # 2. Gatekeeper valida as travas, executa na Binance se aprovado e notifica o Telegram
      processar_solicitacoes_gatekeeper(modo_continuo = FALSE, executar_real = TRUE)
    }, error = function(e) {
      if (file.exists("solicitacao.rds")) unlink("solicitacao.rds")
      if (file.exists("solicitacao_processing.rds")) unlink("solicitacao_processing.rds")
      cat("❌ [MÓDULO 3 | RADAR/GATEKEEPER ERROR]:", conditionMessage(e), "\n")
    })
    last_run_radar <- Sys.time()
  }
  
  # ----------------------------------------------------------------------------
  # MÓDULO 4: LabInvest (Mensageria Telegram - AMARRAÇÃO DE ESCOPO LOCAL COM ANTI-HANG)
  # ----------------------------------------------------------------------------
  tryCatch({
    setTimeLimit(elapsed = 15, transient = TRUE)
    on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
    updates <- updater$bot$get_updates(offset = tg_last_update_id + 1, timeout = 2L)
    setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
    
    if (length(updates) > 0) {
      for (update in updates) {
        tg_last_update_id <- as.numeric(update$update_id)
        tryCatch({
          updater$dispatcher$process_update(update)
        }, error = function(e_up) {
          cat("⚠️ [TELEGRAM HANDLER ERROR]:", conditionMessage(e_up), "\n")
        })
      }
    }
  }, error = function(e) {
    setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
    cat("❌ [MÓDULO 4 | TELEGRAM ERROR]:", conditionMessage(e), "\n")
  })
  
  # ----------------------------------------------------------------------------
  # Heartbeat (Descanso Otimizado do Processador)
  # ----------------------------------------------------------------------------
  Sys.sleep(2) 
}

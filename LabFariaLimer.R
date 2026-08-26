# ==============================================================================
# LabFariaLimer.R — Motor Full Market Watcher (Versão 11.3 - Robust SQL)
# ==============================================================================
options(repos = c(CRAN = "https://cloud.r-project.org"), xts.warn_dplyr_breaks_lag = FALSE)

# Check if running in Docker container
if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
  LOCAL_R_LIB <- file.path(getwd(), "r-lib")
  if(!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
  .libPaths(unique(c(LOCAL_R_LIB, .libPaths())))
}

pkgs_faria <- c("jsonlite", "quantmod", "dplyr", "lubridate", "telegram.bot",
                "binancer", "tidyr", "DBI", "RSQLite")
invisible(lapply(pkgs_faria, function(p) {
  if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
    if(!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p, quiet = TRUE)
  }
  library(p, character.only = TRUE)
}))

if(file.exists("config_auth.R")) source("config_auth.R")
bot <- Bot(token = TG_INVEST_TOKEN) 
db_file <- "MoneyBot_Local.db"

# ------------------------------------------------------------------------------
# FUNÇÃO TÉCNICA: db_safe_append (Auto-Schema Migration & Fail-Safe)
# ------------------------------------------------------------------------------
db_safe_append <- function(table_name, data) {
  tryCatch({
    temp_con <- dbConnect(RSQLite::SQLite(), db_file)
    on.exit(dbDisconnect(temp_con))
    
    if (dbExistsTable(temp_con, table_name)) {
      cols_db <- dbListFields(temp_con, table_name)
      cols_df <- names(data)
      
      # 1. Adiciona dinamicamente colunas faltantes no SQLite
      cols_missing_db <- setdiff(cols_df, cols_db)
      if (length(cols_missing_db) > 0) {
        for (col_m in cols_missing_db) {
          tryCatch(dbExecute(temp_con, sprintf("ALTER TABLE %s ADD COLUMN %s REAL;", table_name, col_m)), error = function(e) NULL)
        }
        cols_db <- dbListFields(temp_con, table_name)
      }
      
      # 2. Garante que apenas colunas válidas sejam enviadas para o append
      cols_common <- intersect(cols_df, cols_db)
      data_filtered <- data[, cols_common, drop = FALSE]
      dbWriteTable(temp_con, table_name, data_filtered, append = TRUE)
    } else {
      dbWriteTable(temp_con, table_name, data, append = TRUE)
    }
    return(TRUE)
  }, error = function(e) {
    cat(paste0("    ⚠️ [FALHA SQL] ", conditionMessage(e), "\n"))
    return(FALSE)
  })
}

# [PARÂMETROS E FUNÇÕES AUXILIARES]
TIMER_RAPIDO <- 300; TIMER_BINANCE <- 60; TIMER_MACRO <- 14400
ORDEM_ATIVOS <- c("BTCBRL", "ETHBRL", "USDTBRL", "BNBBRL", "SOLBRL", 
                  "ADABRL", "LINKBRL", "NEARBRL", "AVAXBRL", "POLBRL", "RENDERBRL", "LTCBRL", "DOGEBRL")

last_run_binance <- Sys.time() - hours(10)
last_run_rapido  <- Sys.time() - hours(10)
last_run_macro   <- Sys.time() - hours(10)

get_safe_quote <- function(tickers) {
  tryCatch({ q <- getQuote(tickers); return(q) }, error = function(e) return(NULL))
}

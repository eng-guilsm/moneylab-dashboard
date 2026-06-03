# ==============================================================================
# LabFariaLimer.R — Motor Full Market Watcher (Versão 11.3 - Robust SQL)
# ==============================================================================
options(repos = c(CRAN = "https://cloud.r-project.org"), xts.warn_dplyr_breaks_lag = FALSE)
LOCAL_R_LIB <- file.path(getwd(), "r-lib")
if(!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(LOCAL_R_LIB, .libPaths())))

pkgs_faria <- c("jsonlite", "quantmod", "dplyr", "lubridate", "telegram.bot",
                "binancer", "tidyr", "DBI", "RSQLite")
invisible(lapply(pkgs_faria, function(p) {
  if(!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p, quiet = TRUE)
  library(p, character.only = TRUE)
}))

if(file.exists("config_auth.R")) source("config_auth.R")
bot <- Bot(token = TG_INVEST_TOKEN) 
db_file <- "MoneyBot_Local.db"

# ------------------------------------------------------------------------------
# FUNÇÃO TÉCNICA: db_safe_append
# ------------------------------------------------------------------------------
db_safe_append <- function(table_name, data) {
  tryCatch({
    temp_con <- dbConnect(RSQLite::SQLite(), db_file)
    dbWriteTable(temp_con, table_name, data, append = TRUE)
    dbDisconnect(temp_con)
    return(TRUE)
  }, error = function(e) {
    cat(paste0("    ⚠️ [FALHA SQL] ", conditionMessage(e), "\n"))
    return(FALSE)
  })
}

# [PARÂMETROS E FUNÇÕES AUXILIARES]
TIMER_RAPIDO <- 300; TIMER_BINANCE <- 60; TIMER_MACRO <- 14400
ORDEM_ATIVOS <- c("BTCBRL", "ETHBRL", "USDTBRL", "BNBBRL", "SOLBRL", 
                  "ADABRL", "PAXGBRL", "LINKBRL", "RENDEDBRL")

last_run_binance <- Sys.time() - hours(10)
last_run_rapido  <- Sys.time() - hours(10)
last_run_macro   <- Sys.time() - hours(10)

get_safe_quote <- function(tickers) {
  tryCatch({ q <- getQuote(tickers); return(q) }, error = function(e) return(NULL))
}

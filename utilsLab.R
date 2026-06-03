# ==============================================================================
# UTILS LAB: Ferramentas de Auditoria e Extração do MoneyBot
# Uso: Carregue no console com source("utilsLab.R")
# ==============================================================================
library(DBI)
library(RSQLite)

# Variável de apontamento global
DB_FILE <- "MoneyBot_Local.db"

# ------------------------------------------------------------------------------
# 1. db_status(): Raio-X do Banco de Dados
# ------------------------------------------------------------------------------
# Mostra todas as tabelas e quantas linhas cada uma tem. Ideal para ver se 
# a coleta da madrugada não travou silenciosamente.
db_status <- function() {
  con <- tryCatch(dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if(is.null(con)) { cat("⚠️ Erro de conexão com o banco.\n"); return(invisible()) }
  
  on.exit(dbDisconnect(con)) # Garante que desconecta mesmo se der erro no meio
  
  tabelas <- dbListTables(con)
  cat("\n📊 --- STATUS DO BANCO DE DADOS ---\n")
  for(tb in tabelas) {
    count <- dbGetQuery(con, paste0("SELECT COUNT(*) as n FROM ", tb))$n
    cat(sprintf(" 📁 %-20s : %8d registros\n", tb, count))
  }
  cat("-----------------------------------\n")
}

# ------------------------------------------------------------------------------
# 2. ver_n(): Evolução do seu ver_10
# ------------------------------------------------------------------------------
# Permite escolher quantas linhas ver e se quer o topo (head) ou o fundo (tail).
# Ex: ver_n("Estado_mundo", 5) ou ver_n("Historico_macro", 20, tail=FALSE)
ver_n <- function(table_name, n = 10, tail = TRUE) {
  con <- tryCatch(dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if(is.null(con)) return(invisible())
  on.exit(dbDisconnect(con))
  
  order_dir <- ifelse(tail, "DESC", "ASC")
  query <- sprintf("SELECT * FROM %s ORDER BY rowid %s LIMIT %d", table_name, order_dir, n)
  
  res <- tryCatch(dbGetQuery(con, query), error = function(e) NULL)
  if(!is.null(res)) {
    if(tail) res <- res[order(as.numeric(rownames(res))), ] # Reordena para leitura natural
    cat(sprintf("\n--- %s %d REGISTROS: %s ---\n", ifelse(tail, "ÚLTIMOS", "PRIMEIROS"), n, table_name))
    print(res)
  } else {
    cat("⚠️ Erro ao ler tabela:", table_name, "\n")
  }
}

# ------------------------------------------------------------------------------
# 3. q_sql(): Terminal SQL Direto no R
# ------------------------------------------------------------------------------
# Execute consultas SQL puras sem escrever as funções de DBI.
# Ex: df <- q_sql("SELECT Data_Hora, BTCBRL FROM Historico_binance WHERE BTCBRL < 340000")
q_sql <- function(query_string) {
  con <- tryCatch(dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if(is.null(con)) return(NULL)
  on.exit(dbDisconnect(con))
  
  res <- tryCatch(dbGetQuery(con, query_string), error = function(e) {
    cat("⚠️ Erro de Sintaxe SQL:", conditionMessage(e), "\n")
    return(NULL)
  })
  return(res)
}

# ------------------------------------------------------------------------------
# 4. export_dat(): O Botão de Backup para o TCC/Pesquisa
# ------------------------------------------------------------------------------
# Lembra daquele comando que fizemos para extrair .dat? Agora é uma função.
# Ex: export_dat("Estado_mundo") -> Gera o arquivo limpo na sua pasta.
export_dat <- function(table_name) {
  df <- q_sql(sprintf("SELECT * FROM %s", table_name))
  if(!is.null(df) && nrow(df) > 0) {
    file_name <- sprintf("%s_Dump_%s.dat", table_name, format(Sys.time(), "%Y%m%d_%H%M"))
    write.table(df, file_name, sep = "\t", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8")
    cat(sprintf("✅ Arquivo gerado com sucesso: %s\n", file_name))
  } else {
    cat("⚠️ Tabela vazia ou não encontrada.\n")
  }
}
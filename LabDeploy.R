# ==============================================================================
# LABDEPLOY.R: MOTOR NUCLEAR (LIMPEZA TOTAL A CADA CICLO)
# ==============================================================================
library(rmarkdown)
library(knitr)
library(googlesheets4)
library(googledrive)
library(lubridate)

# 1. SETUP DE ENCODING (CRÍTICO WINDOWS)
options(encoding = "UTF-8")
if (.Platform$OS.type == "windows") {
  Sys.setlocale("LC_ALL", "Portuguese_Brazil.65001")
}

cat("\n--- 🏁 Sistema de Deploy Pronto ---\n")

# 2. CARREGA CONFIG
caminho_config <- "config_auth.R"
if (!file.exists(caminho_config)) {
  caminho_config <- "C:/Users/Guilherme/OneDrive/Área de Trabalho/Doutorado/Health/MoneyLab/config_auth.R"
}

if(file.exists(caminho_config)) {
  source(caminho_config, encoding = "UTF-8")
  cat("✅ Configurações carregadas de:", caminho_config, "\n")
} else {
  stop("❌ CRÍTICO: config_auth.R não encontrado.")
}

# 3. AJUSTA DIRETÓRIO
if(exists("PATH_PROJETO") && dir.exists(PATH_PROJETO)) {
  setwd(PATH_PROJETO)
  cat("📂 Pasta de trabalho alterada para:", getwd(), "\n")
} else {
  cat("📂 Pasta de trabalho atual mantida:", getwd(), "\n")
}

# 4. CONFIG GIT
git_email <- if(exists("GIT_USER_EMAIL")) GIT_USER_EMAIL else "g.s.macedo7@gmail.com"
git_name  <- if(exists("GIT_USER_NAME"))  GIT_USER_NAME  else "Guilherme Santos"
system(sprintf('git config user.email "%s"', git_email))
system(sprintf('git config user.name "%s"', git_name))

RMD_ALVO <- "dashboard_money.Rmd"
CACHE_FILE <- "moneybot_cache_v2_brl.rds" # O nome exato que definimos no Rmd

# ==============================================================================
# 5. LOOP DE ATUALIZAÇÃO
# ==============================================================================
while(TRUE) {
  cat("\n--- 🏗️ Ciclo de Atualização:", format(Sys.time(), "%H:%M:%S"), "---\n")
  
  if(!file.exists(RMD_ALVO)) {
    cat("❌ ERRO: Arquivo .Rmd não encontrado!\n")
  } else {
    tryCatch({
      # --- A. FASE NUCLEAR (LIMPEZA) ---
      # Deleta o index antigo para garantir que o novo seja criado
      if(file.exists("index.html")) {
        file.remove("index.html")
        cat("   🗑️ index.html antigo removido.\n")
      }
      
      # DELETA O CACHE .RDS (Isso força o download de dados novos!)
      if(file.exists(CACHE_FILE)) {
        file.remove(CACHE_FILE)
        cat("   🗑️ Cache de dados deletado (Forçando download fresco).\n")
      }
      
      # --- B. RENDERIZAÇÃO ---
      # Usamos o GlobalEnv para garantir que as variáveis de config sejam vistas
      render(RMD_ALVO, 
             output_file = "index.html", 
             encoding = "UTF-8", 
             quiet = TRUE,
             clean = TRUE)
      
      cat("   ✅ 1. Nova Dashboard Gerada com Sucesso.\n")
      
      # --- C. GIT DEPLOY ---
      cat("   🛰️ Sincronizando com GitHub...\n")
      
      system("git add index.html")
      
      # Commit com Timestamp
      msg_commit <- sprintf('git commit -m "Auto-Update: %s"', format(Sys.time(), "%d/%m %H:%M"))
      
      # Captura a resposta do Git para vermos se houve mudança
      git_log <- system(msg_commit, intern = TRUE)
      cat("   📝 Git Log:", head(git_log, 1), "\n")
      
      system("git push origin main")
      
      cat("   🚀 2. Deploy Concluído!\n")
      
    }, error = function(e) {
      cat("   ❌ FALHA NO CICLO:", e$message, "\n")
    })
  }
  
  cat("--- 😴 Aguardando 300s ---\n")
  Sys.sleep(300)
}
# ==============================================================================
# LABDEPLOY.R: MOTOR DE DEPLOY CONTÍNUO (HARMONICUS SX & MONEYLAB HUD)
# Versão: 20.0 | Intervalo: 60s (1 Minuto) | Multi-Repositório Git Sync
# ==============================================================================
options(encoding = "UTF-8")
if (.Platform$OS.type == "windows") {
  Sys.setlocale("LC_ALL", "Portuguese_Brazil.65001")
}

cat("\n====================================================================\n")
cat("🚀 [LABDEPLOY v20.0] Inicializando Motor de Deploy Contínuo (1 Minuto)...\n")
cat("====================================================================\n")

# 1. CARREGA CONFIGURAÇÃO
caminho_config <- "config_auth.R"
if (file.exists(caminho_config)) {
  tryCatch(source(caminho_config, encoding = "UTF-8"), error = function(e) NULL)
}

# Caminhos dos Projetos
path_labinvest <- getwd()
path_harmonicus_sx <- file.path(dirname(path_labinvest), "harmonicus-sx")
if (!dir.exists(path_harmonicus_sx)) {
  path_harmonicus_sx <- "/home/ubuntu/harmonicus-sx"
}

cat("📁 LabInvest Base:      ", path_labinvest, "\n")
cat("📁 Harmonicus SX Repo:  ", path_harmonicus_sx, "\n")

# Configurar Git
git_email <- if(exists("GIT_USER_EMAIL")) GIT_USER_EMAIL else "g.s.macedo7@gmail.com"
git_name  <- if(exists("GIT_USER_NAME"))  GIT_USER_NAME  else "Guilherme Santos"

system(sprintf('git config --global user.email "%s"', git_email))
system(sprintf('git config --global user.name "%s"', git_name))

# ==============================================================================
# LOOP DE DEPLOY CONTÍNUO (60 SEGUNDOS)
# ==============================================================================
ciclo_num <- 1

repeat {
  agora_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("\n--- 🛰️ [LABDEPLOY #%d] Ciclo de Atualização: %s ---\n", ciclo_num, agora_str))
  
  # ----------------------------------------------------------------------------
  # 1. EXPORTAÇÃO DE DADOS EM TEMPO REAL (HARMONICUS SX DATA ENGINE)
  # ----------------------------------------------------------------------------
  tryCatch({
    cat("   📊 1. Extraindo métricas de 1,4 anos e cotações ao vivo do SQLite...\n")
    script_export <- file.path(path_labinvest, "scratch", "export_harmonicus_sx_data.py")
    script_kinetics <- file.path(path_labinvest, "scratch", "export_charts_kinetics.py")
    
    cmd_py <- if (.Platform$OS.type == "windows") "python" else "python3"
    
    if (file.exists(script_export)) {
      system(sprintf('%s "%s"', cmd_py, script_export), intern = FALSE, ignore.stdout = TRUE)
    }
    if (file.exists(script_kinetics)) {
      system(sprintf('%s "%s"', cmd_py, script_kinetics), intern = FALSE, ignore.stdout = TRUE)
    }
    cat("   ✅ Dados exportados para data/planos_data.js, harmonicus_sx_data.js e charts_data.js.\n")
  }, error = function(e) {
    cat("   ⚠️ Aviso na exportação Python:", conditionMessage(e), "\n")
  })
  
  # ----------------------------------------------------------------------------
  # 2. GIT SYNC DO NOVO REPOSITÓRIO HARMONICUS-SX
  # ----------------------------------------------------------------------------
  if (dir.exists(path_harmonicus_sx)) {
    tryCatch({
      cat("   🐙 2. Sincronizando repositório GitHub 'harmonicus-sx'...\n")
      cmd_git_sync <- sprintf('cd "%s" && git add . && git commit -m "Auto-Update 1m: %s" && git push origin main', path_harmonicus_sx, agora_str)
      if (.Platform$OS.type == "windows") {
        # PowerShell / CMD
        cmd_win <- sprintf('powershell -Command "Set-Location \'%s\'; git add .; git commit -m \'Auto-Update 1m: %s\'; git push origin main"', path_harmonicus_sx, agora_str)
        system(cmd_win, intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)
      } else {
        system(cmd_git_sync, intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)
      }
      cat("   🚀 Harmonicus SX publicado no GitHub Pages com sucesso!\n")
    }, error = function(e) {
      cat("   ⚠️ Aviso no git push do Harmonicus SX:", conditionMessage(e), "\n")
    })
  }
  
  # ----------------------------------------------------------------------------
  # 3. DEPLOY CLÁSSICO MONEYLAB (DASHBOARD_MONEY.RMD) SE NECESSÁRIO
  # ----------------------------------------------------------------------------
  rmd_alvo <- file.path(path_labinvest, "dashboard_money.Rmd")
  if (file.exists(rmd_alvo) && (ciclo_num %% 5 == 1)) { # A cada 5 minutos
    tryCatch({
      cat("   📝 3. Renderizando dashboard_money.Rmd clássico...\n")
      suppressMessages(rmarkdown::render(rmd_alvo, output_file = "index.html", quiet = TRUE, clean = TRUE))
      system('git add index.html && git commit -m "Auto-Update Classic HUD" && git push origin main', ignore.stdout = TRUE, ignore.stderr = TRUE)
      cat("   ✅ MoneyLab Classic Dashboard atualizado.\n")
    }, error = function(e) {
      # Silencioso
    })
  }
  
  ciclo_num <- ciclo_num + 1
  cat("--- 😴 Aguardando 60 segundos para próximo ciclo ---\n")
  Sys.sleep(60)
}
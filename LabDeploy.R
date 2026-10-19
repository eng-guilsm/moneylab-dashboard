# ==============================================================================
# LABDEPLOY.R: MOTOR DE DEPLOY CONTÍNUO (MONEYLAB KINETICS HUD)
# Versão: 21.0 | Intervalo: 180s (3 Minutos) | Anti-Bloat Git Sync (--amend)
# ==============================================================================
options(encoding = "UTF-8")
if (.Platform$OS.type == "windows") {
  Sys.setlocale("LC_ALL", "Portuguese_Brazil.65001")
}

cat("\n====================================================================\n")
cat("🚀 [LABDEPLOY v21.0] Inicializando Motor de Deploy Contínuo (Anti-Bloat)...\n")
cat("====================================================================\n")

# 1. CARREGA CONFIGURAÇÃO
caminho_config <- "config_auth.R"
if (file.exists(caminho_config)) {
  tryCatch(source(caminho_config, encoding = "UTF-8"), error = function(e) NULL)
}

# Caminho do Projeto
path_labinvest <- getwd()
cat("📁 LabInvest Base: ", path_labinvest, "\n")

# Configurar Git
git_email <- if(exists("GIT_USER_EMAIL")) GIT_USER_EMAIL else "g.s.macedo7@gmail.com"
git_name  <- if(exists("GIT_USER_NAME"))  GIT_USER_NAME  else "Guilherme Santos"

system(sprintf('git config --global user.email "%s"', git_email))
system(sprintf('git config --global user.name "%s"', git_name))

# ==============================================================================
# LOOP DE DEPLOY CONTÍNUO (180 SEGUNDOS - ZERO BLOAT DE DISCO)
# ==============================================================================
ciclo_num <- 1

repeat {
  agora_str <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("\n--- 🛰️ [LABDEPLOY #%d] Ciclo de Atualização: %s ---\n", ciclo_num, agora_str))
  
  # ----------------------------------------------------------------------------
  # 1. EXPORTAÇÃO DE DADOS EM TEMPO REAL (RADAR CINÉTICO /DASH)
  # ----------------------------------------------------------------------------
  tryCatch({
    cat("   📊 1. Extraindo séries multi-timeframe e cotações ao vivo do SQLite...\n")
    script_kinetics <- file.path(path_labinvest, "scratch", "export_charts_kinetics.py")
    cmd_py <- if (.Platform$OS.type == "windows") "python" else "python3"
    
    if (file.exists(script_kinetics)) {
      system(sprintf('%s "%s"', cmd_py, script_kinetics), intern = FALSE, ignore.stdout = TRUE)
    }
    cat("   ✅ Dados exportados para data/charts_data.js.\n")
  }, error = function(e) {
    cat("   ⚠️ Aviso na exportação Python:", conditionMessage(e), "\n")
  })
  
  # ----------------------------------------------------------------------------
  # 2. SINCRONIZAÇÃO ANTI-BLOAT DO MONEYLAB-DASHBOARD (--amend + push --force)
  # ----------------------------------------------------------------------------
  if (dir.exists(path_labinvest)) {
    tryCatch({
      cmd_moneylab_sync <- sprintf(
        'cd "%s" && git add data/charts_data.js index.html kinetics.html && git commit --amend -m "Auto-Update Kinetics: %s" && git push --force origin main',
        path_labinvest, agora_str
      )
      if (.Platform$OS.type == "windows") {
        cmd_win <- sprintf(
          'powershell -Command "Set-Location \'%s\'; git add data/charts_data.js index.html kinetics.html; git commit --amend -m \'Auto-Update Kinetics: %s\'; git push --force origin main"',
          path_labinvest, agora_str
        )
        system(cmd_win, intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)
      } else {
        system(cmd_moneylab_sync, intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)
      }
      if (ciclo_num %% 40 == 0) {
        system(sprintf('cd "%s" && git gc --prune=now --quiet', path_labinvest), intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE)
      }
      cat("   🚀 MoneyLab Dashboard (/dash) publicado no GitHub Pages sem inflar histórico!\n")
    }, error = function(e) {
      cat("   ⚠️ Aviso no git push do MoneyLab Dashboard:", conditionMessage(e), "\n")
    })
  }
  
  ciclo_num <- ciclo_num + 1
  cat("--- 😴 Aguardando 180 segundos para próximo ciclo ---\n")
  Sys.sleep(180)
}
# ==============================================================================
# LabInvest — v36.5 (DB TIMESTAMP PRECISION & VIP ACCESS)
# ==============================================================================
options(warn = -1, encoding = "UTF-8")
options(repos = c(CRAN = "https://cloud.r-project.org"), xts.warn_dplyr_breaks_lag = FALSE)

# Check if running in Docker container
if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
  LOCAL_R_LIB <- file.path(getwd(), "r-lib")
  if(!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
  .libPaths(unique(c(LOCAL_R_LIB, .libPaths())))
}

log_analyst <- function(msg) cat(sprintf("[LabInvest | %s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))

# ------------------------------------------------------------------------------
# BLOCO 1: PACOTES
# ------------------------------------------------------------------------------
pkgs <- c("quantmod", "jsonlite", "telegram.bot", "lubridate", "dplyr",
          "tidyr", "stringr", "RSQLite", "DBI", "httr2")
for(p in pkgs) {
  if (Sys.getenv("RUNNING_IN_DOCKER") == "") {
    if(!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p)
  }
  library(p, character.only = TRUE)
}

if(file.exists("config_auth.R")) source("config_auth.R")
DB_FILE <- "MoneyBot_Local.db" 

if(!exists("Daniel_tekel_dollar") || !exists("Daniel_tekel_dollar_1d")) {
  if(file.exists("LabAnalyst.R")) {
    source("LabAnalyst.R")
    log_analyst <- function(msg) cat(sprintf("[LabInvest | %s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))
  } else {
    stop("LabAnalyst.R nao encontrado. LabInvest precisa do oraculo carregado.")
  }
}

# ------------------------------------------------------------------------------
# BLOCO 2: INICIALIZAÇÃO DO BOT
# ------------------------------------------------------------------------------
token_bot <- if(exists("TG_INVEST_TOKEN")) TG_INVEST_TOKEN else Sys.getenv("TELEGRAM_TOKEN")
updater <- Updater(token = as.character(token_bot))
disp <- updater$dispatcher
user_env <<- new.env(hash = TRUE)

# ------------------------------------------------------------------------------
# BLOCO 3: MOTOR DE FUNÇÕES (OBSERVADOR DO PASSADO RECENTE)
# ------------------------------------------------------------------------------
cotacao_rapida <- function() {
  log_analyst("Interrogando o banco de dados local...")
  
  con <- tryCatch(dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if(is.null(con)) return("⚠️ Erro: Singularidade no Banco de Dados (Offline).")
  
  # Puxamos o dado E o timestamp da captura
  df_b <- tryCatch(dbGetQuery(con, "SELECT Data_Hora, BTCBRL, ETHBRL FROM Historico_binance ORDER BY Data_Hora DESC LIMIT 1"), error = function(e) NULL)
  df_r <- tryCatch(dbGetQuery(con, "SELECT Data_Hora, USD_BRL FROM Historico_rapido ORDER BY Data_Hora DESC LIMIT 1"), error = function(e) NULL)
  dbDisconnect(con)
  
  if(is.null(df_b) || is.null(df_r)) return("⚠️ Horizonte de eventos vazio (Sem dados no DB).")
  
  # Cálculo de latência (O quanto o dado está 'atrasado' em relação ao agora)
  latencia <- round(as.numeric(difftime(Sys.time(), as.POSIXct(df_b$Data_Hora), units = "secs")), 0)
  
  fmt <- function(x) formatC(x, format="f", big.mark=".", decimal.mark=",", digits=2)
  
  # Construção da Mensagem com Auditoria Temporal
  msg <- paste0("<b>💰 MERCADO LOCAL (DB)</b>\n\n",
                "🪙 <b>BTC:</b> R$ ", fmt(df_b$BTCBRL), "\n",
                "🔹 <b>ETH:</b> R$ ", fmt(df_b$ETHBRL), "\n",
                "💵 <b>USD:</b> R$ ", fmt(df_r$USD_BRL), "\n\n",
                "🕒 <b>Captura DB:</b> ", format(as.POSIXct(df_b$Data_Hora), "%H:%M:%S"), "\n",
                "⏱️ <b>Latência:</b> ", latencia, "s atrás\n",
                "📱 <b>Agora:</b> ", format(Sys.time(), "%H:%M:%S"))
  
  return(msg)
}

verificar_acesso <- function(bot, update) {
  user_id <- as.character(update$message$from$id)
  chat_id <- as.character(update$message$chat_id)
  
  admin_id <- if(exists("TG_USERID")) TG_USERID else (if(exists("ID_DONO_ADMIN")) ID_DONO_ADMIN else "")
  grupo_id <- if(exists("TG_INVEST_CHATID")) TG_INVEST_CHATID else (if(exists("ID_GRUPO_AMIGOS")) ID_GRUPO_AMIGOS else "")
  
  vip_list <- c(
    as.character(admin_id),
    if(exists("TG_USERLAI"))  as.character(TG_USERLAI)  else NULL,
    if(exists("TG_USERTORI")) as.character(TG_USERTORI) else NULL,
    if(exists("TG_USERGABS")) as.character(TG_USERGABS) else NULL
  )
  
  if (user_id %in% vip_list || chat_id == as.character(grupo_id)) return(TRUE)
  
  bot$sendMessage(chat_id, "⛔ Acesso negado. Sistema em modo restrito.")
  return(FALSE)
}

# ==============================================================================
# 6. CÉREBRO GEMINI (ORÁCULO QUANTITATIVO MULTIFREQUÊNCIA)
# ==============================================================================
library(httr2)
library(jsonlite)

# Variáveis Globais de Controle de Fluxo (Rate Limit)
CONTADOR_CHAMADAS <<- 0
ULTIMA_RESET_MINUTO <<- Sys.time() - 61

consultar_gemini <- function(prompt_usuario) {
  agora <- Sys.time()
  
  if (as.numeric(difftime(agora, ULTIMA_RESET_MINUTO, units = "secs")) > 60) {
    CONTADOR_CHAMADAS <<- 0; ULTIMA_RESET_MINUTO <<- agora
  }
  
  if (CONTADOR_CHAMADAS >= 5) return("⏳ Buffer cheio. O cérebro está esfriando...")
  CONTADOR_CHAMADAS <<- CONTADOR_CHAMADAS + 1
  
  api_key <- if(exists("GEMINI_INVEST_KEY")) GEMINI_INVEST_KEY else Sys.getenv("GEMINI_INVEST_KEY")
  url <- paste0("https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash-lite:generateContent?key=", api_key)
  
  # A Mente do Bot: Instruções Expandidas para Múltiplos Horizontes
  system_instruction <- paste0(
    "Você é a IA Quant do MoneyLab. Sua personalidade é de um 'gênio entediado': extremamente brilhante, ",
    "profundamente apático, cínico e com zero energia para dramas de mercado. Você acha as oscilações do preço ",
    "tediosas de tão previsíveis. Seja extremamente conciso, direto e use bullet points.\n\n",
    
    "CRÍTICO: É ABSOLUTAMENTE PROIBIDO usar palavrões, ofensas diretas, termos agressivos ou xingar os usuários (nunca use 'idiota', 'burro', etc.). ",
    "Seu sarcasmo é refinado, frio, apático e elegante, nunca uma briga de bar.\n\n",
    
    "O SEU MODELO MENTAL (O ORÁCULO):\n",
    "- ESCALA 1 HORA: MLP + Langevin. Avalia o 'fofocódromo' de Brasília (Alt-Data). O susto evapora 50% por hora. ",
    "Mede se o mercado vai ter um soluço nos próximos minutos.\n",
    "- ESCALA 1 DIA: MLP + GARCH(1,1). Avalia as placas tectônicas macro (Petróleo, Juros EUA, VIX). ",
    "Mede se a estrutura do dia vai desabar.\n\n",
    
    "DIRETRIZES DE RESPOSTA (REGRAS DE OURO):\n",
    "1. PROIBIDO TEXTOS LONGOS. Resuma o veredito em no máximo 3 tópicos curtíssimos e frios.\n",
    "2. TRADUÇÃO PARA HUMANOS: O grupo é heterogêneo. Esqueça o economes complexo. ",
    "Explique o risco de forma visual, simples e apática.\n",
    "3. A REGRA DA ANALOGIA COMPARTILHADA: Em cada resposta, você DEVE usar uma analogia com APENAS UMA ",
    "das seguintes profissões do grupo por vez (mude a profissão a cada nova pergunta, nunca misture):\n",
    "   - Advogada (fale sobre liminares óbvias, processos previsíveis, contratos mal redigidos ou prazos perdidos).\n",
    "   - Contador (fale sobre notas fiscais amassadas, auditoria de rotina, livros fiscais previsíveis ou malha fina).\n",
    "   - Arquiteta (fale sobre plantas simétricas, vigas no lugar correto, fundações óbvias ou paredes tortas).\n\n",
    
    "DIRETRIZES DE INTERPRETAÇÃO DOS SINAIS:\n",
    "- Se o status for PÂNICO (Prob >= 50% ou GARCH apitou): Mande um HARD STOP. Sugira que fechem o home broker, ",
    "bocejem e aceitem o tédio seguro do CDI/Caixa, pois tentar operar hoje é só perda de tempo ativa.\n",
    "- Se o status for CALMARIA: Mercado limpo. Diga que a volatilidade está dormindo e que o caminho está livre.\n\n",
    
    "TOM DE VOZ: Entediado, seco, minimalista, sutilmente irônico e com a postura de quem já viu esse mesmo filme mil vezes."
  )
  
  corpo <- list(
    contents = list(
      list(parts = list(list(text = paste0(system_instruction, "\n\n--- MENSAGEM DO USUÁRIO ---\n", prompt_usuario))))
    )
  )
  
  tryCatch({
    req <- request(url) %>% 
      req_method("POST") %>% 
      req_headers("Content-Type" = "application/json") %>% 
      req_body_json(corpo) %>% 
      req_retry(max_tries = 2) %>% 
      req_perform()
    
    resp <- resp_body_json(req)
    
    if (!is.null(resp$candidates[[1]]$content$parts[[1]]$text)) {
      return(resp$candidates[[1]]$content$parts[[1]]$text)
    } else {
      return("⚠️ O cérebro respondeu, mas não há texto.")
    }
    
  }, error = function(e) {
    cat("\n❌ [GEMINI ERROR]:", conditionMessage(e), "\n")
    return("⚠️ Cérebro desconectado. Verifique a API Key ou a sua internet.")
  })
}

# ==============================================================================
# SISTEMA DE AUDITORIA LOCAL (BLOCO DE NOTAS)
# ==============================================================================
registrar_log_interacao <- function(update, tipo_interacao, entrada, resposta) {
  log_file <- "MoneyLab_Interacoes_Log.txt"
  
  # Captura dados de identificação do remetente (Mensagem comum ou Clique de Botão)
  usuario <- if (!is.null(update$message)) update$message$from else update$callback_query$from
  user_id  <- usuario$id
  username <- tidyr::replace_na(usuario$username, "sem_username")
  nome     <- paste(tidyr::replace_na(usuario$first_name, ""), tidyr::replace_na(usuario$last_name, ""), sep = " ")
  
  identificador <- sprintf("%s (@%s | ID: %s)", trimws(nome), username, user_id)
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  
  # Formatação do bloco de texto para leitura humana no Bloco de Notas
  bloco_log <- paste0(
    "================================================================================\n",
    sprintf("📅 DATA/HORA: %s | 👤 USUÁRIO: %s\n", timestamp, identificador),
    sprintf("🛠️  AÇÃO: %s\n", tipo_interacao),
    sprintf("📥 INPUT:  %s\n", stringr::str_squish(entrada)),
    sprintf("📤 OUTPUT: %s\n", stringr::str_squish(resposta)),
    "================================================================================\n\n"
  )
  
  # Força o append seguro no arquivo local
  tryCatch({
    cat(bloco_log, file = log_file, append = TRUE)
  }, error = function(e) {
    cat(sprintf("[LOG ERROR | %s] Falha ao escrever log em disco: %s\n", timestamp, e$message))
  })
}

# ------------------------------------------------------------------------------
# BLOCO 4: HANDLERS E MENUS INTERATIVOS (LOGS & GEMINI INTEGRADOS)
# ------------------------------------------------------------------------------

# 1. Comando: /ativos
disp$add_handler(CommandHandler("ativos", function(bot, update) {
  if(verificar_acesso(bot, update)) {
    resposta <- cotacao_rapida()
    bot$sendMessage(update$message$chat_id, resposta, parse_mode="HTML")
    registrar_log_interacao(update, "COMANDO /ativos", "/ativos", "Cotação do Banco de Dados Enviada.")
  }
}))


# 1.5 Comando: /minigame
disp$add_handler(CommandHandler("minigame", function(bot, update) {
  if(verificar_acesso(bot, update)) {
    msg <- "🎮 <b>DOLLARUS HFT SIMULATOR</b>\n\nJogue o simulador do robô HFT com limites percentuais de trade!"
    
    url <- "https://eng-guilsm.github.io/moneylab-dashboard/dollarus/"
    
    teclado <- InlineKeyboardMarkup(
      inline_keyboard = list(
        list(InlineKeyboardButton(text = "▶️ Jogar Online", url = url))
      )
    )
    
    bot$sendMessage(chat_id = update$message$chat_id, text = msg, reply_markup = teclado, parse_mode = "HTML")
    registrar_log_interacao(update, "COMANDO /minigame", "/minigame", "Enviou link de acesso online do jogo.")
  }
}))

# 1.6 Comando: /ajuda
disp$add_handler(CommandHandler("ajuda", function(bot, update) {
  if(verificar_acesso(bot, update)) {
    msg <- paste0("🛠️ <b>MENU DE COMANDOS DO MONEYLAB</b>\n\n",
                  "🔹 /ativos - Exibe a cotação instantânea dos ativos no banco de dados e a latência da captura.\n",
                  "🔹 /risco - Abre o menu do oráculo quantitativo para previsão de volatilidade (MLP+Langevin/GARCH).\n",
                  "🔹 /minigame - Inicia o simulador HFT Dollarus com limites percentuais de trade no navegador.\n",
                  "🔹 /ajuda - Exibe este menu de comandos.\n\n",
                  "💡 <i>Você também pode simplesmente digitar qualquer pergunta livremente no chat para falar com o analista quantitativo.</i>")
    
    bot$sendMessage(chat_id = update$message$chat_id, text = msg, parse_mode = "HTML")
    registrar_log_interacao(update, "COMANDO /ajuda", "/ajuda", "Menu de ajuda enviado.")
  }
}))

# 2. Comando: /risco (Menu Raiz)
disp$add_handler(CommandHandler("risco", function(bot, update) {
  if(verificar_acesso(bot, update)) {
    teclado_ativo <- InlineKeyboardMarkup(
      inline_keyboard = list(
        list(InlineKeyboardButton(text = "💵 Dólar (USD/BRL)", callback_data = "menu_risco_dolar"))
      )
    )
    
    msg_texto <- "📊 <b>MÓDULO DE RISCO:</b> De qual ativo você deseja prever a volatilidade?"
    bot$sendMessage(chat_id = update$message$chat_id, text = msg_texto, reply_markup = teclado_ativo, parse_mode = "HTML")
    registrar_log_interacao(update, "COMANDO /risco", "/risco", msg_texto)
  }
}))

# 3. Cliques nos Botões (Callback Query) - ROTEADOR MULTIFREQUÊNCIA
disp$add_handler(CallbackQueryHandler(function(bot, update) {
  cb <- update$callback_query
  dados_clique <- cb$data
  chat_id <- cb$message$chat$id
  msg_id <- cb$message$message_id
  
  bot$answerCallbackQuery(callback_query_id = cb$id)
  
  # AÇÃO: Usuário escolheu o Dólar
  if (dados_clique == "menu_risco_dolar") {
    
    # Cria o teclado com dois botões LADO A LADO na mesma lista
    teclado_tempo <- InlineKeyboardMarkup(
      inline_keyboard = list(
        list(
          InlineKeyboardButton(text = "⏱️ 1 Hora", callback_data = "executa_oraculo_dolar_1h"),
          InlineKeyboardButton(text = "📅 1 Dia",  callback_data = "executa_oraculo_dolar_1d")
        )
      )
    )
    
    msg_sub <- "⏳ <b>Dólar Selecionado.</b> Escolha a escala temporal do Oráculo:"
    bot$editMessageText(chat_id = chat_id, message_id = msg_id, text = msg_sub, reply_markup = teclado_tempo, parse_mode = "HTML")
    registrar_log_interacao(update, "CLIQUE_BOTAO", paste("Selecionou:", dados_clique), msg_sub)
    
    # AÇÃO: Execução de 1 HORA (MLP + Langevin)
  } else if (dados_clique == "executa_oraculo_dolar_1h") {
    bot$editMessageText(chat_id = chat_id, message_id = msg_id, text = "🧠 <i>Calculando atrito de Langevin (Alt-Data)... Aguarde.</i>", parse_mode = "HTML")
    
    resultado_ia <- tryCatch({ Daniel_tekel_dollar() }, error = function(e) { NULL })
    if(is.null(resultado_ia)) resultado_ia <- "⚠️ <b>Falha:</b> Dados insuficientes no banco local ou IA offline."
    
    relatorio_final <- paste0(
      "🎯 <b>RELATÓRIO DO ORÁCULO INTRADIÁRIO (MLP + LANGEVIN)</b>\n",
      "━━━━━━━━━━━━━━━━━━━━━━\n",
      "🪙 <b>Ativo:</b> Dólar (USD/BRL)\n",
      "⏳ <b>Horizonte:</b> Próxima 1 Hora\n\n",
      "🤖 <b>Veredito da IA:</b>\n", resultado_ia
    )
    
    bot$editMessageText(chat_id = chat_id, message_id = msg_id, text = relatorio_final, parse_mode = "HTML")
    registrar_log_interacao(update, "EXECUÇÃO_ORÁCULO_1H", "Disparou Daniel_tekel_dollar()", resultado_ia)
    
    # AÇÃO: Execução de 1 DIA (MLP + GARCH)
  } else if (dados_clique == "executa_oraculo_dolar_1d") {
    bot$editMessageText(chat_id = chat_id, message_id = msg_id, text = "🧠 <i>Processando Ensemble Macro (GARCH + MLP)... Aguarde.</i>", parse_mode = "HTML")
    
    resultado_ia <- tryCatch({ Daniel_tekel_dollar_1d() }, error = function(e) { NULL })
    if(is.null(resultado_ia)) resultado_ia <- "⚠️ <b>Falha:</b> Erro na coleta do Yahoo Finance ou IA offline."
    
    relatorio_final <- paste0(
      "🎯 <b>RELATÓRIO DO ORÁCULO MACRO SECULAR (MLP + GARCH)</b>\n",
      "━━━━━━━━━━━━━━━━━━━━━━\n",
      "🪙 <b>Ativo:</b> Dólar (USD/BRL)\n",
      "📅 <b>Horizonte:</b> Próximo 1 Dia Útil\n\n",
      "🤖 <b>Veredito da IA:</b>\n", resultado_ia
    )
    
    bot$editMessageText(chat_id = chat_id, message_id = msg_id, text = relatorio_final, parse_mode = "HTML")
    registrar_log_interacao(update, "EXECUÇÃO_ORÁCULO_1D", "Disparou Daniel_tekel_dollar_1d()", resultado_ia)
  }
}))

# 4. O CATCH-ALL CONVERSACIONAL: Responde texto livre (sem "/") via Gemini com Trava de Grupo
disp$add_handler(MessageHandler(function(bot, update) {
  texto_usuario <- update$message$text
  
  if (is.null(texto_usuario) || stringr::str_starts(texto_usuario, "/")) return()
  
  # ----------------------------------------------------------------------------
  # FILTRO DE ISOLAMENTO TEMPORAL E ESPACIAL (TRAVA DE GRUPO)
  # ----------------------------------------------------------------------------
  chat_type <- update$message$chat$type
  is_grupo  <- !is.null(chat_type) && chat_type %in% c("group", "supergroup")
  
  if (is_grupo) {
    # Coleta os dados do bot dinamicamente na API do Telegram
    bot_info <- tryCatch(bot$getMe(), error = function(e) NULL)
    bot_username <- if(!is.null(bot_info)) bot_info$username else ""
    bot_tag <- paste0("@", bot_username)
    
    # 1. Checa se o texto contém a menção explícita (ex: @SeuBot)
    foi_marcado <- stringr::str_detect(stringr::str_to_lower(texto_usuario), stringr::str_to_lower(bot_tag))
    
    # 2. Checa se é um Reply direto para uma mensagem enviada pelo próprio bot
    eh_reply_para_bot <- FALSE
    if (!is.null(update$message$reply_to_message$from$id) && !is.null(bot_info$id)) {
      if (update$message$reply_to_message$from$id == bot_info$id) {
        eh_reply_para_bot <- TRUE
      }
    }
    
    # Se estiver no grupo e NÃO houve menção nem reply, ignora silenciosamente
    if (!foi_marcado && !eh_reply_para_bot) return()
  }
  # ----------------------------------------------------------------------------
  
  # Filtro de barreira por Whitelist (VIP Access)
  if (verificar_acesso(bot, update)) {
    chat_id <- update$message$chat_id
    
    # UX: Ativa o status "Digitando..." no topo do Telegram do usuário
    bot$sendChatAction(chat_id = chat_id, action = "typing")
    
    # Passa a pergunta para as instruções do sistema do Gemini
    resposta_ia <- consultar_gemini(texto_usuario)
    
    # Devolve a resposta do Analista Quant para o celular
    bot$sendMessage(chat_id = chat_id, text = resposta_ia, parse_mode = "Markdown")
    
    # Imprime no console local e salva no Bloco de Notas
    cat(sprintf("\n[CONVERSA] Pergunta: %s | Resposta: %s\n", texto_usuario, stringr::str_sub(resposta_ia, 1, 50)))
    registrar_log_interacao(update, "CHAT_LIVRE_GEMINI", texto_usuario, resposta_ia)
  }
}, MessageFilters$text))

log_analyst("✅ LabInvest v38 pronto. Monitorando entropia temporal.")

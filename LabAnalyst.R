# ==============================================================================
# LabAnalyst.R - Motor Analitico do MoneyLab
# Versao: 12.0 | Alt-Data politico global + oraculo USD/BRL 1h validado
# ==============================================================================
options(encoding = "UTF-8", scipen = 999, xts.warn_dplyr_breaks_lag = FALSE)
options(repos = c(CRAN = "https://cloud.r-project.org"))

LOCAL_R_LIB <- file.path(getwd(), "r-lib")
if (!dir.exists(LOCAL_R_LIB)) dir.create(LOCAL_R_LIB, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(LOCAL_R_LIB, .libPaths())))

pkgs <- c("quantmod", "dplyr", "lubridate", "jsonlite", "PerformanceAnalytics",
          "TTR", "zoo", "tidyr", "vars", "DBI", "RSQLite", "ggplot2",
          "scales", "tidyRSS", "stringr", "digest", "rugarch", "nnet")

invisible(lapply(pkgs, function(p) {
  if (!require(p, character.only = TRUE, quietly = TRUE)) install.packages(p, quiet = TRUE)
  library(p, character.only = TRUE)
}))

if (file.exists("config_auth.R")) source("config_auth.R")
DB_FILE <- "MoneyBot_Local.db"

MAPA_TICKERS <- list("USD" = "USDBRL=X", "BTC" = "BTC-USD", "IBOV" = "^BVSP",
                     "ETH" = "ETH-USD", "VIX" = "^VIX")

log_analyst <- function(msg) {
  cat(sprintf("[LabAnalyst | %s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))
}

normalizar_ativo <- function(nome) {
  nome <- toupper(trimws(nome))
  if (nome %in% c("DOLAR", "USDBRL", "USD")) return("USD")
  if (nome %in% c("BITCOIN", "BTC")) return("BTC")
  if (nome %in% c("ETHEREUM", "ETH")) return("ETH")
  nome
}

get_data_safe <- function(tkr, days = 365) {
  tryCatch({
    s <- getSymbols(tkr, src = "yahoo", from = Sys.Date() - days, auto.assign = FALSE)
    zoo::na.locf(zoo::na.locf(s[, 4], na.rm = FALSE), fromLast = TRUE)
  }, error = function(e) NULL)
}

# ==============================================================================
# MODULO 1: AUDITORIA CLASSICA
# ==============================================================================

calcular_zscore <- function(ativo, janela = 180) {
  tkr <- normalizar_ativo(ativo)
  tkr_yahoo <- ifelse(!is.null(MAPA_TICKERS[[tkr]]), MAPA_TICKERS[[tkr]], tkr)
  dados <- get_data_safe(tkr_yahoo, days = janela + 20)
  if (is.null(dados)) return(0)
  precos <- as.numeric(dados)
  round((tail(precos, 1) - mean(precos)) / sd(precos), 2)
}

simular_montecarlo <- function(ativo, dias = 7) {
  tkr <- normalizar_ativo(ativo)
  tkr_y <- ifelse(!is.null(MAPA_TICKERS[[tkr]]), MAPA_TICKERS[[tkr]], tkr)
  d <- get_data_safe(tkr_y, 730)
  rets <- na.omit(diff(log(d)))
  sims <- replicate(1000, as.numeric(tail(d, 1)) * exp(sum(sample(rets, dias, replace = TRUE))))
  list(p5 = quantile(sims, 0.05), med = mean(sims), p95 = quantile(sims, 0.95))
}

executar_analise_estatistica <- function(ativo_bruto) {
  tkr <- normalizar_ativo(ativo_bruto)
  log_analyst(paste("Processando auditoria classica:", tkr))
  usd_rate <- tryCatch(as.numeric(getQuote("USDBRL=X")$Last), error = function(e) 5.20)
  tkr_y <- ifelse(!is.null(MAPA_TICKERS[[tkr]]), MAPA_TICKERS[[tkr]], tkr)
  dados <- get_data_safe(tkr_y)
  if (is.null(dados)) return("ERRO: Ativo nao encontrado.")

  preco_raw <- as.numeric(tail(dados, 1))
  preco_real <- if (tkr %in% c("BTC", "ETH", "USD")) preco_raw * ifelse(tkr == "USD", 1, usd_rate) else preco_raw
  mc <- simular_montecarlo(tkr)
  z_val <- calcular_zscore(tkr)
  p_mc <- as.numeric(mc$med > preco_raw)
  f_kelly <- p_mc - (1 - p_mc) / 0.10
  kelly_final <- max(0, f_kelly / 2)

  sprintf("ATIVO:%s|ATUAL:%.2f|JUSTO:%.2f|UPSIDE:%.1f%%|P5:%.2f|P95:%.2f|KELLY:%.1f%%|ZSCORE:%.2f",
          tkr, preco_real, mc$med * ifelse(tkr %in% c("BTC", "ETH"), usd_rate, 1),
          ((mc$med / preco_raw) - 1) * 100,
          mc$p5 * ifelse(tkr %in% c("BTC", "ETH"), usd_rate, 1),
          mc$p95 * ifelse(tkr %in% c("BTC", "ETH"), usd_rate, 1),
          kelly_final * 100, z_val)
}

carregar_dados_sincronizados <- function(anos = 5) {
  inicio <- Sys.Date() - 365 * anos
  get_c <- function(tkr) {
    tryCatch({
      s <- getSymbols(tkr, src = "yahoo", from = inicio, auto.assign = FALSE)
      zoo::na.locf(Cl(s))
    }, error = function(e) NULL)
  }

  usd <- get_c(MAPA_TICKERS$USD)
  btc <- get_c(MAPA_TICKERS$BTC)
  ibov <- get_c(MAPA_TICKERS$IBOV)
  dados <- merge(usd, btc, ibov)
  colnames(dados) <- c("USD", "BTC", "IBOV")
  na.omit(dados)
}

calc_dist <- function(ref_usd, ref_btc, ref_ibov, h_usd, h_btc, h_ibov) {
  d_u <- (h_usd - ref_usd) / ref_usd
  d_b <- (h_btc - ref_btc) / ref_btc
  d_i <- (h_ibov - ref_ibov) / ref_ibov
  sqrt(d_u^2 + d_b^2 + d_i^2)
}

simular_knn <- function(ativo_alvo, data_compra = Sys.Date(), data_venda = Sys.Date() + 30,
                        valor_investido = 1000, k = 50) {
  ativo_alvo <- toupper(trimws(ativo_alvo))
  if (ativo_alvo %in% c("DOLAR", "USDBRL")) ativo_alvo <- "USD"
  if (ativo_alvo %in% c("BITCOIN")) ativo_alvo <- "BTC"
  if (ativo_alvo %in% c("IBOVESPA", "INDICE")) ativo_alvo <- "IBOV"
  if (!ativo_alvo %in% c("USD", "BTC", "IBOV")) {
    return("Ativo nao suportado pelo KNN. Tente: BTC, USD ou IBOV.")
  }

  d_compra <- as.Date(data_compra)
  d_venda <- as.Date(data_venda)
  dias_h <- as.numeric(d_venda - d_compra)
  if (dias_h <= 0) return("Data futura deve ser maior que hoje.")

  base_xts <- carregar_dados_sincronizados()
  if (is.null(base_xts) || nrow(base_xts) < 200) return("Dados insuficientes para KNN.")
  df_hist <- data.frame(Data = zoo::index(base_xts), zoo::coredata(base_xts))
  idx_ref <- which.min(abs(df_hist$Data - d_compra))
  ref <- df_hist[idx_ref, ]

  max_date <- max(df_hist$Data)
  min_date <- min(df_hist$Data)
  total_days <- as.numeric(max_date - min_date)
  df_knn <- df_hist %>%
    dplyr::filter(abs(as.numeric(Data - d_compra)) > 10) %>%
    dplyr::mutate(
      Dist = calc_dist(ref$USD, ref$BTC, ref$IBOV, USD, BTC, IBOV),
      Recencia = as.numeric(Data - min_date) / total_days,
      Peso = (1 / (Dist + 0.000001)) * (1 + Recencia^2)
    ) %>%
    dplyr::arrange(dplyr::desc(Peso)) %>%
    utils::head(k)

  sim_resultados <- data.frame(Final = numeric(), Peso = numeric())
  for (i in seq_len(nrow(df_knn))) {
    d_futura <- df_knn$Data[i] + lubridate::days(dias_h)
    idx_futuro <- which(df_hist$Data >= d_futura)[1]
    if (!is.na(idx_futuro) && idx_futuro <= nrow(df_hist)) {
      retorno <- df_hist[[ativo_alvo]][idx_futuro] / df_knn[[ativo_alvo]][i]
      sim_resultados <- rbind(sim_resultados,
                              data.frame(Final = valor_investido * retorno, Peso = df_knn$Peso[i]))
    }
  }
  if (nrow(sim_resultados) == 0) return("Dados insuficientes para projetar esse prazo.")

  media_pond <- weighted.mean(sim_resultados$Final, sim_resultados$Peso)
  lucro_pct <- ((media_pond - valor_investido) / valor_investido) * 100
  prob_win <- sum(sim_resultados$Peso[sim_resultados$Final > valor_investido]) / sum(sim_resultados$Peso) * 100
  paste0(
    "<b>SIMULACAO KNN (", ativo_alvo, ")</b>\n",
    "Prazo: ", dias_h, " dias\n",
    "Cenarios similares: ", nrow(sim_resultados), "\n",
    "Probabilidade de lucro: ", format(round(prob_win, 1), nsmall = 1), "%\n",
    "Resultado esperado: R$ ", format(round(media_pond, 2), big.mark = ".", decimal.mark = ","), "\n",
    "Retorno medio: ", ifelse(lucro_pct >= 0, "+", ""), format(round(lucro_pct, 2), decimal.mark = ","), "%"
  )
}

# ==============================================================================
# MODULO 2: TRACKER ALT-DATA (ATORES, SENTIMENTO E DENSIDADE)
# ==============================================================================

normalizar_texto_noticia <- function(x) {
  x <- tidyr::replace_na(as.character(x), "")
  x <- stringr::str_to_lower(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "")
  stringr::str_squish(x)
}

regex_or <- function(termos) {
  termos <- termos[!is.na(termos) & nzchar(termos)]
  paste0("\\b(", paste(unique(termos), collapse = "|"), ")\\b")
}

atores_politicos <- data.frame(
  ator_canonico = c("lula", "bolsonaro", "haddad", "campos neto", "trump",
                    "powell", "milei", "xi jinping", "putin"),
  aliases = c(
    "lula|luiz inacio lula|presidente lula",
    "bolsonaro|jair bolsonaro|ex-presidente bolsonaro",
    "haddad|fernando haddad|ministro da fazenda",
    "campos neto|roberto campos neto|presidente do banco central|banco central",
    "trump|donald trump|presidente dos eua|white house",
    "powell|jerome powell|fed|federal reserve",
    "milei|javier milei|presidente argentino|argentina",
    "xi jinping|china|pequim",
    "putin|vladimir putin|kremlin|russia"
  ),
  escopo = c("nacional", "nacional", "nacional", "nacional", "internacional",
             "internacional", "internacional", "internacional", "internacional"),
  peso_mercado = c(1.25, 0.85, 1.35, 1.45, 1.15, 1.50, 0.85, 1.05, 0.95),
  stringsAsFactors = FALSE
)

identificar_ator <- function(texto, regex_atores, tabela_atores) {
  hit <- stringr::str_extract(texto, regex_atores)
  if (is.na(hit)) return(list(ator = NA_character_, escopo = NA_character_, peso = 1))
  linha <- tabela_atores[stringr::str_detect(hit, tabela_atores$aliases), , drop = FALSE]
  if (nrow(linha) == 0) linha <- tabela_atores[stringr::str_detect(tabela_atores$aliases, hit), , drop = FALSE]
  if (nrow(linha) == 0) return(list(ator = hit, escopo = NA_character_, peso = 1))
  list(ator = linha$ator_canonico[1], escopo = linha$escopo[1], peso = linha$peso_mercado[1])
}

construir_perfil_alvo <- function(tipo_alvo = "politico") {
  if (tipo_alvo %in% c("politico", "politico_global")) {
    dicionario <- list(
      Ruptura = regex_or(c("impeachment", "cassacao", "renuncia", "golpe de estado",
                           "crise institucional", "estado de emergencia", "shutdown")),
      Juridico = regex_or(c("stf", "tse", "pf", "policia federal", "denuncia",
                            "inquerito", "prisao", "cpi", "suprema corte", "indictment")),
      Economico = regex_or(c("fiscal", "deficit", "arcabouco", "selic", "juros",
                             "banco central", "inflacao", "dolar", "tarifa",
                             "fed", "federal reserve", "orcamento", "taxa")),
      Apoio = regex_or(c("apoio", "aprovacao", "popularidade", "aliado",
                         "acordo", "pacote aprovado", "vitoria", "sinaliza alivio")),
      Etica = regex_or(c("corrupcao", "propina", "fake news", "joias", "desvio",
                         "rachadinha", "fraude", "lavagem", "escandalo")),
      RiscoFX = regex_or(c("intervencao", "cambio", "iof", "capital estrangeiro",
                           "fluxo cambial", "risco brasil", "emergentes", "treasury"))
    )
    pesos <- c(Ruptura = 1.40, Juridico = 1.10, Economico = 1.35,
               Apoio = -0.65, Etica = 1.05, RiscoFX = 1.55)
    atores <- atores_politicos
  } else if (tipo_alvo == "cripto") {
    dicionario <- list(
      Ruptura = regex_or(c("banimento", "proibicao", "hack", "exploit", "falencia", "colapso")),
      Juridico = regex_or(c("sec", "regulamentacao", "investigacao", "lavagem de dinheiro", "processo")),
      Economico = regex_or(c("halving", "etf", "inflacao", "taxa de juros", "liquidacoes", "volume")),
      Apoio = regex_or(c("adocao", "institucional", "recorde", "all-time high", "atualizacao")),
      Etica = regex_or(c("scam", "fraude", "ponzi", "rug pull", "ftx")),
      RiscoFX = regex_or(c("dolar", "juros", "fed", "liquidez"))
    )
    pesos <- c(Ruptura = 1.35, Juridico = 1.10, Economico = 0.95,
               Apoio = -0.55, Etica = 1.25, RiscoFX = 0.70)
    atores <- data.frame(
      ator_canonico = c("bitcoin", "ethereum", "crypto"),
      aliases = c("bitcoin|btc", "ethereum|eth", "crypto|cripto"),
      escopo = c("cripto", "cripto", "cripto"),
      peso_mercado = c(1.15, 0.95, 1.0),
      stringsAsFactors = FALSE
    )
  } else {
    stop("Tipo de alvo nao suportado.")
  }

  list(tipo = tipo_alvo, atores = atores,
       alvos_regex = regex_or(unlist(strsplit(atores$aliases, "\\|"))),
       clusters = dicionario, pesos = pesos)
}

processar_fluxo_rss <- function(urls_rss, perfil_alvo, janela_horas = 12) {
  tipo_alvo <- perfil_alvo$tipo
  alvos_regex <- perfil_alvo$alvos_regex
  dicionario <- perfil_alvo$clusters
  pesos <- perfil_alvo$pesos
  atores <- perfil_alvo$atores
  resultados_totais <- data.frame()
  data_corte <- lubridate::now() - lubridate::hours(janela_horas)

  for (url in urls_rss) {
    feed <- tryCatch(tidyRSS::tidyfeed(url), error = function(e) return(NULL))
    if (is.null(feed) || nrow(feed) == 0) next

    noticias <- feed %>%
      dplyr::select(dplyr::any_of(c("item_pub_date", "item_title", "item_description", "item_link"))) %>%
      dplyr::mutate(
        item_pub_date = if ("item_pub_date" %in% names(.)) item_pub_date else lubridate::now(),
        item_link = if ("item_link" %in% names(.)) item_link else NA_character_,
        item_description = if ("item_description" %in% names(.)) item_description else NA_character_
      ) %>%
      dplyr::mutate(
        data_publicacao = lubridate::as_datetime(item_pub_date),
        data_publicacao = dplyr::if_else(is.na(data_publicacao), lubridate::now(), data_publicacao),
        titulo_limpo = normalizar_texto_noticia(item_title),
        texto_bruto = paste(tidyr::replace_na(item_title, ""), tidyr::replace_na(item_description, ""), sep = " "),
        texto_limpo = normalizar_texto_noticia(texto_bruto),
        qtd_palavras = pmax(stringr::str_count(texto_limpo, "\\w+"), 1L),
        ator_no_titulo = stringr::str_detect(titulo_limpo, alvos_regex),
        ator_no_texto = stringr::str_detect(texto_limpo, alvos_regex)
      ) %>%
      dplyr::filter(data_publicacao >= data_corte, ator_no_texto)

    if (nrow(noticias) == 0) next

    noticias$ator_info <- lapply(ifelse(noticias$ator_no_titulo, noticias$titulo_limpo, noticias$texto_limpo),
                                 identificar_ator, regex_atores = alvos_regex, tabela_atores = atores)

    noticias_alvo <- noticias %>%
      dplyr::mutate(
        categoria_alvo = tipo_alvo,
        ator_mencionado = vapply(ator_info, function(x) x$ator, character(1)),
        escopo_noticia = vapply(ator_info, function(x) x$escopo, character(1)),
        peso_ator = as.numeric(vapply(ator_info, function(x) x$peso, numeric(1))),
        fonte_url = url,
        relevancia_titulo = ifelse(ator_no_titulo, 1.0, 0.55),
        id_hash = sapply(paste(item_title, item_link, fonte_url), digest::digest, algo = "md5")
      ) %>%
      dplyr::select(-ator_info)

    for (cluster_nome in names(dicionario)) {
      regex_padrao <- dicionario[[cluster_nome]]
      nome_col_densidade <- paste0("den_", stringr::str_to_lower(cluster_nome))
      nome_col_abs <- paste0("abs_", stringr::str_to_lower(cluster_nome))
      noticias_alvo[[nome_col_abs]] <- stringr::str_count(noticias_alvo$texto_limpo, regex_padrao)
      noticias_alvo[[nome_col_densidade]] <- round((noticias_alvo[[nome_col_abs]] / noticias_alvo$qtd_palavras) * 100, 4)
    }

    resultados_totais <- dplyr::bind_rows(resultados_totais, noticias_alvo)
  }

  if (nrow(resultados_totais) == 0) return(NULL)
  den_cols <- paste0("den_", stringr::str_to_lower(names(dicionario)))
  matriz_den <- as.matrix(resultados_totais[, den_cols, drop = FALSE])
  pesos_ord <- pesos[names(dicionario)]

  dados_banco <- resultados_totais %>%
    dplyr::mutate(
      data_coleta = format(lubridate::now(), "%Y-%m-%d %H:%M:%S"),
      data_publicacao = format(data_publicacao, "%Y-%m-%d %H:%M:%S"),
      densidade_total = rowSums(dplyr::across(dplyr::all_of(den_cols)), na.rm = TRUE),
      score_sentimento = as.numeric(matriz_den %*% pesos_ord),
      score_mercado = round(score_sentimento * relevancia_titulo * peso_ator, 4),
      risco_politico = pmax(score_mercado, 0),
      apoio_politico = abs(pmin(score_mercado, 0)),
      flag_alerta = ifelse(risco_politico >= 1.25 | densidade_total >= 2.0, 1, 0)
    ) %>%
    dplyr::select(id_hash, data_coleta, data_publicacao, fonte_url, categoria_alvo,
                  escopo_noticia, ator_mencionado, peso_ator, relevancia_titulo,
                  item_title, qtd_palavras, dplyr::all_of(den_cols),
                  dplyr::starts_with("abs_"), densidade_total, score_sentimento,
                  score_mercado, risco_politico, apoio_politico, flag_alerta, item_link)

  dados_banco[!duplicated(dados_banco$id_hash), ]
}

db_append_altdata <- function(con, dados) {
  tabela <- "AltData_Sentiment"
  if (!DBI::dbExistsTable(con, tabela)) {
    DBI::dbWriteTable(con, tabela, dados, append = FALSE)
    return(TRUE)
  }

  existentes <- DBI::dbListFields(con, tabela)
  faltantes <- setdiff(names(dados), existentes)
  for (col in faltantes) {
    valor <- dados[[col]]
    tipo_sql <- if (is.numeric(valor) || is.integer(valor)) "REAL" else "TEXT"
    DBI::dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s", tabela, col, tipo_sql))
  }

  hashes_existentes <- DBI::dbGetQuery(con, "SELECT id_hash FROM AltData_Sentiment")$id_hash
  dados <- dados %>% dplyr::filter(!id_hash %in% hashes_existentes)
  if (nrow(dados) == 0) return(FALSE)
  DBI::dbWriteTable(con, tabela, dados, append = TRUE)
  TRUE
}

executar_etl_sentimento <- function(urls_rss, tipo = "politico", janela_horas = 12) {
  log_analyst(paste("Iniciando ETL de Alt-Data. Perfil:", tipo))
  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if (is.null(con)) {
    log_analyst("Erro de conexao com SQLite.")
    return(FALSE)
  }
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  perfil <- construir_perfil_alvo(tipo)
  dados <- processar_fluxo_rss(urls_rss, perfil, janela_horas)
  if (!is.null(dados) && nrow(dados) > 0) {
    inseriu <- db_append_altdata(con, dados)
    if (inseriu) {
      log_analyst(sprintf("ETL concluido. %d candidatos processados para o nucleo.", nrow(dados)))
    } else {
      log_analyst("Nenhuma noticia nova identificada. Banco atualizado.")
    }
  } else {
    log_analyst("Sem volume de dados para o perfil nesta janela.")
  }
  TRUE
}

# ==============================================================================
# MODULO 3: ORACULO QUANTITATIVO USD/BRL 1H
# ==============================================================================

decair_langevin <- function(x, lambda = 0.62) {
  if (length(x) == 0) return(x)
  out <- tidyr::replace_na(as.numeric(x), 0)
  for (i in seq_along(out)[-1]) {
    if (out[i] == 0) out[i] <- out[i - 1] * lambda
  }
  out
}

normalizar_matriz <- function(x_train, x_new = NULL) {
  mins <- apply(x_train, 2, min, na.rm = TRUE)
  maxs <- apply(x_train, 2, max, na.rm = TRUE)
  escala <- pmax(maxs - mins, .Machine$double.eps)
  x_train <- sweep(sweep(x_train, 2, mins, "-"), 2, escala, "/")
  if (!is.null(x_new)) x_new <- sweep(sweep(x_new, 2, mins, "-"), 2, escala, "/")
  list(train = x_train, new = x_new)
}

calibrar_threshold <- function(prob, y, alvo_min = 0.75, alvo_max = 0.80) {
  grade <- seq(0.30, 0.70, by = 0.01)
  acc <- vapply(grade, function(th) mean(ifelse(prob >= th, 1, 0) == y), numeric(1))
  dentro <- which(acc >= alvo_min & acc <= alvo_max)
  if (length(dentro) > 0) {
    idx <- dentro[which.max(acc[dentro])]
  } else {
    idx <- which.min(abs(acc - ((alvo_min + alvo_max) / 2)))
  }
  list(threshold = grade[idx], accuracy = acc[idx], atingiu_meta = acc[idx] >= alvo_min & acc[idx] <= alvo_max)
}

montar_base_dollar_1h <- function(df_usd_raw, df_sent_raw = NULL) {
  df_hourly <- df_usd_raw %>%
    dplyr::mutate(Hora = lubridate::floor_date(as.POSIXct(Data_Hora, format = "%Y-%m-%d %H:%M:%S"), "hour")) %>%
    dplyr::group_by(Hora) %>%
    dplyr::summarise(Close = dplyr::last(USD_BRL), .groups = "drop") %>%
    dplyr::filter(!is.na(Close), Close > 0, Close <= 7.50) %>%
    dplyr::arrange(Hora)

  grid_tempo <- data.frame(Hora = seq(min(df_hourly$Hora), max(df_hourly$Hora), by = "hour"))
  df_base <- dplyr::left_join(grid_tempo, df_hourly, by = "Hora") %>%
    dplyr::mutate(Close = zoo::na.locf(zoo::na.locf(Close, na.rm = FALSE), fromLast = TRUE))

  if (!is.null(df_sent_raw) && nrow(df_sent_raw) > 0) {
    sent <- df_sent_raw %>%
      dplyr::mutate(
        Hora = lubridate::floor_date(as.POSIXct(data_publicacao, format = "%Y-%m-%d %H:%M:%S"), "hour"),
        score_mercado = if ("score_mercado" %in% names(.)) score_mercado else densidade_total,
        risco_politico = if ("risco_politico" %in% names(.)) risco_politico else pmax(score_mercado, 0),
        apoio_politico = if ("apoio_politico" %in% names(.)) apoio_politico else 0,
        escopo_noticia = if ("escopo_noticia" %in% names(.)) escopo_noticia else "nacional"
      ) %>%
      dplyr::group_by(Hora) %>%
      dplyr::summarise(
        Risco_Total = sum(risco_politico, na.rm = TRUE),
        Apoio_Total = sum(apoio_politico, na.rm = TRUE),
        Risco_Nacional = sum(risco_politico[escopo_noticia == "nacional"], na.rm = TRUE),
        Risco_Internacional = sum(risco_politico[escopo_noticia == "internacional"], na.rm = TRUE),
        Noticias = dplyr::n(),
        .groups = "drop"
      )
  } else {
    sent <- data.frame(Hora = df_base$Hora, Risco_Total = 0, Apoio_Total = 0,
                       Risco_Nacional = 0, Risco_Internacional = 0, Noticias = 0)
  }

  df <- dplyr::left_join(df_base, sent, by = "Hora") %>%
    dplyr::mutate(dplyr::across(c(Risco_Total, Apoio_Total, Risco_Nacional,
                                  Risco_Internacional, Noticias), ~ tidyr::replace_na(.x, 0)))

  df$Medo_Langevin <- decair_langevin(df$Risco_Total)
  df$Nacional_Langevin <- decair_langevin(df$Risco_Nacional, 0.68)
  df$Internacional_Langevin <- decair_langevin(df$Risco_Internacional, 0.58)
  df$Apoio_Langevin <- decair_langevin(df$Apoio_Total, 0.55)
  df$Return <- df$Close / dplyr::lag(df$Close) - 1
  df$Abs_Return <- abs(df$Return)
  df$MA_5 <- zoo::rollapply(df$Close, width = 5, FUN = mean, fill = NA, align = "right")
  df$MA_12 <- zoo::rollapply(df$Close, width = 12, FUN = mean, fill = NA, align = "right")
  df$Mom_3 <- df$Close - dplyr::lag(df$Close, 3)
  df$Mom_5 <- df$Close - dplyr::lag(df$Close, 5)
  df$Vol_6 <- zoo::rollapply(df$Return, width = 6, FUN = sd, fill = NA, align = "right")
  df$Vol_12 <- zoo::rollapply(df$Return, width = 12, FUN = sd, fill = NA, align = "right")
  df$Vol_Ratio <- df$Vol_6 / pmax(df$Vol_12, .Machine$double.eps)
  df$Stress_News <- df$Medo_Langevin - (0.45 * df$Apoio_Langevin)
  df$Fwd_Vol_1h <- dplyr::lead(df$Abs_Return, 1)
  limiar <- stats::quantile(df$Fwd_Vol_1h, probs = 0.60, na.rm = TRUE)
  df$Tgt_1h <- ifelse(df$Fwd_Vol_1h >= limiar, 1, 0)
  df
}

Daniel_tekel_dollar <- function(meta_min = 0.75, meta_max = 0.80) {
  log_analyst("Iniciando oraculo de volatilidade (Daniel_tekel_dollar - 1H)...")

  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), DB_FILE), error = function(e) NULL)
  if (is.null(con)) {
    log_analyst("Erro: banco de dados nao encontrado.")
    return(NULL)
  }
  df_usd_raw <- tryCatch(DBI::dbReadTable(con, "Historico_rapido"), error = function(e) NULL)
  df_sent_raw <- tryCatch(DBI::dbReadTable(con, "AltData_Sentiment"), error = function(e) NULL)
  DBI::dbDisconnect(con)

  if (is.null(df_usd_raw) || nrow(df_usd_raw) < 120) {
    log_analyst("Dados de preco insuficientes para a rede neural.")
    return(NULL)
  }

  df_merge <- montar_base_dollar_1h(df_usd_raw, df_sent_raw)
  features <- c("Return", "Abs_Return", "Mom_3", "Vol_6", "Vol_12",
                "Vol_Ratio", "Stress_News", "Noticias")

  df_modelo <- na.omit(df_merge[, c("Hora", features, "Tgt_1h")])
  if (nrow(df_modelo) < 90 || length(unique(df_modelo$Tgt_1h)) < 2) {
    log_analyst("Historico limpo insuficiente ou sem variacao para validar o modelo 1H.")
    return(NULL)
  }

  linha_atual <- df_merge[nrow(df_merge), features]
  if (any(is.na(linha_atual))) {
    log_analyst("Sem dados suficientes na ultima hora para prever.")
    return(NULL)
  }

  n <- nrow(df_modelo)
  n_valid <- max(24, floor(n * 0.20))
  idx_train <- seq_len(n - n_valid)
  idx_valid <- seq((n - n_valid) + 1, n)

  x_train <- as.matrix(df_modelo[idx_train, features])
  y_train <- df_modelo$Tgt_1h[idx_train]
  x_valid <- as.matrix(df_modelo[idx_valid, features])
  y_valid <- df_modelo$Tgt_1h[idx_valid]
  escala_valid <- normalizar_matriz(x_train, x_valid)

  set.seed(42)
  capture.output(modelo_valid <- nnet::nnet(x = escala_valid$train, y = y_train,
                                            size = 3, decay = 0.02, entropy = TRUE,
                                            maxit = 250, trace = FALSE))
  prob_valid <- as.numeric(predict(modelo_valid, escala_valid$new))
  calib <- calibrar_threshold(prob_valid, y_valid, meta_min, meta_max)

  x_full <- as.matrix(df_modelo[, features])
  y_full <- df_modelo$Tgt_1h
  x_new <- as.matrix(linha_atual)
  escala_full <- normalizar_matriz(x_full, x_new)

  set.seed(42)
  capture.output(modelo_final <- nnet::nnet(x = escala_full$train, y = y_full,
                                            size = 3, decay = 0.02, entropy = TRUE,
                                            maxit = 250, trace = FALSE))

  prob_panico <- as.numeric(predict(modelo_final, escala_full$new))
  sinal <- ifelse(prob_panico >= calib$threshold,
                  "PANICO (Hard Stop Ativado)",
                  "CALMARIA (Mercado Livre)")
  status_meta <- ifelse(calib$atingiu_meta, "meta 75-80% calibrada", "fora da meta; manter em observacao")

  resultado <- sprintf(
    "PREVISAO 1H -> Prob de Estresse: %.1f%% | Threshold: %.2f | Acuracia validacao: %.1f%% (%s) | Atrito: %.3f | Status: %s",
    prob_panico * 100, calib$threshold, calib$accuracy * 100, status_meta,
    linha_atual$Stress_News, sinal
  )
  log_analyst(resultado)
  resultado
}

# ==============================================================================
# MODULO 4: ORACULO MACRO DIARIO
# ==============================================================================

Daniel_tekel_dollar_1d <- function() {
  log_analyst("Iniciando oraculo macro diario (MLP + GARCH - 1D)...")

  tryCatch({
    start_date <- "2015-01-01"
    baixar_seguro <- function(ticker) {
      obj <- tryCatch(getSymbols(ticker, src = "yahoo", from = start_date, to = Sys.Date(),
                                 auto.assign = FALSE), error = function(e) NULL)
      if (is.null(obj) || nrow(obj) == 0) return(NULL)
      if (any(is.na(tail(obj, 1)))) obj <- obj[-nrow(obj), ]
      obj
    }

    raw_usd <- baixar_seguro("USDBRL=X")
    raw_wti <- baixar_seguro("CL=F")
    raw_brent <- baixar_seguro("BZ=F")
    raw_tnx <- baixar_seguro("^TNX")
    raw_vix <- baixar_seguro("^VIX")
    if (is.null(raw_usd)) return("Erro de coleta: historico do dolar indisponivel no Yahoo.")
    if (is.null(raw_wti)) return("Erro de coleta: historico do petroleo WTI indisponivel no Yahoo.")
    if (is.null(raw_brent)) return("Erro de coleta: historico do petroleo Brent indisponivel no Yahoo.")
    if (is.null(raw_tnx)) return("Erro de coleta: historico de juros EUA indisponivel no Yahoo.")
    if (is.null(raw_vix)) return("Erro de coleta: historico do VIX indisponivel no Yahoo.")

    df_raw <- merge(raw_usd[, 4], raw_wti[, 4], raw_brent[, 4], raw_tnx[, 4], raw_vix[, 4], all = FALSE)
    if (nrow(df_raw) == 0) return("Erro de alinhamento: merge dos ativos resultou em 0 linhas.")
    colnames(df_raw) <- c("Dolar", "WTI", "Brent", "Juros_EUA", "VIX")
    df_raw <- zoo::na.locf(df_raw, fromLast = TRUE)
    df <- data.frame(Data = zoo::index(df_raw), zoo::coredata(df_raw))

    df$Return <- df$Dolar / dplyr::lag(df$Dolar) - 1
    df$MA_5 <- zoo::rollapply(df$Dolar, width = 5, FUN = mean, fill = NA, align = "right")
    df$MA_10 <- zoo::rollapply(df$Dolar, width = 10, FUN = mean, fill = NA, align = "right")
    df$Mom_5 <- df$Dolar - dplyr::lag(df$Dolar, 5)
    df$Oil_Spread <- df$Brent - df$WTI
    df$Delta_Panico <- df$VIX - dplyr::lag(df$VIX, 3)
    df$Premio_Risco <- log1p(df$Juros_EUA * df$VIX)
    limiar_vix <- zoo::rollapply(df$VIX, width = 30, FUN = mean, fill = NA, align = "right")
    df$Regime_Estresse <- ifelse(df$VIX > limiar_vix, 1, 0)
    df$Return_Garch <- df$Return * 100
    df$Volatility <- zoo::rollapply(df$Return, width = 10, FUN = sd, fill = NA, align = "right")
    df$Target <- ifelse(df$Volatility > median(df$Volatility, na.rm = TRUE), 1, 0)

    features <- c("Return", "MA_5", "MA_10", "Mom_5", "Juros_EUA", "Oil_Spread",
                  "VIX", "Delta_Panico", "Premio_Risco", "Regime_Estresse")
    df_clean <- na.omit(df[, c("Data", features, "Return_Garch", "Target")])
    if (nrow(df_clean) < 500) return("Erro amostral: historico limpo com menos de 500 dias uteis.")

    x_completo <- as.matrix(df_clean[, features])
    y_completo <- df_clean$Target
    x_hoje <- x_completo[nrow(x_completo), , drop = FALSE]
    x_train <- x_completo[-nrow(x_completo), , drop = FALSE]
    y_train <- y_completo[-length(y_completo)]
    escala <- normalizar_matriz(x_train, x_hoje)

    retornos_garch <- df_clean$Return_Garch[-nrow(df_clean)]
    limiar_garch <- sd(retornos_garch)
    spec_garch <- rugarch::ugarchspec(
      variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
      mean.model = list(armaOrder = c(0, 0), include.mean = FALSE),
      distribution.model = "norm"
    )
    fit <- tryCatch(rugarch::ugarchfit(spec = spec_garch, data = retornos_garch, solver = "hybrid"),
                    error = function(e) NULL)
    garch_apita <- 0
    if (!is.null(fit)) {
      forc <- tryCatch(rugarch::ugarchforecast(fit, n.ahead = 21), error = function(e) NULL)
      if (!is.null(forc)) garch_apita <- ifelse(mean(rugarch::sigma(forc)) > limiar_garch, 1, 0)
    }

    set.seed(42)
    capture.output(modelo_mlp <- nnet::nnet(x = escala$train, y = y_train, size = 10,
                                            decay = 0.01, entropy = TRUE,
                                            maxit = 500, trace = FALSE))
    prob_mlp <- as.numeric(predict(modelo_mlp, escala$new))
    decisao_final <- ifelse(garch_apita == 1 | prob_mlp > 0.5, 1, 0)
    status_str <- ifelse(decisao_final == 1, "PANICO DIARIO (Caixa Ativado)",
                         "CALMARIA MACRO (Tendencia Livre)")
    sprintf("PREVISAO 1 DIA -> Status: %s | Prob. Macro: %.1f%% | Gatilho GARCH: %s",
            status_str, prob_mlp * 100, ifelse(garch_apita == 1, "SIM", "NAO"))
  }, error = function(cond) {
    msg_erro <- paste("CRASH INTERNO NO MODULO 4:", conditionMessage(cond))
    log_analyst(msg_erro)
    paste("Bug de compilacao interna:", conditionMessage(cond))
  })
}

log_analyst("LabAnalyst v12.0 Online. Modulos ativos.")

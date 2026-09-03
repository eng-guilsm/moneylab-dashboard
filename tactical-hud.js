/**
 * ==============================================================================
 * HARMONICUS SX // PÁGINA 1: PORTFOLIO TACTICAL HUD CONTROLLER (v4.6)
 * Termômetro 100% AO VIVO com Filtro de Risco, Séries Históricas (1H, 24H, 7D, 30D),
 * Tooltip Interativa com Crosshair e 3 Pilares Executivos Oficiais
 * ==============================================================================
 */

document.addEventListener('DOMContentLoaded', () => {
  initTacticalHUD();
});

let activePlanFilter = 'all';
let activeModalPlanId = null;
let activeModalTimeframe = '1h';
let modalHoverIdx = -1;

function initTacticalHUD() {
  const plans = window.PLANOS_TACTICAL_DATA || [];
  const portfolio = window.PORTFOLIO_STATE || {};

  renderHeroPatrimony(portfolio);
  renderLiveThermometer(plans, activePlanFilter);
  initFilterButtons(plans);
  initModalEvents();
  startLiveTacticalSync();
}

function renderHeroPatrimony(p) {
  if (!p) return;

  const elPatrimonio = document.getElementById('patrimonioTotal');
  const elCaixa = document.getElementById('caixaLivre');
  const elBtc = document.getElementById('tickBTC');
  const elLink = document.getElementById('tickLINK');
  const elSol = document.getElementById('tickSOL');
  const elPaxg = document.getElementById('tickPAXG');
  const elEth = document.getElementById('tickETH');
  const elUsdt = document.getElementById('tickUSDT');
  const elVix = document.getElementById('tickVIX');
  const elGatekeeperBadge = document.getElementById('gatekeeperBadge');
  const elGatekeeperDetail = document.getElementById('gatekeeperDetail');

  const fmt = (v) => v ? v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '--';

  if (elPatrimonio) elPatrimonio.textContent = fmt(p.total_brl || 1709.72);
  if (elCaixa) elCaixa.textContent = fmt(p.caixa_brl || 1150.00);

  const c = p.cotacoes_ao_vivo || {};
  if (elBtc && c.BTCBRL) elBtc.textContent = `R$ ${Math.round(c.BTCBRL).toLocaleString('pt-BR')}`;
  if (elLink && c.LINKBRL) elLink.textContent = `R$ ${c.LINKBRL.toFixed(2)}`;
  if (elSol && c.SOLBRL) elSol.textContent = `R$ ${c.SOLBRL.toFixed(2)}`;
  if (elPaxg && c.PAXGBRL) elPaxg.textContent = `R$ ${Math.round(c.PAXGBRL).toLocaleString('pt-BR')}`;
  if (elEth && c.ETHBRL) elEth.textContent = `R$ ${Math.round(c.ETHBRL).toLocaleString('pt-BR')}`;
  if (elUsdt && c.USDTBRL) elUsdt.textContent = `R$ ${c.USDTBRL.toFixed(3)}`;
  if (elVix && c.VIX) elVix.textContent = `${c.VIX.toFixed(2)} pts`;

  const s = p.harmonicus_sensores || {};
  if (elGatekeeperBadge && elGatekeeperDetail) {
    if (s.pc1 > 0.70) {
      elGatekeeperBadge.textContent = '🚨 PÂNICO SISTÊMICO';
      elGatekeeperBadge.style.color = '#EF4444';
      elGatekeeperBadge.style.borderColor = '#EF4444';
      elGatekeeperDetail.innerHTML = 'Travas ativas: <b>Altcoins Bloqueadas</b> | Foco em Ouro PAXG e Dólar.';
    } else {
      const lote = s.fator_lote === 1.0 ? '100% (Integral)' : '50% (Defensivo)';
      elGatekeeperBadge.textContent = '🟢 VIGILÂNCIA ATIVA';
      elGatekeeperDetail.innerHTML = `Fator de Lote: <b>${lote}</b> | Sem tempestades espectrais`;
    }
  }

  const elDate = document.getElementById('autorunDate');
  const elTime = document.getElementById('autorunTime');
  if (p.timestamp_str) {
    const parts = p.timestamp_str.split(' ');
    if (parts.length >= 2) {
      const dParts = parts[0].split('-');
      const fmtDate = `${dParts[2]}/${dParts[1]}/${dParts[0]}`;
      if (elDate) elDate.textContent = fmtDate;
      if (elTime) elTime.textContent = parts[1];
    }
  }

  // -------------------------------------------------------------
  // DISTRIBUIÇÃO PATRIMONIAL 100% DINÂMICA (CUSTÓDIA ATIVA SPOT)
  // -------------------------------------------------------------
  const allocContainer = document.getElementById('allocBarsContainer');
  if (allocContainer) {
    let items = p.itens_custodia;
    if (!items || items.length === 0) {
      items = [];
      if (p.caixa_brl !== undefined && p.caixa_brl > 0) {
        items.push({ asset: 'BRL', nome: 'Caixa Livre BRL', qtd: null, valor_brl: p.caixa_brl, pct: p.caixa_pct || 0, cor: '#10B981', icone: '💵' });
      }
      if (p.btc_brl !== undefined && p.btc_brl > 0) {
        items.push({ asset: 'BTC', nome: 'Bitcoin Spot', qtd: p.btc_qtd, valor_brl: p.btc_brl, pct: p.btc_pct || 0, cor: '#F59E0B', icone: '🪙' });
      }
      if (p.paxg_brl !== undefined && p.paxg_brl > 0) {
        items.push({ asset: 'PAXG', nome: 'Ouro PAXG', qtd: p.paxg_qtd, valor_brl: p.paxg_brl, pct: p.paxg_pct || 0, cor: '#EAB308', icone: '🥇' });
      }
      if (p.sol_brl !== undefined && p.sol_brl > 0) {
        items.push({ asset: 'SOL', nome: 'Solana Spot', qtd: p.sol_qtd, valor_brl: p.sol_brl, pct: p.sol_pct || 0, cor: '#A855F7', icone: '⚡' });
      }
      if (p.eth_brl !== undefined && p.eth_brl > 0) {
        items.push({ asset: 'ETH', nome: 'Ethereum Spot', qtd: p.eth_qtd, valor_brl: p.eth_brl, pct: p.eth_pct || 0, cor: '#3B82F6', icone: '🔷' });
      }
      if (p.link_brl !== undefined && p.link_brl > 0) {
        items.push({ asset: 'LINK', nome: 'Chainlink Spot', qtd: p.link_qtd, valor_brl: p.link_brl, pct: p.link_pct || 0, cor: '#6366F1', icone: '🔗' });
      }
      if (p.usdt_brl !== undefined && p.usdt_brl > 0) {
        items.push({ asset: 'USDT', nome: 'Tether USD', qtd: p.usdt_qtd, valor_brl: p.usdt_brl, pct: p.usdt_pct || 0, cor: '#06B6D4', icone: '💵' });
      }
    }

    allocContainer.innerHTML = items.map(it => {
      const qtdStr = (it.qtd !== null && it.qtd !== undefined) ? ` (${it.qtd} ${it.asset})` : '';
      const corAtivo = it.cor || '#06B6D4';
      return `
        <div class="alloc-bar-item" style="margin-bottom: 8px;">
          <div class="abi-head" style="display: flex; justify-content: space-between; font-family: var(--font-mono); font-size: 0.73rem; margin-bottom: 2px;">
            <span style="color: var(--text-primary); font-weight: 600;">${it.icone ? it.icone + ' ' : ''}${it.nome}${qtdStr}</span>
            <b style="color: ${corAtivo};">R$ ${fmt(it.valor_brl)} (${it.pct}%)</b>
          </div>
          <div class="abi-track" style="height: 8px; background: rgba(255, 255, 255, 0.08); border-radius: 4px; overflow: hidden;">
            <div class="abi-fill" style="width: ${Math.max(1.5, it.pct)}%; height: 100%; background: ${corAtivo}; border-radius: 4px; transition: width 0.6s cubic-bezier(0.4, 0, 0.2, 1);"></div>
          </div>
        </div>
      `;
    }).join('');
  }
}

// ------------------------------------------------------------------------------
// 1. TERMÔMETRO DE PROXIMIDADE 100% AO VIVO (COM FILTRAGEM DE RISCO)
// ------------------------------------------------------------------------------
function renderLiveThermometer(plans, filter) {
  const container = document.getElementById('thermometerList');
  if (!container || !plans || plans.length === 0) return;

  const filteredPlans = filter === 'all' ? plans : plans.filter(p => p.categoria === filter);
  const sortedPlans = [...filteredPlans].sort((a, b) => b.proximidade_score - a.proximidade_score);

  container.innerHTML = sortedPlans.map((plan, idx) => {
    const isLow = plan.categoria === 'baixo_risco';
    const badgeClass = isLow ? 'badge-low' : 'badge-mid';
    const badgeText = isLow ? '🛡️ BAIXO RISCO' : '⚡ MÉDIO RISCO';

    const pA_score = plan.ponta_a_score !== undefined ? plan.ponta_a_score : plan.proximidade_score;
    const pB_score = plan.ponta_b_score !== undefined ? plan.ponta_b_score : 0;
    const pA_label = plan.ponta_a_label || 'Ponta A: Compra / Rotação A';
    const pB_label = plan.ponta_b_label || 'Ponta B: Venda / Rotação B';

    return `
      <div class="thermo-card" data-plan-id="${plan.id}" style="border-top: 3px solid ${plan.cor};" title="Clique para abrir análise executiva e histórico">
        <div class="thermo-header">
          <span class="thermo-rank">#${idx + 1} AO VIVO</span>
          <span class="plan-badge ${badgeClass}">${badgeText}</span>
        </div>
        <div>
          <div class="thermo-name">${plan.icone} ${plan.nome}</div>
          <div class="thermo-par-tag">${plan.par} • Lote: R$ ${plan.lote_brl.toFixed(2)}</div>
        </div>
        <div class="thermo-dist">${plan.valor_atual_str || ''}</div>
        
        <!-- DUAS METAS BIDIRECIONAIS (PONTA A vs PONTA B) -->
        <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 4px;">
          <!-- PONTA A (COMPRA / ENTRADA) -->
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; font-family: var(--font-mono); font-size: 0.65rem; margin-bottom: 3px;">
              <span style="color: #10B981; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 75%;">🟢 ${pA_label}</span>
              <span style="color: #10B981; font-weight: 700; font-size: 0.72rem;">${pA_score}%</span>
            </div>
            <div class="thermo-bar-track" style="height: 6px; background: rgba(16, 185, 129, 0.15);">
              <div class="thermo-bar-fill" style="width: ${pA_score}%; background: #10B981;"></div>
            </div>
          </div>

          <!-- PONTA B (VENDA / REALIZAÇÃO) -->
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; font-family: var(--font-mono); font-size: 0.65rem; margin-bottom: 3px;">
              <span style="color: #3B82F6; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 75%;">🔵 ${pB_label}</span>
              <span style="color: #3B82F6; font-weight: 700; font-size: 0.72rem;">${pB_score}%</span>
            </div>
            <div class="thermo-bar-track" style="height: 6px; background: rgba(59, 130, 246, 0.15);">
              <div class="thermo-bar-fill" style="width: ${pB_score}%; background: #3B82F6;"></div>
            </div>
          </div>
        </div>

        <div class="thermo-hint" style="margin-top: 8px;">
          <span>🔍</span>
          <span>Clique para abrir gráfico histórico bidirecional</span>
        </div>
      </div>
    `;
  }).join('');

  container.querySelectorAll('.thermo-card').forEach(card => {
    card.addEventListener('click', () => {
      const pId = parseInt(card.getAttribute('data-plan-id'), 10);
      openPlanModal(pId, '1h');
    });
  });
}

function initFilterButtons(plans) {
  const allCount = plans.length;
  const lowCount = plans.filter(p => p.categoria === 'baixo_risco').length;
  const midCount = plans.filter(p => p.categoria === 'medio_risco').length;

  const btnAll = document.querySelector('.filter-btn[data-filter="all"]');
  const btnLow = document.querySelector('.filter-btn[data-filter="baixo_risco"]');
  const btnMid = document.querySelector('.filter-btn[data-filter="medio_risco"]');

  if (btnAll) btnAll.textContent = `TODOS (${allCount})`;
  if (btnLow) btnLow.textContent = `🛡️ BAIXO RISCO (${lowCount})`;
  if (btnMid) btnMid.textContent = `⚡ MÉDIO RISCO (${midCount})`;

  const buttons = document.querySelectorAll('.filter-btn');
  buttons.forEach(btn => {
    btn.addEventListener('click', () => {
      buttons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activePlanFilter = btn.getAttribute('data-filter');
      renderLiveThermometer(plans, activePlanFilter);
    });
  });
}

// ------------------------------------------------------------------------------
// 2. MODAL DE ANÁLISE EXECUTIVA & GRÁFICO HISTÓRICO REAL COM TOOLTIP
// ------------------------------------------------------------------------------
function initModalEvents() {
  const overlay = document.getElementById('planModalOverlay');
  const closeBtn = document.getElementById('modalCloseBtn');

  if (closeBtn) {
    closeBtn.addEventListener('click', () => {
      if (overlay) overlay.classList.remove('active');
    });
  }

  if (overlay) {
    overlay.addEventListener('click', (e) => {
      if (e.target === overlay) overlay.classList.remove('active');
    });
  }
}

window.openPlanModal = function(planId, initialTf) {
  const plans = window.PLANOS_TACTICAL_DATA || [];
  const plan = plans.find(p => p.id === planId) || plans[0];
  if (!plan) return;

  activeModalPlanId = planId;
  activeModalTimeframe = initialTf || '1h';
  modalHoverIdx = -1;

  const overlay = document.getElementById('planModalOverlay');
  const content = document.getElementById('planModalContent');
  if (!overlay || !content) return;

  renderModalLayout(plan, activeModalTimeframe);
  overlay.classList.add('active');
};

function renderModalLayout(plan, tf) {
  const content = document.getElementById('planModalContent');
  if (!content) return;

  const isLow = plan.categoria === 'baixo_risco';
  const badgeClass = isLow ? 'badge-low' : 'badge-mid';
  const badgeText = isLow ? '🛡️ BAIXO RISCO' : '⚡ MÉDIO RISCO';

  content.innerHTML = `
    <div class="modal-header-box">
      <div class="modal-title-left">
        <span class="plan-badge ${badgeClass}">${badgeText}</span>
        <h3 class="modal-plan-title">${plan.icone} ${plan.nome}</h3>
        <span class="plan-par-tag">PAR SINTÉTICO: <b>${plan.par}</b> | Lote: <b>R$ ${plan.lote_brl.toFixed(2)}</b> | Meta Lucro: <b>+${plan.lucro_min_pct.toFixed(2)}%</b></span>
      </div>
    </div>

    <!-- SELETOR DE ESCALA HISTÓRICA DO GRÁFICO (1H, 24H, 7D, 30D) -->
    <div class="modal-tf-selector">
      <span class="tf-label">HISTÓRICO REAL:</span>
      <button class="modal-tf-btn ${tf === '1h' ? 'active' : ''}" data-tf="1h">1H</button>
      <button class="modal-tf-btn ${tf === '24h' ? 'active' : ''}" data-tf="24h">24H</button>
      <button class="modal-tf-btn ${tf === '7d' ? 'active' : ''}" data-tf="7d">7D</button>
      <button class="modal-tf-btn ${tf === '30d' ? 'active' : ''}" data-tf="30d">30D</button>
    </div>

    <!-- GRÁFICO HISTÓRICO REAL DE PROXIMIDADE À META BIDIRECIONAL COM TOOLTIP -->
    <div class="modal-chart-wrapper" id="planChartWrapper" style="position: relative; background: rgba(5, 8, 17, 0.95); border: 1px solid var(--border-subtle); border-radius: 10px; padding: 12px; margin-bottom: 16px;">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; font-family: var(--font-mono); font-size: 0.70rem; color: var(--text-muted); flex-wrap: wrap; gap: 8px;">
        <span>EVOLUÇÃO HISTÓRICA BIDIRECIONAL (0% A 100%)</span>
        <div style="display: flex; gap: 12px;">
          <span style="color: #10B981; font-weight: 700;">🟢 PONTA A: ${plan.ponta_a_score !== undefined ? plan.ponta_a_score : plan.proximidade_score}%</span>
          <span style="color: #3B82F6; font-weight: 700;">🔵 PONTA B: ${plan.ponta_b_score !== undefined ? plan.ponta_b_score : 0}%</span>
        </div>
      </div>
      <canvas id="planHistoryCanvas" width="620" height="150" style="width: 100%; height: 150px; display: block; cursor: crosshair;"></canvas>
      <div id="planCanvasTooltip" class="plan-canvas-tooltip" style="display: none; position: absolute; pointer-events: none; z-index: 50; background: rgba(10, 15, 29, 0.95); border: 1px solid ${plan.cor}; border-radius: 6px; padding: 6px 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.5); font-family: var(--font-mono); font-size: 0.72rem;"></div>
    </div>

    <!-- OS 3 PILARES EXECUTIVOS OFICIAIS -->
    <div class="modal-pillars-grid">
      <div class="modal-pillar-card">
        <span class="mpc-title">📋 1. DESCRIÇÃO EXECUTIVA & TESE QUANT</span>
        <div class="mpc-content">${plan.descricao_executiva || plan.nome}</div>
      </div>

      <div class="modal-pillar-card">
        <span class="mpc-title">🎯 2. CONDIÇÕES MATEMÁTICAS DE ATIVAÇÃO</span>
        <div class="mpc-content">${plan.condicoes_ativacao || plan.gatilho_desc}</div>
      </div>

      <div class="modal-pillar-card" style="border-left-color: #EF4444;">
        <span class="mpc-title" style="color: #EF4444;">🛡️ 3. LIMITAÇÕES DE TRAVA & BLINDAGEM DE RISCO</span>
        <div class="mpc-content">${plan.limitacoes_trava || plan.trava_ruptura}</div>
      </div>
    </div>
  `;

  // Event Listeners nos botões de timeframe do Modal
  content.querySelectorAll('.modal-tf-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const newTf = btn.getAttribute('data-tf');
      activeModalTimeframe = newTf;
      renderModalLayout(plan, newTf);
    });
  });

  setTimeout(() => {
    drawPlanHistoryChart(plan, tf);
    initPlanCanvasInteractions(plan, tf);
  }, 30);
}

// ------------------------------------------------------------------------------
// 3. DESENHO DO CANVAS HISTÓRICO REAL DE PROXIMIDADE COM CROSSHAIR
// ------------------------------------------------------------------------------
function drawPlanHistoryChart(plan, tf) {
  const canvas = document.getElementById('planHistoryCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  const dpr = window.devicePixelRatio || 1;
  const w = canvas.parentElement.clientWidth - 24 || 620;
  const h = 150;

  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  ctx.scale(dpr, dpr);

  ctx.clearRect(0, 0, w, h);

  const series = (plan.series_historica && plan.series_historica[tf]) || [];
  if (series.length === 0) return;

  const padLeft = 40;
  const padRight = 20;
  const padTop = 15;
  const padBottom = 25;
  const plotW = w - padLeft - padRight;
  const plotH = h - padTop - padBottom;

  const getY = (val) => padTop + (1 - (val / 100)) * plotH;
  const getX = (idx) => padLeft + (idx / (series.length - 1)) * plotW;

  // Grade Horizontal (0%, 25%, 50%, 75%, 100%)
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
  ctx.lineWidth = 1;
  [0, 25, 50, 75, 100].forEach(level => {
    const y = getY(level);
    ctx.beginPath();
    ctx.moveTo(padLeft, y);
    ctx.lineTo(w - padRight, y);
    ctx.stroke();

    ctx.fillStyle = level === 100 ? '#F59E0B' : '#6B7280';
    ctx.font = '9px JetBrains Mono';
    ctx.textAlign = 'right';
    ctx.fillText(`${level}%`, padLeft - 6, y + 3);
  });

  // Linha de Gatilho de Execução (100%) em ouro pontilhado
  const yTrigger = getY(100);
  ctx.save();
  ctx.setLineDash([4, 4]);
  ctx.strokeStyle = 'rgba(245, 158, 11, 0.7)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(padLeft, yTrigger);
  ctx.lineTo(w - padRight, yTrigger);
  ctx.stroke();
  ctx.restore();

  // Área preenchida sob a curva
  const grad = ctx.createLinearGradient(0, padTop, 0, h - padBottom);
  grad.addColorStop(0, `${plan.cor}44`);
  grad.addColorStop(1, `${plan.cor}00`);

  const getTopScore = (p) => {
    if (!p) return 0;
    if (p.score_a !== undefined && p.score_b !== undefined) return Math.max(p.score_a, p.score_b);
    if (p.score_a !== undefined) return p.score_a;
    if (p.score !== undefined) return p.score;
    return 0;
  };

  ctx.beginPath();
  ctx.moveTo(getX(0), getY(getTopScore(series[0])));
  for (let i = 1; i < series.length; i++) {
    ctx.lineTo(getX(i), getY(getTopScore(series[i])));
  }
  ctx.lineTo(getX(series.length - 1), h - padBottom);
  ctx.lineTo(getX(0), h - padBottom);
  ctx.closePath();
  ctx.fillStyle = grad;
  ctx.fill();

  // Curva de Trajetória da Ponta A (Verde / Compra)
  const hasBidi = series.length > 0 && series[0].score_a !== undefined;

  if (hasBidi) {
    // 1. Curva da Ponta A (Verde Esmeralda)
    ctx.beginPath();
    ctx.moveTo(getX(0), getY(series[0].score_a || 0));
    for (let i = 1; i < series.length; i++) {
      ctx.lineTo(getX(i), getY(series[i].score_a || 0));
    }
    ctx.strokeStyle = '#10B981';
    ctx.lineWidth = 2.5;
    ctx.shadowColor = '#10B981';
    ctx.shadowBlur = 6;
    ctx.stroke();
    ctx.shadowBlur = 0;

    // 2. Curva da Ponta B (Azul Ciano)
    ctx.beginPath();
    ctx.moveTo(getX(0), getY(series[0].score_b || 0));
    for (let i = 1; i < series.length; i++) {
      ctx.lineTo(getX(i), getY(series[i].score_b || 0));
    }
    ctx.strokeStyle = '#3B82F6';
    ctx.lineWidth = 2.5;
    ctx.shadowColor = '#3B82F6';
    ctx.shadowBlur = 6;
    ctx.stroke();
    ctx.shadowBlur = 0;
  } else {
    // Curva única legada
    ctx.beginPath();
    ctx.moveTo(getX(0), getY(getTopScore(series[0])));
    for (let i = 1; i < series.length; i++) {
      ctx.lineTo(getX(i), getY(getTopScore(series[i])));
    }
    ctx.strokeStyle = plan.cor;
    ctx.lineWidth = 2.5;
    ctx.shadowColor = plan.cor;
    ctx.shadowBlur = 8;
    ctx.stroke();
    ctx.shadowBlur = 0;
  }

  // Rótulos de tempo no eixo X
  ctx.fillStyle = '#6B7280';
  ctx.font = '9px JetBrains Mono';
  ctx.textAlign = 'center';
  const labelSteps = Math.min(5, series.length);
  const step = Math.max(1, Math.floor(series.length / (labelSteps - 1)));
  for (let i = 0; i < series.length; i += step) {
    const timeLabel = series[i].time || series[i].label || '';
    ctx.fillText(timeLabel, getX(i), h - 8);
  }

  // Crosshair e Ponto de Inspeção em Hover
  if (modalHoverIdx >= 0 && modalHoverIdx < series.length) {
    const hX = getX(modalHoverIdx);
    const scoreA = hasBidi ? series[modalHoverIdx].score_a : series[modalHoverIdx].score;
    const scoreB = hasBidi ? series[modalHoverIdx].score_b : 0;
    const hY_A = getY(scoreA);
    const hY_B = getY(scoreB);

    // Linha vertical pontilhada
    ctx.save();
    ctx.setLineDash([3, 3]);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(hX, padTop);
    ctx.lineTo(hX, h - padBottom);
    ctx.stroke();
    ctx.restore();

    // Ponto A destacado (Verde)
    ctx.beginPath();
    ctx.arc(hX, hY_A, 5.0, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();
    ctx.strokeStyle = '#10B981';
    ctx.lineWidth = 2.5;
    ctx.stroke();

    // Ponto B destacado (Azul)
    if (hasBidi) {
      ctx.beginPath();
      ctx.arc(hX, hY_B, 5.0, 0, Math.PI * 2);
      ctx.fillStyle = '#FFFFFF';
      ctx.fill();
      ctx.strokeStyle = '#3B82F6';
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }
  }
}

function initPlanCanvasInteractions(plan, tf) {
  const canvas = document.getElementById('planHistoryCanvas');
  const tooltip = document.getElementById('planCanvasTooltip');
  if (!canvas || !tooltip) return;

  const series = (plan.series_historica && plan.series_historica[tf]) || [];
  if (series.length === 0) return;

  const padLeft = 40;
  const padRight = 20;

  const handlePointer = (clientX, clientY) => {
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left;
    const plotW = rect.width - padLeft - padRight;
    const relX = x - padLeft;

    if (relX < 0 || relX > plotW) {
      modalHoverIdx = -1;
      tooltip.style.display = 'none';
      drawPlanHistoryChart(plan, tf);
      return;
    }

    const pct = relX / plotW;
    const idx = Math.min(series.length - 1, Math.max(0, Math.round(pct * (series.length - 1))));
    modalHoverIdx = idx;

    const pt = series[idx];
    const scoreA = pt.score_a !== undefined ? pt.score_a : pt.score;
    const scoreB = pt.score_b !== undefined ? pt.score_b : 0;
    const isTriggerA = scoreA >= 100;
    const isTriggerB = scoreB >= 100;

    const timeLabel = pt.time || pt.label || '';
    tooltip.style.display = 'block';
    tooltip.innerHTML = `
      <div style="color: #9CA3AF; font-size: 0.65rem; margin-bottom: 3px;">⏱️ ${timeLabel}</div>
      <div style="color: #10B981; font-weight: 700; font-size: 0.75rem; margin-bottom: 2px;">🟢 Ponta A: ${scoreA}% ${isTriggerA ? '🔥 (GATILHO)' : ''}</div>
      <div style="color: #3B82F6; font-weight: 700; font-size: 0.75rem; margin-bottom: 3px;">🔵 Ponta B: ${scoreB}% ${isTriggerB ? '🔥 (GATILHO)' : ''}</div>
      ${pt.metric ? `<div style="color: #06B6D4; font-size: 0.68rem;">📊 ${pt.metric}</div>` : ''}
    `;

    const tipW = 200;
    let tipLeft = x + 15;
    if (tipLeft + tipW > rect.width) tipLeft = x - tipW - 15;
    tooltip.style.left = `${Math.max(10, tipLeft)}px`;
    tooltip.style.top = `25px`;

    drawPlanHistoryChart(plan, tf);
  };

  canvas.addEventListener('mousemove', (e) => handlePointer(e.clientX, e.clientY));
  canvas.addEventListener('mouseleave', () => {
    modalHoverIdx = -1;
    tooltip.style.display = 'none';
    drawPlanHistoryChart(plan, tf);
  });
  canvas.addEventListener('touchmove', (e) => {
    if (e.touches && e.touches[0]) {
      handlePointer(e.touches[0].clientX, e.touches[0].clientY);
    }
  }, { passive: true });
  canvas.addEventListener('touchend', () => {
    modalHoverIdx = -1;
    tooltip.style.display = 'none';
    drawPlanHistoryChart(plan, tf);
  });
}

// ------------------------------------------------------------------------------
// 3. LIVE BACKGROUND AUTO-POLLER (Ignora Cache e Atualiza a UI sem Reload)
// ------------------------------------------------------------------------------
function startLiveTacticalSync() {
  const doSync = async () => {
    try {
      const ts = Date.now();
      const [resPlanos, resSx] = await Promise.all([
        fetch(`data/planos_data.js?_t=${ts}`, { cache: 'no-store' }).catch(() => null),
        fetch(`data/harmonicus_sx_data.js?_t=${ts}`, { cache: 'no-store' }).catch(() => null)
      ]);
      
      if (resPlanos && resPlanos.ok) {
        const tPlanos = await resPlanos.text();
        try { new Function(tPlanos)(); } catch(e) {}
      }
      if (resSx && resSx.ok) {
        const tSx = await resSx.text();
        try { new Function(tSx)(); } catch(e) {}
      }
      
      const plans = window.PLANOS_TACTICAL_DATA || [];
      const portfolio = window.PORTFOLIO_STATE || {};
      
      renderHeroPatrimony(portfolio);
      renderLiveThermometer(plans, activePlanFilter);
      
      if (activeModalPlanId) {
        const activePlan = plans.find(p => p.id === activeModalPlanId);
        if (activePlan) {
          drawPlanHistoryChart(activePlan, activeModalTimeframe);
        }
      }
    } catch (e) {
      console.warn('Live sync notice:', e);
    }
  };

  // Sincroniza imediatamente no carregamento da página
  doSync();
  // E sincroniza continuamente a cada 10 segundos
  setInterval(doSync, 10000);
}

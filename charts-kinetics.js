/**
 * ==============================================================================
 * HARMONICUS SX // PÁGINA 3: ASSET DYNAMICS & MULTI-TIMEFRAME KINETICS CONTROLLER
 * Suporte a 6 Janelas de Tempo (1h, 24h, 1sem, 1m, 1a, tudo), Bandas de Bollinger,
 * Crosshair, Zoom Retangular Interativo & Duplo-Clique para Resetar
 * ==============================================================================
 */

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initChartsKinetics);
} else {
  initChartsKinetics();
}

let currentKineticsAsset = 'USDBRL';
let currentKineticsTimeframe = '24h';
let kineticsPollerTimer = null;
let hoveredDataIndex = -1;
let kineticsZoomRange = null; // [startIdx, endIdx] ou null
let isDraggingKineticsZoom = false;
let kineticsDragStartX = 0;
let kineticsDragCurrentX = 0;
window.currentKineticsAsset = currentKineticsAsset;
window.currentKineticsTimeframe = currentKineticsTimeframe;
window.renderKineticsChart = renderKineticsChart;
window.renderKineticsCockpit = renderKineticsCockpit;

function initChartsKinetics() {
  const assetsData = window.ASSETS_KINETICS_DATA || {};
  
  initAssetPills(assetsData);
  initTimeframeButtons();
  initBandToggles();
  initCanvasInteractions();
  
  renderKineticsCockpit(currentKineticsAsset, currentKineticsTimeframe, assetsData);
  renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, assetsData);
  startLiveBinancePoller();
}

function initBandToggles() {
  const chkZl = document.getElementById('chkToggleZl');
  const lblZl = document.getElementById('lblToggleZl');
  if (chkZl) {
    const updateZlStyle = () => {
      if (lblZl) {
        lblZl.style.background = chkZl.checked ? 'rgba(192, 132, 252, 0.20)' : 'rgba(255, 255, 255, 0.05)';
        lblZl.style.borderColor = chkZl.checked ? '#C084FC' : 'rgba(192, 132, 252, 0.35)';
        lblZl.style.color = chkZl.checked ? '#F5D0FE' : '#9CA3AF';
      }
    };
    updateZlStyle();
    chkZl.addEventListener('change', () => {
      updateZlStyle();
      const data = window.ASSETS_KINETICS_DATA || {};
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, data);
    });
  }
  const chkBb = document.getElementById('chkToggleBb');
  const lblBb = document.getElementById('lblToggleBb');
  if (chkBb) {
    const updateBbStyle = () => {
      if (lblBb) {
        lblBb.style.background = chkBb.checked ? 'rgba(6, 182, 212, 0.16)' : 'rgba(255, 255, 255, 0.05)';
        lblBb.style.borderColor = chkBb.checked ? '#06B6D4' : 'rgba(6, 182, 212, 0.35)';
        lblBb.style.color = chkBb.checked ? '#CFFAFE' : '#9CA3AF';
      }
    };
    updateBbStyle();
    chkBb.addEventListener('change', () => {
      updateBbStyle();
      const data = window.ASSETS_KINETICS_DATA || {};
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, data);
    });
  }
}

function initAssetPills(assetsData) {
  const container = document.getElementById('assetPillsContainer');
  const assetList = [
    { key: 'USDBRL', label: '💵 DÓLAR COMERCIAL (USD) • [BCB/FARIALIMER]', color: '#10B981' },
    { key: 'BTCBRL', label: '🪙 BITCOIN (BTC)', color: '#F59E0B' },
    { key: 'ETHBRL', label: '🔹 ETHEREUM (ETH)', color: '#06B6D4' },
    { key: 'SOLBRL', label: '⚡ SOLANA (SOL)', color: '#EC4899' },
    { key: 'LINKBRL', label: '🌐 CHAINLINK (LINK)', color: '#8B5CF6' },
    { key: 'PAXGBRL', label: '🥇 OURO (PAXG)', color: '#FBBF24' },
    { key: 'USDTBRL', label: '🪙 TETHER (USDT)', color: '#2DD4BF' },
    { key: 'BNBBRL', label: '🟡 BNB CHAIN', color: '#EAB308' },
    { key: 'ADABRL', label: '🔷 CARDANO (ADA)', color: '#3B82F6' }
  ];

  container.innerHTML = assetList.map(item => `
    <button class="asset-pill-btn ${item.key === currentKineticsAsset ? 'active' : ''}" data-asset="${item.key}">
      <span>${item.label}</span>
    </button>
  `).join('');

  container.querySelectorAll('.asset-pill-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      container.querySelectorAll('.asset-pill-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentKineticsAsset = btn.getAttribute('data-asset');
      hoveredDataIndex = -1;
      kineticsZoomRange = null; // Reseta zoom ao trocar de ativo
      
      const data = window.ASSETS_KINETICS_DATA || {};
      renderKineticsCockpit(currentKineticsAsset, currentKineticsTimeframe, data);
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, data);
    });
  });
}

function initTimeframeButtons() {
  const bar = document.getElementById('tfButtonsBar');
  if (!bar) return;

  const btns = bar.querySelectorAll('.tf-btn');
  btns.forEach(btn => {
    btn.addEventListener('click', () => {
      btns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentKineticsTimeframe = btn.getAttribute('data-tf');
      hoveredDataIndex = -1;
      kineticsZoomRange = null; // Reseta zoom ao trocar de escala

      // Atualizar título do card
      const titleEl = document.getElementById('chartTitleText');
      const tfNames = {
        '1h': '1 HORA (ALTA RESOLUÇÃO 1M)',
        '24h': '24 HORAS (CICLO DIÁRIO)',
        '1sem': '1 SEMANA (7 DIAS)',
        '1m': '1 MÊS (30 DIAS)',
        '1a': '1 ANO (365 DIAS)',
        'tudo': 'HISTÓRICO COMPLETO (1.4 ANOS / 596 DIAS)'
      };
      if (titleEl) {
        titleEl.textContent = `CINÉTICA TEMPORAL & ENVELOPE DE BOLLINGER (${tfNames[currentKineticsTimeframe] || '24 HORAS'})`;
      }

      const data = window.ASSETS_KINETICS_DATA || {};
      renderKineticsCockpit(currentKineticsAsset, currentKineticsTimeframe, data);
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, data);
    });
  });

  const resetBtn = document.getElementById('kineticsResetZoomBtn');
  if (resetBtn) {
    resetBtn.addEventListener('click', () => {
      kineticsZoomRange = null;
      resetBtn.style.display = 'none';
      const data = window.ASSETS_KINETICS_DATA || {};
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, data);
    });
  }
}

function renderKineticsCockpit(symbol, tfKey, data) {
  const asset = data[symbol] || {};
  const tfData = (asset.timeframes && asset.timeframes[tfKey]) || {};
  
  const elPrice = document.getElementById('kinPrice');
  const elVar24h = document.getElementById('kinVar24h');
  const elVel = document.getElementById('kinVelocity');
  const elAcc = document.getElementById('kinAcc');
  const elThrustVal = document.getElementById('kinThrustVal');
  const elThrustBar = document.getElementById('kinThrustBar');
  const elKinState = document.getElementById('kinStateTag');

  const p = asset.preco_atual || 0;
  const isFx = symbol === 'USDTBRL' || symbol === 'USDBRL';
  if (elPrice) elPrice.textContent = priceFmt;
  
  const elCardEyebrow = document.querySelector('.kin-price-card .card-eyebrow');
  if (elCardEyebrow) {
    if (symbol === 'USDBRL') {
      elCardEyebrow.innerHTML = 'COTAÇÃO OFICIAL (USD/BRL) <span style="color: #06B6D4; font-size: 0.60rem; margin-left: 6px; font-weight: 700; background: rgba(6, 182, 212, 0.15); padding: 2px 6px; border-radius: 4px; border: 1px solid rgba(6, 182, 212, 0.4);">🔍 PESQUISA EXTERNA BCB SGS + FARIALIMER</span>';
    } else {
      elCardEyebrow.textContent = 'COTAÇÃO AO VIVO (SPOT)';
    }
  }
  
  const pList = tfData.precos || (tfData.series && tfData.series.prices) || [];
  const vList = tfData.velocidades || (tfData.series && tfData.series.velocities) || [];
  const aList = tfData.aceleracoes || (tfData.series && tfData.series.accelerations) || [];

  const pFirst = pList.length > 0 ? pList[0] : p;
  const pLast = pList.length > 0 ? pList[pList.length - 1] : p;
  const v = tfData.variacao_periodo !== undefined ? tfData.variacao_periodo : ((pLast / (pFirst || 1) - 1) * 100);
  const vel = tfData.velocidade_inst !== undefined ? tfData.velocidade_inst : (vList.length > 0 ? vList[vList.length - 1] : 0);
  const acc = tfData.aceleracao_inst !== undefined ? tfData.aceleracao_inst : (aList.length > 0 ? aList[aList.length - 1] : 0);

  if (elVar24h) {
    elVar24h.textContent = `${v >= 0 ? '+' : ''}${v.toFixed(2)}% (${tfData.label || tfKey.toUpperCase()})`;
    elVar24h.className = `hero-tag ${v >= 0 ? 'positive' : 'negative'}`;
  }

  if (elVel) {
    elVel.textContent = `${vel >= 0 ? '▲ +' : '▼ '}${vel.toFixed(3)}%/ponto`;
    elVel.style.color = vel >= 0 ? '#10B981' : '#EF4444';
  }

  if (elAcc) {
    elAcc.textContent = `${acc >= 0 ? '▲ +' : '▼ '}${acc.toFixed(3)}%/ponto²`;
    elAcc.style.color = acc >= 0 ? '#06B6D4' : '#F59E0B';
  }

  if (elThrustVal && elThrustBar) {
    let thrust = tfData.poder_subida_thrust;
    if (thrust === undefined) {
      // Cálculo dinâmico do poder de subida (thrust) baseado em velocidade e aceleração
      const vNorm = Math.max(-1, Math.min(1, vel * 100));
      const aNorm = Math.max(-1, Math.min(1, acc * 1000));
      thrust = Math.max(5, Math.min(95, 50 + vNorm * 30 + aNorm * 20));
    }
    elThrustVal.textContent = `${thrust.toFixed(1)} / 100`;
    elThrustBar.style.width = `${thrust}%`;
    
    if (thrust > 62) {
      elThrustBar.style.background = 'linear-gradient(90deg, #10B981, #06B6D4)';
    } else if (thrust < 38) {
      elThrustBar.style.background = 'linear-gradient(90deg, #EF4444, #F59E0B)';
    } else {
      elThrustBar.style.background = 'linear-gradient(90deg, #F59E0B, #10B981)';
    }
  }

  if (elKinState) {
    let st = tfData.estado_cinetico;
    if (!st) {
      if (vel > 0.005 && acc >= 0) st = 'PROPULSAO_ALTA';
      else if (vel < -0.005 && acc <= 0) st = 'PRESSAO_QUEDA';
      else if (vel > 0 && acc < 0) st = 'DESACELERACAO_ALTA';
      else if (vel < 0 && acc > 0) st = 'EXAUSTAO_QUEDA';
      else st = 'EQUILIBRIO_INERCIAL';
    }
    if (st === 'PROPULSAO_ALTA') {
      elKinState.textContent = '🚀 FORTE PROPULSÃO COMPRADORA';
      elKinState.style.color = '#10B981';
    } else if (st === 'PRESSAO_QUEDA') {
      elKinState.textContent = '⚠️ FORTE PRESSÃO VENDEDORA';
      elKinState.style.color = '#EF4444';
    } else if (st === 'DESACELERACAO_ALTA') {
      elKinState.textContent = '⏱️ DESACELERAÇÃO DE ALTA (TOPO)';
      elKinState.style.color = '#F59E0B';
    } else if (st === 'EXAUSTAO_QUEDA') {
      elKinState.textContent = '🧲 EXAUSTÃO VENDEDORA (FUNDO)';
      elKinState.style.color = '#06B6D4';
    } else {
      elKinState.textContent = '⚖️ EQUILÍBRIO INERCIAL / CONSOLIDAÇÃO';
      elKinState.style.color = '#9CA3AF';
    }
  }
}

// ------------------------------------------------------------------------------
// RENDERIZAÇÃO DO CANVAS PRINCIPAL COM BANDAS DE BOLLINGER & BOX ZOOM
// ------------------------------------------------------------------------------
function renderKineticsChart(symbol, tfKey, data) {
  const canvas = document.getElementById('kineticsMainCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  const asset = data[symbol] || {};
  const tfData = (asset.timeframes && asset.timeframes[tfKey]) || {};
  const series = tfData.series || tfData || {};

  const fullPrices = series.precos || series.prices || [];
  const fullUpper = series.bb_upper || series.bollinger_upper || [];
  const fullLower = series.bb_lower || series.bollinger_lower || [];
  const fullZlUpper = series.zl_upper || [];
  const fullZlLower = series.zl_lower || [];
  const fullSS = series.zerolag || series.supersmoother || [];
  const fullVelocities = series.velocidades || series.velocities || [];
  const fullTimestamps = series.labels || series.timestamps || [];

  if (fullPrices.length === 0) return;

  // Aplicar slice de zoom se ativo
  const startIndex = kineticsZoomRange ? kineticsZoomRange[0] : 0;
  const endIndex = kineticsZoomRange ? kineticsZoomRange[1] : (fullPrices.length - 1);

  const prices = fullPrices.slice(startIndex, endIndex + 1);
  const upper = fullUpper.length > 0 ? fullUpper.slice(startIndex, endIndex + 1) : prices;
  const lower = fullLower.length > 0 ? fullLower.slice(startIndex, endIndex + 1) : prices;
  const zlUpper = fullZlUpper.length > 0 ? fullZlUpper.slice(startIndex, endIndex + 1) : [];
  const zlLower = fullZlLower.length > 0 ? fullZlLower.slice(startIndex, endIndex + 1) : [];
  const supersmoother = fullSS.length > 0 ? fullSS.slice(startIndex, endIndex + 1) : [];
  const velocities = fullVelocities.slice(startIndex, endIndex + 1);
  const timestamps = fullTimestamps.slice(startIndex, endIndex + 1);

  const resetBtn = document.getElementById('kineticsResetZoomBtn');
  if (resetBtn) {
    resetBtn.style.display = kineticsZoomRange ? 'inline-block' : 'none';
  }

  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const w = rect.width || 1100;
  const h = 380;

  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.scale(dpr, dpr);

  const padLeft = 75;
  const padRight = 30;
  const padTop = 20;
  const padBottom = 65;
  const chartH = h - padBottom - padTop;

  ctx.clearRect(0, 0, w, h);

  // Fundo Dark
  ctx.fillStyle = '#050811';
  ctx.fillRect(0, 0, w, h);

  // Checagem de checkboxes de ativação/desativação (Bollinger Ligada por padrão, Zero-Lag Opcional)
  const chkZl = document.getElementById('chkToggleZl');
  const chkBb = document.getElementById('chkToggleBb');
  const showZl = chkZl ? chkZl.checked : false;
  const showBb = chkBb ? chkBb.checked : true;

  // Escalas de Preço (considerando camadas ativas)
  const allVals = [
    ...prices,
    ...(showBb ? [...lower, ...upper] : []),
    ...(showZl ? [...zlUpper, ...zlLower, ...supersmoother] : [])
  ].filter(v => typeof v === 'number' && !isNaN(v));

  const rawMin = Math.min(...allVals);
  const rawMax = Math.max(...allVals);
  const spread = rawMax - rawMin || 1;
  const minP = rawMin - spread * 0.05;
  const maxP = rawMax + spread * 0.05;
  const pRange = maxP - minP;

  const getX = (i) => padLeft + (i / (prices.length - 1)) * (w - padLeft - padRight);
  const getY = (val) => padTop + (1 - (val - minP) / pRange) * chartH;

  // Grade Horizontal
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
  ctx.lineWidth = 1;
  const isFx = symbol === 'USDTBRL' || symbol === 'USDBRL';

  for (let i = 0; i <= 5; i++) {
    const yVal = minP + (i / 5) * pRange;
    const yPos = getY(yVal);
    ctx.beginPath();
    ctx.moveTo(padLeft, yPos);
    ctx.lineTo(w - padRight, yPos);
    ctx.stroke();

    ctx.fillStyle = '#6B7280';
    ctx.font = '10px JetBrains Mono';
    ctx.textAlign = 'right';
    const labelStr = isFx ? `R$ ${yVal.toFixed(4)}` : `R$ ${Math.round(yVal).toLocaleString('pt-BR')}`;
    ctx.fillText(labelStr, padLeft - 8, yPos + 3);
  }

  // 1. Faixa de Bollinger Clássica (Se Ativada - Padrão Ativo)
  if (showBb && upper.length === prices.length && lower.length === prices.length) {
    ctx.beginPath();
    for (let i = 0; i < upper.length; i++) {
      const x = getX(i);
      const y = getY(upper[i]);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    for (let i = lower.length - 1; i >= 0; i--) {
      const x = getX(i);
      const y = getY(lower[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = 'rgba(6, 182, 212, 0.10)'; // Preenchimento Ciano Nítido
    ctx.fill();

    // Linhas das Bandas Superior e Inferior
    ctx.strokeStyle = '#06B6D4';
    ctx.lineWidth = 1.6;
    ctx.setLineDash([5, 4]);

    ctx.beginPath();
    for (let i = 0; i < upper.length; i++) {
      const x = getX(i);
      const y = getY(upper[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();

    ctx.beginPath();
    for (let i = 0; i < lower.length; i++) {
      const x = getX(i);
      const y = getY(lower[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // 1.5 BANDA ZERO-LAG (+/- 2 SIGMA - ROXO/LILÁS VIBRANTE SE ATIVADA)
  if (showZl && zlUpper.length === prices.length && zlLower.length === prices.length) {
    ctx.beginPath();
    for (let i = 0; i < zlUpper.length; i++) {
      const x = getX(i);
      const y = getY(zlUpper[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    for (let i = zlLower.length - 1; i >= 0; i--) {
      const x = getX(i);
      const y = getY(zlLower[i]);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = 'rgba(192, 132, 252, 0.22)'; // Preenchimento da Banda Lilás rico e destacado
    ctx.fill();

    // Linha Superior da Banda Zero-Lag
    ctx.strokeStyle = '#C084FC';
    ctx.lineWidth = 1.8;
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    for (let i = 0; i < zlUpper.length; i++) {
      const x = getX(i);
      const y = getY(zlUpper[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Linha Inferior da Banda Zero-Lag
    ctx.beginPath();
    for (let i = 0; i < zlLower.length; i++) {
      const x = getX(i);
      const y = getY(zlLower[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // 2. Linha Principal de Preço (Ouro Claro)
  ctx.save();
  ctx.beginPath();
  for (let i = 0; i < prices.length; i++) {
    const x = getX(i);
    const y = getY(prices[i]);
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.strokeStyle = '#F59E0B';
  ctx.lineWidth = 2.0;
  ctx.stroke();
  ctx.restore();

  // 2.5 CURVA CENTRAL LILÁS ZERO-LAG (SUPERSMOOTHER DE JOHN EHLERS - DESENHADA POR CIMA SE ATIVADA)
  if (showZl && supersmoother.length === prices.length) {
    ctx.save();
    ctx.beginPath();
    for (let i = 0; i < supersmoother.length; i++) {
      const x = getX(i);
      const y = getY(supersmoother[i]);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = '#F0ABFC'; // Lilás Neon Vibrante
    ctx.lineWidth = 2.6;
    ctx.shadowColor = '#C084FC';
    ctx.shadowBlur = 10;
    ctx.stroke();
    ctx.restore();
  }

  // 3. Painel Inferior: Histograma de Velocidade Instantânea (dP/dt)
  const derivY0 = h - 35;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padLeft, derivY0);
  ctx.lineTo(w - padRight, derivY0);
  ctx.stroke();

  ctx.fillStyle = '#9CA3AF';
  ctx.font = '9px JetBrains Mono';
  ctx.textAlign = 'left';
  ctx.fillText('VELOCIDADE RELATIVA dP/dt (NORMALIZADA POR JANELA)', padLeft, derivY0 - 24);

  const maxAbsVel = Math.max(...velocities.map(v => Math.abs(v)), 0.0001);
  const maxBarH = 22;
  const barW = (w - padLeft - padRight) / velocities.length;

  for (let i = 0; i < velocities.length; i++) {
    const vel = velocities[i];
    const normRatio = Math.abs(vel) / maxAbsVel;
    const barH = Math.max(3, normRatio * maxBarH);
    const x = padLeft + i * barW;
    const y = vel >= 0 ? derivY0 - barH : derivY0;
    ctx.fillStyle = vel >= 0 ? '#10B981' : '#EF4444';
    ctx.fillRect(x, y, Math.max(1.5, barW - 1), barH);
  }

  // Rótulos de tempo no eixo X
  ctx.fillStyle = '#6B7280';
  ctx.font = '9px JetBrains Mono';
  ctx.textAlign = 'center';
  const totalPoints = timestamps.length;
  const numLabels = Math.min(7, totalPoints);
  const step = Math.max(1, Math.floor(totalPoints / (numLabels - 1)));

  for (let i = 0; i < totalPoints; i += step) {
    const x = getX(i);
    ctx.fillText(timestamps[i], x, h - 8);
  }

  // 4. CROSSHAIR & INSPEÇÃO INTERATIVA
  if (hoveredDataIndex >= 0 && hoveredDataIndex < prices.length && !isDraggingKineticsZoom) {
    const i = hoveredDataIndex;
    const x = getX(i);
    const y = getY(prices[i]);

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
    ctx.lineWidth = 1;
    ctx.setLineDash([2, 2]);
    ctx.beginPath();
    ctx.moveTo(x, padTop);
    ctx.lineTo(x, h - padBottom + 10);
    ctx.stroke();

    ctx.setLineDash([]);
    ctx.fillStyle = '#F59E0B';
    ctx.beginPath();
    ctx.arc(x, y, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 2;
    ctx.stroke();

    const badge = document.getElementById('chartInspectBadge');
    if (badge) {
      const pVal = isFx ? `R$ ${prices[i].toFixed(4)}` : `R$ ${prices[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
      const upVal = isFx ? `R$ ${upper[i].toFixed(4)}` : `R$ ${upper[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
      const lowVal = isFx ? `R$ ${lower[i].toFixed(4)}` : `R$ ${lower[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
      const zlUpVal = zlUpper && zlUpper[i] ? (isFx ? `R$ ${zlUpper[i].toFixed(4)}` : `R$ ${zlUpper[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const zlLowVal = zlLower && zlLower[i] ? (isFx ? `R$ ${zlLower[i].toFixed(4)}` : `R$ ${zlLower[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const ssVal = supersmoother && supersmoother[i] ? (isFx ? `R$ ${supersmoother[i].toFixed(4)}` : `R$ ${supersmoother[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const velVal = `${velocities[i] >= 0 ? '+' : ''}${velocities[i].toFixed(3)}%`;

      badge.style.display = 'block';
      let badgeContent = `
        <div class="ib-time">⏱️ ${timestamps[i]}</div>
        <div class="ib-price">Cotação: <b>${pVal}</b></div>
      `;
      if (showZl) {
        badgeContent += `
          <div class="ib-bands" style="color: #F0ABFC; font-weight: bold;">Curva Lilás ZL: ${ssVal || pVal}</div>
          <div class="ib-bands" style="color: #C084FC; font-size: 11px;">Envelopes ZL (±2σ): ${zlLowVal || lowVal} ↔ ${zlUpVal || upVal}</div>
        `;
      }
      if (showBb) {
        badgeContent += `
          <div class="ib-bands" style="color: #06B6D4; font-size: 10px;">Bollinger (SMA): ${lowVal} ↔ ${upVal}</div>
        `;
      }
      badgeContent += `
        <div class="ib-vel">Velocidade: <b style="color: ${velocities[i] >= 0 ? '#10B981' : '#EF4444'}">${velVal}</b></div>
      `;
      badge.innerHTML = badgeContent;

      const badgeW = 200;
      let badgeLeft = x + 15;
      if (badgeLeft + badgeW > w - 10) badgeLeft = x - badgeW - 15;
      badge.style.left = `${badgeLeft}px`;
      badge.style.top = `${Math.max(10, Math.min(h - 130, y - 20))}px`;
    }
  } else {
    const badge = document.getElementById('chartInspectBadge');
    if (badge) badge.style.display = 'none';
  }

  // ----------------------------------------------------------------------------
  // DESENHO DO RETÂNGULO DE SELEÇÃO DE ZOOM (DRAG-TO-ZOOM)
  // ----------------------------------------------------------------------------
  if (isDraggingKineticsZoom) {
    const rx1 = Math.min(kineticsDragStartX, kineticsDragCurrentX);
    const rx2 = Math.max(kineticsDragStartX, kineticsDragCurrentX);
    const rw = rx2 - rx1;

    ctx.save();
    ctx.fillStyle = 'rgba(6, 182, 212, 0.25)';
    ctx.fillRect(rx1, padTop, rw, chartH);
    ctx.strokeStyle = '#06B6D4';
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 4]);
    ctx.strokeRect(rx1, padTop, rw, chartH);
    ctx.restore();
  }
}

function initCanvasInteractions() {
  const canvas = document.getElementById('kineticsMainCanvas');
  if (!canvas) return;

  const padLeft = 75;
  const padRight = 30;

  const getActiveSeriesLength = () => {
    const assetsData = window.ASSETS_KINETICS_DATA || {};
    const asset = assetsData[currentKineticsAsset] || {};
    const tfData = (asset.timeframes && asset.timeframes[currentKineticsTimeframe]) || {};
    const fullPrices = tfData.precos || (tfData.series && tfData.series.prices) || [];
    if (!kineticsZoomRange) return fullPrices.length;
    return kineticsZoomRange[1] - kineticsZoomRange[0] + 1;
  };

  const handlePointerMove = (clientX) => {
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left;
    const plotW = rect.width - padLeft - padRight;
    const relX = x - padLeft;
    const totalLen = getActiveSeriesLength();

    if (isDraggingKineticsZoom) {
      kineticsDragCurrentX = Math.max(padLeft, Math.min(rect.width - padRight, x));
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
      return;
    }

    if (totalLen === 0 || relX < 0 || relX > plotW) {
      hoveredDataIndex = -1;
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
      return;
    }

    const pct = relX / plotW;
    const idx = Math.max(0, Math.min(totalLen - 1, Math.round(pct * (totalLen - 1))));

    if (hoveredDataIndex !== idx) {
      hoveredDataIndex = idx;
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
    }
  };

  const handlePointerDown = (clientX) => {
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left;
    if (x >= padLeft && x <= rect.width - padRight) {
      isDraggingKineticsZoom = true;
      kineticsDragStartX = x;
      kineticsDragCurrentX = x;
    }
  };

  const handlePointerUp = () => {
    if (!isDraggingKineticsZoom) return;
    isDraggingKineticsZoom = false;

    const rect = canvas.getBoundingClientRect();
    const plotW = rect.width - padLeft - padRight;
    const dragDist = Math.abs(kineticsDragCurrentX - kineticsDragStartX);

    if (dragDist >= 15) {
      const assetsData = window.ASSETS_KINETICS_DATA || {};
      const asset = assetsData[currentKineticsAsset] || {};
      const tfData = (asset.timeframes && asset.timeframes[currentKineticsTimeframe]) || {};
      const fullPrices = tfData.precos || (tfData.series && tfData.series.prices) || [];

      const currentOffset = kineticsZoomRange ? kineticsZoomRange[0] : 0;
      const currentLen = kineticsZoomRange ? (kineticsZoomRange[1] - kineticsZoomRange[0] + 1) : fullPrices.length;

      const relStart = Math.min(kineticsDragStartX, kineticsDragCurrentX) - padLeft;
      const relEnd = Math.max(kineticsDragStartX, kineticsDragCurrentX) - padLeft;

      const pctA = Math.max(0, Math.min(1, relStart / plotW));
      const pctB = Math.max(0, Math.min(1, relEnd / plotW));

      const idxA = currentOffset + Math.round(pctA * (currentLen - 1));
      const idxB = currentOffset + Math.round(pctB * (currentLen - 1));

      if (idxB - idxA >= 3) {
        kineticsZoomRange = [idxA, idxB];
      }
    }

    hoveredDataIndex = -1;
    renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
  };

  // Duplo-clique para desfazer o zoom na Página 3
  canvas.addEventListener('dblclick', () => {
    kineticsZoomRange = null;
    const resetBtn = document.getElementById('kineticsResetZoomBtn');
    if (resetBtn) resetBtn.style.display = 'none';
    renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
  });

  canvas.addEventListener('mousedown', (e) => handlePointerDown(e.clientX));
  window.addEventListener('mousemove', (e) => {
    if (isDraggingKineticsZoom) handlePointerMove(e.clientX);
  });
  canvas.addEventListener('mousemove', (e) => {
    if (!isDraggingKineticsZoom) handlePointerMove(e.clientX);
  });
  window.addEventListener('mouseup', handlePointerUp);

  canvas.addEventListener('mouseleave', () => {
    if (!isDraggingKineticsZoom) {
      hoveredDataIndex = -1;
      renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
    }
  });

  canvas.addEventListener('touchstart', (e) => {
    if (e.touches && e.touches[0]) handlePointerDown(e.touches[0].clientX);
  }, { passive: true });

  canvas.addEventListener('touchmove', (e) => {
    if (e.touches && e.touches[0]) handlePointerMove(e.touches[0].clientX);
  }, { passive: true });

  canvas.addEventListener('touchend', handlePointerUp);
}

// ------------------------------------------------------------------------------
// POLLER AO VIVO NO NAVEGADOR (ATUALIZAÇÃO INSTANTÂNEA A CADA 5 SEGUNDOS)
// ------------------------------------------------------------------------------
function startLiveBinancePoller() {
  const fetchLive = async () => {
    try {
      const symbols = ['BTCBRL', 'USDTBRL', 'SOLBRL', 'ETHBRL', 'LINKBRL', 'BNBBRL', 'ADABRL'];
      const url = `https://api.binance.com/api/v3/ticker/price`;
      const res = await fetch(url);
      const data = await res.json();

      if (Array.isArray(data) && window.ASSETS_KINETICS_DATA) {
        const pricesMap = {};
        data.forEach(item => {
          if (symbols.includes(item.symbol)) {
            pricesMap[item.symbol] = parseFloat(item.price);
          }
        });

        if (pricesMap.USDTBRL) {
          pricesMap.PAXGBRL = pricesMap.USDTBRL * 4470.0;
        }

        // Cotação ao vivo do Dólar Oficial via AwesomeAPI (fallback proporcional USDT)
        try {
          const resUsd = await fetch('https://economia.awesomeapi.com.br/last/USD-BRL');
          const dUsd = await resUsd.json();
          if (dUsd && dUsd.USDBRL) {
            pricesMap.USDBRL = (parseFloat(dUsd.USDBRL.bid) + parseFloat(dUsd.USDBRL.ask)) / 2.0;
          }
        } catch (eUsd) {
          if (pricesMap.USDTBRL) {
            pricesMap.USDBRL = pricesMap.USDTBRL * 0.9951;
          }
        }

        Object.keys(pricesMap).forEach(sym => {
          if (window.ASSETS_KINETICS_DATA[sym]) {
            window.ASSETS_KINETICS_DATA[sym].preco_atual = pricesMap[sym];
          }
        });

        renderKineticsCockpit(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA);
      }
    } catch (e) {
      // Falha segura
    }
  };

  const fetchChartsData = async () => {
    try {
      const ts = Date.now();
      const res = await fetch(`data/charts_data.js?_t=${ts}`, { cache: 'no-store' });
      if (!res.ok) return;
      const text = await res.text();
      const scriptFn = new Function(text);
      scriptFn();
      if (!isDraggingKineticsZoom && hoveredDataIndex === -1) {
        renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA || {});
      }
    } catch (e) {
      // Falha silenciosa
    }
  };

  kineticsPollerTimer = setInterval(fetchLive, 5000);
  setInterval(fetchChartsData, 20000);
}

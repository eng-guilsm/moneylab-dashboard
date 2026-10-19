/**
 * ==============================================================================
 * HARMONICUS SX // PÁGINA 3: ASSET DYNAMICS & MULTI-TIMEFRAME KINETICS CONTROLLER
 * Suporte a 6 Janelas de Tempo (1h, 24h, 1sem, 1m, 1a, tudo), Bandas de Bollinger,
 * Crosshair, Zoom Retangular Interativo & Duplo-Clique para Resetar
 * ==============================================================================
 */

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

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initChartsKinetics);
} else {
  initChartsKinetics();
}

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
    { key: 'USDBRL', label: '💵 DÓLAR COMERCIAL • BCB', color: '#10B981' },
    { key: 'BTCBRL', label: '🪙 BITCOIN', color: '#F59E0B' },
    { key: 'ETHBRL', label: '🔹 ETHEREUM', color: '#06B6D4' },
    { key: 'SOLBRL', label: '⚡ SOLANA', color: '#EC4899' },
    { key: 'LINKBRL', label: '🌐 CHAINLINK', color: '#8B5CF6' },
    { key: 'PAXGBRL', label: '🥇 OURO', color: '#FBBF24' },
    { key: 'USDTBRL', label: '💵 TETHER', color: '#2DD4BF' },
    { key: 'BNBBRL', label: '🟡 BNB CHAIN', color: '#EAB308' },
    { key: 'ADABRL', label: '🔷 CARDANO', color: '#3B82F6' }
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

      // Atualizar título do card sem parênteses redundantes
      const titleEl = document.getElementById('chartTitleText');
      const tfNames = {
        '1h': '1 HORA',
        '24h': '24 HORAS',
        '1sem': '1 SEMANA',
        '1m': '1 MÊS',
        '1a': '1 ANO',
        'tudo': 'HISTÓRICO COMPLETO'
      };
      if (titleEl) {
        titleEl.textContent = `CINÉTICA TEMPORAL & ENVELOPE DE BOLLINGER • ${tfNames[currentKineticsTimeframe] || '24 HORAS'}`;
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
  const priceFmt = isFx ? `R$ ${p.toFixed(4)}` : `R$ ${p.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  if (elPrice) elPrice.textContent = priceFmt;
  
  const elCardEyebrow = document.querySelector('.kin-price-card .card-eyebrow');
  if (elCardEyebrow) {
    if (symbol === 'USDBRL') {
      elCardEyebrow.innerHTML = 'COTAÇÃO OFICIAL USD/BRL <span style="color: #06B6D4; font-size: 0.60rem; margin-left: 6px; font-weight: 700; background: rgba(6, 182, 212, 0.15); padding: 2px 6px; border-radius: 4px; border: 1px solid rgba(6, 182, 212, 0.4);">OFICIAL BCB & FARIALIMER</span>';
    } else {
      elCardEyebrow.textContent = 'COTAÇÃO AO VIVO SPOT';
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
    elVar24h.textContent = `${v >= 0 ? '+' : ''}${v.toFixed(2)}% • ${tfData.label || tfKey.toUpperCase()}`;
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
  const fullDates = series.full_dates || [];

  if (fullPrices.length === 0) return;

  // Aplicar slice de zoom se ativo
  const startIndex = kineticsZoomRange ? kineticsZoomRange[0] : 0;
  const endIndex = kineticsZoomRange ? kineticsZoomRange[1] : (fullPrices.length - 1);

  const prices = fullPrices.slice(startIndex, endIndex + 1);
  const upper = fullUpper.length > 0 ? fullUpper.slice(startIndex, endIndex + 1) : prices;
  const lower = fullLower.length > 0 ? fullLower.slice(startIndex, endIndex + 1) : prices;
  let zlUpper = fullZlUpper.length > 0 ? fullZlUpper.slice(startIndex, endIndex + 1) : [];
  let zlLower = fullZlLower.length > 0 ? fullZlLower.slice(startIndex, endIndex + 1) : [];
  const supersmoother = fullSS.length > 0 ? fullSS.slice(startIndex, endIndex + 1) : [];
  const velocities = fullVelocities.slice(startIndex, endIndex + 1);
  const timestamps = fullTimestamps.slice(startIndex, endIndex + 1);
  const dates = fullDates.length > 0 ? fullDates.slice(startIndex, endIndex + 1) : [];

  // Fallback de alta precisão para garantir a Banda Zero-Lag caso não venha no dataset estático
  if (zlUpper.length === 0 && supersmoother.length === prices.length && prices.length > 0) {
    const isFxSymbol = symbol === 'USDTBRL' || symbol === 'USDBRL' || symbol === 'ADABRL';
    const decDigits = isFxSymbol ? 4 : 2;
    const win = Math.max(5, Math.min(20, Math.floor(prices.length / 3)));
    zlUpper = [];
    zlLower = [];
    for (let i = 0; i < prices.length; i++) {
      const start = Math.max(0, i - win + 1);
      let sumDiff = 0;
      let count = 0;
      for (let j = start; j <= i; j++) {
        sumDiff += Math.abs(prices[j] - supersmoother[j]);
        count++;
      }
      const meanDiff = count > 0 ? sumDiff / count : 1;
      const sigma = meanDiff * 1.25; // Estimador robusto de 1 sigma
      zlUpper.push(Number((supersmoother[i] + 2.0 * sigma).toFixed(decDigits)));
      zlLower.push(Number((supersmoother[i] - 2.0 * sigma).toFixed(decDigits)));
    }
  }

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

  const padLeft = 70;
  const padRight = 75;
  const padTop = 18;
  const padBottom = 66;
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

  // 2.8 LINHA DE PREÇO ATUAL, BEACON PULSANTE E ETIQUETA NO EIXO DIREITO
  if (prices.length > 0) {
    const currentVal = prices[prices.length - 1];
    const currentY = getY(currentVal);
    const lastX = getX(prices.length - 1);
    const isFx = symbol === 'USDTBRL' || symbol === 'USDBRL' || symbol === 'ADABRL';
    const badgeText = isFx ? `R$ ${currentVal.toFixed(4)}` : `R$ ${Math.round(currentVal).toLocaleString('pt-BR')}`;

    ctx.save();
    // Linha horizontal pontilhada de preço atual cruzando todo o gráfico
    ctx.strokeStyle = 'rgba(245, 158, 11, 0.60)';
    ctx.lineWidth = 1.2;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padLeft, currentY);
    ctx.lineTo(w - padRight, currentY);
    ctx.stroke();

    // Beacon pulsante (Halo) no último candle do gráfico
    ctx.setLineDash([]);
    ctx.fillStyle = 'rgba(245, 158, 11, 0.35)';
    ctx.beginPath();
    ctx.arc(lastX, currentY, 8, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#F59E0B';
    ctx.beginPath();
    ctx.arc(lastX, currentY, 4, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Etiqueta de Preço no Eixo Direito (Right Price Badge)
    const bw = 70;
    const bh = 18;
    const bx = w - padRight + 3;
    const by = Math.max(padTop, Math.min(h - padBottom - bh, currentY - bh / 2));

    ctx.fillStyle = '#F59E0B';
    ctx.beginPath();
    if (ctx.roundRect) {
      ctx.roundRect(bx, by, bw, bh, 3);
    } else {
      ctx.rect(bx, by, bw, bh);
    }
    ctx.fill();

    ctx.fillStyle = '#050811';
    ctx.font = 'bold 9.5px JetBrains Mono, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(badgeText.replace('R$ ', ''), bx + bw / 2, by + bh / 2);
    ctx.restore();
  }
  // ----------------------------------------------------------------------------
  // 3. SUB-PAINEL DE VELOCIDADE (dP/dt) & SEPARADORES
  // ----------------------------------------------------------------------------
  const derivY0 = padTop + chartH + 16; // Centro das barras dP/dt
  const timeAxisY = h - 26; // Linha base do eixo de tempo (~354px)

  // Linha divisória sutil entre área de preço e velocidade
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padLeft, padTop + chartH);
  ctx.lineTo(w - padRight, padTop + chartH);
  ctx.stroke();

  // Linha zero da velocidade
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padLeft, derivY0);
  ctx.lineTo(w - padRight, derivY0);
  ctx.stroke();

  ctx.fillStyle = '#6B7280';
  ctx.font = '8px JetBrains Mono, monospace';
  ctx.textAlign = 'left';
  ctx.fillText('VELOCIDADE dP/dt', padLeft, derivY0 - 10);

  const maxAbsVel = Math.max(...velocities.map(v => Math.abs(v)), 0.0001);
  const maxBarH = 13;
  const barW = (w - padLeft - padRight) / Math.max(1, velocities.length);

  for (let i = 0; i < velocities.length; i++) {
    const vel = velocities[i];
    const normRatio = Math.abs(vel) / maxAbsVel;
    const barH = Math.max(2, normRatio * maxBarH);
    const x = padLeft + i * barW;
    const y = vel >= 0 ? derivY0 - barH : derivY0;
    ctx.fillStyle = vel >= 0 ? '#10B981' : '#EF4444';
    ctx.fillRect(x, y, Math.max(1.2, barW - 0.8), barH);
  }

  // Linha base do eixo de tempo
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
  ctx.beginPath();
  ctx.moveTo(padLeft, timeAxisY);
  ctx.lineTo(w - padRight, timeAxisY);
  ctx.stroke();

  // ----------------------------------------------------------------------------
  // 3.5 RÓTULOS DE DATA E HORÁRIO NO EIXO X (COM GRIDLINES & TICKS)
  // ----------------------------------------------------------------------------
  const totalPoints = timestamps.length;
  if (totalPoints > 0) {
    const plotW = w - padLeft - padRight;
    const minLabelDist = 88; // Distância mínima entre rótulos para zero sobreposição
    const numLabels = Math.max(3, Math.min(8, Math.floor(plotW / minLabelDist)));

    const labelIndices = [];
    for (let k = 0; k < numLabels - 1; k++) {
      labelIndices.push(Math.round(k * (totalPoints - 1) / (numLabels - 1)));
    }
    if (!labelIndices.includes(totalPoints - 1)) {
      labelIndices.push(totalPoints - 1);
    }

    labelIndices.forEach(i => {
      const x = getX(i);
      const rawLabel = String(timestamps[i] || '');
      const fullDateStr = (dates && dates[i]) ? String(dates[i]) : '';

      // Gridline vertical pontilhada sutil atravessando a área do gráfico de preço
      ctx.save();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
      ctx.lineWidth = 1;
      ctx.setLineDash([2, 4]);
      ctx.beginPath();
      ctx.moveTo(x, padTop);
      ctx.lineTo(x, timeAxisY);
      ctx.stroke();
      ctx.restore();

      // Tick mark na linha base
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, timeAxisY);
      ctx.lineTo(x, timeAxisY + 4);
      ctx.stroke();

      // Decompor Horário e Data para exibição estética em duas linhas
      let timeStr = '';
      let dateStr = '';

      if (rawLabel.includes(' ')) {
        const parts = rawLabel.split(' ');
        dateStr = parts[0];
        timeStr = parts[1];
      } else if (rawLabel.includes(':')) {
        timeStr = rawLabel;
        if (fullDateStr) {
          const dp = fullDateStr.split(' ');
          dateStr = dp[0].substring(0, 5); // 'DD/MM'
        }
      } else {
        dateStr = rawLabel;
      }

      ctx.textAlign = 'center';
      if (timeStr && dateStr) {
        // Linha 1: Horário nítido
        ctx.fillStyle = '#E2E8F0';
        ctx.font = 'bold 9px JetBrains Mono, monospace';
        ctx.fillText(timeStr, x, timeAxisY + 11);

        // Linha 2: Data em ciano suave
        ctx.fillStyle = '#06B6D4';
        ctx.font = '8px JetBrains Mono, monospace';
        ctx.fillText(dateStr, x, timeAxisY + 21);
      } else {
        // Linha única centrada
        ctx.fillStyle = '#CBD5E1';
        ctx.font = 'bold 9px JetBrains Mono, monospace';
        ctx.fillText(rawLabel, x, timeAxisY + 15);
      }
    });
  }

  // ----------------------------------------------------------------------------
  // 4. CROSSHAIR & TOOLTIP ESTÉTICA DE ALTA RESOLUÇÃO
  // ----------------------------------------------------------------------------
  if (hoveredDataIndex >= 0 && hoveredDataIndex < prices.length && !isDraggingKineticsZoom) {
    const i = hoveredDataIndex;
    const x = getX(i);
    const y = getY(prices[i]);
    const rawLabel = String(timestamps[i] || '');
    const fullDateStr = (dates && dates[i]) ? String(dates[i]) : rawLabel;

    // Crosshair Vertical (Ciano Neon translúcido)
    ctx.save();
    ctx.strokeStyle = 'rgba(6, 182, 212, 0.45)';
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(x, padTop);
    ctx.lineTo(x, timeAxisY);
    ctx.stroke();

    // Crosshair Horizontal (Âmbar translúcido)
    ctx.strokeStyle = 'rgba(245, 158, 11, 0.35)';
    ctx.beginPath();
    ctx.moveTo(padLeft, y);
    ctx.lineTo(w - padRight, y);
    ctx.stroke();

    // Floating Badge no Eixo X (Pill de Data/Hora no Rodapé)
    const hoverBadgeText = fullDateStr || rawLabel;
    ctx.setLineDash([]);
    ctx.font = 'bold 9px JetBrains Mono, monospace';
    const tbw = ctx.measureText(hoverBadgeText).width + 14;
    const tbh = 18;
    const tbx = Math.max(padLeft, Math.min(w - padRight - tbw, x - tbw / 2));
    const tby = timeAxisY + 2;

    ctx.fillStyle = 'rgba(5, 8, 17, 0.95)';
    ctx.strokeStyle = '#06B6D4';
    ctx.lineWidth = 1.2;
    if (ctx.roundRect) {
      ctx.beginPath();
      ctx.roundRect(tbx, tby, tbw, tbh, 4);
      ctx.fill();
      ctx.stroke();
    } else {
      ctx.fillRect(tbx, tby, tbw, tbh);
      ctx.strokeRect(tbx, tby, tbw, tbh);
    }
    ctx.fillStyle = '#38BDF8';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(hoverBadgeText, tbx + tbw / 2, tby + tbh / 2);

    // Floating Badge no Eixo Y (Pill de Preço Hover no Eixo Direito)
    const hoverPriceText = isFx ? prices[i].toFixed(4) : Math.round(prices[i]).toLocaleString('pt-BR');
    const pbw = 64;
    const pbh = 18;
    const pbx = w - padRight + 3;
    const pby = Math.max(padTop, Math.min(padTop + chartH - pbh, y - pbh / 2));

    ctx.fillStyle = '#050811';
    ctx.strokeStyle = '#F59E0B';
    ctx.lineWidth = 1.2;
    if (ctx.roundRect) {
      ctx.beginPath();
      ctx.roundRect(pbx, pby, pbw, pbh, 4);
      ctx.fill();
      ctx.stroke();
    } else {
      ctx.fillRect(pbx, pby, pbw, pbh);
      ctx.strokeRect(pbx, pby, pbw, pbh);
    }
    ctx.fillStyle = '#FBBF24';
    ctx.font = 'bold 9px JetBrains Mono, monospace';
    ctx.fillText(hoverPriceText, pbx + pbw / 2, pby + pbh / 2);

    // Halo pulsante no ponto sob o cursor
    ctx.fillStyle = 'rgba(245, 158, 11, 0.25)';
    ctx.beginPath();
    ctx.arc(x, y, 9, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#F59E0B';
    ctx.beginPath();
    ctx.arc(x, y, 4.5, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 1.5;
    ctx.stroke();
    ctx.restore();

    // Tooltip HTML Flutuante de Alta Resolução
    const badge = document.getElementById('chartInspectBadge');
    if (badge) {
      const pVal = isFx ? `${prices[i].toFixed(4)} reais` : `${prices[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })} reais`;
      const upVal = isFx ? `${upper[i].toFixed(4)}` : `${upper[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
      const lowVal = isFx ? `${lower[i].toFixed(4)}` : `${lower[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`;
      const zlUpVal = zlUpper && zlUpper[i] ? (isFx ? `${zlUpper[i].toFixed(4)}` : `${zlUpper[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const zlLowVal = zlLower && zlLower[i] ? (isFx ? `${zlLower[i].toFixed(4)}` : `${zlLower[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const ssVal = supersmoother && supersmoother[i] ? (isFx ? `${supersmoother[i].toFixed(4)}` : `${supersmoother[i].toLocaleString('pt-BR', { minimumFractionDigits: 2 })}`) : null;
      const velVal = `${velocities[i] >= 0 ? '+' : ''}${velocities[i].toFixed(3)}%/min`;

      badge.style.display = 'block';
      let badgeContent = `
        <div class="ib-header">
          <span class="ib-status-dot"></span>
          <span class="ib-time">📅 ${fullDateStr}</span>
        </div>
        <div class="ib-price-row">
          <span class="ib-price-label">COTAÇÃO</span>
          <span class="ib-price-val">${pVal}</span>
        </div>
        <div class="ib-metrics-grid">
          <div class="ib-metric">
            <span class="ib-metric-lbl">Velocidade (dP/dt)</span>
            <span class="ib-metric-val ${velocities[i] >= 0 ? 'pos' : 'neg'}">${velVal}</span>
          </div>
        </div>
      `;

      if (showBb) {
        badgeContent += `
          <div class="ib-band-box bb">
            <div class="ib-band-title"><span>🔹</span> Bandas Bollinger (SMA 20)</div>
            <div class="ib-band-range">${lowVal} ↔ ${upVal}</div>
          </div>
        `;
      }

      if (showZl) {
        badgeContent += `
          <div class="ib-band-box zl">
            <div class="ib-band-title"><span>⚡</span> Zero-Lag SuperSmoother (±2σ)</div>
            <div class="ib-band-range">${zlLowVal || lowVal} ↔ ${zlUpVal || upVal}</div>
            ${ssVal ? `<div class="ib-band-sub">Eixo Zero-Lag: ${ssVal}</div>` : ''}
          </div>
        `;
      }

      badge.innerHTML = badgeContent;

      const badgeW = 230;
      let badgeLeft = x + 16;
      if (badgeLeft + badgeW > w - 12) badgeLeft = x - badgeW - 16;
      badge.style.left = `${badgeLeft}px`;
      badge.style.top = `${Math.max(12, Math.min(h - 170, y - 30))}px`;
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

  const padLeft = 70;
  const padRight = 75;

  const getActiveSeriesLength = () => {
    const assetsData = window.ASSETS_KINETICS_DATA || {};
    const asset = assetsData[currentKineticsAsset] || {};
    const tfData = (asset.timeframes && asset.timeframes[currentKineticsTimeframe]) || {};
    const fullPrices = tfData.precos || (tfData.series && tfData.series.prices) || (tfData.series && tfData.series.precos) || [];
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

        let hasPriceChange = false;
        Object.keys(pricesMap).forEach(sym => {
          if (window.ASSETS_KINETICS_DATA[sym] && sym !== 'USDBRL') {
            const newP = pricesMap[sym];
            if (window.ASSETS_KINETICS_DATA[sym].preco_atual !== newP) {
              hasPriceChange = true;
              window.ASSETS_KINETICS_DATA[sym].preco_atual = newP;
              
              // Atualizar também o último ponto da série para todos os timeframes desse ativo
              const tfs = window.ASSETS_KINETICS_DATA[sym].timeframes;
              if (tfs) {
                const dec = (sym === 'USDTBRL' || sym === 'ADABRL') ? 4 : 2;
                Object.keys(tfs).forEach(tf => {
                  const pArr = tfs[tf].precos || (tfs[tf].series && tfs[tf].series.prices);
                  if (pArr && pArr.length > 0) {
                    pArr[pArr.length - 1] = Number(newP.toFixed(dec));
                  }
                });
              }
            }
          }
        });

        if (hasPriceChange) {
          renderKineticsCockpit(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA);
          renderKineticsChart(currentKineticsAsset, currentKineticsTimeframe, window.ASSETS_KINETICS_DATA);
        }
      }
    } catch (e) {
      // Falha segura
    }
  };

  // Chamada imediata ao carregar a página (zero latência percebida)
  fetchLive();
  // Atualização leve a cada 5 segundos apenas para o ticker spot (sem travar a UI)
  kineticsPollerTimer = setInterval(fetchLive, 5000);
}


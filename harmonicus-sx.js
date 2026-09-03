/**
 * ==============================================================================
 * HARMONICUS SX // PÁGINA 2: SYNTHESIZER & SPECTRAL TOPOLOGY CONTROLLER (v5.0)
 * Processamento Digital de Sinais (DSP) de John F. Ehlers & Análise Espectral
 * Halos Espectrais Dinâmicos (Oitavados, Harmônicos, Anarmônicos),
 * Linhas de Campo de Direcionalidade (STE) & Cockpit de Decisão
 * ==============================================================================
 */

document.addEventListener('DOMContentLoaded', () => {
  initHarmonicusSX();
});

let activeTunerBand = 'daily';
let focusedSpectralNodeId = null; // null = visão panorâmica

let d3GraphSimulation = null;
let d3SvgSelection = null;
let d3ZoomRoot = null;
let d3ZoomBehavior = null;

let d3GraphNodes = [];
let d3GraphEdges = [];

function initHarmonicusSX() {
  const data = window.HARMONICUS_SX_DATA || {};

  initTabNavigation();
  initAudioControls();
  initRadioTuner(data.bands || []);
  initSpectralCockpit();
  initSpectralTelemetry(data.sensores || {});
  initOscilloscope();
  initD3NetworkGraph(data.nodes || [], data.edges || []);
  renderCWTSlices(data.cwt_slices || []);
}

// ------------------------------------------------------------------------------
// 1. NAVEGAÇÃO DE 3 ABAS COM RE-RENDERIZAÇÃO AUTOMÁTICA
// ------------------------------------------------------------------------------
function initTabNavigation() {
  const tabBtns = document.querySelectorAll('.nav-tab');
  const pages = {
    pageTactical: document.getElementById('pageTactical'),
    pageHarmonicus: document.getElementById('pageHarmonicus'),
    pageKinetics: document.getElementById('pageKinetics')
  };

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      const targetPage = btn.getAttribute('data-page');
      Object.entries(pages).forEach(([k, el]) => {
        if (el) {
          if (k === targetPage) el.classList.add('active');
          else el.classList.remove('active');
        }
      });

      // Se navegou para o Sintetizador, garantir renderização do Grafo D3
      if (targetPage === 'pageHarmonicus') {
        setTimeout(() => {
          const data = window.HARMONICUS_SX_DATA || {};
          initD3NetworkGraph(data.nodes || [], data.edges || []);
        }, 60);
      }

      // Se foi para a página de cinéticas, re-renderizar cockpit e canvas
      if (targetPage === 'pageKinetics') {
        setTimeout(() => {
          const asset = window.currentKineticsAsset || 'USDBRL';
          const tf = window.currentKineticsTimeframe || '24h';
          const data = window.ASSETS_KINETICS_DATA || {};
          if (typeof renderKineticsCockpit === 'function') {
            renderKineticsCockpit(asset, tf, data);
          }
          if (typeof renderKineticsChart === 'function') {
            renderKineticsChart(asset, tf, data);
          }
        }, 80);
      }
    });
  });
}

// ------------------------------------------------------------------------------
// 2. CONTROLES DE ÁUDIO MASTER
// ------------------------------------------------------------------------------
function initAudioControls() {
  const btnToggle = document.getElementById('audioToggleBtn');
  const audioIcon = document.getElementById('audioIcon');
  const audioText = document.getElementById('audioText');
  const masterVol = document.getElementById('masterVolume');

  if (btnToggle) {
    btnToggle.addEventListener('click', () => {
      const isNowPlaying = window.harmonicusAudio.toggleAudio();
      if (isNowPlaying) {
        btnToggle.classList.add('active');
        audioIcon.textContent = '🔊';
        audioText.textContent = 'ÁUDIO ATIVO';
      } else {
        btnToggle.classList.remove('active');
        audioIcon.textContent = '🔇';
        audioText.textContent = 'ÁUDIO MUTADO';
      }
    });
  }

  if (masterVol) {
    masterVol.addEventListener('input', (e) => {
      const vol = parseFloat(e.target.value);
      window.harmonicusAudio.setVolume(vol);
    });
  }
}

// ------------------------------------------------------------------------------
// 3. SINTONIZADOR DE RÁDIO ANALÓGICO COM GEOMETRIA ANGULAR CIRCULAR 360º REAL
// ------------------------------------------------------------------------------
function initRadioTuner(bands) {
  const dial = document.getElementById('tunerDial');
  const bandNameEl = document.getElementById('tunerBandName');
  const bandFreqEl = document.getElementById('tunerBandFreq');
  const bandDescEl = document.getElementById('tunerBandDesc');
  const markers = document.querySelectorAll('.svg-marker');

  if (!dial) return;

  // Mapeamento trigonométrico exato dos ângulos de cada marcador (arco de -135° a +135°)
  const markerAngleMap = {
    '15m': -135,
    '1h': -81,
    '4h': -27,
    '24h': 27,
    '7d': 81,
    '45d': 135
  };

  const markerToBand = {
    '15m': 'ultra_high',
    '1h': 'ultra_high',
    '4h': 'intraday',
    '24h': 'daily',
    '7d': 'macro',
    '45d': 'macro'
  };

  const markerReadouts = {
    '15m': { nome: 'ONDAS ULTRACURTAS // 15 MINUTOS', freq: 'Banda: 15 MIN | High Frequency (HF)', desc: 'Micro-oscilações rápidas de livro de ofertas e captura de micro-dips intradiários.' },
    '1h':  { nome: 'ONDAS HORÁRIAS // 1 HORA', freq: 'Banda: 1H | Curto Prazo', desc: 'Oscilações horárias de fluxo de liquidez institucional e repique de médias móveis.' },
    '4h':  { nome: 'ONDAS MÉDIAS // 4 HORAS', freq: 'Banda: 4H | Intraday Swing', desc: 'Ciclos intradiários de volume e rotação de correlação entre Bitcoin e Ethereum.' },
    '24h': { nome: 'ONDAS CURTAS // DIÁRIO (24H)', freq: 'Banda: 24H | Diário Dominante', desc: 'Harmônico fundamental de rotação de mercado. Cointegração forte entre TradFi e Cripto.' },
    '7d':  { nome: 'ONDAS SEMANAIS // 7 DIAS', freq: 'Banda: 7D | Swing Semanal', desc: 'Tendência semanal de fluxo de capital e ajuste de posições institucionais.' },
    '45d': { nome: 'ONDAS LONGAS // SECULAR (45D)', freq: 'Banda: 45D | Macro Secular', desc: 'As placas tectônicas do macro. Onde reside o ciclo secular do Plano Guiana Brasileira.' }
  };

  let currentAngle = 27; // Padrão: 24H
  let isDragging = false;
  let startMouseAngle = 0;
  let startDialAngle = 0;
  let startY = 0;

  const setDialRotation = (deg) => {
    // Permite arco amplo de -140° a +140° (280° de excursão do potenciômetro)
    currentAngle = Math.max(-140, Math.min(140, deg));
    dial.style.transform = `rotate(${currentAngle}deg)`;

    // Encontrar o marcador mais próximo do ângulo atual
    let closestMarker = '24h';
    let minDiff = 999;
    for (const [mId, mDeg] of Object.entries(markerAngleMap)) {
      const diff = Math.abs(currentAngle - mDeg);
      if (diff < minDiff) {
        minDiff = diff;
        closestMarker = mId;
      }
    }

    // Atualizar classe ativa nos marcadores SVG
    markers.forEach(m => {
      const markerKey = m.getAttribute('data-marker') || m.textContent.trim().toLowerCase();
      if (markerKey === closestMarker) m.classList.add('active');
      else m.classList.remove('active');
    });

    const targetBand = markerToBand[closestMarker] || 'daily';
    const readout = markerReadouts[closestMarker];

    if (bandNameEl && readout) bandNameEl.textContent = readout.nome;
    if (bandFreqEl && readout) bandFreqEl.textContent = readout.freq;
    if (bandDescEl && readout) bandDescEl.textContent = readout.desc;

    if (activeTunerBand !== targetBand) {
      activeTunerBand = targetBand;
      window.harmonicusAudio.setBand(activeTunerBand);
      updateD3GraphForBand(activeTunerBand);
    }
  };

  // Cálculo angular do ponteiro relativo ao centro geométrico (0° = 12h, positivo = horário)
  const getClockAngle = (clientX, clientY) => {
    const rect = dial.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const dx = clientX - centerX;
    const dy = clientY - centerY;
    return Math.atan2(dx, -dy) * (180 / Math.PI);
  };

  const onStart = (e) => {
    isDragging = true;
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    const clickDeg = getClockAngle(clientX, clientY);
    if (clickDeg >= -145 && clickDeg <= 145) {
      setDialRotation(clickDeg);
    }
    e.preventDefault();
  };

  const onMove = (e) => {
    if (!isDragging) return;
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    
    const targetDeg = getClockAngle(clientX, clientY);
    if (targetDeg > 135) {
      if (targetDeg < 170) setDialRotation(135);
    } else if (targetDeg < -135) {
      if (targetDeg > -170) setDialRotation(-135);
    } else {
      setDialRotation(targetDeg);
    }
  };

  const onEnd = () => { isDragging = false; };

  dial.addEventListener('mousedown', onStart);
  window.addEventListener('mousemove', onMove);
  window.addEventListener('mouseup', onEnd);
  dial.addEventListener('touchstart', onStart, { passive: false });
  window.addEventListener('touchmove', onMove, { passive: false });
  window.addEventListener('touchend', onEnd);

  // Scroll wheel suave
  dial.parentElement.addEventListener('wheel', (e) => {
    e.preventDefault();
    const step = e.deltaY > 0 ? 15 : -15;
    setDialRotation(currentAngle + step);
  }, { passive: false });

  // Clique direto em qualquer marcador SVG
  markers.forEach(m => {
    m.addEventListener('click', () => {
      const markerKey = m.getAttribute('data-marker') || m.textContent.trim().toLowerCase();
      const targetDeg = markerAngleMap[markerKey] || 0;
      setDialRotation(targetDeg);
    });
  });

  setDialRotation(27);
}

// ------------------------------------------------------------------------------
// ------------------------------------------------------------------------------
// 4. COCKPIT ESPECTRAL & BANCA POLIFÔNICA (ATÉ 4 ATIVOS / TÉTRADES DE HILBERT)
// ------------------------------------------------------------------------------
let polyphonicSelectedNodes = [];

function initSpectralCockpit() {
  // Atalhos de foco rápido
  const quickBtns = document.querySelectorAll('.qfb-btn');
  quickBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const assetKey = btn.getAttribute('data-asset');
      if (assetKey === 'all') {
        resetSpectralFocus();
      } else {
        const node = d3GraphNodes.find(n => n.id === assetKey);
        if (node) {
          polyphonicSelectedNodes = [node];
          updatePolyphonicSlotsUI();
          focusSpectralNode(assetKey);
        }
      }
    });
  });

  // Botão Drone Contínuo (Sustentação de até 4 vozes)
  const btnDrone = document.getElementById('btnToggleDrone');
  const droneIcon = document.getElementById('droneIcon');
  const droneText = document.getElementById('droneText');
  if (btnDrone) {
    btnDrone.addEventListener('click', () => {
      if (polyphonicSelectedNodes.length === 0) return;
      const isPlaying = window.harmonicusAudio.togglePolyphonicDrone(polyphonicSelectedNodes);
      if (isPlaying) {
        btnDrone.classList.add('active');
        if (droneIcon) droneIcon.textContent = '⏹';
        if (droneText) droneText.textContent = 'PARAR SOM';
      } else {
        btnDrone.classList.remove('active');
        if (droneIcon) droneIcon.textContent = '🔊';
        if (droneText) droneText.textContent = 'ACORDE CONTÍNUO';
      }
    });
  }

  // Botão Sequenciador Melódico (Play Arpeggio)
  const btnArp = document.getElementById('btnPlayArpeggio');
  const arpIcon = document.getElementById('arpeggioIcon');
  const arpText = document.getElementById('arpeggioText');
  if (btnArp) {
    btnArp.addEventListener('click', () => {
      if (polyphonicSelectedNodes.length === 0) return;
      btnArp.classList.add('playing');
      if (arpIcon) arpIcon.textContent = '⏳';
      if (arpText) arpText.textContent = 'MELODIA...';

      window.harmonicusAudio.playMelodicArpeggio(
        polyphonicSelectedNodes,
        (node, stepIdx) => {
          // Animação de pulso luminoso sincronizada no nó correspondente
          if (d3SvgSelection) {
            d3SvgSelection.selectAll('.nodes .node-group')
              .filter(d => d.id === node.id)
              .select('.node-body')
              .classed('node-arpeggio-pulse', true);
            
            setTimeout(() => {
              d3SvgSelection.selectAll('.nodes .node-group .node-body')
                .classed('node-arpeggio-pulse', false);
            }, 420);
          }

          // Destacar badge no HUD superior direito
          const badgeEl = document.getElementById(`fstBadgeItem${stepIdx}`);
          if (badgeEl) {
            badgeEl.classList.add('active-step');
            setTimeout(() => badgeEl.classList.remove('active-step'), 420);
          }
        },
        () => {
          btnArp.classList.remove('playing');
          if (arpIcon) arpIcon.textContent = '▶';
          if (arpText) arpText.textContent = 'PLAY MELODIA';
        }
      );
    });
  }

  // Botão Limpar Banca
  const btnClear = document.getElementById('btnClearPoly');
  if (btnClear) {
    btnClear.addEventListener('click', () => {
      resetSpectralFocus();
    });
  }

  // Botões de Remover nos Slots Individuais
  for (let i = 0; i < 4; i++) {
    const slotEl = document.getElementById(`polySlot${i}`);
    if (slotEl) {
      const rmBtn = slotEl.querySelector('.ps-remove');
      if (rmBtn) {
        rmBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          if (polyphonicSelectedNodes[i]) {
            polyphonicSelectedNodes.splice(i, 1);
            updatePolyphonicSlotsUI();
            if (polyphonicSelectedNodes.length > 0) {
              focusSpectralNode(polyphonicSelectedNodes[0].id);
            } else {
              resetSpectralFocus();
            }
          }
        });
      }
    }
  }
}

// ------------------------------------------------------------------------------
// 5. CLASSIFICAÇÃO ESPECTRAL DA TÉTRADE / ACORDE FORMADO (1 A 4 ATIVOS)
// ------------------------------------------------------------------------------
function calculateTetradChord(nodesList) {
  if (!nodesList || nodesList.length === 0) {
    return {
      type: "NENHUM ATIVO NA BANCA",
      sub: "Clique em até 4 nós no grafo para sintetizar acordes",
      consonance: 0,
      isTension: false
    };
  }

  if (nodesList.length === 1) {
    const n = nodesList[0];
    return {
      type: `SOLO // ${n.id.replace('BRL','').replace('_Pts','')}`,
      sub: `Fundamental: ${n.nota} (${n.fundamental_hz} Hz) • Vol: ${n.vol}% • PC1: ${(n.autovetor_pc1*100).toFixed(1)}%`,
      consonance: 100,
      isTension: n.id === 'VIX_Index'
    };
  }

  const freqs = nodesList.map(n => n.fundamental_hz || 220);
  const ids = nodesList.map(n => n.id);
  const hasVix = ids.includes('VIX_Index');

  if (nodesList.length === 2) {
    const ratio = Math.max(freqs[0], freqs[1]) / Math.min(freqs[0], freqs[1]);
    let interval = "Intervalo Espectral";
    let cons = 85;

    if (Math.abs(ratio - 2.0) < 0.04 || Math.abs(ratio - 1.0) < 0.025) {
      interval = "DÍADE: Oitava Fractal (2^k)";
      cons = 100;
    } else if (Math.abs(ratio - 1.50) < 0.035) {
      interval = "DÍADE: Quinta Justa (Poder)";
      cons = 98;
    } else if (Math.abs(ratio - 1.333) < 0.035) {
      interval = "DÍADE: Quarta Justa";
      cons = 95;
    } else if (Math.abs(ratio - 1.25) < 0.035) {
      interval = "DÍADE: Terça Maior (Expansão)";
      cons = 92;
    } else if (Math.abs(ratio - 1.414) < 0.045 || hasVix) {
      interval = "DÍADE: Trítono Diabolus / Tensão";
      cons = 42;
    }

    return {
      type: interval,
      sub: `${ids[0].replace('BRL','')} + ${ids[1].replace('BRL','')} // Consonância: ${cons}%`,
      consonance: cons,
      isTension: cons < 50
    };
  }

  if (nodesList.length === 3) {
    if (hasVix) {
      return {
        type: "TRÍADE DE TENSÃO & CHOQUE MACRO",
        sub: `Dissonância de Cauda (VIX Ativo) // Consonância: 38%`,
        consonance: 38,
        isTension: true
      };
    }
    const isMajor = ids.includes('BTCBRL') && ids.includes('ETHBRL');
    return {
      type: isMajor ? "TRÍADE MAIOR: Expansão de Liquidez" : "TRÍADE ESPECTRAL: Rotação Harmônica",
      sub: `Clustered Fasor // Consonância: ${isMajor ? '94%' : '88%'}`,
      consonance: isMajor ? 94 : 88,
      isTension: false
    };
  }

  if (nodesList.length >= 4) {
    if (hasVix) {
      return {
        type: "TÉTRADE DE RISCO & PÂNICO SISTÊMICO",
        sub: `Tensão 4D com VIX // Consonância: 32% (Stop Ativo)`,
        consonance: 32,
        isTension: true
      };
    }
    const isCryptoConsonant = ids.includes('BTCBRL') && (ids.includes('ETHBRL') || ids.includes('SOLBRL'));
    return {
      type: isCryptoConsonant ? "TÉTRADE: Harmonious Major 7th (4D)" : "TÉTRADE: Subespaço Multiespectral",
      sub: `Subespaço de Hilbert 4D // Consonância: ${isCryptoConsonant ? '96%' : '90%'}`,
      consonance: isCryptoConsonant ? 96 : 90,
      isTension: false
    };
  }
}

function updatePolyphonicSlotsUI() {
  const count = polyphonicSelectedNodes.length;
  const counterEl = document.getElementById('polySlotsCounter');
  if (counterEl) counterEl.textContent = `${count} / 4`;

  const chordInfo = calculateTetradChord(polyphonicSelectedNodes);
  const badgeEl = document.getElementById('polyChordBadge');
  const typeEl = document.getElementById('pcbType');
  const subEl = document.getElementById('pcbSub');

  if (badgeEl) {
    if (count > 0) badgeEl.classList.add('active');
    else badgeEl.classList.remove('active');
  }
  if (typeEl) {
    typeEl.textContent = chordInfo.type;
    typeEl.style.color = chordInfo.isTension ? '#EF4444' : (chordInfo.consonance >= 90 ? '#10B981' : '#F59E0B');
  }
  if (subEl) subEl.textContent = chordInfo.sub;

  // Atualizar HUD Fixo no Canto Superior Direito do Grafo
  const fstChord = document.getElementById('fstChordBadge');
  const fstBadgesRow = document.getElementById('fstBadgesRow');
  const slotSymbols = ['①', '②', '③', '④'];

  if (fstChord) {
    if (count === 0) {
      fstChord.textContent = 'VAZIO';
      fstChord.style.borderColor = 'rgba(245, 158, 11, 0.35)';
      fstChord.style.color = '#FFFFFF';
    } else {
      const shortName = chordInfo.type.split('//')[0].replace('DÍADE: ', '').replace('TRÍADE: ', '').replace('TÉTRADE: ', '').trim();
      fstChord.textContent = shortName.length > 20 ? shortName.substring(0, 20) : shortName;
      fstChord.style.borderColor = chordInfo.isTension ? '#EF4444' : (chordInfo.consonance >= 90 ? '#10B981' : '#F59E0B');
      fstChord.style.color = chordInfo.isTension ? '#EF4444' : (chordInfo.consonance >= 90 ? '#10B981' : '#F59E0B');
    }
  }

  if (fstBadgesRow) {
    if (count === 0) {
      fstBadgesRow.innerHTML = '<span class="fst-empty-hint">Nenhum ativo (clique nos nós)</span>';
    } else {
      fstBadgesRow.innerHTML = polyphonicSelectedNodes.map((n, i) => `
        <span class="fst-badge-item" id="fstBadgeItem${i}" style="border-color:${n.cor}; box-shadow: 0 0 8px ${n.cor}33;">
          <span class="fst-badge-idx">${slotSymbols[i]}</span>
          <span style="color:${n.cor}; font-weight:800;">${n.id.replace('BRL','').replace('_Pts','')}</span>
          <span class="fst-badge-note">[${n.nota}]</span>
        </span>
      `).join('');
    }
  }

  const btnDrone = document.getElementById('btnToggleDrone');
  if (btnDrone) {
    if (count === 0 && window.harmonicusAudio.isPolyDroneActive) {
      window.harmonicusAudio.stopPolyphonicDrone();
      btnDrone.classList.remove('active');
      const dIcon = document.getElementById('droneIcon');
      const dText = document.getElementById('droneText');
      if (dIcon) dIcon.textContent = '🔊';
      if (dText) dText.textContent = 'ACORDE CONTÍNUO';
    }
  }

  for (let i = 0; i < 4; i++) {
    const slotEl = document.getElementById(`polySlot${i}`);
    if (!slotEl) continue;

    const node = polyphonicSelectedNodes[i];
    const tickerEl = slotEl.querySelector('.ps-ticker');
    const noteEl = slotEl.querySelector('.ps-note');

    if (node) {
      slotEl.className = 'poly-slot filled';
      slotEl.style.borderColor = node.cor;
      if (tickerEl) tickerEl.innerHTML = `<span style="color:${node.cor}; font-weight:800;">${node.id.replace('BRL','').replace('_Pts','')}</span>`;
      if (noteEl) noteEl.textContent = `${node.nota}`;
    } else {
      slotEl.className = 'poly-slot empty';
      slotEl.style.borderColor = '';
      if (tickerEl) tickerEl.textContent = 'Vazio';
      if (noteEl) noteEl.textContent = '--';
    }
  }
}

function toggleNodeSelectionInPolyphony(node) {
  const existingIdx = polyphonicSelectedNodes.findIndex(n => n.id === node.id);
  if (existingIdx >= 0) {
    if (polyphonicSelectedNodes.length > 1) {
      polyphonicSelectedNodes.splice(existingIdx, 1);
    }
  } else {
    if (polyphonicSelectedNodes.length < 4) {
      polyphonicSelectedNodes.push(node);
    } else {
      polyphonicSelectedNodes[3] = node;
    }
  }
  updatePolyphonicSlotsUI();

  if (window.harmonicusAudio.isPolyDroneActive) {
    window.harmonicusAudio.startPolyphonicDrone(polyphonicSelectedNodes);
  }
}

// ------------------------------------------------------------------------------
// 6. CLASSIFICAÇÃO ESPECTRAL RELACIONAL: OITAVADOS, HARMÔNICOS E ANARMÔNICOS
// ------------------------------------------------------------------------------
function calculateSpectralRelations(targetNode, allNodes, allEdges) {
  if (!targetNode) {
    return { octaves: [], harmonics: [], anarmonics: [], neutrals: allNodes, directLinks: new Map() };
  }

  const fA = targetNode.fundamental_hz || 220.0;
  const tId = targetNode.id;

  const directLinks = new Map();
  allEdges.forEach(e => {
    const sId = typeof e.source === 'object' ? e.source.id : e.source;
    const tgId = typeof e.target === 'object' ? e.target.id : e.target;
    if (sId === tId) directLinks.set(tgId, { edge: e, direction: 'out', coherence: e.coerencia });
    if (tgId === tId) directLinks.set(sId, { edge: e, direction: 'in', coherence: e.coerencia });
  });

  const octaves = [];
  const harmonics = [];
  const anarmonics = [];
  const neutrals = [];

  allNodes.forEach(node => {
    if (node.id === tId) return;

    const fB = node.fundamental_hz || 220.0;
    const ratio = Math.max(fA, fB) / Math.min(fA, fB);
    const linkInfo = directLinks.get(node.id);

    // 1. OITAVADOS (Ressonância Fractal: 1.0x, 2.0x, 4.0x)
    const isOctave = (Math.abs(ratio - 1.0) < 0.025) || 
                     (Math.abs(ratio - 2.0) < 0.04) || 
                     (Math.abs(ratio - 4.0) < 0.08) ||
                     (Math.abs(ratio - 0.5) < 0.02);

    // 2. HARMÔNICOS CONSONANTES (Quinta 1.50, Quarta 1.33, Terça 1.25, Sexta 1.67 ou Coerência Forte >= 0.65)
    const isHarmonicRatio = (Math.abs(ratio - 1.50) < 0.035) ||
                            (Math.abs(ratio - 1.333) < 0.035) ||
                            (Math.abs(ratio - 1.25) < 0.035) ||
                            (Math.abs(ratio - 1.667) < 0.04);
    const isHarmonicCoherence = linkInfo && linkInfo.coherence >= 0.65 && node.id !== 'VIX_Index' && targetNode.id !== 'VIX_Index';

    // 3. ANARMÔNICOS DISSONANTES (Trítono 1.414, Segunda menor 1.067, Sétima 1.875 ou VIX de Pânico)
    const isTritone = (Math.abs(ratio - 1.414) < 0.045);
    const isDissonantRatio = (Math.abs(ratio - 1.067) < 0.025) || (Math.abs(ratio - 1.875) < 0.04);
    const isVixTension = (node.id === 'VIX_Index' || targetNode.id === 'VIX_Index') && 
                         (node.classe === 'Cripto' || targetNode.classe === 'Cripto' || node.classe === 'TradFi' || targetNode.classe === 'TradFi');

    if (isOctave) {
      octaves.push(node);
    } else if (isVixTension || isTritone || isDissonantRatio) {
      anarmonics.push(node);
    } else if (isHarmonicRatio || isHarmonicCoherence) {
      harmonics.push(node);
    } else {
      neutrals.push(node);
    }
  });

  return { octaves, harmonics, anarmonics, neutrals, directLinks };
}

// ------------------------------------------------------------------------------
// 7. MOTOR DE FOCO ESPECTRAL, HALOS E LINHAS DE CAMPO DIRECIONAL
// ------------------------------------------------------------------------------
function focusSpectralNode(nodeId) {
  if (!d3SvgSelection || d3GraphNodes.length === 0) return;
  const targetNode = d3GraphNodes.find(n => n.id === nodeId);
  if (!targetNode) return;

  focusedSpectralNodeId = nodeId;
  const relations = calculateSpectralRelations(targetNode, d3GraphNodes, d3GraphEdges);

  // 1. Atualizar Cockpit Lateral
  const facBadge = document.getElementById('facBadge');
  const facHint = document.getElementById('facHint');
  const facTitle = document.getElementById('facTitle');
  const facMeta = document.getElementById('facMeta');

  if (facBadge) facBadge.textContent = targetNode.classe.toUpperCase();
  if (facHint) facHint.textContent = 'Auditoria Espectral Ativa';
  if (facTitle) facTitle.innerHTML = `<span style="color: ${targetNode.cor};">${targetNode.nome}</span> (${targetNode.id})`;
  if (facMeta) facMeta.textContent = `Fundamental: ${targetNode.nota} (${targetNode.fundamental_hz} Hz) • Vol: ${targetNode.vol}% • PC1: ${(targetNode.autovetor_pc1 * 100).toFixed(1)}%`;

  // Preencher Lista de Oitavados
  const listOct = document.getElementById('listOctave');
  const countOct = document.getElementById('countOctave');
  if (countOct) countOct.textContent = relations.octaves.length;
  if (listOct) {
    if (relations.octaves.length === 0) {
      listOct.innerHTML = '<span class="srp-empty">Nenhum par em oitava pura</span>';
    } else {
      listOct.innerHTML = relations.octaves.map(n => `
        <span class="srp-tag tag-octave" data-id="${n.id}" title="${n.nome} (${n.nota} / ${n.fundamental_hz} Hz)">
          ⚪ ${n.id.replace('BRL','').replace('_Pts','')} [${n.nota}]
        </span>
      `).join('');
    }
  }

  // Preencher Lista de Harmônicos
  const listHarm = document.getElementById('listHarmonic');
  const countHarm = document.getElementById('countHarmonic');
  if (countHarm) countHarm.textContent = relations.harmonics.length;
  if (listHarm) {
    if (relations.harmonics.length === 0) {
      listHarm.innerHTML = '<span class="srp-empty">Sem acoplamento harmônico direto</span>';
    } else {
      listHarm.innerHTML = relations.harmonics.map(n => `
        <span class="srp-tag tag-harmonic" data-id="${n.id}" title="${n.nome} (${n.nota} / ${n.fundamental_hz} Hz)">
          🔵 ${n.id.replace('BRL','').replace('_Pts','')} [${n.nota}]
        </span>
      `).join('');
    }
  }

  // Preencher Lista de Anarmônicos
  const listAnarm = document.getElementById('listAnarmonic');
  const countAnarm = document.getElementById('countAnarmonic');
  if (countAnarm) countAnarm.textContent = relations.anarmonics.length;
  if (listAnarm) {
    if (relations.anarmonics.length === 0) {
      listAnarm.innerHTML = '<span class="srp-empty">Sem tensão anarmônica detectada</span>';
    } else {
      listAnarm.innerHTML = relations.anarmonics.map(n => `
        <span class="srp-tag tag-anarmonic" data-id="${n.id}" title="${n.nome} (${n.nota} / ${n.fundamental_hz} Hz)">
          🔴 ${n.id.replace('BRL','').replace('_Pts','')} [${n.nota}]
        </span>
      `).join('');
    }
  }

  // Eventos de clique nas tags do Cockpit
  document.querySelectorAll('.srp-tag').forEach(tag => {
    tag.addEventListener('click', (e) => {
      e.stopPropagation();
      const nextId = tag.getAttribute('data-id');
      const nextNode = d3GraphNodes.find(n => n.id === nextId);
      if (nextNode) {
        toggleNodeSelectionInPolyphony(nextNode);
        focusSpectralNode(nextId);
      }
    });
  });

  // Atualizar botões de foco rápido
  document.querySelectorAll('.qfb-btn').forEach(btn => {
    if (btn.getAttribute('data-asset') === nodeId) btn.classList.add('active');
    else btn.classList.remove('active');
  });

  // 2. Atualizar Grafo D3 (Halos, Opacidade e Linhas de Campo)
  const nodeGroups = d3SvgSelection.selectAll('.nodes .node-group');
  const linkLines = d3SvgSelection.selectAll('.links line');

  const selectedIds = new Set(polyphonicSelectedNodes.map(n => n.id));
  if (selectedIds.size === 0) selectedIds.add(nodeId);

  const octaveIds = new Set(relations.octaves.map(n => n.id));
  const harmonicIds = new Set(relations.harmonics.map(n => n.id));
  const anarmonicIds = new Set(relations.anarmonics.map(n => n.id));
  const relevantIds = new Set([...selectedIds, ...octaveIds, ...harmonicIds, ...anarmonicIds]);

  // Transição de Nós
  nodeGroups.transition().duration(300)
    .style('opacity', d => relevantIds.has(d.id) ? 1.0 : 0.15)
    .style('filter', d => relevantIds.has(d.id) ? 'none' : 'grayscale(80%) brightness(0.25)');

  // Anéis e Halos
  nodeGroups.each(function(d) {
    const grp = d3.select(this);
    const halo = grp.select('.node-halo');
    const ring = grp.select('.active-node-ring');

    halo.attr('class', 'node-halo').style('display', 'none');
    ring.style('display', 'none');

    if (selectedIds.has(d.id)) {
      ring.style('display', 'block');
    } else if (octaveIds.has(d.id)) {
      halo.classed('halo-octave', true).style('display', 'block');
    } else if (harmonicIds.has(d.id)) {
      halo.classed('halo-harmonic', true).style('display', 'block');
    } else if (anarmonicIds.has(d.id)) {
      halo.classed('halo-anarmonic', true).style('display', 'block');
    }
  });

  // Transição de Arestas e Linhas de Campo
  linkLines.transition().duration(300)
    .attr('stroke', l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      const isBothSelected = selectedIds.has(sId) && selectedIds.has(tId);
      if (isBothSelected) return '#F59E0B';

      const isIncident = (selectedIds.has(sId) || selectedIds.has(tId));
      if (!isIncident) return '#1E293B';

      const otherId = selectedIds.has(sId) ? tId : sId;
      if (octaveIds.has(otherId)) return '#FFFFFF';
      if (anarmonicIds.has(otherId)) return '#EF4444';
      if (harmonicIds.has(otherId)) return '#06B6D4';
      return '#F59E0B';
    })
    .attr('stroke-width', l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      const isIncident = (selectedIds.has(sId) || selectedIds.has(tId));
      return isIncident ? 3.5 : 1.0;
    })
    .attr('stroke-opacity', l => {
      const sId = typeof l.source === 'object' ? l.source.id : l.source;
      const tId = typeof l.target === 'object' ? l.target.id : l.target;
      const isIncident = (selectedIds.has(sId) || selectedIds.has(tId));
      return isIncident ? 1.0 : 0.04;
    });

  // Linhas de campo animadas para arestas incidentes
  linkLines.each(function(l) {
    const lineEl = d3.select(this);
    const sId = typeof l.source === 'object' ? l.source.id : l.source;
    const tId = typeof l.target === 'object' ? l.target.id : l.target;
    const isIncident = (selectedIds.has(sId) || selectedIds.has(tId));

    if (isIncident) {
      lineEl.classed('directional-field-line', true);
      const otherId = selectedIds.has(sId) ? tId : sId;
      if (octaveIds.has(otherId)) lineEl.attr('marker-end', 'url(#arrow-white)');
      else if (anarmonicIds.has(otherId)) lineEl.attr('marker-end', 'url(#arrow-red)');
      else if (harmonicIds.has(otherId)) lineEl.attr('marker-end', 'url(#arrow-cyan)');
      else lineEl.attr('marker-end', 'url(#arrow-gold)');
    } else {
      lineEl.classed('directional-field-line', false).attr('marker-end', null);
    }
  });

  // 3. Tocar Sonificação Analítica Musical Pura
  if (window.harmonicusAudio && !window.harmonicusAudio.isPolyDroneActive) {
    if (polyphonicSelectedNodes.length > 1 && typeof window.harmonicusAudio.playBankChord === 'function') {
      window.harmonicusAudio.playBankChord(polyphonicSelectedNodes);
    } else if (typeof window.harmonicusAudio.playNodeTone === 'function') {
      window.harmonicusAudio.playNodeTone(targetNode.fundamental_hz, targetNode.nome);
    }
  }
}

// ------------------------------------------------------------------------------
// 8. RESTAURAR VISÃO PANORÂMICA (SEM FILTRO / TODOS OS NÓS)
// ------------------------------------------------------------------------------
function resetSpectralFocus() {
  focusedSpectralNodeId = null;
  polyphonicSelectedNodes = [];
  updatePolyphonicSlotsUI();

  const facBadge = document.getElementById('facBadge');
  const facHint = document.getElementById('facHint');
  const facTitle = document.getElementById('facTitle');
  const facMeta = document.getElementById('facMeta');

  if (facBadge) facBadge.textContent = 'VISÃO PANORÂMICA';
  if (facHint) facHint.textContent = 'Clique em um ativo para diagnosticar';
  if (facTitle) facTitle.textContent = '🌐 REDE COMPLETA (26 ATIVOS)';
  if (facMeta) facMeta.textContent = 'Afinação: Multiespectral • Coerência Global Ativa';

  const listOct = document.getElementById('listOctave');
  const listHarm = document.getElementById('listHarmonic');
  const listAnarm = document.getElementById('listAnarmonic');
  const countOct = document.getElementById('countOctave');
  const countHarm = document.getElementById('countHarmonic');
  const countAnarm = document.getElementById('countAnarmonic');

  if (countOct) countOct.textContent = '0';
  if (countHarm) countHarm.textContent = '0';
  if (countAnarm) countAnarm.textContent = '0';

  if (listOct) listOct.innerHTML = '<span class="srp-empty">Selecione um ativo</span>';
  if (listHarm) listHarm.innerHTML = '<span class="srp-empty">Selecione um ativo</span>';
  if (listAnarm) listAnarm.innerHTML = '<span class="srp-empty">Selecione um ativo</span>';

  document.querySelectorAll('.qfb-btn').forEach(btn => {
    if (btn.getAttribute('data-asset') === 'all') btn.classList.add('active');
    else btn.classList.remove('active');
  });

  if (!d3SvgSelection) return;

  const nodeGroups = d3SvgSelection.selectAll('.nodes .node-group');
  const linkLines = d3SvgSelection.selectAll('.links line');

  nodeGroups.transition().duration(300)
    .style('opacity', 1.0)
    .style('filter', 'none');

  nodeGroups.selectAll('.node-halo').style('display', 'none');
  nodeGroups.selectAll('.active-node-ring').style('display', 'none');

  linkLines.transition().duration(300)
    .attr('stroke', d => d.coerencia >= 0.75 ? '#06B6D4' : '#4B5563')
    .attr('stroke-width', d => Math.max(1.5, d.peso * 0.9))
    .attr('stroke-opacity', d => Math.max(0.25, d.coerencia));

  linkLines.classed('directional-field-line', false).attr('marker-end', null);
}

// ------------------------------------------------------------------------------
// 9. OBSERVÁVEIS ESPECTRAIS EM TEMPO REAL (TELEMETRIA DSP DE EHLERS & GRANGER)
// ------------------------------------------------------------------------------
function initSpectralTelemetry(sensores) {
  const telePC1 = document.getElementById('telePC1');
  const teleT0 = document.getElementById('teleT0');
  const teleSNR = document.getElementById('teleSNR');
  const teleSTE = document.getElementById('teleSTE');

  const pc1Val = sensores.pc1 !== undefined ? (sensores.pc1 * 100).toFixed(1) + '%' : '39.4%';
  const t0Val = sensores.t0_ehlers !== undefined ? sensores.t0_ehlers.toFixed(1) + 'h' : '13.7h';
  const snrVal = sensores.snr_ehlers !== undefined ? (sensores.snr_ehlers > 0 ? '+' : '') + sensores.snr_ehlers.toFixed(1) + ' dB' : '+12.8 dB';
  const steVal = sensores.fluxo_ste !== undefined ? (sensores.fluxo_ste > 0 ? '+' : '') + sensores.fluxo_ste.toFixed(4) : '+0.1325';

  if (telePC1) telePC1.textContent = pc1Val;
  if (teleT0) teleT0.textContent = t0Val;
  if (teleSNR) {
    teleSNR.textContent = snrVal;
    const snrNum = parseFloat(sensores.snr_ehlers || 12.8);
    teleSNR.style.color = snrNum >= 6.0 ? '#10B981' : (snrNum >= 0 ? '#F59E0B' : '#EF4444');
  }
  if (teleSTE) {
    teleSTE.textContent = steVal;
    const steNum = parseFloat(sensores.fluxo_ste || 0.13);
    teleSTE.style.color = steNum >= 0 ? '#10B981' : '#EF4444';
  }
}

// ------------------------------------------------------------------------------
// 10. OSCILOSCÓPIO CRT DE 60 FPS REATIVO
// ------------------------------------------------------------------------------
function initOscilloscope() {
  const canvas = document.getElementById('oscCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  function resizeCanvas() {
    canvas.width = canvas.parentElement.clientWidth || 900;
    canvas.height = 140;
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  let phase = 0;

  function renderOsc() {
    requestAnimationFrame(renderOsc);

    const w = canvas.width;
    const h = canvas.height;

    // Rastro fosforescente
    ctx.fillStyle = 'rgba(2, 4, 8, 0.35)';
    ctx.fillRect(0, 0, w, h);

    // Grade CRT
    ctx.strokeStyle = 'rgba(6, 182, 212, 0.08)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 0; x < w; x += 40) { ctx.moveTo(x, 0); ctx.lineTo(x, h); }
    for (let y = 0; y < h; y += 20) { ctx.moveTo(0, y); ctx.lineTo(w, y); }
    ctx.stroke();

    // Linha central
    ctx.strokeStyle = 'rgba(6, 182, 212, 0.2)';
    ctx.beginPath();
    ctx.moveTo(0, h / 2);
    ctx.lineTo(w, h / 2);
    ctx.stroke();

    const isPlaying = window.harmonicusAudio && (window.harmonicusAudio.isPlaying || window.harmonicusAudio.isPolyDroneActive);
    const dataArray = isPlaying ? window.harmonicusAudio.getWaveformData() : null;

    let freqMult = 1.0;
    let speedMult = 1.0;
    switch (activeTunerBand) {
      case 'ultra_high': freqMult = 3.8; speedMult = 2.5; break;
      case 'intraday':   freqMult = 2.2; speedMult = 1.6; break;
      case 'daily':      freqMult = 1.0; speedMult = 1.0; break;
      case 'macro':      freqMult = 0.45; speedMult = 0.4; break;
    }

    phase += 0.035 * speedMult;

    // Cor do feixe CRT
    let beamColor = '#06B6D4';
    if (focusedSpectralNodeId === 'VIX_Index') beamColor = '#EF4444';
    else if (focusedSpectralNodeId === 'BTCBRL') beamColor = '#F59E0B';
    else if (focusedSpectralNodeId === 'SOLBRL') beamColor = '#EC4899';
    else if (focusedSpectralNodeId === 'PAXG_Ouro') beamColor = '#FBBF24';
    else beamColor = '#06B6D4';

    ctx.lineWidth = 2.5;
    ctx.strokeStyle = beamColor;
    ctx.shadowBlur = 12;
    ctx.shadowColor = beamColor;
    ctx.beginPath();

    const points = 256;
    const sliceWidth = w / points;
    const defaultDamping = 0.50;

    for (let i = 0; i < points; i++) {
      let v = 1.0;

      if (isPlaying && dataArray && dataArray.length > 0) {
        const raw = dataArray[Math.floor((i / points) * dataArray.length)];
        v = raw / 128.0;
      } else {
        const t = (i * 0.03 * freqMult) + phase;
        const noise = (Math.random() - 0.5) * (defaultDamping * 0.22);
        
        if (focusedSpectralNodeId === 'VIX_Index') {
          const saw = (t % (Math.PI * 2)) / Math.PI - 1.0;
          v = 1.0 + 0.32 * Math.sin(t) + 0.22 * Math.sin(t * 1.414) + 0.12 * saw + noise * 1.6;
        } else if (focusedSpectralNodeId === 'BTCBRL') {
          v = 1.0 + 0.28 * Math.sin(t) + 0.14 * Math.sin(t * 1.5) + 0.07 * Math.sin(t * 2.0) + noise;
        } else {
          v = 1.0 + 0.20 * Math.sin(t) + 0.10 * Math.sin(t * 2) + noise * 0.4;
        }
      }

      const y = (v * h) / 2;
      const x = i * sliceWidth;

      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }

    ctx.stroke();
    ctx.shadowBlur = 0;
  }

  renderOsc();
}

// ------------------------------------------------------------------------------
// 11. GRAFO TOPOLÓGICO DOS 26 ATIVOS COM HALOS & LINHAS DE CAMPO DIRECIONAIS
// ------------------------------------------------------------------------------
function initD3NetworkGraph(rawNodes, rawEdges) {
  const container = document.getElementById('networkGraphStage');
  const btnReset = document.getElementById('btnResetZoom');
  const fniTag = document.getElementById('fniTag');
  const fniTitle = document.getElementById('fniTitle');
  const fniSub = document.getElementById('fniSub');

  if (!container || !window.d3) return;

  const dataNodes = (rawNodes && rawNodes.length > 0) ? rawNodes : (window.HARMONICUS_SX_DATA && window.HARMONICUS_SX_DATA.nodes) || [];
  const dataEdges = (rawEdges && rawEdges.length > 0) ? rawEdges : (window.HARMONICUS_SX_DATA && window.HARMONICUS_SX_DATA.edges) || [];

  if (dataNodes.length === 0) return;

  d3GraphNodes = dataNodes.map(d => ({
    id: d.id,
    nome: d.nome,
    classe: d.classe,
    fundamental_hz: d.fundamental_hz,
    nota: d.nota,
    cor: d.cor,
    vol: d.vol,
    autovetor_pc1: d.autovetor_pc1
  }));

  d3GraphEdges = dataEdges.map(d => ({
    source: typeof d.source === 'object' ? d.source.id : d.source,
    target: typeof d.target === 'object' ? d.target.id : d.target,
    coerencia: d.coerencia,
    peso: d.peso,
    tipo: d.tipo
  }));

  const rect = container.getBoundingClientRect();
  const width = Math.max(rect.width || container.clientWidth || 900, 700);
  const height = Math.max(rect.height || container.clientHeight || 420, 400);

  // Limpar SVGs anteriores
  d3.select(container).selectAll('svg').remove();

  const svg = d3.select(container)
    .append('svg')
    .attr('width', '100%')
    .attr('height', '100%')
    .attr('viewBox', [0, 0, width, height]);

  d3SvgSelection = svg;

  // Defs com Marcadores de Seta SVG Direcionais (Linhas de Campo)
  const defs = svg.append('defs');

  const addMarker = (id, color) => {
    defs.append('marker')
      .attr('id', id)
      .attr('viewBox', '0 -5 10 10')
      .attr('refX', 30)
      .attr('refY', 0)
      .attr('markerWidth', 6)
      .attr('markerHeight', 6)
      .attr('orient', 'auto')
      .append('path')
      .attr('d', 'M0,-4L10,0L0,4')
      .attr('fill', color);
  };

  addMarker('arrow-gold', '#F59E0B');
  addMarker('arrow-cyan', '#06B6D4');
  addMarker('arrow-red', '#EF4444');
  addMarker('arrow-white', '#FFFFFF');

  // Container de Zoom e Pan
  d3ZoomRoot = svg.append('g').attr('class', 'zoom-root');

  d3ZoomBehavior = d3.zoom()
    .scaleExtent([0.4, 3.0])
    .on('zoom', (event) => {
      d3ZoomRoot.attr('transform', event.transform);
    });

  svg.call(d3ZoomBehavior);

  if (btnReset) {
    btnReset.onclick = () => {
      svg.transition().duration(600).call(
        d3ZoomBehavior.transform,
        d3.zoomIdentity.translate(0, 0).scale(1)
      );
      resetSpectralFocus();
    };
  }

  // Simulação física compacta e agrupada
  d3GraphSimulation = d3.forceSimulation(d3GraphNodes)
    .force('link', d3.forceLink(d3GraphEdges).id(d => d.id).distance(d => Math.max(40, 72 - (d.coerencia * 30))))
    .force('charge', d3.forceManyBody().strength(-105))
    .force('center', d3.forceCenter(width / 2, height / 2))
    .force('radial', d3.forceRadial(Math.min(width, height) * 0.28, width / 2, height / 2).strength(0.18))
    .force('collision', d3.forceCollide().radius(d => Math.max(24, 26 + d.autovetor_pc1 * 26) + 6));

  // Arestas
  const link = d3ZoomRoot.append('g')
    .attr('class', 'links')
    .selectAll('line')
    .data(d3GraphEdges)
    .enter().append('line')
    .attr('stroke', d => d.coerencia >= 0.75 ? '#06B6D4' : '#4B5563')
    .attr('stroke-width', d => Math.max(1.5, d.peso * 0.9))
    .attr('stroke-opacity', d => Math.max(0.25, d.coerencia));

  // Nós
  const node = d3ZoomRoot.append('g')
    .attr('class', 'nodes')
    .selectAll('g')
    .data(d3GraphNodes)
    .enter().append('g')
    .attr('class', 'node-group')
    .attr('data-id', d => d.id)
    .call(d3.drag()
      .on('start', dragstarted)
      .on('drag', dragged)
      .on('end', dragended));

  // 1. Halo Espectral Relacional (Branco, Azul ou Vermelho)
  node.append('circle')
    .attr('class', 'node-halo')
    .attr('r', d => Math.max(22, 24 + d.autovetor_pc1 * 24) + 8)
    .style('display', 'none');

  // 2. Anel de Seleção Ativa (Dourado Pulsante)
  node.append('circle')
    .attr('class', 'active-node-ring')
    .attr('r', d => Math.max(22, 24 + d.autovetor_pc1 * 24) + 4)
    .style('display', 'none');

  // 3. Círculo do Ativo com Cor Temática
  node.append('circle')
    .attr('class', 'node-body')
    .attr('r', d => Math.max(22, 24 + d.autovetor_pc1 * 24))
    .attr('fill', d => d.cor)
    .attr('stroke', '#FFFFFF')
    .attr('stroke-width', 2.0)
    .attr('stroke-opacity', 0.9)
    .style('cursor', 'pointer')
    .style('transition', 'all 0.3s ease')
    .style('filter', d => `drop-shadow(0 0 10px ${d.cor})`);

  // 4. Texto Símbolo do Ativo
  node.append('text')
    .text(d => {
      const clean = d.id.replace('BRL', '').replace('_Pts', '').replace('_USD', '').replace('_Yield', '').replace('_Index', '');
      return clean.length > 5 ? clean.substring(0, 5) : clean;
    })
    .attr('x', 0)
    .attr('y', 4)
    .attr('text-anchor', 'middle')
    .attr('fill', '#030712')
    .attr('font-size', '11px')
    .attr('font-weight', '800')
    .attr('font-family', 'JetBrains Mono, monospace')
    .style('pointer-events', 'none');

  // INSPEÇÃO NO HUD FIXO (CANTO SUPERIOR ESQUERDO)
  node.on('mouseover', (event, d) => {
    if (fniTag) fniTag.textContent = `${d.classe.toUpperCase()} // ${d.nota}`;
    if (fniTitle) fniTitle.innerHTML = `<span style="color: ${d.cor}; font-weight:800;">${d.nome}</span> (${d.id})`;
    if (fniSub) fniSub.innerHTML = `Afinação: <b>${d.fundamental_hz} Hz</b> • Vol: <b>${d.vol}%</b> • PC1: <b>${(d.autovetor_pc1*100).toFixed(1)}%</b>`;
  })
  .on('mouseout', () => {
    if (focusedSpectralNodeId) {
      const fNode = d3GraphNodes.find(n => n.id === focusedSpectralNodeId);
      if (fNode) {
        if (fniTag) fniTag.textContent = `${fNode.classe.toUpperCase()} // ${fNode.nota}`;
        if (fniTitle) fniTitle.innerHTML = `<span style="color: ${fNode.cor}; font-weight:800;">${fNode.nome}</span> (${fNode.id})`;
        if (fniSub) fniSub.innerHTML = `Afinação: <b>${fNode.fundamental_hz} Hz</b> • Vol: <b>${fNode.vol}%</b> • PC1: <b>${(fNode.autovetor_pc1*100).toFixed(1)}%</b>`;
      }
    } else {
      if (fniTag) fniTag.textContent = 'INSPEÇÃO ESPECTRAL';
      if (fniTitle) fniTitle.textContent = 'PASSE O MOUSE NO GRAFO';
      if (fniSub) fniSub.textContent = 'Inspecione afinação (Hz), classe e volatilidade instantânea';
    }
  })
  .on('click', (event, d) => {
    event.stopPropagation();
    toggleNodeSelectionInPolyphony(d);
    focusSpectralNode(d.id);
  });

  // Clique no fundo do SVG restaura a visão panorâmica
  svg.on('click', () => {
    resetSpectralFocus();
  });

  // Tick com contenção suave
  d3GraphSimulation.on('tick', () => {
    d3GraphNodes.forEach(d => {
      const r = 32;
      d.x = Math.max(r, Math.min(width - r, d.x));
      d.y = Math.max(r, Math.min(height - r, d.y));
    });

    link
      .attr('x1', d => d.source.x)
      .attr('y1', d => d.source.y)
      .attr('x2', d => d.target.x)
      .attr('y2', d => d.target.y);

    node
      .attr('transform', d => `translate(${d.x}, ${d.y})`);
  });

  function dragstarted(event, d) {
    if (!event.active) d3GraphSimulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  function dragged(event, d) {
    d.fx = event.x;
    d.fy = event.y;
  }

  function dragended(event, d) {
    if (!event.active) d3GraphSimulation.alphaTarget(0);
    d.fx = null;
    d.fy = null;
  }
}

// ------------------------------------------------------------------------------
// 11. SINTONIZADOR DE ONDAS NO GRAFO
// ------------------------------------------------------------------------------
function updateD3GraphForBand(bandId) {
  if (!d3SvgSelection) return;
  const links = d3SvgSelection.selectAll('.links line');

  let bandColor = '#06B6D4';
  if (bandId === 'ultra_high') bandColor = '#F59E0B';
  else if (bandId === 'intraday') bandColor = '#06B6D4';
  else if (bandId === 'daily') bandColor = '#10B981';
  else if (bandId === 'macro') bandColor = '#EF4444';

  links.transition().duration(300)
    .attr('stroke', d => {
      if (focusedSpectralNodeId) return d3.select(this).attr('stroke');
      if (bandId === 'ultra_high') return (d.source.classe === 'Cripto' && d.target.classe === 'Cripto') ? '#F59E0B' : '#374151';
      if (bandId === 'intraday') return d.coerencia >= 0.70 ? '#06B6D4' : '#374151';
      if (bandId === 'daily') return d.coerencia >= 0.50 ? '#10B981' : '#4B5563';
      return (d.source.classe === 'Macro' || d.target.classe === 'Macro') ? '#EF4444' : '#374151';
    })
    .attr('stroke-opacity', d => {
      if (focusedSpectralNodeId) return d3.select(this).attr('stroke-opacity');
      return Math.max(0.25, d.coerencia);
    });
}

// ------------------------------------------------------------------------------
// 12. RENDERIZAÇÃO DAS FATIAS CWT MORLET (CORREÇÃO DE CAMPOS E DB)
// ------------------------------------------------------------------------------
function renderCWTSlices(slices) {
  const container = document.getElementById('cwtBarsContainer');
  if (!container) return;

  const latest = (slices && slices.length > 0) ? slices[0] : {
    escala_15m: 2.4,
    escala_1h: 1.8,
    escala_4h: 0.9,
    escala_24h: -0.59
  };

  const scales = [
    { name: "Escala 15 MIN", freq: "HF (Alta Frequência)", val: latest.escala_15m !== undefined ? latest.escala_15m : 2.4 },
    { name: "Escala 1H", freq: "Intraday Curto", val: latest.escala_1h !== undefined ? latest.escala_1h : 1.8 },
    { name: "Escala 4H", freq: "Intraday Médio", val: latest.escala_4h !== undefined ? latest.escala_4h : 0.9 },
    { name: "Escala 24H", freq: "Ciclo Diário Dominante", val: latest.escala_24h !== undefined ? latest.escala_24h : -0.59 }
  ];

  container.innerHTML = scales.map(s => {
    const isNeg = s.val < 0;
    const absVal = Math.min(100, Math.abs(s.val) * 10);
    const color = isNeg ? '#06B6D4' : '#EF4444';
    return `
      <div class="cwt-bar-row">
        <div class="cwt-bar-label"><span>${s.name}</span> <small>${s.freq}</small></div>
        <div class="cwt-bar-track">
          <div class="cwt-bar-fill" style="width: ${absVal}%; background: ${color};"></div>
        </div>
        <div class="cwt-bar-val" style="color: ${color}">${s.val > 0 ? '+' : ''}${s.val.toFixed(2)} dB</div>
      </div>
    `;
  }).join('');
}

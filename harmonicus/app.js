/**
 * HARMONICUS — Spectral Topology & Market Equalizer Engine
 * Powered by D3.js v7 & Web Audio API
 */

(function() {
  'use strict';

  // State Management
  const state = {
    dataset: null,
    activeEpoch: '2026-ALL',
    activeBand: 'daily',
    corrThreshold: 0.25,
    mstOnly: false,
    selectedNodeId: null,
    isPlayingTimeline: false,
    timelineInterval: null,
    isAudioMuted: true,
    isPhysicsFrozen: false,
    audioCtx: null,
    audioNodes: null
  };

  const epochKeys = ['2026-ALL', '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08'];
  const epochNames = {
    '2026-ALL': 'ANO COMPLETO (2026)',
    '2026-01': 'JANEIRO 2026',
    '2026-02': 'FEVEREIRO 2026',
    '2026-03': 'MARÇO 2026',
    '2026-04': 'ABRIL 2026',
    '2026-05': 'MAIO 2026',
    '2026-06': 'JUNHO 2026',
    '2026-07': 'JULHO 2026',
    '2026-08': 'AGOSTO 2026'
  };

  const bandDescriptions = {
    'ultra_high': {
      title: 'Ultra-Alta / Ruído (15m - 1h)',
      desc: 'Microestrutura e arbitragem de alta frequência. Criptoativos formam um arquipélago quase isolado do TradFi, dominado por ruído microeconômico.'
    },
    'intraday': {
      title: 'Intraday / Sessão (4h - 8h)',
      desc: 'Dinâmica intradiária e ciclos de abertura de pregões (B3 / NY / Londres). Primeiras pontes de contágio cambial começam a se formar.'
    },
    'daily': {
      title: 'Swing / Diário (24h)',
      desc: 'Ciclo diário consolidado. Pontes entre TradFi e Criptoativos emergem com clareza estrutural através de liquidez global (S&P 500 / DXY).'
    },
    'macro': {
      title: 'Macro / Secular (3d - 7d)',
      desc: 'Tendências seculares e alinhamento macroeconômico. Alta coerência com títulos do tesouro americano (US10Y), commodities e ciclos cambiais.'
    }
  };

  // D3 Elements
  let svg, gZoom, linkLayer, nodeLayer, simulation;
  let zoomBehavior;

  // DOM Elements
  const dom = {
    networkSvg: document.getElementById('networkSvg'),
    graphContainer: document.getElementById('graphContainer'),
    nodeTooltip: document.getElementById('nodeTooltip'),
    epochBadge: document.getElementById('epochBadge'),
    timelineSlider: document.getElementById('timelineSlider'),
    playTimelineBtn: document.getElementById('playTimelineBtn'),
    playIcon: document.getElementById('playIcon'),
    playText: document.getElementById('playText'),
    timelineTicks: document.getElementById('timelineTicks'),
    thresholdSlider: document.getElementById('thresholdSlider'),
    thresholdVal: document.getElementById('thresholdVal'),
    mstOnlyToggle: document.getElementById('mstOnlyToggle'),
    nodeEdgeCounter: document.getElementById('nodeEdgeCounter'),
    bandDescBox: document.getElementById('bandDescBox'),
    arValue: document.getElementById('arValue'),
    arBarFill: document.getElementById('arBarFill'),
    dominantHubVal: document.getElementById('dominantHubVal'),
    coherenceVal: document.getElementById('coherenceVal'),
    syncPairsList: document.getElementById('syncPairsList'),
    hedgePairsList: document.getElementById('hedgePairsList'),
    spectralInsightText: document.getElementById('spectralInsightText'),
    resetViewBtn: document.getElementById('resetViewBtn'),
    togglePhysicsBtn: document.getElementById('togglePhysicsBtn'),
    audioToggleBtn: document.getElementById('audioToggleBtn')
  };

  // 1. Initialize Application
  async function init() {
    initD3Canvas();
    setupEventListeners();
    await loadData();
    updateView();
  }

  // 2. Load JSON Data
  async function loadData() {
    try {
      const resp = await fetch('network_spectrum_data.json');
      if (!resp.ok) throw new Error(`HTTP error ${resp.status}`);
      state.dataset = await resp.json();
      console.log('Harmonicus dataset loaded successfully:', state.dataset);
    } catch (err) {
      console.warn('Could not fetch network_spectrum_data.json directly. Using fallback embedded structure.', err);
      state.dataset = generateFallbackData();
    }
  }

  // 3. Initialize D3 Canvas
  function initD3Canvas() {
    const width = dom.graphContainer.clientWidth || 800;
    const height = dom.graphContainer.clientHeight || 600;

    svg = d3.select('#networkSvg')
      .attr('viewBox', [0, 0, width, height]);

    // Defs for Glow Filters and Gradients
    const defs = svg.append('defs');
    
    // Glow filter
    const filter = defs.append('filter')
      .attr('id', 'glow')
      .attr('x', '-50%').attr('y', '-50%')
      .attr('width', '200%').attr('height', '200%');
    filter.append('feGaussianBlur')
      .attr('stdDeviation', '4')
      .attr('result', 'coloredBlur');
    const feMerge = filter.append('feMerge');
    feMerge.append('feMergeNode').attr('in', 'coloredBlur');
    feMerge.append('feMergeNode').attr('in', 'SourceGraphic');

    gZoom = svg.append('g').attr('class', 'g-zoom');
    linkLayer = gZoom.append('g').attr('class', 'link-layer');
    nodeLayer = gZoom.append('g').attr('class', 'node-layer');

    zoomBehavior = d3.zoom()
      .scaleExtent([0.3, 4])
      .on('zoom', (event) => {
        gZoom.attr('transform', event.transform);
      });

    svg.call(zoomBehavior);

    // D3 Force Simulation
    simulation = d3.forceSimulation()
      .force('link', d3.forceLink().id(d => d.id).distance(d => (d.distance || 1.0) * 110 + 35))
      .force('charge', d3.forceManyBody().strength(-350).distanceMax(500))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('collide', d3.forceCollide().radius(d => (d.size || 20) + 16))
      .on('tick', ticked);

    // Click on canvas resets isolation
    svg.on('click', (event) => {
      if (event.target.tagName === 'svg' || event.target.classList.contains('g-zoom')) {
        state.selectedNodeId = null;
        dom.nodeTooltip.classList.add('hidden');
        resetHighlights();
      }
    });

    window.addEventListener('resize', () => {
      const w = dom.graphContainer.clientWidth;
      const h = dom.graphContainer.clientHeight;
      svg.attr('viewBox', [0, 0, w, h]);
      simulation.force('center', d3.forceCenter(w / 2, h / 2));
      simulation.alpha(0.2).restart();
    });
  }

  // 4. Update View (Filter, Graph, Telemetry)
  function updateView() {
    if (!state.dataset || !state.dataset.data) return;

    const epochData = state.dataset.data[state.activeEpoch];
    if (!epochData) return;

    const bandData = epochData[state.activeBand];
    if (!bandData) return;

    // Filter edges by threshold & MST
    const rawEdges = bandData.edges || [];
    const filteredEdges = rawEdges.filter(e => {
      if (state.mstOnly) return e.is_mst;
      return Math.abs(e.weight) >= state.corrThreshold || e.is_mst;
    });

    // Deep copy nodes to retain D3 simulation state (x, y, vx, vy)
    const rawNodes = bandData.nodes || [];
    const currentNodesMap = new Map((simulation.nodes() || []).map(n => [n.id, n]));

    const nodes = rawNodes.map(n => {
      const existing = currentNodesMap.get(n.id);
      return {
        ...n,
        x: existing ? existing.x : undefined,
        y: existing ? existing.y : undefined,
        vx: existing ? existing.vx : 0,
        vy: existing ? existing.vy : 0
      };
    });

    // Rebind Edges (links)
    const links = filteredEdges.map(e => ({
      source: e.source,
      target: e.target,
      weight: e.weight,
      distance: e.distance,
      is_mst: e.is_mst,
      type: e.type
    }));

    // Update Counter
    dom.nodeEdgeCounter.textContent = `${nodes.length} Ativos | ${links.length} Conexões`;

    // Render D3 Graph
    renderGraph(nodes, links);

    // Update Telemetry Panel & Descriptions
    updateTelemetry(bandData.telemetry);

    // Update Equalizer Description
    const bInfo = bandDescriptions[state.activeBand];
    dom.bandDescBox.innerHTML = `
      <span class="band-name">${bInfo.title}</span>
      <p class="band-detail">${bInfo.desc}</p>
    `;

    // Trigger Audio drone update if unmuted
    if (!state.isAudioMuted) {
      updateAudioDrone(bandData.telemetry);
    }
  }

  // 5. Render D3 Graph
  function renderGraph(nodes, links) {
    // LINKS
    const link = linkLayer.selectAll('line.link-line')
      .data(links, d => `${d.source.id || d.source}_${d.target.id || d.target}`);

    link.exit().transition().duration(300).style('stroke-opacity', 0).remove();

    const linkEnter = link.enter().append('line')
      .attr('class', d => `link-line ${d.type} ${d.is_mst ? 'mst-edge' : ''}`)
      .style('stroke-width', d => d.is_mst ? 2.5 : Math.max(1, Math.abs(d.weight) * 3))
      .style('stroke-opacity', 0)
      .style('stroke', d => d.type === 'sync' ? 'var(--neon-cyan)' : 'var(--neon-magenta)');

    const linkMerged = linkEnter.merge(link);
    linkMerged.transition().duration(400)
      .style('stroke-opacity', d => d.is_mst ? 0.85 : Math.min(0.7, Math.abs(d.weight) * 0.8))
      .style('stroke-width', d => d.is_mst ? 2.5 : Math.max(1, Math.abs(d.weight) * 3));

    // NODES
    const node = nodeLayer.selectAll('g.node-group')
      .data(nodes, d => d.id);

    node.exit().transition().duration(300).style('opacity', 0).remove();

    const nodeEnter = node.enter().append('g')
      .attr('class', 'node-group')
      .call(d3.drag()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended)
      );

    // Outer Halo Ring
    nodeEnter.append('circle')
      .attr('class', 'node-halo')
      .attr('r', d => (d.size || 18) + 5)
      .attr('fill', 'none')
      .attr('stroke', d => d.color || '#06B6D4')
      .attr('stroke-width', 1.5)
      .attr('stroke-opacity', 0.4)
      .attr('stroke-dasharray', '3, 3');

    // Core Circle
    nodeEnter.append('circle')
      .attr('class', 'node-core')
      .attr('r', d => d.size || 18)
      .attr('fill', d => d.color || '#06B6D4')
      .attr('fill-opacity', 0.25)
      .attr('stroke', d => d.color || '#06B6D4')
      .attr('stroke-width', 2);

    // Node Label
    nodeEnter.append('text')
      .attr('class', 'node-label')
      .attr('dy', 4)
      .text(d => d.id);

    // Interactivity
    nodeEnter
      .on('mouseenter', (event, d) => showTooltip(event, d))
      .on('mouseleave', () => hideTooltip())
      .on('click', (event, d) => {
        event.stopPropagation();
        isolateNode(d);
      });

    const nodeMerged = nodeEnter.merge(node);
    nodeMerged.select('circle.node-core')
      .transition().duration(400)
      .attr('r', d => d.size || 18)
      .attr('fill', d => d.color)
      .attr('stroke', d => d.color);

    nodeMerged.select('circle.node-halo')
      .transition().duration(400)
      .attr('r', d => (d.size || 18) + 5)
      .attr('stroke', d => d.color);

    // Restart Simulation
    simulation.nodes(nodes);
    simulation.force('link').links(links);
    simulation.alpha(0.35).restart();
  }

  function ticked() {
    linkLayer.selectAll('line.link-line')
      .attr('x1', d => d.source.x)
      .attr('y1', d => d.source.y)
      .attr('x2', d => d.target.x)
      .attr('y2', d => d.target.y);

    nodeLayer.selectAll('g.node-group')
      .attr('transform', d => `translate(${d.x}, ${d.y})`);
  }

  // Drag Behaviors
  function dragstarted(event, d) {
    if (!event.active && !state.isPhysicsFrozen) simulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
  }

  function dragged(event, d) {
    d.fx = event.x;
    d.fy = event.y;
  }

  function dragended(event, d) {
    if (!event.active && !state.isPhysicsFrozen) simulation.alphaTarget(0);
    if (!state.isPhysicsFrozen) {
      d.fx = null;
      d.fy = null;
    }
  }

  // 6. Tooltips & Isolation
  function showTooltip(event, d) {
    dom.nodeTooltip.classList.remove('hidden');
    document.getElementById('ttCategory').textContent = (d.category || 'ASSET').toUpperCase();
    document.getElementById('ttSymbol').textContent = d.id;
    document.getElementById('ttName').textContent = d.name;
    document.getElementById('ttBetweenness').textContent = (d.betweenness || 0).toFixed(4);
    document.getElementById('ttDegree').textContent = `${d.degree || 0} conexões`;
    document.getElementById('ttVol').textContent = `${((d.volatility || 0) * 100).toFixed(1)}% a.a.`;
    
    const retEl = document.getElementById('ttReturn');
    const retVal = d.cum_return || 0;
    retEl.textContent = `${retVal >= 0 ? '+' : ''}${retVal.toFixed(2)}%`;
    retEl.style.color = retVal >= 0 ? 'var(--neon-emerald)' : 'var(--neon-magenta)';
  }

  function hideTooltip() {
    if (!state.selectedNodeId) {
      dom.nodeTooltip.classList.add('hidden');
    }
  }

  function isolateNode(selected) {
    state.selectedNodeId = selected.id;
    showTooltip(null, selected);

    const connectedNodeIds = new Set([selected.id]);
    
    // Highlight links
    linkLayer.selectAll('line.link-line')
      .style('stroke-opacity', d => {
        const s = d.source.id || d.source;
        const t = d.target.id || d.target;
        if (s === selected.id || t === selected.id) {
          connectedNodeIds.add(s);
          connectedNodeIds.add(t);
          return 1.0;
        }
        return 0.05;
      })
      .style('stroke-width', d => {
        const s = d.source.id || d.source;
        const t = d.target.id || d.target;
        return (s === selected.id || t === selected.id) ? 3.5 : 1;
      });

    // Dim other nodes
    nodeLayer.selectAll('g.node-group')
      .style('opacity', d => connectedNodeIds.has(d.id) ? 1.0 : 0.2);
  }

  function resetHighlights() {
    linkLayer.selectAll('line.link-line')
      .style('stroke-opacity', d => d.is_mst ? 0.85 : Math.min(0.7, Math.abs(d.weight) * 0.8))
      .style('stroke-width', d => d.is_mst ? 2.5 : Math.max(1, Math.abs(d.weight) * 3));

    nodeLayer.selectAll('g.node-group')
      .style('opacity', 1.0);
  }

  // 7. Update Telemetry HUD
  function updateTelemetry(telemetry) {
    if (!telemetry) return;

    // Absorption Ratio
    const ar = telemetry.absorption_ratio_pc1 || 35.0;
    dom.arValue.textContent = `${ar.toFixed(1)}%`;
    dom.arBarFill.style.width = `${Math.min(100, ar)}%`;

    // Dominant Hub & Coherence
    dom.dominantHubVal.textContent = telemetry.dominant_hub || 'BTC';
    dom.coherenceVal.textContent = (telemetry.mean_coherence || 0.3).toFixed(3);

    // Top Sync Pairs
    dom.syncPairsList.innerHTML = (telemetry.top_sync_pairs || []).map(p => `
      <div class="pair-row sync">
        <span class="pair-name">${p.pair}</span>
        <span class="pair-corr">+${(p.corr).toFixed(3)}</span>
      </div>
    `).join('') || '<div class="pair-row"><span class="pair-name">Nenhum par forte</span></div>';

    // Top Hedge Pairs
    dom.hedgePairsList.innerHTML = (telemetry.top_hedge_pairs || []).map(p => `
      <div class="pair-row hedge">
        <span class="pair-name">${p.pair}</span>
        <span class="pair-corr">${(p.corr).toFixed(3)}</span>
      </div>
    `).join('') || '<div class="pair-row"><span class="pair-name">Nenhum par de hedge</span></div>';

    // Dynamic Spectral Insight
    generateSpectralInsight(ar, telemetry.dominant_hub, state.activeBand);
  }

  function generateSpectralInsight(ar, hub, band) {
    let text = "";
    if (band === 'ultra_high') {
      text = `Em frequências de ruído (15m-1h), o mercado opera altamente fragmentado. O ativo ${hub} lidera a conectividade de arbitragem rápida. Cripto e TradFi operam com baixa correlação direta.`;
    } else if (band === 'intraday') {
      text = `Na escala de sessão (4h-8h), choques intradiários de câmbio (USD/BRL) começam a se propagar para índices de ações. ${hub} atua como distribuidor de volatilidade.`;
    } else if (band === 'daily') {
      text = `No horizonte diário (24h), a Razão de Absorção está em ${ar.toFixed(1)}%. ${hub} consolida-se como o nó central do grafo, com pontes robustas de liquidez entre Cripto e Renda Variável Global.`;
    } else {
      text = `Na escala secular (3d-7d), os fatores macroeconômicos dominam. Títulos públicos e moedas alinham o mercado em clusters densos de contágio sistêmico.`;
    }
    dom.spectralInsightText.textContent = text;
  }

  // 8. Event Listeners & UI Controls
  function setupEventListeners() {
    // Equalizer Band Buttons
    document.querySelectorAll('.eq-col').forEach(col => {
      col.addEventListener('click', () => {
        document.querySelectorAll('.eq-col').forEach(c => c.classList.remove('active'));
        col.classList.add('active');
        state.activeBand = col.getAttribute('data-band');
        updateView();
      });
    });

    // Timeline Slider
    dom.timelineSlider.addEventListener('input', (e) => {
      const idx = parseInt(e.target.value, 10);
      setEpochByIndex(idx);
    });

    // Timeline Ticks
    dom.timelineTicks.querySelectorAll('.tick').forEach(tick => {
      tick.addEventListener('click', () => {
        const idx = parseInt(tick.getAttribute('data-idx'), 10);
        dom.timelineSlider.value = idx;
        setEpochByIndex(idx);
      });
    });

    // Timeline Play / Pause
    dom.playTimelineBtn.addEventListener('click', toggleTimelinePlayback);

    // Correlation Threshold Slider
    dom.thresholdSlider.addEventListener('input', (e) => {
      state.corrThreshold = parseFloat(e.target.value);
      dom.thresholdVal.textContent = `≥ ${state.corrThreshold.toFixed(2)}`;
      updateView();
    });

    // MST Toggle
    dom.mstOnlyToggle.addEventListener('change', (e) => {
      state.mstOnly = e.target.checked;
      updateView();
    });

    // Reset View Button
    dom.resetViewBtn.addEventListener('click', () => {
      svg.transition().duration(600).call(zoomBehavior.transform, d3.zoomIdentity);
      state.selectedNodeId = null;
      dom.nodeTooltip.classList.add('hidden');
      resetHighlights();
    });

    // Toggle Physics Button
    dom.togglePhysicsBtn.addEventListener('click', () => {
      state.isPhysicsFrozen = !state.isPhysicsFrozen;
      dom.togglePhysicsBtn.textContent = state.isPhysicsFrozen ? '🔥 Soltar' : '❄️ Fixar';
      if (state.isPhysicsFrozen) {
        simulation.stop();
      } else {
        simulation.alpha(0.3).restart();
      }
    });

    // Audio Toggle Button
    dom.audioToggleBtn.addEventListener('click', toggleAudio);
  }

  function setEpochByIndex(idx) {
    state.activeEpoch = epochKeys[idx];
    dom.epochBadge.textContent = epochNames[state.activeEpoch];
    
    dom.timelineTicks.querySelectorAll('.tick').forEach(t => {
      t.classList.toggle('active', parseInt(t.getAttribute('data-idx'), 10) === idx);
    });

    updateView();
  }

  function toggleTimelinePlayback() {
    state.isPlayingTimeline = !state.isPlayingTimeline;
    if (state.isPlayingTimeline) {
      dom.playIcon.textContent = '⏸';
      dom.playText.textContent = 'PAUSE';
      dom.playTimelineBtn.classList.add('playing');
      
      let curIdx = parseInt(dom.timelineSlider.value, 10);
      state.timelineInterval = setInterval(() => {
        curIdx = (curIdx + 1) % epochKeys.length;
        // Skip ALL when playing loop for pure chronological experience if preferred, or include it
        dom.timelineSlider.value = curIdx;
        setEpochByIndex(curIdx);
      }, 1800);
    } else {
      clearInterval(state.timelineInterval);
      dom.playIcon.textContent = '▶';
      dom.playText.textContent = 'PLAY';
      dom.playTimelineBtn.classList.remove('playing');
    }
  }

  // 9. Web Audio API Ambient Synthesizer
  function toggleAudio() {
    state.isAudioMuted = !state.isAudioMuted;
    if (!state.isAudioMuted) {
      dom.audioToggleBtn.classList.add('hud-btn-primary');
      dom.audioToggleBtn.querySelector('.audio-icon').textContent = '🔊';
      dom.audioToggleBtn.querySelector('.btn-text').textContent = 'ÁUDIO ATIVO';
      initAudioSynthesizer();
    } else {
      dom.audioToggleBtn.classList.remove('hud-btn-primary');
      dom.audioToggleBtn.querySelector('.audio-icon').textContent = '🔇';
      dom.audioToggleBtn.querySelector('.btn-text').textContent = 'ÁUDIO MUTADO';
      if (state.audioCtx) {
        state.audioCtx.suspend();
      }
    }
  }

  function initAudioSynthesizer() {
    if (!state.audioCtx) {
      const AudioCtxClass = window.AudioContext || window.webkitAudioContext;
      state.audioCtx = new AudioCtxClass();
      
      // Master Gain
      const masterGain = state.audioCtx.createGain();
      masterGain.gain.setValueAtTime(0.12, state.audioCtx.currentTime);

      // Lowpass Biquad Filter (Simulating Spectral Resonator)
      const filter = state.audioCtx.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.setValueAtTime(450, state.audioCtx.currentTime);
      filter.Q.setValueAtTime(3.5, state.audioCtx.currentTime);

      // 3 Harmonic Drone Oscillators (C minor Chord: C3=130.81Hz, G3=196.00Hz, Eb4=311.13Hz)
      const baseFreqs = [130.81, 196.00, 311.13];
      const oscs = baseFreqs.map(f => {
        const osc = state.audioCtx.createOscillator();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(f, state.audioCtx.currentTime);
        osc.connect(filter);
        osc.start();
        return osc;
      });

      filter.connect(masterGain);
      masterGain.connect(state.audioCtx.destination);

      state.audioNodes = { masterGain, filter, oscs, baseFreqs };
    } else {
      state.audioCtx.resume();
    }
  }

  function updateAudioDrone(telemetry) {
    if (!state.audioNodes || !state.audioCtx) return;
    
    const ar = (telemetry && telemetry.absorption_ratio_pc1) ? telemetry.absorption_ratio_pc1 : 35;
    // Map AR (20% to 60%) to filter cutoff (200Hz to 1200Hz)
    const targetFreq = 250 + (ar * 15);
    state.audioNodes.filter.frequency.setTargetAtTime(targetFreq, state.audioCtx.currentTime, 0.5);

    // Detune based on band
    const bandPitchShift = {
      'ultra_high': 20,
      'intraday': 10,
      'daily': 0,
      'macro': -15
    }[state.activeBand] || 0;

    state.audioNodes.oscs.forEach((osc, i) => {
      osc.frequency.setTargetAtTime(state.audioNodes.baseFreqs[i] + bandPitchShift, state.audioCtx.currentTime, 0.4);
    });
  }

  // 10. Fallback data generator if JSON cannot be loaded
  function generateFallbackData() {
    return {
      metadata: { total_assets: 6 },
      data: {
        '2026-ALL': {
          'daily': {
            nodes: [
              { id: 'BTC', name: 'Bitcoin', category: 'crypto', color: '#F59E0B', betweenness: 0.04, degree: 4, volatility: 0.32, cum_return: 14.5, size: 24 },
              { id: 'ETH', name: 'Ethereum', category: 'crypto', color: '#F59E0B', betweenness: 0.03, degree: 4, volatility: 0.38, cum_return: 8.2, size: 22 },
              { id: 'SP500', name: 'S&P 500', category: 'tradfi', color: '#06B6D4', betweenness: 0.06, degree: 5, volatility: 0.16, cum_return: 12.1, size: 28 },
              { id: 'IBOV', name: 'Ibovespa', category: 'tradfi', color: '#06B6D4', betweenness: 0.03, degree: 3, volatility: 0.21, cum_return: 5.4, size: 20 },
              { id: 'USD/BRL', name: 'Dólar Spot', category: 'fx', color: '#10B981', betweenness: 0.05, degree: 4, volatility: 0.14, cum_return: -3.2, size: 26 },
              { id: 'US10Y', name: 'Treasury 10Y', category: 'macro', color: '#EC4899', betweenness: 0.02, degree: 2, volatility: 0.18, cum_return: 1.8, size: 18 }
            ],
            edges: [
              { source: 'BTC', target: 'ETH', weight: 0.88, distance: 0.48, is_mst: true, type: 'sync' },
              { source: 'SP500', target: 'IBOV', weight: 0.65, distance: 0.83, is_mst: true, type: 'sync' },
              { source: 'SP500', target: 'BTC', weight: 0.42, distance: 1.07, is_mst: true, type: 'sync' },
              { source: 'USD/BRL', target: 'IBOV', weight: -0.71, distance: 1.84, is_mst: true, type: 'hedge' },
              { source: 'USD/BRL', target: 'US10Y', weight: 0.54, distance: 0.95, is_mst: true, type: 'sync' }
            ],
            telemetry: {
              absorption_ratio_pc1: 38.4,
              mean_coherence: 0.35,
              dominant_hub: 'SP500',
              top_sync_pairs: [{ pair: 'BTC / ETH', corr: 0.88 }, { pair: 'SP500 / IBOV', corr: 0.65 }],
              top_hedge_pairs: [{ pair: 'USD/BRL / IBOV', corr: -0.71 }]
            }
          }
        }
      }
    };
  }

  // Launch application
  document.addEventListener('DOMContentLoaded', init);
})();

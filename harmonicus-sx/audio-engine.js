/**
 * ==============================================================================
 * HARMONICUS SX // WEB AUDIO API SYNTHESIS ENGINE
 * High-Fidelity Physics & Market Signal Sonification Engine
 * ==============================================================================
 */

class HarmonicusAudioEngine {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.analyser = null;
    this.filterNode = null;
    this.reverbNode = null;
    this.isPlaying = false;
    this.volume = 0.5;

    // Synth state
    this.activeDrones = [];
    this.activeChord = 'unison';
    this.currentBand = 'daily';
    this.damping = 0.5;
    this.fourierTension = 20.98;
    this.morletEnergy = -0.59;

    // Frequencies (Equal Temperament A4 = 440Hz)
    this.scale = {
      C2: 65.41,
      A2: 110.00,
      C3: 130.81,
      D3: 146.83,
      E3: 164.81,
      Fs3: 185.00,
      G3: 196.00,
      A3: 220.00,
      B3: 246.94,
      C4: 261.63,
      D4: 293.66,
      E4: 329.63,
      G4: 392.00
    };
  }

  init() {
    if (this.ctx) return;
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    this.ctx = new AudioContext();

    // Master Gain & Limiter/Compressor
    this.compressor = this.ctx.createDynamicsCompressor();
    this.compressor.threshold.setValueAtTime(-18, this.ctx.currentTime);
    this.compressor.knee.setValueAtTime(12, this.ctx.currentTime);
    this.compressor.ratio.setValueAtTime(8, this.ctx.currentTime);
    this.compressor.attack.setValueAtTime(0.003, this.ctx.currentTime);
    this.compressor.release.setValueAtTime(0.25, this.ctx.currentTime);

    this.masterGain = this.ctx.createGain();
    this.masterGain.gain.setValueAtTime(this.volume, this.ctx.currentTime);

    // Resonant Low-Pass Filter (Afinação Aberta e Musical sem Distorção de Q)
    this.filterNode = this.ctx.createBiquadFilter();
    this.filterNode.type = 'lowpass';
    this.filterNode.frequency.setValueAtTime(3200, this.ctx.currentTime);
    this.filterNode.Q.setValueAtTime(0.707, this.ctx.currentTime);

    // Analyser Node for 60fps CRT Oscilloscope
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.smoothingTimeConstant = 0.85;

    // Convolution Reverb (Synthesized Impulse Response)
    this.reverbNode = this.createSyntheticReverb(2.5, 1.8);

    // Signal Chain: Oscillators -> Filter -> Compressor -> MasterGain -> Analyser -> Destination
    this.filterNode.connect(this.compressor);
    this.compressor.connect(this.masterGain);
    this.masterGain.connect(this.analyser);
    this.analyser.connect(this.ctx.destination);
  }

  createSyntheticReverb(seconds, decay) {
    const rate = this.ctx.sampleRate;
    const length = rate * seconds;
    const impulse = this.ctx.createBuffer(2, length, rate);
    const left = impulse.getChannelData(0);
    const right = impulse.getChannelData(1);

    for (let i = 0; i < length; i++) {
      const n = (Math.random() * 2 - 1) * Math.pow(1 - i / length, decay);
      left[i] = n;
      right[i] = n * 0.9;
    }

    const convolver = this.ctx.createConvolver();
    convolver.buffer = impulse;
    return convolver;
  }

  toggleAudio() {
    if (!this.ctx) this.init();

    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }

    if (this.isPlaying) {
      this.stop();
      return false;
    } else {
      this.start();
      return true;
    }
  }

  setVolume(v) {
    this.volume = Math.max(0, Math.min(1, v));
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setTargetAtTime(this.volume, this.ctx.currentTime, 0.05);
    }
  }

  start() {
    if (!this.ctx) this.init();
    this.isPlaying = true;
  }

  stop() {
    this.isPlaying = false;
    this.stopDrones();
    this.stopPolyphonicDrone();
  }

  stopDrones() {
    this.activeDrones.forEach(d => {
      try {
        d.gain.gain.setTargetAtTime(0.0001, this.ctx.currentTime, 0.1);
        setTimeout(() => {
          d.osc.stop();
          d.osc.disconnect();
        }, 150);
      } catch (e) {}
    });
    this.activeDrones = [];
  }

  // Toca nota individual limpa (sem batimentos de desafinação)
  playNodeTone(freqHz, assetName) {
    if (!this.ctx) this.init();
    if (this.ctx.state === 'suspended') this.ctx.resume();

    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = 'triangle';
    osc.frequency.setValueAtTime(freqHz || 220, this.ctx.currentTime);
    osc.detune.setValueAtTime(0, this.ctx.currentTime); // Afinação precisa 0 cents

    gain.gain.setValueAtTime(0.0001, this.ctx.currentTime);
    gain.gain.linearRampToValueAtTime(0.28, this.ctx.currentTime + 0.03);
    gain.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + 0.90);

    osc.connect(gain);
    gain.connect(this.filterNode);
    osc.start();
    osc.stop(this.ctx.currentTime + 0.95);
  }

  // Toca o acorde exato formado pelos nós presentes na banca (Slots 1 a 4)
  playBankChord(nodesList) {
    if (!this.ctx) this.init();
    if (this.ctx.state === 'suspended') this.ctx.resume();
    if (!nodesList || nodesList.length === 0) return;

    const count = Math.min(4, nodesList.length);
    const baseAmp = 0.28 / Math.sqrt(count);

    nodesList.slice(0, 4).forEach((node, i) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = node.id === 'VIX_Index' ? 'sawtooth' : 'triangle';
      osc.frequency.setValueAtTime(node.fundamental_hz || 220, this.ctx.currentTime);
      osc.detune.setValueAtTime(0, this.ctx.currentTime); // Afinação pura sem desafinação

      gain.gain.setValueAtTime(0.0001, this.ctx.currentTime);
      gain.gain.linearRampToValueAtTime(baseAmp, this.ctx.currentTime + 0.04);
      gain.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + 1.20);

      osc.connect(gain);
      gain.connect(this.filterNode);
      osc.start();
      osc.stop(this.ctx.currentTime + 1.25);
    });
  }

  // ============================================================================
  // SÍNTESE POLIFÔNICA CONTÍNUA (DRONE DE ATÉ 4 VOZES / TÉTRADES DE HILBERT)
  // ============================================================================
  startPolyphonicDrone(nodesList) {
    if (!this.ctx) this.init();
    if (this.ctx.state === 'suspended') this.ctx.resume();

    this.stopPolyphonicDrone();
    if (!nodesList || nodesList.length === 0) return;

    this.isPolyDroneActive = true;
    const count = Math.min(4, nodesList.length);
    const baseAmp = 0.25 / Math.sqrt(count);

    if (!this.polyDroneVoices) this.polyDroneVoices = [];

    nodesList.slice(0, 4).forEach((node, idx) => {
      const freq = node.fundamental_hz || 220;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.type = node.id === 'VIX_Index' ? 'sawtooth' : 'triangle';
      osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
      osc.detune.setValueAtTime(0, this.ctx.currentTime); // Afinação matemática pura (sem batimentos)

      gain.gain.setValueAtTime(0.0001, this.ctx.currentTime);
      gain.gain.linearRampToValueAtTime(baseAmp, this.ctx.currentTime + 0.25);

      osc.connect(gain);
      gain.connect(this.filterNode);
      osc.start();

      this.polyDroneVoices.push({ osc, gain, node });
    });
  }

  stopPolyphonicDrone() {
    this.isPolyDroneActive = false;
    if (this.polyDroneVoices && this.polyDroneVoices.length > 0) {
      this.polyDroneVoices.forEach(v => {
        try {
          v.gain.gain.setTargetAtTime(0.0001, this.ctx.currentTime, 0.08);
          setTimeout(() => {
            v.osc.stop();
            v.osc.disconnect();
          }, 120);
        } catch (e) {}
      });
      this.polyDroneVoices = [];
    }
  }

  togglePolyphonicDrone(nodesList) {
    if (this.isPolyDroneActive) {
      this.stopPolyphonicDrone();
      return false;
    } else {
      this.startPolyphonicDrone(nodesList);
      return true;
    }
  }

  // ============================================================================
  // SEQUENCIADOR MELÓDICO (ARPEGGIO PASSO-A-PASSO NOTA POR NOTA)
  // ============================================================================
  playMelodicArpeggio(nodesList, onStepCallback, onDoneCallback) {
    if (!this.ctx) this.init();
    if (this.ctx.state === 'suspended') this.ctx.resume();

    if (!nodesList || nodesList.length === 0) {
      if (onDoneCallback) onDoneCallback();
      return;
    }

    const wasDroneActive = this.isPolyDroneActive;
    if (wasDroneActive) this.stopPolyphonicDrone();

    this.isArpeggioPlaying = true;
    const stepDurationMs = 450;
    const totalSteps = nodesList.length;

    nodesList.forEach((node, stepIdx) => {
      setTimeout(() => {
        if (!this.isArpeggioPlaying) return;

        if (onStepCallback) onStepCallback(node, stepIdx);

        const freq = node.fundamental_hz || 220;
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();

        osc.type = node.id === 'VIX_Index' ? 'sawtooth' : 'triangle';
        osc.frequency.setValueAtTime(freq, this.ctx.currentTime);
        osc.detune.setValueAtTime(0, this.ctx.currentTime); // Afinação precisa 0 cents

        gain.gain.setValueAtTime(0.0001, this.ctx.currentTime);
        gain.gain.linearRampToValueAtTime(0.30, this.ctx.currentTime + 0.03);
        gain.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + 0.40);

        osc.connect(gain);
        gain.connect(this.filterNode);
        osc.start();
        osc.stop(this.ctx.currentTime + 0.42);

      }, stepIdx * stepDurationMs);
    });

    setTimeout(() => {
      this.isArpeggioPlaying = false;
      if (onDoneCallback) onDoneCallback();
      if (wasDroneActive) this.startPolyphonicDrone(nodesList);
    }, totalSteps * stepDurationMs + 100);
  }

  // Atualiza parâmetros de física (Langevin, Fourier, Morlet)
  updatePhysicsParams(damping, fourier, morlet) {
    this.damping = damping;
    this.fourierTension = fourier;
    this.morletEnergy = morlet;

    if (this.filterNode && this.ctx) {
      // Damping controla o fator de qualidade Q (ressonância de pico)
      const qVal = Math.max(0.5, Math.min(8.0, 1.0 / (damping + 0.1)));
      this.filterNode.Q.setTargetAtTime(qVal, this.ctx.currentTime, 0.1);
    }
  }

  // Dados para o Osciloscópio de 60fps
  getWaveformData() {
    if (!this.analyser) return new Uint8Array(512).fill(128);
    const dataArray = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteTimeDomainData(dataArray);
    return dataArray;
  }
}

// Instância global única
window.harmonicusAudio = new HarmonicusAudioEngine();

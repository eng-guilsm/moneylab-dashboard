/**
 * ==============================================================================
 * HARMONICUS SX // GATEKEEPER LOCK PROTOCOL (v1.0)
 * Autenticação Cyberpunk por PIN Mestre (1727) com Trava de 3 Tentativas / 12 Horas
 * ==============================================================================
 */

(function() {
  const MASTER_PIN = "1727";
  const MAX_ATTEMPTS = 3;
  const LOCKOUT_MS = 12 * 60 * 60 * 1000; // 12 Horas

  let enteredPin = "";
  let lockInterval = null;

  document.addEventListener('DOMContentLoaded', () => {
    buildLockOverlay();
    checkAuthState();
  });

  function buildLockOverlay() {
    if (document.getElementById('gatekeeperLockOverlay')) return;

    const overlay = document.createElement('div');
    overlay.id = 'gatekeeperLockOverlay';
    overlay.className = 'gk-lock-overlay';
    overlay.innerHTML = `
      <div class="gk-lock-box">
        <div class="gk-lock-header">
          <div class="gk-shield-pulse">🛡️</div>
          <h2 class="gk-title">GATEKEEPER SECURITY PROTOCOL</h2>
          <p class="gk-subtitle">TERMINAL QUANTITATIVO PRIVADO // NÍVEL 4</p>
        </div>

        <div class="gk-pin-display" id="gkPinDisplay">
          <div class="pin-dot" id="dot0"></div>
          <div class="pin-dot" id="dot1"></div>
          <div class="pin-dot" id="dot2"></div>
          <div class="pin-dot" id="dot3"></div>
        </div>

        <div class="gk-status-msg" id="gkStatusMsg">
          Insira o PIN de 4 dígitos para autorizar a custódia.
        </div>

        <div class="gk-lockout-timer" id="gkLockoutTimer" style="display: none;">
          <span class="timer-label">ACESSO SUSPENSO POR 12H:</span>
          <span class="timer-countdown" id="gkCountdownVal">12:00:00</span>
        </div>

        <div class="gk-numpad" id="gkNumpad">
          <button class="gk-key" data-k="1">1</button>
          <button class="gk-key" data-k="2">2</button>
          <button class="gk-key" data-k="3">3</button>
          <button class="gk-key" data-k="4">4</button>
          <button class="gk-key" data-k="5">5</button>
          <button class="gk-key" data-k="6">6</button>
          <button class="gk-key" data-k="7">7</button>
          <button class="gk-key" data-k="8">8</button>
          <button class="gk-key" data-k="9">9</button>
          <button class="gk-key gk-key-action" id="gkKeyClear">⌫</button>
          <button class="gk-key" data-k="0">0</button>
          <button class="gk-key gk-key-action gk-key-enter" id="gkKeyEnter">↵</button>
        </div>

        <div class="gk-lock-footer">
          <span>SESSÃO CRIPTOGRAFADA // AUTO-PURGE EM CASO DE FORÇA BRUTA</span>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    // Eventos do Numpad
    overlay.querySelectorAll('.gk-key[data-k]').forEach(btn => {
      btn.addEventListener('click', () => {
        handleDigit(btn.getAttribute('data-k'));
      });
    });

    document.getElementById('gkKeyClear').addEventListener('click', () => {
      handleBackspace();
    });

    document.getElementById('gkKeyEnter').addEventListener('click', () => {
      validatePin();
    });

    // Teclado físico
    window.addEventListener('keydown', (e) => {
      if (isLockedOut() || isAuthed()) return;
      if (e.key >= '0' && e.key <= '9') {
        handleDigit(e.key);
      } else if (e.key === 'Backspace') {
        handleBackspace();
      } else if (e.key === 'Enter') {
        validatePin();
      }
    });
  }

  function handleDigit(d) {
    if (isLockedOut()) return;
    if (enteredPin.length < 4) {
      enteredPin += d;
      updateDots();
      if (enteredPin.length === 4) {
        setTimeout(validatePin, 200);
      }
    }
  }

  function handleBackspace() {
    if (enteredPin.length > 0) {
      enteredPin = enteredPin.slice(0, -1);
      updateDots();
    }
  }

  function updateDots() {
    for (let i = 0; i < 4; i++) {
      const dot = document.getElementById(`dot${i}`);
      if (dot) {
        if (i < enteredPin.length) dot.classList.add('filled');
        else dot.classList.remove('filled');
      }
    }
  }

  function validatePin() {
    if (isLockedOut()) return;
    if (enteredPin.length !== 4) return;

    if (enteredPin === MASTER_PIN) {
      // Sucesso
      sessionStorage.setItem('gk_auth', '1');
      localStorage.removeItem('gk_attempts');
      localStorage.removeItem('gk_lock_until');
      showSuccessFeedback();
    } else {
      // Falha
      let attempts = parseInt(localStorage.getItem('gk_attempts') || '0', 10) + 1;
      localStorage.setItem('gk_attempts', attempts);
      enteredPin = "";
      updateDots();

      const msgEl = document.getElementById('gkStatusMsg');
      const box = document.querySelector('.gk-lock-box');
      if (box) {
        box.classList.add('shake');
        setTimeout(() => box.classList.remove('shake'), 500);
      }

      if (attempts >= MAX_ATTEMPTS) {
        const lockUntil = Date.now() + LOCKOUT_MS;
        localStorage.setItem('gk_lock_until', lockUntil);
        applyLockout(lockUntil);
      } else {
        const restam = MAX_ATTEMPTS - attempts;
        if (msgEl) {
          msgEl.innerHTML = `<span style="color: #EF4444; font-weight: bold;">❌ PIN INCORRETO.</span> Resta${restam === 1 ? ' apenas' : 'm'} <b>${restam}</b> tentativa${restam === 1 ? '' : 's'} antes da trava de 12h.`;
        }
      }
    }
  }

  function showSuccessFeedback() {
    const msgEl = document.getElementById('gkStatusMsg');
    if (msgEl) {
      msgEl.innerHTML = `<span style="color: #10B981; font-weight: bold;">✅ IDENTIDADE CONFIRMADA. DESBLOQUEANDO TERMINAL...</span>`;
    }
    const overlay = document.getElementById('gatekeeperLockOverlay');
    if (overlay) {
      overlay.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
      overlay.style.opacity = '0';
      overlay.style.transform = 'scale(1.05)';
      setTimeout(() => {
        overlay.style.display = 'none';
        unblurApp();
      }, 600);
    }
  }

  function checkAuthState() {
    const lockUntil = parseInt(localStorage.getItem('gk_lock_until') || '0', 10);
    if (lockUntil > Date.now()) {
      applyLockout(lockUntil);
      blurApp();
      return;
    } else if (lockUntil > 0 && lockUntil <= Date.now()) {
      // Expirou o lockout
      localStorage.removeItem('gk_lock_until');
      localStorage.removeItem('gk_attempts');
    }

    if (sessionStorage.getItem('gk_auth') === '1') {
      // Já autenticado na sessão
      const overlay = document.getElementById('gatekeeperLockOverlay');
      if (overlay) overlay.style.display = 'none';
      unblurApp();
    } else {
      blurApp();
    }
  }

  function applyLockout(lockUntil) {
    const numpad = document.getElementById('gkNumpad');
    const timerBox = document.getElementById('gkLockoutTimer');
    const msgEl = document.getElementById('gkStatusMsg');
    const countdownEl = document.getElementById('gkCountdownVal');

    if (numpad) numpad.style.opacity = '0.2';
    if (numpad) numpad.style.pointerEvents = 'none';
    if (timerBox) timerBox.style.display = 'block';
    if (msgEl) {
      msgEl.innerHTML = `<span style="color: #EF4444; font-weight: 700;">🚨 LIMITE EXCEDIDO (3/3). COCKPIT TRAVADO POR 12 HORAS.</span>`;
    }

    if (lockInterval) clearInterval(lockInterval);

    function tick() {
      const remain = lockUntil - Date.now();
      if (remain <= 0) {
        clearInterval(lockInterval);
        localStorage.removeItem('gk_lock_until');
        localStorage.removeItem('gk_attempts');
        if (numpad) {
          numpad.style.opacity = '1';
          numpad.style.pointerEvents = 'auto';
        }
        if (timerBox) timerBox.style.display = 'none';
        if (msgEl) msgEl.textContent = 'Trava expirada. Digite o PIN de 4 dígitos.';
        return;
      }

      const h = Math.floor(remain / (1000 * 60 * 60));
      const m = Math.floor((remain % (1000 * 60 * 60)) / (1000 * 60));
      const s = Math.floor((remain % (1000 * 60)) / 1000);
      if (countdownEl) {
        countdownEl.textContent = `${pad(h)}:${pad(m)}:${pad(s)}`;
      }
    }

    tick();
    lockInterval = setInterval(tick, 1000);
  }

  function pad(n) {
    return n < 10 ? '0' + n : n;
  }

  function isLockedOut() {
    const lockUntil = parseInt(localStorage.getItem('gk_lock_until') || '0', 10);
    return lockUntil > Date.now();
  }

  function isAuthed() {
    return sessionStorage.getItem('gk_auth') === '1';
  }

  function blurApp() {
    const app = document.querySelector('.app-container');
    if (app) {
      app.style.filter = 'blur(16px)';
      app.style.pointerEvents = 'none';
      app.style.userSelect = 'none';
    }
  }

  function unblurApp() {
    const app = document.querySelector('.app-container');
    if (app) {
      app.style.filter = 'none';
      app.style.pointerEvents = 'auto';
      app.style.userSelect = 'auto';
    }
  }

  // Exportar função para relock voluntário
  window.gatekeeperLockNow = function() {
    sessionStorage.removeItem('gk_auth');
    enteredPin = "";
    updateDots();
    const overlay = document.getElementById('gatekeeperLockOverlay');
    if (overlay) {
      overlay.style.display = 'flex';
      overlay.style.opacity = '1';
      overlay.style.transform = 'scale(1)';
    }
    blurApp();
  };
})();


/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║           CINEMATIC INTRO ENGINE — NANDA CYSEC              ║
 * ║   Hollywood sci-fi film opening sequence for the portfolio  ║
 * ╚══════════════════════════════════════════════════════════════╝
 */

(function () {
  'use strict';

  // ─── State ───────────────────────────────────────────────────────────────
  let animFrame = null;
  let isSkipped = false;
  let W, H;
  const CI = document.getElementById('ci-root');
  const canvas = document.getElementById('ci-canvas');
  const ctx = canvas.getContext('2d');

  // ─── Helpers ─────────────────────────────────────────────────────────────
  const $ = id => document.getElementById(id);
  const delay = ms => new Promise(r => setTimeout(r, ms));
  const lerp = (a, b, t) => a + (b - a) * t;
  const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

  function resize() {
    W = canvas.width = window.innerWidth;
    H = canvas.height = window.innerHeight;
  }
  resize();
  window.addEventListener('resize', resize);

  // ─── Particle System ─────────────────────────────────────────────────────
  const particles = [];
  const PCOUNT = window.innerWidth < 768 ? 60 : 120;

  function spawnParticle(opts = {}) {
    return {
      x: opts.x ?? Math.random() * W,
      y: opts.y ?? Math.random() * H,
      vx: opts.vx ?? (Math.random() - 0.5) * 0.4,
      vy: opts.vy ?? (Math.random() - 0.5) * 0.4,
      size: opts.size ?? Math.random() * 1.4 + 0.3,
      alpha: opts.alpha ?? 0,
      targetAlpha: opts.targetAlpha ?? Math.random() * 0.6 + 0.1,
      color: opts.color ?? (Math.random() < 0.12 ? '#ff2244' : '#ffffff'),
      life: opts.life ?? 1,
      fadeIn: opts.fadeIn ?? true,
      explode: false,
      explodeVx: 0,
      explodeVy: 0,
    };
  }

  for (let i = 0; i < PCOUNT; i++) {
    particles.push(spawnParticle({ targetAlpha: Math.random() * 0.4 + 0.05 }));
  }

  // Grid lines
  const gridLines = [];
  for (let i = 0; i < 10; i++) {
    gridLines.push({ x: Math.random() * W, y: 0, alpha: 0, speed: Math.random() * 0.3 + 0.1, horizontal: Math.random() > 0.5 });
  }

  // ─── State machine ───────────────────────────────────────────────────────
  let phase = 'particles'; // particles → story → boot → flash → hero → done
  let phaseProgress = 0;
  let globalTime = 0;
  let glitchActive = false;
  let glitchTimer = 0;
  let scanlineOpacity = 0;
  let barsProgress = 0; // 1 = full bars, 0 = gone
  let heroAlpha = 0;
  let particlesFadeOut = false;
  let explodeParticles = false;
  let flashAlpha = 0;
  let flashDir = 0; // 1 = fade in, -1 = fade out
  let bootProgress = 0; // 0–100
  let gridAlpha = 0;

  // ─── Canvas Draw Loop ────────────────────────────────────────────────────
  function drawFrame() {
    if (document.hidden) { animFrame = requestAnimationFrame(drawFrame); return; }
    animFrame = requestAnimationFrame(drawFrame);
    globalTime += 0.016;
    ctx.clearRect(0, 0, W, H);

    // Background
    ctx.fillStyle = '#000000';
    ctx.fillRect(0, 0, W, H);

    // Scanlines
    if (scanlineOpacity > 0) {
      ctx.save();
      ctx.globalAlpha = scanlineOpacity * 0.18;
      for (let y = 0; y < H; y += 3) {
        ctx.fillStyle = '#000000';
        ctx.fillRect(0, y, W, 1);
      }
      ctx.restore();
    }

    // Grid
    if (gridAlpha > 0) {
      ctx.save();
      ctx.globalAlpha = gridAlpha * 0.08;
      ctx.strokeStyle = '#ff2244';
      ctx.lineWidth = 0.5;
      const gs = 60;
      for (let x = 0; x < W; x += gs) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke();
      }
      for (let y = 0; y < H; y += gs) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
      }
      ctx.restore();
    }

    // Particles
    particles.forEach(p => {
      if (explodeParticles) {
        p.x += p.explodeVx;
        p.y += p.explodeVy;
        p.explodeVx *= 0.96;
        p.explodeVy *= 0.96;
        p.alpha *= 0.97;
      } else {
        p.x += p.vx;
        p.y += p.vy;
        if (particlesFadeOut) {
          p.alpha = lerp(p.alpha, 0, 0.03);
        } else {
          p.alpha = lerp(p.alpha, p.targetAlpha, 0.02);
        }
        if (p.x < 0) p.x = W; if (p.x > W) p.x = 0;
        if (p.y < 0) p.y = H; if (p.y > H) p.y = 0;
      }
      if (p.alpha <= 0.003) return;
      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
      // Glow for red
      if (p.color === '#ff2244') {
        ctx.shadowColor = '#ff2244';
        ctx.shadowBlur = 8;
        ctx.fill();
      }
      ctx.restore();
    });

    // Glitch effect
    if (glitchActive && glitchTimer > 0) {
      glitchTimer -= 0.016;
      if (Math.random() < 0.6) {
        const slices = Math.floor(Math.random() * 4) + 2;
        for (let i = 0; i < slices; i++) {
          const sy = Math.random() * H;
          const sh = Math.random() * 20 + 2;
          const offset = (Math.random() - 0.5) * 30;
          ctx.save();
          ctx.globalAlpha = Math.random() * 0.5;
          ctx.drawImage(canvas, 0, sy, W, sh, offset, sy, W, sh);
          ctx.restore();
        }
        // Red channel shift
        ctx.save();
        ctx.globalAlpha = 0.08;
        ctx.fillStyle = '#ff0000';
        ctx.fillRect(Math.random() * 20 - 10, Math.random() * H, W, Math.random() * 4);
        ctx.restore();
      }
      if (glitchTimer <= 0) glitchActive = false;
    }

    // Cinematic bars
    if (barsProgress > 0) {
      const barH = H * 0.085 * barsProgress;
      ctx.save();
      ctx.fillStyle = '#000000';
      ctx.fillRect(0, 0, W, barH);
      ctx.fillRect(0, H - barH, W, barH);
      ctx.restore();
    }

    // White flash
    if (flashAlpha > 0) {
      ctx.save();
      ctx.globalAlpha = flashAlpha;
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }
  }

  animFrame = requestAnimationFrame(drawFrame);

  // ─── UI helpers ──────────────────────────────────────────────────────────
  function showEl(id, displayType = 'flex') {
    const el = $(id);
    if (el) { el.style.display = displayType; el.style.opacity = '0'; }
  }
  function fadeIn(id, dur = 1200) {
    return new Promise(r => {
      const el = $(id);
      if (!el) { r(); return; }
      el.style.display = el.style.display === 'none' || !el.style.display ? 'flex' : el.style.display;
      el.style.transition = `opacity ${dur}ms ease`;
      requestAnimationFrame(() => {
        requestAnimationFrame(() => { el.style.opacity = '1'; setTimeout(r, dur); });
      });
    });
  }
  function fadeOut(id, dur = 800) {
    return new Promise(r => {
      const el = $(id);
      if (!el) { r(); return; }
      el.style.transition = `opacity ${dur}ms ease`;
      el.style.opacity = '0';
      setTimeout(r, dur);
    });
  }
  function setHTML(id, html) { const el = $(id); if (el) el.innerHTML = html; }
  function setText(id, txt) { const el = $(id); if (el) el.textContent = txt; }

  // ─── Trigger glitch ──────────────────────────────────────────────────────
  function triggerGlitch(duration = 0.4) {
    glitchActive = true;
    glitchTimer = duration;
  }

  // ─── Boot sequence typing ─────────────────────────────────────────────────
  async function typeBootLine(el, text, speed = 28) {
    if (isSkipped) { el.textContent = text; return; }
    el.textContent = '';
    for (let i = 0; i <= text.length; i++) {
      if (isSkipped) { el.textContent = text; return; }
      el.textContent = text.slice(0, i);
      await delay(speed);
    }
  }

  async function animateProgressBar(from, to, dur) {
    if (isSkipped) {
      setText('ci-bar-fill-pct', to + '%');
      $('ci-bar-fill').style.width = to + '%';
      return;
    }
    const start = performance.now();
    return new Promise(r => {
      function tick(now) {
        if (isSkipped) {
          setText('ci-bar-fill-pct', to + '%');
          $('ci-bar-fill').style.width = to + '%';
          r(); return;
        }
        const t = clamp((now - start) / dur, 0, 1);
        const ease = 1 - Math.pow(1 - t, 3);
        const val = Math.round(from + (to - from) * ease);
        setText('ci-bar-fill-pct', val + '%');
        $('ci-bar-fill').style.width = val + '%';
        if (t < 1) requestAnimationFrame(tick);
        else r();
      }
      requestAnimationFrame(tick);
    });
  }

  // ─── Phase: Story ─────────────────────────────────────────────────────────
  async function phaseStory() {
    const lines = [
      'Every line of code tells a story.',
      'Every project leaves a legacy.',
      'This is mine.'
    ];
    const story = $('ci-story');
    const storyLine = $('ci-story-line');
    story.style.display = 'flex';
    await delay(600);

    for (let i = 0; i < lines.length; i++) {
      if (isSkipped) break;
      storyLine.style.transition = 'opacity 1.2s ease';
      storyLine.style.opacity = '0';
      await delay(300);
      storyLine.textContent = lines[i];
      storyLine.style.opacity = '1';
      await delay(lines[i].length < 20 ? 2200 : 2600);
      if (isSkipped) break;
      storyLine.style.opacity = '0';
      await delay(1000);
    }
    story.style.opacity = '0';
    story.style.transition = 'opacity 0.8s ease';
    await delay(900);
    story.style.display = 'none';
  }

  // ─── Phase: Boot ─────────────────────────────────────────────────────────
  async function phaseBoot() {
    scanlineOpacity = 1;
    gridAlpha = 1;
    triggerGlitch(0.5);

    const boot = $('ci-boot');
    boot.style.display = 'flex';
    boot.style.opacity = '0';
    boot.style.transition = 'opacity 0.6s ease';
    await delay(100);
    boot.style.opacity = '1';
    await delay(500);

    const lines = [
      { id: 'ci-bl-0', label: 'INITIALIZING CORE SYSTEMS', status: 'OK', color: '#00ff88', pct: [0, 15] },
      { id: 'ci-bl-1', label: 'BOOTING SYSTEM', status: 'OK', color: '#00ff88', pct: [15, 30] },
      { id: 'ci-bl-2', label: 'LOADING MEMORIES', status: 'OK', color: '#00ff88', pct: [30, 50] },
      { id: 'ci-bl-3', label: 'LOADING PROJECTS', status: 'OK', color: '#ff2244', pct: [50, 68], glitch: true },
      { id: 'ci-bl-4', label: 'LOADING EXPERIENCE', status: 'OK', color: '#00ff88', pct: [68, 85] },
      { id: 'ci-bl-5', label: 'VERIFYING IDENTITY', status: 'OK', color: '#00ff88', pct: [85, 98] },
      { id: 'ci-bl-6', label: 'ACCESS GRANTED', status: '✓', color: '#ff2244', pct: [98, 100], glitch: true, big: true },
    ];

    for (const line of lines) {
      if (isSkipped) break;
      const el = $(line.id);
      if (!el) continue;
      el.style.display = 'flex';
      el.style.opacity = '0';
      el.style.transition = 'opacity 0.3s ease';
      await delay(50);
      el.style.opacity = '1';

      const textEl = el.querySelector('.ci-bl-text');
      const statEl = el.querySelector('.ci-bl-stat');
      if (textEl) await typeBootLine(textEl, line.label, line.big ? 40 : 22);
      if (statEl) {
        statEl.textContent = '...';
        await delay(180);
        statEl.textContent = `[ ${line.status} ]`;
        statEl.style.color = line.color;
      }

      if (line.glitch) triggerGlitch(0.35);
      await animateProgressBar(line.pct[0], line.pct[1], line.big ? 600 : 350);
      await delay(line.big ? 400 : 120);
    }

    await delay(500);
  }

  // ─── Phase: Flash & Explode ───────────────────────────────────────────────
  async function phaseFlash() {
    triggerGlitch(0.8);
    await delay(300);

    // Fade boot UI out
    $('ci-boot').style.transition = 'opacity 0.4s ease';
    $('ci-boot').style.opacity = '0';

    // Flash
    flashDir = 1;
    let t = 0;
    await new Promise(r => {
      function fadein() {
        t += 0.05;
        flashAlpha = clamp(t, 0, 1);
        if (t < 1) requestAnimationFrame(fadein);
        else r();
      }
      fadein();
    });

    // Explode particles
    explodeParticles = true;
    particles.forEach(p => {
      const angle = Math.atan2(p.y - H / 2, p.x - W / 2);
      const speed = Math.random() * 12 + 4;
      p.explodeVx = Math.cos(angle) * speed;
      p.explodeVy = Math.sin(angle) * speed;
      p.alpha = Math.random() * 0.8 + 0.2;
    });

    // Spawn burst particles
    for (let i = 0; i < 80; i++) {
      const angle = (i / 80) * Math.PI * 2;
      const speed = Math.random() * 15 + 5;
      particles.push(spawnParticle({
        x: W / 2, y: H / 2,
        vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
        explodeVx: Math.cos(angle) * speed,
        explodeVy: Math.sin(angle) * speed,
        size: Math.random() * 2.5 + 0.5,
        alpha: 1,
        color: Math.random() < 0.4 ? '#ff2244' : '#ffffff',
        targetAlpha: 0,
      }));
      particles[particles.length - 1].explode = true;
    }

    await delay(120);

    // Flash out
    t = 1;
    await new Promise(r => {
      function fadeout() {
        t -= 0.06;
        flashAlpha = clamp(t, 0, 1);
        if (t > 0) requestAnimationFrame(fadeout);
        else { flashAlpha = 0; r(); }
      }
      fadeout();
    });

    // Remove bars (letterbox goes away)
    let barT = 1;
    await new Promise(r => {
      function shrinkBars() {
        barT -= 0.04;
        barsProgress = clamp(barT, 0, 1);
        if (barT > 0) requestAnimationFrame(shrinkBars);
        else { barsProgress = 0; r(); }
      }
      shrinkBars();
    });

    scanlineOpacity = 0;
    gridAlpha = 0;
  }

  // ─── Phase: Hero Reveal ───────────────────────────────────────────────────
  async function phaseHero() {
    const hero = $('ci-hero');
    hero.style.display = 'flex';
    hero.style.opacity = '0';

    // Staggered reveal
    const els = hero.querySelectorAll('[data-delay]');
    hero.style.transition = 'opacity 0.01s';
    hero.style.opacity = '1';

    for (const el of els) {
      const d = parseInt(el.dataset.delay) || 0;
      await delay(d);
      el.style.transition = 'opacity 1.4s ease, transform 1.2s cubic-bezier(0.16,1,0.3,1)';
      el.style.opacity = '1';
      el.style.transform = 'translateY(0)';
    }

    await delay(1800);
  }

  // ─── Phase: Exit ─────────────────────────────────────────────────────────
  async function phaseExit() {
    particlesFadeOut = true;

    CI.style.transition = 'opacity 1.2s ease';
    CI.style.opacity = '0';
    await delay(1200);
    CI.style.display = 'none';

    document.body.style.overflow = '';
    document.body.classList.remove('ci-active');

    const nav = document.getElementById('nav');
    if (nav) { nav.classList.add('show'); }

    // Stop loop
    cancelAnimationFrame(animFrame);
  }

  // ─── Skip Handler ─────────────────────────────────────────────────────────
  function skipAll() {
    if (isSkipped) return;
    isSkipped = true;
    cancelAnimationFrame(animFrame);
    barsProgress = 0;
    flashAlpha = 0;
    scanlineOpacity = 0;
    gridAlpha = 0;
    CI.style.transition = 'opacity 0.6s ease';
    CI.style.opacity = '0';
    setTimeout(() => {
      CI.style.display = 'none';
      document.body.style.overflow = '';
      document.body.classList.remove('ci-active');
      const nav = document.getElementById('nav');
      if (nav) nav.classList.add('show');
    }, 650);
  }

  window.ciSkip = skipAll;
  document.addEventListener('keydown', e => { if (e.key === 'Escape' || e.key === 'Enter') skipAll(); });

  // ─── Master Sequence ──────────────────────────────────────────────────────
  async function masterSequence() {
    document.body.style.overflow = 'hidden';

    // Let particles fade in
    barsProgress = 1;
    await delay(1200);

    // Story phase
    await phaseStory();
    if (isSkipped) return;

    await delay(400);

    // Boot phase
    await phaseBoot();
    if (isSkipped) return;

    // Flash & explode
    await phaseFlash();
    if (isSkipped) return;

    // Hero reveal
    await phaseHero();
    if (isSkipped) return;

    // Exit
    await phaseExit();
  }

  // Start
  setTimeout(masterSequence, 300);

})();

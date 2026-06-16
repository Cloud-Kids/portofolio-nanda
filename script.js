// Load Three.js for 3D background
(function () {
  const script = document.createElement('script');
  script.src = 'https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js';
  script.onload = function () {
    initVideoBackground();
    initPlexusBackground();
  };
  document.head.appendChild(script);

  function initVideoBackground() {
    if (!window.THREE) return;

    // Create canvas
    const canvas = document.createElement('canvas');
    canvas.id = 'video-bg-canvas';
    document.body.insertBefore(canvas, document.body.firstChild);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 100);
    const renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1)); // Optimized for low-end

    function resize() {
      renderer.setSize(window.innerWidth, window.innerHeight);
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener('resize', resize);

    camera.position.z = 12;
    camera.position.y = 2;
    camera.lookAt(0, 0, 0);

    // Liquid Metal Plane
    const geometry = new THREE.PlaneGeometry(50, 40, 20, 15); // Optimized geometry for low-end devices
    const material = new THREE.MeshStandardMaterial({
      color: 0x2a2a2a,
      roughness: 0.1,
      metalness: 0.9,
      flatShading: false,
    });

    const plane = new THREE.Mesh(geometry, material);
    plane.rotation.x = -Math.PI / 2.2; // Tilted back
    plane.position.y = -3;
    plane.position.z = -5;
    scene.add(plane);

    // Lighting for dramatic cyber liquid reflections
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.9);
    scene.add(ambientLight);

    const light1 = new THREE.DirectionalLight(0xffffff, 4.0); // Bright white
    light1.position.set(10, 15, 5);
    scene.add(light1);

    const light2 = new THREE.DirectionalLight(0xa1a1aa, 3.5); // Silver
    light2.position.set(-10, 10, 2);
    scene.add(light2);

    const mouseLight = new THREE.PointLight(0xffffff, 1.5, 20);
    scene.add(mouseLight);

    // Wave physics setup
    const clock = new THREE.Clock();
    const vertices = geometry.attributes.position.array;

    // Interaction
    let mouseX = 0, mouseY = 0;
    let targetScrollY = window.scrollY;
    let currentScrollY = window.scrollY;

    document.addEventListener('mousemove', (e) => {
      mouseX = (e.clientX / window.innerWidth) * 2 - 1;
      mouseY = -(e.clientY / window.innerHeight) * 2 + 1;
    });
    window.addEventListener('scroll', () => { targetScrollY = window.scrollY; });

    function animate() {
      requestAnimationFrame(animate);
      if (document.hidden) return; // Prevent background rendering
      const time = clock.getElapsedTime() * 0.5;
      currentScrollY += (targetScrollY - currentScrollY) * 0.05;

      // Fluid Wave mathematical animation
      for (let i = 0; i < vertices.length; i += 3) {
        const x = vertices[i];
        const y = vertices[i + 1];

        // Combining overlapping sine/cosine waves for organic ripples
        const wave1 = Math.sin(x * 0.2 + time) * 1.2;
        const wave2 = Math.cos(y * 0.25 - time * 0.8) * 1.2;
        const wave3 = Math.sin((x + y) * 0.15 + time * 1.2) * 0.8;

        vertices[i + 2] = wave1 + wave2 + wave3;
      }
      geometry.attributes.position.needsUpdate = true;
      geometry.computeVertexNormals();

      // Mouse point light follows cursor to create a glowing reflection
      mouseLight.position.x += (mouseX * 15 - mouseLight.position.x) * 0.05;
      mouseLight.position.y += (mouseY * 10 + 2 - mouseLight.position.y) * 0.05;
      mouseLight.position.z = 4;

      // Subtle Camera parallax
      camera.position.x += (mouseX * 1 - camera.position.x) * 0.05;
      camera.position.y = 2 + currentScrollY * -0.002;
      camera.lookAt(0, -2, -5);

      renderer.render(scene, camera);
    }
    animate();
  }

  function initPlexusBackground() {
    const hero = document.getElementById('hero');
    if (!hero || !window.THREE) return;

    const canvas = document.createElement('canvas');
    canvas.id = 'plexus-canvas';
    hero.insertBefore(canvas, hero.firstChild);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(60, hero.offsetWidth / hero.offsetHeight, 0.1, 100);
    const renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1)); // Optimized for low-end

    function resize() {
      renderer.setSize(hero.offsetWidth, hero.offsetHeight);
      camera.aspect = hero.offsetWidth / hero.offsetHeight;
      camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener('resize', resize);

    camera.position.z = 10;

    // Plexus particles
    const particleCount = 70; // Optimized particle count
    const positions = new Float32Array(particleCount * 3);
    const velocities = [];
    const particleGeometry = new THREE.BufferGeometry();

    for (let i = 0; i < particleCount * 3; i += 3) {
      positions[i] = (Math.random() - 0.5) * 30;     // x
      positions[i + 1] = (Math.random() - 0.5) * 20; // y
      positions[i + 2] = (Math.random() - 0.5) * 15; // z

      velocities.push({
        x: (Math.random() - 0.5) * 0.03,
        y: (Math.random() - 0.5) * 0.03,
        z: (Math.random() - 0.5) * 0.03
      });
    }

    particleGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    const particleMaterial = new THREE.PointsMaterial({
      color: 0xffffff,
      size: 0.12,
      transparent: true,
      opacity: 0.9,
      blending: THREE.AdditiveBlending
    });

    const particles = new THREE.Points(particleGeometry, particleMaterial);
    scene.add(particles);

    // Plexus Lines
    const lineMaterial = new THREE.LineBasicMaterial({
      color: 0xa1a1aa,
      transparent: true,
      opacity: 0.15,
      blending: THREE.AdditiveBlending
    });

    const lineGeometry = new THREE.BufferGeometry();
    const maxLines = particleCount * particleCount / 2;
    const linePositions = new Float32Array(maxLines * 6);
    lineGeometry.setAttribute('position', new THREE.BufferAttribute(linePositions, 3));
    lineGeometry.setDrawRange(0, 0);

    const lines = new THREE.LineSegments(lineGeometry, lineMaterial);
    scene.add(lines);

    let mouseX = 0, mouseY = 0;
    document.addEventListener('mousemove', (e) => {
      const rect = hero.getBoundingClientRect();
      if (e.clientY < rect.bottom) {
        mouseX = (e.clientX / window.innerWidth) * 2 - 1;
        mouseY = -(e.clientY / window.innerHeight) * 2 + 1;
      }
    });

    function animate() {
      requestAnimationFrame(animate);
      if (document.hidden) return; // Prevent background rendering

      const posAttr = particles.geometry.attributes.position.array;

      // Move particles
      for (let i = 0; i < particleCount; i++) {
        posAttr[i * 3] += velocities[i].x;
        posAttr[i * 3 + 1] += velocities[i].y;
        posAttr[i * 3 + 2] += velocities[i].z;

        // Bounce
        if (Math.abs(posAttr[i * 3]) > 15) velocities[i].x *= -1;
        if (Math.abs(posAttr[i * 3 + 1]) > 10) velocities[i].y *= -1;
        if (Math.abs(posAttr[i * 3 + 2]) > 8) velocities[i].z *= -1;
      }
      particles.geometry.attributes.position.needsUpdate = true;

      // Interactive connecting lines
      let vertexCount = 0;
      for (let i = 0; i < particleCount; i++) {
        for (let j = i + 1; j < particleCount; j++) {
          const dx = posAttr[i * 3] - posAttr[j * 3];
          const dy = posAttr[i * 3 + 1] - posAttr[j * 3 + 1];
          const dz = posAttr[i * 3 + 2] - posAttr[j * 3 + 2];
          const distSq = dx * dx + dy * dy + dz * dz;

          if (distSq < 10) {
            linePositions[vertexCount++] = posAttr[i * 3];
            linePositions[vertexCount++] = posAttr[i * 3 + 1];
            linePositions[vertexCount++] = posAttr[i * 3 + 2];
            linePositions[vertexCount++] = posAttr[j * 3];
            linePositions[vertexCount++] = posAttr[j * 3 + 1];
            linePositions[vertexCount++] = posAttr[j * 3 + 2];
          }
        }
      }
      lineGeometry.setDrawRange(0, vertexCount / 3);
      lineGeometry.attributes.position.needsUpdate = true;

      // Camera Parallax & Rotation
      particles.rotation.y += 0.0005;
      lines.rotation.y += 0.0005;
      particles.rotation.x += 0.0002;
      lines.rotation.x += 0.0002;

      camera.position.x += (mouseX * 3 - camera.position.x) * 0.05;
      camera.position.y += (mouseY * 3 - camera.position.y) * 0.05;
      camera.lookAt(scene.position);

      renderer.render(scene, camera);
    }
    animate();
  }
})();

// ═══ Old terminal intro removed — cinematic-intro.js handles this now

// ═══ CURSOR ══════════════════════════════════════════════
(function () {
  const dot = document.getElementById('cursorDot'), ring = document.getElementById('cursorRing');
  let mx = 0, my = 0, rx = 0, ry = 0;
  document.addEventListener('mousemove', e => {
    mx = e.clientX; my = e.clientY;
    dot.style.left = mx - 4 + 'px'; dot.style.top = my - 4 + 'px';
  });
  function anim() { 
    if (!document.hidden) {
      rx += (mx - rx - 20) * 0.1; ry += (my - ry - 20) * 0.1; ring.style.left = rx + 'px'; ring.style.top = ry + 'px'; 
    }
    requestAnimationFrame(anim); 
  }
  anim();
  document.querySelectorAll('a,button,.proj-card,.why-card,.process-card,.testi-card,.stat-box,.tag,.hero-arrow,.social-icon,.back-to-top').forEach(el => {
    el.addEventListener('mouseenter', () => { dot.style.transform = 'scale(2.5)'; ring.style.width = '56px'; ring.style.height = '56px'; ring.style.borderColor = 'rgba(255,255,255,0.6)'; });
    el.addEventListener('mouseleave', () => { dot.style.transform = 'scale(1)'; ring.style.width = '40px'; ring.style.height = '40px'; ring.style.borderColor = 'rgba(255,255,255,0.35)'; });
  });
})();

// ═══ SCROLL REVEAL & DYNAMIC ANIMATIONS ═══════════════════════════════════════
const observer = new IntersectionObserver(entries => {
  entries.forEach((e, i) => {
    if (e.isIntersecting) {
      setTimeout(() => {
        e.target.classList.add('visible');

        // Add extra dynamic animations based on element type
        if (e.target.classList.contains('proj-card')) {
          e.target.style.transform = 'translateY(0) scale(1)';
          e.target.style.opacity = '1';
        } else if (e.target.classList.contains('process-card') || e.target.classList.contains('why-card')) {
          e.target.style.transform = 'translateY(0)';
          e.target.style.opacity = '1';
        } else if (e.target.classList.contains('testi-card')) {
          e.target.style.transform = 'translateX(0)';
          e.target.style.opacity = '1';
        }
      }, i * 120); // slightly increased stagger delay for better effect
      observer.unobserve(e.target);
    }
  });
}, { threshold: 0.15 });

// Prepare initial states for extra dynamic animations
document.querySelectorAll('.proj-card, .process-card, .why-card, .testi-card').forEach(el => {
  el.classList.add('reveal');
  if (el.classList.contains('proj-card')) {
    el.style.transform = 'translateY(40px) scale(0.95)';
  } else if (el.classList.contains('process-card') || el.classList.contains('why-card')) {
    el.style.transform = 'translateY(30px)';
  } else if (el.classList.contains('testi-card')) {
    el.style.transform = 'translateX(30px)';
  }
  el.style.opacity = '0';
  el.style.transition = 'all 0.8s cubic-bezier(0.16, 1, 0.3, 1)';
});

document.querySelectorAll('.reveal').forEach(el => observer.observe(el));

// ═══ ANIMATED COUNTERS ═══════════════════════════════════
const statObserver = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.querySelectorAll('.num[data-target]').forEach(el => {
        const target = parseFloat(el.dataset.target);
        const isDecimal = el.dataset.decimal === 'true';
        let current = 0; const dur = 1500; const start = performance.now();
        function tick(now) {
          const p = Math.min((now - start) / dur, 1);
          const eased = 1 - Math.pow(1 - p, 3);
          current = eased * target;
          el.textContent = isDecimal ? current.toFixed(1) : (Math.round(current) + (el.dataset.target >= 100 ? 'k+' : '+'));
          if (p < 1) requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);
      });
      statObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.3 });
document.querySelectorAll('.stats-row').forEach(el => statObserver.observe(el));

// ═══ BACK TO TOP ═════════════════════════════════════════
const btt = document.getElementById('btt');
window.addEventListener('scroll', () => { btt.classList.toggle('show', window.scrollY > 600); });

// ═══ MAGNETIC BUTTONS ═════════════════════════════════════
document.querySelectorAll('.btn, .nav-links a, .social-icon, .arrow-link, .proj-arrow, .hero-arrow').forEach(btn => {
  btn.addEventListener('mousemove', (e) => {
    const rect = btn.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width / 2;
    const y = e.clientY - rect.top - rect.height / 2;
    btn.style.transform = `translate(${x * 0.3}px, ${y * 0.3}px)`;
  });
  btn.addEventListener('mouseleave', () => {
    btn.style.transform = '';
  });
});

// ═══ SMOOTH SCROLL (LENIS) ════════════════════════════════
(function () {
  const lenisScript = document.createElement('script');
  lenisScript.src = 'https://unpkg.com/@studio-freight/lenis@1.0.34/dist/lenis.min.js';
  lenisScript.onload = function () {
    const lenis = new Lenis({
      duration: 1.2,
      easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
      direction: 'vertical',
      gestureDirection: 'vertical',
      smooth: true,
      smoothTouch: false,
      touchMultiplier: 2
    });

    function raf(time) {
      if (!document.hidden) lenis.raf(time);
      requestAnimationFrame(raf);
    }
    requestAnimationFrame(raf);

    // Update our anchor links to use lenis
    document.querySelectorAll('a[href^="#"]').forEach(a => {
      a.addEventListener('click', e => {
        e.preventDefault();
        const target = document.querySelector(a.getAttribute('href'));
        if (target) lenis.scrollTo(target);
      });
    });

    // Update back to top
    const btt = document.getElementById('btt');
    if (btt) {
      btt.onclick = () => lenis.scrollTo(0);
    }
  };
  document.head.appendChild(lenisScript);
})();

// ═══ SPACE BACKGROUND ANIMATION (HERO ONLY) ════════════════════
(function () {
  // Only animate when hero is in view
  const hero = document.getElementById('hero');
  if (!hero) return;

  // Create canvas
  const canvas = document.createElement('canvas');
  canvas.id = 'space-canvas';
  canvas.style.position = 'absolute';
  canvas.style.inset = '0';
  canvas.style.width = '100%';
  canvas.style.height = '100%';
  canvas.style.zIndex = '0';
  canvas.style.pointerEvents = 'none';
  hero.insertBefore(canvas, hero.firstChild);

  const ctx = canvas.getContext('2d');
  let W, H, mx = -9999, my = -9999;

  function resize() { W = canvas.width = canvas.offsetWidth; H = canvas.height = canvas.offsetHeight; }
  resize();
  window.addEventListener('resize', resize);
  document.addEventListener('mousemove', e => { mx = e.clientX; my = e.clientY; });

  // Stars
  const stars = [];
  for (let i = 0; i < 40; i++) { // Optimized star count
    stars.push({
      x: Math.random() * W,
      y: Math.random() * H,
      size: Math.random() * 1.5 + 0.3,
      speed: Math.random() * 0.2 + 0.05,
      opacity: Math.random() * 0.8 + 0.2,
      twinkle: Math.random() * 0.02 + 0.01
    });
  }

  // Meteors
  const meteors = [];
  function spawnMeteor() {
    if (meteors.length > 2) return;
    meteors.push({
      x: Math.random() * W + 100,
      y: -30,
      size: Math.random() * 2 + 1,
      speed: Math.random() * 3 + 2,
      tailLength: Math.random() * 50 + 30,
      alpha: 1
    });
  }
  setInterval(spawnMeteor, 4000);

  // Particles
  const particles = [];
  for (let i = 0; i < 15; i++) { // Optimized particle count
    particles.push({
      x: Math.random() * W,
      y: Math.random() * H,
      size: Math.random() * 2 + 0.5,
      vx: (Math.random() - 0.5) * 0.3,
      vy: (Math.random() - 0.5) * 0.3,
      opacity: Math.random() * 0.4 + 0.15
    });
  }

  function draw() {
    requestAnimationFrame(draw);
    if (document.hidden) return; // Prevent background rendering
    ctx.clearRect(0, 0, W, H);

    // Stars
    stars.forEach(star => {
      ctx.beginPath();
      ctx.arc(star.x, star.y, star.size, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(255,255,255,${star.opacity})`;
      ctx.fill();
      star.opacity += Math.random() * star.twinkle - star.twinkle * 0.5;
      star.opacity = Math.max(0.1, Math.min(0.9, star.opacity));
      star.y += star.speed;
      if (star.y > H) star.y = 0;
    });

    // Meteors
    meteors.forEach((meteor, i) => {
      if (meteor.alpha <= 0) { meteors.splice(i, 1); return; }
      ctx.beginPath();
      ctx.arc(meteor.x, meteor.y, meteor.size, 0, Math.PI * 2);
      const grad = ctx.createRadialGradient(meteor.x, meteor.y, 0, meteor.x, meteor.y, meteor.size * 3);
      grad.addColorStop(0, `rgba(255,255,255,${meteor.alpha})`);
      grad.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = grad;
      ctx.fill();
      const tailX = meteor.x - 40;
      const tailY = meteor.y + 40;
      ctx.beginPath();
      ctx.moveTo(meteor.x, meteor.y);
      ctx.lineTo(tailX, tailY);
      ctx.strokeStyle = `rgba(255,255,255,${meteor.alpha * 0.4})`;
      ctx.lineWidth = meteor.size * 2;
      ctx.lineCap = 'round';
      ctx.stroke();
      meteor.x -= meteor.speed;
      meteor.y += meteor.speed;
      meteor.alpha -= 0.006;
    });

    // Particles
    particles.forEach(p => {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(255,255,255,${p.opacity})`;
      ctx.fill();
      particles.forEach(p2 => {
        const dx = p.x - p2.x, dy = p.y - p2.y, dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 90) {
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.strokeStyle = `rgba(255,255,255,${0.12 * (1 - dist / 90)})`;
          ctx.lineWidth = 0.4;
          ctx.stroke();
        }
      });
      p.x += p.vx; p.y += p.vy;
      if (p.x < 0) p.x = W; if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H; if (p.y > H) p.y = 0;
    });

  }

  draw();
})();

// ═══ NAV BACKGROUND ON SCROLL ════════════════════════════
const nav = document.getElementById('nav');
window.addEventListener('scroll', () => {
  nav.style.background = window.scrollY > 100 ? 'rgba(6,6,8,0.95)' : 'rgba(12,12,16,0.8)';
});

// ═══ 3D TILT + GLOW ══════════════════════════════════════
(function () {
  const TILT_SELECTORS = [
    '.proj-card', '.process-card', '.why-card',
    '.testi-card', '.stat-box', '.float-card',
    '.hero-proj-card'
  ];
  const MAX_TILT = 18; // Enhanced tilt degrees

  function addGlowLayer(el) {
    // Avoid double-inserting
    if (el.querySelector('.tilt-glow')) return;
    const glow = document.createElement('div');
    glow.className = 'tilt-glow';
    el.appendChild(glow);
  }

  function applyTilt(el, e) {
    const rect = el.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const dx = (e.clientX - cx) / (rect.width / 2);   // -1 to 1
    const dy = (e.clientY - cy) / (rect.height / 2);  // -1 to 1

    const rotX = -dy * MAX_TILT;
    const rotY = dx * MAX_TILT;

    // Mouse position as % for glow gradient
    const mx = ((e.clientX - rect.left) / rect.width * 100).toFixed(1) + '%';
    const my = ((e.clientY - rect.top) / rect.height * 100).toFixed(1) + '%';

    el.style.transform = `perspective(1000px) rotateX(${rotX}deg) rotateY(${rotY}deg) scale3d(1.04,1.04,1.04) translateZ(10px)`;
    el.style.setProperty('--mx', mx);
    el.style.setProperty('--my', my);

    // Add inner content lift
    const inner = el.querySelector('.proj-card-inner, .proj-label, h3, .process-card h3, .why-card h3, .testi-info');
    if (inner) {
      inner.style.transform = `translateZ(${Math.abs(rotX) * 1.5}px)`;
    }
  }

  function resetTilt(el) {
    el.style.transform = '';
    const inner = el.querySelector('.proj-card-inner, .proj-label, h3, .process-card h3, .why-card h3, .testi-info');
    if (inner) {
      inner.style.transform = '';
    }
  }

  function initCard(el) {
    el.classList.add('tilt-card');
    addGlowLayer(el);

    el.addEventListener('mousemove', e => applyTilt(el, e));
    el.addEventListener('mouseleave', () => resetTilt(el));
  }

  // Init immediately available cards
  TILT_SELECTORS.forEach(sel => {
    document.querySelectorAll(sel).forEach(initCard);
  });

  // Also re-run after intro exits (cards may be hidden until then)
  const origSkip = window.skipIntro;
  if (typeof origSkip === 'function') {
    window.skipIntro = function () {
      origSkip();
      setTimeout(() => {
        TILT_SELECTORS.forEach(sel => {
          document.querySelectorAll(sel).forEach(initCard);
        });
      }, 1000);
    };
  }
})();

// ═══ LANYARD ID CARD PHYSICS ═════════════════════════════
(function () {
  const wrap = document.getElementById('lanyardWrap');
  const canvas = document.getElementById('lanyardCanvas');
  const card = document.getElementById('lanyardCard');
  if (!wrap || !canvas || !card) return;
  const ctx = canvas.getContext('2d');

  let angle = 3;
  let angleVel = 0;
  let target = 0;
  let flipAngle = 0;
  let flipVel = 0;
  let flipTarget = 0;
  let isDragging = false;
  let dragStartX = 0;
  let dragStartAngle = 0;
  let dragStartFlip = 0;
  let idleTime = 0;
  let lastInteract = 0;
  let W = 0, H = 0, pivotX = 0, pivotY = 0, cardH = 0;

  function measure() {
    W = wrap.offsetWidth;
    H = wrap.offsetHeight;
    canvas.width = W;
    canvas.height = H;
    pivotX = W / 2;
    pivotY = 20;
    cardH = card.offsetHeight;
  }

  // Build QR dot pattern
  (function buildQr() {
    const qr = document.getElementById('lcQr');
    if (!qr) return;
    const pat = [1, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1];
    qr.innerHTML = pat.map(b =>
      `<div class="${b ? 'lc-qr-b' : 'lc-qr-w'}"></div>`
    ).join('');
  })();

  wrap.addEventListener('mousemove', e => {
    if (isDragging) return;
    const r = wrap.getBoundingClientRect();
    const dx = (e.clientX - (r.left + r.width / 2)) / (r.width / 2);
    target = dx * 18;
    lastInteract = Date.now();
  });
  wrap.addEventListener('mouseleave', () => { if (!isDragging) target = 0; });

  card.addEventListener('mousedown', e => {
    isDragging = true;
    dragStartX = e.clientX;
    dragStartAngle = angle;
    dragStartFlip = flipAngle;
    lastInteract = Date.now();
    e.preventDefault();
  });
  document.addEventListener('mousemove', e => {
    if (!isDragging) return;
    const dx = e.clientX - dragStartX;
    target = Math.max(-45, Math.min(45, dragStartAngle + dx * 0.15));
    flipTarget = dragStartFlip + dx * 1.5;
    lastInteract = Date.now();
  });
  document.addEventListener('mouseup', () => {
    isDragging = false;
    target = 0;
    flipTarget = Math.round(flipAngle / 180) * 180;
  });

  card.addEventListener('touchstart', e => {
    isDragging = true;
    dragStartX = e.touches[0].clientX;
    dragStartAngle = angle;
    dragStartFlip = flipAngle;
    lastInteract = Date.now();
  }, { passive: true });
  document.addEventListener('touchmove', e => {
    if (!isDragging) return;
    const dx = e.touches[0].clientX - dragStartX;
    target = Math.max(-45, Math.min(45, dragStartAngle + dx * 0.15));
    flipTarget = dragStartFlip + dx * 1.5;
    lastInteract = Date.now();
  }, { passive: true });
  document.addEventListener('touchend', () => {
    isDragging = false;
    target = 0;
    flipTarget = Math.round(flipAngle / 180) * 180;
  });
  window.addEventListener('resize', () => setTimeout(measure, 50));

  function drawFabricStrap(x1, y1, x2, y2) {
    const dist = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2);
    const sag = dist * 0.13 + 5;
    const midX = (x1 + x2) / 2;
    const midY = (y1 + y2) / 2;
    const cpX = midX;
    const cpY = midY + sag;
    const STRAP_W = 10;

    // Deep shadow
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.quadraticCurveTo(cpX + 1, cpY + 4, x2, y2);
    ctx.strokeStyle = 'rgba(0,0,0,0.65)';
    ctx.lineWidth = STRAP_W + 5;
    ctx.lineCap = 'round';
    ctx.stroke();

    // Main navy fabric body
    const g = ctx.createLinearGradient(x1 - 5, midY, x2 + 5, midY);
    g.addColorStop(0, '#3a6db5');
    g.addColorStop(0.2, '#1e4a88');
    g.addColorStop(0.5, '#0f2443');
    g.addColorStop(0.8, '#1e4a88');
    g.addColorStop(1, '#2a5fa8');
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.quadraticCurveTo(cpX, cpY, x2, y2);
    ctx.strokeStyle = g;
    ctx.lineWidth = STRAP_W;
    ctx.lineCap = 'round';
    ctx.stroke();

    // Center dark spine
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.quadraticCurveTo(cpX, cpY, x2, y2);
    ctx.strokeStyle = 'rgba(0,0,0,0.3)';
    ctx.lineWidth = 2.5;
    ctx.stroke();

    // Left edge highlight
    ctx.beginPath();
    ctx.moveTo(x1 - 2, y1);
    ctx.quadraticCurveTo(cpX - 3, cpY - 1, x2 - 2, y2);
    ctx.strokeStyle = 'rgba(120, 180, 255, 0.4)';
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Right subtle highlight
    ctx.beginPath();
    ctx.moveTo(x1 + 2, y1);
    ctx.quadraticCurveTo(cpX + 3, cpY - 1, x2 + 2, y2);
    ctx.strokeStyle = 'rgba(255,255,255,0.08)';
    ctx.lineWidth = 1;
    ctx.stroke();

    // Fabric weave tick marks
    for (let t = 0.08; t < 1.0; t += 0.1) {
      const bx = (1 - t) * (1 - t) * x1 + 2 * (1 - t) * t * cpX + t * t * x2;
      const by = (1 - t) * (1 - t) * y1 + 2 * (1 - t) * t * cpY + t * t * y2;
      const dtx = 2 * (1 - t) * (cpX - x1) + 2 * t * (x2 - cpX);
      const dty = 2 * (1 - t) * (cpY - y1) + 2 * t * (y2 - cpY);
      const len = Math.sqrt(dtx * dtx + dty * dty) || 1;
      const nx = -dty / len * (STRAP_W / 2 - 1.5);
      const ny = dtx / len * (STRAP_W / 2 - 1.5);
      ctx.beginPath();
      ctx.moveTo(bx + nx, by + ny);
      ctx.lineTo(bx - nx, by - ny);
      ctx.strokeStyle = 'rgba(0,0,0,0.15)';
      ctx.lineWidth = 0.8;
      ctx.stroke();
    }
  }

  function drawClip() {
    const ax = pivotX, ay = pivotY;
    const cW = 14, cH = 24;
    const cx = ax - cW / 2, cy = ay - 6;

    // Clip shadow
    ctx.beginPath();
    ctx.roundRect(cx + 1, cy + 2, cW, cH, 2);
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.fill();

    // Clip body gradient
    const cg = ctx.createLinearGradient(cx, cy, cx + cW, cy);
    cg.addColorStop(0, '#3a4f62');
    cg.addColorStop(0.3, '#c8d8ea');
    cg.addColorStop(0.6, '#8c9db5');
    cg.addColorStop(1, '#3a4f62');
    ctx.beginPath();
    ctx.roundRect(cx, cy, cW, cH, 3);
    ctx.fillStyle = cg;
    ctx.fill();

    // Clip inner cutout
    ctx.beginPath();
    ctx.roundRect(cx + 3, cy + 5, cW - 6, cH - 10, 1.5);
    ctx.fillStyle = 'rgba(0,0,0,0.55)';
    ctx.fill();

    // Gate bar
    ctx.beginPath();
    ctx.roundRect(cx + 1, cy + cH - 6, cW - 2, 5, 1.5);
    const gg = ctx.createLinearGradient(cx, 0, cx + cW, 0);
    gg.addColorStop(0, '#546e7a'); gg.addColorStop(0.5, '#b0c4d4'); gg.addColorStop(1, '#546e7a');
    ctx.fillStyle = gg;
    ctx.fill();

    // Top highlight
    ctx.beginPath();
    ctx.roundRect(cx + 2, cy + 1, cW - 4, 2.5, 1);
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.fill();

    // Subtle glow around clip
    const grd = ctx.createRadialGradient(ax, ay + cH / 2, 0, ax, ay + cH / 2, 32);
    grd.addColorStop(0, 'rgba(30,74,136,0.2)');
    grd.addColorStop(1, 'transparent');
    ctx.beginPath();
    ctx.arc(ax, ay + cH / 2, 32, 0, Math.PI * 2);
    ctx.fillStyle = grd;
    ctx.fill();
  }

  function drawRope() {
    ctx.clearRect(0, 0, W, H);
    if (!cardH || !W) return;

    const a = angle * Math.PI / 180;
    const cardTopY = H - cardH - (H * 0.04);
    const swayX = Math.sin(a) * (cardTopY - pivotY) * 0.12;
    const cardTopX = W / 2 + swayX;

    const leftAnchor = { x: pivotX - 16, y: pivotY + 22 };
    const rightAnchor = { x: pivotX + 16, y: pivotY + 22 };
    const cardEnd = { x: cardTopX, y: cardTopY + 6 };

    drawFabricStrap(leftAnchor.x, leftAnchor.y, cardEnd.x - 3, cardEnd.y);
    drawFabricStrap(rightAnchor.x, rightAnchor.y, cardEnd.x + 3, cardEnd.y);
    drawClip();
  }

  function tick() {
    if (!isDragging && Date.now() - lastInteract > 4000) {
      idleTime += 0.007;
      target = Math.sin(idleTime) * 3.5;
      // Optionally add a slow subtle 3D rotation if idle
      // flipTarget = Math.sin(idleTime * 0.5) * 15; // Un-comment if you want idle 3D wobble
    }

    const spring = isDragging ? 0.22 : 0.032;
    const damping = isDragging ? 0.60 : 0.90;

    angleVel += (target - angle) * spring;
    angleVel *= damping;
    angle += angleVel;

    const flipSpring = isDragging ? 0.15 : 0.05;
    const flipDamping = isDragging ? 0.8 : 0.92;
    flipVel += (flipTarget - flipAngle) * flipSpring;
    flipVel *= flipDamping;
    flipAngle += flipVel;

    if (!document.hidden) {
      card.style.transform = `translateX(-50%) rotateZ(${angle}deg) rotateY(${flipAngle}deg)`;
      drawRope();
    }
    requestAnimationFrame(tick);
  }

  requestAnimationFrame(() => { measure(); tick(); });
})();

// ===== BACKGROUND MUSIC =====
let musicStarted = false;
function tryPlayMusic() {
  if (musicStarted) return;
  const music = document.getElementById('bg-music');
  if (music) {
    music.volume = 0.4;
    music.play().then(() => {
      musicStarted = true;
      document.removeEventListener('click', tryPlayMusic);
      document.removeEventListener('keydown', tryPlayMusic);
      document.removeEventListener('touchstart', tryPlayMusic);
    }).catch(err => console.log('Autoplay blocked until interaction:', err));
  }
}

// Automatically try to play on first interaction
document.addEventListener('click', tryPlayMusic);
document.addEventListener('keydown', tryPlayMusic);
document.addEventListener('touchstart', tryPlayMusic);

// Also try immediately (in case browser policy allows it)
setTimeout(tryPlayMusic, 500);

function toggleMusic() {
  const music = document.getElementById('bg-music');
  const toggle = document.getElementById('music-toggle');

  if (music.paused) {
    music.play();
    toggle.classList.remove('muted');
    toggle.textContent = '🎵';
  } else {
    music.pause();
    toggle.classList.add('muted');
    toggle.textContent = '🔇';
  }
}

// ===== VISIBILITY & PERFORMANCE OBSERVATION =====
document.addEventListener("visibilitychange", () => {
  const music = document.getElementById('bg-music');
  if (document.hidden) {
    if (music && !music.paused) {
      music.dataset.wasPlaying = "true";
      music.pause();
    }
  } else {
    if (music && music.dataset.wasPlaying === "true") {
      music.play();
      music.dataset.wasPlaying = "false";
    }
  }
});
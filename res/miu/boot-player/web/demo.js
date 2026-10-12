/* Local visual prototype. This file never runs commands or reads user data. */
(() => {
  'use strict';
  const elements = new Map();
  const $ = (id) => elements.get(id) || (elements.set(id, document.getElementById(id)), elements.get(id));
  const text = (id, value) => { const el = $(id); if (el.textContent !== value) el.textContent = value; };
  const duration = 18;
  const scene = $('experience');
  const panels = [...document.querySelectorAll('[data-enter]')];
  const clamp = (n) => Math.max(0, Math.min(1, n));
  const smooth = (a, b, t) => { const x = clamp((t - a) / (b - a)); return x * x * x * (x * (x * 6 - 15) + 10); };
  let state = 'idle';
  let startedAt = 0;
  let finishedAt = 0;
  let raf = 0;
  let fullPlayback = false;
  let starting = false;
  let lastLogCount = -1;
  let lastRecipeCount = -1;
  let handedOff = false;
  const contexts = {};
  const logoTraces = [...document.querySelectorAll('.logo-trace')];
  const traceStarts = logoTraces.map((el) => .1 + el.getBBox().x / 530 * .3);
  const desktopFurniture = [...document.querySelectorAll('.desktop-top, .desktop-welcome, .desktop-shortcuts, .mock-taskbar')];

  const moduleNames = ['MIU.CORE', 'PET.MOTION', 'CHAT.SURFACE', 'MESSAGE.BUS', 'LIGHT.FIELD', 'SCENE.RENDER'];
  $('modules').innerHTML = moduleNames.map((name) => `<div class="module-row"><span>${name}</span><small>WAIT</small><div class="module-track"><i></i></div></div>`).join('');
  const modules = [...document.querySelectorAll('.module-row')].map(row => ({ row, bar: row.querySelector('i'), label: row.querySelector('small') }));
  const events = [
    [4.3, 'Miu experience sequence created.', 'INIT'],
    [4.7, 'Building the local scene graph.', 'SCENE'],
    [5.1, 'Establishing motion timing.', 'CLOCK'],
    [5.6, 'Pet expression layers assembled.', 'PET'],
    [6.1, 'Luna / Void motion channels staged.', 'PET'],
    [6.7, 'Message surface composed.', 'CHAT'],
    [7.2, 'Typography and panels aligned.', 'UI'],
    [7.8, 'Light envelope shaped to four edges.', 'GLOW'],
    [8.35, 'Breathing curve interpolated.', 'MOTION'],
    [8.9, 'Visual code stream staged.', 'STREAM'],
    [9.5, 'Theme spectrum transition staged.', 'COLOR'],
    [10.05, 'Desktop composition prepared.', 'SCENE'],
    [10.6, 'Message and pet surfaces ready.', 'READY'],
    [11.1, 'All visual layers synchronized.', 'SYNC'],
    [11.6, 'Preparing the final light field.', 'GLOW'],
    [12, 'Experience assembly complete.', 'DONE'],
  ];
  const recipe = [
    '<span class="dim">// Miu visual scene · demo only</span>',
    '<span class="gold">experience</span> {',
    '  brand: <span class="blue">"Miu AI"</span>',
    '  companion: [<span class="blue">Luna, Void</span>]',
    '  motion: <span class="blue">continuous</span>',
    '  messages: <span class="blue">composed</span>',
    '  viewport: <span class="blue">adaptive</span>',
    '  palette: [<span class="blue">accent, glow, ink</span>]',
    '  timing: <span class="blue">monotonic</span>',
    '  easing: <span class="blue">quintic</span>',
    '  layers: {',
    '    backdrop: <span class="gold">0</span>,',
    '    terminal: <span class="gold">1</span>,',
    '    companion: <span class="gold">2</span>,',
    '    glow: <span class="gold">3</span>',
    '  }',
    '  pet: {',
    '    atlas: <span class="blue">staged</span>,',
    '    expressions: <span class="gold">10</span>,',
    '    blending: <span class="blue">continuous</span>,',
    '    idle: <span class="blue">breathe</span>,',
    '    greeting: <span class="blue">queued</span>',
    '  }',
    '  chat: {',
    '    surface: <span class="blue">glass</span>,',
    '    bubbles: <span class="blue">composed</span>,',
    '    typography: <span class="blue">aligned</span>,',
    '    transitions: <span class="blue">soft</span>',
    '  }',
    '  light: {',
    '    edges: <span class="gold">4</span>,',
    '    falloff: <span class="blue">smooth</span>,',
    '    rhythm: <span class="blue">breathe</span>',
    '    spectrum: <span class="blue">themeAccent</span>,',
    '    corners: <span class="blue">seamless</span>,',
    '    envelope: <span class="blue">continuous</span>',
    '  }',
    '  render: {',
    '    sceneGraph: <span class="blue">linked</span>,',
    '    vectorPaths: <span class="blue">resolved</span>,',
    '    contours: <span class="blue">unified</span>,',
    '    waveform: <span class="blue">synchronized</span>,',
    '    orbitTrails: <span class="blue">staged</span>,',
    '    clipping: <span class="blue">viewport</span>,',
    '    composition: <span class="blue">layered</span>',
    '  }',
    '  handoff: {',
    '    title: <span class="blue">"Miu AI"</span>,',
    '    desktop: <span class="blue">simulated</span>,',
    '    background: <span class="blue">transparent</span>,',
    '    edgeLight: <span class="blue">fadeIn</span>,',
    '    continuity: <span class="blue">preserved</span>',
    '  }',
    '  state: <span class="gold">READY</span>',
    '}',
  ];
  // Fictional display text only; never evaluated or sent anywhere.
  const streamLines = [
    'miu.scene.compose(layer, frame);',
    '  let alpha = curve.sample(t);',
    'pet.motion.blend("Luna", pose);',
    '  await renderer.stage(next);',
    'message.surface.layout(view);',
    'glow.edges.map(smoothFalloff);',
    '  return mix(accent, light);',
    'frame.graph.link(source, dst);',
    'shader.uniforms.phase = time;',
    '  vec4 color = field(uv.xy);',
    'miu.typography.align(center);',
    'pet.expression.easeTo(happy);',
    '  scene.layers.commit(frame);',
    'light.envelope.breathe(phase);',
    'render.queue.flush(nextFrame);',
    '// local visual sequence only',
  ];

  function setState(next) {
    state = next;
    document.body.dataset.state = next;
    $('controls').inert = next === 'playing';
    $('boot').inert = next === 'finished';
  }

  function fitCanvas(id) {
    const canvas = $(id);
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    const context = canvas.getContext('2d');
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    contexts[id] = { ctx: context, w: width, h: height };
  }

  function buildGlow() {
    fitCanvas('edgeGlow');
    const { ctx, w, h } = contexts.edgeGlow;
    const depth = Math.min(w, h) * .205;
    ctx.clearRect(0, 0, w, h);
    // Same color + source-over alpha union: no clipped corner or color seam.
    [[0, 0, 0, depth], [0, h, 0, h - depth], [0, 0, depth, 0], [w, 0, w - depth, 0]].forEach(([x1, y1, x2, y2]) => {
      const gradient = ctx.createLinearGradient(x1, y1, x2, y2);
      [[0, 1], [.035, .79], [.1, .57], [.23, .33], [.45, .135], [.7, .033], [1, 0]].forEach(([stop, alpha]) => gradient.addColorStop(stop, `rgba(39,133,255,${alpha})`));
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, w, h);
    });
  }

  function resize() {
    fitCanvas('wave');
    fitCanvas('core');
    fitCanvas('codeStream');
    buildGlow();
    if (state === 'playing') render((performance.now() - startedAt) / 1000);
    else if (state === 'idle') drawLogo(3.25);
  }

  function drawLogo(t) {
    const fill = smooth(1.8, 3.05, t);
    logoTraces.forEach((path, i) => {
      path.style.strokeDashoffset = String(1 - smooth(traceStarts[i], traceStarts[i] + 2.15, t));
    });
    $('logoFill').style.opacity = String(fill);
    $('logoOutline').style.opacity = String(smooth(0, .25, t) * (1 - .8 * fill));
    const sheen = smooth(2.1, 3.6, t);
    $('logoSheen').setAttribute('gradientTransform', `translate(${sheen * 800 - 120} 0) rotate(12)`);
    $('logoHighlight').style.opacity = String(Math.sin(sheen * Math.PI) * .6);
  }

  function drawWave(t) {
    const { ctx, w, h } = contexts.wave;
    ctx.clearRect(0, 0, w, h);
    ctx.strokeStyle = '#276d9833';
    ctx.lineWidth = 1;
    for (let x = 18; x < w; x += w / 10) { ctx.beginPath(); ctx.moveTo(x, 10); ctx.lineTo(x, h - 5); ctx.stroke(); }
    for (let y = 15; y < h; y += h / 4) { ctx.beginPath(); ctx.moveTo(15, y); ctx.lineTo(w - 15, y); ctx.stroke(); }
    for (let layer = 0; layer < 2; layer++) {
      ctx.beginPath();
      for (let x = 14; x < w - 14; x += 2) {
        const n = (x - 14) / (w - 28);
        const envelope = Math.sin(n * Math.PI) ** 1.4;
        const amplitude = (Math.sin(n * 22 - t * 2.5 + layer) * .58 + Math.sin(n * 49 + t * 1.2) * .22) * envelope;
        const y = h * .5 + amplitude * h * (layer ? .18 : .31);
        if (x === 14) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = layer ? '#71e9ff88' : '#73c6ff';
      ctx.lineWidth = layer ? 1 : 1.3;
      ctx.stroke();
    }
    text('phase', ((t * .2) % 1).toFixed(2));
  }

  function drawCore(t) {
    const { ctx, w, h } = contexts.core;
    ctx.clearRect(0, 0, w, h);
    const x = w / 2, y = h / 2, r = Math.min(w * .29, h * .29);
    const reveal = smooth(4.5, 6.5, t);
    ctx.fillStyle = '#348cc342';
    for (let gx = 19; gx < w; gx += 24) for (let gy = 18; gy < h; gy += 24) ctx.fillRect(gx, gy, 1, 1);
    ctx.strokeStyle = '#2687c645'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(18, y); ctx.lineTo(x - r * 1.4, y); ctx.moveTo(x + r * 1.4, y); ctx.lineTo(w - 18, y); ctx.stroke();
    for (let ring = 0; ring < 3; ring++) {
      ctx.beginPath();
      ctx.strokeStyle = ['#3aa1e440', '#67bffaaa', '#8cefff77'][ring];
      const offset = (ring % 2 ? -1 : 1) * t * (.16 + ring * .04);
      ctx.arc(x, y, r * (1 + ring * .21), offset, offset + Math.PI * (1.65 - ring * .12) * reveal);
      ctx.stroke();
    }
    for (let i = 0; i < 48; i++) {
      const angle = i / 48 * Math.PI * 2;
      const inner = r * 1.52, outer = inner + (i % 4 === 0 ? 7 : 3);
      ctx.beginPath(); ctx.moveTo(x + Math.cos(angle) * inner, y + Math.sin(angle) * inner); ctx.lineTo(x + Math.cos(angle) * outer, y + Math.sin(angle) * outer);
      ctx.strokeStyle = i / 48 < smooth(5, 12, t) ? '#8ad9ffe0' : '#3576ae38'; ctx.stroke();
    }
    for (let i = 0; i < 4; i++) {
      const angle = t * .2 + i * Math.PI / 2;
      const nx = x + Math.cos(angle) * r * 1.21, ny = y + Math.sin(angle) * r * 1.21;
      for (let tail = 1; tail <= 12; tail++) {
        const a = angle - tail * .014;
        ctx.beginPath();
        ctx.strokeStyle = `rgba(106,206,255,${(1 - tail / 13) * .36})`;
        ctx.lineWidth = 2;
        ctx.arc(x, y, r * 1.21, a - .014, a);
        ctx.stroke();
      }
      ctx.fillStyle = i === 1 ? '#b8ffff' : '#8dcfff';
      ctx.fillRect(nx - 2, ny - 2, 4, 4);
    }
    ctx.lineWidth = 1;
  }

  function drawCodeStream(t) {
    const { ctx, w, h } = contexts.codeStream;
    ctx.clearRect(0, 0, w, h);
    const elapsed = Math.max(0, Math.min(t, 12.1) - 5.8);
    const travel = elapsed * 32 + 3 * Math.sin(elapsed * 2);
    const head = Math.floor(travel);
    const fontSize = Math.max(8, Math.min(12, w / 35));
    const lineHeight = fontSize * 1.42;
    ctx.font = `400 ${fontSize}px "Miu Mono", monospace`;
    for (let row = 0; row <= Math.ceil(h / lineHeight) + 1; row++) {
      const index = head - row;
      if (index < 0) continue;
      const y = h - 4 - row * lineHeight - (travel - head) * lineHeight;
      const alpha = .3 + .7 * Math.max(0, y / Math.max(h, 1));
      ctx.fillStyle = `rgba(77,147,191,${alpha})`;
      ctx.fillText(String(index + 1).padStart(4, '0'), 10, y);
      ctx.fillStyle = row < 2 ? '#d5f9ff' : index % 4 === 0 ? '#67deda' : `rgba(121,194,243,${alpha})`;
      ctx.fillText(streamLines[index % streamLines.length], 10 + fontSize * 3.3, y);
    }
    text('streamCount', `${String(head).padStart(4, '0')} LINES`);
    text('streamState', t >= 12.1 ? 'COMPLETE' : 'STREAMING');
  }

  function render(t) {
    t = Math.min(t, duration);
    if (state === 'playing' && t >= 12.1 && !handedOff) {
      handedOff = true;
      window.chrome.webview.postMessage('handoff');
    }
    const heroOut = smooth(3.45, 4.6, t);
    $('hero').style.opacity = String(1 - heroOut);
    $('hero').style.transform = `translate(-50%, -50%) scale(${1 - heroOut * .18}) translateY(${-heroOut * 35}px)`;
    if (t < 4.7) drawLogo(t);
    document.querySelector('.hero-kicker').style.opacity = String(smooth(1.75, 2.7, t));
    document.querySelector('.hero-caption').style.opacity = String(smooth(1.8, 3, t));
    document.querySelector('.cursor').style.opacity = String(.2 + .55 * (.5 + .5 * Math.sin(t * 5)));
    const terminalOut = smooth(12.1, 13.45, t);
    $('terminal').style.visibility = t > 3.65 && t < 13.5 ? 'visible' : 'hidden';
    $('terminal').style.opacity = String(smooth(3.65, 4.4, t) * (1 - terminalOut));
    $('terminal').style.transform = `scale(${1 - terminalOut * .055})`;
    for (const panel of panels) {
      const enter = Number(panel.dataset.enter);
      const amount = smooth(enter, enter + 1.05, t);
      panel.style.opacity = String(amount);
      panel.style.transform = `translate3d(0, ${(1 - amount) * 16}px, 0) scale(${.985 + .015 * amount})`;
    }
    const assembly = smooth(4.3, 12.1, t);
    text('timecode', (Math.floor(Math.max(0, t - 4) * 20) / 20).toFixed(2).padStart(5, '0'));
    $('progress').style.transform = `scaleX(${assembly})`;
    text('percent', `${Math.floor(assembly * 100)}%`);
    modules.forEach(({ row, bar, label }, i) => {
      const amount = smooth(4.6 + i * .67, 7.4 + i * .82, t);
      bar.style.transform = `scaleX(${amount})`;
      const status = amount >= 1 ? 'READY' : amount > 0 ? `${Math.floor(amount * 100)}%` : 'WAIT';
      if (label.textContent !== status) label.textContent = status;
      row.classList.toggle('complete', amount >= 1);
    });
    const logCount = events.filter(([at]) => at <= t).length;
    if (logCount !== lastLogCount) {
      $('logs').innerHTML = events.slice(0, logCount).slice(-5).map(([at, text, tag]) => `<div class="log"><time>${(at - 4).toFixed(3)}</time><span>${text}</span><b>${tag}</b></div>`).join('');
      $('logCount').textContent = `${String(logCount).padStart(2, '0')} ENTRIES`;
      lastLogCount = logCount;
    }
    const recipeProgress = Math.max(0, Math.min(recipe.length, (t - 5) * 8));
    const recipeCount = Math.ceil(recipeProgress);
    if (recipeCount !== lastRecipeCount) {
      $('recipe').innerHTML = recipe.slice(0, recipeCount).map((line, i) => `<div><i>${String(i + 1).padStart(2, '0')}</i><span>${line}</span></div>`).join('');
      lastRecipeCount = recipeCount;
    }
    if (recipeCount > 0) {
      const row = $('recipe').lastElementChild;
      row.style.opacity = String(smooth(0, .35, recipeProgress - recipeCount + 1));
      $('recipe').scrollTop = Math.max(0, recipeProgress * row.offsetHeight + 16 - $('recipe').clientHeight);
    } else $('recipe').scrollTop = 0;
    text('coreState', t < 11.5 ? 'ASSEMBLING EXPERIENCE' : 'EXPERIENCE COMPLETE');
    text('stageLabel', t < 8 ? 'PREPARING THE EXPERIENCE' : t < 12 ? 'BRINGING IT ALL TOGETHER' : 'ALL VISUAL LAYERS READY');
    text('sequenceLabel', t < 4 ? 'AWAKENING' : t < 12.5 ? 'ASSEMBLING' : 'READY');
    if (t > 4 && t < 13.5) { drawWave(t); drawCore(t); drawCodeStream(t); }
    const readyIn = smooth(13, 13.8, t);
    const readyOut = smooth(15, 16.4, t);
    $('ready').style.opacity = String(readyIn * (1 - readyOut));
    $('ready').style.transform = `translateY(${(1 - readyIn) * 18}px) scale(${.97 + .03 * readyIn + .035 * readyOut})`;
    const sweep = smooth(14.1, 16.5, t);
    $('lightSweep').style.transform = `translate(-50%, -50%) scale(${sweep * 28})`;
    $('lightSweep').style.opacity = String(Math.sin(sweep * Math.PI) * .9);
    // The ready text lives outside the black boot layer: its own surface is transparent.
    const desktopIn = smooth(12.1, 13.5, t);
    $('boot').style.opacity = String(1 - desktopIn);
    $('boot').style.visibility = t >= 13.5 ? 'hidden' : 'visible';
    for (const element of desktopFurniture) element.style.opacity = String(smooth(15.7, 17, t));
    $('edgeGlow').style.opacity = String(smooth(14.8, 17, t) * .82);
  }

  function frame(now) {
    if (state === 'playing') {
      const t = (now - startedAt) / 1000;
      render(t);
      if (t >= duration) finish();
    } else if (state === 'finished') {
      const seconds = (now - finishedAt) / 1000;
      // Start at the same alpha as the last boot frame; no jump at handoff.
      $('edgeGlow').style.opacity = String(.82 + .14 * Math.sin(seconds * Math.PI * 2 / 4.8) * smooth(0, 1.2, seconds));
    }
    raf = requestAnimationFrame(frame);
  }

  function start(fullscreen) {
    cancelAnimationFrame(raf);
    fullPlayback = fullscreen;
    lastLogCount = lastRecipeCount = -1;
    handedOff = false;
    $('streamCount').textContent = '0000 LINES';
    $('streamState').textContent = 'STAGED';
    const stream = contexts.codeStream;
    stream.ctx.clearRect(0, 0, stream.w, stream.h);
    $('error').textContent = '';
    setState('playing');
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
    startedAt = performance.now();
    resize();
    render(0);
    raf = requestAnimationFrame(frame);
  }

  function finish() {
    if (state === 'finished') return;
    setState('finished');
    fullPlayback = false;
    finishedAt = performance.now();
    render(duration);
    $('controlTitle').textContent = '欢迎回来，Miu AI 已就绪';
    $('controlHint').textContent = '模拟桌面 · 四边光效持续呼吸';
    $('play').textContent = '重播';
    $('fullscreenPlay').innerHTML = '<span aria-hidden="true">⛶</span> 全屏重播';
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {
      $('error').textContent = '请按 Esc 退出浏览器全屏。';
    });
    // Skip from the idle screen also needs one breathing loop.
    if (!raf) raf = requestAnimationFrame(frame);
  }

  $('play').addEventListener('click', () => start(false));
  $('skip').addEventListener('click', finish);
  $('fullscreenPlay').addEventListener('click', async () => {
    if (starting) return;
    starting = true;
    $('error').textContent = '';
    try {
      // Fullscreen requires this explicit click. No taskbar or OS settings change.
      await scene.requestFullscreen({ navigationUI: 'hide' });
      if (document.fullscreenElement === scene) start(true);
    } catch {
      $('error').textContent = '浏览器未允许全屏，请使用 Edge / Chrome 打开，或选择“播放”。';
    } finally { starting = false; }
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && state === 'playing') { event.preventDefault(); finish(); }
  });
  document.addEventListener('fullscreenchange', () => {
    // Native Esc may exit fullscreen before JavaScript receives a key event.
    if (fullPlayback && state === 'playing' && !document.fullscreenElement) finish();
    resize();
  });
  window.addEventListener('resize', resize);
  resize();
  render(3.25);
  $('sequenceLabel').textContent = 'AWAITING YOUR SIGNAL';
  document.fonts.load('400 100px "Miu Logo"').then(() => document.fonts.ready).then(() => {
    if (state === 'idle') render(3.25);
    $('play').disabled = false;
    $('fullscreenPlay').disabled = false;
  }).catch(() => {
    $('error').textContent = 'Varesco 字体未能加载，请保留 assets/fonts 文件夹后重新打开 Demo。';
  });
})();

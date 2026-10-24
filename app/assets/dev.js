(function () {
    var cards = document.querySelectorAll('.project-card');
    var area = document.querySelector('.projects');
    var rect = area.getBoundingClientRect();
    var isMobile = rect.width <= 640;
    var gapX = 20, gapY = 20;
    var cardW = isMobile ? (rect.width - 32) : 340;
    var cardH = 200;
    var cols = Math.min(cards.length, Math.floor(rect.width / (cardW + gapX)) || 1);
    var startX;
    cols = Math.min(cols, 2);
    var totalW = cols * cardW + (cols - 1) * gapX;
    startX = (rect.width - totalW) / 2;
    var totalRows = Math.ceil(cards.length / cols);
    var areaHeight = totalRows * (cardH + gapY + 20) + 40;
    area.style.height = areaHeight + 'px';

    // ── Enabled effects (empty array = no effects) ──
    var enabledEffects = ['quake', 'slice'];

    // ── Shared state ──
    var effectType = sessionStorage.getItem('effectType');
    var effectState = sessionStorage.getItem('effectState');
    var triggered = false;

    if (effectState === 'reloaded_once') {
        sessionStorage.removeItem('effectState');
        sessionStorage.removeItem('effectType');
        sessionStorage.setItem('effectDone', '1');
        effectState = null;
        effectType = null;
    }

    var effectDone = sessionStorage.getItem('effectDone') === '1';

    var positions = [];
    cards.forEach(function (c, i) {
        var col = i % cols, row = Math.floor(i / cols);
        var x = startX + col * (cardW + gapX);
        var y = row * (cardH + gapY + 20) + 20;
        positions.push({ x: x, y: y });
        c.style.left = x + 'px';
        c.style.top = y + 'px';
        c.style.transform = 'rotate(0deg)';
        c.dataset.rot = '0';
        c.dataset.orgX = x;
        c.dataset.orgY = y;
    });

    var msgEl = document.createElement('div');
    msgEl.className = 'quake-msg';
    msgEl.style.display = 'none';
    area.parentNode.insertBefore(msgEl, area);

    var messages = {
        quake: {
            initial: '🫨 Oops! Your cursor caused an earthquake - drag the cards to put them back!',
            reload: '😏 Nice try! Reload once more to end the fun - or stay and play.',
            fixed: '✨ Nice work! Everything is back in order.'
        },
        slice: {
            initial: '✂️ Your cursor just sliced through the cards - drag the pieces back!',
            reload: '🔪 Still in pieces! One more reload to undo the damage - or fix it yourself.',
            fixed: '🧩 Perfectly reassembled! Good as new.'
        }
    };

    // ── Sound effects (synthesized via Web Audio API) ──

    var audioCtx = null;

    function getAudioCtx() {
        if (!audioCtx) {
            try { audioCtx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {}
        }
        return audioCtx;
    }

    function resumeAudio() {
        var ctx = getAudioCtx();
        if (ctx && ctx.state === 'suspended') ctx.resume();
    }

    document.addEventListener('click', resumeAudio);
    document.addEventListener('touchstart', resumeAudio);
    document.addEventListener('mousedown', resumeAudio);
    document.addEventListener('keydown', resumeAudio);

    function playQuakeSound() {
        var ctx = getAudioCtx();
        if (!ctx) return;
        // Low rumble: brown noise burst with frequency sweep
        var dur = 0.8;
        var len = ctx.sampleRate * dur;
        var buf = ctx.createBuffer(1, len, ctx.sampleRate);
        var data = buf.getChannelData(0);
        var last = 0;
        for (var i = 0; i < len; i++) {
            var white = Math.random() * 2 - 1;
            last = (last + (0.02 * white)) / 1.02;
            data[i] = last * 3.5 * (1 - i / len);
        }
        var src = ctx.createBufferSource();
        src.buffer = buf;
        var gain = ctx.createGain();
        gain.gain.setValueAtTime(0.6, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + dur);
        src.connect(gain);
        gain.connect(ctx.destination);
        src.start();
    }

    function playSliceSound() {
        var ctx = getAudioCtx();
        if (!ctx) return;
        // Metallic swoosh: high-freq noise burst with fast decay
        var dur = 0.3;
        var len = ctx.sampleRate * dur;
        var buf = ctx.createBuffer(1, len, ctx.sampleRate);
        var data = buf.getChannelData(0);
        for (var i = 0; i < len; i++) {
            var t = i / ctx.sampleRate;
            var env = Math.exp(-t * 15);
            data[i] = (Math.random() * 2 - 1) * env;
        }
        var src = ctx.createBufferSource();
        src.buffer = buf;
        var hp = ctx.createBiquadFilter();
        hp.type = 'highpass';
        hp.frequency.value = 3000;
        var gain = ctx.createGain();
        gain.gain.value = 0.5;
        src.connect(hp);
        hp.connect(gain);
        gain.connect(ctx.destination);
        src.start();
    }

    function playFixSound() {
        var ctx = getAudioCtx();
        if (!ctx) return;
        // Pleasant chime: two quick ascending tones
        [523.25, 783.99].forEach(function (freq, i) {
            var osc = ctx.createOscillator();
            osc.type = 'sine';
            osc.frequency.value = freq;
            var gain = ctx.createGain();
            var t = ctx.currentTime + i * 0.12;
            gain.gain.setValueAtTime(0.3, t);
            gain.gain.exponentialRampToValueAtTime(0.01, t + 0.4);
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.start(t);
            osc.stop(t + 0.4);
        });
    }

    function playPickupSound() {
        var ctx = getAudioCtx();
        if (!ctx) return;
        // Soft pop: short sine burst rising in pitch
        var osc = ctx.createOscillator();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(300, ctx.currentTime);
        osc.frequency.exponentialRampToValueAtTime(600, ctx.currentTime + 0.08);
        var gain = ctx.createGain();
        gain.gain.setValueAtTime(0.2, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.1);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start();
        osc.stop(ctx.currentTime + 0.1);
    }

    function playDropSound() {
        var ctx = getAudioCtx();
        if (!ctx) return;
        // Soft thud: short low sine dropping in pitch
        var osc = ctx.createOscillator();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(250, ctx.currentTime);
        osc.frequency.exponentialRampToValueAtTime(80, ctx.currentTime + 0.12);
        var gain = ctx.createGain();
        gain.gain.setValueAtTime(0.25, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.15);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start();
        osc.stop(ctx.currentTime + 0.15);
    }

    var soundPlayers = { quake: playQuakeSound, slice: playSliceSound, fix: playFixSound, pickup: playPickupSound, drop: playDropSound };

    function playSound(key) {
        try { if (soundPlayers[key]) soundPlayers[key](); } catch (e) {}
    }

    // ── Shared helpers ──

    function scatterCards(animate) {
        cards.forEach(function (c) {
            var maxX = rect.width - cardW;
            var maxY = parseFloat(area.style.height) - cardH;
            var rx = Math.random() * maxX;
            var ry = Math.random() * maxY;
            var rr = (Math.random() * 30 - 15);
            if (animate) {
                c.style.transition = 'left 0.5s cubic-bezier(0.22,1,0.36,1), top 0.5s cubic-bezier(0.22,1,0.36,1), transform 0.5s cubic-bezier(0.22,1,0.36,1)';
                setTimeout(function() { c.style.transition = ''; }, 550);
            }
            c.style.left = rx + 'px';
            c.style.top = ry + 'px';
            c.style.transform = 'rotate(' + rr + 'deg)';
            c.dataset.rot = rr;
        });
    }

    function setSliceVisual(on) {
        cards.forEach(function (c) { c.classList[on ? 'add' : 'remove']('sliced'); });
    }

    function activate(type, animate) {
        triggered = true;
        effectType = type;
        sessionStorage.setItem('effectType', type);
        sessionStorage.setItem('effectState', 'triggered');
        msgEl.innerHTML = messages[type].initial;
        msgEl.style.display = 'block';
    }

    // ── Effect: Earthquake ──

    function earthquakeEffect() {
        if (triggered) return;
        activate('quake');
        playSound('quake');
        if (navigator.vibrate) navigator.vibrate([100, 50, 100]); // haptic feedback for quake
        area.classList.add('quake-shake');
        setTimeout(function () { area.classList.remove('quake-shake'); }, 600);
        scatterCards(true);
    }

    function earthquakeRestore() {
        scatterCards(false);
    }

    // ── Effect: Slice ──

    function sliceEffect() {
        if (triggered) return;
        activate('slice');
        playSound('slice');
        if (navigator.vibrate) navigator.vibrate([80, 40, 80]); // haptic feedback for slice
        area.classList.add('slash-sweep');
        setTimeout(function () { area.classList.remove('slash-sweep'); }, 800);
        setSliceVisual(true);
        setTimeout(function () { scatterCards(true); }, 200);
    }

    function sliceRestore() {
        setSliceVisual(true);
        scatterCards(false);
    }

    // ── Effect registry ──

    var effects = {
        quake: { trigger: earthquakeEffect, restore: earthquakeRestore, cleanup: function () {} },
        slice: { trigger: sliceEffect, restore: sliceRestore, cleanup: function () { setSliceVisual(false); } }
    };

    // ── Handle reload persistence ──

    if (effectState === 'triggered' && effectType && effects[effectType]) {
        sessionStorage.setItem('effectState', 'reloaded_once');
        triggered = true;
        msgEl.innerHTML = messages[effectType].reload;
        msgEl.style.display = 'block';
        effects[effectType].restore();
    }

    // ── Trigger random effect on hover (only after first click) ──

    var userInteracted = false;

    function onFirstInteraction() {
        userInteracted = true;
        resumeAudio();
        document.removeEventListener('click', onFirstInteraction);
        document.removeEventListener('touchstart', onFirstInteraction);
    }

    document.addEventListener('click', onFirstInteraction);
    document.addEventListener('touchstart', onFirstInteraction);

    function triggerRandomEffect() {
        if (!userInteracted || triggered || enabledEffects.length === 0) return;
        var picked = enabledEffects[Math.floor(Math.random() * enabledEffects.length)];
        if (effects[picked]) effects[picked].trigger();
    }

    if (!effectDone && enabledEffects.length > 0) {
        area.addEventListener('mouseenter', triggerRandomEffect);
        area.addEventListener('touchstart', function () { triggerRandomEffect(); }, { passive: true, once: true });
    }

    // ── Check if cards are back in place ──

    function checkOrganized() {
        if (!triggered) return;
        var allGood = true;
        cards.forEach(function (c, i) {
            var cx = parseFloat(c.style.left);
            var cy = parseFloat(c.style.top);
            var dx = Math.abs(cx - positions[i].x);
            var dy = Math.abs(cy - positions[i].y);
            if (dx > 50 || dy > 50) allGood = false;
        });
        if (allGood) {
            playSound('fix');
            sessionStorage.removeItem('effectState');
            sessionStorage.removeItem('effectType');
            sessionStorage.setItem('effectDone', '1');
            if (effectType && effects[effectType]) effects[effectType].cleanup();
            msgEl.innerHTML = messages[effectType || 'quake'].fixed;
            msgEl.classList.add('quake-msg-success');
            setTimeout(function () {
                msgEl.style.display = 'none';
                msgEl.classList.remove('quake-msg-success');
            }, 2500);
        }
    }

    // ── Drag handling ──

    var drag = null, offX, offY, moved;
    function onDown(e) {
        var c = e.target.closest('.project-card');
        if (!c) return;
        e.preventDefault();
        drag = c; moved = false;
        var t = e.touches ? e.touches[0] : e;
        var cr = c.getBoundingClientRect();
        offX = t.clientX - cr.left;
        offY = t.clientY - cr.top;
        c.classList.add('dragging');
        c.style.transform = 'rotate(0deg) scale(1.04)';
        c.style.zIndex = 100;
        playSound('pickup');
        if (navigator.vibrate) navigator.vibrate(50); // haptic feedback for drag start
    }
    function onMove(e) {
        if (!drag) return;
        e.preventDefault();
        moved = true;
        var t = e.touches ? e.touches[0] : e;
        var ar = area.getBoundingClientRect();
        drag.style.left = (t.clientX - ar.left - offX) + 'px';
        drag.style.top = (t.clientY - ar.top - offY) + 'px';
    }
    function onUp(e) {
        if (!drag) return;
        playSound('drop');
        if (navigator.vibrate) navigator.vibrate(30); // haptic feedback for drag end
        drag.classList.remove('dragging');
        drag.style.transform = 'rotate(' + drag.dataset.rot + 'deg)';
        drag.style.zIndex = '';
        if (!moved) {
            var href = drag.getAttribute('href');
            if (href) window.open(href, '_blank');
        }
        drag = null;
        checkOrganized();
    }
    area.addEventListener('mousedown', onDown);
    area.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
    area.addEventListener('touchstart', onDown, { passive: false });
    area.addEventListener('touchmove', onMove, { passive: false });
    document.addEventListener('touchend', onUp);
    cards.forEach(function (c) { c.addEventListener('click', function (e) { e.preventDefault(); }) });
})();
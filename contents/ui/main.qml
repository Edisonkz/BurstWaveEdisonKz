import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    compactRepresentation: fullRepresentation
    Plasmoid.backgroundHints: "NoBackground"

    Layout.minimumWidth: 400
    Layout.minimumHeight: 220
    Layout.preferredWidth: 1920
    Layout.preferredHeight: 360
    Layout.fillWidth: true
    Layout.fillHeight: true

    readonly property var cfg: Plasmoid.configuration || plasmoid.configuration
    readonly property int numBars: cfg && cfg.numBars ? cfg.numBars : 32
    readonly property real maxRange: 1000.0
    readonly property int framerate: cfg && cfg.framerate ? cfg.framerate : 60
    readonly property int sensitivity: cfg && cfg.sensitivity ? cfg.sensitivity : 110
    readonly property real noiseReduction: (cfg && cfg.noiseReduction !== undefined) ? cfg.noiseReduction : 0.77
    readonly property real chargeSpeed: (cfg && cfg.chargeSpeed !== undefined) ? cfg.chargeSpeed : 1.4

    readonly property string c1: (cfg && cfg.color1) || "#00f0ff"        // Electric Cyan
    readonly property string c2: (cfg && cfg.color2) || "#b026ff"        // Neon Purple
    readonly property string burst: (cfg && cfg.burstColor) || "#ff007f" // Intense Pink/Magenta

    readonly property bool plasmoidVisible: (plasmoid.visible === undefined) ? true : plasmoid.visible

    property var bars: Array(numBars).fill(0)
    property string mStatus: ""
    property string artUrl: ""
    property string mTitle: ""
    property string mArtist: ""

    readonly property bool isPlaying: {
        if (mpris2Model.currentPlayer && mpris2Model.currentPlayer.playbackStatus !== undefined) {
            return mpris2Model.currentPlayer.playbackStatus === Mpris.PlaybackStatus.Playing;
        }
        return mStatus === "Playing";
    }

    function togglePlayPause() {
        if (mpris2Model.currentPlayer) {
            mpris2Model.currentPlayer.PlayPause();
        } else {
            cmdSrc.connectSource("qdbus6 org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause 2>/dev/null || busctl --user call org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlayPause 2>/dev/null || playerctl play-pause 2>/dev/null; true");
        }
    }

    function playNext() {
        if (mpris2Model.currentPlayer) {
            mpris2Model.currentPlayer.Next();
        } else {
            cmdSrc.connectSource("qdbus6 org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Next 2>/dev/null || busctl --user call org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Next 2>/dev/null || playerctl next 2>/dev/null; true");
        }
    }

    function playPrev() {
        if (mpris2Model.currentPlayer) {
            mpris2Model.currentPlayer.Previous();
        } else {
            cmdSrc.connectSource("qdbus6 org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Previous 2>/dev/null || busctl --user call org.mpris.MediaPlayer2.plasma-browser-integration /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Previous 2>/dev/null || playerctl previous 2>/dev/null; true");
        }
    }

    readonly property string feederPath: Qt.resolvedUrl("../code/feeder.sh").toString().replace(/^file:\/\//, "")
    readonly property string mprisPath: Qt.resolvedUrl("../code/mpris.sh").toString().replace(/^file:\/\//, "")

    property string resolvedRunDir: ""
    property string framePath: ""
    property string barsPath: ""
    property real lastFrameOk: 0

    function shellQuote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'"; }

    function hexLerp(a, b, t) {
        t = Math.max(0, Math.min(1, t));
        const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
        const ar = (pa >> 16) & 255, ag = (pa >> 8) & 255, ab = pa & 255;
        const br = (pb >> 16) & 255, bg = (pb >> 8) & 255, bb = pb & 255;
        const r = Math.round(ar + (br - ar) * t);
        const g = Math.round(ag + (bg - ag) * t);
        const bl = Math.round(ab + (bb - ab) * t);
        return "rgb(" + r + "," + g + "," + bl + ")";
    }

    function barAt(frac) {
        const idx = Math.floor(((frac % 1 + 1) % 1) * bars.length);
        return (bars[idx] || 0) / maxRange;
    }

    // ── CAVA Feeder Integration ───────────────────────────────────────────
    Plasma5Support.DataSource {
        id: cmdSrc
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
        }
    }

    Plasma5Support.DataSource {
        id: pathResolver
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
            const p = (data["stdout"] || "").trim();
            if (p) {
                root.resolvedRunDir = p;
                root.framePath = p + "/frame.ini";
                root.barsPath = p + "/bars";
                root.ensureFeeder();
            }
        }
    }

    Component.onCompleted: {
        pathResolver.connectSource("echo -n ${XDG_RUNTIME_DIR:-/tmp}/audio-wave-widget");
        startTimer.interval = 800;
        startTimer.start();
        pollMpris();
    }

    Component.onDestruction: {
        if (resolvedRunDir) {
            cmdSrc.connectSource("pkill -F " + shellQuote(resolvedRunDir + "/feeder.pid") + " -f 'feeder\\.sh' 2>/dev/null; true");
        }
    }

    Timer {
        id: startTimer
        repeat: false
        onTriggered: ensureFeeder()
    }

    Timer {
        id: feederHeartbeat
        interval: 25000
        repeat: true
        running: root.plasmoidVisible
        onTriggered: {
            if (root.resolvedRunDir && (Date.now() - root.lastFrameOk) > 3000) {
                ensureFeeder();
            }
        }
    }

    function ensureFeeder() {
        if (!resolvedRunDir) return;
        cmdSrc.connectSource("bash " + shellQuote(feederPath) + " " + numBars + " " + framerate
                   + " " + sensitivity + " " + noiseReduction + " auto");
    }

    // ── Frame Transport ───────────────────────────────────────────────────
    Loader {
        id: barsIni
        active: root.framePath !== ""
        sourceComponent: Settings { location: "file://" + root.framePath }
    }

    Plasma5Support.DataSource {
        id: legacyReader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
            ingest(String(data["stdout"] || "").trim());
        }
    }

    Timer {
        id: framePoll
        interval: Math.max(16, Math.round(1000 / root.framerate))
        repeat: true
        triggeredOnStart: true
        running: root.plasmoidVisible
        onTriggered: pollFrame()
    }

    function pollFrame() {
        const s = barsIni.item;
        if (s) {
            s.sync();
            const stamp = Number(s.value("t", 0)) * 1000;
            if (stamp > 0 && Math.abs(Date.now() - stamp) < 2500) {
                root.lastFrameOk = Date.now();
                ingest(String(s.value("v", "")));
                return;
            }
        }
        if (root.barsPath && legacyReader.connectedSources.length === 0) {
            legacyReader.connectSource("cat " + shellQuote(root.barsPath));
        }
    }

    function ingest(raw) {
        if (!raw) return;
        const parts = String(raw).split(/[;,]/).filter(Boolean);
        if (parts.length === 0) return;
        const count = numBars;
        const prev = bars;
        const out = new Array(count);
        let changed = prev.length !== count;
        for (let i = 0; i < count; i++) {
            const pIdx = Math.min(parts.length - 1, Math.floor(i * parts.length / count));
            const v = Number(parts[pIdx]) || 0;
            const t = Math.max(0, Math.min(maxRange, v));
            const b = prev[i] || 0;
            const n = b + 0.68 * (t - b);
            out[i] = n;
            if (Math.abs(n - b) > 1) changed = true;
        }
        if (changed) bars = out;
    }

    // ── MPRIS Integration ─────────────────────────────────────────────────
    Mpris.Mpris2Model {
        id: mpris2Model
    }

    function _syncMpris() {
        const p = mpris2Model.currentPlayer;
        if (p) {
            if (p.artUrl !== undefined && p.artUrl !== "") root.artUrl = p.artUrl;
            if (p.track !== undefined && p.track !== "") root.mTitle = p.track;
            if (p.artist !== undefined && p.artist !== "") root.mArtist = p.artist;
        }
    }

    Connections {
        target: mpris2Model
        ignoreUnknownSignals: true
        function onCurrentPlayerChanged() {
            root._syncMpris();
            pollMpris();
        }
    }

    Connections {
        target: mpris2Model.currentPlayer
        ignoreUnknownSignals: true
        function onArtUrlChanged() { root._syncMpris(); }
        function onTrackChanged() { root._syncMpris(); }
        function onArtistChanged() { root._syncMpris(); }
        function onPlaybackStatusChanged() { root._syncMpris(); }
    }

    Plasma5Support.DataSource {
        id: mprisSrc
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source);
            const line = String(data["stdout"] || "").split("\n").filter(Boolean)[0] || "";
            if (!line) return;
            const f = line.split("\t");
            if (f[0]) root.mStatus = f[0];
            if (f[1]) root.artUrl = f[1];
            if (f[2]) root.mTitle = f[2];
            if (f[3]) root.mArtist = f[3];
        }
    }

    Timer {
        id: mprisTimer
        interval: 1800
        repeat: true
        running: root.plasmoidVisible
        onTriggered: pollMpris()
    }

    function pollMpris() {
        if (mprisSrc.connectedSources.length === 0) {
            mprisSrc.connectSource("python3 " + shellQuote(mprisPath));
        }
    }

    // ── Full Representation (Visual View & Graphics Engine) ──────────────
    fullRepresentation: Item {
        id: container
        anchors.fill: parent

        readonly property real artR: 90
        readonly property real artX: artR + 40
        readonly property real artY: height > 0 ? height / 2 : 180

        property real now: 0
        property real band: 0
        property real bandLow: 0
        property real bandHigh: 0
        property real attackPrev: 0
        property real peak: 0
        property real charge: 0
        property real shockT: 99
        property real flashT: 99
        property real lastBurst: -10000

        property var bolts: []
        property var sparks: []

        // Dynamic frame pacing
        Timer {
            id: stepTimer
            interval: (container.band > 0.008 || container.bolts.length > 0) ? 16 : 55
            repeat: true
            running: root.plasmoidVisible
            onTriggered: container.step(interval * 0.001)
        }

        function step(dt) {
            now += dt;

            const N = root.bars.length;
            let s = 0, low = 0, lowN = 0, hi = 0, hiN = 0;
            for (let i = 0; i < N; i++) {
                const v = root.bars[i] || 0;
                s += v;
                if (i < N * 0.35) { low += v; lowN++; }
                else if (i > N * 0.65) { hi += v; hiN++; }
            }
            const avg = N ? (s / N) / root.maxRange : 0;
            const bass = lowN ? (low / lowN) / root.maxRange : 0;
            const treble = hiN ? (hi / hiN) / root.maxRange : 0;

            band = band > 0 ? band + 0.35 * (avg - band) : avg;
            bandLow = bandLow > 0 ? bandLow + 0.48 * (bass - bandLow) : bass;
            bandHigh = bandHigh > 0 ? bandHigh + 0.40 * (treble - bandHigh) : treble;

            attackPrev = attackPrev + 0.25 * (band - attackPrev);
            const attack = band - attackPrev;
            peak = Math.max(band, peak * 0.96);

            // Calibrated 5-7 second charge accumulation
            if (band > 0.01) {
                const speedMult = 0.8 + bandLow * 0.7 + band * 0.3;
                charge = Math.min(100, charge + (dt / 5.8) * 100 * speedMult);
            } else {
                charge = Math.max(0, charge - 14.0 * dt);
            }

            // Periodic electric discharge every 5-7s on full charge OR chorus drop
            if (charge >= 99.5) {
                fireBurst(0.70 + band * 0.7);
            } else if (attack > 0.28 && band > 0.48 && (now - lastBurst) > 4.5) {
                fireBurst(0.80 + attack * 1.3);
            }

            // Advance bolts
            for (let i = bolts.length - 1; i >= 0; i--) {
                bolts[i].life += dt;
                if (bolts[i].life >= bolts[i].max) bolts.splice(i, 1);
            }

            // Advance sparks
            const cw = width > 0 ? width : 1920;
            for (let i = sparks.length - 1; i >= 0; i--) {
                const sp = sparks[i];
                sp.life += dt;
                sp.x += sp.vx * dt;
                sp.y += sp.vy * dt;
                sp.vx *= 0.988;
                sp.vy += 70 * dt;
                if (sp.life >= sp.max || sp.x > cw + 40) sparks.splice(i, 1);
            }

            if (shockT < 1.0) shockT += dt * 1.8;
            if (flashT < 1.0) flashT += dt * 3.5;

            canvas.requestPaint();
        }

        function fireBurst(power) {
            lastBurst = now;
            charge = 0;
            shockT = 0;
            flashT = 0;

            const R = artR;
            const cx = artX, cy = artY;
            const cw = width > 0 ? width : 1920;
            const ch = height > 0 ? height : 360;

            const nBolts = 3 + Math.floor(power * 3);
            for (let b = 0; b < nBolts; b++) {
                const targetY = cy + (Math.random() - 0.5) * 70;
                bolts.push({
                    seed: Math.random() * 9999,
                    life: 0,
                    max: 0.38 + Math.random() * 0.40,
                    yStart: cy + (Math.random() - 0.5) * R * 0.5,
                    yEnd: targetY,
                    xEnd: cw - 15 - Math.random() * 50,
                    jitter: 20 + Math.random() * 25,
                    divs: 35 + Math.floor(Math.random() * 15),
                    power: 0.7 + Math.random() * 0.4,
                    branch: Math.random() < 0.5,
                    branchDiv: 14 + Math.floor(Math.random() * 12),
                    branchAngle: (Math.random() - 0.5) * 0.5
                });
            }

            const nSparks = 24 + Math.floor(power * 25);
            const palette = [root.c1, root.c2, root.burst, "#ffffff"];
            for (let i = 0; i < nSparks; i++) {
                sparks.push({
                    x: cx + R * (0.8 + Math.random() * 0.4),
                    y: cy + (Math.random() - 0.5) * 40,
                    vx: 550 + Math.random() * 800,
                    vy: (Math.random() - 0.5) * 220,
                    life: 0,
                    max: 0.50 + Math.random() * 0.50,
                    size: 1.4 + Math.random() * 2.0,
                    color: palette[Math.floor(Math.random() * palette.length)]
                });
            }
        }

        // ── Canvas Overlay (Auras, Enveloping Waves & Multi-Wave Beam) ─────
        Canvas {
            id: canvas
            anchors.fill: parent
            z: 5
            renderTarget: Canvas.FramebufferObject
            renderStrategy: Canvas.Cooperative

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (width < 50 || height < 50) return;

                const R = container.artR;
                const cx = container.artX;
                const cy = container.artY;

                drawAuraAndHub(ctx, cx, cy, R);
                drawEnvelopingWaves(ctx, cx, cy, R);
                drawContinuousMultiWaveBeam(ctx, cx, cy, R, width);
                drawChargeRing(ctx, cx, cy, R);
                drawElectricBurst(ctx, cx, cy, R);
            }

            // 1. Bass Aura & High-Speed Border Rim
            function drawAuraAndHub(ctx, cx, cy, R) {
                const TAU = Math.PI * 2;
                const bass = container.bandLow;

                if (container.flashT < 1.0) {
                    const fa = (1.0 - container.flashT) * 0.35;
                    ctx.fillStyle = "rgba(255,255,255," + fa + ")";
                    ctx.beginPath();
                    ctx.arc(cx, cy, R * 1.4, 0, TAU);
                    ctx.fill();
                }

                const auraRadius = R * (1.12 + bass * 0.55);
                const g = ctx.createRadialGradient(cx, cy, R * 0.7, cx, cy, auraRadius);
                g.addColorStop(0, "rgba(0,240,255," + (0.22 + bass * 0.35) + ")");
                g.addColorStop(0.6, "rgba(176,38,255," + (0.12 + bass * 0.2) + ")");
                g.addColorStop(1, "rgba(0,0,0,0)");
                ctx.fillStyle = g;
                ctx.beginPath();
                ctx.arc(cx, cy, auraRadius, 0, TAU);
                ctx.fill();

                ctx.lineWidth = 6.0;
                ctx.strokeStyle = "rgba(0,240,255,0.30)";
                ctx.beginPath();
                ctx.arc(cx, cy, R + 1, 0, TAU);
                ctx.stroke();

                ctx.lineWidth = 2.4;
                ctx.strokeStyle = root.hexLerp(root.c1, root.burst, 0.4 + 0.5 * Math.sin(container.now * 3));
                ctx.beginPath();
                ctx.arc(cx, cy, R + 1, 0, TAU);
                ctx.stroke();
            }

            // 2. Enveloping Waves
            function drawEnvelopingWaves(ctx, cx, cy, R) {
                const TAU = Math.PI * 2;
                const now = container.now;
                const band = container.band;
                const bass = container.bandLow;

                const ringConfigs = [
                    { r: R + 15, lobes: 6,  speed: 2.2,  amp: 5 + bass * 18,  color: root.c1,    width: 2.2, alpha: 0.60 },
                    { r: R + 34, lobes: 8,  speed: -1.6, amp: 7 + band * 16,  color: root.c2,    width: 1.8, alpha: 0.45 }
                ];

                for (let k = 0; k < ringConfigs.length; k++) {
                    const cfg = ringConfigs[k];
                    const baseR = cfg.r;
                    const N = 48;
                    ctx.beginPath();
                    for (let i = 0; i <= N; i++) {
                        const a = (i / N) * TAU;
                        const mod = Math.sin(a * cfg.lobes + now * cfg.speed) * cfg.amp;
                        const rr = baseR + mod;
                        const x = cx + Math.cos(a) * rr;
                        const y = cy + Math.sin(a) * rr;
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.closePath();
                    ctx.strokeStyle = cfg.color;
                    ctx.globalAlpha = Math.min(0.9, cfg.alpha + band * 0.3);
                    ctx.lineWidth = cfg.width;
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;

                const stems = 26;
                ctx.lineCap = "round";
                for (let i = 0; i < stems; i++) {
                    const frac = i / stems;
                    const a = frac * TAU + now * 0.22;
                    const bv = root.barAt(frac);
                    const spikeLen = (4 + bv * 38 * (0.8 + bass * 0.5));
                    const r0 = R + 7;
                    const r1 = r0 + spikeLen;

                    const x0 = cx + Math.cos(a) * r0;
                    const y0 = cy + Math.sin(a) * r0;
                    const x1 = cx + Math.cos(a) * r1;
                    const y1 = cy + Math.sin(a) * r1;

                    ctx.strokeStyle = root.hexLerp(root.c1, root.c2, frac);
                    ctx.globalAlpha = 0.35 + bv * 0.50;
                    ctx.lineWidth = 2.0;
                    ctx.beginPath();
                    ctx.moveTo(x0, y0);
                    ctx.lineTo(x1, y1);
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;
            }

            // 3. CONTINUOUS MULTI-WAVE HARMONIC BEAM (4 Interwoven Waves)
            function drawContinuousMultiWaveBeam(ctx, cx, cy, R, w) {
                const x0 = cx + R + 14;
                const x1 = w - 15;
                if (x1 <= x0) return;

                const span = x1 - x0;
                const now = container.now;
                const band = container.band;
                const bass = container.bandLow;
                const treble = container.bandHigh;

                const chorusFactor = Math.pow(Math.max(0.08, band), 1.35);
                const maxAmp = 20 + chorusFactor * 130;

                const numPoints = 55;
                const dx = span / numPoints;

                ctx.save();
                ctx.lineCap = "round";
                ctx.lineJoin = "round";

                // Wave 1: Bass / Low End (Electric Cyan)
                ctx.beginPath();
                for (let i = 0; i <= numPoints; i++) {
                    const u = i / numPoints;
                    const px = x0 + i * dx;
                    const bv = root.barAt(u * 0.35);
                    const amp = (9 + (bass * 0.45 + bv * 0.55) * maxAmp);
                    const w1 = Math.sin(u * 11 - now * 4.2) * (amp * 0.85);
                    const w2 = Math.sin(u * 22 + now * 5.2) * (amp * 0.22);
                    const py = cy + w1 + w2;
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.strokeStyle = root.c1;
                ctx.lineWidth = 6.5 + chorusFactor * 3.5;
                ctx.globalAlpha = 0.35 + chorusFactor * 0.35;
                ctx.stroke();
                ctx.lineWidth = 2.4;
                ctx.globalAlpha = 0.92;
                ctx.stroke();

                // Wave 2: Mids / Vocals (Neon Violet)
                ctx.beginPath();
                for (let i = 0; i <= numPoints; i++) {
                    const u = i / numPoints;
                    const px = x0 + i * dx;
                    const bv = root.barAt(0.25 + u * 0.45);
                    const amp = (7 + (band * 0.40 + bv * 0.60) * maxAmp * 0.85);
                    const w1 = Math.sin(u * 17 + now * 3.8 + 1.2) * (amp * 0.78);
                    const w2 = -Math.cos(u * 29 - now * 4.6) * (amp * 0.24);
                    const py = cy + w1 + w2;
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.strokeStyle = root.c2;
                ctx.lineWidth = 5.0;
                ctx.globalAlpha = 0.28 + chorusFactor * 0.25;
                ctx.stroke();
                ctx.lineWidth = 2.0;
                ctx.globalAlpha = 0.85;
                ctx.stroke();

                // Wave 3: Treble / Detail (Hot Magenta)
                ctx.beginPath();
                for (let i = 0; i <= numPoints; i++) {
                    const u = i / numPoints;
                    const px = x0 + i * dx;
                    const bv = root.barAt(0.55 + u * 0.45);
                    const amp = (6 + (treble * 0.40 + bv * 0.60) * maxAmp * 0.75);
                    const w1 = Math.sin(u * 27 - now * 6.2 + 2.3) * (amp * 0.70);
                    const w2 = Math.sin(u * 44 + now * 7.8) * (amp * 0.30);
                    const py = cy + w1 + w2;
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.strokeStyle = root.burst;
                ctx.lineWidth = 4.2;
                ctx.globalAlpha = 0.26 + chorusFactor * 0.25;
                ctx.stroke();
                ctx.lineWidth = 1.8;
                ctx.globalAlpha = 0.82;
                ctx.stroke();

                // Wave 4: Sub-harmonic Resonance (Ice Blue)
                ctx.beginPath();
                for (let i = 0; i <= numPoints; i++) {
                    const u = i / numPoints;
                    const px = x0 + i * dx;
                    const bv = root.barAt(1.0 - u);
                    const amp = (7 + bv * maxAmp * 0.65);
                    const w1 = Math.cos(u * 8 + now * 2.8 - 1.0) * (amp * 0.80);
                    const w2 = Math.sin(u * 19 - now * 3.5) * (amp * 0.20);
                    const py = cy + w1 + w2;
                    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                }
                ctx.strokeStyle = "#70e0ff";
                ctx.lineWidth = 1.6;
                ctx.globalAlpha = 0.60 + chorusFactor * 0.30;
                ctx.stroke();

                // Dynamic vertical equalizer spikes
                const nBars = 30;
                for (let j = 0; j < nBars; j++) {
                    const u = j / nBars;
                    const sx = x0 + u * span;
                    const bv = root.barAt(u);
                    if (bv > 0.06) {
                        const h = (bv * maxAmp * 1.05);
                        const baseline = cy + Math.sin(u * 11 - now * 4.2) * ((7 + bv * maxAmp) * 0.45);
                        ctx.beginPath();
                        ctx.moveTo(sx, baseline - h * 0.5);
                        ctx.lineTo(sx, baseline + h * 0.5);
                        ctx.strokeStyle = root.hexLerp(root.c1, root.burst, u);
                        ctx.globalAlpha = 0.30 + bv * 0.50;
                        ctx.lineWidth = 1.8;
                        ctx.stroke();
                    }
                }
                ctx.restore();
            }

            // 4. Energy Accumulator Ring
            function drawChargeRing(ctx, cx, cy, R) {
                const TAU = Math.PI * 2;
                const frac = Math.min(1.0, container.charge / 100);
                if (frac <= 0.01) return;

                const a0 = -Math.PI / 2;
                const a1 = a0 + frac * TAU;
                const gaugeR = R + 6.5;

                ctx.save();
                ctx.lineCap = "round";
                ctx.lineWidth = 6;
                ctx.strokeStyle = root.hexLerp(root.c1, root.burst, frac);
                ctx.globalAlpha = 0.35 + frac * 0.45;
                ctx.beginPath();
                ctx.arc(cx, cy, gaugeR, a0, a1);
                ctx.stroke();

                ctx.lineWidth = 2.0;
                ctx.strokeStyle = "#ffffff";
                ctx.globalAlpha = 0.85 + frac * 0.15;
                ctx.beginPath();
                ctx.arc(cx, cy, gaugeR, a0, a1);
                ctx.stroke();
                ctx.restore();
            }

            // 5. Electric Burst
            function drawElectricBurst(ctx, cx, cy, R) {
                for (let b = 0; b < container.bolts.length; b++) {
                    const bolt = container.bolts[b];
                    const t = bolt.life / bolt.max;
                    if (t >= 1.0) continue;
                    const alpha = (1.0 - t);

                    const x0 = cx + R + 10;
                    const y0 = bolt.yStart;
                    const x1 = bolt.xEnd;
                    const y1 = bolt.yEnd;
                    const n = bolt.divs;
                    const dx = (x1 - x0) / n;

                    const pts = [];
                    for (let i = 0; i <= n; i++) {
                        const px = x0 + i * dx;
                        const frac = i / n;
                        const linY = y0 + (y1 - y0) * frac;
                        const wave1 = Math.sin(i * 0.9 + bolt.seed) * bolt.jitter;
                        const wave2 = Math.cos(i * 1.8 + bolt.seed * 1.5) * (bolt.jitter * 0.35);
                        pts.push([px, linY + wave1 + wave2]);
                    }

                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    ctx.globalAlpha = alpha * 0.38;
                    ctx.strokeStyle = (b % 2 === 0) ? root.burst : root.c1;
                    ctx.lineWidth = 7.0 * bolt.power;
                    ctx.beginPath();
                    ctx.moveTo(pts[0][0], pts[0][1]);
                    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
                    ctx.stroke();

                    ctx.globalAlpha = alpha * 0.95;
                    ctx.strokeStyle = "#ffffff";
                    ctx.lineWidth = 1.8;
                    ctx.beginPath();
                    ctx.moveTo(pts[0][0], pts[0][1]);
                    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;

                for (let i = 0; i < container.sparks.length; i++) {
                    const sp = container.sparks[i];
                    const t = sp.life / sp.max;
                    if (t >= 1.0) continue;
                    ctx.globalAlpha = 1.0 - t;
                    ctx.strokeStyle = sp.color;
                    ctx.lineWidth = sp.size;
                    ctx.beginPath();
                    ctx.moveTo(sp.x - sp.vx * 0.03, sp.y - sp.vy * 0.03);
                    ctx.lineTo(sp.x, sp.y);
                    ctx.stroke();
                }
                ctx.globalAlpha = 1.0;

                if (container.shockT < 1.0) {
                    const t = container.shockT;
                    const shockX = cx + t * (width - cx);
                    ctx.globalAlpha = (1.0 - t) * 0.45;
                    ctx.strokeStyle = root.c1;
                    ctx.lineWidth = 1 + (1.0 - t) * 5;
                    ctx.beginPath();
                    ctx.arc(cx, cy, shockX - cx, -Math.PI * 0.36, Math.PI * 0.36);
                    ctx.stroke();
                    ctx.globalAlpha = 1.0;
                }
            }
        }

        // ── Interactive Circular Hub (Artist Photo, Media Controls & Info) ──
        Item {
            id: artContainer
            x: container.artX - container.artR
            y: container.artY - container.artR
            width: container.artR * 2
            height: container.artR * 2
            z: 20

            property bool hovered: hoverHandler.hovered

            HoverHandler {
                id: hoverHandler
            }

            // Cover Art Image (hidden offscreen source)
            Image {
                id: artImg
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }

            // Circular Mask with layer texture enabled for MultiEffect
            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            // Masked Circular Cover Art via MultiEffect
            MultiEffect {
                id: maskedArt
                anchors.fill: parent
                source: artImg
                maskEnabled: true
                maskSource: artMask
                visible: (artImg.status === Image.Ready || artImg.status === Image.Loading) && root.artUrl !== ""
            }

            // Fallback gradient circle when no album art is available
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: !maskedArt.visible
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a1b2e" }
                    GradientStop { position: 1.0; color: "#0c0d17" }
                }
                border.color: root.c1
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "♫"
                    font.pixelSize: Math.max(12, Math.round(container.artR * 0.95))
                    font.bold: true
                    color: root.c1
                    opacity: 0.85 + 0.15 * Math.sin(container.now * 4)
                }
            }

            // Dark glass overlay for contrast and controls (fades in on hover or pause)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#080914"
                opacity: (artContainer.hovered || !root.isPlaying) ? 0.65 : 0.25
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // ── Controls & Track Info Content Inside the Circle ────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                // Artist Name
                Text {
                    Layout.fillWidth: true
                    text: (root.mArtist || "Media Player").toUpperCase()
                    font.pixelSize: 11
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                // Track Title
                Text {
                    Layout.fillWidth: true
                    text: root.mTitle || "Sin reproducción"
                    font.pixelSize: 10
                    color: root.c1
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    opacity: 0.90
                }

                Item { Layout.fillHeight: true }

                // Interactive Control Buttons Row (Prev | Play/Pause | Next)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    // Previous Button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: prevMouse.containsMouse ? "rgba(0,240,255,0.35)" : "rgba(255,255,255,0.15)"
                        border.color: prevMouse.containsMouse ? root.c1 : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "⏮"
                            font.pixelSize: 12
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playPrev()
                        }
                    }

                    // Play / Pause Central Button
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: playMouse.containsMouse ? root.burst : root.c1 }
                            GradientStop { position: 1.0; color: playMouse.containsMouse ? root.c1 : root.c2 }
                        }
                        border.color: "#ffffff"
                        border.width: 1.5

                        Text {
                            anchors.centerIn: parent
                            text: root.isPlaying ? "⏸" : "▶"
                            font.pixelSize: 17
                            font.bold: true
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePlayPause()
                        }
                    }

                    // Next Button
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: nextMouse.containsMouse ? "rgba(0,240,255,0.35)" : "rgba(255,255,255,0.15)"
                        border.color: nextMouse.containsMouse ? root.c1 : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "⏭"
                            font.pixelSize: 12
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playNext()
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
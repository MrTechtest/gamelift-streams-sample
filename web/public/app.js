// Browser logic for the GameLift Streams sample.
//
// Flow when the user clicks "ゲームを起動":
//   1. Create a GameLiftStreams client bound to the <video>/<audio> elements.
//   2. generateSignalRequest()  -> WebRTC offer (SDP).
//   3. POST it to our backend, which calls StartStreamSession and returns the
//      SDP answer once the stream is ACTIVE.
//   4. processSignalResponse(answer) -> completes the WebRTC connection; frames
//      start rendering into the <video> element.
//   5. attachInput() -> keyboard / mouse / gamepad are forwarded to the game.

// The SDK keeps its RTCPeerConnection private, and input travels over a data
// channel called "inputChannel" that nothing else exposes. Wrapping
// createDataChannel before the SDK runs is the only way to see whether the
// browser is actually putting keystrokes on the wire, which is the one fact
// that separates a client-side problem from a host-side one.
const dataChannels = [];
const origCreateDataChannel = RTCPeerConnection.prototype.createDataChannel;
RTCPeerConnection.prototype.createDataChannel = function (label, opts) {
  const ch = origCreateDataChannel.call(this, label, opts);
  ch.__sent = 0;
  const origSend = ch.send.bind(ch);
  ch.send = (data) => { ch.__sent++; return origSend(data); };
  ch.addEventListener('open', () => console.log('[gls] dataChannel OPEN:', label));
  ch.addEventListener('close', () => console.log('[gls] dataChannel CLOSE:', label));
  ch.addEventListener('error', (e) => console.error('[gls] dataChannel ERROR:', label, e));
  dataChannels.push(ch);
  console.log('[gls] dataChannel created:', label);
  return ch;
};

const els = {
  overlay: document.getElementById('overlay'),
  launch: document.getElementById('launch'),
  status: document.getElementById('status'),
  video: document.getElementById('stream-video'),
  audio: document.getElementById('stream-audio'),
  stage: document.getElementById('stage'),
  stop: document.getElementById('stop'),
  fullscreen: document.getElementById('fullscreen'),
};

let gls = null;
let streamSessionArn = null;

function setStatus(msg, spinning = false) {
  els.status.innerHTML = spinning
    ? `<div class="spinner" style="margin:0 auto 8px"></div>${msg}`
    : msg;
}

// Locate the Web SDK class regardless of the exact global it exposes.
function resolveSdk() {
  if (window.gameliftstreams && window.gameliftstreams.GameLiftStreams) {
    return window.gameliftstreams.GameLiftStreams;
  }
  if (typeof window.GameLiftStreams === 'function') return window.GameLiftStreams;
  return null;
}

async function launch() {
  const SDK = resolveSdk();
  if (!SDK) {
    setStatus('Web SDK が読み込まれていません。public/ に gameliftstreams-*.js を配置してください。');
    return;
  }

  els.launch.disabled = true;
  setStatus('ストリームを準備しています…', true);

  try {
    // SDK log levels are "none" | "debug"; "debug" traces the WebRTC handshake.
    window.gameliftstreams?.setLogLevel?.('debug');

    gls = new SDK({
      videoElement: els.video,
      audioElement: els.audio,
      inputConfiguration: {
        autoKeyboard: true,
        autoMouse: true,
        autoGamepad: true,
        // Do not silently detach when the window blurs (devtools, alt-tab):
        // that is indistinguishable from "input is broken" while debugging.
        trackWindowFocus: false,
      },
      clientConnection: {
        connectionState: (state) => {
          console.log('[gls] connectionState:', state);
          if (state === 'connected') {
            setStatus('');
            els.overlay.classList.add('hidden');
            els.stop.disabled = false;
            els.fullscreen.disabled = false;
            attachInput('connected');
            startDiagnostics();
          } else if (state === 'disconnected' || state === 'failed' || state === 'closed') {
            onDisconnected(state);
          }
        },
        serverDisconnect: (reason) => onDisconnected(`server:${reason}`),
        channelError: (e) => console.error('[gls] channelError', e),
      },
    });

    // 1) WebRTC offer
    const signalRequest = await gls.generateSignalRequest();

    // 2) Ask the backend to start the session and return the answer
    setStatus('ゲームサーバーに接続中…', true);
    const resp = await fetch('/api/stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ signalRequest }),
    });
    if (!resp.ok) {
      const err = await resp.json().catch(() => ({}));
      throw new Error(err.message || err.error || `HTTP ${resp.status}`);
    }
    const { signalResponse, streamSessionArn: arn } = await resp.json();
    streamSessionArn = arn;

    // 3) Complete the WebRTC connection
    setStatus('映像を受信しています…', true);
    await gls.processSignalResponse(signalResponse);

    // connectionState('connected') callback takes over from here.
  } catch (err) {
    console.error(err);
    setStatus(`起動に失敗しました: ${err.message}`);
    els.launch.disabled = false;
    cleanup(false);
  }
}

// attachInput() throws if the stream is not in a state that accepts input.
// Never swallow that: a silent failure looks exactly like "the game is frozen".
function attachInput(why) {
  try {
    gls.attachInput();
    console.log('[gls] attachInput OK (%s)', why);
  } catch (err) {
    console.error('[gls] attachInput FAILED (%s):', why, err);
    setStatus(`入力の接続に失敗しました: ${err.message}`);
  }
}

// Distinguishes "the stream stalled" from "the stream is fine, the game is
// simply idle because no input reaches it". framesDecoded is the deciding
// number: if it keeps climbing, frames are flowing and the problem is input.
let diagTimer = null;

function startDiagnostics() {
  stopDiagnostics();
  let lastFrames = null;
  diagTimer = setInterval(async () => {
    let framesDecoded = null;
    let fps = null;
    try {
      const report = await gls?.getVideoRTCStats?.();
      report?.forEach((s) => {
        if (s.type === 'inbound-rtp' && s.kind === 'video') {
          framesDecoded = s.framesDecoded;
          fps = s.framesPerSecond;
        }
      });
    } catch (err) {
      console.warn('[gls] getVideoRTCStats failed:', err);
    }
    const chans = dataChannels
      .map((c) => `${c.label}[${c.readyState} sent=${c.__sent}]`)
      .join(' ') || '(none)';
    console.log(
      '[gls] video t=%ss fps=%s framesDecoded=%s | inputModule=%s | channels: %s',
      els.video.currentTime.toFixed(2), fps, framesDecoded,
      'GameCastInputModule' in window, chans,
    );
    if (framesDecoded !== null && framesDecoded === lastFrames) {
      console.warn('[gls] no new frames in 2s -> the STREAM is stalled (not input).');
    }
    lastFrames = framesDecoded;
  }, 2000);
}

function stopDiagnostics() {
  if (diagTimer) { clearInterval(diagTimer); diagTimer = null; }
}

// Shows whether the browser sees the key at all, before the SDK forwards it.
window.addEventListener('keydown', (e) => {
  console.log('[gls] keydown seen by browser:', e.code, 'target=', e.target?.tagName);
}, true);

function onDisconnected(reason) {
  console.warn('disconnected:', reason);
  setStatus(`ストリームが切断されました (${reason})。もう一度起動できます。`);
  els.overlay.classList.remove('hidden');
  els.launch.disabled = false;
  els.stop.disabled = true;
  els.fullscreen.disabled = true;
}

async function stop() {
  setStatus('停止しています…');
  await cleanup(true);
  els.overlay.classList.remove('hidden');
  els.launch.disabled = false;
  els.stop.disabled = true;
  els.fullscreen.disabled = true;
  setStatus('');
}

async function cleanup(terminateRemote) {
  stopDiagnostics();
  try { gls?.detachInput?.(); } catch {}
  try { gls?.close?.(); } catch {}
  gls = null;
  if (terminateRemote && streamSessionArn) {
    try {
      await fetch('/api/stream/terminate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ streamSessionArn }),
      });
    } catch {}
  }
  streamSessionArn = null;
}

// Re-focus input when the user clicks the video (browsers require a gesture).
els.stage.addEventListener('click', () => { if (gls) attachInput('stage click'); });
els.fullscreen.addEventListener('click', () => els.stage.requestFullscreen?.());
els.stop.addEventListener('click', stop);
els.launch.addEventListener('click', launch);
window.addEventListener('beforeunload', () => cleanup(true));

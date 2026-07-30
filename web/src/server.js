// Minimal backend for the Amazon GameLift Streams sample web app.
//
// It exposes two endpoints the browser calls:
//   POST /api/stream            -> starts a stream session, returns the SDP answer
//   POST /api/stream/terminate  -> ends a stream session
//
// The browser generates a WebRTC "offer" (SignalRequest) with the GameLift
// Streams Web SDK; this server forwards it to StartStreamSession, polls
// GetStreamSession until the stream is ACTIVE, and returns the "answer"
// (SignalResponse) for the browser to complete the WebRTC connection.

import express from 'express';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  GameLiftStreamsClient,
  StartStreamSessionCommand,
  GetStreamSessionCommand,
  TerminateStreamSessionCommand,
} from '@aws-sdk/client-gameliftstreams';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const REGION = process.env.AWS_REGION || 'ap-northeast-1';
const STREAM_GROUP_ID = process.env.STREAM_GROUP_ID;
const APPLICATION_ID = process.env.APPLICATION_ID;
const LOCATIONS = (process.env.STREAM_LOCATIONS || REGION)
  .split(',').map((s) => s.trim()).filter(Boolean);
const PORT = Number(process.env.PORT || 8000);

if (!STREAM_GROUP_ID || !APPLICATION_ID) {
  console.error('ERROR: set STREAM_GROUP_ID and APPLICATION_ID in web/.env');
  process.exit(1);
}

const client = new GameLiftStreamsClient({ region: REGION });
const app = express();
app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(__dirname, '..', 'public')));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Start a stream session and wait for the SDP answer.
app.post('/api/stream', async (req, res) => {
  const signalRequest = req.body?.signalRequest;
  if (!signalRequest) {
    return res.status(400).json({ error: 'missing signalRequest' });
  }
  try {
    const start = await client.send(new StartStreamSessionCommand({
      Identifier: STREAM_GROUP_ID,
      ApplicationIdentifier: APPLICATION_ID,
      Protocol: 'WebRTC',
      SignalRequest: signalRequest,
      Locations: LOCATIONS,
      ConnectionTimeoutSeconds: 300,
    }));

    const arn = start.Arn;
    let signalResponse = start.SignalResponse || null;
    let status = start.Status;

    // Poll until the stream server produces the answer (status ACTIVE).
    const deadline = Date.now() + 120_000;
    while (!signalResponse && Date.now() < deadline) {
      if (status === 'ERROR' || status === 'TERMINATED') {
        return res.status(502).json({ error: `stream ${status}`, reason: status });
      }
      await sleep(1000);
      const get = await client.send(new GetStreamSessionCommand({
        Identifier: STREAM_GROUP_ID,
        StreamSessionIdentifier: arn,
      }));
      status = get.Status;
      signalResponse = get.SignalResponse || null;
    }

    if (!signalResponse) {
      return res.status(504).json({ error: 'timed out waiting for stream to become ACTIVE' });
    }

    res.json({ streamSessionArn: arn, signalResponse });
  } catch (err) {
    console.error('StartStreamSession failed:', err);
    res.status(500).json({ error: err.name || 'error', message: err.message });
  }
});

// End a stream session.
app.post('/api/stream/terminate', async (req, res) => {
  const arn = req.body?.streamSessionArn;
  if (!arn) return res.status(400).json({ error: 'missing streamSessionArn' });
  try {
    await client.send(new TerminateStreamSessionCommand({
      Identifier: STREAM_GROUP_ID,
      StreamSessionIdentifier: arn,
    }));
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.name, message: err.message });
  }
});

app.get('/healthz', (_req, res) => res.json({ ok: true, region: REGION }));

app.listen(PORT, () => {
  console.log(`GameLift Streams sample web app on http://localhost:${PORT}`);
  console.log(`  region=${REGION} streamGroup=${STREAM_GROUP_ID} app=${APPLICATION_ID}`);
});

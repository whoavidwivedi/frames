const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.PORT || 3000;
const PUBLIC_DIR = path.join(__dirname, 'public');
const DATA_DIR = path.join(__dirname, 'data');
const DB_FILE = path.join(DATA_DIR, 'analytics.json');
const FEEDBACK_FILE = path.join(DATA_DIR, 'feedback.json');
const DMG_PATH = path.join(PUBLIC_DIR, 'downloads', 'Frames-AppleSilicon.dmg');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// In-memory analytics state backed by JSON persistence
let analytics = {
  uniqueVisitors: 0,
  totalPageViews: 0,
  totalDownloads: 0,
  uniqueDownloads: 0,
  visitorUuids: {},      // uuid -> first_seen timestamp
  visitorHashes: {},     // ip_ua_hash -> first_seen timestamp
  downloadUuids: {},     // uuid -> download count
  downloadHashes: {},    // ip_ua_hash -> download count
  dailyVisits: {},       // YYYY-MM-DD -> { unique, total }
  dailyDownloads: {}     // YYYY-MM-DD -> { unique, total }
};

// Load existing analytics
if (fs.existsSync(DB_FILE)) {
  try {
    const raw = fs.readFileSync(DB_FILE, 'utf8');
    analytics = { ...analytics, ...JSON.parse(raw) };
  } catch (err) {
    console.error('Failed to parse analytics.json, initializing fresh store:', err.message);
  }
}

function saveAnalytics() {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(analytics, null, 2), 'utf8');
  } catch (err) {
    console.error('Failed to persist analytics:', err.message);
  }
}

// Debounced save
let saveTimer = null;
function scheduleSave() {
  if (saveTimer) return;
  saveTimer = setTimeout(() => {
    saveTimer = null;
    saveAnalytics();
  }, 1000);
}

// Save on exit
process.on('SIGINT', () => { saveAnalytics(); process.exit(0); });
process.on('SIGTERM', () => { saveAnalytics(); process.exit(0); });

function getClientFingerprintHash(req) {
  const forwarded = req.headers['x-forwarded-for'];
  const ip = forwarded ? forwarded.split(',')[0].trim() : (req.socket.remoteAddress || '127.0.0.1');
  const ua = req.headers['user-agent'] || 'unknown';
  const acceptLang = req.headers['accept-language'] || '';
  // Salt with a fixed system salt for privacy
  return crypto.createHash('sha256').update(`${ip}::${ua}::${acceptLang}::frames-privacy-salt`).digest('hex');
}

function getTodayKey() {
  return new Date().toISOString().slice(0, 10);
}

// MIME types table
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.dmg': 'application/x-apple-diskimage',
  '.mp4': 'video/mp4',
  '.woff2': 'font/woff2'
};

const server = http.createServer((req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = decodeURIComponent(parsedUrl.pathname);

  // Enable CORS for local testing if needed
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Visitor-Id');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // API 1: Track Visit (Deduplicated Unique Visitor Tracking)
  if (pathname === '/api/track-visit' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      let data = {};
      try { data = JSON.parse(body || '{}'); } catch (_) {}

      const clientUuid = (data.visitorId || req.headers['x-visitor-id'] || '').trim();
      const ipUaHash = getClientFingerprintHash(req);
      const today = getTodayKey();
      const now = new Date().toISOString();

      if (!analytics.dailyVisits[today]) {
        analytics.dailyVisits[today] = { unique: 0, total: 0 };
      }

      analytics.totalPageViews += 1;
      analytics.dailyVisits[today].total += 1;

      // Unique detection rule:
      // If clientUuid is known OR ipUaHash is known, it is NOT a new unique visitor.
      const isKnownUuid = clientUuid && analytics.visitorUuids[clientUuid];
      const isKnownHash = analytics.visitorHashes[ipUaHash];

      let isNewUnique = false;
      if (!isKnownUuid && !isKnownHash) {
        analytics.uniqueVisitors += 1;
        analytics.dailyVisits[today].unique += 1;
        isNewUnique = true;
      }

      // Record / update timestamps
      if (clientUuid) {
        analytics.visitorUuids[clientUuid] = analytics.visitorUuids[clientUuid] || now;
      }
      analytics.visitorHashes[ipUaHash] = analytics.visitorHashes[ipUaHash] || now;

      scheduleSave();

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        isNewUnique,
        uniqueVisitors: analytics.uniqueVisitors,
        totalPageViews: analytics.totalPageViews,
        totalDownloads: analytics.totalDownloads,
        uniqueDownloads: analytics.uniqueDownloads
      }));
    });
    return;
  }

  // API 2: Public Live Stats
  if (pathname === '/api/stats' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache'
    });
    res.end(JSON.stringify({
      uniqueVisitors: analytics.uniqueVisitors,
      totalPageViews: analytics.totalPageViews,
      totalDownloads: analytics.totalDownloads,
      uniqueDownloads: analytics.uniqueDownloads,
      today: getTodayKey()
    }));
    return;
  }

  // API 3: Track Download Beacon
  if (pathname === '/api/track-download' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      let data = {};
      try { data = JSON.parse(body || '{}'); } catch (_) {}

      const clientUuid = (data.visitorId || req.headers['x-visitor-id'] || '').trim();
      const ipUaHash = getClientFingerprintHash(req);
      const today = getTodayKey();

      if (!analytics.dailyDownloads[today]) {
        analytics.dailyDownloads[today] = { unique: 0, total: 0 };
      }

      analytics.totalDownloads += 1;
      analytics.dailyDownloads[today].total += 1;

      const isKnownDlUuid = clientUuid && analytics.downloadUuids[clientUuid];
      const isKnownDlHash = analytics.downloadHashes[ipUaHash];

      let isNewUniqueDownload = false;
      if (!isKnownDlUuid && !isKnownDlHash) {
        analytics.uniqueDownloads += 1;
        analytics.dailyDownloads[today].unique += 1;
        isNewUniqueDownload = true;
      }

      if (clientUuid) {
        analytics.downloadUuids[clientUuid] = (analytics.downloadUuids[clientUuid] || 0) + 1;
      }
      analytics.downloadHashes[ipUaHash] = (analytics.downloadHashes[ipUaHash] || 0) + 1;

      scheduleSave();

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        isNewUniqueDownload,
        totalDownloads: analytics.totalDownloads,
        uniqueDownloads: analytics.uniqueDownloads
      }));
    });
    return;
  }

  // API 4: Direct Download Endpoint (Streams the actual DMG and counts download)
  if (pathname === '/download' || pathname === '/download/Frames-AppleSilicon.dmg') {
    if (!fs.existsSync(DMG_PATH)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('DMG file not found. Please build with packaging/build_dmg.sh first.');
      return;
    }

    // Track download directly
    const ipUaHash = getClientFingerprintHash(req);
    const clientUuid = (req.headers['x-visitor-id'] || '').trim();
    const today = getTodayKey();

    if (!analytics.dailyDownloads[today]) {
      analytics.dailyDownloads[today] = { unique: 0, total: 0 };
    }
    analytics.totalDownloads += 1;
    analytics.dailyDownloads[today].total += 1;

    const isKnownDlUuid = clientUuid && analytics.downloadUuids[clientUuid];
    const isKnownDlHash = analytics.downloadHashes[ipUaHash];

    if (!isKnownDlUuid && !isKnownDlHash) {
      analytics.uniqueDownloads += 1;
      analytics.dailyDownloads[today].unique += 1;
    }
    if (clientUuid) {
      analytics.downloadUuids[clientUuid] = (analytics.downloadUuids[clientUuid] || 0) + 1;
    }
    analytics.downloadHashes[ipUaHash] = (analytics.downloadHashes[ipUaHash] || 0) + 1;
    scheduleSave();

    const stat = fs.statSync(DMG_PATH);
    res.writeHead(200, {
      'Content-Type': 'application/x-apple-diskimage',
      'Content-Disposition': 'attachment; filename="Frames-v1.1.0-AppleSilicon.dmg"',
      'Content-Length': stat.size,
      'Cache-Control': 'no-cache'
    });

    const stream = fs.createReadStream(DMG_PATH);
    stream.pipe(res);
    return;
  }

  // API 5: Feedback Submissions
  if (pathname === '/api/feedback' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      let data = {};
      try { data = JSON.parse(body || '{}'); } catch (_) {}

      const name = (data.name || 'Anonymous').trim();
      const email = (data.email || '').trim();
      const message = (data.message || '').trim();
      const feedbackType = (data.type || 'general').trim();

      if (!message) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Message cannot be empty.' }));
        return;
      }

      let feedbacks = [];
      if (fs.existsSync(FEEDBACK_FILE)) {
        try {
          feedbacks = JSON.parse(fs.readFileSync(FEEDBACK_FILE, 'utf8'));
        } catch (_) { feedbacks = []; }
      }

      const entry = {
        id: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        name,
        email,
        type: feedbackType,
        message,
        ipHash: getClientFingerprintHash(req)
      };

      feedbacks.push(entry);
      fs.writeFileSync(FEEDBACK_FILE, JSON.stringify(feedbacks, null, 2), 'utf8');

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        message: 'Feedback recorded successfully. Thank you!'
      }));
    });
    return;
  }

  // Static File Serving
  let relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\//, '');
  let filePath = path.join(PUBLIC_DIR, relativePath);

  // Security check: prevent directory traversal
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Access Forbidden');
    return;
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      // Serve custom 404
      const custom404 = path.join(PUBLIC_DIR, '404.html');
      if (fs.existsSync(custom404)) {
        res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
        fs.createReadStream(custom404).pipe(res);
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('404 Not Found');
      }
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stats.size,
      'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600'
    });

    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`=======================================================`);
  console.log(`  Frames Distribution Website Running on Localhost!`);
  console.log(`  URL: http://localhost:${PORT}`);
  console.log(`  DMG Direct: http://localhost:${PORT}/download`);
  console.log(`=======================================================`);
});

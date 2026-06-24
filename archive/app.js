const http = require('http');
const os = require('os');

const APP = process.env.APP_NAME || 'unknown';
let healthy = true;

http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(healthy ? 200 : 500);
    return res.end(healthy ? 'ok\n' : 'broken\n');
  }
  if (req.url === '/break') {
    healthy = false;
    return res.end(`pod=${os.hostname()} will now fail readiness\n`);
  }
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(`app=${APP} pod=${os.hostname()}\n`);
}).listen(3000, '0.0.0.0', () => console.log(`${APP} listening on 0.0.0.0:3000`));

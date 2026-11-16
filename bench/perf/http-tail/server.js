// Node: same work as the Manuscript and Go servers.
const http = require("http");
const SPIN = parseInt(process.env.SPIN || "1000000");
const port = parseInt(process.argv[2] || "8082");
http.createServer((req, res) => {
  let spun = 0;
  if (req.url.startsWith("/slow")) { let x = 1; for (let i = 0; i < SPIN; i++) x = (x * 31 + i) % 1000003; spun = x; }
  const items = [];
  const count = req.url.startsWith("/big") ? 4096 : 64;
  for (let i = 0; i < count; i++) items.push({ id: i, name: "item-" + i });
  const body = JSON.stringify({ path: req.url, spun, items });
  res.writeHead(200, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
  res.end(body);
}).listen(port, "127.0.0.1");

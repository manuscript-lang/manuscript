import http from 'node:http';
const server = http.createServer(async (req, res) => {
  res.setHeader('X-Example', 'reference');
  const url = new URL(req.url, 'http://localhost');
  const json = value => {res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(value));};
  if (url.pathname.startsWith('/hello/') && ['GET', 'HEAD'].includes(req.method)) {
    json({message: `Hello, ${decodeURIComponent(url.pathname.slice(7))}`});
  } else if (url.pathname === '/echo' && req.method === 'POST') {
    let size = 0; const chunks = [];
    try {
      for await (const chunk of req) {size += chunk.length; if (size > 4096) throw Error('limit'); chunks.push(chunk);}
      const value = JSON.parse(Buffer.concat(chunks));
      if (typeof value.name !== 'string' || Object.keys(value).length !== 1) throw Error('shape');
      json({message: `Hello, ${value.name}`});
    } catch {res.statusCode = 400; res.end('Invalid JSON');}
  } else if (url.pathname === '/events' && req.method === 'GET') {
    res.setHeader('Content-Type', 'text/event-stream');
    res.write('data: one\n\n'); setTimeout(() => res.end('data: two\n\n'), 10);
  } else if (url.pathname === '/' && ['GET', 'HEAD'].includes(req.method)) {
    res.setHeader('Content-Type', 'text/html'); res.end('<h1>Hello</h1>');
  } else {res.statusCode = 404; res.end('Not found');}
});
server.listen(Number(process.env.PORT || 19801), '127.0.0.1');
process.on('SIGTERM', () => server.close());

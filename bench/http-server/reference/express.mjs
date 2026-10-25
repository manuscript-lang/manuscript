import express from 'express';
const app = express();
app.use((req, res, next) => {res.set('X-Example', 'reference'); next();});
app.use(express.json({limit: 4096, strict: true}));
app.get('/hello/:name', (req, res) => res.json({message: `Hello, ${req.params.name}`}));
app.post('/echo', (req, res) => {
  if (!req.body || typeof req.body.name !== 'string' || Object.keys(req.body).length !== 1) return res.status(400).send('Invalid JSON');
  res.json({message: `Hello, ${req.body.name}`});
});
app.get('/events', (req, res) => {res.type('text/event-stream'); res.write('data: one\n\n'); setTimeout(() => res.end('data: two\n\n'), 10);});
app.get('/', (req, res) => res.type('html').send('<h1>Hello</h1>'));
app.use((error, req, res, next) => res.status(400).send('Invalid JSON'));
const server = app.listen(Number(process.env.PORT || 19802), '127.0.0.1');
process.on('SIGTERM', () => server.close());

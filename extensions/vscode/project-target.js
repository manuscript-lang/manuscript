const fs = require('node:fs/promises');
const path = require('node:path');

async function targetFor(file) {
  for (let dir = path.dirname(file); ; dir = path.dirname(dir)) {
    const manifest = path.join(dir, 'ms.toml');
    try { await fs.access(manifest); return manifest; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (path.dirname(dir) === dir) return file;
  }
}

module.exports = { targetFor };

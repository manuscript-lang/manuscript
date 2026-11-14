const { Worker, isMainThread, parentPort, workerData } = require("node:worker_threads");
const fs = require("node:fs");
const path = require("node:path");

function summarize(file) {
  const s = { lines: 0, latency: 0, c: [0, 0, 0, 0] };
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (line === "") continue;
    const f = line.split(" ");
    s.lines++;
    s.latency += parseInt(f[5], 10) || 0;
    s.c[Math.min(f[4].charCodeAt(0) - 50, 3)]++;
  }
  return s;
}

function collect(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) collect(p, out); else out.push(p);
  }
}

if (!isMainThread) {
  const t = { lines: 0, latency: 0, c: [0, 0, 0, 0] };
  for (let i = workerData.w; i < workerData.files.length; i += 4) {
    const s = summarize(workerData.files[i]);
    t.lines += s.lines; t.latency += s.latency;
    for (let k = 0; k < 4; k++) t.c[k] += s.c[k];
  }
  parentPort.postMessage(t);
} else {
  const files = [];
  collect(process.argv[2], files);
  Promise.all([0, 1, 2, 3].map((w) => new Promise((resolve, reject) => {
    const worker = new Worker(__filename, { workerData: { w, files } });
    worker.on("message", resolve);
    worker.on("error", reject);
  }))).then((parts) => {
    const t = { lines: 0, latency: 0, c: [0, 0, 0, 0] };
    for (const s of parts) {
      t.lines += s.lines; t.latency += s.latency;
      for (let k = 0; k < 4; k++) t.c[k] += s.c[k];
    }
    console.log(`files: ${files.length}`);
    console.log(`lines: ${t.lines}`);
    console.log(`status: 2xx=${t.c[0]} 3xx=${t.c[1]} 4xx=${t.c[2]} 5xx=${t.c[3]}`);
    console.log(`latency: ${t.latency}`);
  });
}

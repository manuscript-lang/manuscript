const os = require("node:os");
const { Worker, isMainThread, parentPort, workerData } = require("node:worker_threads");

function chunkChecksum(chunk) {
  const hist = new Array(256).fill(0);
  let x = chunk * 7919 + 1;
  let h = 0;
  for (let i = 0; i < 200000; i++) {
    x = (x * 48271) % 2147483647;
    hist[x % 256]++;
    h = (h * 31 + x) % 1000000007;
  }
  for (let b = 0; b < 256; b++) h = (h * 131 + hist[b]) % 1000000007;
  return h;
}

if (!isMainThread) {
  let t = 0;
  for (let c = workerData.first; c < 128; c += workerData.step) t += chunkChecksum(c);
  parentPort.postMessage(t);
} else {
  // One worker thread per core, each taking every n-th chunk.
  const n = os.availableParallelism();
  const parts = Array.from({ length: n }, (_, w) => new Promise((resolve, reject) => {
    const worker = new Worker(__filename, { workerData: { first: w, step: n } });
    worker.on("message", resolve);
    worker.on("error", reject);
  }));
  Promise.all(parts).then((r) => console.log(`chunks 128 checksum ${r.reduce((a, b) => a + b, 0)}`));
}

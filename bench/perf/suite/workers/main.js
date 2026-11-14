const { Worker, isMainThread, parentPort, workerData } = require("node:worker_threads");

function countPrimes(lo, hi) {
  let count = 0;
  for (let n = lo; n < hi; n++) {
    if (n < 2) continue;
    let isPrime = true;
    for (let d = 2; d * d <= n; d++) if (n % d === 0) { isPrime = false; break; }
    if (isPrime) count++;
  }
  return count;
}

const small = (i) => { let t = 0; for (let k = 0; k < 200; k++) t += (i + k) % 7; return t; };

if (!isMainThread) {
  parentPort.postMessage(countPrimes(workerData.lo, workerData.hi));
} else {
  // Worker threads for the CPU-bound chunks; the small tasks run as promises on the one main thread
  // (Node has no cheaper way to spread them).
  const chunks = Array.from({ length: 16 }, (_, c) => new Promise((resolve, reject) => {
    const w = new Worker(__filename, { workerData: { lo: c * 250000, hi: c * 250000 + 250000 } });
    w.on("message", resolve);
    w.on("error", reject);
  }));
  Promise.all(chunks).then(async (counts) => {
    const primes = counts.reduce((a, b) => a + b, 0);
    const many = Array.from({ length: 100000 }, (_, i) => Promise.resolve().then(() => small(i)));
    const total = (await Promise.all(many)).reduce((a, b) => a + b, 0);
    console.log(`primes ${primes} small ${total}`);
  });
}

function heat(n, steps) {
  let a = new Float64Array(n * n), b = new Float64Array(n * n);
  for (let i = 0; i < n * n; i++) if (i % 97 === 0) a[i] = 100.0;
  for (let s = 0; s < steps; s++) {
    for (let y = 1; y < n - 1; y++) {
      for (let x = 1; x < n - 1; x++) {
        const i = y * n + x;
        b[i] = a[i] + 0.2 * (a[i - 1] + a[i + 1] + a[i - n] + a[i + n] - 4.0 * a[i]);
      }
    }
    a.set(b);
  }
  let total = 0.0;
  for (const v of a) total += v;
  return Math.trunc(total * 1000.0);
}

function mandelbrot(size, limit) {
  let inside = 0, work = 0;
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      const cr = (px * 3.0) / size - 2.0;
      const ci = (py * 2.0) / size - 1.0;
      let zr = 0.0, zi = 0.0, k = 0;
      while (k < limit && zr * zr + zi * zi <= 4.0) {
        const t = zr * zr - zi * zi + cr;
        zi = 2.0 * zr * zi + ci;
        zr = t;
        k++;
      }
      work += k;
      if (k === limit) inside++;
    }
  }
  return inside * 1000003 + (work % 1000003);
}

function norms(count) {
  let total = 0.0;
  for (let i = 1; i < count; i++) total += Math.sqrt(i * i + 3.0);
  return Math.trunc(total);
}

console.log(`heat ${heat(500, 120)}`);
console.log(`mandelbrot ${mandelbrot(700, 200)}`);
console.log(`norms ${norms(20000000)}`);

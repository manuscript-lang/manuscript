// Number Functions

export const abs = Math.abs;
export const min = Math.min;
export const max = Math.max;
export const floor = Math.floor;
export const ceil = Math.ceil;
export const round = Math.round;
export const sqrt = Math.sqrt;
export const pow = Math.pow;

export function clamp(n: number, lo: number, hi: number): number {
  return Math.min(Math.max(n, lo), hi);
}

export function random(): number {
  return Math.random();
}

export function random_int(minVal: number, maxVal: number): number {
  return Math.floor(Math.random() * (maxVal - minVal + 1)) + minVal;
}

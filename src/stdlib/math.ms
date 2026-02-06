// std/math - Mathematical functions

extern fn sqrt(n: number): number
extern fn pow(base: number, exp: number): number
extern fn floor(n: number): number
extern fn ceil(n: number): number
extern fn round(n: number): number
extern fn random(): number
extern fn random_int(min: number, max: number): number

fn abs(n: number): number
  if n < 0 then -n else n

fn min(a: number, b: number): number
  if a < b then a else b

fn max(a: number, b: number): number
  if a > b then a else b

fn clamp(n: number, lo: number, hi: number): number
  min(max(n, lo), hi)

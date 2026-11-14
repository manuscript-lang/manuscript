// Float simulation: a heat-diffusion stencil on a flat grid, then a Mandelbrot
// escape-time count.
import sqrt from "@std/math/math.ms"

fn heat(n: Int, steps: Int) Int:
	var a = List[Float]()
	var b = List[Float]()

	for i in 0..n * n:
		a.append(if i % 97 == 0: 100.0 else: 0.0)
		b.append(0.0)

	for s in 0..steps:
		for y in 1..n - 1:
			for x in 1..n - 1:
				i := y * n + x
				b[i] = (
					a[i]
					+ 0.2 * (
						a[i - 1]
						+ a[i + 1]
						+ a[i - n]
						+ a[i + n]
						- 4.0 * a[i]
					)
				)

		for i in 0..n * n:
			a[i] = b[i]

	var total = 0.0
	for v in a:
		total += v
	return (total * 1000.0).truncate_to_int().get(0)

fn mandelbrot(size: Int, limit: Int) Int:
	var inside = 0
	var work = 0

	for py in 0..size:
		for px in 0..size:
			cr := px.to_float() * 3.0 / size.to_float() - 2.0
			ci := py.to_float() * 2.0 / size.to_float() - 1.0
			var zr = 0.0
			var zi = 0.0
			var k = 0

			while k < limit and zr * zr + zi * zi <= 4.0:
				t := zr * zr - zi * zi + cr
				zi = 2.0 * zr * zi + ci
				zr = t
				k += 1

			work += k
			if k == limit: inside += 1

	return inside * 1000003 + work % 1000003

fn norms(count: Int) Int:
	var total = 0.0

	for i in 1..count:
		f := i.to_float()
		total += sqrt(f * f + 3.0)

	return (total).truncate_to_int().get(0)

fn main() Unit:
	print("heat {heat(500, 120)}")
	print("mandelbrot {mandelbrot(700, 200)}")
	print("norms {norms(20000000)}")

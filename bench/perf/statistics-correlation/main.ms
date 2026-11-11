import (
	stdout from "@std/io/io.ms",
	correlation, linear_regression from "@std/math/statistics.ms",
	monotonic from "@std/time.ms",
)

fn say(text: String) Unit:
	_ignored := stdout().write(text)

fn series(n: Int, f: fn(Int) Float) List[Float]:
	var out: List[Float] = []
	for i in 0..n:
		out.append(f(i))
	return out

fn run_corr(name: String, xs: List[Float], ys: List[Float], reps: Int) Unit:
	var sum = 0.0
	t := monotonic()
	for rep in 0..reps:
		sum += correlation(xs, ys).get(0.0) + rep.to_float() * 0.0

	ns := monotonic().difference(t).to_nanoseconds()
	say("corr {name} n={xs.length()} {ns / reps}ns {sum / reps.to_float()}\n")

fn run_reg(name: String, xs: List[Float], ys: List[Float], reps: Int) Unit:
	var sum = 0.0
	t := monotonic()
	for rep in 0..reps:
		if r := linear_regression(xs, ys):
			sum += r.slope + r.intercept

	ns := monotonic().difference(t).to_nanoseconds()
	say("reg  {name} n={xs.length()} {ns / reps}ns {sum / reps.to_float()}\n")

fn both(name: String, xs: List[Float], ys: List[Float]) Unit:
	reps := 400000 / xs.length() + 20
	run_corr(name, xs, ys, reps)
	run_reg(name, xs, ys, reps)

fn cases(n: Int) Unit:
	both(
		"broad-perfect", series(n, fn i: (i % 17 + 1).to_float()),
		series(n, fn i: (2.0 * (i % 17 + 1).to_float() + 1.0))
	)
	both(
		"broad-centered", series(n, fn i: (i % 17 - 8).to_float()),
		series(n, fn i: ((i * 7) % 13 - 6).to_float())
	)
	both(
		"broad-noisy", series(n, fn i: (i % 17 + 1).to_float()),
		series(n, fn i: ((i * 7) % 13 + 1).to_float())
	)
	both(
		"orthogonal", series(n, fn i: if i % 2 == 0: 1.0 else: -1.0),
		series(n, fn i: if i % 4 < 2: 1.0 else: -1.0)
	)
	both("const-x", series(n, fn i: 3.0), series(n, fn i: (i % 17 + 1).to_float()))
	both("const-y", series(n, fn i: (i % 17 + 1).to_float()), series(n, fn i: 3.0))
	both("const-both", series(n, fn i: 0.0), series(n, fn i: 1.0))
	both(
		"price-narrow", series(n, fn i: 100.0 + ((i % 17 - 8).to_float()) * 0.01),
		series(n, fn i: (50.0 + ((i * 7) % 13).to_float() * 0.01))
	)
	both(
		"timestamps", series(n, fn i: 1000000000.0 + i.to_float()),
		series(n, fn i: (i % 17).to_float())
	)
	both(
		"offset-1e16", series(n, fn i: 1e16 + 2.0 * (i % 3).to_float()),
		series(n, fn i: (i % 3).to_float())
	)
	both(
		"tiny", series(n, fn i: (i % 17 + 1).to_float() * 1e-200),
		series(n, fn i: (((i * 7) % 13 + 1).to_float() * 1e-200))
	)
	both(
		"large", series(n, fn i: (i % 17 + 1).to_float() * 1e200),
		series(n, fn i: (((i * 7) % 13 + 1).to_float() * 1e200))
	)

fn timestamp_controls() Unit:
	// Short epoch-second series whose plain result is already exact.
	xs := series(10, fn i: 1000000000.0 + i.to_float())
	both("ts-same", xs, series(10, fn i: 1000000000.0 + i.to_float()))
	both("ts-reversed", xs, series(10, fn i: 1000000009.0 - i.to_float()))
	both("ts-line", xs, series(10, fn i: 2.0 * i.to_float() + 1.0))

export fn main() Int:
	timestamp_controls()
	cases(10)
	cases(1000)
	return 0

// `a.min(b)` and `a.clamp(low, high)` against the same comparison written with `if`; both should cost the same.
bench "ordering.min_method" per 1000000 {
	var total = 0
	for i in 0..1000000 {
		total += ((i * 7919) % 10007).min(5000)
	}
	total
}

bench "ordering.min_if" per 1000000 {
	var total = 0

	for i in 0..1000000 {
		value := (i * 7919) % 10007

		if value < 5000 {
			total += value
		} else {
			total += 5000
		}
	}

	total
}

bench "ordering.clamp_method" per 1000000 {
	var total = 0
	for i in 0..1000000 {
		total += ((i * 7919) % 10007).clamp(2000, 8000)
	}
	total
}

bench "ordering.clamp_if" per 1000000 {
	var total = 0

	for i in 0..1000000 {
		value := (i * 7919) % 10007

		if value < 2000 {
			total += 2000
		} else if value > 8000 {
			total += 8000
		} else {
			total += value
		}
	}

	total
}

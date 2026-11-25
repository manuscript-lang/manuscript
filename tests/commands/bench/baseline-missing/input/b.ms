bench "loop" {
	var s = 0
	for i in 0..10 {
		s += i
	}
	print(s)
}

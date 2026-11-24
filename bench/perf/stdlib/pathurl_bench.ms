import (
	sin, sqrt from "@std/math/math.ms",
	encode_component, parse from "@std/net/url.ms",
	basename, join, normalize from "@std/os/path.ms",
)

bench "path.join_normalize" per 50000 {
	var n = 0
	for i in 0..50000 {
		n += (
			join(["/a", "b/../c", "d.txt"])
			| normalize
			| .length()
		)
	}
	n
}

bench "path.basename" per 100000 {
	var n = 0
	for i in 0..100000 {
		n += basename("/a/b/c/file.txt").length()
	}
	n
}

bench "url.parse" per 20000 {
	address := "https://example.com:8080/a/b?x=1&y=2#frag"
	var n = 0
	for i in 0..20000 {
		if parse(address).is_ok() { n += 1 }
	}
	n
}

bench "url.encode_component" per 50000 {
	var n = 0
	for i in 0..50000 {
		n += encode_component("a b&c=d/é").length()
	}
	n
}

bench "math.sqrt_sin" per 1000000 {
	var acc = 0.0
	for i in 0..1000000 {
		acc += sqrt(2.0) + sin(1.0)
	}
	acc.truncate_to_int() or 0
}

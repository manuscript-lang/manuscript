// LZ77 compress and decompress round trip over generated text-like bytes: flat tables,
// byte lists, match copies.
fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn make_input(n: Int) List[Int]:
	var vocab: List[List[Int]] = []
	var x = 17

	for w in 0..200:
		var word: List[Int] = []
		x = lcg(x)

		for k in 0..(3 + x / 11 % 8):
			x = lcg(x)
			word.append(97 + x / 13 % 26)

		vocab.append(word)

	var out: List[Int] = []

	while out.length() < n:
		x = lcg(x)
		out.extend(vocab[x / 17 % 200])
		out.append(32)

	return out

// Tokens: a literal is one byte (0..255); a match is two entries, 256 + length then
// distance.
fn compress(data: List[Int]) List[Int]:
	var head: List[Int] = []
	for i in 0..65536:
		head.append(-1)

	var out: List[Int] = []
	n := data.length()
	var i = 0

	while i < n:
		var best = 0
		var dist = 0

		if i + 3 <= n:
			h := (data[i] * 506832829 + data[i + 1] * 65599 + data[i + 2]) % 65536
			cand := head[h]
			head[h] = i

			if cand >= 0 and i - cand < 32768:
				var len = 0
				while i + len < n and len < 255 and data[cand + len] == data[i + len]:
					len += 1

				if len >= 3:
					best = len
					dist = i - cand

		if best >= 3:
			out.append(256 + best)
			out.append(dist)
			i += best
		else:
			out.append(data[i])
			i += 1

	return out

fn decompress(tokens: List[Int]) List[Int]:
	var out: List[Int] = []
	var i = 0

	while i < tokens.length():
		t := tokens[i]

		if t < 256:
			out.append(t)
			i += 1
		else:
			len := t - 256
			start := out.length() - tokens[i + 1]
			for k in 0..len:
				out.append(out[start + k])
			i += 2

	return out

fn main() Unit:
	data := make_input(4000000)
	var checksum = 0

	for pass in 0..3:
		packed := compress(data)
		unpacked := decompress(packed)
		if unpacked != data: print("MISMATCH")
		checksum += packed.length()

	print("input {data.length()} tokens {checksum}")

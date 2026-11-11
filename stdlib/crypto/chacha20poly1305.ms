import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	constant_time_equal from "@std/crypto.ms",
	bit_and,
	bit_not,
	bit_or,
	bit_xor,
	shift_left,
	shift_right,
	shift_right_unsigned from "@std/math/math.ms",
)

fn rotl32(value: Int, count: Int) Int:
	return bit_and(
		bit_or(
			shift_left(value, count),
			shift_right_unsigned(value, 32 - count),
		),
		4294967295,
	)

fn le32(data: Bytes, at: Int) Int:
	var value = 0
	for offset in 0..4:
		value = bit_or(value, shift_left(data.get(at + offset).to_int(), 8 * offset))
	return value

fn quarter(var state: List[Int], a: Int, b: Int, c: Int, d: Int) Unit:
	var va = state[a]
	var vb = state[b]
	var vc = state[c]
	var vd = state[d]
	va = bit_and(va + vb, 4294967295)
	vd = rotl32(bit_xor(vd, va), 16)
	vc = bit_and(vc + vd, 4294967295)
	vb = rotl32(bit_xor(vb, vc), 12)
	va = bit_and(va + vb, 4294967295)
	vd = rotl32(bit_xor(vd, va), 8)
	vc = bit_and(vc + vd, 4294967295)
	vb = rotl32(bit_xor(vb, vc), 7)
	state.set(a, va)
	state.set(b, vb)
	state.set(c, vc)
	state.set(d, vd)

// One 64-byte ChaCha20 keystream block (RFC 8439) for a 32-byte key, 32-bit counter and
// 12-byte nonce.
fn initial_state(key: Bytes, counter: Int, nonce: Bytes) List[Int]:
	var initial = [1634760805, 857760878, 2036477234, 1797285236]
	for index in 0..8:
		initial.append(le32(key, index * 4))
	initial.append(counter)
	for index in 0..3:
		initial.append(le32(nonce, index * 4))
	return initial

// Runs the 20 ChaCha rounds over `initial` and returns the 16 keystream words.
fn keystream(initial: List[Int]) List[Int]:
	var state = initial.clone()

	for round in 0..10:
		quarter(var state, 0, 4, 8, 12)
		quarter(var state, 1, 5, 9, 13)
		quarter(var state, 2, 6, 10, 14)
		quarter(var state, 3, 7, 11, 15)
		quarter(var state, 0, 5, 10, 15)
		quarter(var state, 1, 6, 11, 12)
		quarter(var state, 2, 7, 8, 13)
		quarter(var state, 3, 4, 9, 14)

	for index in 0..16:
		state.set(index, bit_and(state[index] + initial[index], 4294967295))
	return state

fn block(key: Bytes, counter: Int, nonce: Bytes) Bytes:
	words := keystream(initial_state(key, counter, nonce))
	var out = BytesBuilder()
	for word in words:
		for offset in 0..4:
			out.append(
				bit_and(
					shift_right_unsigned(word, 8 * offset),
					255,
				).to_uint8().get(0)
			)
	return out.build()

fn check_key_nonce(key: Bytes, nonce: Bytes) Bool:
	return key.length() == 32 and nonce.length() == 12

// Whether `length` bytes fit in the block counter space left from `counter` (RFC 8439
// counters are 32 bits).
fn fits_counter(counter: Int, length: Int) Bool:
	return (length + 63) / 64 <= 4294967296 - counter

fn xor_stream(key: Bytes, counter: Int, nonce: Bytes, data: Bytes) Bytes:
	var out = BytesBuilder()
	var state = initial_state(key, counter, nonce)
	var position = 0
	var index = counter

	while position < data.length():
		state.set(12, index)

		for word in keystream(state):
			for offset in 0..4:
				if position < data.length():
					pad := bit_and(shift_right_unsigned(word, 8 * offset), 255)
					out.append(
						bit_xor(
							data.get(position).to_int(),
							pad,
						).to_uint8().get(0)
					)
					position += 1

		index += 1

	return out.build()

/*
Encrypts or decrypts `data` with the ChaCha20 stream cipher (RFC 8439); the same call does both.
`key` is 32 bytes, `nonce` 12 bytes and `counter` the initial 32-bit block counter (normally 1 after the Poly1305 key block).
A wrong key or nonce length, or data that needs more blocks than the 32-bit counter has left, returns EINVAL. Never reuse a key and nonce pair.
*/
export fn chacha20(key: Bytes, nonce: Bytes, counter: Int, data: Bytes) Bytes!:
	if not check_key_nonce(key, nonce) or counter < 0 or counter > 4294967295:
		return error(Error("crypto: invalid input", kind: "EINVAL"))
	if not fits_counter(counter, data.length()):
		return error(Error("crypto: invalid input", kind: "EINVAL"))

	return ok(xor_stream(key, counter, nonce, data))

fn limbs_load(data: Bytes, at: Int, shift: Int) Int:
	return shift_right_unsigned(le32(data, at), shift)

// Computes the Poly1305 one-time authenticator (RFC 8439) of `data` with a 32-byte
// one-time key, returning 16 bytes. Authenticate with a key used for one message only;
// use `chacha20poly1305_seal` unless implementing a protocol.
export fn poly1305(key: Bytes, data: Bytes) Bytes!:
	if key.length() != 32: return error(Error("crypto: invalid input", kind: "EINVAL"))

	mask := 67108863
	r0 := bit_and(le32(key, 0), 67108863)
	r1 := bit_and(limbs_load(key, 3, 2), 67108611)
	r2 := bit_and(limbs_load(key, 6, 4), 67092735)
	r3 := bit_and(limbs_load(key, 9, 6), 66076671)
	r4 := bit_and(limbs_load(key, 12, 8), 1048575)
	s1 := r1 * 5
	s2 := r2 * 5
	s3 := r3 * 5
	s4 := r4 * 5
	var h0 = 0
	var h1 = 0
	var h2 = 0
	var h3 = 0
	var h4 = 0
	var position = 0

	while position < data.length():
		var chunk = BytesBuilder()
		var hibit = 16777216
		remaining := data.length() - position

		if remaining >= 16:
			for offset in 0..16:
				chunk.append(data.get(position + offset))
		else:
			hibit = 0
			for offset in 0..remaining:
				chunk.append(data.get(position + offset))
			chunk.append(1)
			for offset in remaining + 1..16:
				chunk.append(0)

		m := chunk.build()
		h0 += bit_and(le32(m, 0), mask)
		h1 += bit_and(limbs_load(m, 3, 2), mask)
		h2 += bit_and(limbs_load(m, 6, 4), mask)
		h3 += bit_and(limbs_load(m, 9, 6), mask)
		h4 += bit_or(limbs_load(m, 12, 8), hibit)

		var d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
		var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
		var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
		var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
		var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0
		var carry = shift_right_unsigned(d0, 26)
		h0 = bit_and(d0, mask)
		d1 += carry
		carry = shift_right_unsigned(d1, 26)
		h1 = bit_and(d1, mask)
		d2 += carry
		carry = shift_right_unsigned(d2, 26)
		h2 = bit_and(d2, mask)
		d3 += carry
		carry = shift_right_unsigned(d3, 26)
		h3 = bit_and(d3, mask)
		d4 += carry
		carry = shift_right_unsigned(d4, 26)
		h4 = bit_and(d4, mask)
		h0 += carry * 5
		carry = shift_right_unsigned(h0, 26)
		h0 = bit_and(h0, mask)
		h1 += carry
		position += 16

	var carry = shift_right_unsigned(h1, 26)
	h1 = bit_and(h1, mask)
	h2 += carry
	carry = shift_right_unsigned(h2, 26)
	h2 = bit_and(h2, mask)
	h3 += carry
	carry = shift_right_unsigned(h3, 26)
	h3 = bit_and(h3, mask)
	h4 += carry
	carry = shift_right_unsigned(h4, 26)
	h4 = bit_and(h4, mask)
	h0 += carry * 5
	carry = shift_right_unsigned(h0, 26)
	h0 = bit_and(h0, mask)
	h1 += carry

	var g0 = h0 + 5
	carry = shift_right_unsigned(g0, 26)
	g0 = bit_and(g0, mask)

	var g1 = h1 + carry
	carry = shift_right_unsigned(g1, 26)
	g1 = bit_and(g1, mask)

	var g2 = h2 + carry
	carry = shift_right_unsigned(g2, 26)
	g2 = bit_and(g2, mask)

	var g3 = h3 + carry
	carry = shift_right_unsigned(g3, 26)
	g3 = bit_and(g3, mask)

	g4 := h4 + carry - 67108864

	// g4 is negative exactly when h < 2^130 - 5, so keep h in that case. The choice is
	// a mask, not a branch, so the time taken does not depend on the secret
	// accumulator.
	keep := shift_right(g4, 63)
	take := bit_not(keep)
	h0 = bit_or(bit_and(h0, keep), bit_and(g0, take))
	h1 = bit_or(bit_and(h1, keep), bit_and(g1, take))
	h2 = bit_or(bit_and(h2, keep), bit_and(g2, take))
	h3 = bit_or(bit_and(h3, keep), bit_and(g3, take))
	h4 = bit_or(bit_and(h4, keep), bit_and(bit_and(g4, mask), take))

	word_mask := 4294967295
	var f0 = bit_and(bit_or(h0, shift_left(h1, 26)), word_mask) + le32(key, 16)
	var f1 = (
		bit_and(
			bit_or(shift_right_unsigned(h1, 6), shift_left(h2, 20)),
			word_mask,
		)
		+ le32(key, 20)
	)
	var f2 = (
		bit_and(
			bit_or(shift_right_unsigned(h2, 12), shift_left(h3, 14)),
			word_mask,
		)
		+ le32(key, 24)
	)
	var f3 = (
		bit_and(
			bit_or(shift_right_unsigned(h3, 18), shift_left(h4, 8)),
			word_mask,
		)
		+ le32(key, 28)
	)
	f1 += shift_right_unsigned(f0, 32)
	f2 += shift_right_unsigned(f1, 32)
	f3 += shift_right_unsigned(f2, 32)

	var out = BytesBuilder()
	for word in [f0, f1, f2, f3]:
		for offset in 0..4:
			out.append(
				bit_and(
					shift_right_unsigned(word, 8 * offset),
					255,
				).to_uint8().get(0)
			)
	return ok(out.build())

fn pad16(var out: BytesBuilder, length: Int) Unit:
	for index in length % 16..16:
		if length % 16 != 0:
			out.append(0)

fn put_le64(var out: BytesBuilder, value: Int) Unit:
	for offset in 0..8:
		out.append(
			bit_and(
				shift_right_unsigned(value, 8 * offset),
				255,
			).to_uint8().get(0)
		)

fn tag_for(key: Bytes, nonce: Bytes, associated_data: Bytes, ciphertext: Bytes) Bytes!:
	one_time := block(key, 0, nonce)
	var mac = BytesBuilder()
	mac.append_bytes(associated_data)
	pad16(var mac, associated_data.length())
	mac.append_bytes(ciphertext)
	pad16(var mac, ciphertext.length())
	put_le64(var mac, associated_data.length())
	put_le64(var mac, ciphertext.length())
	return poly1305(one_time.slice(0, 32).get(Bytes([])), mac.build())

// Encrypts and authenticates `plaintext` with ChaCha20-Poly1305 (RFC 8439), returning
// the ciphertext followed by a 16-byte tag.
// `key` is 32 bytes and `nonce` 12 bytes; a wrong length returns EINVAL. The caller supplies a nonce never reused with the key.
export fn chacha20poly1305_seal(
	key: Bytes,
	nonce: Bytes,
	plaintext: Bytes,
	associated_data: Bytes,
) Bytes!:
	if not check_key_nonce(key, nonce) or not fits_counter(1, plaintext.length()):
		return error(Error("crypto: invalid input", kind: "EINVAL"))

	ciphertext := xor_stream(key, 1, nonce, plaintext)
	tag := tag_for(key, nonce, associated_data, ciphertext)?
	var out = BytesBuilder()
	out.append_bytes(ciphertext)
	out.append_bytes(tag)
	return ok(out.build())

// Authenticates and decrypts a value produced by `chacha20poly1305_seal`. A wrong key,
// nonce, associated data or altered ciphertext returns EAUTH; a wrong key or nonce
// length or input shorter than the 16-byte tag returns EINVAL.
export fn chacha20poly1305_open(
	key: Bytes,
	nonce: Bytes,
	sealed: Bytes,
	associated_data: Bytes,
) Bytes!:
	if (
		not check_key_nonce(key, nonce)
		or sealed.length() < 16
		or not fits_counter(1, sealed.length() - 16)
	):
		return error(Error("crypto: invalid input", kind: "EINVAL"))

	split := sealed.length() - 16
	ciphertext := sealed.slice(0, split).get(Bytes([]))
	tag := sealed.slice(split, sealed.length()).get(Bytes([]))
	expected := tag_for(key, nonce, associated_data, ciphertext)?
	if not constant_time_equal(expected, tag):
		return error(Error("crypto: authentication failed", kind: "EAUTH"))

	return ok(xor_stream(key, 1, nonce, ciphertext))

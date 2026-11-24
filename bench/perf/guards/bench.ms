// Gated by `make bench-gate`: the same work as the programs in this folder, as bench
// blocks whose allocation and copy counts are compared with baseline.json. Counts do
// not depend on machine load or host, so the gate does not flake; refresh the baseline
// with
// `ms bench bench/perf/guards/ms.toml --ops --json > bench/perf/guards/baseline.json`
// when a change deliberately moves them.
import (
	Curve,
	HashAlgorithm,
	ecdh_shared_secret,
	ecdsa_generate,
	ecdsa_sign,
	ecdsa_verify,
	public_key,
	public_key_der,
	sign,
	verify from "@std/crypto/crypto.ms",
	ColorMode,
	ImageFormat,
	decode_image,
	encode_image,
	encode_jpeg,
	new_image from "@std/image/image.ms",
	compile from "@std/regex.ms",
)

type Row:
	id Int
	name String

// Ed25519 and P-256 sign, verify and key agreement (#4178).
bench "signatures":
	seed := "0123456789abcdef0123456789abcdef".to_bytes()
	msg := "hello".to_bytes()
	key := public_key(seed)?
	sig := sign(seed, msg)?
	priv := ecdsa_generate(Curve.P256)?
	pubk := public_key_der(priv)?
	esig := ecdsa_sign(priv, HashAlgorithm.Sha256, msg)?
	var n = 0

	for i in 0..5:
		if verify(key, msg, sig): n += 1
		n += (sign(seed, msg)?).length()
		if ecdsa_verify(pubk, HashAlgorithm.Sha256, msg, esig): n += 1
		n += (ecdh_shared_secret(priv, pubk)?).length()

	n

// A regex with a literal prefix over generated text (#4189).
bench "regex find_all":
	var text = ""
	for i in 0..2000:
		text += f"line {i} some filler text here\nfunc name{i}(a, b)\n"

	re := compile("func\\s+\\w+\\(")?
	(re.find_all(text, null)?).length()

// JPEG and PNG encode and decode of one image (#4197).
bench "image codecs":
	w := 96
	h := 96
	var img = new_image(w, h, ColorMode.Rgb)?

	for y in 0..h:
		for x in 0..w:
			at := (y * w + x) * 3
			img.pixels[at] = ((x * 3 + y * 5) % 256).to_uint8() or 0
			img.pixels[at + 1] = ((x + y * 2) % 256).to_uint8() or 0
			img.pixels[at + 2] = ((x * 7 + y) % 256).to_uint8() or 0

	png := encode_image(img, ImageFormat.Png)?
	jpg := encode_jpeg(img)?
	(
		png.length()
		+ jpg.length()
		+ (decode_image(png)?).width
		+ (decode_image(jpg)?).width
	)

// Iterator chains over records and strings (#4185).
bench "fused chains":
	var rows List[Row] = []
	for i in 0..5000:
		rows.append(Row(i, f"name{i % 311}"))

	total := rows.filter(fn(r Row) Bool: r.id % 3 == 0).map(
		fn(r Row) Int: (r.name.length())
	).sum()
	text := "the quick brown fox jumps over the lazy dog ".repeat(100)
	words := text.split(" ").filter(fn(w String) Bool: w.length() > 3).map(
		fn(w String) Int: w.length()
	).sum()
	total + words

// Map lookups, contains, and any and all over strings and records.
bench "map probes and predicates":
	var counts = Map[Int, Int]()
	var rows List[Row] = []

	for i in 0..5000:
		counts[i % 997] = counts.get_or(i % 997, 0) + 1
		rows.append(Row(i, f"name{i % 311}"))

	var hits = 0
	for i in 0..5000:
		if counts.contains(i): hits += 1

	text := "the quick brown fox jumps over the lazy dog ".repeat(100)
	any_row := rows.any(fn(r Row) Bool: r.name.starts_with("name3") and r.id > 4990)
	every := rows.all(fn(r Row) Bool: r.name.length() > 4)
	lower := text.chars().all(fn(c String) Bool: c != "Z")
	hits + (if any_row: 1 else: 0) + (if every: 1 else: 0) + (if lower: 1 else: 0)

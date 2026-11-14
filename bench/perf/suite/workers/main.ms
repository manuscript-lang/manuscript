// Concurrency: a fixed set of independent chunks, each processed by its own promise (compare a thread pool,
// goroutines and worker threads). A chunk generates 200,000 pseudo-random values, counts them into 256 buckets
// and folds them into a checksum, so every task does real CPU work and shares nothing.
import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn chunk_checksum(chunk: Int) Int!:
	var hist: List[Int] = []
	for b in 0..256:
		hist.append(0)

	var x = chunk * 7919 + 1
	var h = 0

	for i in 0..200000:
		x = (x * 48271) % 2147483647
		hist[x % 256] = hist[x % 256] + 1
		h = (h * 31 + x) % 1000000007

	for b in 0..256:
		h = (h * 131 + hist[b]) % 1000000007

	return ok(h)

// A promise a function returns owns the values it captured.
fn start_chunk(chunk: Int) Promise[Int]:
	return promise[Int](fn: chunk_checksum(chunk))

fn main() Unit:
	var ps: List[Promise[Int]] = []
	for chunk in 0..128:
		ps.append(start_chunk(chunk))

	var total = 0
	for r in wait_all(ps).get():
		total += r
	print("chunks 128 checksum {total}")

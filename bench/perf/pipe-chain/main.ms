import (
	promise from "@std/concurrency/promise.ms",
	ReadStream, WriteStream, pipe, stdout from "@std/io/io.ms",
)

fn fill(var out: WriteStream[Int], from: Int, count: Int) Unit!:
	for i in from..from + count:
		out.write(i)?
	out.flush()?
	return out.close()

fn stage(var input: ReadStream[Int], var out: WriteStream[Int]) Unit!:
	for v in input:
		out.write(v + 1)?
	out.flush()?
	return out.close()

fn run() Unit!:
	var p = pipe[Int](64)
	var q = pipe[Int](64)
	var w1 = p.writer()
	var pr = p.reader()
	var qw = q.writer()
	var input = q.reader()
	p.close()?
	q.close()?

	a := promise(fn: fill(var w1, 0, 1000000))
	st := promise(fn: stage(var pr, var qw))
	var sum = 0
	var n = 0

	for v in input:
		sum += v
		n += 1

	a.wait()?
	st.wait()?
	stdout().write("{n} {sum}\n")?

fn main() Unit:
	run().get()

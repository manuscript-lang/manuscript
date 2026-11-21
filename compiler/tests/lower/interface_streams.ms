interface Sink[T]:
	var fn write(move value: T) Void!
	move fn close() Void!

type Out:
	n: Int = 0

fn var Out.write(move value: String) Void!:
	self.n += value.length()

fn move Out.close() Void!:
	return ok()

type Stream[T]:
	sink: Sink[T]

fn var Stream[T].write(move value: T) Void!:
	return self.sink.write(value)

fn move Stream[T].close() Void!:
	return self.sink.close()

fn main() Void!:
	var s = Stream[String](Out())
	_w := s.write("hi")

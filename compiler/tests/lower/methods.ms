type Counter:
	count: Int

fn Counter.total(other: Int) Int:
	return self.count + other

fn Counter.doubled() Int:
	return self.total(self.count)

fn var Counter.bump(by: Int) Int:
	self.count += by
	return self.count

type Span:
	low: Float
	high: Float
	open: Bool

fn Span.width() Float:
	return self.high - self.low

fn Span.holds(x: Float) Bool:
	return self.open and x > self.low and x < self.high

fn Span.report() Void:
	if self.holds(self.low): return

	print(self.width())

fn combined(c: Counter, s: Span) Int:
	if s.holds(1.5): return c.total(2) + c.doubled()
	return c.doubled()

fn main() Int:
	return combined(Counter(count: 2), Span(low: 1.0, high: 4.0, open: true))

import expect_equal from "@std/test/test.ms"

type Counter:
	n: Int

enum Shape:
	Circle(r: Int)
	Square(side: Int)

interface Bumper:
	fn bump(by: Int) Int

interface Scaler:
	fn scale(factor: Int, offset: Int?) Int

fn Counter.bump(by: Int) Int: self.n + by

fn Counter.scale(factor: Int, offset: Int?) Int: (self.n * factor + offset.get(0))

fn Shape.bump(by: Int) Int:
	match self:
		Circle(r): return r + by
		Square(side): return side * by

fn through_view(b: Bumper, by: Int) Int:
	return b.bump(by)

fn guarded(c: Counter, by: Int) Int:
	if by < 0: return 0
	return c.bump(by)

test "method calls on concrete receivers":
	c := Counter(4)
	expect_equal(c.bump(3), 7)?
	expect_equal(Shape.Circle(2).bump(1), 3)?
	expect_equal(Shape.Square(3).bump(2), 6)?

test "one call site sees different receiver types":
	counters: List[Counter] := [Counter(1), Counter(2), Counter(3)]
	var total = 0
	for counter in counters:
		total += guarded(counter, 10)
	expect_equal(total, 36)?

test "views, defaults, and reordered labels keep dispatch":
	c := Counter(5)
	expect_equal(through_view(c, 2), 7)?
	expect_equal(c.scale(2), 10)?
	expect_equal(c.scale(offset: 1, factor: 2), 11)?
	expect_equal(c.scale(2, 3), 13)?

type Parser:
	base: Int

interface Parse:
	fn parse(n: Int) Int!Error

fn Parser.parse(n: Int) Int!Error:
	if n < 0: return error(Error("negative"))
	return ok(self.base + n)

type Chain:
	parser: Parser

interface Step:
	fn step(n: Int) Int!Error

fn Chain.step(n: Int) Int!Error:
	return ok((self.parser.parse(n)?) + 1)

fn code(r: Int!Error) Int:
	return r.get(-1)

fn run_direct(chain: Chain, n: Int) Int:
	return chain.step(n) | code

fn run_view(chain: Chain, n: Int) Int:
	return chain.step(n) | code

fn run_bound(chain: Chain, n: Int) Int:
	callback := chain.step
	return callback(n) | code

test "nested try in a direct method becomes an error result":
	chain := Chain(Parser(10))
	expect_equal(run_direct(chain, 5), 16)?
	expect_equal(run_direct(chain, -5), -1)?
	expect_equal(run_view(chain, -5), -1)?
	expect_equal(run_bound(chain, -5), -1)?
	expect_equal(run_bound(chain, 5), 16)?

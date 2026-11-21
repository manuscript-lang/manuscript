type Tagged:
	name: String
	scores: List[Int]

type Wrapper:
	inner: Tagged
	count: Int

fn label(t: Tagged) String:
	return t.name

fn count(t: Tagged) Int:
	return t.scores.length

fn wrap(t: Tagged) Wrapper:
	return Wrapper(inner: t, count: 1)

fn make(name: String) Tagged:
	return Tagged(name: name, scores: [1, 2])

fn main() Int:
	t := make("a")
	w := wrap(make("b"))
	return count(t) + count(w.inner) + label(t).length

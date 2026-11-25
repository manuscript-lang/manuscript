// conform: tags=testing
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// `split`, `lines` and `fields_by` yield borrowed pieces one at a time; `collect` builds the list.

fn pieces_of(text String) List[String] {
	var found = List[String]()
	for piece in text.split(",") {
		found.append(piece.clone())
	}
	return found
}

fn rows_of(text String) List[String] {
	var found = List[String]()
	for row in text.lines() {
		found.append(row.clone())
	}
	return found
}

fn words_of(text String) List[String] {
	var found = List[String]()
	for word in text.fields_by(c => c == " " or c == "-") {
		found.append(word.clone())
	}
	return found
}

fn first_of(text String) String {
	return text.split(" ").collect()[0].clone()
}

test "split yields every piece, including empty ones" {
	expect_equal(pieces_of("a,b,,c,"), ["a", "b", "", "c", ""])?
	expect_equal("a,b".split(",").collect(), ["a", "b"])?
	expect_equal("".split(",").collect(), [""])?
}

test "copies of pieces outlive the text they came from" {
	found := pieces_of("alpha-beta-gamma-delta-epsilon,zeta-eta-theta-iota-kappa".repeat(2))
	expect_equal(found.length(), 3)?
	expect_equal(found[0], "alpha-beta-gamma-delta-epsilon")?
}

test "lines keep empty rows and fields_by skips empty runs" {
	expect_equal(rows_of("one\ntwo\n\nthree"), ["one", "two", "", "three"])?
	expect_equal(words_of("a b--c  d"), ["a", "b", "c", "d"])?
	expect_equal("x y z".fields_by(c => c == " ").collect(), ["x", "y", "z"])?
}

test "the first piece of a split is read without building the list" {
	expect_equal(first_of("head tail more"), "head")?
	expect_equal(first_of("single"), "single")?
	expect_equal(first_of(""), "")?
}

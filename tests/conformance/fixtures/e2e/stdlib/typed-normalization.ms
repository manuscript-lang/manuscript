// conform: tags=closures,control-flow,faults,generics,match,modules,optional,stdlib-string,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/typed-normalization.ms
import (
	NormalizationForm from "@std/string.ms",
	expect_equal from "@std/test/test.ms",
)

fn normalize(form: NormalizationForm, text: String) String!:
	return form.normalize(text)

fn call[T](operation: fn(String, Int?) T, text: String) T:
	return operation(text, none)

test "typed Unicode forms retain normalization and bound dispatch":
	decomposed := "é"
	expect_equal(normalize(NormalizationForm.Nfc, decomposed).get(), "é")?
	expect_equal(NormalizationForm.Nfd.normalize("é").get(), decomposed)?
	expect_equal(NormalizationForm.Nfkc.normalize("ﬁ").get(), "fi")?
	expect_equal(NormalizationForm.Nfkd.normalize("ﬁ").get(), "fi")?

	for form in [
		NormalizationForm.Nfc, NormalizationForm.Nfd, NormalizationForm.Nfkc,
		NormalizationForm.Nfkd
	]:
		spelling := match form:
			Nfc: "NFC"
			Nfd: "NFD"
			Nfkc: "NFKC"
			Nfkd: "NFKD"

		expect_equal(form.normalize("ﬁé").get(), "ﬁé".normalize(spelling).get())?

	stored := NormalizationForm.Nfc.normalize
	expect_equal(call(stored, decomposed).get(), "é")?

test "typed normalization keeps UTF-8 byte budgets and domain errors":
	form := NormalizationForm.Nfc
	expect_equal(form.normalize("é", 2).get(), "é")?
	expect_equal(form.normalize("", 0).get(), "")?
	expect_equal(
		form.normalize("é", 1).err(), Error("string: limit exceeded", kind: "EOVERFLOW")
	)?
	expect_equal(
		form.normalize("x", 0).err(), Error("string: limit exceeded", kind: "EOVERFLOW")
	)?
	expect_equal(
		form.normalize("", -1).err(), Error("string: invalid input", kind: "EINVAL")
	)?
	expect_equal(
		"x".normalize("nfc").err(), Error("string: invalid input", kind: "EINVAL")
	)?

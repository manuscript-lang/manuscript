import (
	Bytes from "@std/bytes.ms",
	ascii_decode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

type BenchData {
	datas List[Bytes]
	expecteds List[String!]
}

fn make_fixture() BenchData {
	var datas List[Bytes] = []
	var expecteds List[String!] = []
	expected := "Az09 \n\u{0}".repeat(0)
	data := expected.to_bytes()
	expected_2 := "Az09 \n\u{0}".repeat(1)
	data_2 := expected_2.to_bytes()
	expected_3 := "Az09 \n\u{0}".repeat(8)
	data_3 := expected_3.to_bytes()
	expected_4 := "Az09 \n\u{0}".repeat(585)
	data_4 := expected_4.to_bytes()
	expected_5 := "Az09 \n\u{0}".repeat(149797)
	data_5 := expected_5.to_bytes()
	good := ("Az09 \n\u{0}".repeat(0)).to_bytes()
	bad := Bytes([255])
	data_6 := bad.concat(good)
	expected_6 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_7 := ("Az09 \n\u{0}".repeat(0)).to_bytes()
	bad_7 := Bytes([255])
	data_7 := good_7.concat(bad_7)
	expected_7 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_8 := ("Az09 \n\u{0}".repeat(8)).to_bytes()
	bad_8 := Bytes([255])
	data_8 := bad_8.concat(good_8)
	expected_8 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_9 := ("Az09 \n\u{0}".repeat(8)).to_bytes()
	bad_9 := Bytes([255])
	data_9 := good_9.concat(bad_9)
	expected_9 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_10 := ("Az09 \n\u{0}".repeat(585)).to_bytes()
	bad_10 := Bytes([255])
	data_10 := bad_10.concat(good_10)
	expected_10 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_11 := ("Az09 \n\u{0}".repeat(585)).to_bytes()
	bad_11 := Bytes([255])
	data_11 := good_11.concat(bad_11)
	expected_11 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_12 := ("Az09 \n\u{0}".repeat(149797)).to_bytes()
	bad_12 := Bytes([255])
	data_12 := bad_12.concat(good_12)
	expected_12 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	good_13 := ("Az09 \n\u{0}".repeat(149797)).to_bytes()
	bad_13 := Bytes([255])
	data_13 := good_13.concat(bad_13)
	expected_13 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_14 := ("é".repeat(1)).to_bytes()
	expected_14 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_15 := ("🙂".repeat(1)).to_bytes()
	expected_15 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_16 := ("é".repeat(2048)).to_bytes()
	expected_16 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_17 := ("🙂".repeat(2048)).to_bytes()
	expected_17 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_18 := ("é".repeat(524288)).to_bytes()
	expected_18 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	data_19 := ("🙂".repeat(524288)).to_bytes()
	expected_19 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	tail := "A".repeat(8)
	data_20 := ("é" + tail).to_bytes()
	expected_20 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	tail_21 := "A".repeat(8)
	data_21 := (tail_21 + "é").to_bytes()
	expected_21 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	tail_22 := "A".repeat(524288)
	data_22 := ("é" + tail_22).to_bytes()
	expected_22 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	tail_23 := "A".repeat(524288)
	data_23 := (tail_23 + "é").to_bytes()
	expected_23 String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	datas.append(data)
	expecteds.append(ok(expected.clone()))
	datas.append(data_2)
	expecteds.append(ok(expected_2.clone()))
	datas.append(data_3)
	expecteds.append(ok(expected_3.clone()))
	datas.append(data_4)
	expecteds.append(ok(expected_4.clone()))
	datas.append(data_5)
	expecteds.append(ok(expected_5.clone()))
	datas.append(data_6)
	expecteds.append(expected_6)
	datas.append(data_7)
	expecteds.append(expected_7)
	datas.append(data_8)
	expecteds.append(expected_8)
	datas.append(data_9)
	expecteds.append(expected_9)
	datas.append(data_10)
	expecteds.append(expected_10)
	datas.append(data_11)
	expecteds.append(expected_11)
	datas.append(data_12)
	expecteds.append(expected_12)
	datas.append(data_13)
	expecteds.append(expected_13)
	datas.append(data_14)
	expecteds.append(expected_14)
	datas.append(data_15)
	expecteds.append(expected_15)
	datas.append(data_16)
	expecteds.append(expected_16)
	datas.append(data_17)
	expecteds.append(expected_17)
	datas.append(data_18)
	expecteds.append(expected_18)
	datas.append(data_19)
	expecteds.append(expected_19)
	datas.append(data_20)
	expecteds.append(expected_20)
	datas.append(data_21)
	expecteds.append(expected_21)
	datas.append(data_22)
	expecteds.append(expected_22)
	datas.append(data_23)
	expecteds.append(expected_23)
	return BenchData(datas: datas, expecteds: expecteds)
}

fn var BenchData.before_all() Void! {
	for i in 0..self.datas.length() {
		expect_equal(ascii_decode(self.datas[i]), self.expecteds[i])?
	}
	return ok()
}

bench "ascii.valid.0" {
	(ascii_decode(fixture.datas[0])?).length()
}

bench "ascii.valid.7" {
	(ascii_decode(fixture.datas[1])?).length()
}

bench "ascii.valid.56" {
	(ascii_decode(fixture.datas[2])?).length()
}

bench "ascii.valid.4095" {
	(ascii_decode(fixture.datas[3])?).length()
}

bench "ascii.valid.1048579" {
	(ascii_decode(fixture.datas[4])?).length()
}

bench "ascii.invalid.first.1" {
	actual := ascii_decode(fixture.datas[5])
	expect_equal(actual, fixture.expecteds[5])?
	fixture.datas[5].length()
}

bench "ascii.invalid.last.1" {
	actual := ascii_decode(fixture.datas[6])
	expect_equal(actual, fixture.expecteds[6])?
	fixture.datas[6].length()
}

bench "ascii.invalid.first.57" {
	actual := ascii_decode(fixture.datas[7])
	expect_equal(actual, fixture.expecteds[7])?
	fixture.datas[7].length()
}

bench "ascii.invalid.last.57" {
	actual := ascii_decode(fixture.datas[8])
	expect_equal(actual, fixture.expecteds[8])?
	fixture.datas[8].length()
}

bench "ascii.invalid.first.4096" {
	actual := ascii_decode(fixture.datas[9])
	expect_equal(actual, fixture.expecteds[9])?
	fixture.datas[9].length()
}

bench "ascii.invalid.last.4096" {
	actual := ascii_decode(fixture.datas[10])
	expect_equal(actual, fixture.expecteds[10])?
	fixture.datas[10].length()
}

bench "ascii.invalid.first.1048580" {
	actual := ascii_decode(fixture.datas[11])
	expect_equal(actual, fixture.expecteds[11])?
	fixture.datas[11].length()
}

bench "ascii.invalid.last.1048580" {
	actual := ascii_decode(fixture.datas[12])
	expect_equal(actual, fixture.expecteds[12])?
	fixture.datas[12].length()
}

bench "ascii.unicode.accent.1" {
	expect_equal(ascii_decode(fixture.datas[13]), fixture.expecteds[13])?
	fixture.datas[13].length()
}

bench "ascii.unicode.emoji.1" {
	expect_equal(ascii_decode(fixture.datas[14]), fixture.expecteds[14])?
	fixture.datas[14].length()
}

bench "ascii.unicode.accent.2048" {
	expect_equal(ascii_decode(fixture.datas[15]), fixture.expecteds[15])?
	fixture.datas[15].length()
}

bench "ascii.unicode.emoji.2048" {
	expect_equal(ascii_decode(fixture.datas[16]), fixture.expecteds[16])?
	fixture.datas[16].length()
}

bench "ascii.unicode.accent.524288" {
	expect_equal(ascii_decode(fixture.datas[17]), fixture.expecteds[17])?
	fixture.datas[17].length()
}

bench "ascii.unicode.emoji.524288" {
	expect_equal(ascii_decode(fixture.datas[18]), fixture.expecteds[18])?
	fixture.datas[18].length()
}

bench "ascii.unicode.first.8" {
	expect_equal(ascii_decode(fixture.datas[19]), fixture.expecteds[19])?
	fixture.datas[19].length()
}

bench "ascii.unicode.last.8" {
	expect_equal(ascii_decode(fixture.datas[20]), fixture.expecteds[20])?
	fixture.datas[20].length()
}

bench "ascii.unicode.first.524288" {
	expect_equal(ascii_decode(fixture.datas[21]), fixture.expecteds[21])?
	fixture.datas[21].length()
}

bench "ascii.unicode.last.524288" {
	expect_equal(ascii_decode(fixture.datas[22]), fixture.expecteds[22])?
	fixture.datas[22].length()
}

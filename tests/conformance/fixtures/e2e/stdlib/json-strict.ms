// conform: tags=optional,records,stdlib-json,testing,try-result
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import stringify, StringifyOptions from "@std/data/json.ms"

type Handler:
    name String
    done Void
    note String?

type Plain:
    name String
    tags List[Int?]
    note String?

type Holder:
    items List[Void]

test "JSON stringify omits values without a JSON form unless strict":
    handler := Handler("h", void, null)
    expect_equal(stringify(handler), ok("{\"name\":\"h\"}"))?

    invalid String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
    expect_equal(stringify(handler, StringifyOptions(strict: true)), invalid)?

test "JSON strict stringify rejects no-form list elements":
    holder := Holder([void])
    expect_equal(stringify(holder), ok("{\"items\":[null]}"))?

    invalid String! := error(Error("JSON: invalid data", kind: "EBADMSG"))
    expect_equal(stringify(holder, StringifyOptions(strict: true)), invalid)?

test "JSON strict stringify accepts none and nulls that are values":
    plain := Plain("p", [1, null], null)
    expected := "{\"name\":\"p\",\"tags\":[1,null]}"
    expect_equal(
        stringify(plain, StringifyOptions(strict: true)), ok(expected.clone())
    )?
    expect_equal(stringify(plain), ok(expected))?

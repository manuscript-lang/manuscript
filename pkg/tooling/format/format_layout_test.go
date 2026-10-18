package format_test

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/tooling/format"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFormatCompactGolden(t *testing.T) {
	input, err := os.ReadFile("testdata/compact.input.ms")
	if err != nil {
		t.Fatal(err)
	}
	want, err := os.ReadFile("testdata/compact.golden.ms")
	if err != nil {
		t.Fatal(err)
	}
	for _, newline := range []string{"\n", "\r\n", "\n\n\n"} {
		// Authored blank lines do not affect canonical paragraph boundaries.
		source := strings.ReplaceAll(string(input), "\n", newline)
		got, err := format.Format("compact.ms", source)
		if err != nil {
			t.Fatal(err)
		}
		if got != string(want) {
			t.Fatalf("formatted:\n%s\nwant:\n%s", got, want)
		}
		assertFormatMeaning(t, "compact.ms", source, got)
		twice, err := format.Format("compact.ms", got)
		if err != nil || twice != got {
			t.Fatalf("formatting is not idempotent: %v\n%s", err, twice)
		}
		for _, text := range []string{source, got} {
			result := compiler.CompileSource("compact.ms", text, compiler.Options{Tests: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
		}
	}
}

func TestFormatExpressionLayouts(t *testing.T) {
	cases := []struct {
		name, source, want string
	}{
		{
			name: "comparison argument uses the call continuation",
			source: `fn work() Unit:
    try expect_false(try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options) != [["line\n\nbreak"], [""]])
`,
			want: `fn work() Unit:
    try expect_false(
        try parse("\"line\r\n\r\nbreak\"\r\n\"\"\r\n", options) != [
            ["line\n\nbreak"],
            [""]
        ]
    )
`,
		},
		{
			name: "argument width is measured after moving into the call",
			source: `fn work() Unit:
    send_message(condition: account_is_active and payment_is_allowed and remaining_balance > 0)
`,
			want: `fn work() Unit:
    send_message(
        condition: account_is_active and payment_is_allowed and remaining_balance > 0
    )
`,
		},
		{
			name: "long argument operators use the call continuation",
			source: `fn work() Unit:
    send(condition: account_is_active or payment_is_allowed and remaining_balance > minimum_balance)
`,
			want: `fn work() Unit:
    send(
        condition: account_is_active
        or payment_is_allowed and remaining_balance > minimum_balance
    )
`,
		},
		{
			name: "long parameter default uses the signature continuation",
			source: `fn work(balance: Int = initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total) Int:
    return balance
`,
			want: `fn work(
    balance: Int = initial_account_balance
    + pending_deposit_total * applicable_exchange_rate
    - pending_withdrawal_total
) Int:
    return balance
`,
		},
		{
			name: "long map value uses the collection continuation",
			source: `fn work() Unit:
    let values = {"balance": initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total}
`,
			want: `fn work() Unit:
    let values = {
        "balance": initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total
    }
`,
		},
		{
			name: "long member argument uses the call continuation",
			source: `fn work() Unit:
    send(payload: incoming_request_payload.normalize_whitespace().remove_legacy_separators().trim_whitespace())
`,
			want: `fn work() Unit:
    send(
        payload: incoming_request_payload
        .normalize_whitespace()
        .remove_legacy_separators()
        .trim_whitespace()
    )
`,
		},
		{
			name: "function-typed parameter measures only its own signature",
			source: `fn map_box[T, U_wwwwwwwwwwww](b_wwwwwwwwwwwwwwwwwwwwwwww: Box_wwwwwwwwwwwwwwwwwww[T], f_wwwwwwwwwww: fn(v: T) U_wwwwwwwwwwww) Box_wwwwwwwwwwwwwwwwwww[U_wwwwwwwwwwww]:
    return b_wwwwwwwwwwwwwwwwwwwwwwww
`,
			want: `fn map_box[T, U_wwwwwwwwwwww](
    b_wwwwwwwwwwwwwwwwwwwwwwww: Box_wwwwwwwwwwwwwwwwwww[T],
    f_wwwwwwwwwww: fn(v: T) U_wwwwwwwwwwww
) Box_wwwwwwwwwwwwwwwwwww[U_wwwwwwwwwwww]:
    return b_wwwwwwwwwwwwwwwwwwwwwwww
`,
		},
		{
			name: "long if let value wraps without the binding",
			source: `fn work() Int:
    if let value = [2, 5, 3, (-6), (-9), 1, 2, 3, 4].clone().sorted(fn(l: Int, r: Int) Int: l - r).first():
        return value
    return 0
`,
			want: `fn work() Int:
    if let value = (
        [2, 5, 3, (-6), (-9), 1, 2, 3, 4]
        .clone()
        .sorted(fn(l: Int, r: Int) Int: (l - r))
        .first()
    ):
        return value

    return 0
`,
		},
		{
			name: "list comments retain item boundaries",
			source: `fn work() Unit:
    let values = [1, # Keep the first value explained.
        2, 3, 4]
`,
			want: `fn work() Unit:
    let values = [
        1,  # Keep the first value explained.
        2,
        3,
        4
    ]
`,
		},
		{
			name: "simple list rows use available width",
			source: `fn work() Unit:
    let values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]
`,
			want: `fn work() Unit:
    let values = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25, 26, 27, 28, 29, 30
    ]
`,
		},
		{
			name: "many short map entries stay compact",
			source: `fn work() Unit:
    let values = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 0: 0}
`,
			want: `fn work() Unit:
    let values = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 0: 0}
`,
		},
		{
			name: "module constant initializer starting before its operator",
			source: `let prices = [12, 8, 25]
let affordable = prices.length > 1 and prices.keep(predicate: fn(value: Int) Bool:
    return value <= 10
).length > 0
`,
			want: `let prices = [12, 8, 25]
let affordable = (
    prices.length > 1
    and prices.keep(
        predicate: fn(value: Int) Bool:
            return value <= 10
    ).length > 0
)
`,
		},
		{
			name: "match arms after a try joined from a later line",
			source: `fn work(early: Int) Int:
    let result = subtract(try
        match some(0):
            some(_):
                10
            none: 10
    )
    return result
`,
			want: `fn work(early: Int) Int:
    let result = subtract(
        try match some(0):
            some(_):
                10
            none: 10
    )
    return result
`,
		},
		{
			name: "nested computations below the width limit",
			source: `fn work() Unit:
    send(destination: resolve(name: service, region: region), payload: encode(build(records)))
`,
			want: `fn work() Unit:
    send(
        destination: resolve(name: service, region: region),
        payload: encode(build(records))
    )
`,
		},
		{
			name: "long call and labeled inputs",
			source: `fn work() Unit:
    send(destination: destination_address, payload: encoded_message_payload, timeout: configured_request_timeout)
`,
			want: `fn work() Unit:
    send(
        destination: destination_address,
        payload: encoded_message_payload,
        timeout: configured_request_timeout
    )
`,
		},
		{
			name: "compact larger and nested collections",
			source: `fn work() Unit:
    let larger = [1, 2, 3, 4, 5]
    let nested = [[1, 2], [3, 4]]
`,
			want: `fn work() Unit:
    let larger = [1, 2, 3, 4, 5]
    let nested = [[1, 2], [3, 4]]
`,
		},
		{
			name: "compound conditions keep inline guards",
			source: `fn work() Int:
    if active and allowed and remaining > 0: return 1
    return 0
`,
			want: `fn work() Int:
    if active and allowed and remaining > 0: return 1

    return 0
`,
		},
		{
			name: "compound assignment keeps its operator",
			source: `fn work() Int:
    var total = 1
    total+=2
    total   *=   3
    box.count -=  total
    return total
`,
			want: `fn work() Int:
    var total = 1
    total += 2
    total *= 3
    box.count -= total
    return total
`,
		},
		{
			name: "boolean precedence and comparison operands",
			source: `fn work() Bool:
    return active or allowed and remaining > 0 or fallback
`,
			want: `fn work() Bool:
    return active or allowed and remaining > 0 or fallback
`,
		},
		{
			name: "compound argument values",
			source: `fn work() Unit:
    send(condition: active and allowed and remaining > 0, payload: "data")
`,
			want: `fn work() Unit:
    send(condition: active and allowed and remaining > 0, payload: "data")
`,
		},
		{
			name: "mixed boolean clauses",
			source: `fn work() Bool:
    return active or allowed and remaining > 0
`,
			want: `fn work() Bool:
    return active or allowed and remaining > 0
`,
		},
		{
			name: "long boolean chain wraps at the width",
			source: `fn work() Bool:
    return account_is_active and payment_is_allowed and remaining_balance > minimum_balance
`,
			want: `fn work() Bool:
    return (
        account_is_active
        and payment_is_allowed
        and remaining_balance > minimum_balance
    )
`,
		},
		{
			name: "long arithmetic retains precedence",
			source: `fn work() Int:
    return initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total
`,
			want: `fn work() Int:
    return (
        initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total
    )
`,
		},
		{
			name: "long chain has one operation per line",
			source: `fn work() String:
    return incoming_request_payload.normalize_whitespace().replace(old: legacy_separator, new: current_separator).trim()
`,
			want: `fn work() String:
    return (
        incoming_request_payload
        .normalize_whitespace()
        .replace(old: legacy_separator, new: current_separator)
        .trim()
    )
`,
		},
		{
			name: "parameter and import groups",
			source: `import {First, Second, Third, Fourth, Fifth} from "./contracts.ms"
fn work(first: Int, second: Int, third: Int, fourth: Int) Int: return first
`,
			want: `import {First, Second, Third, Fourth, Fifth} from "./contracts.ms"

fn work(first: Int, second: Int, third: Int, fourth: Int) Int: return first
`,
		},
		{
			name: "signature includes its return type in the width budget",
			source: `fn work(first: Int, second: String) Result[Optional[Map[String, String]], ApplicationError]:
    return error(cause)
`,
			want: `fn work(
    first: Int,
    second: String
) Result[Optional[Map[String, String]], ApplicationError]:
    return error(cause)
`,
		},
		{
			name: "comments stay with arguments",
			source: `fn work() Unit:
    send(  # Delivery settings.
            first: 1, # First setting.
        # Second setting.
            second: 2,
        ) # Completed settings.
`,
			want: `fn work() Unit:
    send(  # Delivery settings.
        first: 1,  # First setting.
        # Second setting.
        second: 2,
    )  # Completed settings.
`,
		},
		{
			name: "inline closure argument",
			source: `fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int: return value + 1)
`,
			want: `fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int: return value + 1)
`,
		},
		{
			name: "indented closure argument moves with its body",
			source: `fn work() Int:
    return apply(value: 3, transform: fn(value: Int) Int:
        if value == 0: return 0
        let next = value + 1
        return next
    )
`,
			want: `fn work() Int:
    return apply(
        value: 3,
        transform: fn(value: Int) Int:
            if value == 0: return 0

            let next = value + 1
            return next
    )
`,
		},
		{
			name: "inline closure ends at its enclosing delimiter",
			source: `fn work() Bool:
    return [[1, 2], [3]].flat_map(transform: fn(value: List[Int]) List[Int]: return value) == [1, 2, 3]
`,
			want: `fn work() Bool:
    return (
        [[1, 2], [3]].flat_map(
            transform: fn(value: List[Int]) List[Int]: return value
        ) == [1, 2, 3]
    )
`,
		},
		{
			name: "compound defaults",
			source: `fn work(value: Bool = active and allowed and remaining > 0) Bool: return value
`,
			want: `fn work(value: Bool = active and allowed and remaining > 0) Bool: return value
`,
		},
		{
			name: "long collection element expression",
			source: `fn work() Unit:
    let values = [initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total, 0]
`,
			want: `fn work() Unit:
    let values = [
        initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total,
        0
    ]
`,
		},
		{
			name: "multiline match header retains compact inline arms",
			source: `fn choose(value: Choice) Int:
    match value:
        long_variant(first_payload_name, second_payload_name, third_payload_name, fourth_payload_name): return 1
        _: return 0
`,
			want: `fn choose(value: Choice) Int:
    match value:
        long_variant(
            first_payload_name,
            second_payload_name,
            third_payload_name,
            fourth_payload_name
        ): return 1
        _: return 0
`,
		},
		{
			name: "comparison suffix contributes to nested call width",
			source: `fn work() Bool:
    return Error(value: CommandError.Failed(message: "command diagnostic")).message() != "command diagnostic"
`,
			want: `fn work() Bool:
    return (
        Error(
            value: CommandError.Failed(message: "command diagnostic")
        ).message() != "command diagnostic"
    )
`,
		},
		{
			name: "condition colon contributes to width",
			source: `fn work() Int:
    if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic":
        return 1
    return 0
`,
			want: `fn work() Int:
    if (
        tagged_detail(integer) != "integer 7"
        or tagged_detail(text) != "text diagnostic"
    ):
        return 1

    return 0
`,
		},
		{
			name: "simple forms and atomic strings remain intact",
			source: `fn work() String:
    let values = [1, 2, 3]
    let text = "# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
    if enabled: return text
    return text
`,
			want: `fn work() String:
    let values = [1, 2, 3]
    let text = "# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
    if enabled: return text

    return text
`,
		},
	}
	for _, tc := range cases {
		for _, newline := range []string{"\n", "\r\n"} {
			name := tc.name + "/LF"
			if newline == "\r\n" {
				name = tc.name + "/CRLF"
			}
			t.Run(name, func(t *testing.T) {
				source := strings.ReplaceAll(tc.source, "\n", newline)
				got, err := format.Format("layout.ms", source)
				if err != nil {
					t.Fatal(err)
				}
				if got != tc.want {
					t.Fatalf("formatted:\n%s\nwant:\n%s", got, tc.want)
				}
				assertFormatMeaning(t, "layout.ms", source, got)
				twice, err := format.Format("layout.ms", got)
				if err != nil || twice != got {
					t.Fatalf("formatting is not idempotent: %v\n%s", err, twice)
				}
			})
		}
	}
}

func TestFormatTestCorpusIsCanonical(t *testing.T) {
	files := []string{
		"../../../examples/hello/src/main.ms",
		"../../../examples/hello/test.ms",
		"../../../examples/tooling-demo/src/math.ms",
	}
	err := filepath.WalkDir("../../../tests/e2e/testdata", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && strings.HasSuffix(path, ".ms") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range files {
		t.Run(path, func(t *testing.T) {
			source, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := parser.Parse(path, string(source)); err != nil {
				return // Preserve deliberate syntax-rejection fixtures.
			}
			formatted, err := format.Format(path, string(source))
			if err != nil {
				t.Fatal(err)
			}
			if formatted != string(source) {
				t.Fatalf("run ms fmt %s", path)
			}
		})
	}
}

func FuzzFormat(f *testing.F) {
	for _, path := range []string{
		"../../../tests/e2e/testdata/accept/builtin-parity.ms",
		"../../../tests/e2e/testdata/accept/inline-suites.ms",
		"../../../tests/e2e/testdata/accept/cl-18.ms",
	} {
		source, err := os.ReadFile(path)
		if err != nil {
			f.Fatal(err)
		}
		f.Add(string(source))
	}
	f.Add("fn f() Bool:\n    return active or allowed and remaining > 0\n")
	f.Fuzz(func(t *testing.T, source string) {
		_, parseError := parser.Parse("fuzz.ms", source)
		formatted, err := format.Format("fuzz.ms", source)
		if parseError != nil {
			if err == nil || formatted != "" {
				t.Fatal("invalid syntax produced formatted output")
			}
			return
		}
		if err != nil {
			t.Fatal(err)
		}
		assertFormatMeaning(t, "fuzz.ms", source, formatted)
		twice, err := format.Format("fuzz.ms", formatted)
		if err != nil || twice != formatted {
			t.Fatalf("formatting is not idempotent: %v", err)
		}
	})
}

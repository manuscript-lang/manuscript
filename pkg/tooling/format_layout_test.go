package tooling_test

import (
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFormatExpressionLayouts(t *testing.T) {
	cases := []struct {
		name, source, want string
	}{
		{
			name: "nested computations below the width limit",
			source: `fn work() -> Unit:
    send(destination: resolve(name: service, region: region), payload: encode(build(records)))
`,
			want: `fn work() -> Unit:
    send(
        destination: resolve(name: service, region: region),
        payload: encode(build(records))
    )
`,
		},
		{
			name: "long call and labeled inputs",
			source: `fn work() -> Unit:
    send(destination: destination_address, payload: encoded_message_payload, timeout: configured_request_timeout)
`,
			want: `fn work() -> Unit:
    send(
        destination: destination_address,
        payload: encoded_message_payload,
        timeout: configured_request_timeout
    )
`,
		},
		{
			name: "larger and nested collections",
			source: `fn work() -> Unit:
    let larger = [1, 2, 3, 4, 5]
    let nested = [[1, 2], [3, 4]]
`,
			want: `fn work() -> Unit:
    let larger = [
        1,
        2,
        3,
        4,
        5
    ]
    let nested = [
        [1, 2],
        [3, 4]
    ]
`,
		},
		{
			name: "compound conditions keep inline guards",
			source: `fn work() -> Int:
    if active and allowed and remaining > 0: return 1
    return 0
`,
			want: `fn work() -> Int:
    if (
        active
        and allowed
        and remaining > 0
    ): return 1

    return 0
`,
		},
		{
			name: "boolean precedence and comparison operands",
			source: `fn work() -> Bool:
    return active or allowed and remaining > 0 or fallback
`,
			want: `fn work() -> Bool:
    return (
        active
        or allowed and remaining > 0
        or fallback
    )
`,
		},
		{
			name: "compound argument values",
			source: `fn work() -> Unit:
    send(condition: active and allowed and remaining > 0, payload: "data")
`,
			want: `fn work() -> Unit:
    send(
        condition: (
            active
            and allowed
            and remaining > 0
        ),
        payload: "data"
    )
`,
		},
		{
			name: "mixed boolean clauses",
			source: `fn work() -> Bool:
    return active or allowed and remaining > 0
`,
			want: `fn work() -> Bool:
    return (
        active
        or allowed and remaining > 0
    )
`,
		},
		{
			name: "long arithmetic retains precedence",
			source: `fn work() -> Int:
    return initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total
`,
			want: `fn work() -> Int:
    return (
        initial_account_balance
        + pending_deposit_total * applicable_exchange_rate
        - pending_withdrawal_total
    )
`,
		},
		{
			name: "long chain has one operation per line",
			source: `fn work() -> String:
    return incoming_request_payload.normalize_whitespace().replace(old: legacy_separator, new: current_separator).trim()
`,
			want: `fn work() -> String:
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
fn work(first: Int, second: Int, third: Int, fourth: Int) -> Int: return first
`,
			want: `import {
    First,
    Second,
    Third,
    Fourth,
    Fifth
} from "./contracts.ms"

fn work(
    first: Int,
    second: Int,
    third: Int,
    fourth: Int
) -> Int: return first
`,
		},
		{
			name: "signature includes its return type in the width budget",
			source: `fn work(first: Int, second: String) -> Result[Optional[Map[String, String]], ApplicationError]:
    return error(cause)
`,
			want: `fn work(
    first: Int,
    second: String
) -> Result[Optional[Map[String, String]], ApplicationError]:
    return error(cause)
`,
		},
		{
			name: "comments stay with arguments",
			source: `fn work() -> Unit:
    send(  # Delivery settings.
            first: 1, # First setting.
        # Second setting.
            second: 2,
        ) # Completed settings.
`,
			want: `fn work() -> Unit:
    send(  # Delivery settings.
        first: 1,  # First setting.
        # Second setting.
        second: 2,
    )  # Completed settings.
`,
		},
		{
			name: "inline closure argument",
			source: `fn work() -> Int:
    return apply(value: 3, transform: fn(value: Int) -> Int: return value + 1)
`,
			want: `fn work() -> Int:
    return apply(
        value: 3,
        transform: fn(value: Int) -> Int: return value + 1
    )
`,
		},
		{
			name: "indented closure argument moves with its body",
			source: `fn work() -> Int:
    return apply(value: 3, transform: fn(value: Int) -> Int:
        if value == 0: return 0
        let next = value + 1
        return next
    )
`,
			want: `fn work() -> Int:
    return apply(
        value: 3,
        transform: fn(value: Int) -> Int:
            if value == 0: return 0

            let next = value + 1
            return next
    )
`,
		},
		{
			name: "inline closure ends at its enclosing delimiter",
			source: `fn work() -> Bool:
    return [[1, 2], [3]].flat_map(transform: fn(value: List[Int]) -> List[Int]: return value) == [1, 2, 3]
`,
			want: `fn work() -> Bool:
    return (
        [
            [1, 2],
            [3]
        ].flat_map(
            transform: fn(value: List[Int]) -> List[Int]: return value
        ) == [1, 2, 3]
    )
`,
		},
		{
			name: "compound defaults",
			source: `fn work(value: Bool = active and allowed and remaining > 0) -> Bool: return value
`,
			want: `fn work(
    value: Bool = (
        active
        and allowed
        and remaining > 0
    )
) -> Bool: return value
`,
		},
		{
			name: "long collection element expression",
			source: `fn work() -> Unit:
    let values = [initial_account_balance + pending_deposit_total * applicable_exchange_rate - pending_withdrawal_total, 0]
`,
			want: `fn work() -> Unit:
    let values = [
        (
            initial_account_balance
            + pending_deposit_total * applicable_exchange_rate
            - pending_withdrawal_total
        ),
        0
    ]
`,
		},
		{
			name: "multiline match header retains compact inline arms",
			source: `fn choose(value: Choice) -> Int:
    match value:
        long_variant(first_payload_name, second_payload_name, third_payload_name, fourth_payload_name): return 1
        _: return 0
`,
			want: `fn choose(value: Choice) -> Int:
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
			source: `fn work() -> Bool:
    return Error(value: CommandError.Failed(message: "command diagnostic")).message() != "command diagnostic"
`,
			want: `fn work() -> Bool:
    return (
        Error(
            value: CommandError.Failed(message: "command diagnostic")
        ).message() != "command diagnostic"
    )
`,
		},
		{
			name: "condition colon contributes to width",
			source: `fn work() -> Int:
    if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic":
        return 1
    return 0
`,
			want: `fn work() -> Int:
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
			source: `fn work() -> String:
    let values = [1, 2, 3]
    let text = "# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
    if enabled: return text
    return text
`,
			want: `fn work() -> String:
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
				got, err := tooling.Format("layout.ms", source)
				if err != nil {
					t.Fatal(err)
				}
				if got != tc.want {
					t.Fatalf("formatted:\n%s\nwant:\n%s", got, tc.want)
				}
				assertFormatMeaning(t, "layout.ms", source, got)
				twice, err := tooling.Format("layout.ms", got)
				if err != nil || twice != got {
					t.Fatalf("formatting is not idempotent: %v\n%s", err, twice)
				}
			})
		}
	}
}

func TestFormatTestCorpusIsCanonical(t *testing.T) {
	files := []string{"../../examples/hello/test.ms", "../../examples/tooling-demo/src/math.ms"}
	err := filepath.WalkDir("../../tests/e2e/testdata", func(path string, entry fs.DirEntry, err error) error {
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
			formatted, err := tooling.Format(path, string(source))
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
		"../../tests/e2e/testdata/accept/builtin-parity.ms",
		"../../tests/e2e/testdata/accept/inline-suites.ms",
		"../../tests/e2e/testdata/accept/cl-18.ms",
	} {
		source, err := os.ReadFile(path)
		if err != nil {
			f.Fatal(err)
		}
		f.Add(string(source))
	}
	f.Add("fn f() -> Bool:\n    return active or allowed and remaining > 0\n")
	f.Fuzz(func(t *testing.T, source string) {
		_, parseError := parser.Parse("fuzz.ms", source)
		formatted, err := tooling.Format("fuzz.ms", source)
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
		twice, err := tooling.Format("fuzz.ms", formatted)
		if err != nil || twice != formatted {
			t.Fatalf("formatting is not idempotent: %v", err)
		}
	})
}

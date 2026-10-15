package tooling_test

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"strings"
	"testing"
)

func TestFormatParagraphs(t *testing.T) {
	cases := []struct {
		name, source, want string
	}{
		{
			name: "interleaved import sections",
			source: `fn first() -> Int: return 1
import Value from "./value.ms"
import Other from "./other.ms"
fn last() -> Int: return 2
`,
			want: `fn first() -> Int: return 1

import Value from "./value.ms"
import Other from "./other.ms"

fn last() -> Int: return 2
`,
		},
		{
			name: "bindings guards and outcome handling",
			source: `fn process(input: String) -> Int:
    let records = parse(input)
    if records.length == 0: return 0
    if records.length > 100: return 1
    let report = summarize(records)
    let payload = encode(report)
    match save(payload):
        ok(_):
            return 0
        error(_):
            return 1
`,
			want: `fn process(input: String) -> Int:
    let records = parse(input)
    if records.length == 0: return 0
    if records.length > 100: return 1

    let report = summarize(records)
    let payload = encode(report)

    match save(payload):
        ok(_):
            return 0
        error(_):
            return 1
`,
		},
		{
			name: "branch families loops and cleanup",
			source: `fn work(enabled: Bool) -> Int:
    let count = 2
    if enabled:
        run(count)
    else if count > 0: run(1)
    else:
        run(0)
    while enabled:
        if count == 0: break
        run(count)
        break
    for item in [1, 2]:
        if item == 1: continue
        run(item)
    with resource = acquire():
        run(resource)
    return count
`,
			want: `fn work(enabled: Bool) -> Int:
    let count = 2

    if enabled:
        run(count)
    else if count > 0: run(1)
    else:
        run(0)

    while enabled:
        if count == 0: break

        run(count)
        break

    for item in [1, 2]:
        if item == 1: continue

        run(item)

    with resource = acquire():
        run(resource)

    return count
`,
		},
		{
			name: "compact and indented match arms",
			source: `fn choose(value: Choice) -> Int:
    match value:
        first: return 1
        second: return 2
        third:
            let result = calculate()
            return result
        _: return 0
    return 3
`,
			want: `fn choose(value: Choice) -> Int:
    match value:
        first: return 1
        second: return 2
        third:
            let result = calculate()
            return result
        _: return 0

    return 3
`,
		},
		{
			name: "comments stay attached",
			source: `# A public contract.
export interface Run:
    fn first() -> Int
    fn second() -> Int
# The implementation.
impl Run for Runner:
    fn first() -> Int: return 1
    # Explain the second operation.
    fn second() -> Int:
        let value = 2
        # Handle both outcomes.
        # Keep these comments together.
        match value:
            one: return 1
            # Fallback explanation.
            _:
                return 2
# Application entry.
fn main() -> Int: return 0
`,
			want: `# A public contract.
export interface Run:
    fn first() -> Int
    fn second() -> Int

# The implementation.
impl Run for Runner:
    fn first() -> Int: return 1

    # Explain the second operation.
    fn second() -> Int:
        let value = 2

        # Handle both outcomes.
        # Keep these comments together.
        match value:
            one: return 1
            # Fallback explanation.
            _:
                return 2

# Application entry.
fn main() -> Int: return 0
`,
		},
		{
			name: "nested closure paragraphs",
			source: `fn example() -> Int:
    let result = apply(
        value: 3,
        transform: (
            fn(value: Int) -> Int:
                if value == 0: return 0
                let next = value + 1
                return next
        )
    )
    return result
`,
			want: `fn example() -> Int:
    let result = apply(
        value: 3,
        transform: (
            fn(value: Int) -> Int:
                if value == 0: return 0

                let next = value + 1
                return next
        )
    )
    return result
`,
		},
		{
			name: "author paragraphs and different indent comments",
			source: `# File introduction.
fn example() -> Int:
    let first = 1


    # A deliberate new step.
    let second = first + 1
    if second > 2:
        run(second)
        # A comment inside the branch.
    # A comment on the next step.
    return second
`,
			want: `# File introduction.
fn example() -> Int:
    let first = 1

    # A deliberate new step.
    let second = first + 1

    if second > 2:
        run(second)
        # A comment inside the branch.

    # A comment on the next step.
    return second
`,
		},
		{
			name: "multiline expressions collapse unless commented",
			source: `fn example(
    value: Int = choose(
        first: 1,
        second: 2
    )
) -> Int:
    let text = "# if value: return {value}"
    let next = choose(
        first: value,
        # Explain this argument.
        second: 2
    )
    if (
        next > 0
        and value > 0
    ): return next
    return 0
`,
			want: `fn example(value: Int = choose(first: 1, second: 2)) -> Int:
    let text = "# if value: return {value}"
    let next = choose(
        first: value,
        # Explain this argument.
        second: 2
    )
    if (next > 0 and value > 0): return next

    return 0
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
				got, err := tooling.Format("paragraphs.ms", source)
				if err != nil {
					t.Fatal(err)
				}
				if got != tc.want {
					t.Fatalf("formatted source:\n%s\nwant:\n%s", got, tc.want)
				}
				twice, err := tooling.Format("paragraphs.ms", got)
				if err != nil || twice != got {
					t.Fatalf("formatting is not idempotent: %v\n%s", err, twice)
				}
				original, err := lexer.Lex("paragraphs.ms", source)
				if err != nil {
					t.Fatal(err)
				}
				formatted, err := lexer.Lex("paragraphs.ms", got)
				if err != nil {
					t.Fatal(err)
				}
				if len(original) != len(formatted) {
					t.Fatal("formatting changed the token count")
				}
				for i, token := range original {
					if token.Kind != formatted[i].Kind || token.Text != formatted[i].Text {
						t.Fatalf("formatting changed token %d: %+v -> %+v", i, token, formatted[i])
					}
				}
			})
		}
	}
}

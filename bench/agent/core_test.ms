# Unit tests for the runner's core. Run from the repository root: ms test bench/agent/core_test.ms
import access, glob from "@std/os/fs.ms"
import JsonValue, parse from "@std/data/json.ms"
import expect_close, expect_equal, expect_false, expect_true, fail from "@std/test/test.ms"
import cost_from_tokens, load_challenges, load_languages from "./core/model.ms"
import count_text from "./core/codetokens.ms"
import ClaudeCode from "./harnesses/claude_code.ms"
import Codex from "./harnesses/codex.ms"
import dumps from "./lib/pyjson.ms"
import fmt_g, fixed, pct0 from "./lib/pyfmt.ms"
import seeded from "./lib/pyrandom.ms"
import norm from "./lib/text.ms"

test "norm ignores trailing whitespace only":
    try expect_equal(norm("a  \nb\n\n"), norm("a\nb"))
    try expect_false(norm("a\nb") == norm("b\na"))
    try expect_equal(norm(""), norm("\n"))

test "every challenge is complete":
    let langs = load_languages([])
    let chs = load_challenges([])
    try expect_true(not chs.is_empty())

    for ch in chs:
        try expect_true(not ch.cases("examples").is_empty())
        try expect_true(ch.cases("hidden").length() > ch.cases("examples").length() - 1)

        let visible = ch.cases("examples").map(fn c: c.stdin.clone())
        if not ch.cases("hidden").any(fn c: not visible.contains(c.stdin)): try fail(
            "{ch.id}: hidden cases add nothing"
        )

        if access("{ch.dir}/oracle", 0).is_ok():
            # Large challenges: Go oracle only, no per-language references.
            if glob("{ch.dir}/oracle", "*.ref", none).get([]).is_empty(): try fail(
                "{ch.id}: empty oracle"
            )
            continue

        for lang in langs:
            if not access("{ch.solution(lang.template)}/{lang.reference()}", 0).is_ok(): try fail(
                "{ch.id}: missing {lang.id} reference solution"
            )

test "claude code parse":
    let lines = [
        "\{\"type\": \"assistant\"\}",
        "\{\"type\": \"result\", \"num_turns\": 7, \"total_cost_usd\": 0.5, \"usage\": \{\"input_tokens\": 10, \"output_tokens\": 20, \"cache_read_input_tokens\": 100, \"cache_creation_input_tokens\": 5\}\}"
    ]
    let u = ClaudeCode().parse(lines.join("\n"))
    try expect_equal(u.tokens_in, 10)
    try expect_equal(u.tokens_cached, 105)
    try expect_equal(u.tokens_out, 20)
    try expect_equal(u.turns, 7)
    try expect_close(u.cost_usd, 0.5, 0.0000001)
    try expect_equal(u.cost_source, "harness")

test "codex parse sums turns and splits cache":
    let event = "\{\"type\": \"turn.completed\", \"usage\": \{\"input_tokens\": 100, \"cached_input_tokens\": 60, \"output_tokens\": 5\}\}"
    let u = Codex().parse([event.clone(), event.clone()].join("\n"))
    try expect_equal(u.tokens_in, 80)
    try expect_equal(u.tokens_cached, 120)
    try expect_equal(u.tokens_out, 10)
    try expect_equal(u.turns, 2)

test "cost estimate":
    try expect_close(cost_from_tokens(1000000, 0, 0, "default"), 3.0, 0.0000001)

test "code tokens skip comments":
    try expect_equal(count_text("a // c\nb /* x\ny */ c"), 3)
    try expect_equal(count_text("f(\"a b\", 1.5)"), 6)

test "random matches CPython's Mersenne Twister":
    var r = seeded(3)
    try expect_equal(r.randint(0, 999), 243)
    try expect_equal(r.randint(0, 999), 606)
    try expect_equal(r.randint(0, 999), 557)

    var s = seeded(3)
    try expect_equal(s.randrange(5, 50), 20)

test "json layout matches json.dumps":
    let doc = parse("[\{\"a\": \"é\\n\", \"b\": [], \"c\": \{\}\}, 1]").get(
        JsonValue.Null
    )
    try expect_equal(
        dumps(doc, 1),
        "[\n \{\n  \"a\": \"\\u00e9\\n\",\n  \"b\": [],\n  \"c\": \{\}\n \},\n 1\n]"
    )
    try expect_equal(
        dumps(doc, 0), "[\{\"a\": \"\\u00e9\\n\", \"b\": [], \"c\": \{\}\}, 1]"
    )

test "number formats match CPython":
    try expect_equal(fixed(17.25, 1), "17.2")
    try expect_equal(fixed(0.35, 1), "0.3")
    try expect_equal(fmt_g(981756.0, 3), "9.82e+05")
    try expect_equal(fmt_g(0.026123, 3), "0.0261")
    try expect_equal(pct0(0.125), "12%")

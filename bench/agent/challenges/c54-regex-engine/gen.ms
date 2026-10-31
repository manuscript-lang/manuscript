# Generator for c54-regex-engine. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c54
import Cases, build_oracle, write_cases from "../../lib/gen.ms"

fn rep(text: String, count: Int) String:
    return text.repeat(count).get("")

fn line(cmd: String, pat: String, subj: String = "", repl: String? = none) String:
    var fields = [cmd, pat, subj]
    if let r = repl:
        fields.append(r)

    return fields.join("\t") + "\n"

fn M(pat: String, subj: String) String:
    return line("match", pat, subj)

fn T(pat: String, subj: String) String:
    return line("test", pat, subj)

fn F(pat: String, subj: String) String:
    return line("full", pat, subj)

fn A(pat: String, subj: String) String:
    return line("find-all", pat, subj)

fn R(pat: String, subj: String, repl: String) String:
    return line("replace", pat, subj, repl)

fn S(pat: String, subj: String) String:
    return line("split", pat, subj)


export fn gen_c54() Unit:
    var cs = Cases(build_oracle("c54-regex-engine"))
    cs.push("literals", M("abc", "xxabcxx") + M("abc", "ab") + M("", "abc") + M("a.c", "abc") + M("a.c", "a\\nc") + M("a\\.c", "a.c") + M("a\\.c", "abc") + T("hello", "say hello") + T("hello", "Hello") + F("abc", "abc") + F("abc", "abcd") + F("abc", "xabc") + F("", "") + F("", "a"))
    cs.push("escapes", M("\\x41\\x62", "Ab") + M("a\\tb", "a\\tb") + M("\\n", "x\\ny") + M("a\\/b", "a/b") + M("\\(\\)\\[\\]\\\{\\\}\\*\\+\\?\\|\\^\\$\\\\", "()[]\{\}*+?|^$\\\\") + M("\\-\\ \\#\\@", "- #@") + M("\\r", "a\\x0db") + M("[\\x41-\\x43]+", "xABCDx"))
    cs.push("classes", M("[abc]+", "xxbcaxx") + M("[^abc]+", "abxyzc") + M("[a-z]+", "ABcdeFG") + M("[A-Za-z_][A-Za-z0-9_]*", "  _foo9 bar") + M("[0-9]+", "ab123cd") + M("[a-]+", "a-a-b") + M("[-a]+", "-a-b") + M("[]a]+", "x]a]") + M("[^]a]+", "]]xy]") + M("[.]", "a.b") + M("[*+?]+", "a*+?b") + M("[\\]\\\\]+", "a]\\\\b") + M("[\\^a]+", "^^a") + M("[a^]+", "a^^") + M("[\\n]", "a\\nb") + M("[a-cx-z]+", "abxyzd"))
    cs.push("shorthand", M("\\d+", "abc 123 def") + M("\\D+", "123abc456") + M("\\w+", "  hello_world9! ") + M("\\W+", "ab  ,. cd") + M("\\s+", "a \\t\\n b") + M("\\S+", "  tok  ") + M("[\\d.]+", "v1.2.3x") + M("[^\\d\\s]+", "12 ab 34") + M("[\\w-]+", "foo-bar baz") + M("[\\D]+", "12ab34") + M("[\\s\\d]+", "a 1 2 b"))
    cs.push("anchors", M("^abc", "abcabc") + M("^abc", "xabc") + M("abc$", "abcabc") + M("abc$", "abcx") + M("^$", "") + M("^$", "a") + T("^$", "\\n") + M("a$", "a\\n") + M("^b", "a\\nb") + M("a$", "a\\nb") + M("^.*$", "ab\\ncd") + A("^", "abc") + A("$", "abc") + A("^a", "aaa"))
    cs.push("word-boundary", M("\\bfoo\\b", "a foo b") + M("\\bfoo\\b", "afoo foob foo") + A("\\b", "ab cd") + A("\\B", "ab cd") + A("\\b\\w", "ab cd") + A("\\w\\b", "ab cd") + M("\\Bfoo", "foo afoo") + T("\\b", "") + T("\\B", "") + T("\\b", "!") + A("\\bx", "x xx x"))
    cs.push("quantifiers-greedy", M("a*", "aaab") + M("a+", "baaa") + M("a?", "aa") + M("a\{2\}", "aaaa") + M("a\{2,\}", "aaaa") + M("a\{1,3\}", "aaaa") + M("a\{0\}", "aaa") + M("a\{0,1\}b", "aab") + M("x*y", "xxxz") + M("ab*c", "abbbc") + M("(ab)+", "ababab!") + M("(ab)\{2\}", "ababab") + M("<.*>", "<a><b>") + M("a.*b", "a1b2b3") + M("[0-9]\{3\}-[0-9]\{4\}", "call 555-1234 now"))
    cs.push("quantifiers-lazy", M("a*?", "aaa") + M("a+?", "aaa") + M("a??b", "ab") + M("a\{2,\}?", "aaaa") + M("a\{1,3\}?", "aaaa") + M("<.*?>", "<a><b>") + M("<.+?>", "<a><b>") + M("a.*?b", "a1b2b3") + M("(a+?)(a*)", "aaa") + M("(a+)(a*?)", "aaa") + F("a*?b", "aaab") + M("\"(.*?)\"", "say \"hi\" and \"bye\"") + M("x\{2,3\}?y", "xxxy"))
    cs.push("quantifier-literal-braces", M("a\{", "a\{") + M("a\{x\}", "a\{x\}") + M("a\{1", "a\{1") + M("a\{,3\}", "a\{,3\}") + M("\{2\}", "\{2\}") + M("\{", "\{") + M("\}", "\}") + M("a\{1,2,3\}", "a\{1,2,3\}") + M("a\{2\}b\{", "aab\{") + M("(a|\{)", "\{") + M("a|\{2\}", "\{2\}") + M("]", "]"))
    cs.push("alternation", M("cat|dog", "hotdog") + M("cat|dog", "category") + M("a|ab", "ab") + M("ab|a", "ab") + M("(a|ab)(c|bcd)", "abcd") + M("x(a|b|c)y", "xby") + M("a||b", "b") + M("|a", "a") + M("a|", "b") + M("(|a)+", "aaa") + M("(a|b)*c", "abbac") + M("^(foo|bar)$", "bar") + M("^(foo|bar)$", "foobar") + A("a|b", "cab") + M("(?:a|b)+", "abba"))
    cs.push("groups-capture", M("(a)(b)(c)", "abc") + M("(a(b(c)))", "abc") + M("((a)|(b))+", "ab") + M("(a)|(b)", "b") + M("(a)?b", "b") + M("(a)*b", "b") + M("(a)*b", "aab") + M("(\\d+)-(\\d+)", "tel 12-345") + M("(?:ab)+(c)", "ababc") + M("()", "x") + M("(())", "x") + M("(a*)+", "b") + M("(a*)*", "aab") + M("(a|b)*", "ab") + M("(a+|b+)*c", "aabbc") + M("((a)|b)+", "ab") + M("(?:(a)|b)+", "ab"))
    cs.push("groups-named", M("(?<year>\\d\{4\})-(?<mon>\\d\\d)", "on 2024-05-17") + M("(?<a>x)(?<b>y)?", "x") + M("(?<n_1>a)(b)(?<z>c)", "abc") + M("(?<a>a)\\k<a>", "aa") + M("(?<a>a)\\k<a>", "ab") + M("(?<x>.)(?<y>.)\\k<y>\\k<x>", "abba") + T("(?<a>a)(?<a>b)", "ab") + T("(?<>a)", "a") + T("(?<1a>a)", "a") + T("(?<a", "a") + T("(?<a>a)\\k<b>", "a") + T("\\k<a>(?<a>a)", "a") + T("(?<a b>a)", "a") + T("\\k", "a") + T("\\k<>", "a"))
    cs.push("backrefs", M("(a)\\1", "aa") + M("(a)\\1", "ab") + M("(\\w+) \\1", "the the cat") + M("(\\w)(\\w)\\2\\1", "xabbay") + M("(a*)b\\1", "aabaa") + M("(a*)b\\1", "aaba") + M("(a)?\\1", "b") + M("(a)|\\1b", "b") + M("(?i)(a)\\1", "aA") + M("(a)(b)(c)(d)(e)(f)(g)(h)(i)\\9", "abcdefghii") + T("(a)\\2", "aa") + T("\\1(a)", "aa") + T("(a\\1)", "aa") + M("(.)\\1+", "xaaay") + M("^(.+)\\1$", "abcabc") + M("^(.+)\\1$", "abcab") + T("\\1", "a") + T("\\0", "a") + M("(a)\\10", "aa0") + M("(['\\\"]).*?\\1", "say 'hi' ok"))
    cs.push("lookahead", M("a(?=b)", "acab") + M("a(?!b)", "abac") + M("\\w+(?=;)", "ab cd; ef") + M("(?=(a+))a*b\\1", "baaabac") + M("(?!a)\\w", "abc") + M("(?=.*\\d)(?=.*[a-z]).\{4,\}", "abc1") + F("(?=.*\\d)(?=.*[a-z]).\{4,\}", "abcd") + M("a(?=(b))", "ab") + M("a(?!(b))", "ac") + M("(?=a)", "ba") + A("(?=a)", "aaa") + A("\\d(?=(\\d\{3\})+$)", "1234567") + T("(?=a)*", "a") + T("(?!a)+", "a") + T("(?=a", "a") + M("(?=a)a", "a") + T("(?<=a)b", "ab") + T("(?<!a)b", "ab"))
    cs.push("flags", T("(?i)abc", "xABCx") + M("(?i)[a-c]+", "xAbCd") + M("(?i)[^a]+", "AAbA") + M("(?i)\\w+", "Ab_") + T("(?s)a.b", "a\\nb") + T("a.b", "a\\nb") + A("(?m)^\\w+", "ab\\ncd\\n\\nef") + A("(?m)\\w+$", "ab\\ncd\\n\\nef") + A("^\\w+", "ab\\ncd") + M("(?ims)^a.b$", "x\\nA\\nB\\ny") + A("(?mi)^[a-b]", "a\\nB\\nc") + T("(?x)a", "a") + T("(?i", "a") + T("a(?i)", "a") + T("(?)", "a") + T("(?i)(?s)a", "a") + T("(?ii)a", "A") + M("(?i:ab)c", "ABc"))
    cs.push("replace-basic", R("a", "banana", "o") + R("an", "banana", "[$0]") + R("(\\w+)@(\\w+)", "me@host you@there", "$2:$1") + R("x*", "abc", "-") + R("", "abc", "|") + R("b", "abc", "$$") + R("b", "abc", "$") + R("b", "abc", "a$") + R("b", "abc", "$x") + R("(b)", "abc", "$1$1") + R("(b)", "abc", "$10") + R("(b)|(c)", "abc", "[$1,$2]") + R("a", "aaa", "") + R("\\s+", "a  b \\t c", " ") + R("(?<w>\\w+)", "ab cd", "<$\{w\}>") + R("(?<w>b)", "abc", "$\{w\}$\{w\}") + R("^", "a\\nb", ">") + R("(?m)^", "a\\nb", ">") + R("$", "ab", "!") + R("b", "abc", "\\n") + R("b", "abc", "\\\\"))
    cs.push("replace-errors", R("a", "a", "$1") + R("(a)", "a", "$2") + R("(a)", "a", "$\{x\}") + R("(?<x>a)", "a", "$\{x") + R("(?<x>a)", "a", "$\{y\}") + R("(a)", "a", "$\{1\}") + R("a", "b", "$1") + R("(a)", "b", "$2") + R("a", "a", "$0$0") + R("(?<x>a)", "a", "$\{\}"))
    cs.push("find-all", A("a", "banana") + A("an", "banana") + A("a*", "baac") + A("a*?", "aa") + A("", "ab") + A("x", "abc") + A("\\d+", "a1b22c333") + A("(?=a)", "aa") + A("\\b\\w", "hi there you") + A("a|ab", "abab") + A(".", "a\\nb") + A("aa", "aaaaa") + A("\\w*", "ab cd") + A("a?", "baab") + A("[a-c]*", "abcdabc"))
    cs.push("split", S(",", "a,b,,c") + S(",", ",a,") + S(",", "") + S(",", "abc") + S("\\s+", "  a  b ") + S("x*", "axxb") + S("", "abc") + S("(,)", "a,b") + S("[,;]", "a;b,c") + S("b+", "abbbc") + S("^", "a\\nb") + S("(?m)^", "a\\nb") + S("a", "aaa"))
    cs.push("full-match", F("a|ab", "ab") + F("(a|ab)(c|bcd)", "abcd") + F("(a|ab)(c|bcd)(d*)", "abcd") + F("a*", "aaa") + F("a*?", "aaa") + F("a+?", "aaa") + F("(a+?)(a*)", "aaa") + F("\\d+", "123") + F("\\d+", "12a") + F("[a-z]+@[a-z]+\\.com", "joe@site.com") + F("(.)(.)", "ab") + F(".*", "") + F("^a$", "a") + F("(?m)^a$", "a\\nb") + F(".", "\\n"))
    cs.push("empty-loops", M("(a*)*", "aaa") + M("(a*)+", "aaa") + M("(a|b*)*", "ab") + M("(a?)*", "aa") + M("(a?)*?b", "aab") + M("(?:a*)*b", "aaab") + M("(a*)*b", "aaab") + M("(a*)\{2\}", "aaa") + M("(a*)\{2,3\}", "aaa") + M("(a*)+?b", "aab") + M("()\{3\}", "a") + M("()*", "a") + M("(a|)+", "aab") + M("((a)|(b)|())+", "abx"))
    cs.push("nested-quantifiers", M("(a+)+b", "aaab") + M("(a+)+b", "aaac") + M("(a|aa)+$", "aaaa") + M("(a*b)*c", "abaabbc") + M("((a+)b)+", "aabab") + M("(?:a\{2\})\{2,3\}", "aaaaaaaaa") + M("(a\{1,2\})\{2\}", "aaaa") + M("(ab|a)(bc|c)?", "abc") + M("(a+)(b+)?", "aac") + M("(\\d+)(?:\\.(\\d+))?", "v3 and 4.25"))
    cs.push("practical", M("^[\\w.+-]+@[\\w-]+\\.[\\w.-]+$", "john.doe+tag@example.co.uk") + T("^[\\w.+-]+@[\\w-]+\\.[\\w.-]+$", "not an email") + M("(\\d\{1,3\})\\.(\\d\{1,3\})\\.(\\d\{1,3\})\\.(\\d\{1,3\})", "ip 192.168.0.12 end") + M("^#?([a-f0-9]\{6\}|[a-f0-9]\{3\})$", "#a3c113") + A("\\b[A-Z][a-z]+\\b", "Alice met Bob and carol in Paris") + A("\\$\\d+(?:\\.\\d\\d)?", "cost $5, $12.50 or $7.5") + R("(\\d+)", "a1b22", "<$1>") + R("(?<d>\\d)(?<m>\\d)", "12 34", "$\{m\}$\{d\}") + R("^\\s+|\\s+$", "  trim me  ", "") + R("(\\w)(\\w*)", "hello big world", "$2$1ay") + M("(?i)^(?:(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)(?:\\.|$))\{4\}$", "10.0.255.1") + S("\\s*;\\s*", "a ; b;c  ;  d") + M("^(\\w+)\\s*=\\s*\"([^\"]*)\"$", "key = \"some value\"") + M("<(\\w+)>.*?</\\1>", "x <b>bold</b> <i>it</i>") + A("(\\w+)=(\\w+)", "a=1, bb=22;c=3"))
    cs.push("parse-errors-1", T("(a", "a") + T("a)", "a") + T("(", "a") + T(")", "a") + T("((a)", "a") + T("(a))", "a") + T("*a", "a") + T("+", "a") + T("?", "a") + T("a**", "a") + T("a+*", "a") + T("a*+", "a") + T("a??", "a") + T("a???", "a") + T("a\{2\}\{3\}", "a") + T("a\{2\}*", "a") + T("a\{2\}?", "a") + T("a\{2\}??", "a") + T("(*a)", "a") + T("|*", "a") + T("a|*", "a") + T("^*", "a") + T("$+", "a") + T("\\b*", "a") + T("\\B?", "a") + T("(?=a)+", "a"))
    cs.push("parse-errors-2", T("[a", "a") + T("[", "a") + T("[]", "a") + T("[^", "a") + T("[z-a]", "a") + T("[a-\\d]", "a") + T("[\\d-z]", "a") + T("[\\b]", "a") + T("[\\1]", "a") + T("\\", "a") + T("a\\", "a") + T("\\q", "a") + T("\\0", "a") + T("\\x4", "a") + T("\\xZZ", "a") + T("[\\x4]", "a") + T("\\A", "a") + T("\\z", "a") + T("\\p\{L\}", "a") + T("\\u0041", "a") + T("(?z)", "a") + T("(?", "a") + T("(?>a)", "a") + T("a\{3,2\}", "a") + T("a\{1001\}", "a") + T("a\{0,1001\}", "a") + T("a\{1000\}", "a") + T("a\{99999999\}", "a") + T("(?<=a)b", "a"))
    cs.push("parse-error-order", T("(a\\1", "a") + T("a)\\1", "a") + T("(a)\\2)", "a") + T("*(", "a") + T("(*", "a") + T("[a\\q", "a") + T("\\q[", "a") + T("(?<a>a)(?<a>b)\\k<c>", "a") + T("\\k<c>(?<a>a)(?<a>b)", "a") + T("a\{3,2\}(", "a") + T("(a\{3,2\}", "a"))
    cs.push("bad-commands", "\n" + "bogus\ta\tb\n" + "match\ta\n" + "match\ta\tb\tc\n" + "replace\ta\tb\n" + "replace\ta\tb\tc\td\n" + "test\n" + "match\ta\tb\\q\n" + "match\ta\tb\\\n" + "match\ta\t\\x4\n" + "replace\ta\ta\t\\z\n" + "MATCH\ta\ta\n" + "match\t\t\n" + "match\t(\tb\\q\n" + "\n")
    cs.push("subject-escapes", M("a\\\\b", "a\\\\b") + M("\\\\", "x\\\\y") + M("\\n", "a\\nb") + A("\\t", "\\t\\t") + M(".+", "\\x01\\x7f\\xe9\\x80") + M("[^a]", "\\xff") + M("\\xff", "\\xff") + M("\\w", "\\xe9") + M(".", "\\x00") + A("\\W", "\\x00 \\xff"))
    cs.push("output-quoting", A("\\W", "a\"b\\\\c\\nd\\te\\x01\\x7f") + R("x", "x", "\"\\\\\\n\\t"))
    var numbers = List[String]()
    for i in 0..200:
        numbers.append("{i}")
    cs.push("long-input", M("(a|b)*c", rep("ab", 500) + "c") + A("ab", rep("ab", 300)) + A("b+", rep("abbbabbab", 50)) + M("^(\\w+\\s?)+$", rep("word ", 40) + "end") + R("o", rep("foo boo ", 100), "0") + S(",", numbers.join(",")) + M(rep("x", 50) + "y", rep("x", 49) + "xy"))
    cs.push("priority-and-leftmost", M("a*?b|a", "aab") + M("(a|ab)*c", "abac") + M("(ab|a)(bc|c)", "abc") + M("(a+)(b)?(c)?", "aab") + M("x*", "aaa") + M("x*?", "aaa") + M("b|ab", "ab") + M("(?:b|ab)", "ab") + M("a+|b+", "bbaaa") + M("(a)|b", "xb") + A("a|b|ab", "abab") + M("a(?:b|c|)d", "ad") + M("(wo|wor)ld", "world") + M("(?:w|wo)(rld|orld)", "world"))
    cs.push("ignore-case-more", A("(?i)[a-c]", "aBcD") + A("(?i)[^a-c]", "aBcD") + M("(?i)straSSe", "STRASSE") + M("(?i)\\bthe\\b", "Is THE one") + M("(?i)(a)(B)\\1\\2", "aBAb") + M("(?i)[A-Z]+", "abcXYZ123") + A("(?i)k", "kK") + M("(?i)\\x41", "a") + T("(?i)[\\x41-\\x43]", "b") + R("(?i)hello", "Hello HELLO hello", "bye"))
    cs.push("dot-newline", M(".*", "ab\\ncd") + M("(?s).*", "ab\\ncd") + A(".", "a\\nb") + A("(?s).", "a\\nb") + M("a.b", "a\\rb") + M("[^x]+", "a\\nb") + F("(?s)a.*b", "a\\n\\nb") + F("a.*b", "a\\n\\nb"))
    cs.push("multiline-anchors", A("(?m)^", "a\\nb\\n") + A("(?m)$", "a\\nb\\n") + A("(?m)^$", "a\\n\\nb") + A("(?m)^\\w", "ab\\ncd\\nef") + M("(?m)^b$", "a\\nb\\nc") + M("^b$", "a\\nb\\nc") + R("(?m)^", "x\\ny", "> ") + R("(?m)$", "x\\ny", ";") + S("(?m)\\n", "a\\nb\\nc"))
    cs.push("quantified-groups-captures", M("(a)+", "aaa") + M("(a|b)+", "abab") + M("(\\w)+", "abc") + M("(?:(\\w)\\s?)+", "a b c") + M("(a)(b)?(c)", "ac") + M("(a(b)?)+", "aba") + M("(a(b)?)+", "abaa") + M("((a)|(b))+", "ba") + M("(\\d)(\\d)?(\\d)?(\\d)?", "12") + M("(x)?(y)?z", "z") + M("(a)\{2\}", "aaa") + M("(a)\{0\}b", "b"))
    cs.push("backtracking-needed", M("a*ab", "aaab") + M("(a*)(ab)", "aaab") + M(".*foo", "xfooyfoo") + M(".*?foo", "xfooyfoo") + M("(.*)(\\d+)", "abc123") + M("(.*?)(\\d+)", "abc123") + M("(.*)(\\d+)$", "ab12") + M("^(a+)+$", "aaaa") + M("(?:a|ab)(?:c|bcd)", "abcd") + M("^(.*),(.*)$", "a,b,c") + M("^(.*?),(.*)$", "a,b,c"))
    cs.push("replace-templates", R("(a)(b)(c)", "abc", "$3$2$1") + R("b", "abcb", "[$0$0]") + R("(?<first>\\w)(?<rest>\\w*)", "hello world", "$\{rest\}$\{first\}") + R("x", "axb", "$") + R("x", "axb", "$$$$") + R("x", "axb", "$ ") + R("(x)", "axb", "$\{1\}") + R("x", "axb", "$\{") + R("a", "banana", "$0$0") + R("", "ab", "-") + R("\\s", "a b\\tc", "\\\\s"))
    let batch = ["a", "a", "a", "b", "^a$", "a", "^a$", "ab", "a|b", "c", "\\d\{3\}", "12", "\\d\{3\}", "123", "[aeiou]\{2\}", "xaex", "(ab)+$", "abab", "(ab)+$", "aba", "\\bcat\\b", "a cat!", "\\bcat\\b", "concat", "^\\s*$", "   ", "^\\s*$", " x ", ".", "", "", ""]
    var tests = ""
    var k = 0
    while k < batch.length():
        tests += T(batch[k].clone(), batch[k + 1].clone())
        k += 2
    cs.push("test-batch", tests)
    let examples = [
        cs.make("basic", M("(\\d+)-(\\d+)", "tel 12-345") + A("a*", "baac") + R("(\\w+)@(\\w+)", "me@host you@there", "$2:$1") + S("\\s*,\\s*", "a , b,c")),
        cs.make("named-and-lazy", M("(?<year>\\d\{4\})-(?<mon>\\d\\d)", "on 2024-05-17") + M("<.*?>", "<a><b>") + T("(a", "a") + M("(?i)HeLLo", "say hello")),
        cs.make("lookahead-backref", M("(\\w+) \\1", "the the cat") + M("a(?=b)", "acab") + F("a|ab", "ab") + line("bogus", "x", "y"))
    ]
    write_cases("c54-regex-engine", examples, examples.concat(cs.list))

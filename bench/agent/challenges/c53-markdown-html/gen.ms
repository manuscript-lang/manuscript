# Generator for c53-markdown-html. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c53
import Cases, build_oracle, write_cases from "../../lib/gen.ms"


export fn gen_c53() Unit:
    var cs = Cases(build_oracle("c53-markdown-html"))
    cs.push("headings", "# H1\n## H2 with *emph*\n### H3\n#### H4\n##### H5\n###### H6\n####### not a heading\n#nospace\n  ## indented two\n   ### indented three\n    #### four spaces is code\n# closing ###\n## closing # not closed#\n### ###\n#\n# \n## foo ## bar ##\n# `code` and [link](u)\n")
    cs.push("paragraphs", "First paragraph\nspans two lines.\n\nSecond paragraph.\n\n\n\nThird after many blanks.\n   indented continuation\n     more indented\n\nTrailing spaces  \nhard break above.\n\nBackslash break\\\nabove.\n\nLast line backslash\\\n")
    cs.push("hard-breaks", "a  \nb   \nc\\\nd\n\n*em  \nstill*\n\ntext  \n\nnext\n\nx\\\\\ny\n")
    cs.push("emphasis-basic", "*em* _em_ **strong** __strong__ ***both*** ___both___\n\n*a **b** c*\n\n**a *b* c**\n\n*a* *b* **c** **d**\n\n_a_b_ and a_b_c and *a*b and foo*bar*baz\n")
    cs.push("emphasis-flanking", "a * b * c\n\n2 * 3 * 4\n\n** not strong **\n\n_ not em _\n\nfoo_bar_baz\n\n*foo*bar\n\n(*foo*) and (**foo**) and \"*foo*\"\n\n*(foo)* and **(foo)**\n\nsnake_case_name and _lead and trail_\n\n*foo\n\n**foo\n\nfoo*\n\n***\n\n___ x ___\n")
    cs.push("emphasis-nesting", "***foo** bar*\n\n***foo* bar**\n\n*foo **bar***\n\n**foo *bar***\n\n*foo**bar**baz*\n\n**foo*bar*baz**\n\n*one **two *three* two** one*\n\n_foo __bar__ baz_\n\n**a** **b** and *c* _d_ **e**\n\n****a****\n\n*****a*****\n\n**a*b**c*\n\n*a**b*c**\n")
    cs.push("emphasis-mismatch", "*foo_\n\n_foo*\n\n*foo**\n\n**foo*\n\n_foo__\n\n*a _b* c_\n\n_a *b_ c*\n")
    cs.push("code-spans", "`code` and ``double `tick` code`` and ` padded `\n\n`` `a` ``\n\n`  two  `\n\n` `\n\n`unclosed\n\n``unclosed `x`\n\n`a\nb`\n\n`*not em*` `<b>&amp;`\n\n`foo`bar`\n\n```inline``` code\n\n\\`not code\\`\n")
    cs.push("escapes", "\\*not em\\* \\_x\\_ \\# \\[a\\](b) \\\\ \\a \\<b\\> \\& \\` \\| \\~ \\!\n\n\\## not heading\n\n1\\. not list\n\n\\- not list\n\n\\> not quote\n")
    cs.push("html-escaping", "a < b > c & d \" e ' f\n\n<div>raw html is text</div>\n\n&amp; &lt; &copy; stays escaped\n\n`<code & \"stuff\">`\n\n[<x>](a&b \"t<\"\">\")\n")
    cs.push("links", "[text](http://example.com)\n\n[text](http://example.com \"Title\")\n\n[text](</my url> 'x')\n\n[a](<my url>)\n\n[empty]()\n\n[](x)\n\n[*em* and `code`](u)\n\n[nested [brackets]](u)\n\n[a](b(c)d)\n\n[a](b\\)c)\n\n[a](b \"t\\\"q\")\n\n[a]( spaced )\n\n[a]( spaced \"t\" )\n\n[a](b c)\n\n[a] (b)\n\n[a](b\n\n[a]\n\n]\n\n[[a](b)](c)\n\n[a](b)[c](d)\n\ntext [a](b) text [c](d \"e\") end\n")
    cs.push("links-invalid-title", "[a](b \"t)\n\n[a](b \"t\" x)\n\n[a](b'c')\n\n[a](<b)\n\n[a](<b>c)\n")
    cs.push("images", "![alt](src.png)\n\n![alt *em* `code`](s \"T\")\n\n![](s)\n\n![a [b](c) d](e)\n\n![nested ![inner](i) x](o)\n\nbefore ![x](y) after\n\n![unclosed](\n\n!not image [a](b)\n\n! [a](b)\n")
    cs.push("links-no-nesting", "[a [b](c) d](e)\n\n[a ![img](i) b](u)\n\n*[a](b)* and [*a*](b) and **[a](b)**\n\n[a*b](c)*d*\n\n*a [b*](c)\n")
    cs.push("blockquotes", "> quote\n\n> multi\n> line\n\n>no space\n\n> # head\n> para\n>\n> second\n\n> a\n>\n>> nested\n>>\n>> deeper\n> back\n\n> one\n\n> two\n\ntext\n> interrupts\nafter lazy?\n")
    cs.push("blockquote-contents", "> - a\n> - b\n>\n> ```\n> code\n> ```\n>\n>     indented\n\n> 1. x\n> 2. y\n\n> > > triple\n\n>\n\n>\n> text\n")
    cs.push("lists-basic", "- a\n- b\n- c\n\n* x\n* y\n\n+ p\n+ q\n\n1. one\n2. two\n3. three\n\n1) one\n2) two\n")
    cs.push("lists-start", "3. three\n4. four\n\n0. zero\n1. one\n\n10. ten\n11. eleven\n\n1. a\n1. b\n1. c\n\n7) seven\n")
    cs.push("lists-markers-switch", "- a\n- b\n* c\n* d\n+ e\n\n1. a\n2. b\n1) c\n2) d\n\n- a\n1. b\n- c\n")
    cs.push("lists-nested", "- a\n  - b\n    - c\n  - d\n- e\n\n1. one\n   - sub a\n   - sub b\n2. two\n   1. deep\n   2. deeper\n\n- a\n - b\n  - c\n   - d\n")
    cs.push("lists-loose", "- a\n\n- b\n\n- c\n\n---\n\n- a\n- b\n\n- c\n\n---\n\n- a\n\n  more\n- b\n\n---\n\n- a\n  - b\n\n  c\n- d\n\n---\n\n1. a\n\n2. b\n")
    cs.push("lists-tight-mixed", "- a\n  - b\n\n- c\n\n---\n\n- a\n  > quote\n- b\n\n---\n\n- a\n  ```\n  code\n  ```\n- b\n\n---\n\n- # heading\n- ***\n- > q\n")
    cs.push("lists-blocks", "- para one\n\n  para two\n\n      indented code\n\n  ```js\n  let x;\n  ```\n\n  > quote\n- next\n\n1. item\n\n   ```\n   code in ordered\n   ```\n\n2. next\n")
    cs.push("lists-empty-items", "-\n- b\n-\n\n1.\n2. x\n\n- \n  text on next line\n\n*\n")
    cs.push("lists-interrupt", "para\n- list interrupts\n- more\n\npara\n1. ordered one interrupts\n\npara\n2. two does not interrupt\n\npara\n-\ntext\n\npara\n* \n\npara\n+ a\n")
    cs.push("lists-end", "- a\n- b\ntext not lazy\n\n- c\n  continued\nnot\n\n- x\n\n\ntext after two blanks\n\n- one\n\n\n- two\n")
    cs.push("lists-indent-widths", "-   wide marker\n    continuation\n\n-     code after wide\n\n10. ten\n    cont\n\n1.  four-space\n    - nested\n\n- a\n\n      code\n")
    cs.push("thematic-breaks", "---\n***\n___\n- - -\n* * *\n_ _ _\n----------\n   ---\n    ---\n--\n-*-\n--- a\n+++\ntext\n---\ntext\n***\n")
    cs.push("fenced-code", "```\nplain\n```\n\n```go\nfunc main() \{\}\n```\n\n~~~python extra words\nx = 1 < 2\n~~~\n\n````\n```\ninside\n```\n````\n\n```\nunclosed\n\nstill code\n")
    cs.push("fenced-edge", "```\n\n  leading blank and indented\n\n```\n\n  ```\n  indented fence\n    keeps extra\n  ```\n\n```a`b\nnot a fence\n\n~~~\ntilde ``` inside\n~~~\n\n```\ntext\n~~~\n```\n\n``` \n```\n\n```x\n```\nafter\n\n```\n<&\">\n```\n")
    cs.push("indented-code", "    code line 1\n    code line 2\n\n    after blank\n\n\n    after two blanks\n      extra indent\n\npara\n    not code (continuation)\n\n    code\npara right after\n\n        eight\n")
    cs.push("code-and-others", "# Title\n    code\n> quote\n    still quote text?\n- item\n\n      code in item\n")
    cs.push("tables-basic", "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\n| H1 | H2 | H3 | H4 |\n|:---|:---:|---:|----|\n| l | c | r | n |\n")
    cs.push("tables-forms", "a | b\n--|--\n1 | 2\n\n| x |\n|---|\n| y |\n\n| head only | b |\n|---|---|\n\n| a | b |\n|---|---|\n| only one |\n| three | cells | extra |\n\n|a|b|\n|-|-|\n|*em*|`code`|\n")
    cs.push("tables-escapes", "| a | b |\n|---|---|\n| x \\| y | `z` |\n| \\\\ | [l](u) |\n")
    cs.push("tables-not", "| a | b |\n|---|\n| 1 | 2 |\n\n| a | b |\n| 1 | 2 |\n\nno pipe\n---\n\n| a |\n| b |\n\n| a | b |\n| - | x |\n")
    cs.push("tables-ending", "| a | b |\n|---|---|\n| 1 | 2 |\ntext after is a row\n# heading ends\n| a | b |\n|---|---|\n| 1 | 2 |\n> quote ends\n\n| a | b |\n|---|---|\n| 1 | 2 |\n- list is a row\n\n| a | b |\n|---|---|\n| 1 | 2 |\n---\ntext\n")
    cs.push("tables-in-containers", "> | a | b |\n> |---|---|\n> | 1 | 2 |\n\n- | a | b |\n  |---|---|\n  | 1 | 2 |\n\npara\n| a | b |\n|---|---|\n")
    cs.push("interrupts", "para\n# heading\npara\n```\ncode\n```\npara\n> quote\npara\n---\npara\n    indented continues\n")
    cs.push("mixed-doc", "# Project\n\nA *short* intro with `code`, a [link](http://x.y \"t\"), and **bold** text.\n\n## Install\n\n1. Download\n2. Run:\n\n   ```sh\n   make install\n   ```\n3. Done\n\n## Table\n\n| Name | Qty | Price |\n|:-----|----:|:-----:|\n| Nut  |  10 | 0.5   |\n| Bolt |   3 | 1.25  |\n\n> **Note**\n> Be careful.\n\n---\n\n- [x] not a task list\n- plain\n")
    cs.push("empty-and-blank", "")
    cs.push("only-blank", "\n\n   \n\n")
    cs.push("no-trailing-newline", "# Title\n\npara no newline")
    cs.push("crlf-ignored", "line one\n\nline two\n")
    cs.push("unicode-free-long-line", "word ".repeat(80).get("") + "\n\n" + "*a* ".repeat(40).get("") + "\n")
    var inline = ""
    for i in 0..30:
        inline += "*a{i}* **b{i}** `c{i}` [d{i}](u{i}) ![e{i}](v{i}) \\*f_{i}_g\n"
    cs.push("stress-inline", inline)
    var nested = ""
    for i in 0..40:
        nested += "  ".repeat(i % 4).get("") + "- item {i}\n"
    cs.push("stress-nested-lists", nested)
    cs.push("stress-quotes", ">".repeat(20).get("") + " deep\n" + "> ".repeat(5).get("") + "x\n")
    let examples = [
        cs.make("basic", "# Title\n\nSome *emphasis*, **strong text** and `code`.\n\n- one\n- two\n  - nested\n\n> a quote\n"),
        cs.make("table-and-code", "| Name | Qty |\n|:-----|----:|\n| Nut  |  10 |\n\n```py\nprint(1 < 2)\n```\n\nSee [docs](http://x.y \"Docs\").\n"),
        cs.make("loose-list", "1. first\n\n2. second\n   continues\n\n3. third\n")
    ]
    write_cases("c53-markdown-html", examples, examples.concat(cs.list))

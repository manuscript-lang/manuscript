# Generator for c58-mini-vcs. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c58
import Cases, build_oracle, write_cases, solve_with from "../../lib/gen.ms"
import compile from "@std/string.ms"

# The `{cN}` placeholders stand for the short id of the N-th commit; a dry run with a dummy id finds them.
fn resolve_hashes(oracle: String, script: String) String:
    if not script.contains("\{c"):
        return script.clone()

    let marker = compile("\\\{c[0-9]+\\\}").to_optional()
    let probe = marker.get().replace_all(script, "0000000").get("")
    let out = solve_with(oracle, probe)
    let found = compile("(?m)^\\[[^\\]]* ([0-9a-f]\{7\})\\] ").to_optional()
    var shorts = List[String]()
    for groups in found.get().captures_all(out, 1000).get([]):
        shorts.append(groups[1].clone())

    var resolved = script.clone()
    var n = 1

    while n <= shorts.length():
        resolved = resolved.replace("\{c{n}\}", shorts[n - 1].clone())
        n += 1

    return resolved

fn add(var cs: Cases, name: String, script: String) Unit:
    cs.push(name, resolve_hashes(cs.oracle, strip_nl(script)))

fn strip_nl(text: String) String:
    var chars = text.chars()
    var start = 0
    var end = chars.length()
    while start < end and chars[start] == "\n":
        start += 1
    while end > start and chars[end - 1] == "\n":
        end -= 1
    return chars.slice(start, end).get([]).join("") + "\n"

fn W(name: String, lines: List[String] = []) String:
    if lines.is_empty():
        return "write {name}\n.\n"

    return "write {name}\n" + lines.join("\n") + "\n.\n"

export fn gen_c58() Unit:
    var cs = Cases(build_oracle("c58-mini-vcs"))
    let BASE = (
        W("a.txt", ["one", "two", "three", "four", "five"])
        + "add a.txt\ncommit initial\n"
    )
    add(
        var cs,
        "files-basic",
        W("a.txt", ["hello", "world"])
        + "cat a.txt\nappend a.txt\nmore\n.\ncat a.txt\nls\nmv a.txt b.txt\nls\ncat a.txt\nrm b.txt\nrm b.txt\nls\ncat\nmv x\nmv q r\nrm\nwrite\nappend new.txt\nx\ny\n.\ncat new.txt\nwrite empty.txt\n.\ncat empty.txt\nls"
    )
    add(
        var cs, "status-fresh",
        "status\nls\nlog\nbranch\nbranch x\ntag\ntag t\nshow HEAD\nmerge x\ncheckout -b y\ncommit nothing\nadd .\nadd nothing"
    )
    add(
        var cs,
        "first-commit",
        W("a", ["1"])
        + W("b", ["2"])
        + "status\nadd a\nstatus\ncommit first\nstatus\nadd b\ncommit second commit message\nstatus\nlog\nlog -n 1\nlog -n 0\nlog -n x\nlog 5"
    )
    add(
        var cs,
        "commit-errors",
        W("a", ["1"])
        + "commit\ncommit  \ncommit no add\nadd a\ncommit ok\ncommit again\nadd a\ncommit again"
    )
    add(
        var cs,
        "status-sections",
        BASE
        + W("b.txt", ["bee"])
        + W("a.txt", ["one", "changed"])
        + "status\nadd a.txt\nstatus\nwrite a.txt\nthird edit\n.\nstatus\nrm a.txt\nstatus\nadd a.txt\nstatus\nadd .\nstatus\ncommit del\nstatus\nls"
    )
    add(
        var cs,
        "add-dot-deletion",
        W("a", ["A"])
        + W("b", ["B"])
        + W("c", ["C"])
        + "add .\ncommit abc\nrm a\nwrite c\nC2\n.\nwrite d\nD\n.\nstatus\nadd .\nstatus\ncommit mixed\nshow HEAD\nls"
    )
    add(
        var cs,
        "add-paths-partial",
        W("a", ["A"]) + W(
            "b", ["B"]
        ) + "add a b nothere c\nstatus\nadd b\nstatus"
    )
    add(
        var cs,
        "overwrite-and-recommit",
        BASE
        + "write a.txt\nsame\n.\nwrite a.txt\none\ntwo\nthree\nfour\nfive\n.\nstatus\nadd a.txt\ncommit noop\nstatus"
    )
    add(
        var cs,
        "identical-trees-different-msgs",
        W("a", ["x"])
        + "add a\ncommit m1\nbranch b1\nbranch b2\nwrite a\ny\n.\nadd a\ncommit same msg\ncheckout b1\nwrite a\ny\n.\nadd a\ncommit same msg\nlog\ncheckout b2\nwrite a\ny\n.\nadd a\ncommit same msg\nlog\nbranch"
    )
    add(
        var cs,
        "show-and-refs",
        W("a", ["1", "2"])
        + "add a\ncommit c1\nwrite a\n1\n2\n3\n.\nwrite b\nbb\n.\nadd .\ncommit c2\nwrite a\nz\n.\nadd a\ncommit c3\nshow HEAD\nshow HEAD~1\nshow HEAD~2\nshow HEAD~3\nshow HEAD~x\nshow nope\nshow \{c1\}\nshow zz\nshow abc\ntag v1 HEAD~1\ntag v2\ntag v1\ntag bad name\ntag\nshow v1\nshow v1~1\nshow main~2\nshow main\nshow\nshow a b"
    )
    add(
        var cs,
        "ref-prefix-ambiguity",
        W("a", ["1"])
        + "add a\ncommit one\nwrite a\n2\n.\nadd a\ncommit two\nshow 0000\nshow ffff\nshow \{c2\}\nlog -n 1"
    )
    add(
        var cs,
        "diff-working",
        BASE
        + "write a.txt\none\nTWO\nthree\nsix\nfive\nseven\n.\nwrite new.txt\nfresh\n.\ndiff\nadd a.txt\ndiff\nadd .\ndiff\ndiff HEAD\ncommit next\ndiff\ndiff HEAD~1\nrm a.txt\ndiff HEAD"
    )
    add(
        var cs,
        "diff-refs",
        BASE
        + W("a.txt", ["one", "three", "five", "six"])
        + W("b.txt", ["bee"])
        + "add .\ncommit second\nrm b.txt\nadd .\ncommit third\ndiff HEAD~2 HEAD~1\ndiff HEAD~1 HEAD\ndiff HEAD~2 HEAD\ndiff HEAD HEAD\ndiff HEAD~5\ndiff a b c\ndiff HEAD~1 nope"
    )
    add(
        var cs,
        "diff-lcs-ties",
        W("f", ["a", "b", "a", "b", "a"])
        + "add f\ncommit base\nwrite f\nb\na\nb\na\nb\n.\ndiff\nwrite f\na\na\na\n.\ndiff\nwrite f\nx\na\nb\na\nb\na\nx\n.\ndiff\nwrite f\n.\ndiff\nwrite f\nb\nb\n.\ndiff"
    )
    add(
        var cs,
        "diff-duplicates-moved",
        W("f", ["1", "2", "3", "4", "5", "6"])
        + "add f\ncommit base\nwrite f\n4\n5\n6\n1\n2\n3\n.\ndiff\nwrite f\n1\n2\n3\n3\n4\n5\n6\n6\n.\ndiff"
    )
    add(
        var cs,
        "branch-basic",
        BASE
        + "branch\nbranch dev\nbranch feature/x\nbranch dev\nbranch bad..name!\nbranch\nbranch -d nope\nbranch -d main\nbranch -d dev\nbranch\nbranch -d feature/x\nbranch -d\nbranch a b c"
    )
    add(
        var cs,
        "branch-delete-unmerged",
        BASE
        + "checkout -b topic\nwrite t.txt\nt\n.\nadd t.txt\ncommit topic work\ncheckout main\nbranch -d topic\nmerge topic\nbranch -d topic\nbranch"
    )
    add(
        var cs,
        "checkout-basic",
        BASE
        + "checkout -b dev\nwrite a.txt\ndev\n.\nadd a.txt\ncommit dev change\ncat a.txt\ncheckout main\ncat a.txt\ncheckout dev\ncat a.txt\ncheckout dev\ncheckout nothere\ncheckout -b dev\ncheckout -b\nstatus\nlog"
    )
    add(
        var cs,
        "checkout-dirty",
        BASE
        + "checkout -b dev\ncheckout main\nwrite a.txt\nmod\n.\ncheckout dev\nadd a.txt\ncheckout dev\ncommit mod\ncheckout dev\nstatus\nwrite z.txt\nuntracked\n.\ncheckout main\nls"
    )
    add(
        var cs,
        "checkout-deleted-tracked",
        BASE
        + "checkout -b dev\ncheckout main\nrm a.txt\ncheckout dev\nstatus\nadd a.txt\nstatus\ncheckout dev"
    )
    add(
        var cs,
        "checkout-untracked-collision",
        BASE
        + "checkout -b dev\nwrite n.txt\nfrom dev\n.\nadd n.txt\ncommit add n\ncheckout main\nwrite n.txt\nlocal untracked\n.\ncheckout dev\ncat n.txt\nrm n.txt\ncheckout dev\ncat n.txt\nls"
    )
    add(
        var cs,
        "checkout-removes-files",
        BASE
        + "checkout -b dev\nwrite extra.txt\nx\n.\nwrite a.txt\nA\n.\nadd .\ncommit dev\ncheckout main\nls\ncat a.txt\nwrite keep.txt\nuntracked stays\n.\ncheckout dev\nls\ncheckout main\nls"
    )
    add(
        var cs,
        "detached-head",
        W("a", ["1"])
        + "add a\ncommit c1\nwrite a\n2\n.\nadd a\ncommit c2\nwrite a\n3\n.\nadd a\ncommit c3\ncheckout HEAD~2\nstatus\ncat a\nbranch\nwrite a\nd\n.\nadd a\ncommit on detached\nlog\nbranch saved\nbranch\ncheckout main\nlog\ncheckout saved\nlog -n 2\ncheckout \{c1\}\ncheckout main"
    )
    add(
        var cs,
        "detached-tag",
        W("a", ["1"])
        + "add a\ncommit c1\ntag release\nwrite a\n2\n.\nadd a\ncommit c2\ncheckout release\ncat a\nstatus\ncheckout main\ncat a\ncheckout release~1\ntag late"
    )
    add(
        var cs,
        "merge-fast-forward",
        BASE
        + "checkout -b feat\nwrite b.txt\nb\n.\nadd b.txt\ncommit b\nwrite c.txt\nc\n.\nadd c.txt\ncommit c\ncheckout main\nmerge feat\nlog\nls\nstatus\nmerge feat\nmerge main"
    )
    add(
        var cs,
        "merge-up-to-date",
        BASE
        + "checkout -b feat\ncheckout main\nwrite m.txt\nm\n.\nadd m.txt\ncommit m\nmerge feat\nlog -n 1"
    )
    add(
        var cs,
        "merge-clean-different-files",
        BASE
        + "checkout -b feat\nwrite f.txt\nfeat file\n.\nadd f.txt\ncommit feat file\ncheckout main\nwrite m.txt\nmain file\n.\nadd m.txt\ncommit main file\nmerge feat\nls\nlog\nstatus\nshow HEAD"
    )
    add(
        var cs,
        "merge-clean-same-file-different-regions",
        W("a.txt", ["1", "2", "3", "4", "5", "6", "7", "8"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\n1\n2\n3\n4\n5\n6\n7\neight\n.\nadd a.txt\ncommit tail\ncheckout main\nwrite a.txt\none\n2\n3\n4\n5\n6\n7\n8\n.\nadd a.txt\ncommit head\nmerge feat\ncat a.txt\nstatus"
    )
    add(
        var cs,
        "merge-both-same-change",
        BASE
        + "checkout -b feat\nwrite a.txt\none\nTWO\nthree\nfour\nfive\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\none\nTWO\nthree\nfour\nfive\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt\nlog -n 1"
    )
    add(
        var cs,
        "merge-conflict-content",
        BASE
        + "checkout -b feat\nwrite a.txt\none\nfeat two\nthree\nfour\nfive\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\none\nmain two\nthree\nfour\nfive\n.\nadd a.txt\ncommit main\nmerge feat\nstatus\ncat a.txt\nlog -n 1\ncommit try\nadd a.txt\nstatus"
    )
    add(
        var cs,
        "merge-conflict-resolve",
        BASE
        + "checkout -b feat\nwrite a.txt\nfeat\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\nmain\n.\nadd a.txt\ncommit main\nmerge feat\nwrite a.txt\nresolved\n.\nstatus\nadd a.txt\nstatus\ncommit Resolved merge\nstatus\nlog\ncheckout feat\ncat a.txt\ncheckout main\ncat a.txt\nshow HEAD"
    )
    add(
        var cs,
        "merge-in-progress-errors",
        BASE
        + "checkout -b feat\nwrite a.txt\nf\n.\nadd a.txt\ncommit f\ncheckout main\nwrite a.txt\nm\n.\nadd a.txt\ncommit m\nmerge feat\nmerge feat\ncheckout feat\ncommit\ncommit stuck\nbranch -d feat\nmerge --abort\nmerge --abort\nstatus\ncat a.txt"
    )
    add(
        var cs,
        "merge-abort",
        BASE
        + "checkout -b feat\nwrite a.txt\nf\n.\nwrite new.txt\nnew from feat\n.\nadd .\ncommit f\ncheckout main\nwrite a.txt\nm\n.\nadd a.txt\ncommit m\nmerge feat\nls\nstatus\nwrite scratch.txt\ns\n.\nmerge --abort\nls\ncat a.txt\nstatus"
    )
    add(
        var cs,
        "merge-multiple-conflicts-sorted",
        W("z.txt", ["z"])
        + W("a.txt", ["a"])
        + W("m.txt", ["m"])
        + "add .\ncommit base\ncheckout -b feat\nwrite z.txt\nz-feat\n.\nwrite a.txt\na-feat\n.\nwrite m.txt\nm-feat\n.\nwrite q.txt\nq1\n.\nadd .\ncommit feat\ncheckout main\nwrite z.txt\nz-main\n.\nwrite a.txt\na-main\n.\nwrite q.txt\nq2\n.\nadd .\ncommit main\nmerge feat\nstatus\ncat q.txt\ncat m.txt\ncommit early\nadd a.txt\ncommit early\nadd z.txt q.txt\ncommit done"
    )
    add(
        var cs,
        "merge-modify-delete",
        BASE
        + W("b.txt", ["bee"])
        + "add b.txt\ncommit b\ncheckout -b feat\nrm b.txt\nadd b.txt\ncommit delete b\ncheckout main\nwrite b.txt\nbee changed\n.\nadd b.txt\ncommit modify b\nmerge feat\nstatus\nls\ncat b.txt\nadd b.txt\ncommit keep modified\nls"
    )
    add(
        var cs,
        "merge-delete-modify",
        BASE
        + W("b.txt", ["bee"])
        + "add b.txt\ncommit b\ncheckout -b feat\nwrite b.txt\nbee changed\n.\nadd b.txt\ncommit modify b\ncheckout main\nrm b.txt\nadd b.txt\ncommit delete b\nmerge feat\nstatus\nls\ncat b.txt\nrm b.txt\nadd b.txt\nstatus\ncommit accept delete\nls"
    )
    add(
        var cs,
        "merge-one-side-deletes-unchanged",
        BASE
        + W("b.txt", ["bee"])
        + "add b.txt\ncommit b\ncheckout -b feat\nrm b.txt\nadd b.txt\ncommit delete b\ncheckout main\nwrite c.txt\nc\n.\nadd c.txt\ncommit add c\nmerge feat\nls\nstatus"
    )
    add(
        var cs,
        "merge-add-add",
        BASE
        + "checkout -b feat\nwrite n.txt\nfeat n\n.\nadd n.txt\ncommit feat n\ncheckout main\nwrite n.txt\nmain n\n.\nadd n.txt\ncommit main n\nmerge feat\ncat n.txt\nstatus"
    )
    add(
        var cs,
        "merge-add-add-identical",
        BASE
        + "checkout -b feat\nwrite n.txt\nsame\n.\nadd n.txt\ncommit feat n\ncheckout main\nwrite n.txt\nsame\n.\nadd n.txt\ncommit main n\nmerge feat\ncat n.txt\nstatus"
    )
    add(
        var cs,
        "merge-dirty-tree",
        BASE
        + "checkout -b feat\nwrite f.txt\nf\n.\nadd f.txt\ncommit f\ncheckout main\nwrite m.txt\nm\n.\nadd m.txt\ncommit m\nwrite a.txt\ndirty\n.\nmerge feat\nadd a.txt\nmerge feat\ncommit stage\nmerge feat\nls"
    )
    add(
        var cs,
        "merge-untracked-collision",
        BASE
        + "checkout -b feat\nwrite f.txt\nf\n.\nadd f.txt\ncommit f\ncheckout main\nwrite m.txt\nm\n.\nadd m.txt\ncommit m\nwrite f.txt\nuntracked\n.\nmerge feat\nrm f.txt\nmerge feat\nls"
    )
    add(
        var cs, "merge-unknown-branch",
        BASE + "merge nope\nmerge\nmerge a b\ncheckout -b x\nmerge x"
    )
    add(
        var cs,
        "merge-line-level-adjacent",
        W("a.txt", ["a", "b", "c", "d", "e"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\na\nB\nc\nd\ne\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\na\nb\nC\nd\ne\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt"
    )
    add(
        var cs,
        "merge-line-level-separated",
        W("a.txt", ["a", "b", "c", "d", "e"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\na\nB\nc\nd\ne\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\na\nb\nc\nD\ne\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt"
    )
    add(
        var cs,
        "merge-insert-delete-mix",
        W("a.txt", ["1", "2", "3", "4", "5", "6"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\n1\n3\n4\n5\n5.5\n6\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\n0\n1\n2\n3\n4\n6\n7\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt\nstatus"
    )
    add(
        var cs,
        "merge-conflict-multi-hunk",
        W("a.txt", ["1", "2", "3", "4", "5", "6", "7"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\nF1\n2\n3\nF4\n5\n6\nF7\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\nM1\n2\n3\n4\n5\n6\nM7\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt"
    )
    add(
        var cs,
        "merge-conflict-delete-vs-change-lines",
        W("a.txt", ["x", "y", "z"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\nx\nz\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\nx\nY\nz\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt"
    )
    add(
        var cs,
        "merge-empty-file-results",
        W("a.txt", ["x"])
        + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\n.\nadd a.txt\ncommit empty\ncheckout main\nwrite b.txt\nb\n.\nadd b.txt\ncommit b\nmerge feat\nls\ncat a.txt\nshow HEAD"
    )
    add(
        var cs,
        "merge-criss-cross",
        W("a", ["base"])
        + "add a\ncommit root\ncheckout -b x\nwrite xf\nx1\n.\nadd xf\ncommit x1\ncheckout main\nbranch y\nwrite mf\nm1\n.\nadd mf\ncommit m1\nmerge x\ncheckout y\nwrite yf\ny1\n.\nadd yf\ncommit y1\nmerge x\ncheckout x\nwrite xf\nx2\n.\nadd xf\ncommit x2\nmerge main\nls\nlog"
    )
    add(
        var cs,
        "merge-base-nearest",
        W("a.txt", ["1", "2", "3"])
        + "add a.txt\ncommit c1\ncheckout -b feat\nwrite a.txt\n1\n2\n3\n4\n.\nadd a.txt\ncommit c2 feat\ncheckout main\nmerge feat\nwrite a.txt\n0\n1\n2\n3\n4\n.\nadd a.txt\ncommit c3 main\ncheckout feat\nwrite a.txt\n1\n2\n3\n4\n5\n.\nadd a.txt\ncommit c4 feat\ncheckout main\nmerge feat\ncat a.txt\nlog"
    )
    add(
        var cs,
        "reset-hard",
        BASE
        + W("b.txt", ["bee"])
        + "add b.txt\ncommit b\nwrite a.txt\nx\n.\nwrite junk\nj\n.\nadd a.txt\nreset --hard\nstatus\ncat a.txt\nls\nreset --hard HEAD~1\nls\nlog\nstatus\nreset --hard nope\nreset\nreset --soft\nreset --hard a b"
    )
    add(
        var cs,
        "reset-hard-conflict",
        BASE
        + "checkout -b feat\nwrite a.txt\nf\n.\nadd a.txt\ncommit f\ncheckout main\nwrite a.txt\nm\n.\nadd a.txt\ncommit m\nmerge feat\nreset --hard\nstatus\ncat a.txt\nmerge --abort"
    )
    add(
        var cs,
        "reset-moves-branch",
        W("a", ["1"])
        + "add a\ncommit c1\nwrite a\n2\n.\nadd a\ncommit c2\nwrite a\n3\n.\nadd a\ncommit c3\nbranch keep\nreset --hard HEAD~2\nlog\nbranch\ncat a\ncheckout keep\ncat a\nlog -n 1"
    )
    add(
        var cs,
        "tags-and-refs-in-diff",
        W("a", ["1"])
        + "add a\ncommit c1\ntag v1\nwrite a\n2\n.\nadd a\ncommit c2\ntag v2\ndiff v1 v2\ndiff v1\ndiff v2 v1\ntag\nbranch v1\ncheckout v1\nbranch"
    )
    add(
        var cs, "long-workflow",
        "\nwrite README\n# project\n.\nwrite src/main.c\nint main() \{ return 0; \}\n.\nadd .\ncommit initial import\ncheckout -b feature/login\nwrite src/login.c\nvoid login() \{\}\n.\nwrite README\n# project\nlogin support\n.\nadd .\ncommit add login\ncheckout main\nwrite src/main.c\nint main() \{ return 1; \}\n.\nadd src/main.c\ncommit fix exit code\ncheckout -b feature/docs\nwrite docs/guide.md\nguide\n.\nadd docs/guide.md\ncommit docs\ncheckout main\nmerge feature/login\nmerge feature/docs\nlog\nls\ntag v1.0\ncheckout feature/login\nwrite src/login.c\nvoid login() \{ auth(); \}\n.\nadd .\ncommit auth\ncheckout main\nmerge feature/login\ndiff v1.0 HEAD\nbranch -d feature/login\nbranch -d feature/docs\nbranch\nstatus\n"
    )
    add(
        var cs,
        "conflict-then-continue-work",
        BASE
        + "checkout -b feat\nwrite a.txt\nF\n.\nadd a.txt\ncommit F\ncheckout main\nwrite a.txt\nM\n.\nadd a.txt\ncommit M\nmerge feat\nwrite a.txt\nboth\n.\nadd a.txt\ncommit merged\nwrite a.txt\nafter\n.\nadd a.txt\ncommit more\nlog\nmerge feat\nbranch -d feat\nbranch"
    )
    add(
        var cs, "script-edge-cases",
        "# comment line\n\n   \nfrobnicate\nwrite a\nx\n.\nadd a\ncommit c\nstatus extra\nls extra\ncat a b\nwrite b\nunterminated\nstill content\n"
    )

    # TODO(port) write_cases(examples, hidden)
    let examples = [
        cs.make(
            "ex-linear",
            W("a.txt", ["hello"])
            + "add a.txt\ncommit first\nwrite a.txt\nhello\nworld\n.\ndiff\nadd a.txt\ncommit second\nlog\nstatus\n"
        ),
        cs.make(
            "ex-merge",
            W("a.txt", ["1", "2", "3"])
            + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\n1\n2\n3\n4\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\n0\n1\n2\n3\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt\nlog\n"
        ),
        cs.make(
            "ex-conflict",
            W("a.txt", ["x"])
            + "add a.txt\ncommit base\ncheckout -b feat\nwrite a.txt\nfeat\n.\nadd a.txt\ncommit feat\ncheckout main\nwrite a.txt\nmain\n.\nadd a.txt\ncommit main\nmerge feat\ncat a.txt\nstatus\ncommit too early\n"
        )
    ]
    write_cases("c58-mini-vcs", examples, cs.list)

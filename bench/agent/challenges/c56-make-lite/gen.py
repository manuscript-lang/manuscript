"""Generator for c56-make-lite. The expected outputs come from the Go oracle in oracle/*.ref (built with the local
Go toolchain); this script only supplies the inputs. Deterministic; run: python3 gen.py"""
import json, pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).parent

def build_oracle():
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="msbench-oracle-"))
    for f in sorted((root / "oracle").glob("*.ref")):
        shutil.copy(f, tmp / f.name[:-4])
    (tmp / "go.mod").write_text("module oracle\n\ngo 1.21\n")
    subprocess.run(["go", "build", "-o", "oracle", "."], cwd=tmp, check=True)
    return tmp / "oracle"

ORACLE = build_oracle()

def solve(stdin):
    r = subprocess.run([str(ORACLE)], input=stdin, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        sys.exit("oracle failed (exit %d): %s" % (r.returncode, r.stderr[:500]))
    return r.stdout

def case(name, stdin): return {"name": name, "stdin": stdin, "stdout": solve(stdin)}

def write_cases(examples, hidden):
    names = [c["name"] for c in hidden]
    assert len(set(names)) == len(names), "duplicate case names"
    for d, cs in (("examples", examples), ("hidden", hidden)):
        (root / d).mkdir(exist_ok=True)
        (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
    print(len(examples), len(hidden))

T = "\t"
def mk(makefile, files, reqs):
    mf = makefile.replace("<T>", T).strip("\n") + "\n"
    ft = "".join("%s %d\n" % (k, v) for k, v in files.items())
    return mf + "====\n" + ft + "====\n" + "\n".join(reqs) + "\n"

CASES = []
def add(name, makefile, files, reqs):
    CASES.append(case(name, mk(makefile, files, reqs)))

CPROJ = """
CC = gcc
CFLAGS := -O2 -Wall
OBJS = main.o util.o
SRCS = $(patsubst %.o,%.c,$(OBJS))

.PHONY: all clean
all: app

app: $(OBJS)
<T>$(CC) $(CFLAGS) -o $@ $^
<T>@echo built $@

%.o: %.c util.h
<T>$(CC) $(CFLAGS) -c $< -o $@

clean:
<T>-rm -f app $(OBJS)
<T>@echo cleaned
"""
CFILES = {"main.c": 10, "util.c": 12, "util.h": 5}

add("c-project-full", CPROJ, CFILES, ["build", "build", "touch util.h", "build", "build app", "files"])
add("c-project-partial", CPROJ, {"main.c": 10, "util.c": 12, "util.h": 5, "main.o": 20, "util.o": 8, "app": 30}, ["build", "files"])
add("c-project-dry-and-override", CPROJ, CFILES, ["dry", "build CC=clang CFLAGS=-g", "build", "build clean", "build", "files"])
add("c-project-deps-targets", CPROJ, CFILES, ["deps app", "deps all", "deps main.c", "deps nothing", "targets"])
add("c-project-touch-source", CPROJ, {"main.c": 10, "util.c": 12, "util.h": 5, "main.o": 20, "util.o": 20, "app": 30}, ["build", "touch main.c 40", "build", "build", "touch util.c", "build app"])

add("simple-up-to-date", "a: b\n<T>@echo a\nb:\n<T>@echo b", {"a": 5, "b": 3}, ["build"])
add("simple-newer-prereq", "a: b\n<T>@echo a\nb:\n<T>@echo b", {"a": 5, "b": 7}, ["build", "files"])
add("missing-target-rebuilds", "a: b\n<T>echo a\nb: c\n<T>echo b", {"c": 1}, ["build", "files", "build"])
add("no-rule", "a: b\n<T>echo a", {}, ["build", "build b", "build a b"])
add("no-rule-needed-by", "all: x y\n<T>echo all\nx:\n<T>echo x", {"x": 1}, ["build"])
add("source-only", "a: s\n<T>echo a", {"s": 4}, ["build", "build s", "build", "build"])
add("no-recipe-rule", "a: b c\nb:\nc:\n<T>echo c", {}, ["build", "build", "build b"])
add("default-goal-skips-dot", ".PHONY: x\n.hidden:\n<T>echo no\nreal: x\n<T>echo real\nx:\n<T>echo x", {}, ["build", "targets"])
add("no-targets", "A = 1", {}, ["build", "targets"])
add("multi-goals", "a:\n<T>echo a\nb:\n<T>echo b\nc: a\n<T>echo c", {}, ["build b a", "build c a", "build c c"])
add("multi-target-rule", "a b c: d\n<T>echo $@ from $<\nd:\n<T>echo d", {}, ["build c a", "targets", "build b"])
add("rule-merge", "a: b\na: c\n<T>echo $^\na: d\nb c d:\n<T>echo $@", {}, ["build", "deps a"])
add("recipe-override-warning", "a:\n<T>echo one\na:\n<T>echo two", {}, ["build"])
add("inline-recipe", "a: ; echo inline $@\nb: a ; echo b\n<T>echo more", {}, ["build b"])
add("order-only", "app: main.o | outdir\n<T>echo link $^ / $|\nmain.o:\n<T>echo cc\noutdir:\n<T>touch outdir", {"main.o": 5}, ["build", "touch main.o 100", "build", "build", "touch outdir 500", "build"])
add("phony-always", ".PHONY: t\nt: f\n<T>echo test\nf:\n<T>touch f", {"f": 5}, ["build", "build", "files"])
add("phony-forces-parent", ".PHONY: gen\nout: gen\n<T>echo out\ngen:\n<T>echo gen", {"out": 100}, ["build", "build out"])
add("phony-file-exists", ".PHONY: clean\nclean:\n<T>echo cleaning", {"clean": 3}, ["build clean", "build clean"])
add("circular", "a: b\n<T>echo a\nb: c\n<T>echo b\nc: a\n<T>echo c", {}, ["build", "deps a", "dry a"])
add("self-circular", "a: a\n<T>echo a", {}, ["build"])
add("diamond", "top: l r\n<T>echo top\nl: base\n<T>echo l\nr: base\n<T>echo r\nbase:\n<T>echo base", {}, ["build", "files", "build"])
add("failure-stops", "all: a b c\n<T>echo all\na:\n<T>echo a\nb:\n<T>false\nc:\n<T>echo c", {}, ["build", "files", "build a c"])
add("failure-ignored", "all: a b\n<T>echo all\na:\n<T>-false\n<T>echo after\nb:\n<T>-exit 3", {}, ["build", "files"])
add("exit-codes", "x:\n<T>echo start\n<T>exit 7\n<T>echo never", {}, ["build"])
add("silent-and-prefix", "x:\n<T>@echo quiet\n<T>echo loud\n<T>@-false\n<T>-@echo both\n<T> @  echo spaced", {}, ["build"])
add("touch-rm-cp", "all: copy\n<T>@echo done\ncopy: src\n<T>cp src dst\n<T>touch made\n<T>rm -f junk\nsrc:\n<T>touch src", {"junk": 1}, ["build", "files", "build", "build copy"])
add("cp-missing", "a:\n<T>cp nothere there\n<T>echo not reached", {}, ["build"])
add("echo-quotes", "a:\n<T>echo 'hello  world' \"x y\" z", {}, ["build"])

add("pattern-basic", "%.o: %.c\n<T>cc -c $< -o $@\nall: x.o y.o\n<T>@echo linked", {"x.c": 1, "y.c": 2, "y.o": 5}, ["build", "files"])
add("pattern-chain", "app: a.o\n<T>link $^\n%.o: %.s\n<T>as $< -o $@\n%.s: %.c\n<T>cc -S $< -o $@", {"a.c": 3}, ["build", "files", "build"])
add("pattern-stem", "%.txt: %.in\n<T>gen $* from $< to $@\nall: foo.txt dir/bar.txt\n<T>@echo ok\n", {"foo.in": 1, "dir/bar.in": 1}, ["build"])
add("pattern-order", "%.o: %.c\n<T>cc $<\n%.o: %.cc\n<T>c++ $<\nall: a.o b.o\n<T>@echo done", {"a.c": 1, "a.cc": 1, "b.cc": 2}, ["build"])
add("pattern-no-match", "%.o: %.c\n<T>cc $<\nall: a.o\n<T>@echo done", {"a.h": 1}, ["build", "deps a.o"])
add("pattern-plus-explicit-deps", "%.o: %.c\n<T>cc $< $^\na.o: common.h\nb.o: common.h other.h\nall: a.o b.o\n<T>@echo done", {"a.c": 1, "b.c": 1, "common.h": 1, "other.h": 1}, ["build", "deps b.o"])
add("explicit-beats-pattern", "%.o: %.c\n<T>cc $<\na.o: a.c\n<T>special $<\nall: a.o b.o\n<T>@echo done", {"a.c": 1, "b.c": 1}, ["build"])
add("auto-vars", "out: a b a c | d\n<T>echo '$@' '$<' '$^' '$?' '$|' '$$HOME'\nd:\n<T>touch d", {"out": 10, "a": 5, "b": 15, "c": 20}, ["build", "build"])
add("auto-newer-only", "out: a b c\n<T>echo newer=$?\nb:\n<T>touch b", {"out": 10, "a": 5, "b": 3, "c": 20}, ["build", "build"])

add("var-flavors", "A = 1\nB = $(A)\nC := $(A)\nA = 2\nD ?= keep\nD ?= no\nE ?= set\nF := x\nF += y\nG = x\nG += $(A)\nA = 3\nall:\n<T>echo $(A) $(B) $(C) $(D) $(E) $(F) [$(G)] [$(Z)]", {}, ["build"])
add("var-braces-single", "X = hello\nY = ${X} world\nall:\n<T>echo ${Y} $(Y) $X $(X)x $$X", {}, ["build"])
add("var-override", ".PHONY: all\nCC = gcc\nFLAGS = $(CC) -O\nall:\n<T>echo $(CC) $(FLAGS) $(MODE)\nMODE ?= debug", {}, ["build", "build CC=clang", "build MODE=release", "build CC=a MODE=b FLAGS=c"])
add("var-recursive-error", "A = $(B)\nB = $(A)\nall:\n<T>echo $(A)", {}, ["build"])
add("var-recursive-parse-error", "A = $(B)\nB = $(A)\nC := $(A)\nall:\n<T>echo c", {}, ["build"])
add("var-space-idiom", "empty :=\nspace := $(empty) $(empty)\nlist = a b c\nall:\n<T>echo [$(subst $(space),+,$(list))] [$(space)]", {}, ["build"])
add("var-subst-ref", "SRC = a.c b.c dir/c.c\nOBJ = $(SRC:.c=.o)\nDEP = $(SRC:%.c=obj/%.d)\nall:\n<T>echo $(OBJ) / $(DEP)", {}, ["build"])
add("var-in-targets", "T1 = one\nT2 = two\n$(T1) $(T2): common\n<T>echo $@\ncommon:\n<T>echo common", {}, ["build two", "build one", "targets"])
add("comments-continuation", "# comment\nA = a \\\n  b \\\n  c   # trailing\nB = x\\#y\nall: dep1 \\\n dep2 # c\n<T>echo $(A) | $(B) \\\n<T>   more\n<T>echo # not a make comment\ndep1 dep2:", {}, ["build", "expand $(A)"])

add("fn-text", "L = foo.c bar.h baz.c dir/qux.cc\nall:\n<T>@echo [$(subst .c,.o,$(L))] [$(patsubst %.c,%.x,$(L))] [$(patsubst %.c,out/%,$(L))] [$(strip   a   b  c )]\n<T>@echo [$(findstring bar,$(L))] [$(findstring nope,$(L))] [$(filter %.c,$(L))] [$(filter-out %.c %.h,$(L))] [$(filter foo.c baz.c,$(L))]\n<T>@echo [$(sort z b a b c)] [$(word 2,$(L))] [$(word 9,$(L))] [$(word 0,$(L))] [$(wordlist 2,3,$(L))] [$(wordlist 3,99,$(L))] [$(words $(L))] [$(firstword $(L))] [$(lastword $(L))]\n<T>@echo [$(dir $(L) x)] [$(notdir $(L) x)] [$(suffix $(L) x.tar.gz)] [$(basename $(L) a.b/c)]\n<T>@echo [$(addprefix src/,$(L))] [$(addsuffix .bak,a b)]", {}, ["build"])
add("fn-foreach-if", "DIRS = a b c\nFILES = $(foreach d,$(DIRS),$(d)/x.c $(d)/y.c)\nE =\nall:\n<T>@echo [$(FILES)]\n<T>@echo [$(if $(E),yes,no)] [$(if x,yes,no)] [$(if $(E),yes)] [$(if  ,a,b)]\n<T>@echo [$(foreach n,1 2 3,$(n)$(n))] [$(foreach n,,$(n))]\n<T>@echo $(foreach a,x y,$(foreach b,1 2,$(a)$(b)))", {}, ["build"])
add("fn-wildcard", "SRC := $(wildcard src/*.c)\nALL := $(wildcard *.h src/?.c nothing*)\nall:\n<T>@echo [$(SRC)] [$(ALL)] [$(wildcard main.c)]", {"src/b.c": 1, "src/a.c": 1, "src/x.h": 1, "main.c": 1, "a.h": 1, "z.h": 1, "src/sub/q.c": 1}, ["build", "touch src/c.c", "build"])
add("fn-info-error", "$(info parsing)\nA := $(info immediate)x\nall:\n<T>@echo run $(info expanding)\nbad:\n<T>$(error boom $(A))", {}, ["build", "build bad"])
add("fn-error-parse", "ifdef FAIL\n$(error stop at parse)\nendif\nall:\n<T>@echo fine", {}, ["build", "build FAIL=1"])
add("fn-nested-args", "L = a,b c\nall:\n<T>@echo [$(subst $(comma),;,x$(comma)y)] [$(if $(filter a,a b),$(words 1 2 3),zero)] [$(patsubst %,[%],a b)]\ncomma := ,", {}, ["build"])
add("fn-substitution-edge", "all:\n<T>@echo [$(subst ,x,abc)] [$(subst aa,b,aaaaa)] [$(patsubst a%,X,abc bcd)] [$(patsubst abc,X,abc abcd)]", {}, ["build"])

add("cond-ifdef", ".PHONY: all\nA = 1\nEMPTY =\nifdef A\nM1 = a-defined\nelse\nM1 = a-undef\nendif\nifdef EMPTY\nM2 = e-defined\nelse\nM2 = e-undef\nendif\nifndef NOPE\nM3 = nope-undef\nendif\nall:\n<T>@echo $(M1) $(M2) $(M3)", {}, ["build", "build A= EMPTY=x NOPE=1"])
add("cond-ifeq", ".PHONY: all\nMODE = debug\nifeq ($(MODE),debug)\nF = -g\nelse\nF = -O2\nendif\nifneq ($(MODE), release)\nG = notrel\nendif\nifeq (a b, a b)\nH = same\nendif\nall:\n<T>@echo $(F) $(G) $(H)", {}, ["build", "build MODE=release"])
add("cond-nested", ".PHONY: all\nA = 1\nifdef A\nifdef B\nR = ab\nelse\nR = a-only\nendif\nelse\nifdef B\nR = b\nelse\nR = none\nendif\nendif\nall:\n<T>@echo $(R)\nifdef B\nbonly:\n<T>@echo b\nendif", {}, ["build", "build B=1", "build B=1 bonly", "targets B=1"])
add("cond-errors", "ifdef A\nall:\n<T>echo x", {}, ["build"])
add("cond-extraneous", "all:\n<T>echo x\nendif", {}, ["build"])
add("cond-else-twice", "ifdef A\nelse\nelse\nendif", {}, ["build"])

add("err-missing-separator", "all:\n<T>echo ok\nthis is bad\n", {}, ["build", "targets"])
add("err-recipe-first", "<T>echo orphan\nall:\n<T>echo x", {}, ["build"])
add("err-recipe-after-var", "A = 1\n<T>echo orphan\n", {}, ["build"])
add("empty-makefile", "", {}, ["build", "targets", "files", "build x"])

add("dry-run", "all: a b\n<T>@echo all\na: s\n<T>@echo a\n<T>touch a\nb:\n<T>echo b", {"s": 5, "a": 9}, ["dry", "files", "dry a", "build", "dry", "dry all b"])
add("dry-failing-recipes", "all: x\n<T>echo all\nx:\n<T>false\n<T>exit 4", {}, ["dry", "build"])
add("requests-misc", "all:\n<T>@echo hi", {"b": 2, "a": 1}, ["files", "rm a", "files", "touch c 9", "touch d", "files", "bogus", "# comment", "", "rm b c d", "files", "deps", "touch"])
add("expand-request", "A = x y\nB := $(A) z\nall:", {}, ["expand $(A)|$(B)|$$|$(words $(B))", "expand   padded   text  ", "expand $(UNDEF)", "expand $(firstword $(A) $(B)) ${B}"])
add("rebuild-cascade", "a: b\n<T>touch a\nb: c\n<T>touch b\nc: d\n<T>touch c", {"a": 10, "b": 10, "c": 10, "d": 10}, ["build", "touch d 50", "build", "files", "build"])
add("clock-after-touch", "x:\n<T>touch y\ny: z\n<T>touch y", {"z": 100}, ["build", "files", "build y", "files", "touch z 200", "build y", "files"])
add("long-pipeline", """
NAME := app
VERSION = 1.2
SRCS := $(wildcard src/*.c)
OBJS := $(patsubst src/%.c,build/%.o,$(SRCS))
HDRS := $(wildcard src/*.h)
.PHONY: all clean dist
all: build/$(NAME)
build/$(NAME): $(OBJS) | build
<T>@echo linking $@ from $(words $(OBJS)) objects
<T>link -o $@ $^
build:
<T>mkdir build
<T>touch build
build/%.o: src/%.c $(HDRS) | build
<T>compile $< -> $@
dist: build/$(NAME)
<T>tar $(NAME)-$(VERSION).tar $<
<T>touch $(NAME)-$(VERSION).tar
clean:
<T>rm -f $(OBJS) build/$(NAME)
""", {"src/a.c": 10, "src/b.c": 11, "src/c.c": 12, "src/a.h": 5}, ["targets", "build", "build", "touch src/a.h", "build dist", "build dist", "build clean", "files", "build VERSION=2.0 dist"])

hidden = CASES
examples = [case("ex-basic", mk("all: a\n<T>@echo all done\na: b\n<T>cp b a\n", {"b": 3}, ["build", "build", "touch b", "build", "files"])),
            case("ex-pattern-vars", mk("CC = cc\nOBJS = x.o y.o\nprog: $(OBJS)\n<T>$(CC) -o $@ $^\n%.o: %.c\n<T>$(CC) -c $< -o $@\n", {"x.c": 1, "y.c": 2, "y.o": 9}, ["dry", "build CC=gcc", "deps prog"])),
            case("ex-fail", mk(".PHONY: t\nt: a\n<T>echo test\na:\n<T>-false\n<T>exit 2\n<T>echo no\n", {}, ["build"]))]
write_cases(examples, hidden)

"""Generator for c57-assembler-vm. The expected outputs come from the Go oracle in oracle/*.ref (built with the local
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

CASES = []
def add(name, prog, inp=None):
    s = prog.strip("\n") + "\n"
    if inp is not None:
        s += "====\n" + inp + "\n"
    CASES.append(case(name, s))

add("factorial-recursive", """
fact:   cmp r0, 1
        jle base
        push r0
        dec r0
        call fact
        pop r1
        mul r0, r1
base:   ret
main:   mov r0, 10
        call fact
        out r0
        halt
""")
add("fibonacci-loop", """
main:   mov r0, 0
        mov r1, 1
        mov r2, 20
again:  out r0
        mov r3, r0
        add r3, r1
        mov r0, r1
        mov r1, r3
        dec r2
        cmp r2, 0
        jg again
        halt
""")
add("gcd-input", """
main:   in r0
        in r1
loop:   cmp r1, 0
        je done
        mod r0, r1
        mov r2, r0
        mov r0, r1
        mov r1, r2
        jmp loop
done:   out r0
        halt
""", "1071 462")
add("read-until-zero-sum", """
        mov r1, 0
next:   in r0
        cmp r0, 0
        je fin
        add r1, r0
        jmp next
fin:    out r1
        halt
""", "5 -3 10 20\n7 0 99")
add("bubble-sort", """
.equ N, 8
.data
arr:    .space N
.text
main:   mov r0, 0
rd:     in r1
        mov [arr+r0], r1
        inc r0
        cmp r0, N
        jl rd
outer:  mov r2, 0
        mov r3, 0
inner:  mov r4, [arr+r3]
        lea r5, [r3+1]
        mov r6, [arr+r5]
        cmp r4, r6
        jle noswap
        mov [arr+r3], r6
        mov [arr+r5], r4
        mov r2, 1
noswap: inc r3
        cmp r3, N-1
        jl inner
        cmp r2, 0
        jne outer
        mov r0, 0
pr:     mov r1, [arr+r0]
        out r1
        inc r0
        cmp r0, N
        jl pr
        halt
""", "5 2 9 -1 7 7 0 3")
add("sieve", """
.equ LIMIT, 50
.data
flags:  .space LIMIT+1, 1
.text
main:   mov r0, 2
outer:  mov r1, r0
        mul r1, r0
        cmp r1, LIMIT
        jg report
        mov r2, [flags+r0]
        cmp r2, 0
        je nexto
inner:  cmp r1, LIMIT
        jg nexto
        mov r3, 0
        mov [flags+r1], r3
        add r1, r0
        jmp inner
nexto:  inc r0
        jmp outer
report: mov r0, 2
rl:     cmp r0, LIMIT
        jg fin
        mov r2, [flags+r0]
        cmp r2, 0
        je skip
        out r0
skip:   inc r0
        jmp rl
fin:    halt
""")
add("string-print", """
.data
hello:  .asciz "Hello, World!\\n"
.text
main:   mov r0, hello
pl:     mov r1, [r0]
        cmp r1, 0
        je fin
        outc r1
        inc r0
        jmp pl
fin:    halt
""")
add("string-reverse", """
.data
s:      .ascii "stressed"
.equ SLEN, 8
.text
main:   mov r0, 0
pushl:  mov r1, [s+r0]
        push r1
        inc r0
        cmp r0, SLEN
        jl pushl
        mov r0, 0
popl:   pop r1
        outc r1
        inc r0
        cmp r0, SLEN
        jl popl
        outc 10
        halt
""")
add("collatz", """
main:   in r0
        mov r1, 0
loop:   cmp r0, 1
        je done
        mov r2, r0
        and r2, 1
        cmp r2, 0
        je even
        mul r0, 3
        inc r0
        jmp cont
even:   sar r0, 1
cont:   inc r1
        jmp loop
done:   out r1
        halt
""", "27")
add("print-number-digits", """
; prints a number digit by digit using div/mod and the stack
main:   in r0
        cmp r0, 0
        jge pos
        outc '-'
        neg r0
pos:    mov r3, 0
dl:     mov r1, r0
        mod r1, 10
        push r1
        inc r3
        div r0, 10
        cmp r0, 0
        jne dl
pl:     pop r1
        add r1, '0'
        outc r1
        dec r3
        cmp r3, 0
        jg pl
        outc '\\n'
        halt
""", "-90417")
add("call-nested", """
main:   mov r0, 1
        call a
        out r0
        halt
a:      add r0, 10
        call b
        add r0, 100
        ret
b:      add r0, 1000
        call c
        add r0, 10000
        ret
c:      add r0, 100000
        ret
""")
add("flags-jumps", """
main:   mov r0, 3
        mov r1, 5
        cmp r0, r1
        jl l1
        out 0
l1:     out 1
        jle l2
        out 0
l2:     out 2
        jg bad
        out 3
        jge bad
        out 4
        jne l3
        out 0
l3:     out 5
        je bad
        out 6
        cmp r1, r0
        jg l4
        out 0
l4:     out 7
        jge l5
        out 0
l5:     out 8
        cmp r0, r0
        je l6
        out 0
l6:     jz l7
        out 0
l7:     jle l8
        out 0
l8:     jge l9
        out 0
l9:     jnz bad
        out 9
        halt
bad:    out -1
        halt
""")
add("signed-compare-negative", """
main:   mov r0, -5
        mov r1, 3
        cmp r0, r1
        jl neg
        out 0
        halt
neg:    out 1
        cmp r0, -5
        je same
        out 0
same:   out 2
        halt
""")
add("arith-wrap", """
main:   mov r0, 2147483647
        add r0, 1
        out r0
        mov r0, -2147483648
        sub r0, 1
        out r0
        mov r0, 65536
        mul r0, 65536
        out r0
        mov r0, 100000
        mul r0, 100000
        out r0
        mov r0, 4294967295
        out r0
        mov r0, -2147483648
        neg r0
        out r0
        mov r0, -2147483648
        div r0, -1
        out r0
        mov r0, -2147483648
        mod r0, -1
        out r0
        halt
""")
add("div-mod-signs", """
main:   mov r0, 7
        div r0, 2
        out r0
        mov r0, -7
        div r0, 2
        out r0
        mov r0, 7
        div r0, -2
        out r0
        mov r0, -7
        div r0, -2
        out r0
        mov r0, 7
        mod r0, 3
        out r0
        mov r0, -7
        mod r0, 3
        out r0
        mov r0, 7
        mod r0, -3
        out r0
        mov r0, -7
        mod r0, -3
        out r0
        halt
""")
add("bitwise-shifts", """
main:   mov r0, 0xF0F0
        and r0, 0xFF00
        out r0
        mov r0, 0b1010
        or r0, 0b0101
        out r0
        mov r0, 0xFF
        xor r0, 0x0F
        out r0
        mov r0, 1
        shl r0, 31
        out r0
        shr r0, 31
        out r0
        mov r0, -16
        sar r0, 2
        out r0
        mov r0, -16
        shr r0, 28
        out r0
        mov r0, 5
        shl r0, 33
        out r0
        mov r0, 5
        shl r0, -1
        out r0
        mov r0, 0
        not r0
        out r0
        halt
""")
add("memory-modes", """
.data
a:      .word 10, 20, 30, 40
.text
main:   mov r0, [a]
        out r0
        mov r1, 2
        mov r0, [a+1]
        out r0
        mov r0, [r1]
        out r0
        mov r0, [r1+a]
        out r0
        mov r0, [a+r1]
        out r0
        mov r2, 3
        mov r0, [r2-1+a]
        out r0
        mov r0, [r2 - 1]
        out r0
        mov [a+3], r1
        mov r0, [a+3]
        out r0
        mov [r1], 77
        mov r0, [2]
        out r0
        lea r4, [r2+5]
        out r4
        lea r4, [a]
        out r4
        halt
""")
add("data-directives", """
.data
w:      .word 1, -2, 0x10, 'A', w, w+2
s1:     .ascii "ab"
s2:     .asciz "c\\td"
sp1:    .space 3
sp2:    .space 2, 9
tail:   .word tail
.text
main:   mov r1, 0
l:      mov r0, [r1]
        out r0
        inc r1
        cmp r1, 18
        jl l
        out tail
        halt
""")
add("equ-expressions", """
.equ BASE, 100
.equ NEXT, BASE + 5
.equ LATER, EARLY + 1
.equ EARLY, 7
.equ MIXED, 'a' - 'A' + 0x10 - 0b11
.equ NEG, -BASE
main:   out BASE
        out NEXT
        out LATER
        out MIXED
        out NEG
        out BASE-NEXT+ 1
        out - 5
        out 2147483648
        halt
""")
add("entry-main-vs-zero", """
        out 1
        halt
main:   out 2
        halt
""")
add("no-main-starts-at-zero", """
start:  out 1
        out 2
        halt
""")
add("multiple-labels-one-line", """
a: b: c: out 1
d:
        out 2
        jmp c2
c2: halt
""")
add("comments-and-strings", """
.data
msg:    .asciz "semi;colon"  ; real comment
q:      .word ';'  ; char semicolon
.text
main:   mov r0, msg   ; comment ; more
l:      mov r1, [r0]
        cmp r1, 0
        je d
        outc r1
        inc r0
        jmp l
d:      outc 10
        out [q]
        halt
""")
add("sp-and-bp", """
main:   out sp
        push 1
        push 2
        out sp
        mov bp, sp
        add bp, 1
        mov r0, [bp]
        out r0
        mov r0, [sp]
        out r0
        pop r1
        pop r2
        out sp
        sub sp, 2
        mov [sp], 5
        mov [sp+1], 6
        pop r3
        pop r4
        out r3
        out r4
        halt
""")
JT = """
.data
table:  .word case0, case1, case2
.text
main:   in r5
        mov r1, [table+r5]
        push r1
        ret
case0:  out 100
        halt
case1:  out 101
        halt
case2:  out 102
        halt
"""
add("jump-table-0", JT, "0")
add("jump-table-2", JT, "2")
add("jump-table-wild", JT, "3")
add("ret-to-pushed-address", """
main:   push done
        ret
        out 99
done:   out 7
        halt
""")
add("outc-chars", """
main:   outc 72
        outc 105
        outc 33
        outc 10
        outc 126
        outc 10
        halt
""")
add("in-multiple-lines", """
main:   in r0
        in r1
        in r2
        add r0, r1
        add r0, r2
        out r0
        halt
""", "1\n2\n\n  3\n")
add("regs-final-state", """
main:   mov r0, 1
        mov r1, 2
        mov r2, 3
        mov r3, 4
        mov r4, 5
        mov r5, 6
        mov r6, 7
        mov r7, 8
        mov bp, 9
        push 10
        cmp r0, r1
        halt
""")

# traps
add("trap-div-zero", "main: mov r0, 1\n mov r1, 0\n div r0, r1\n out r0\n halt")
add("trap-mem-low", "main: mov r0, -1\n mov r1, [r0]\n halt")
add("trap-mem-high", "main: mov r0, 4096\n out 5\n mov [r0], 1\n halt")
add("trap-mem-abs", "main: out [5000]\n halt")
add("trap-stack-underflow", "main: pop r0\n halt")
add("trap-stack-overflow", "main: push 1\n jmp main")
add("trap-recursion-overflow", "f: call f\nmain: call f\n halt")
add("trap-fall-off-end", "main: out 1\n nop")
add("trap-empty-program", "; nothing here\n")
add("trap-bad-return", "main: push 1000\n ret\n halt")
add("trap-outc-range", "main: outc 65\n outc 200\n halt")
add("trap-input-exhausted", "main: in r0\n in r1\n out r0\n halt", "5")
add("trap-budget-default", "main: jmp main")
add("trap-budget-custom", ".budget 50\nmain: inc r0\n jmp main")
add("budget-exact", ".budget 3\nmain: nop\n nop\n halt")
add("budget-one-short", ".budget 2\nmain: nop\n nop\n halt")
add("budget-large-ok", ".budget 400000\nmain: mov r0, 0\nl: inc r0\n cmp r0, 100000\n jl l\n out r0\n halt")

# assembler errors
for n, p in [
    ("unknown-mnemonic", "main: out 1\n frob r0\n halt"),
    ("uppercase-mnemonic", "main: MOV r0, 1\n halt"),
    ("wrong-count-few", "main: add r0\n halt"),
    ("invalid-dst-imm", "main: add 5, r0\n"),
    ("invalid-mov-mem-mem", "main: mov [1], [2]\n"),
    ("invalid-jump-reg", "main: jmp r0\n"),
    ("bad-mem-operand", "main: mov r0, [r1\n"),
    ("bad-mem-empty", "main: mov r0, []\n"),
    ("duplicate-label", "a: nop\na: nop\n"),
    ("duplicate-equ", ".equ a, 1\n.equ a, 2\n"),
    ("reserved-name", "r0: nop\n"),
    ("undefined-symbol", "main: mov r0, nowhere\n halt"),
    ("undefined-in-word", ".data\nw: .word 1, zzz\n.text\nmain: halt"),
    ("undefined-order", "main: mov r0, aaa\n mov r1, bbb\n halt"),
    ("pass1-before-pass2", "main: mov r0, undefined1\n bogus\n halt"),
    ("circular-equ", ".equ A, B\n.equ B, A\nmain: out A\n"),
    ("unknown-directive", ".bogus 1\nmain: halt"),
    ("data-in-text", "main: halt\n.word 5\n"),
    ("instruction-in-data", ".data\n out 1\n"),
    ("space-forward-label", ".data\n.space later\nlater: .word 1\n"),
    ("space-negative", ".data\n.space -1\n"),
    ("data-too-large", ".data\n.space 4000\n.space 100\n"),
    ("bad-string", ".data\ns: .ascii hello\n"),
    ("bad-expression", "main: out 1 +\n"),
    ("immediate-range", "main: mov r0, 4294967296\n"),
    ("bad-char-literal", "main: mov r0, 'ab'\n"),
    ("jump-target-range", ".equ FAR, 100\nmain: jmp FAR\n"),
    ("budget-bad", ".budget 0\nmain: halt"),
    ("equ-bad-name", ".equ 1x, 5\n"),
    ("error-line-number", "; line 1\n\n  \nmain: nop ; four\n\n nope\n"),
]:
    add("asm-" + n, p)

add("dotted-label", "main: jmp loop.1\nloop.1: out 5\n halt")
add("label-after-last-instruction", "main: jmp tail\n halt\ntail:\n")

hidden = CASES
examples = [
    case("ex-sum", "main: in r0\n mov r1, 0\nl: add r1, r0\n dec r0\n cmp r0, 0\n jg l\n out r1\n halt\n====\n10\n"),
    case("ex-hello", ".data\nmsg: .asciz \"Hi!\\n\"\n.text\nmain: mov r0, msg\nl: mov r1, [r0]\n cmp r1, 0\n je d\n outc r1\n inc r0\n jmp l\nd: halt\n"),
    case("ex-trap", "main: mov r0, 5\n mov r1, 0\n div r0, r1\n halt\n"),
    case("ex-error", "main: out 1\n bogus r0\n"),
]
write_cases(examples, hidden)

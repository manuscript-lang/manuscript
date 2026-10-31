# Generator for c57-assembler-vm. The expected outputs come from the Go oracle in oracle/*.ref (built with the
# local Go toolchain); this file only supplies the inputs. Deterministic; run: ms run bench/agent/gen.ms -- c57
import Cases, build_oracle, write_cases from "../../lib/gen.ms"

let JT = "\n.data\ntable:  .word case0, case1, case2\n.text\nmain:   in r5\n        mov r1, [table+r5]\n        push r1\n        ret\ncase0:  out 100\n        halt\ncase1:  out 101\n        halt\ncase2:  out 102\n        halt\n"

fn strip_nl(text: String) String:
    var chars = text.chars()
    var start = 0
    var end = chars.length()
    while start < end and chars[start] == "\n":
        start += 1
    while end > start and chars[end - 1] == "\n":
        end -= 1
    return chars.slice(start, end).get([]).join("")

fn add(var cs: Cases, name: String, prog: String, inp: String? = none) Unit:
    var s = strip_nl(prog) + "\n"
    if let text = inp:
        s += "====\n" + text + "\n"
    cs.push(name, s)

export fn gen_c57() Unit:
    var cs = Cases(build_oracle("c57-assembler-vm"))
    add(
        var cs, "factorial-recursive",
        "\nfact:   cmp r0, 1\n        jle base\n        push r0\n        dec r0\n        call fact\n        pop r1\n        mul r0, r1\nbase:   ret\nmain:   mov r0, 10\n        call fact\n        out r0\n        halt\n"
    )
    add(
        var cs, "fibonacci-loop",
        "\nmain:   mov r0, 0\n        mov r1, 1\n        mov r2, 20\nagain:  out r0\n        mov r3, r0\n        add r3, r1\n        mov r0, r1\n        mov r1, r3\n        dec r2\n        cmp r2, 0\n        jg again\n        halt\n"
    )
    add(
        var cs, "gcd-input",
        "\nmain:   in r0\n        in r1\nloop:   cmp r1, 0\n        je done\n        mod r0, r1\n        mov r2, r0\n        mov r0, r1\n        mov r1, r2\n        jmp loop\ndone:   out r0\n        halt\n",
        "1071 462"
    )
    add(
        var cs, "read-until-zero-sum",
        "\n        mov r1, 0\nnext:   in r0\n        cmp r0, 0\n        je fin\n        add r1, r0\n        jmp next\nfin:    out r1\n        halt\n",
        "5 -3 10 20\n7 0 99"
    )
    add(
        var cs, "bubble-sort",
        "\n.equ N, 8\n.data\narr:    .space N\n.text\nmain:   mov r0, 0\nrd:     in r1\n        mov [arr+r0], r1\n        inc r0\n        cmp r0, N\n        jl rd\nouter:  mov r2, 0\n        mov r3, 0\ninner:  mov r4, [arr+r3]\n        lea r5, [r3+1]\n        mov r6, [arr+r5]\n        cmp r4, r6\n        jle noswap\n        mov [arr+r3], r6\n        mov [arr+r5], r4\n        mov r2, 1\nnoswap: inc r3\n        cmp r3, N-1\n        jl inner\n        cmp r2, 0\n        jne outer\n        mov r0, 0\npr:     mov r1, [arr+r0]\n        out r1\n        inc r0\n        cmp r0, N\n        jl pr\n        halt\n",
        "5 2 9 -1 7 7 0 3"
    )
    add(
        var cs, "sieve",
        "\n.equ LIMIT, 50\n.data\nflags:  .space LIMIT+1, 1\n.text\nmain:   mov r0, 2\nouter:  mov r1, r0\n        mul r1, r0\n        cmp r1, LIMIT\n        jg report\n        mov r2, [flags+r0]\n        cmp r2, 0\n        je nexto\ninner:  cmp r1, LIMIT\n        jg nexto\n        mov r3, 0\n        mov [flags+r1], r3\n        add r1, r0\n        jmp inner\nnexto:  inc r0\n        jmp outer\nreport: mov r0, 2\nrl:     cmp r0, LIMIT\n        jg fin\n        mov r2, [flags+r0]\n        cmp r2, 0\n        je skip\n        out r0\nskip:   inc r0\n        jmp rl\nfin:    halt\n"
    )
    add(
        var cs, "string-print",
        "\n.data\nhello:  .asciz \"Hello, World!\\n\"\n.text\nmain:   mov r0, hello\npl:     mov r1, [r0]\n        cmp r1, 0\n        je fin\n        outc r1\n        inc r0\n        jmp pl\nfin:    halt\n"
    )
    add(
        var cs, "string-reverse",
        "\n.data\ns:      .ascii \"stressed\"\n.equ SLEN, 8\n.text\nmain:   mov r0, 0\npushl:  mov r1, [s+r0]\n        push r1\n        inc r0\n        cmp r0, SLEN\n        jl pushl\n        mov r0, 0\npopl:   pop r1\n        outc r1\n        inc r0\n        cmp r0, SLEN\n        jl popl\n        outc 10\n        halt\n"
    )
    add(
        var cs, "collatz",
        "\nmain:   in r0\n        mov r1, 0\nloop:   cmp r0, 1\n        je done\n        mov r2, r0\n        and r2, 1\n        cmp r2, 0\n        je even\n        mul r0, 3\n        inc r0\n        jmp cont\neven:   sar r0, 1\ncont:   inc r1\n        jmp loop\ndone:   out r1\n        halt\n",
        "27"
    )
    add(
        var cs, "print-number-digits",
        "\n; prints a number digit by digit using div/mod and the stack\nmain:   in r0\n        cmp r0, 0\n        jge pos\n        outc '-'\n        neg r0\npos:    mov r3, 0\ndl:     mov r1, r0\n        mod r1, 10\n        push r1\n        inc r3\n        div r0, 10\n        cmp r0, 0\n        jne dl\npl:     pop r1\n        add r1, '0'\n        outc r1\n        dec r3\n        cmp r3, 0\n        jg pl\n        outc '\\n'\n        halt\n",
        "-90417"
    )
    add(
        var cs, "call-nested",
        "\nmain:   mov r0, 1\n        call a\n        out r0\n        halt\na:      add r0, 10\n        call b\n        add r0, 100\n        ret\nb:      add r0, 1000\n        call c\n        add r0, 10000\n        ret\nc:      add r0, 100000\n        ret\n"
    )
    add(
        var cs, "flags-jumps",
        "\nmain:   mov r0, 3\n        mov r1, 5\n        cmp r0, r1\n        jl l1\n        out 0\nl1:     out 1\n        jle l2\n        out 0\nl2:     out 2\n        jg bad\n        out 3\n        jge bad\n        out 4\n        jne l3\n        out 0\nl3:     out 5\n        je bad\n        out 6\n        cmp r1, r0\n        jg l4\n        out 0\nl4:     out 7\n        jge l5\n        out 0\nl5:     out 8\n        cmp r0, r0\n        je l6\n        out 0\nl6:     jz l7\n        out 0\nl7:     jle l8\n        out 0\nl8:     jge l9\n        out 0\nl9:     jnz bad\n        out 9\n        halt\nbad:    out -1\n        halt\n"
    )
    add(
        var cs, "signed-compare-negative",
        "\nmain:   mov r0, -5\n        mov r1, 3\n        cmp r0, r1\n        jl neg\n        out 0\n        halt\nneg:    out 1\n        cmp r0, -5\n        je same\n        out 0\nsame:   out 2\n        halt\n"
    )
    add(
        var cs, "arith-wrap",
        "\nmain:   mov r0, 2147483647\n        add r0, 1\n        out r0\n        mov r0, -2147483648\n        sub r0, 1\n        out r0\n        mov r0, 65536\n        mul r0, 65536\n        out r0\n        mov r0, 100000\n        mul r0, 100000\n        out r0\n        mov r0, 4294967295\n        out r0\n        mov r0, -2147483648\n        neg r0\n        out r0\n        mov r0, -2147483648\n        div r0, -1\n        out r0\n        mov r0, -2147483648\n        mod r0, -1\n        out r0\n        halt\n"
    )
    add(
        var cs, "div-mod-signs",
        "\nmain:   mov r0, 7\n        div r0, 2\n        out r0\n        mov r0, -7\n        div r0, 2\n        out r0\n        mov r0, 7\n        div r0, -2\n        out r0\n        mov r0, -7\n        div r0, -2\n        out r0\n        mov r0, 7\n        mod r0, 3\n        out r0\n        mov r0, -7\n        mod r0, 3\n        out r0\n        mov r0, 7\n        mod r0, -3\n        out r0\n        mov r0, -7\n        mod r0, -3\n        out r0\n        halt\n"
    )
    add(
        var cs, "bitwise-shifts",
        "\nmain:   mov r0, 0xF0F0\n        and r0, 0xFF00\n        out r0\n        mov r0, 0b1010\n        or r0, 0b0101\n        out r0\n        mov r0, 0xFF\n        xor r0, 0x0F\n        out r0\n        mov r0, 1\n        shl r0, 31\n        out r0\n        shr r0, 31\n        out r0\n        mov r0, -16\n        sar r0, 2\n        out r0\n        mov r0, -16\n        shr r0, 28\n        out r0\n        mov r0, 5\n        shl r0, 33\n        out r0\n        mov r0, 5\n        shl r0, -1\n        out r0\n        mov r0, 0\n        not r0\n        out r0\n        halt\n"
    )
    add(
        var cs, "memory-modes",
        "\n.data\na:      .word 10, 20, 30, 40\n.text\nmain:   mov r0, [a]\n        out r0\n        mov r1, 2\n        mov r0, [a+1]\n        out r0\n        mov r0, [r1]\n        out r0\n        mov r0, [r1+a]\n        out r0\n        mov r0, [a+r1]\n        out r0\n        mov r2, 3\n        mov r0, [r2-1+a]\n        out r0\n        mov r0, [r2 - 1]\n        out r0\n        mov [a+3], r1\n        mov r0, [a+3]\n        out r0\n        mov [r1], 77\n        mov r0, [2]\n        out r0\n        lea r4, [r2+5]\n        out r4\n        lea r4, [a]\n        out r4\n        halt\n"
    )
    add(
        var cs, "data-directives",
        "\n.data\nw:      .word 1, -2, 0x10, 'A', w, w+2\ns1:     .ascii \"ab\"\ns2:     .asciz \"c\\td\"\nsp1:    .space 3\nsp2:    .space 2, 9\ntail:   .word tail\n.text\nmain:   mov r1, 0\nl:      mov r0, [r1]\n        out r0\n        inc r1\n        cmp r1, 18\n        jl l\n        out tail\n        halt\n"
    )
    add(
        var cs, "equ-expressions",
        "\n.equ BASE, 100\n.equ NEXT, BASE + 5\n.equ LATER, EARLY + 1\n.equ EARLY, 7\n.equ MIXED, 'a' - 'A' + 0x10 - 0b11\n.equ NEG, -BASE\nmain:   out BASE\n        out NEXT\n        out LATER\n        out MIXED\n        out NEG\n        out BASE-NEXT+ 1\n        out - 5\n        out 2147483648\n        halt\n"
    )
    add(
        var cs, "entry-main-vs-zero",
        "\n        out 1\n        halt\nmain:   out 2\n        halt\n"
    )
    add(
        var cs, "no-main-starts-at-zero",
        "\nstart:  out 1\n        out 2\n        halt\n"
    )
    add(
        var cs, "multiple-labels-one-line",
        "\na: b: c: out 1\nd:\n        out 2\n        jmp c2\nc2: halt\n"
    )
    add(
        var cs, "comments-and-strings",
        "\n.data\nmsg:    .asciz \"semi;colon\"  ; real comment\nq:      .word ';'  ; char semicolon\n.text\nmain:   mov r0, msg   ; comment ; more\nl:      mov r1, [r0]\n        cmp r1, 0\n        je d\n        outc r1\n        inc r0\n        jmp l\nd:      outc 10\n        out [q]\n        halt\n"
    )
    add(
        var cs, "sp-and-bp",
        "\nmain:   out sp\n        push 1\n        push 2\n        out sp\n        mov bp, sp\n        add bp, 1\n        mov r0, [bp]\n        out r0\n        mov r0, [sp]\n        out r0\n        pop r1\n        pop r2\n        out sp\n        sub sp, 2\n        mov [sp], 5\n        mov [sp+1], 6\n        pop r3\n        pop r4\n        out r3\n        out r4\n        halt\n"
    )
    add(var cs, "jump-table-0", JT, "0")
    add(var cs, "jump-table-2", JT, "2")
    add(var cs, "jump-table-wild", JT, "3")
    add(
        var cs, "ret-to-pushed-address",
        "\nmain:   push done\n        ret\n        out 99\ndone:   out 7\n        halt\n"
    )
    add(
        var cs, "outc-chars",
        "\nmain:   outc 72\n        outc 105\n        outc 33\n        outc 10\n        outc 126\n        outc 10\n        halt\n"
    )
    add(
        var cs, "in-multiple-lines",
        "\nmain:   in r0\n        in r1\n        in r2\n        add r0, r1\n        add r0, r2\n        out r0\n        halt\n",
        "1\n2\n\n  3\n"
    )
    add(
        var cs, "regs-final-state",
        "\nmain:   mov r0, 1\n        mov r1, 2\n        mov r2, 3\n        mov r3, 4\n        mov r4, 5\n        mov r5, 6\n        mov r6, 7\n        mov r7, 8\n        mov bp, 9\n        push 10\n        cmp r0, r1\n        halt\n"
    )
    add(
        var cs, "trap-div-zero",
        "main: mov r0, 1\n mov r1, 0\n div r0, r1\n out r0\n halt"
    )
    add(var cs, "trap-mem-low", "main: mov r0, -1\n mov r1, [r0]\n halt")
    add(var cs, "trap-mem-high", "main: mov r0, 4096\n out 5\n mov [r0], 1\n halt")
    add(var cs, "trap-mem-abs", "main: out [5000]\n halt")
    add(var cs, "trap-stack-underflow", "main: pop r0\n halt")
    add(var cs, "trap-stack-overflow", "main: push 1\n jmp main")
    add(var cs, "trap-recursion-overflow", "f: call f\nmain: call f\n halt")
    add(var cs, "trap-fall-off-end", "main: out 1\n nop")
    add(var cs, "trap-empty-program", "; nothing here\n")
    add(var cs, "trap-bad-return", "main: push 1000\n ret\n halt")
    add(var cs, "trap-outc-range", "main: outc 65\n outc 200\n halt")
    add(var cs, "trap-input-exhausted", "main: in r0\n in r1\n out r0\n halt", "5")
    add(var cs, "trap-budget-default", "main: jmp main")
    add(var cs, "trap-budget-custom", ".budget 50\nmain: inc r0\n jmp main")
    add(var cs, "budget-exact", ".budget 3\nmain: nop\n nop\n halt")
    add(var cs, "budget-one-short", ".budget 2\nmain: nop\n nop\n halt")
    add(
        var cs, "budget-large-ok",
        ".budget 400000\nmain: mov r0, 0\nl: inc r0\n cmp r0, 100000\n jl l\n out r0\n halt"
    )

    let asm_errors = [
        "unknown-mnemonic", "main: out 1\n frob r0\n halt", "uppercase-mnemonic",
        "main: MOV r0, 1\n halt", "wrong-count-few", "main: add r0\n halt",
        "invalid-dst-imm", "main: add 5, r0\n", "invalid-mov-mem-mem",
        "main: mov [1], [2]\n", "invalid-jump-reg", "main: jmp r0\n", "bad-mem-operand",
        "main: mov r0, [r1\n", "bad-mem-empty", "main: mov r0, []\n", "duplicate-label",
        "a: nop\na: nop\n", "duplicate-equ", ".equ a, 1\n.equ a, 2\n", "reserved-name",
        "r0: nop\n", "undefined-symbol", "main: mov r0, nowhere\n halt",
        "undefined-in-word", ".data\nw: .word 1, zzz\n.text\nmain: halt",
        "undefined-order", "main: mov r0, aaa\n mov r1, bbb\n halt",
        "pass1-before-pass2", "main: mov r0, undefined1\n bogus\n halt", "circular-equ",
        ".equ A, B\n.equ B, A\nmain: out A\n", "unknown-directive",
        ".bogus 1\nmain: halt", "data-in-text", "main: halt\n.word 5\n",
        "instruction-in-data", ".data\n out 1\n", "space-forward-label",
        ".data\n.space later\nlater: .word 1\n", "space-negative", ".data\n.space -1\n",
        "data-too-large", ".data\n.space 4000\n.space 100\n", "bad-string",
        ".data\ns: .ascii hello\n", "bad-expression", "main: out 1 +\n",
        "immediate-range", "main: mov r0, 4294967296\n", "bad-char-literal",
        "main: mov r0, 'ab'\n", "jump-target-range", ".equ FAR, 100\nmain: jmp FAR\n",
        "budget-bad", ".budget 0\nmain: halt", "equ-bad-name", ".equ 1x, 5\n",
        "error-line-number", "; line 1\n\n  \nmain: nop ; four\n\n nope\n"
    ]
    var k = 0

    while k < asm_errors.length():
        add(var cs, "asm-" + asm_errors[k], asm_errors[k + 1].clone())
        k += 2

    add(var cs, "dotted-label", "main: jmp loop.1\nloop.1: out 5\n halt")
    add(var cs, "label-after-last-instruction", "main: jmp tail\n halt\ntail:\n")

    let examples = [
        cs.make(
            "ex-sum",
            "main: in r0\n mov r1, 0\nl: add r1, r0\n dec r0\n cmp r0, 0\n jg l\n out r1\n halt\n====\n10\n"
        ),
        cs.make(
            "ex-hello",
            ".data\nmsg: .asciz \"Hi!\\n\"\n.text\nmain: mov r0, msg\nl: mov r1, [r0]\n cmp r1, 0\n je d\n outc r1\n inc r0\n jmp l\nd: halt\n"
        ),
        cs.make("ex-trap", "main: mov r0, 5\n mov r1, 0\n div r0, r1\n halt\n"),
        cs.make("ex-error", "main: out 1\n bogus r0\n")
    ]
    write_cases("c57-assembler-vm", examples, cs.list)

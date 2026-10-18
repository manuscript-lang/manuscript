TEXT main.bench_try(SB) generated.go
  generated.go:1	0x59dce0		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59dce4		0f8650010000		JBE 0x59de3a
  generated.go:1	0x59dcea		55			PUSHQ BP
  generated.go:1	0x59dceb		4889e5			MOVQ SP, BP
  generated.go:1	0x59dcee		4883ec60		SUBQ $0x60, SP
  main.ms:151		0x59dcf2		4889442470		MOVQ AX, 0x70(SP)
  main.ms:147		0x59dcf7		90			NOPL
  host.go:167		0x59dcf8		e8034cffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59dcfd		488b8898000000		MOVQ 0x98(AX), CX
  main.ms:147		0x59dd04		488b4918		MOVQ 0x18(CX), CX
  host.go:167		0x59dd08		488b80a0000000		MOVQ 0xa0(AX), AX
  main.ms:147		0x59dd0f		488b5c2470		MOVQ 0x70(SP), BX
  main.ms:147		0x59dd14		ffd1			CALL CX
  main.ms:147		0x59dd16		4889442458		MOVQ AX, 0x58(SP)
  main.ms:147		0x59dd1b		48895c2450		MOVQ BX, 0x50(SP)
  main.ms:151		0x59dd20		488b4c2470		MOVQ 0x70(SP), CX
  main.ms:151		0x59dd25		31d2			XORL DX, DX
  main.ms:151		0x59dd27		31f6			XORL SI, SI
  main.ms:151		0x59dd29		eb06			JMP 0x59dd31
  main.ms:151		0x59dd2b		4c89ca			MOVQ R9, DX
  main.ms:155		0x59dd2e		4c89de			MOVQ R11, SI
  main.ms:155		0x59dd31		4889742430		MOVQ SI, 0x30(SP)
  main.ms:155		0x59dd36		660f1f840000000000	NOPW 0(AX)(AX*1)
  main.ms:155		0x59dd3f		90			NOPL
  main.ms:151		0x59dd40		4881fa40420f00		CMPQ DX, $0xf4240
  main.ms:151		0x59dd47		0f8daf000000		JGE 0x59ddfc
  main.ms:151		0x59dd4d		4c8d4a01		LEAQ 0x1(DX), R9
  main.ms:151		0x59dd51		4c894c2438		MOVQ R9, 0x38(SP)
  main.ms:151		0x59dd56		49f7c13f000000		TESTQ $0x3f, R9
  main.ms:151		0x59dd5d		7548			JNE 0x59dda7
  main.ms:151		0x59dd5f		90			NOPL
  exec.go:97		0x59dd60		4885c9			TESTQ CX, CX
  exec.go:97		0x59dd63		7442			JE 0x59dda7
  main.ms:151		0x59dd65		4889542440		MOVQ DX, 0x40(SP)
  exec.go:97		0x59dd6a		488b11			MOVQ 0(CX), DX
  exec.go:97		0x59dd6d		488b4108		MOVQ 0x8(CX), AX
  exec.go:93		0x59dd71		488b4a28		MOVQ 0x28(DX), CX
  exec.go:93		0x59dd75		ffd1			CALL CX
  exec.go:93		0x59dd77		660f1f840000000000	NOPW 0(AX)(AX*1)
  exec.go:93		0x59dd80		4885c0			TESTQ AX, AX
  exec.go:97		0x59dd83		0f859d000000		JNE 0x59de26
  main.ms:159		0x59dd89		488b442458		MOVQ 0x58(SP), AX
  exec.go:97		0x59dd8e		488b4c2470		MOVQ 0x70(SP), CX
  numeric.go:18		0x59dd93		488b542440		MOVQ 0x40(SP), DX
  main.ms:159		0x59dd98		488b5c2450		MOVQ 0x50(SP), BX
  numeric.go:18		0x59dd9d		488b742430		MOVQ 0x30(SP), SI
  numeric.go:19		0x59dda2		4c8b4c2438		MOVQ 0x38(SP), R9
  numeric.go:18		0x59dda7		4c8d1432		LEAQ 0(DX)(SI*1), R10
  numeric.go:18		0x59ddab		4d8d5201		LEAQ 0x1(R10), R10
  numeric.go:19		0x59ddaf		4c31d6			XORQ R10, SI
  numeric.go:19		0x59ddb2		4d89d3			MOVQ R10, R11
  numeric.go:19		0x59ddb5		4d31ca			XORQ R9, R10
  main.ms:152		0x59ddb8		90			NOPL
  main.ms:153		0x59ddb9		90			NOPL
  main.ms:47		0x59ddba		90			NOPL
  numeric.go:14		0x59ddbb		90			NOPL
  numeric.go:14		0x59ddbc		0f1f4000		NOPL 0(AX)
  numeric.go:19		0x59ddc0		4c85d6			TESTQ R10, SI
  numeric.go:19		0x59ddc3		0f8d62ffffff		JGE 0x59dd2b
  numeric.go:18		0x59ddc9		4c895c2448		MOVQ R11, 0x48(SP)
  numeric.go:20		0x59ddce		488b057b940d00		MOVQ 0xd947b(IP), AX
  numeric.go:20		0x59ddd5		488d1574940d00		LEAQ 0xd9474(IP), DX
  numeric.go:20		0x59dddc		ffd0			CALL AX
  main.ms:159		0x59ddde		488b442458		MOVQ 0x58(SP), AX
  exec.go:97		0x59dde3		488b4c2470		MOVQ 0x70(SP), CX
  main.ms:159		0x59dde8		488b5c2450		MOVQ 0x50(SP), BX
  main.ms:151		0x59dded		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:155		0x59ddf2		4c8b5c2448		MOVQ 0x48(SP), R11
  numeric.go:20		0x59ddf7		e92fffffff		JMP 0x59dd2b
  main.ms:159		0x59ddfc		bf40420f00		MOVL $0xf4240, DI
  main.ms:159		0x59de01		4889c6			MOVQ AX, SI
  main.ms:159		0x59de04		4989d8			MOVQ BX, R8
  main.ms:159		0x59de07		4889c8			MOVQ CX, AX
  main.ms:159		0x59de0a		488d1dfcda0b00		LEAQ 0xbdafc(IP), BX
  main.ms:159		0x59de11		b903000000		MOVL $0x3, CX
  main.ms:159		0x59de16		e825f0ffff		CALL main.report(SB)
  main.ms:160		0x59de1b		488b442430		MOVQ 0x30(SP), AX
  main.ms:160		0x59de20		4883c460		ADDQ $0x60, SP
  main.ms:160		0x59de24		5d			POPQ BP
  main.ms:160		0x59de25		c3			RET
  exec.go:98		0x59de26		488d0513870600		LEAQ 0x68713(IP), AX
  exec.go:98		0x59de2d		488d1d4cdf2f00		LEAQ 0x2fdf4c(IP), BX
  exec.go:98		0x59de34		e8a76eedff		CALL runtime.gopanic(SB)
  exec.go:98		0x59de39		90			NOPL
  generated.go:1	0x59de3a		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59de3f		90			NOPL
  generated.go:1	0x59de40		e8fbc9edff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59de45		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59de4a		e991feffff		JMP main.bench_try(SB)

TEXT main.bench_method(SB) generated.go
  generated.go:1	0x59dba0		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59dba4		0f8630010000		JBE 0x59dcda
  generated.go:1	0x59dbaa		55			PUSHQ BP
  generated.go:1	0x59dbab		4889e5			MOVQ SP, BP
  generated.go:1	0x59dbae		4883ec58		SUBQ $0x58, SP
  main.ms:139		0x59dbb2		4889442468		MOVQ AX, 0x68(SP)
  main.ms:135		0x59dbb7		90			NOPL
  host.go:167		0x59dbb8		e8434dffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59dbbd		488b8898000000		MOVQ 0x98(AX), CX
  main.ms:135		0x59dbc4		488b4918		MOVQ 0x18(CX), CX
  host.go:167		0x59dbc8		488b80a0000000		MOVQ 0xa0(AX), AX
  main.ms:135		0x59dbcf		488b5c2468		MOVQ 0x68(SP), BX
  main.ms:135		0x59dbd4		ffd1			CALL CX
  main.ms:135		0x59dbd6		4889442450		MOVQ AX, 0x50(SP)
  main.ms:135		0x59dbdb		48895c2440		MOVQ BX, 0x40(SP)
  main.ms:136		0x59dbe0		48c744244800000000	MOVQ $0x0, 0x48(SP)
  main.ms:139		0x59dbe9		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:139		0x59dbee		31d2			XORL DX, DX
  main.ms:139		0x59dbf0		eb0e			JMP 0x59dc00
  main.ms:14		0x59dbf2		4c89642448		MOVQ R12, 0x48(SP)
  main.ms:139		0x59dbf7		4c89ca			MOVQ R9, DX
  main.ms:139		0x59dbfa		660f1f440000		NOPW 0(AX)(AX*1)
  main.ms:139		0x59dc00		4881fa40420f00		CMPQ DX, $0xf4240
  main.ms:139		0x59dc07		0f8d8f000000		JGE 0x59dc9c
  main.ms:139		0x59dc0d		4c8d4a01		LEAQ 0x1(DX), R9
  main.ms:139		0x59dc11		4c894c2438		MOVQ R9, 0x38(SP)
  main.ms:139		0x59dc16		49f7c13f000000		TESTQ $0x3f, R9
  main.ms:139		0x59dc1d		7530			JNE 0x59dc4f
  main.ms:139		0x59dc1f		90			NOPL
  exec.go:97		0x59dc20		4885c9			TESTQ CX, CX
  exec.go:97		0x59dc23		742a			JE 0x59dc4f
  exec.go:97		0x59dc25		488b11			MOVQ 0(CX), DX
  exec.go:97		0x59dc28		488b4108		MOVQ 0x8(CX), AX
  exec.go:93		0x59dc2c		488b4a28		MOVQ 0x28(DX), CX
  exec.go:93		0x59dc30		ffd1			CALL CX
  exec.go:93		0x59dc32		4885c0			TESTQ AX, AX
  exec.go:97		0x59dc35		0f858b000000		JNE 0x59dcc6
  main.ms:143		0x59dc3b		488b442450		MOVQ 0x50(SP), AX
  exec.go:97		0x59dc40		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:143		0x59dc45		488b5c2440		MOVQ 0x40(SP), BX
  main.ms:139		0x59dc4a		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:14		0x59dc4f		4c8b542448		MOVQ 0x48(SP), R10
  numeric.go:18		0x59dc54		4d8d5a01		LEAQ 0x1(R10), R11
  numeric.go:19		0x59dc58		4d31da			XORQ R11, R10
  numeric.go:19		0x59dc5b		4d89dc			MOVQ R11, R12
  numeric.go:19		0x59dc5e		4983f301		XORQ $0x1, R11
  main.ms:140		0x59dc62		90			NOPL
  numeric.go:14		0x59dc63		90			NOPL
  numeric.go:19		0x59dc64		4d85da			TESTQ R11, R10
  numeric.go:19		0x59dc67		7d89			JGE 0x59dbf2
  numeric.go:18		0x59dc69		4c89642430		MOVQ R12, 0x30(SP)
  numeric.go:20		0x59dc6e		488b05db950d00		MOVQ 0xd95db(IP), AX
  numeric.go:20		0x59dc75		488d15d4950d00		LEAQ 0xd95d4(IP), DX
  numeric.go:20		0x59dc7c		ffd0			CALL AX
  main.ms:143		0x59dc7e		488b442450		MOVQ 0x50(SP), AX
  exec.go:97		0x59dc83		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:143		0x59dc88		488b5c2440		MOVQ 0x40(SP), BX
  main.ms:139		0x59dc8d		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:14		0x59dc92		4c8b642430		MOVQ 0x30(SP), R12
  numeric.go:20		0x59dc97		e956ffffff		JMP 0x59dbf2
  main.ms:143		0x59dc9c		bf40420f00		MOVL $0xf4240, DI
  main.ms:143		0x59dca1		4889c6			MOVQ AX, SI
  main.ms:143		0x59dca4		4989d8			MOVQ BX, R8
  main.ms:143		0x59dca7		4889c8			MOVQ CX, AX
  main.ms:143		0x59dcaa		488d1d3e270c00		LEAQ 0xc273e(IP), BX
  main.ms:143		0x59dcb1		b90b000000		MOVL $0xb, CX
  main.ms:143		0x59dcb6		e805f2ffff		CALL main.report(SB)
  main.ms:144		0x59dcbb		488b442448		MOVQ 0x48(SP), AX
  main.ms:144		0x59dcc0		4883c458		ADDQ $0x58, SP
  main.ms:144		0x59dcc4		5d			POPQ BP
  main.ms:144		0x59dcc5		c3			RET
  exec.go:98		0x59dcc6		488d0573880600		LEAQ 0x68873(IP), AX
  exec.go:98		0x59dccd		488d1dace02f00		LEAQ runtime.zerobase(SB), BX
  exec.go:98		0x59dcd4		e80770edff		CALL runtime.gopanic(SB)
  exec.go:98		0x59dcd9		90			NOPL
  generated.go:1	0x59dcda		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59dcdf		90			NOPL
  generated.go:1	0x59dce0		e85bcbedff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59dce5		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59dcea		e9b1feffff		JMP main.bench_method(SB)

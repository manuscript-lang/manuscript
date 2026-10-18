TEXT main.bench_method(SB) generated.go
  generated.go:1	0x59db80		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59db84		0f8630010000		JBE 0x59dcba
  generated.go:1	0x59db8a		55			PUSHQ BP
  generated.go:1	0x59db8b		4889e5			MOVQ SP, BP
  generated.go:1	0x59db8e		4883ec58		SUBQ $0x58, SP
  main.ms:139		0x59db92		4889442468		MOVQ AX, 0x68(SP)
  main.ms:135		0x59db97		90			NOPL
  host.go:167		0x59db98		e8634dffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59db9d		488b8898000000		MOVQ 0x98(AX), CX
  main.ms:135		0x59dba4		488b4918		MOVQ 0x18(CX), CX
  host.go:167		0x59dba8		488b80a0000000		MOVQ 0xa0(AX), AX
  main.ms:135		0x59dbaf		488b5c2468		MOVQ 0x68(SP), BX
  main.ms:135		0x59dbb4		ffd1			CALL CX
  main.ms:135		0x59dbb6		4889442450		MOVQ AX, 0x50(SP)
  main.ms:135		0x59dbbb		48895c2440		MOVQ BX, 0x40(SP)
  main.ms:136		0x59dbc0		48c744244800000000	MOVQ $0x0, 0x48(SP)
  main.ms:139		0x59dbc9		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:139		0x59dbce		31d2			XORL DX, DX
  main.ms:139		0x59dbd0		eb0e			JMP 0x59dbe0
  main.ms:14		0x59dbd2		4c89642448		MOVQ R12, 0x48(SP)
  main.ms:139		0x59dbd7		4c89ca			MOVQ R9, DX
  main.ms:139		0x59dbda		660f1f440000		NOPW 0(AX)(AX*1)
  main.ms:139		0x59dbe0		4881fa40420f00		CMPQ DX, $0xf4240
  main.ms:139		0x59dbe7		0f8d8f000000		JGE 0x59dc7c
  main.ms:139		0x59dbed		4c8d4a01		LEAQ 0x1(DX), R9
  main.ms:139		0x59dbf1		4c894c2438		MOVQ R9, 0x38(SP)
  main.ms:139		0x59dbf6		49f7c13f000000		TESTQ $0x3f, R9
  main.ms:139		0x59dbfd		7530			JNE 0x59dc2f
  main.ms:139		0x59dbff		90			NOPL
  exec.go:97		0x59dc00		4885c9			TESTQ CX, CX
  exec.go:97		0x59dc03		742a			JE 0x59dc2f
  exec.go:97		0x59dc05		488b11			MOVQ 0(CX), DX
  exec.go:97		0x59dc08		488b4108		MOVQ 0x8(CX), AX
  exec.go:93		0x59dc0c		488b4a28		MOVQ 0x28(DX), CX
  exec.go:93		0x59dc10		ffd1			CALL CX
  exec.go:93		0x59dc12		4885c0			TESTQ AX, AX
  exec.go:97		0x59dc15		0f858b000000		JNE 0x59dca6
  main.ms:143		0x59dc1b		488b442450		MOVQ 0x50(SP), AX
  exec.go:97		0x59dc20		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:143		0x59dc25		488b5c2440		MOVQ 0x40(SP), BX
  main.ms:139		0x59dc2a		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:14		0x59dc2f		4c8b542448		MOVQ 0x48(SP), R10
  numeric.go:18		0x59dc34		4d8d5a01		LEAQ 0x1(R10), R11
  numeric.go:19		0x59dc38		4d31da			XORQ R11, R10
  numeric.go:19		0x59dc3b		4d89dc			MOVQ R11, R12
  numeric.go:19		0x59dc3e		4983f301		XORQ $0x1, R11
  main.ms:140		0x59dc42		90			NOPL
  numeric.go:14		0x59dc43		90			NOPL
  numeric.go:19		0x59dc44		4d85da			TESTQ R11, R10
  numeric.go:19		0x59dc47		7d89			JGE 0x59dbd2
  numeric.go:18		0x59dc49		4c89642430		MOVQ R12, 0x30(SP)
  numeric.go:20		0x59dc4e		488b05fb950d00		MOVQ 0xd95fb(IP), AX
  numeric.go:20		0x59dc55		488d15f4950d00		LEAQ 0xd95f4(IP), DX
  numeric.go:20		0x59dc5c		ffd0			CALL AX
  main.ms:143		0x59dc5e		488b442450		MOVQ 0x50(SP), AX
  exec.go:97		0x59dc63		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:143		0x59dc68		488b5c2440		MOVQ 0x40(SP), BX
  main.ms:139		0x59dc6d		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:14		0x59dc72		4c8b642430		MOVQ 0x30(SP), R12
  numeric.go:20		0x59dc77		e956ffffff		JMP 0x59dbd2
  main.ms:143		0x59dc7c		bf40420f00		MOVL $0xf4240, DI
  main.ms:143		0x59dc81		4889c6			MOVQ AX, SI
  main.ms:143		0x59dc84		4989d8			MOVQ BX, R8
  main.ms:143		0x59dc87		4889c8			MOVQ CX, AX
  main.ms:143		0x59dc8a		488d1d5e270c00		LEAQ 0xc275e(IP), BX
  main.ms:143		0x59dc91		b90b000000		MOVL $0xb, CX
  main.ms:143		0x59dc96		e8a5f1ffff		CALL main.report(SB)
  main.ms:144		0x59dc9b		488b442448		MOVQ 0x48(SP), AX
  main.ms:144		0x59dca0		4883c458		ADDQ $0x58, SP
  main.ms:144		0x59dca4		5d			POPQ BP
  main.ms:144		0x59dca5		c3			RET
  exec.go:98		0x59dca6		488d0593880600		LEAQ 0x68893(IP), AX
  exec.go:98		0x59dcad		488d1dcce02f00		LEAQ 0x2fe0cc(IP), BX
  exec.go:98		0x59dcb4		e82770edff		CALL runtime.gopanic(SB)
  exec.go:98		0x59dcb9		90			NOPL
  generated.go:1	0x59dcba		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59dcbf		90			NOPL
  generated.go:1	0x59dcc0		e87bcbedff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59dcc5		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59dcca		e9b1feffff		JMP main.bench_method(SB)

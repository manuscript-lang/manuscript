TEXT main.bench_try(SB) generated.go
  generated.go:1	0x59dd00		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59dd04		0f8650010000		JBE 0x59de5a
  generated.go:1	0x59dd0a		55			PUSHQ BP
  generated.go:1	0x59dd0b		4889e5			MOVQ SP, BP
  generated.go:1	0x59dd0e		4883ec60		SUBQ $0x60, SP
  main.ms:151		0x59dd12		4889442470		MOVQ AX, 0x70(SP)
  main.ms:147		0x59dd17		90			NOPL
  host.go:167		0x59dd18		e8e34bffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59dd1d		488b8898000000		MOVQ 0x98(AX), CX
  main.ms:147		0x59dd24		488b4918		MOVQ 0x18(CX), CX
  host.go:167		0x59dd28		488b80a0000000		MOVQ 0xa0(AX), AX
  main.ms:147		0x59dd2f		488b5c2470		MOVQ 0x70(SP), BX
  main.ms:147		0x59dd34		ffd1			CALL CX
  main.ms:147		0x59dd36		4889442458		MOVQ AX, 0x58(SP)
  main.ms:147		0x59dd3b		48895c2450		MOVQ BX, 0x50(SP)
  main.ms:151		0x59dd40		488b4c2470		MOVQ 0x70(SP), CX
  main.ms:151		0x59dd45		31d2			XORL DX, DX
  main.ms:151		0x59dd47		31f6			XORL SI, SI
  main.ms:151		0x59dd49		eb06			JMP 0x59dd51
  main.ms:151		0x59dd4b		4c89ca			MOVQ R9, DX
  main.ms:155		0x59dd4e		4c89de			MOVQ R11, SI
  main.ms:155		0x59dd51		4889742430		MOVQ SI, 0x30(SP)
  main.ms:155		0x59dd56		660f1f840000000000	NOPW 0(AX)(AX*1)
  main.ms:155		0x59dd5f		90			NOPL
  main.ms:151		0x59dd60		4881fa40420f00		CMPQ DX, $0xf4240
  main.ms:151		0x59dd67		0f8daf000000		JGE 0x59de1c
  main.ms:151		0x59dd6d		4c8d4a01		LEAQ 0x1(DX), R9
  main.ms:151		0x59dd71		4c894c2438		MOVQ R9, 0x38(SP)
  main.ms:151		0x59dd76		49f7c13f000000		TESTQ $0x3f, R9
  main.ms:151		0x59dd7d		7548			JNE 0x59ddc7
  main.ms:151		0x59dd7f		90			NOPL
  exec.go:97		0x59dd80		4885c9			TESTQ CX, CX
  exec.go:97		0x59dd83		7442			JE 0x59ddc7
  main.ms:151		0x59dd85		4889542440		MOVQ DX, 0x40(SP)
  exec.go:97		0x59dd8a		488b11			MOVQ 0(CX), DX
  exec.go:97		0x59dd8d		488b4108		MOVQ 0x8(CX), AX
  exec.go:93		0x59dd91		488b4a28		MOVQ 0x28(DX), CX
  exec.go:93		0x59dd95		ffd1			CALL CX
  exec.go:93		0x59dd97		660f1f840000000000	NOPW 0(AX)(AX*1)
  exec.go:93		0x59dda0		4885c0			TESTQ AX, AX
  exec.go:97		0x59dda3		0f859d000000		JNE 0x59de46
  main.ms:159		0x59dda9		488b442458		MOVQ 0x58(SP), AX
  exec.go:97		0x59ddae		488b4c2470		MOVQ 0x70(SP), CX
  numeric.go:18		0x59ddb3		488b542440		MOVQ 0x40(SP), DX
  main.ms:159		0x59ddb8		488b5c2450		MOVQ 0x50(SP), BX
  numeric.go:18		0x59ddbd		488b742430		MOVQ 0x30(SP), SI
  numeric.go:19		0x59ddc2		4c8b4c2438		MOVQ 0x38(SP), R9
  numeric.go:18		0x59ddc7		4c8d1432		LEAQ 0(DX)(SI*1), R10
  numeric.go:18		0x59ddcb		4d8d5201		LEAQ 0x1(R10), R10
  numeric.go:19		0x59ddcf		4c31d6			XORQ R10, SI
  numeric.go:19		0x59ddd2		4d89d3			MOVQ R10, R11
  numeric.go:19		0x59ddd5		4d31ca			XORQ R9, R10
  main.ms:152		0x59ddd8		90			NOPL
  main.ms:153		0x59ddd9		90			NOPL
  main.ms:47		0x59ddda		90			NOPL
  numeric.go:14		0x59dddb		90			NOPL
  numeric.go:14		0x59dddc		0f1f4000		NOPL 0(AX)
  numeric.go:19		0x59dde0		4c85d6			TESTQ R10, SI
  numeric.go:19		0x59dde3		0f8d62ffffff		JGE 0x59dd4b
  numeric.go:18		0x59dde9		4c895c2448		MOVQ R11, 0x48(SP)
  numeric.go:20		0x59ddee		488b055b940d00		MOVQ 0xd945b(IP), AX
  numeric.go:20		0x59ddf5		488d1554940d00		LEAQ 0xd9454(IP), DX
  numeric.go:20		0x59ddfc		ffd0			CALL AX
  main.ms:159		0x59ddfe		488b442458		MOVQ 0x58(SP), AX
  exec.go:97		0x59de03		488b4c2470		MOVQ 0x70(SP), CX
  main.ms:159		0x59de08		488b5c2450		MOVQ 0x50(SP), BX
  main.ms:151		0x59de0d		4c8b4c2438		MOVQ 0x38(SP), R9
  main.ms:155		0x59de12		4c8b5c2448		MOVQ 0x48(SP), R11
  numeric.go:20		0x59de17		e92fffffff		JMP 0x59dd4b
  main.ms:159		0x59de1c		bf40420f00		MOVL $0xf4240, DI
  main.ms:159		0x59de21		4889c6			MOVQ AX, SI
  main.ms:159		0x59de24		4989d8			MOVQ BX, R8
  main.ms:159		0x59de27		4889c8			MOVQ CX, AX
  main.ms:159		0x59de2a		488d1ddcda0b00		LEAQ 0xbdadc(IP), BX
  main.ms:159		0x59de31		b903000000		MOVL $0x3, CX
  main.ms:159		0x59de36		e885f0ffff		CALL main.report(SB)
  main.ms:160		0x59de3b		488b442430		MOVQ 0x30(SP), AX
  main.ms:160		0x59de40		4883c460		ADDQ $0x60, SP
  main.ms:160		0x59de44		5d			POPQ BP
  main.ms:160		0x59de45		c3			RET
  exec.go:98		0x59de46		488d05f3860600		LEAQ 0x686f3(IP), AX
  exec.go:98		0x59de4d		488d1d2cdf2f00		LEAQ runtime.zerobase(SB), BX
  exec.go:98		0x59de54		e8876eedff		CALL runtime.gopanic(SB)
  exec.go:98		0x59de59		90			NOPL
  generated.go:1	0x59de5a		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59de5f		90			NOPL
  generated.go:1	0x59de60		e8dbc9edff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59de65		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59de6a		e991feffff		JMP main.bench_try(SB)

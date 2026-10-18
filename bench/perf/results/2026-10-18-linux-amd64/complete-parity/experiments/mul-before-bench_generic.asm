TEXT main.bench_generic(SB) generated.go
  generated.go:1	0x59da80		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59da84		0f86e2000000		JBE 0x59db6c
  generated.go:1	0x59da8a		55			PUSHQ BP
  generated.go:1	0x59da8b		4889e5			MOVQ SP, BP
  generated.go:1	0x59da8e		4883ec58		SUBQ $0x58, SP
  main.ms:127		0x59da92		4889442468		MOVQ AX, 0x68(SP)
  main.ms:123		0x59da97		90			NOPL
  host.go:167		0x59da98		e8634effff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59da9d		488b8898000000		MOVQ 0x98(AX), CX
  main.ms:123		0x59daa4		488b4918		MOVQ 0x18(CX), CX
  host.go:167		0x59daa8		488b80a0000000		MOVQ 0xa0(AX), AX
  main.ms:123		0x59daaf		488b5c2468		MOVQ 0x68(SP), BX
  main.ms:123		0x59dab4		ffd1			CALL CX
  main.ms:123		0x59dab6		4889442450		MOVQ AX, 0x50(SP)
  main.ms:123		0x59dabb		48895c2448		MOVQ BX, 0x48(SP)
  main.ms:127		0x59dac0		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:127		0x59dac5		31d2			XORL DX, DX
  main.ms:127		0x59dac7		31f6			XORL SI, SI
  main.ms:127		0x59dac9		eb06			JMP 0x59dad1
  main.ms:128		0x59dacb		4801d6			ADDQ DX, SI
  main.ms:127		0x59dace		4c89ca			MOVQ R9, DX
  main.ms:128		0x59dad1		4889742438		MOVQ SI, 0x38(SP)
  main.ms:127		0x59dad6		4881fa40420f00		CMPQ DX, $0xf4240
  main.ms:127		0x59dadd		7d4f			JGE 0x59db2e
  main.ms:127		0x59dadf		4c8d4a01		LEAQ 0x1(DX), R9
  main.ms:127		0x59dae3		49f7c13f000000		TESTQ $0x3f, R9
  main.ms:127		0x59daea		75df			JNE 0x59dacb
  main.ms:127		0x59daec		90			NOPL
  exec.go:97		0x59daed		4885c9			TESTQ CX, CX
  exec.go:97		0x59daf0		74d9			JE 0x59dacb
  main.ms:127		0x59daf2		4889542430		MOVQ DX, 0x30(SP)
  main.ms:127		0x59daf7		4c894c2440		MOVQ R9, 0x40(SP)
  exec.go:97		0x59dafc		488b11			MOVQ 0(CX), DX
  exec.go:97		0x59daff		488b4108		MOVQ 0x8(CX), AX
  exec.go:93		0x59db03		488b4a28		MOVQ 0x28(DX), CX
  exec.go:93		0x59db07		ffd1			CALL CX
  exec.go:93		0x59db09		4885c0			TESTQ AX, AX
  exec.go:97		0x59db0c		754a			JNE 0x59db58
  main.ms:131		0x59db0e		488b442450		MOVQ 0x50(SP), AX
  exec.go:97		0x59db13		488b4c2468		MOVQ 0x68(SP), CX
  main.ms:128		0x59db18		488b542430		MOVQ 0x30(SP), DX
  main.ms:131		0x59db1d		488b5c2448		MOVQ 0x48(SP), BX
  main.ms:128		0x59db22		488b742438		MOVQ 0x38(SP), SI
  main.ms:127		0x59db27		4c8b4c2440		MOVQ 0x40(SP), R9
  exec.go:97		0x59db2c		eb9d			JMP 0x59dacb
  main.ms:131		0x59db2e		bf40420f00		MOVL $0xf4240, DI
  main.ms:131		0x59db33		4889c6			MOVQ AX, SI
  main.ms:131		0x59db36		4989d8			MOVQ BX, R8
  main.ms:131		0x59db39		4889c8			MOVQ CX, AX
  main.ms:131		0x59db3c		488d1d4a2f0c00		LEAQ 0xc2f4a(IP), BX
  main.ms:131		0x59db43		b90c000000		MOVL $0xc, CX
  main.ms:131		0x59db48		e873f3ffff		CALL main.report(SB)
  main.ms:132		0x59db4d		488b442438		MOVQ 0x38(SP), AX
  main.ms:132		0x59db52		4883c458		ADDQ $0x58, SP
  main.ms:132		0x59db56		5d			POPQ BP
  main.ms:132		0x59db57		c3			RET
  exec.go:98		0x59db58		488d05e1890600		LEAQ 0x689e1(IP), AX
  exec.go:98		0x59db5f		488d1d1ae22f00		LEAQ runtime.zerobase(SB), BX
  exec.go:98		0x59db66		e87571edff		CALL runtime.gopanic(SB)
  exec.go:98		0x59db6b		90			NOPL
  generated.go:1	0x59db6c		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59db71		e8caccedff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59db76		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59db7b		0f1f440000		NOPL 0(AX)(AX*1)
  generated.go:1	0x59db80		e9fbfeffff		JMP main.bench_generic(SB)

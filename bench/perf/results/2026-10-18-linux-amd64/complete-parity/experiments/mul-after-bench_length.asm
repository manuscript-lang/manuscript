TEXT main.bench_length(SB) generated.go
  generated.go:1	0x59e0e0		4c8d6424f0			LEAQ -0x10(SP), R12
  generated.go:1	0x59e0e5		4d3b6610			CMPQ R12, 0x10(R14)
  generated.go:1	0x59e0e9		0f86d7010000			JBE 0x59e2c6
  generated.go:1	0x59e0ef		55				PUSHQ BP
  generated.go:1	0x59e0f0		4889e5				MOVQ SP, BP
  generated.go:1	0x59e0f3		4881ec88000000			SUBQ $0x88, SP
  main.ms:179		0x59e0fa		4889842498000000		MOVQ AX, 0x98(SP)
  main.ms:176		0x59e102		440f117c2478			MOVUPS X15, 0x78(SP)
  main.ms:176		0x59e108		48c784248000000000000000	MOVQ $0x0, 0x80(SP)
  main.ms:176		0x59e114		488d1565dc2f00			LEAQ 0x2fdc65(IP), DX
  main.ms:176		0x59e11b		4889542470			MOVQ DX, 0x70(SP)
  main.ms:176		0x59e120		31c9				XORL CX, CX
  main.ms:179		0x59e122		eb0d				JMP 0x59e131
  list_ops.go:522	0x59e124		48895c2478			MOVQ BX, 0x78(SP)
  list_ops.go:522	0x59e129		49894cd9f8			MOVQ CX, -0x8(R9)(BX*8)
  main.ms:179		0x59e12e		4889d1				MOVQ DX, CX
  main.ms:179		0x59e131		4883f964			CMPQ CX, $0x64
  main.ms:179		0x59e135		0f8d9e000000			JGE 0x59e1d9
  main.ms:179		0x59e13b		48894c2448			MOVQ CX, 0x48(SP)
  main.ms:179		0x59e140		488d5101			LEAQ 0x1(CX), DX
  main.ms:179		0x59e144		4889542460			MOVQ DX, 0x60(SP)
  main.ms:179		0x59e149		48f7c23f000000			TESTQ $0x3f, DX
  main.ms:179		0x59e150		752e				JNE 0x59e180
  main.ms:179		0x59e152		90				NOPL
  exec.go:97		0x59e153		4885c0				TESTQ AX, AX
  exec.go:97		0x59e156		7428				JE 0x59e180
  exec.go:97		0x59e158		488b08				MOVQ 0(AX), CX
  exec.go:97		0x59e15b		488b4008			MOVQ 0x8(AX), AX
  exec.go:93		0x59e15f		488b4928			MOVQ 0x28(CX), CX
  exec.go:93		0x59e163		ffd1				CALL CX
  exec.go:93		0x59e165		4885c0				TESTQ AX, AX
  exec.go:97		0x59e168		0f8542010000			JNE 0x59e2b0
  exec.go:97		0x59e16e		488b842498000000		MOVQ 0x98(SP), AX
  list_ops.go:522	0x59e176		488b4c2448			MOVQ 0x48(SP), CX
  main.ms:179		0x59e17b		488b542460			MOVQ 0x60(SP), DX
  list_ops.go:522	0x59e180		4c8b842480000000		MOVQ 0x80(SP), R8
  list_ops.go:522	0x59e188		488b5c2478			MOVQ 0x78(SP), BX
  list_ops.go:522	0x59e18d		48ffc3				INCQ BX
  main.ms:180		0x59e190		90				NOPL
  list_ops.go:522	0x59e191		4c8b4c2470			MOVQ 0x70(SP), R9
  list_ops.go:522	0x59e196		4939d8				CMPQ R8, BX
  list_ops.go:522	0x59e199		7389				JAE 0x59e124
  list_ops.go:522	0x59e19b		488d35be560500			LEAQ 0x556be(IP), SI
  list_ops.go:522	0x59e1a2		4c89c8				MOVQ R9, AX
  list_ops.go:522	0x59e1a5		4c89c1				MOVQ R8, CX
  list_ops.go:522	0x59e1a8		bf01000000			MOVL $0x1, DI
  list_ops.go:522	0x59e1ad		e86e8eedff			CALL runtime.growslice(SB)
  list_ops.go:522	0x59e1b2		48898c2480000000		MOVQ CX, 0x80(SP)
  list_ops.go:522	0x59e1ba		4889442470			MOVQ AX, 0x70(SP)
  list_ops.go:522	0x59e1bf		488b4c2448			MOVQ 0x48(SP), CX
  main.ms:179		0x59e1c4		488b542460			MOVQ 0x60(SP), DX
  list_ops.go:522	0x59e1c9		4989c1				MOVQ AX, R9
  exec.go:97		0x59e1cc		488b842498000000		MOVQ 0x98(SP), AX
  list_ops.go:522	0x59e1d4		e94bffffff			JMP 0x59e124
  main.ms:183		0x59e1d9		90				NOPL
  host.go:167		0x59e1da		e82147ffff			CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59e1df		488b8898000000			MOVQ 0x98(AX), CX
  main.ms:183		0x59e1e6		488b4918			MOVQ 0x18(CX), CX
  host.go:167		0x59e1ea		488b80a0000000			MOVQ 0xa0(AX), AX
  main.ms:183		0x59e1f1		488b9c2498000000		MOVQ 0x98(SP), BX
  main.ms:183		0x59e1f9		ffd1				CALL CX
  main.ms:183		0x59e1fb		4889442468			MOVQ AX, 0x68(SP)
  main.ms:183		0x59e200		48895c2458			MOVQ BX, 0x58(SP)
  main.ms:187		0x59e205		488b8c2498000000		MOVQ 0x98(SP), CX
  main.ms:187		0x59e20d		31d2				XORL DX, DX
  main.ms:187		0x59e20f		31f6				XORL SI, SI
  main.ms:187		0x59e211		eb04				JMP 0x59e217
  main.ms:188		0x59e213		4883c664			ADDQ $0x64, SI
  main.ms:188		0x59e217		4889742440			MOVQ SI, 0x40(SP)
  main.ms:188		0x59e21c		0f1f4000			NOPL 0(AX)
  main.ms:187		0x59e220		4881fa40420f00			CMPQ DX, $0xf4240
  main.ms:187		0x59e227		7d47				JGE 0x59e270
  main.ms:187		0x59e229		48ffc2				INCQ DX
  main.ms:187		0x59e22c		48f7c23f000000			TESTQ $0x3f, DX
  main.ms:187		0x59e233		75de				JNE 0x59e213
  main.ms:187		0x59e235		90				NOPL
  exec.go:97		0x59e236		4885c9				TESTQ CX, CX
  exec.go:97		0x59e239		74d8				JE 0x59e213
  main.ms:187		0x59e23b		4889542450			MOVQ DX, 0x50(SP)
  exec.go:97		0x59e240		488b11				MOVQ 0(CX), DX
  exec.go:97		0x59e243		488b4108			MOVQ 0x8(CX), AX
  exec.go:93		0x59e247		488b4a28			MOVQ 0x28(DX), CX
  exec.go:93		0x59e24b		ffd1				CALL CX
  exec.go:93		0x59e24d		4885c0				TESTQ AX, AX
  exec.go:97		0x59e250		754b				JNE 0x59e29d
  main.ms:191		0x59e252		488b442468			MOVQ 0x68(SP), AX
  exec.go:97		0x59e257		488b8c2498000000		MOVQ 0x98(SP), CX
  main.ms:187		0x59e25f		488b542450			MOVQ 0x50(SP), DX
  main.ms:191		0x59e264		488b5c2458			MOVQ 0x58(SP), BX
  main.ms:188		0x59e269		488b742440			MOVQ 0x40(SP), SI
  exec.go:97		0x59e26e		eba3				JMP 0x59e213
  main.ms:191		0x59e270		bf40420f00			MOVL $0xf4240, DI
  main.ms:191		0x59e275		4889c6				MOVQ AX, SI
  main.ms:191		0x59e278		4989d8				MOVQ BX, R8
  main.ms:191		0x59e27b		4889c8				MOVQ CX, AX
  main.ms:191		0x59e27e		488d1db4350c00			LEAQ 0xc35b4(IP), BX
  main.ms:191		0x59e285		b90e000000			MOVL $0xe, CX
  main.ms:191		0x59e28a		e8b1ebffff			CALL main.report(SB)
  main.ms:192		0x59e28f		488b442440			MOVQ 0x40(SP), AX
  main.ms:192		0x59e294		4881c488000000			ADDQ $0x88, SP
  main.ms:192		0x59e29b		5d				POPQ BP
  main.ms:192		0x59e29c		c3				RET
  exec.go:98		0x59e29d		488d059c820600			LEAQ 0x6829c(IP), AX
  exec.go:98		0x59e2a4		488d1dd5da2f00			LEAQ 0x2fdad5(IP), BX
  exec.go:98		0x59e2ab		e8306aedff			CALL runtime.gopanic(SB)
  exec.go:98		0x59e2b0		488d0589820600			LEAQ 0x68289(IP), AX
  exec.go:98		0x59e2b7		488d1dc2da2f00			LEAQ 0x2fdac2(IP), BX
  exec.go:98		0x59e2be		6690				NOPW
  exec.go:98		0x59e2c0		e81b6aedff			CALL runtime.gopanic(SB)
  exec.go:98		0x59e2c5		90				NOPL
  generated.go:1	0x59e2c6		4889442408			MOVQ AX, 0x8(SP)
  generated.go:1	0x59e2cb		e870c5edff			CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59e2d0		488b442408			MOVQ 0x8(SP), AX
  generated.go:1	0x59e2d5		e906feffff			JMP main.bench_length(SB)

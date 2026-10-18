TEXT main.bench_length(SB) generated.go
  generated.go:1	0x59e100		4c8d6424f0			LEAQ -0x10(SP), R12
  generated.go:1	0x59e105		4d3b6610			CMPQ R12, 0x10(R14)
  generated.go:1	0x59e109		0f86d7010000			JBE 0x59e2e6
  generated.go:1	0x59e10f		55				PUSHQ BP
  generated.go:1	0x59e110		4889e5				MOVQ SP, BP
  generated.go:1	0x59e113		4881ec88000000			SUBQ $0x88, SP
  main.ms:179		0x59e11a		4889842498000000		MOVQ AX, 0x98(SP)
  main.ms:176		0x59e122		440f117c2478			MOVUPS X15, 0x78(SP)
  main.ms:176		0x59e128		48c784248000000000000000	MOVQ $0x0, 0x80(SP)
  main.ms:176		0x59e134		488d1545dc2f00			LEAQ runtime.zerobase(SB), DX
  main.ms:176		0x59e13b		4889542470			MOVQ DX, 0x70(SP)
  main.ms:176		0x59e140		31c9				XORL CX, CX
  main.ms:179		0x59e142		eb0d				JMP 0x59e151
  list_ops.go:522	0x59e144		48895c2478			MOVQ BX, 0x78(SP)
  list_ops.go:522	0x59e149		49894cd9f8			MOVQ CX, -0x8(R9)(BX*8)
  main.ms:179		0x59e14e		4889d1				MOVQ DX, CX
  main.ms:179		0x59e151		4883f964			CMPQ CX, $0x64
  main.ms:179		0x59e155		0f8d9e000000			JGE 0x59e1f9
  main.ms:179		0x59e15b		48894c2448			MOVQ CX, 0x48(SP)
  main.ms:179		0x59e160		488d5101			LEAQ 0x1(CX), DX
  main.ms:179		0x59e164		4889542460			MOVQ DX, 0x60(SP)
  main.ms:179		0x59e169		48f7c23f000000			TESTQ $0x3f, DX
  main.ms:179		0x59e170		752e				JNE 0x59e1a0
  main.ms:179		0x59e172		90				NOPL
  exec.go:97		0x59e173		4885c0				TESTQ AX, AX
  exec.go:97		0x59e176		7428				JE 0x59e1a0
  exec.go:97		0x59e178		488b08				MOVQ 0(AX), CX
  exec.go:97		0x59e17b		488b4008			MOVQ 0x8(AX), AX
  exec.go:93		0x59e17f		488b4928			MOVQ 0x28(CX), CX
  exec.go:93		0x59e183		ffd1				CALL CX
  exec.go:93		0x59e185		4885c0				TESTQ AX, AX
  exec.go:97		0x59e188		0f8542010000			JNE 0x59e2d0
  exec.go:97		0x59e18e		488b842498000000		MOVQ 0x98(SP), AX
  list_ops.go:522	0x59e196		488b4c2448			MOVQ 0x48(SP), CX
  main.ms:179		0x59e19b		488b542460			MOVQ 0x60(SP), DX
  list_ops.go:522	0x59e1a0		4c8b842480000000		MOVQ 0x80(SP), R8
  list_ops.go:522	0x59e1a8		488b5c2478			MOVQ 0x78(SP), BX
  list_ops.go:522	0x59e1ad		48ffc3				INCQ BX
  main.ms:180		0x59e1b0		90				NOPL
  list_ops.go:522	0x59e1b1		4c8b4c2470			MOVQ 0x70(SP), R9
  list_ops.go:522	0x59e1b6		4939d8				CMPQ R8, BX
  list_ops.go:522	0x59e1b9		7389				JAE 0x59e144
  list_ops.go:522	0x59e1bb		488d359e560500			LEAQ 0x5569e(IP), SI
  list_ops.go:522	0x59e1c2		4c89c8				MOVQ R9, AX
  list_ops.go:522	0x59e1c5		4c89c1				MOVQ R8, CX
  list_ops.go:522	0x59e1c8		bf01000000			MOVL $0x1, DI
  list_ops.go:522	0x59e1cd		e84e8eedff			CALL runtime.growslice(SB)
  list_ops.go:522	0x59e1d2		48898c2480000000		MOVQ CX, 0x80(SP)
  list_ops.go:522	0x59e1da		4889442470			MOVQ AX, 0x70(SP)
  list_ops.go:522	0x59e1df		488b4c2448			MOVQ 0x48(SP), CX
  main.ms:179		0x59e1e4		488b542460			MOVQ 0x60(SP), DX
  list_ops.go:522	0x59e1e9		4989c1				MOVQ AX, R9
  exec.go:97		0x59e1ec		488b842498000000		MOVQ 0x98(SP), AX
  list_ops.go:522	0x59e1f4		e94bffffff			JMP 0x59e144
  main.ms:183		0x59e1f9		90				NOPL
  host.go:167		0x59e1fa		e80147ffff			CALL github.com/manuscript-lang/manuscript/pkg/runtime.hostRoots(SB)
  host.go:167		0x59e1ff		488b8898000000			MOVQ 0x98(AX), CX
  main.ms:183		0x59e206		488b4918			MOVQ 0x18(CX), CX
  host.go:167		0x59e20a		488b80a0000000			MOVQ 0xa0(AX), AX
  main.ms:183		0x59e211		488b9c2498000000		MOVQ 0x98(SP), BX
  main.ms:183		0x59e219		ffd1				CALL CX
  main.ms:183		0x59e21b		4889442468			MOVQ AX, 0x68(SP)
  main.ms:183		0x59e220		48895c2458			MOVQ BX, 0x58(SP)
  main.ms:187		0x59e225		488b8c2498000000		MOVQ 0x98(SP), CX
  main.ms:187		0x59e22d		31d2				XORL DX, DX
  main.ms:187		0x59e22f		31f6				XORL SI, SI
  main.ms:187		0x59e231		eb04				JMP 0x59e237
  main.ms:188		0x59e233		4883c664			ADDQ $0x64, SI
  main.ms:188		0x59e237		4889742440			MOVQ SI, 0x40(SP)
  main.ms:188		0x59e23c		0f1f4000			NOPL 0(AX)
  main.ms:187		0x59e240		4881fa40420f00			CMPQ DX, $0xf4240
  main.ms:187		0x59e247		7d47				JGE 0x59e290
  main.ms:187		0x59e249		48ffc2				INCQ DX
  main.ms:187		0x59e24c		48f7c23f000000			TESTQ $0x3f, DX
  main.ms:187		0x59e253		75de				JNE 0x59e233
  main.ms:187		0x59e255		90				NOPL
  exec.go:97		0x59e256		4885c9				TESTQ CX, CX
  exec.go:97		0x59e259		74d8				JE 0x59e233
  main.ms:187		0x59e25b		4889542450			MOVQ DX, 0x50(SP)
  exec.go:97		0x59e260		488b11				MOVQ 0(CX), DX
  exec.go:97		0x59e263		488b4108			MOVQ 0x8(CX), AX
  exec.go:93		0x59e267		488b4a28			MOVQ 0x28(DX), CX
  exec.go:93		0x59e26b		ffd1				CALL CX
  exec.go:93		0x59e26d		4885c0				TESTQ AX, AX
  exec.go:97		0x59e270		754b				JNE 0x59e2bd
  main.ms:191		0x59e272		488b442468			MOVQ 0x68(SP), AX
  exec.go:97		0x59e277		488b8c2498000000		MOVQ 0x98(SP), CX
  main.ms:187		0x59e27f		488b542450			MOVQ 0x50(SP), DX
  main.ms:191		0x59e284		488b5c2458			MOVQ 0x58(SP), BX
  main.ms:188		0x59e289		488b742440			MOVQ 0x40(SP), SI
  exec.go:97		0x59e28e		eba3				JMP 0x59e233
  main.ms:191		0x59e290		bf40420f00			MOVL $0xf4240, DI
  main.ms:191		0x59e295		4889c6				MOVQ AX, SI
  main.ms:191		0x59e298		4989d8				MOVQ BX, R8
  main.ms:191		0x59e29b		4889c8				MOVQ CX, AX
  main.ms:191		0x59e29e		488d1d94350c00			LEAQ 0xc3594(IP), BX
  main.ms:191		0x59e2a5		b90e000000			MOVL $0xe, CX
  main.ms:191		0x59e2aa		e811ecffff			CALL main.report(SB)
  main.ms:192		0x59e2af		488b442440			MOVQ 0x40(SP), AX
  main.ms:192		0x59e2b4		4881c488000000			ADDQ $0x88, SP
  main.ms:192		0x59e2bb		5d				POPQ BP
  main.ms:192		0x59e2bc		c3				RET
  exec.go:98		0x59e2bd		488d057c820600			LEAQ 0x6827c(IP), AX
  exec.go:98		0x59e2c4		488d1db5da2f00			LEAQ runtime.zerobase(SB), BX
  exec.go:98		0x59e2cb		e8106aedff			CALL runtime.gopanic(SB)
  exec.go:98		0x59e2d0		488d0569820600			LEAQ 0x68269(IP), AX
  exec.go:98		0x59e2d7		488d1da2da2f00			LEAQ runtime.zerobase(SB), BX
  exec.go:98		0x59e2de		6690				NOPW
  exec.go:98		0x59e2e0		e8fb69edff			CALL runtime.gopanic(SB)
  exec.go:98		0x59e2e5		90				NOPL
  generated.go:1	0x59e2e6		4889442408			MOVQ AX, 0x8(SP)
  generated.go:1	0x59e2eb		e850c5edff			CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59e2f0		488b442408			MOVQ 0x8(SP), AX
  generated.go:1	0x59e2f5		e906feffff			JMP main.bench_length(SB)

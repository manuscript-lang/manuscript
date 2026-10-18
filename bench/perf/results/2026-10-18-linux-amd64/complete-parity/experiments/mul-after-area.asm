TEXT main.area(SB) generated.go
  generated.go:1	0x59d140		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59d144		0f8604010000		JBE 0x59d24e
  generated.go:1	0x59d14a		55			PUSHQ BP
  generated.go:1	0x59d14b		4889e5			MOVQ SP, BP
  generated.go:1	0x59d14e		4883ec08		SUBQ $0x8, SP
  generated.go:1	0x59d152		48895c2420		MOVQ BX, 0x20(SP)
  generated.go:1	0x59d157		48894c2428		MOVQ CX, 0x28(SP)
  generated.go:1	0x59d15c		0f1f4000		NOPL 0(AX)
  main.ms:53		0x59d160		4885db			TESTQ BX, BX
  main.ms:53		0x59d163		0f84da000000		JE 0x59d243
  main.ms:53		0x59d169		8b7310			MOVL 0x10(BX), SI
  main.ms:53		0x59d16c		81fe46d05b3a		CMPL SI, $0x3a5bd046
  main.ms:53		0x59d172		751d			JNE 0x59d191
  main.ms:58		0x59d174		488d15057d1100		LEAQ go:itab.main.Shape_Tri,main.Shape(SB), DX
  main.ms:58		0x59d17b		0f1f440000		NOPL 0(AX)(AX*1)
  main.ms:58		0x59d180		4839d3			CMPQ BX, DX
  main.ms:58		0x59d183		0f85b6000000		JNE 0x59d23f
  main.ms:58		0x59d189		488b09			MOVQ 0(CX), CX
  main.ms:53		0x59d18c		e9b4000000		JMP 0x59d245
  main.ms:53		0x59d191		81fe2ff393c2		CMPL SI, $-0x3d6c0cd1
  main.ms:53		0x59d197		7552			JNE 0x59d1eb
  main.ms:56		0x59d199		488d35c07c1100		LEAQ go:itab.main.Shape_Square,main.Shape(SB), SI
  main.ms:56		0x59d1a0		4839f3			CMPQ BX, SI
  main.ms:56		0x59d1a3		0f8596000000		JNE 0x59d23f
  main.ms:56		0x59d1a9		488b01			MOVQ 0(CX), AX
  main.ms:56		0x59d1ac		4889c1			MOVQ AX, CX
  numeric.go:44		0x59d1af		48f7e0			MULQ AX
  numeric.go:45		0x59d1b2		4889cb			MOVQ CX, BX
  numeric.go:45		0x59d1b5		48c1f93f		SARQ $0x3f, CX
  numeric.go:45		0x59d1b9		4821cb			ANDQ CX, BX
  numeric.go:45		0x59d1bc		488d0c1b		LEAQ 0(BX)(BX*1), CX
  numeric.go:45		0x59d1c0		4829ca			SUBQ CX, DX
  numeric.go:46		0x59d1c3		4889c1			MOVQ AX, CX
  numeric.go:46		0x59d1c6		48c1f83f		SARQ $0x3f, AX
  main.ms:57		0x59d1ca		90			NOPL
  numeric.go:33		0x59d1cb		90			NOPL
  numeric.go:46		0x59d1cc		4839d0			CMPQ AX, DX
  numeric.go:46		0x59d1cf		7474			JE 0x59d245
  numeric.go:44		0x59d1d1		48890c24		MOVQ CX, 0(SP)
  numeric.go:47		0x59d1d5		488b0574a00d00		MOVQ 0xda074(IP), AX
  numeric.go:47		0x59d1dc		488d156da00d00		LEAQ 0xda06d(IP), DX
  numeric.go:47		0x59d1e3		ffd0			CALL AX
  main.ms:61		0x59d1e5		488b0c24		MOVQ 0(SP), CX
  numeric.go:47		0x59d1e9		eb5a			JMP 0x59d245
  main.ms:53		0x59d1eb		81fe9efe6bf3		CMPL SI, $-0xc940162
  main.ms:53		0x59d1f1		754c			JNE 0x59d23f
  main.ms:54		0x59d1f3		488d35467c1100		LEAQ go:itab.main.Shape_Circle,main.Shape(SB), SI
  main.ms:54		0x59d1fa		4839f3			CMPQ BX, SI
  main.ms:54		0x59d1fd		7540			JNE 0x59d23f
  main.ms:54		0x59d1ff		488b09			MOVQ 0(CX), CX
  numeric.go:44		0x59d202		b803000000		MOVL $0x3, AX
  numeric.go:44		0x59d207		48f7e1			MULQ CX
  numeric.go:45		0x59d20a		48c1f93f		SARQ $0x3f, CX
  numeric.go:45		0x59d20e		83e103			ANDL $0x3, CX
  numeric.go:45		0x59d211		4829ca			SUBQ CX, DX
  numeric.go:46		0x59d214		4889c1			MOVQ AX, CX
  numeric.go:46		0x59d217		48c1f83f		SARQ $0x3f, AX
  main.ms:55		0x59d21b		90			NOPL
  numeric.go:33		0x59d21c		90			NOPL
  numeric.go:33		0x59d21d		0f1f00			NOPL 0(AX)
  numeric.go:46		0x59d220		4839d0			CMPQ AX, DX
  numeric.go:46		0x59d223		7420			JE 0x59d245
  numeric.go:44		0x59d225		48890c24		MOVQ CX, 0(SP)
  numeric.go:47		0x59d229		488b0520a00d00		MOVQ 0xda020(IP), AX
  numeric.go:47		0x59d230		488d1519a00d00		LEAQ 0xda019(IP), DX
  numeric.go:47		0x59d237		ffd0			CALL AX
  main.ms:61		0x59d239		488b0c24		MOVQ 0(SP), CX
  numeric.go:47		0x59d23d		eb06			JMP 0x59d245
  numeric.go:47		0x59d23f		31c9			XORL CX, CX
  main.ms:53		0x59d241		eb02			JMP 0x59d245
  main.ms:53		0x59d243		31c9			XORL CX, CX
  main.ms:61		0x59d245		4889c8			MOVQ CX, AX
  main.ms:61		0x59d248		4883c408		ADDQ $0x8, SP
  main.ms:61		0x59d24c		5d			POPQ BP
  main.ms:61		0x59d24d		c3			RET
  generated.go:1	0x59d24e		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59d253		48895c2410		MOVQ BX, 0x10(SP)
  generated.go:1	0x59d258		48894c2418		MOVQ CX, 0x18(SP)
  generated.go:1	0x59d25d		0f1f00			NOPL 0(AX)
  generated.go:1	0x59d260		e8dbd5edff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59d265		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59d26a		488b5c2410		MOVQ 0x10(SP), BX
  generated.go:1	0x59d26f		488b4c2418		MOVQ 0x18(SP), CX
  generated.go:1	0x59d274		e9c7feffff		JMP main.area(SB)

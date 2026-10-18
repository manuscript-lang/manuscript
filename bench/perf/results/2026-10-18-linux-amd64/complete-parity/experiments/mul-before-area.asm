TEXT main.area(SB) generated.go
  generated.go:1	0x59d1c0		493b6610		CMPQ SP, 0x10(R14)
  generated.go:1	0x59d1c4		0f8695000000		JBE 0x59d25f
  generated.go:1	0x59d1ca		55			PUSHQ BP
  generated.go:1	0x59d1cb		4889e5			MOVQ SP, BP
  generated.go:1	0x59d1ce		4883ec10		SUBQ $0x10, SP
  generated.go:1	0x59d1d2		48895c2428		MOVQ BX, 0x28(SP)
  generated.go:1	0x59d1d7		48894c2430		MOVQ CX, 0x30(SP)
  generated.go:1	0x59d1dc		0f1f4000		NOPL 0(AX)
  main.ms:53		0x59d1e0		4885db			TESTQ BX, BX
  main.ms:53		0x59d1e3		746f			JE 0x59d254
  main.ms:53		0x59d1e5		8b5310			MOVL 0x10(BX), DX
  main.ms:53		0x59d1e8		81fa46d05b3a		CMPL DX, $0x3a5bd046
  main.ms:53		0x59d1ee		7512			JNE 0x59d202
  main.ms:58		0x59d1f0		488d15497c1100		LEAQ go:itab.main.Shape_Tri,main.Shape(SB), DX
  main.ms:58		0x59d1f7		4839d3			CMPQ BX, DX
  main.ms:58		0x59d1fa		7554			JNE 0x59d250
  main.ms:58		0x59d1fc		488b09			MOVQ 0(CX), CX
  main.ms:58		0x59d1ff		90			NOPL
  main.ms:53		0x59d200		eb54			JMP 0x59d256
  main.ms:53		0x59d202		81fa2ff393c2		CMPL DX, $-0x3d6c0cd1
  main.ms:53		0x59d208		7520			JNE 0x59d22a
  main.ms:56		0x59d20a		488d150f7c1100		LEAQ go:itab.main.Shape_Square,main.Shape(SB), DX
  main.ms:56		0x59d211		4839d3			CMPQ BX, DX
  main.ms:56		0x59d214		753a			JNE 0x59d250
  main.ms:56		0x59d216		488b19			MOVQ 0(CX), BX
  main.ms:57		0x59d219		4889d8			MOVQ BX, AX
  main.ms:57		0x59d21c		0f1f4000		NOPL 0(AX)
  main.ms:57		0x59d220		e8bb96ffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.IntMultiply(SB)
  main.ms:61		0x59d225		4889c1			MOVQ AX, CX
  main.ms:53		0x59d228		eb2c			JMP 0x59d256
  main.ms:53		0x59d22a		81fa9efe6bf3		CMPL DX, $-0xc940162
  main.ms:53		0x59d230		751e			JNE 0x59d250
  main.ms:54		0x59d232		488d15c77b1100		LEAQ go:itab.main.Shape_Circle,main.Shape(SB), DX
  main.ms:54		0x59d239		4839d3			CMPQ BX, DX
  main.ms:54		0x59d23c		7512			JNE 0x59d250
  main.ms:54		0x59d23e		488b01			MOVQ 0(CX), AX
  main.ms:55		0x59d241		bb03000000		MOVL $0x3, BX
  main.ms:55		0x59d246		e89596ffff		CALL github.com/manuscript-lang/manuscript/pkg/runtime.IntMultiply(SB)
  main.ms:61		0x59d24b		4889c1			MOVQ AX, CX
  main.ms:53		0x59d24e		eb06			JMP 0x59d256
  main.ms:53		0x59d250		31c9			XORL CX, CX
  main.ms:53		0x59d252		eb02			JMP 0x59d256
  main.ms:53		0x59d254		31c9			XORL CX, CX
  main.ms:61		0x59d256		4889c8			MOVQ CX, AX
  main.ms:61		0x59d259		4883c410		ADDQ $0x10, SP
  main.ms:61		0x59d25d		5d			POPQ BP
  main.ms:61		0x59d25e		c3			RET
  generated.go:1	0x59d25f		4889442408		MOVQ AX, 0x8(SP)
  generated.go:1	0x59d264		48895c2410		MOVQ BX, 0x10(SP)
  generated.go:1	0x59d269		48894c2418		MOVQ CX, 0x18(SP)
  generated.go:1	0x59d26e		e8cdd5edff		CALL runtime.morestack_noctxt.abi0(SB)
  generated.go:1	0x59d273		488b442408		MOVQ 0x8(SP), AX
  generated.go:1	0x59d278		488b5c2410		MOVQ 0x10(SP), BX
  generated.go:1	0x59d27d		488b4c2418		MOVQ 0x18(SP), CX
  generated.go:1	0x59d282		e939ffffff		JMP main.area(SB)

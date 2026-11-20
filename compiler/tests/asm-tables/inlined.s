	.file	1 "t.ms"
	.text
	.globl	outer
	.type	outer,@function
outer:
	.loc	1 3 1
	nop
	.loc	1 11 2
	nop
	ret
	.size	outer, .-outer

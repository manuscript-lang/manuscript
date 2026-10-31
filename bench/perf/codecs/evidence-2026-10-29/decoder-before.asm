0000000000000000 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	41 57                	push   %r15
   6:	41 56                	push   %r14
   8:	41 55                	push   %r13
   a:	41 54                	push   %r12
   c:	53                   	push   %rbx
   d:	48 81 ec 48 01 00 00 	sub    $0x148,%rsp
  14:	48 c7 c0 ff ff ff ff 	mov    $0xffffffffffffffff,%rax
  1b:	49 83 f8 01          	cmp    $0x1,%r8
  1f:	75 08                	jne    29 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x29>
  21:	4c 89 c8             	mov    %r9,%rax
  24:	4d 85 c9             	test   %r9,%r9
  27:	78 5e                	js     87 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x87>
  29:	48 85 d2             	test   %rdx,%rdx
  2c:	74 2d                	je     5b <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x5b>
  2e:	45 31 c0             	xor    %r8d,%r8d
  31:	49 b9 00 26 00 00 01 	movabs $0x100002600,%r9
  38:	00 00 00
  3b:	eb 0b                	jmp    48 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x48>
  3d:	0f 1f 00             	nopl   (%rax)
  40:	49 ff c0             	inc    %r8
  43:	4c 39 c2             	cmp    %r8,%rdx
  46:	74 13                	je     5b <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x5b>
  48:	46 0f b6 14 06       	movzbl (%rsi,%r8,1),%r10d
  4d:	49 83 fa 20          	cmp    $0x20,%r10
  51:	77 ed                	ja     40 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40>
  53:	4d 0f a3 d1          	bt     %r10,%r9
  57:	73 e7                	jae    40 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40>
  59:	eb 6c                	jmp    c7 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xc7>
  5b:	48 85 d2             	test   %rdx,%rdx
  5e:	74 2d                	je     8d <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x8d>
  60:	4c 8d 46 ff          	lea    -0x1(%rsi),%r8
  64:	45 31 ff             	xor    %r15d,%r15d
  67:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
  6e:	00 00
  70:	41 80 3c 10 3d       	cmpb   $0x3d,(%r8,%rdx,1)
  75:	75 19                	jne    90 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x90>
  77:	49 ff c7             	inc    %r15
  7a:	49 ff c8             	dec    %r8
  7d:	4c 39 fa             	cmp    %r15,%rdx
  80:	75 ee                	jne    70 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x70>
  82:	49 89 d7             	mov    %rdx,%r15
  85:	eb 09                	jmp    90 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x90>
  87:	c6 47 08 00          	movb   $0x0,0x8(%rdi)
  8b:	eb 3e                	jmp    cb <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xcb>
  8d:	45 31 ff             	xor    %r15d,%r15d
  90:	49 83 ff 03          	cmp    $0x3,%r15
  94:	41 0f 92 c0          	setb   %r8b
  98:	f6 c2 03             	test   $0x3,%dl
  9b:	41 0f 94 c1          	sete   %r9b
  9f:	45 84 c1             	test   %r8b,%r9b
  a2:	74 23                	je     c7 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xc7>
  a4:	49 89 d6             	mov    %rdx,%r14
  a7:	49 c1 ee 02          	shr    $0x2,%r14
  ab:	4b 8d 1c 76          	lea    (%r14,%r14,2),%rbx
  af:	45 31 c0             	xor    %r8d,%r8d
  b2:	49 89 d9             	mov    %rbx,%r9
  b5:	4d 29 f9             	sub    %r15,%r9
  b8:	4d 0f 43 c1          	cmovae %r9,%r8
  bc:	49 39 c0             	cmp    %rax,%r8
  bf:	76 26                	jbe    e7 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xe7>
  c1:	c6 47 08 02          	movb   $0x2,0x8(%rdi)
  c5:	eb 04                	jmp    cb <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xcb>
  c7:	c6 47 08 01          	movb   $0x1,0x8(%rdi)
  cb:	48 c7 07 ff ff ff ff 	movq   $0xffffffffffffffff,(%rdi)
  d2:	48 89 f8             	mov    %rdi,%rax
  d5:	48 81 c4 48 01 00 00 	add    $0x148,%rsp
  dc:	5b                   	pop    %rbx
  dd:	41 5c                	pop    %r12
  df:	41 5d                	pop    %r13
  e1:	41 5e                	pop    %r14
  e3:	41 5f                	pop    %r15
  e5:	5d                   	pop    %rbp
  e6:	c3                   	ret
  e7:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # ee <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xee>
  ee:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # f5 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xf5>
  f5:	84 c9                	test   %cl,%cl
  f7:	49 0f 45 c0          	cmovne %r8,%rax
  fb:	66 0f 76 c0          	pcmpeqd %xmm0,%xmm0
  ff:	66 0f 7f 45 80       	movdqa %xmm0,-0x80(%rbp)
 104:	66 0f 7f 85 70 ff ff 	movdqa %xmm0,-0x90(%rbp)
 10b:	ff
 10c:	66 0f 7f 85 60 ff ff 	movdqa %xmm0,-0xa0(%rbp)
 113:	ff
 114:	66 0f 7f 85 50 ff ff 	movdqa %xmm0,-0xb0(%rbp)
 11b:	ff
 11c:	66 0f 7f 85 40 ff ff 	movdqa %xmm0,-0xc0(%rbp)
 123:	ff
 124:	66 0f 7f 85 30 ff ff 	movdqa %xmm0,-0xd0(%rbp)
 12b:	ff
 12c:	66 0f 7f 85 20 ff ff 	movdqa %xmm0,-0xe0(%rbp)
 133:	ff
 134:	66 0f 7f 85 10 ff ff 	movdqa %xmm0,-0xf0(%rbp)
 13b:	ff
 13c:	66 0f 7f 85 00 ff ff 	movdqa %xmm0,-0x100(%rbp)
 143:	ff
 144:	66 0f 7f 85 f0 fe ff 	movdqa %xmm0,-0x110(%rbp)
 14b:	ff
 14c:	66 0f 7f 85 e0 fe ff 	movdqa %xmm0,-0x120(%rbp)
 153:	ff
 154:	66 0f 7f 85 d0 fe ff 	movdqa %xmm0,-0x130(%rbp)
 15b:	ff
 15c:	66 0f 7f 85 c0 fe ff 	movdqa %xmm0,-0x140(%rbp)
 163:	ff
 164:	66 0f 7f 85 b0 fe ff 	movdqa %xmm0,-0x150(%rbp)
 16b:	ff
 16c:	66 0f 7f 85 a0 fe ff 	movdqa %xmm0,-0x160(%rbp)
 173:	ff
 174:	66 0f 7f 85 90 fe ff 	movdqa %xmm0,-0x170(%rbp)
 17b:	ff
 17c:	48 8d 0d 00 00 00 00 	lea    0x0(%rip),%rcx        # 183 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x183>
 183:	4c 8d 05 00 00 00 00 	lea    0x0(%rip),%r8        # 18a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x18a>
 18a:	4c 0f 45 c1          	cmovne %rcx,%r8
 18e:	49 89 c1             	mov    %rax,%r9
 191:	4d 29 c1             	sub    %r8,%r9
 194:	0f 84 9f 00 00 00    	je     239 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x239>
 19a:	49 29 c0             	sub    %rax,%r8
 19d:	44 89 c1             	mov    %r8d,%ecx
 1a0:	83 e1 03             	and    $0x3,%ecx
 1a3:	49 83 f9 fc          	cmp    $0xfffffffffffffffc,%r9
 1a7:	76 05                	jbe    1ae <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1ae>
 1a9:	45 31 c9             	xor    %r9d,%r9d
 1ac:	eb 66                	jmp    214 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x214>
 1ae:	49 83 e0 fc          	and    $0xfffffffffffffffc,%r8
 1b2:	45 31 c9             	xor    %r9d,%r9d
 1b5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
 1bc:	00 00 00 00
 1c0:	46 0f b6 14 08       	movzbl (%rax,%r9,1),%r10d
 1c5:	46 88 8c 15 90 fe ff 	mov    %r9b,-0x170(%rbp,%r10,1)
 1cc:	ff
 1cd:	46 0f b6 54 08 01    	movzbl 0x1(%rax,%r9,1),%r10d
 1d3:	45 8d 59 01          	lea    0x1(%r9),%r11d
 1d7:	46 88 9c 15 90 fe ff 	mov    %r11b,-0x170(%rbp,%r10,1)
 1de:	ff
 1df:	46 0f b6 54 08 02    	movzbl 0x2(%rax,%r9,1),%r10d
 1e5:	45 8d 59 02          	lea    0x2(%r9),%r11d
 1e9:	46 88 9c 15 90 fe ff 	mov    %r11b,-0x170(%rbp,%r10,1)
 1f0:	ff
 1f1:	46 0f b6 54 08 03    	movzbl 0x3(%rax,%r9,1),%r10d
 1f7:	45 8d 59 03          	lea    0x3(%r9),%r11d
 1fb:	46 88 9c 15 90 fe ff 	mov    %r11b,-0x170(%rbp,%r10,1)
 202:	ff
 203:	49 83 c1 04          	add    $0x4,%r9
 207:	4d 39 c8             	cmp    %r9,%r8
 20a:	75 b4                	jne    1c0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1c0>
 20c:	48 85 c9             	test   %rcx,%rcx
 20f:	74 28                	je     239 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x239>
 211:	4c 01 c8             	add    %r9,%rax
 214:	45 0f b6 c1          	movzbl %r9b,%r8d
 218:	45 31 c9             	xor    %r9d,%r9d
 21b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
 220:	47 8d 14 08          	lea    (%r8,%r9,1),%r10d
 224:	46 0f b6 1c 08       	movzbl (%rax,%r9,1),%r11d
 229:	46 88 94 1d 90 fe ff 	mov    %r10b,-0x170(%rbp,%r11,1)
 230:	ff
 231:	49 ff c1             	inc    %r9
 234:	4c 39 c9             	cmp    %r9,%rcx
 237:	75 e7                	jne    220 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x220>
 239:	48 89 7d b8          	mov    %rdi,-0x48(%rbp)
 23d:	48 85 db             	test   %rbx,%rbx
 240:	0f 88 28 02 00 00    	js     46e <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x46e>
 246:	48 85 d2             	test   %rdx,%rdx
 249:	0f 84 eb 01 00 00    	je     43a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x43a>
 24f:	4c 89 75 b0          	mov    %r14,-0x50(%rbp)
 253:	49 89 f4             	mov    %rsi,%r12
 256:	49 89 d5             	mov    %rdx,%r13
 259:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 25f <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x25f>
 25f:	41 be 01 00 00 00    	mov    $0x1,%r14d
 265:	be 01 00 00 00       	mov    $0x1,%esi
 26a:	48 89 df             	mov    %rbx,%rdi
 26d:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 273 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x273>
 273:	48 85 c0             	test   %rax,%rax
 276:	0f 84 f5 01 00 00    	je     471 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x471>
 27c:	48 89 5d c0          	mov    %rbx,-0x40(%rbp)
 280:	48 89 45 c8          	mov    %rax,-0x38(%rbp)
 284:	48 c7 45 d0 00 00 00 	movq   $0x0,-0x30(%rbp)
 28b:	00
 28c:	31 db                	xor    %ebx,%ebx
 28e:	45 31 c9             	xor    %r9d,%r9d
 291:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 295:	4c 89 e8             	mov    %r13,%rax
 298:	4c 89 e1             	mov    %r12,%rcx
 29b:	4c 8b 45 b0          	mov    -0x50(%rbp),%r8
 29f:	48 83 f8 04          	cmp    $0x4,%rax
 2a3:	ba 04 00 00 00       	mov    $0x4,%edx
 2a8:	48 0f 42 d0          	cmovb  %rax,%rdx
 2ac:	48 89 ce             	mov    %rcx,%rsi
 2af:	48 01 d1             	add    %rdx,%rcx
 2b2:	48 29 d0             	sub    %rdx,%rax
 2b5:	49 ff c1             	inc    %r9
 2b8:	4c 89 4d 98          	mov    %r9,-0x68(%rbp)
 2bc:	4d 39 c1             	cmp    %r8,%r9
 2bf:	41 be 00 00 00 00    	mov    $0x0,%r14d
 2c5:	4d 0f 44 f7          	cmove  %r15,%r14
 2c9:	41 b8 04 00 00 00    	mov    $0x4,%r8d
 2cf:	4d 29 f0             	sub    %r14,%r8
 2d2:	45 31 e4             	xor    %r12d,%r12d
 2d5:	45 31 c9             	xor    %r9d,%r9d
 2d8:	eb 31                	jmp    30b <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x30b>
 2da:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
 2e0:	46 0f b6 94 1d 90 fe 	movzbl -0x170(%rbp,%r11,1),%r10d
 2e7:	ff ff
 2e9:	41 81 fa ff 00 00 00 	cmp    $0xff,%r10d
 2f0:	0f 84 14 01 00 00    	je     40a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40a>
 2f6:	49 ff c1             	inc    %r9
 2f9:	45 89 e5             	mov    %r12d,%r13d
 2fc:	41 c1 e5 06          	shl    $0x6,%r13d
 300:	45 89 d4             	mov    %r10d,%r12d
 303:	45 09 ec             	or     %r13d,%r12d
 306:	4c 39 ca             	cmp    %r9,%rdx
 309:	74 18                	je     323 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x323>
 30b:	46 0f b6 1c 0e       	movzbl (%rsi,%r9,1),%r11d
 310:	4d 39 c1             	cmp    %r8,%r9
 313:	72 cb                	jb     2e0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2e0>
 315:	45 31 d2             	xor    %r10d,%r10d
 318:	41 83 fb 3d          	cmp    $0x3d,%r11d
 31c:	74 d8                	je     2f6 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2f6>
 31e:	e9 e7 00 00 00       	jmp    40a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40a>
 323:	49 83 fe 01          	cmp    $0x1,%r14
 327:	74 11                	je     33a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x33a>
 329:	49 83 fe 02          	cmp    $0x2,%r14
 32d:	75 14                	jne    343 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x343>
 32f:	66 45 85 e4          	test   %r12w,%r12w
 333:	74 0e                	je     343 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x343>
 335:	e9 d0 00 00 00       	jmp    40a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40a>
 33a:	45 84 e4             	test   %r12b,%r12b
 33d:	0f 85 c7 00 00 00    	jne    40a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x40a>
 343:	48 3b 5d c0          	cmp    -0x40(%rbp),%rbx
 347:	75 1e                	jne    367 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x367>
 349:	48 8d 7d c0          	lea    -0x40(%rbp),%rdi
 34d:	48 89 45 a0          	mov    %rax,-0x60(%rbp)
 351:	48 89 4d a8          	mov    %rcx,-0x58(%rbp)
 355:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 35b <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x35b>
 35b:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 35f:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 363:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 367:	44 89 ea             	mov    %r13d,%edx
 36a:	c1 ea 10             	shr    $0x10,%edx
 36d:	48 8b 75 c8          	mov    -0x38(%rbp),%rsi
 371:	88 14 1e             	mov    %dl,(%rsi,%rbx,1)
 374:	48 8d 53 01          	lea    0x1(%rbx),%rdx
 378:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
 37c:	49 83 fe 02          	cmp    $0x2,%r14
 380:	73 72                	jae    3f4 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x3f4>
 382:	48 3b 55 c0          	cmp    -0x40(%rbp),%rdx
 386:	75 1e                	jne    3a6 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x3a6>
 388:	48 8d 7d c0          	lea    -0x40(%rbp),%rdi
 38c:	48 89 45 a0          	mov    %rax,-0x60(%rbp)
 390:	48 89 4d a8          	mov    %rcx,-0x58(%rbp)
 394:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 39a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x39a>
 39a:	48 8b 4d a8          	mov    -0x58(%rbp),%rcx
 39e:	48 8b 45 a0          	mov    -0x60(%rbp),%rax
 3a2:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 3a6:	41 c1 ed 08          	shr    $0x8,%r13d
 3aa:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 3ae:	44 88 6c 1a 01       	mov    %r13b,0x1(%rdx,%rbx,1)
 3b3:	48 8d 53 02          	lea    0x2(%rbx),%rdx
 3b7:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
 3bb:	4d 85 f6             	test   %r14,%r14
 3be:	75 34                	jne    3f4 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x3f4>
 3c0:	48 3b 55 c0          	cmp    -0x40(%rbp),%rdx
 3c4:	75 1a                	jne    3e0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x3e0>
 3c6:	48 8d 7d c0          	lea    -0x40(%rbp),%rdi
 3ca:	49 89 c6             	mov    %rax,%r14
 3cd:	49 89 cd             	mov    %rcx,%r13
 3d0:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 3d6 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x3d6>
 3d6:	4c 89 e9             	mov    %r13,%rcx
 3d9:	4c 89 f0             	mov    %r14,%rax
 3dc:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 3e0:	48 8b 55 c8          	mov    -0x38(%rbp),%rdx
 3e4:	44 88 64 1a 02       	mov    %r12b,0x2(%rdx,%rbx,1)
 3e9:	48 83 c3 03          	add    $0x3,%rbx
 3ed:	48 89 5d d0          	mov    %rbx,-0x30(%rbp)
 3f1:	48 89 da             	mov    %rbx,%rdx
 3f4:	4c 8b 45 b0          	mov    -0x50(%rbp),%r8
 3f8:	4c 8b 4d 98          	mov    -0x68(%rbp),%r9
 3fc:	48 89 d3             	mov    %rdx,%rbx
 3ff:	48 85 c0             	test   %rax,%rax
 402:	0f 85 97 fe ff ff    	jne    29f <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x29f>
 408:	eb 48                	jmp    452 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x452>
 40a:	c6 47 08 01          	movb   $0x1,0x8(%rdi)
 40e:	48 c7 07 ff ff ff ff 	movq   $0xffffffffffffffff,(%rdi)
 415:	48 8b 75 c0          	mov    -0x40(%rbp),%rsi
 419:	48 85 f6             	test   %rsi,%rsi
 41c:	0f 84 b0 fc ff ff    	je     d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 422:	48 8b 7d c8          	mov    -0x38(%rbp),%rdi
 426:	ba 01 00 00 00       	mov    $0x1,%edx
 42b:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 431 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x431>
 431:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 435:	e9 98 fc ff ff       	jmp    d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 43a:	48 89 5d c0          	mov    %rbx,-0x40(%rbp)
 43e:	48 c7 45 c8 01 00 00 	movq   $0x1,-0x38(%rbp)
 445:	00
 446:	48 c7 45 d0 00 00 00 	movq   $0x0,-0x30(%rbp)
 44d:	00
 44e:	48 8b 7d b8          	mov    -0x48(%rbp),%rdi
 452:	48 8b 45 d0          	mov    -0x30(%rbp),%rax
 456:	48 89 47 10          	mov    %rax,0x10(%rdi)
 45a:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 45e:	48 89 07             	mov    %rax,(%rdi)
 461:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 465:	48 89 47 08          	mov    %rax,0x8(%rdi)
 469:	e9 64 fc ff ff       	jmp    d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 46e:	45 31 f6             	xor    %r14d,%r14d
 471:	4c 89 f7             	mov    %r14,%rdi
 474:	48 89 de             	mov    %rbx,%rsi
 477:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 47d <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x47d>

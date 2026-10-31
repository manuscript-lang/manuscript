0000000000000000 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	41 57                	push   %r15
   6:	41 56                	push   %r14
   8:	41 55                	push   %r13
   a:	41 54                	push   %r12
   c:	53                   	push   %rbx
   d:	48 83 ec 48          	sub    $0x48,%rsp
  11:	48 c7 c0 ff ff ff ff 	mov    $0xffffffffffffffff,%rax
  18:	49 83 f8 01          	cmp    $0x1,%r8
  1c:	75 08                	jne    26 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x26>
  1e:	4c 89 c8             	mov    %r9,%rax
  21:	4d 85 c9             	test   %r9,%r9
  24:	78 61                	js     87 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x87>
  26:	48 85 d2             	test   %rdx,%rdx
  29:	74 30                	je     5b <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x5b>
  2b:	45 31 c0             	xor    %r8d,%r8d
  2e:	49 b9 00 26 00 00 01 	movabs $0x100002600,%r9
  35:	00 00 00
  38:	eb 0e                	jmp    48 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x48>
  3a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
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
  a4:	49 89 d2             	mov    %rdx,%r10
  a7:	49 c1 ea 02          	shr    $0x2,%r10
  ab:	4b 8d 1c 52          	lea    (%r10,%r10,2),%rbx
  af:	45 31 c0             	xor    %r8d,%r8d
  b2:	49 89 d9             	mov    %rbx,%r9
  b5:	4d 29 f9             	sub    %r15,%r9
  b8:	4d 0f 43 c1          	cmovae %r9,%r8
  bc:	49 39 c0             	cmp    %rax,%r8
  bf:	76 23                	jbe    e4 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xe4>
  c1:	c6 47 08 02          	movb   $0x2,0x8(%rdi)
  c5:	eb 04                	jmp    cb <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xcb>
  c7:	c6 47 08 01          	movb   $0x1,0x8(%rdi)
  cb:	48 c7 07 ff ff ff ff 	movq   $0xffffffffffffffff,(%rdi)
  d2:	48 89 f8             	mov    %rdi,%rax
  d5:	48 83 c4 48          	add    $0x48,%rsp
  d9:	5b                   	pop    %rbx
  da:	41 5c                	pop    %r12
  dc:	41 5d                	pop    %r13
  de:	41 5e                	pop    %r14
  e0:	41 5f                	pop    %r15
  e2:	5d                   	pop    %rbp
  e3:	c3                   	ret
  e4:	48 8d 05 00 00 00 00 	lea    0x0(%rip),%rax        # eb <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xeb>
  eb:	4c 8d 2d 00 00 00 00 	lea    0x0(%rip),%r13        # f2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xf2>
  f2:	84 c9                	test   %cl,%cl
  f4:	4c 0f 45 e8          	cmovne %rax,%r13
  f8:	48 85 db             	test   %rbx,%rbx
  fb:	0f 88 34 02 00 00    	js     335 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x335>
 101:	48 85 d2             	test   %rdx,%rdx
 104:	0f 84 fb 01 00 00    	je     305 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x305>
 10a:	4c 89 55 a8          	mov    %r10,-0x58(%rbp)
 10e:	49 89 f4             	mov    %rsi,%r12
 111:	49 89 d6             	mov    %rdx,%r14
 114:	48 89 7d b0          	mov    %rdi,-0x50(%rbp)
 118:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 11e <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x11e>
 11e:	b8 01 00 00 00       	mov    $0x1,%eax
 123:	48 89 45 d0          	mov    %rax,-0x30(%rbp)
 127:	be 01 00 00 00       	mov    $0x1,%esi
 12c:	48 89 df             	mov    %rbx,%rdi
 12f:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 135 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x135>
 135:	48 85 c0             	test   %rax,%rax
 138:	0f 84 ff 01 00 00    	je     33d <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x33d>
 13e:	48 89 5d b8          	mov    %rbx,-0x48(%rbp)
 142:	48 89 45 c0          	mov    %rax,-0x40(%rbp)
 146:	48 c7 45 c8 00 00 00 	movq   $0x0,-0x38(%rbp)
 14d:	00
 14e:	31 d2                	xor    %edx,%edx
 150:	45 31 c9             	xor    %r9d,%r9d
 153:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 157:	4c 89 f0             	mov    %r14,%rax
 15a:	4c 89 e1             	mov    %r12,%rcx
 15d:	4c 8b 45 a8          	mov    -0x58(%rbp),%r8
 161:	48 89 55 d0          	mov    %rdx,-0x30(%rbp)
 165:	48 83 f8 04          	cmp    $0x4,%rax
 169:	ba 04 00 00 00       	mov    $0x4,%edx
 16e:	48 0f 42 d0          	cmovb  %rax,%rdx
 172:	48 89 ce             	mov    %rcx,%rsi
 175:	48 01 d1             	add    %rdx,%rcx
 178:	48 29 d0             	sub    %rdx,%rax
 17b:	49 ff c1             	inc    %r9
 17e:	4c 89 4d 90          	mov    %r9,-0x70(%rbp)
 182:	4d 39 c1             	cmp    %r8,%r9
 185:	bb 00 00 00 00       	mov    $0x0,%ebx
 18a:	49 0f 44 df          	cmove  %r15,%rbx
 18e:	41 b8 04 00 00 00    	mov    $0x4,%r8d
 194:	49 29 d8             	sub    %rbx,%r8
 197:	45 31 e4             	xor    %r12d,%r12d
 19a:	45 31 c9             	xor    %r9d,%r9d
 19d:	eb 29                	jmp    1c8 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1c8>
 19f:	90                   	nop
 1a0:	47 0f b6 54 1d 00    	movzbl 0x0(%r13,%r11,1),%r10d
 1a6:	41 81 fa ff 00 00 00 	cmp    $0xff,%r10d
 1ad:	0f 84 22 01 00 00    	je     2d5 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2d5>
 1b3:	49 ff c1             	inc    %r9
 1b6:	45 89 e6             	mov    %r12d,%r14d
 1b9:	41 c1 e6 06          	shl    $0x6,%r14d
 1bd:	45 89 d4             	mov    %r10d,%r12d
 1c0:	45 09 f4             	or     %r14d,%r12d
 1c3:	4c 39 ca             	cmp    %r9,%rdx
 1c6:	74 18                	je     1e0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1e0>
 1c8:	46 0f b6 1c 0e       	movzbl (%rsi,%r9,1),%r11d
 1cd:	4d 39 c1             	cmp    %r8,%r9
 1d0:	72 ce                	jb     1a0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1a0>
 1d2:	45 31 d2             	xor    %r10d,%r10d
 1d5:	41 83 fb 3d          	cmp    $0x3d,%r11d
 1d9:	74 d8                	je     1b3 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1b3>
 1db:	e9 f5 00 00 00       	jmp    2d5 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2d5>
 1e0:	48 83 fb 01          	cmp    $0x1,%rbx
 1e4:	74 11                	je     1f7 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x1f7>
 1e6:	48 83 fb 02          	cmp    $0x2,%rbx
 1ea:	75 14                	jne    200 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x200>
 1ec:	66 45 85 e4          	test   %r12w,%r12w
 1f0:	74 0e                	je     200 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x200>
 1f2:	e9 de 00 00 00       	jmp    2d5 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2d5>
 1f7:	45 84 e4             	test   %r12b,%r12b
 1fa:	0f 85 d5 00 00 00    	jne    2d5 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2d5>
 200:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 204:	4c 3b 45 b8          	cmp    -0x48(%rbp),%r8
 208:	75 22                	jne    22c <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x22c>
 20a:	48 8d 7d b8          	lea    -0x48(%rbp),%rdi
 20e:	48 89 45 98          	mov    %rax,-0x68(%rbp)
 212:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 216:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 21c <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x21c>
 21c:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 220:	48 8b 4d a0          	mov    -0x60(%rbp),%rcx
 224:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 228:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 22c:	44 89 f2             	mov    %r14d,%edx
 22f:	c1 ea 10             	shr    $0x10,%edx
 232:	48 8b 75 c0          	mov    -0x40(%rbp),%rsi
 236:	42 88 14 06          	mov    %dl,(%rsi,%r8,1)
 23a:	49 8d 50 01          	lea    0x1(%r8),%rdx
 23e:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 242:	48 83 fb 02          	cmp    $0x2,%rbx
 246:	73 7a                	jae    2c2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2c2>
 248:	48 3b 55 b8          	cmp    -0x48(%rbp),%rdx
 24c:	75 22                	jne    270 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x270>
 24e:	48 8d 7d b8          	lea    -0x48(%rbp),%rdi
 252:	48 89 45 98          	mov    %rax,-0x68(%rbp)
 256:	48 89 4d a0          	mov    %rcx,-0x60(%rbp)
 25a:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 260 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x260>
 260:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 264:	48 8b 4d a0          	mov    -0x60(%rbp),%rcx
 268:	48 8b 45 98          	mov    -0x68(%rbp),%rax
 26c:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 270:	41 c1 ee 08          	shr    $0x8,%r14d
 274:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 278:	46 88 74 02 01       	mov    %r14b,0x1(%rdx,%r8,1)
 27d:	49 8d 50 02          	lea    0x2(%r8),%rdx
 281:	48 89 55 c8          	mov    %rdx,-0x38(%rbp)
 285:	48 85 db             	test   %rbx,%rbx
 288:	75 38                	jne    2c2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2c2>
 28a:	48 3b 55 b8          	cmp    -0x48(%rbp),%rdx
 28e:	75 1e                	jne    2ae <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2ae>
 290:	48 8d 7d b8          	lea    -0x48(%rbp),%rdi
 294:	48 89 c3             	mov    %rax,%rbx
 297:	49 89 ce             	mov    %rcx,%r14
 29a:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 2a0 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2a0>
 2a0:	4c 8b 45 d0          	mov    -0x30(%rbp),%r8
 2a4:	4c 89 f1             	mov    %r14,%rcx
 2a7:	48 89 d8             	mov    %rbx,%rax
 2aa:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 2ae:	48 8b 55 c0          	mov    -0x40(%rbp),%rdx
 2b2:	46 88 64 02 02       	mov    %r12b,0x2(%rdx,%r8,1)
 2b7:	49 83 c0 03          	add    $0x3,%r8
 2bb:	4c 89 45 c8          	mov    %r8,-0x38(%rbp)
 2bf:	4c 89 c2             	mov    %r8,%rdx
 2c2:	4c 8b 45 a8          	mov    -0x58(%rbp),%r8
 2c6:	4c 8b 4d 90          	mov    -0x70(%rbp),%r9
 2ca:	48 85 c0             	test   %rax,%rax
 2cd:	0f 85 8e fe ff ff    	jne    161 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x161>
 2d3:	eb 44                	jmp    319 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x319>
 2d5:	c6 47 08 01          	movb   $0x1,0x8(%rdi)
 2d9:	48 c7 07 ff ff ff ff 	movq   $0xffffffffffffffff,(%rdi)
 2e0:	48 8b 75 b8          	mov    -0x48(%rbp),%rsi
 2e4:	48 85 f6             	test   %rsi,%rsi
 2e7:	0f 84 e5 fd ff ff    	je     d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 2ed:	48 8b 7d c0          	mov    -0x40(%rbp),%rdi
 2f1:	ba 01 00 00 00       	mov    $0x1,%edx
 2f6:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 2fc <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x2fc>
 2fc:	48 8b 7d b0          	mov    -0x50(%rbp),%rdi
 300:	e9 cd fd ff ff       	jmp    d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 305:	48 89 5d b8          	mov    %rbx,-0x48(%rbp)
 309:	48 c7 45 c0 01 00 00 	movq   $0x1,-0x40(%rbp)
 310:	00
 311:	48 c7 45 c8 00 00 00 	movq   $0x0,-0x38(%rbp)
 318:	00
 319:	48 8b 45 c8          	mov    -0x38(%rbp),%rax
 31d:	48 89 47 10          	mov    %rax,0x10(%rdi)
 321:	48 8b 45 b8          	mov    -0x48(%rbp),%rax
 325:	48 89 07             	mov    %rax,(%rdi)
 328:	48 8b 45 c0          	mov    -0x40(%rbp),%rax
 32c:	48 89 47 08          	mov    %rax,0x8(%rdi)
 330:	e9 9d fd ff ff       	jmp    d2 <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0xd2>
 335:	48 c7 45 d0 00 00 00 	movq   $0x0,-0x30(%rbp)
 33c:	00
 33d:	48 8b 7d d0          	mov    -0x30(%rbp),%rdi
 341:	48 89 de             	mov    %rbx,%rsi
 344:	ff 15 00 00 00 00    	call   *0x0(%rip)        # 34a <_RNvCskAOVCP7lgAu_15ms_std_encoding13base64_decode+0x34a>

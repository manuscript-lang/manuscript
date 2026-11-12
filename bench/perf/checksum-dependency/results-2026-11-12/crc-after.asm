
/workspace/hash-results/new:     file format elf64-x86-64


Disassembly of section .text:

000000000021ce10 <msstd_checksum_crc32>:
  21ce10:	4c 8b 4f 08          	mov    0x8(%rdi),%r9
  21ce14:	4d 85 c9             	test   %r9,%r9
  21ce17:	0f 84 aa 00 00 00    	je     21cec7 <msstd_checksum_crc32+0xb7>
  21ce1d:	55                   	push   %rbp
  21ce1e:	48 89 e5             	mov    %rsp,%rbp
  21ce21:	53                   	push   %rbx
  21ce22:	48 8b 37             	mov    (%rdi),%rsi
  21ce25:	48 b8 f8 ff ff ff ff 	movabs $0x7ffffffffffffff8,%rax
  21ce2c:	ff ff 7f 
  21ce2f:	4c 21 c8             	and    %r9,%rax
  21ce32:	48 8d 14 06          	lea    (%rsi,%rax,1),%rdx
  21ce36:	41 83 e1 07          	and    $0x7,%r9d
  21ce3a:	48 85 c0             	test   %rax,%rax
  21ce3d:	0f 84 87 00 00 00    	je     21ceca <msstd_checksum_crc32+0xba>
  21ce43:	bb ff ff ff ff       	mov    $0xffffffff,%ebx
  21ce48:	48 8d 3d e9 66 fe ff 	lea    -0x19917(%rip),%rdi        # 203538 <_RNvCsjLkg4TF75xj_9ms_native4HEAP+0x3>
  21ce4f:	90                   	nop
  21ce50:	33 1e                	xor    (%rsi),%ebx
  21ce52:	44 0f b6 46 04       	movzbl 0x4(%rsi),%r8d
  21ce57:	0f b6 46 05          	movzbl 0x5(%rsi),%eax
  21ce5b:	8b 84 87 00 08 00 00 	mov    0x800(%rdi,%rax,4),%eax
  21ce62:	42 33 84 87 00 0c 00 	xor    0xc00(%rdi,%r8,4),%eax
  21ce69:	00 
  21ce6a:	44 0f b6 46 06       	movzbl 0x6(%rsi),%r8d
  21ce6f:	42 33 84 87 00 04 00 	xor    0x400(%rdi,%r8,4),%eax
  21ce76:	00 
  21ce77:	44 0f b6 46 07       	movzbl 0x7(%rsi),%r8d
  21ce7c:	42 33 04 87          	xor    (%rdi,%r8,4),%eax
  21ce80:	44 0f b6 c3          	movzbl %bl,%r8d
  21ce84:	42 33 84 87 00 1c 00 	xor    0x1c00(%rdi,%r8,4),%eax
  21ce8b:	00 
  21ce8c:	0f b6 cf             	movzbl %bh,%ecx
  21ce8f:	33 84 8f 00 18 00 00 	xor    0x1800(%rdi,%rcx,4),%eax
  21ce96:	89 d9                	mov    %ebx,%ecx
  21ce98:	c1 e9 0e             	shr    $0xe,%ecx
  21ce9b:	81 e1 fc 03 00 00    	and    $0x3fc,%ecx
  21cea1:	33 84 39 00 14 00 00 	xor    0x1400(%rcx,%rdi,1),%eax
  21cea8:	c1 eb 18             	shr    $0x18,%ebx
  21ceab:	33 84 9f 00 10 00 00 	xor    0x1000(%rdi,%rbx,4),%eax
  21ceb2:	48 83 c6 08          	add    $0x8,%rsi
  21ceb6:	89 c3                	mov    %eax,%ebx
  21ceb8:	48 39 d6             	cmp    %rdx,%rsi
  21cebb:	75 93                	jne    21ce50 <msstd_checksum_crc32+0x40>
  21cebd:	4d 85 c9             	test   %r9,%r9
  21cec0:	75 12                	jne    21ced4 <msstd_checksum_crc32+0xc4>
  21cec2:	f7 d0                	not    %eax
  21cec4:	5b                   	pop    %rbx
  21cec5:	5d                   	pop    %rbp
  21cec6:	c3                   	ret
  21cec7:	31 c0                	xor    %eax,%eax
  21cec9:	c3                   	ret
  21ceca:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
  21cecf:	4d 85 c9             	test   %r9,%r9
  21ced2:	74 ee                	je     21cec2 <msstd_checksum_crc32+0xb2>
  21ced4:	0f b6 0a             	movzbl (%rdx),%ecx
  21ced7:	30 c1                	xor    %al,%cl
  21ced9:	0f b6 c9             	movzbl %cl,%ecx
  21cedc:	48 8d 35 55 66 fe ff 	lea    -0x199ab(%rip),%rsi        # 203538 <_RNvCsjLkg4TF75xj_9ms_native4HEAP+0x3>
  21cee3:	c1 e8 08             	shr    $0x8,%eax
  21cee6:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cee9:	41 83 f9 01          	cmp    $0x1,%r9d
  21ceed:	74 d3                	je     21cec2 <msstd_checksum_crc32+0xb2>
  21ceef:	0f b6 4a 01          	movzbl 0x1(%rdx),%ecx
  21cef3:	30 c1                	xor    %al,%cl
  21cef5:	0f b6 c9             	movzbl %cl,%ecx
  21cef8:	c1 e8 08             	shr    $0x8,%eax
  21cefb:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cefe:	41 83 f9 02          	cmp    $0x2,%r9d
  21cf02:	74 be                	je     21cec2 <msstd_checksum_crc32+0xb2>
  21cf04:	0f b6 4a 02          	movzbl 0x2(%rdx),%ecx
  21cf08:	30 c1                	xor    %al,%cl
  21cf0a:	0f b6 c9             	movzbl %cl,%ecx
  21cf0d:	c1 e8 08             	shr    $0x8,%eax
  21cf10:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf13:	41 83 f9 03          	cmp    $0x3,%r9d
  21cf17:	74 a9                	je     21cec2 <msstd_checksum_crc32+0xb2>
  21cf19:	0f b6 4a 03          	movzbl 0x3(%rdx),%ecx
  21cf1d:	30 c1                	xor    %al,%cl
  21cf1f:	0f b6 c9             	movzbl %cl,%ecx
  21cf22:	c1 e8 08             	shr    $0x8,%eax
  21cf25:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf28:	41 83 f9 04          	cmp    $0x4,%r9d
  21cf2c:	74 94                	je     21cec2 <msstd_checksum_crc32+0xb2>
  21cf2e:	0f b6 4a 04          	movzbl 0x4(%rdx),%ecx
  21cf32:	30 c1                	xor    %al,%cl
  21cf34:	0f b6 c9             	movzbl %cl,%ecx
  21cf37:	c1 e8 08             	shr    $0x8,%eax
  21cf3a:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf3d:	41 83 f9 05          	cmp    $0x5,%r9d
  21cf41:	0f 84 7b ff ff ff    	je     21cec2 <msstd_checksum_crc32+0xb2>
  21cf47:	0f b6 4a 05          	movzbl 0x5(%rdx),%ecx
  21cf4b:	30 c1                	xor    %al,%cl
  21cf4d:	0f b6 c9             	movzbl %cl,%ecx
  21cf50:	c1 e8 08             	shr    $0x8,%eax
  21cf53:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf56:	41 83 f9 06          	cmp    $0x6,%r9d
  21cf5a:	0f 84 62 ff ff ff    	je     21cec2 <msstd_checksum_crc32+0xb2>
  21cf60:	0f b6 4a 06          	movzbl 0x6(%rdx),%ecx
  21cf64:	30 c1                	xor    %al,%cl
  21cf66:	0f b6 c9             	movzbl %cl,%ecx
  21cf69:	c1 e8 08             	shr    $0x8,%eax
  21cf6c:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf6f:	f7 d0                	not    %eax
  21cf71:	5b                   	pop    %rbx
  21cf72:	5d                   	pop    %rbp
  21cf73:	c3                   	ret

Disassembly of section .plt:

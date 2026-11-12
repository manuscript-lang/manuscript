
/workspace/hash-results/ms:     file format elf64-x86-64


Disassembly of section .text:

000000000021ce10 <msstd_checksum_crc32>:
  21ce10:	48 8b 4f 08          	mov    0x8(%rdi),%rcx
  21ce14:	48 85 c9             	test   %rcx,%rcx
  21ce17:	0f 84 b0 00 00 00    	je     21cecd <msstd_checksum_crc32+0xbd>
  21ce1d:	55                   	push   %rbp
  21ce1e:	48 89 e5             	mov    %rsp,%rbp
  21ce21:	53                   	push   %rbx
  21ce22:	48 8b 37             	mov    (%rdi),%rsi
  21ce25:	48 b8 f8 ff ff ff ff 	movabs $0x7ffffffffffffff8,%rax
  21ce2c:	ff ff 7f 
  21ce2f:	48 21 c8             	and    %rcx,%rax
  21ce32:	48 8d 14 06          	lea    (%rsi,%rax,1),%rdx
  21ce36:	83 e1 07             	and    $0x7,%ecx
  21ce39:	48 85 c0             	test   %rax,%rax
  21ce3c:	0f 84 8e 00 00 00    	je     21ced0 <msstd_checksum_crc32+0xc0>
  21ce42:	bb ff ff ff ff       	mov    $0xffffffff,%ebx
  21ce47:	48 8d 3d ea 66 fe ff 	lea    -0x19916(%rip),%rdi        # 203538 <_RNvCsjLkg4TF75xj_9ms_native4HEAP+0x3>
  21ce4e:	66 90                	xchg   %ax,%ax
  21ce50:	33 1e                	xor    (%rsi),%ebx
  21ce52:	44 0f b6 c3          	movzbl %bl,%r8d
  21ce56:	0f b6 c7             	movzbl %bh,%eax
  21ce59:	8b 84 87 00 18 00 00 	mov    0x1800(%rdi,%rax,4),%eax
  21ce60:	42 33 84 87 00 1c 00 	xor    0x1c00(%rdi,%r8,4),%eax
  21ce67:	00 
  21ce68:	41 89 d8             	mov    %ebx,%r8d
  21ce6b:	41 c1 e8 0e          	shr    $0xe,%r8d
  21ce6f:	41 81 e0 fc 03 00 00 	and    $0x3fc,%r8d
  21ce76:	41 33 84 38 00 14 00 	xor    0x1400(%r8,%rdi,1),%eax
  21ce7d:	00 
  21ce7e:	c1 eb 18             	shr    $0x18,%ebx
  21ce81:	33 84 9f 00 10 00 00 	xor    0x1000(%rdi,%rbx,4),%eax
  21ce88:	44 0f b6 46 07       	movzbl 0x7(%rsi),%r8d
  21ce8d:	44 0f b6 4e 04       	movzbl 0x4(%rsi),%r9d
  21ce92:	42 33 84 8f 00 0c 00 	xor    0xc00(%rdi,%r9,4),%eax
  21ce99:	00 
  21ce9a:	44 0f b6 4e 05       	movzbl 0x5(%rsi),%r9d
  21ce9f:	42 33 84 8f 00 08 00 	xor    0x800(%rdi,%r9,4),%eax
  21cea6:	00 
  21cea7:	44 0f b6 4e 06       	movzbl 0x6(%rsi),%r9d
  21ceac:	42 33 84 8f 00 04 00 	xor    0x400(%rdi,%r9,4),%eax
  21ceb3:	00 
  21ceb4:	42 33 04 87          	xor    (%rdi,%r8,4),%eax
  21ceb8:	48 83 c6 08          	add    $0x8,%rsi
  21cebc:	89 c3                	mov    %eax,%ebx
  21cebe:	48 39 d6             	cmp    %rdx,%rsi
  21cec1:	75 8d                	jne    21ce50 <msstd_checksum_crc32+0x40>
  21cec3:	48 85 c9             	test   %rcx,%rcx
  21cec6:	75 12                	jne    21ceda <msstd_checksum_crc32+0xca>
  21cec8:	f7 d0                	not    %eax
  21ceca:	5b                   	pop    %rbx
  21cecb:	5d                   	pop    %rbp
  21cecc:	c3                   	ret
  21cecd:	31 c0                	xor    %eax,%eax
  21cecf:	c3                   	ret
  21ced0:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
  21ced5:	48 85 c9             	test   %rcx,%rcx
  21ced8:	74 ee                	je     21cec8 <msstd_checksum_crc32+0xb8>
  21ceda:	0f b6 32             	movzbl (%rdx),%esi
  21cedd:	40 30 c6             	xor    %al,%sil
  21cee0:	40 0f b6 fe          	movzbl %sil,%edi
  21cee4:	48 8d 35 4d 66 fe ff 	lea    -0x199b3(%rip),%rsi        # 203538 <_RNvCsjLkg4TF75xj_9ms_native4HEAP+0x3>
  21ceeb:	c1 e8 08             	shr    $0x8,%eax
  21ceee:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cef1:	83 f9 01             	cmp    $0x1,%ecx
  21cef4:	74 d2                	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cef6:	0f b6 7a 01          	movzbl 0x1(%rdx),%edi
  21cefa:	40 30 c7             	xor    %al,%dil
  21cefd:	40 0f b6 ff          	movzbl %dil,%edi
  21cf01:	c1 e8 08             	shr    $0x8,%eax
  21cf04:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cf07:	83 f9 02             	cmp    $0x2,%ecx
  21cf0a:	74 bc                	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cf0c:	0f b6 7a 02          	movzbl 0x2(%rdx),%edi
  21cf10:	40 30 c7             	xor    %al,%dil
  21cf13:	40 0f b6 ff          	movzbl %dil,%edi
  21cf17:	c1 e8 08             	shr    $0x8,%eax
  21cf1a:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cf1d:	83 f9 03             	cmp    $0x3,%ecx
  21cf20:	74 a6                	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cf22:	0f b6 7a 03          	movzbl 0x3(%rdx),%edi
  21cf26:	40 30 c7             	xor    %al,%dil
  21cf29:	40 0f b6 ff          	movzbl %dil,%edi
  21cf2d:	c1 e8 08             	shr    $0x8,%eax
  21cf30:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cf33:	83 f9 04             	cmp    $0x4,%ecx
  21cf36:	74 90                	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cf38:	0f b6 7a 04          	movzbl 0x4(%rdx),%edi
  21cf3c:	40 30 c7             	xor    %al,%dil
  21cf3f:	40 0f b6 ff          	movzbl %dil,%edi
  21cf43:	c1 e8 08             	shr    $0x8,%eax
  21cf46:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cf49:	83 f9 05             	cmp    $0x5,%ecx
  21cf4c:	0f 84 76 ff ff ff    	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cf52:	0f b6 7a 05          	movzbl 0x5(%rdx),%edi
  21cf56:	40 30 c7             	xor    %al,%dil
  21cf59:	40 0f b6 ff          	movzbl %dil,%edi
  21cf5d:	c1 e8 08             	shr    $0x8,%eax
  21cf60:	33 04 be             	xor    (%rsi,%rdi,4),%eax
  21cf63:	83 f9 06             	cmp    $0x6,%ecx
  21cf66:	0f 84 5c ff ff ff    	je     21cec8 <msstd_checksum_crc32+0xb8>
  21cf6c:	0f b6 4a 06          	movzbl 0x6(%rdx),%ecx
  21cf70:	30 c1                	xor    %al,%cl
  21cf72:	0f b6 c9             	movzbl %cl,%ecx
  21cf75:	c1 e8 08             	shr    $0x8,%eax
  21cf78:	33 04 8e             	xor    (%rsi,%rcx,4),%eax
  21cf7b:	f7 d0                	not    %eax
  21cf7d:	5b                   	pop    %rbx
  21cf7e:	5d                   	pop    %rbp
  21cf7f:	c3                   	ret

Disassembly of section .plt:

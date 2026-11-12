
/workspace/hash-results/c:     file format elf64-x86-64


Disassembly of section .init:

Disassembly of section .plt:

Disassembly of section .plt.got:

Disassembly of section .text:

0000000000001820 <crc>:
    1820:	89 f8                	mov    %edi,%eax
    1822:	53                   	push   %rbx
    1823:	48 89 f7             	mov    %rsi,%rdi
    1826:	48 89 d6             	mov    %rdx,%rsi
    1829:	f7 d0                	not    %eax
    182b:	48 83 fa 07          	cmp    $0x7,%rdx
    182f:	0f 86 9a 00 00 00    	jbe    18cf <crc+0xaf>
    1835:	4c 8d 4a f8          	lea    -0x8(%rdx),%r9
    1839:	48 89 f9             	mov    %rdi,%rcx
    183c:	4c 89 ca             	mov    %r9,%rdx
    183f:	48 c1 ea 03          	shr    $0x3,%rdx
    1843:	4c 8d 44 d7 08       	lea    0x8(%rdi,%rdx,8),%r8
    1848:	48 8d 15 31 28 00 00 	lea    0x2831(%rip),%rdx        # 4080 <table>
    184f:	90                   	nop
    1850:	33 01                	xor    (%rcx),%eax
    1852:	44 0f b6 59 05       	movzbl 0x5(%rcx),%r11d
    1857:	48 83 c1 08          	add    $0x8,%rcx
    185b:	89 c3                	mov    %eax,%ebx
    185d:	41 89 c2             	mov    %eax,%r10d
    1860:	0f b6 41 fc          	movzbl -0x4(%rcx),%eax
    1864:	41 c1 ea 10          	shr    $0x10,%r10d
    1868:	8b 84 82 00 0c 00 00 	mov    0xc00(%rdx,%rax,4),%eax
    186f:	42 33 84 9a 00 08 00 	xor    0x800(%rdx,%r11,4),%eax
    1876:	00 
    1877:	45 0f b6 d2          	movzbl %r10b,%r10d
    187b:	44 0f b6 59 fe       	movzbl -0x2(%rcx),%r11d
    1880:	42 33 84 9a 00 04 00 	xor    0x400(%rdx,%r11,4),%eax
    1887:	00 
    1888:	44 0f b6 59 ff       	movzbl -0x1(%rcx),%r11d
    188d:	42 33 04 9a          	xor    (%rdx,%r11,4),%eax
    1891:	44 0f b6 db          	movzbl %bl,%r11d
    1895:	42 33 84 9a 00 1c 00 	xor    0x1c00(%rdx,%r11,4),%eax
    189c:	00 
    189d:	41 89 db             	mov    %ebx,%r11d
    18a0:	0f b6 df             	movzbl %bh,%ebx
    18a3:	41 c1 eb 18          	shr    $0x18,%r11d
    18a7:	42 33 84 9a 00 10 00 	xor    0x1000(%rdx,%r11,4),%eax
    18ae:	00 
    18af:	33 84 9a 00 18 00 00 	xor    0x1800(%rdx,%rbx,4),%eax
    18b6:	42 33 84 92 00 14 00 	xor    0x1400(%rdx,%r10,4),%eax
    18bd:	00 
    18be:	49 39 c8             	cmp    %rcx,%r8
    18c1:	75 8d                	jne    1850 <crc+0x30>
    18c3:	49 83 e1 f8          	and    $0xfffffffffffffff8,%r9
    18c7:	83 e6 07             	and    $0x7,%esi
    18ca:	4a 8d 7c 0f 08       	lea    0x8(%rdi,%r9,1),%rdi
    18cf:	48 85 f6             	test   %rsi,%rsi
    18d2:	0f 84 93 00 00 00    	je     196b <crc+0x14b>
    18d8:	0f b6 0f             	movzbl (%rdi),%ecx
    18db:	48 8d 15 9e 27 00 00 	lea    0x279e(%rip),%rdx        # 4080 <table>
    18e2:	31 c1                	xor    %eax,%ecx
    18e4:	c1 e8 08             	shr    $0x8,%eax
    18e7:	0f b6 c9             	movzbl %cl,%ecx
    18ea:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    18ed:	48 83 fe 01          	cmp    $0x1,%rsi
    18f1:	74 78                	je     196b <crc+0x14b>
    18f3:	0f b6 4f 01          	movzbl 0x1(%rdi),%ecx
    18f7:	31 c1                	xor    %eax,%ecx
    18f9:	c1 e8 08             	shr    $0x8,%eax
    18fc:	0f b6 c9             	movzbl %cl,%ecx
    18ff:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    1902:	48 83 fe 02          	cmp    $0x2,%rsi
    1906:	74 63                	je     196b <crc+0x14b>
    1908:	0f b6 4f 02          	movzbl 0x2(%rdi),%ecx
    190c:	31 c1                	xor    %eax,%ecx
    190e:	c1 e8 08             	shr    $0x8,%eax
    1911:	0f b6 c9             	movzbl %cl,%ecx
    1914:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    1917:	48 83 fe 03          	cmp    $0x3,%rsi
    191b:	74 4e                	je     196b <crc+0x14b>
    191d:	0f b6 4f 03          	movzbl 0x3(%rdi),%ecx
    1921:	31 c1                	xor    %eax,%ecx
    1923:	c1 e8 08             	shr    $0x8,%eax
    1926:	0f b6 c9             	movzbl %cl,%ecx
    1929:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    192c:	48 83 fe 04          	cmp    $0x4,%rsi
    1930:	74 39                	je     196b <crc+0x14b>
    1932:	0f b6 4f 04          	movzbl 0x4(%rdi),%ecx
    1936:	31 c1                	xor    %eax,%ecx
    1938:	c1 e8 08             	shr    $0x8,%eax
    193b:	0f b6 c9             	movzbl %cl,%ecx
    193e:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    1941:	48 83 fe 05          	cmp    $0x5,%rsi
    1945:	74 24                	je     196b <crc+0x14b>
    1947:	0f b6 4f 05          	movzbl 0x5(%rdi),%ecx
    194b:	31 c1                	xor    %eax,%ecx
    194d:	c1 e8 08             	shr    $0x8,%eax
    1950:	0f b6 c9             	movzbl %cl,%ecx
    1953:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    1956:	48 83 fe 06          	cmp    $0x6,%rsi
    195a:	74 0f                	je     196b <crc+0x14b>
    195c:	0f b6 4f 06          	movzbl 0x6(%rdi),%ecx
    1960:	31 c1                	xor    %eax,%ecx
    1962:	c1 e8 08             	shr    $0x8,%eax
    1965:	0f b6 c9             	movzbl %cl,%ecx
    1968:	33 04 8a             	xor    (%rdx,%rcx,4),%eax
    196b:	f7 d0                	not    %eax
    196d:	5b                   	pop    %rbx
    196e:	c3                   	ret

Disassembly of section .fini:

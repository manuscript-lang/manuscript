// conform: tags=control-flow,lowering
// conform: phase=run
// Past 64 open scopes, 32 loops, 256 mutable locals and 8 `var` arguments the lowerer
// used to stop with an internal error.
fn pick(n Int) String {
	if n == 0 {
		return "v0"
	} else if n == 1 {
		return "v1"
	} else if n == 2 {
		return "v2"
	} else if n == 3 {
		return "v3"
	} else if n == 4 {
		return "v4"
	} else if n == 5 {
		return "v5"
	} else if n == 6 {
		return "v6"
	} else if n == 7 {
		return "v7"
	} else if n == 8 {
		return "v8"
	} else if n == 9 {
		return "v9"
	} else if n == 10 {
		return "v10"
	} else if n == 11 {
		return "v11"
	} else if n == 12 {
		return "v12"
	} else if n == 13 {
		return "v13"
	} else if n == 14 {
		return "v14"
	} else if n == 15 {
		return "v15"
	} else if n == 16 {
		return "v16"
	} else if n == 17 {
		return "v17"
	} else if n == 18 {
		return "v18"
	} else if n == 19 {
		return "v19"
	} else if n == 20 {
		return "v20"
	} else if n == 21 {
		return "v21"
	} else if n == 22 {
		return "v22"
	} else if n == 23 {
		return "v23"
	} else if n == 24 {
		return "v24"
	} else if n == 25 {
		return "v25"
	} else if n == 26 {
		return "v26"
	} else if n == 27 {
		return "v27"
	} else if n == 28 {
		return "v28"
	} else if n == 29 {
		return "v29"
	} else if n == 30 {
		return "v30"
	} else if n == 31 {
		return "v31"
	} else if n == 32 {
		return "v32"
	} else if n == 33 {
		return "v33"
	} else if n == 34 {
		return "v34"
	} else if n == 35 {
		return "v35"
	} else if n == 36 {
		return "v36"
	} else if n == 37 {
		return "v37"
	} else if n == 38 {
		return "v38"
	} else if n == 39 {
		return "v39"
	} else if n == 40 {
		return "v40"
	} else if n == 41 {
		return "v41"
	} else if n == 42 {
		return "v42"
	} else if n == 43 {
		return "v43"
	} else if n == 44 {
		return "v44"
	} else if n == 45 {
		return "v45"
	} else if n == 46 {
		return "v46"
	} else if n == 47 {
		return "v47"
	} else if n == 48 {
		return "v48"
	} else if n == 49 {
		return "v49"
	} else if n == 50 {
		return "v50"
	} else if n == 51 {
		return "v51"
	} else if n == 52 {
		return "v52"
	} else if n == 53 {
		return "v53"
	} else if n == 54 {
		return "v54"
	} else if n == 55 {
		return "v55"
	} else if n == 56 {
		return "v56"
	} else if n == 57 {
		return "v57"
	} else if n == 58 {
		return "v58"
	} else if n == 59 {
		return "v59"
	} else if n == 60 {
		return "v60"
	} else if n == 61 {
		return "v61"
	} else if n == 62 {
		return "v62"
	} else if n == 63 {
		return "v63"
	} else if n == 64 {
		return "v64"
	} else if n == 65 {
		return "v65"
	} else if n == 66 {
		return "v66"
	} else if n == 67 {
		return "v67"
	} else if n == 68 {
		return "v68"
	} else if n == 69 {
		return "v69"
	} else {
		return "none"
	}
}

fn bump(
	var a0 Int,
	var a1 Int,
	var a2 Int,
	var a3 Int,
	var a4 Int,
	var a5 Int,
	var a6 Int,
	var a7 Int,
	var a8 Int,
	var a9 Int,
	var a10 Int,
	var a11 Int,
) Void {
	a0 += 1
	a1 += 2
	a2 += 3
	a3 += 4
	a4 += 5
	a5 += 6
	a6 += 7
	a7 += 8
	a8 += 9
	a9 += 10
	a10 += 11
	a11 += 12
}

fn main() Void {
	var w0 = 0
	var w1 = 0
	var w2 = 0
	var w3 = 0
	var w4 = 0
	var w5 = 0
	var w6 = 0
	var w7 = 0
	var w8 = 0
	var w9 = 0
	var w10 = 0
	var w11 = 0
	bump(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11)
	bump(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11)
	print(w0 + w11)
	print(pick(0))
	print(pick(69))
	print(pick(70))

	var count = 0
	for i0 in 0..1 {
		for i1 in 0..1 {
			for i2 in 0..1 {
				for i3 in 0..1 {
					for i4 in 0..1 {
						for i5 in 0..1 {
							for i6 in 0..1 {
								for i7 in 0..1 {
									for i8 in 0..1 {
										for i9 in 0..1 {
											for i10 in 0..1 {
												for i11 in 0..1 {
													for i12 in 0..1 {
														for i13 in 0..1 {
															for i14 in 0..1 {
																for i15 in 0..1 {
																	for i16 in 0..1 {
																		for i17 in 0..1 {
																			for i18 in 0..1 {
																				for i19 in 0..1 {
																					for i20 in 0..1 {
																						for i21 in 0..1 {
																							for i22 in 0..1 {
																								for i23 in 0..1 {
																									for i24 in 0..1 {
																										for i25 in 0..1 {
																											for i26 in 0..1 {
																												for i27 in 0..1 {
																													for i28 in 0..1 {
																														for i29 in 0..1 {
																															for i30 in 0..1 {
																																for i31 in 0..1 {
																																	for i32 in 0..1 {
																																		for i33 in 0..1 {
																																			for i34 in 0..1 {
																																				for i35 in 0..1 {
																																					count += 1
																																				}
																																			}
																																		}
																																	}
																																}
																															}
																														}
																													}
																												}
																											}
																										}
																									}
																								}
																							}
																						}
																					}
																				}
																			}
																		}
																	}
																}
															}
														}
													}
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	print(count)

	var s0 = "x0"
	s0 += "y"

	var s1 = "x1"
	s1 += "y"

	var s2 = "x2"
	s2 += "y"

	var s3 = "x3"
	s3 += "y"

	var s4 = "x4"
	s4 += "y"

	var s5 = "x5"
	s5 += "y"

	var s6 = "x6"
	s6 += "y"

	var s7 = "x7"
	s7 += "y"

	var s8 = "x8"
	s8 += "y"

	var s9 = "x9"
	s9 += "y"

	var s10 = "x10"
	s10 += "y"

	var s11 = "x11"
	s11 += "y"

	var s12 = "x12"
	s12 += "y"

	var s13 = "x13"
	s13 += "y"

	var s14 = "x14"
	s14 += "y"

	var s15 = "x15"
	s15 += "y"

	var s16 = "x16"
	s16 += "y"

	var s17 = "x17"
	s17 += "y"

	var s18 = "x18"
	s18 += "y"

	var s19 = "x19"
	s19 += "y"

	var s20 = "x20"
	s20 += "y"

	var s21 = "x21"
	s21 += "y"

	var s22 = "x22"
	s22 += "y"

	var s23 = "x23"
	s23 += "y"

	var s24 = "x24"
	s24 += "y"

	var s25 = "x25"
	s25 += "y"

	var s26 = "x26"
	s26 += "y"

	var s27 = "x27"
	s27 += "y"

	var s28 = "x28"
	s28 += "y"

	var s29 = "x29"
	s29 += "y"

	var s30 = "x30"
	s30 += "y"

	var s31 = "x31"
	s31 += "y"

	var s32 = "x32"
	s32 += "y"

	var s33 = "x33"
	s33 += "y"

	var s34 = "x34"
	s34 += "y"

	var s35 = "x35"
	s35 += "y"

	var s36 = "x36"
	s36 += "y"

	var s37 = "x37"
	s37 += "y"

	var s38 = "x38"
	s38 += "y"

	var s39 = "x39"
	s39 += "y"

	var s40 = "x40"
	s40 += "y"

	var s41 = "x41"
	s41 += "y"

	var s42 = "x42"
	s42 += "y"

	var s43 = "x43"
	s43 += "y"

	var s44 = "x44"
	s44 += "y"

	var s45 = "x45"
	s45 += "y"

	var s46 = "x46"
	s46 += "y"

	var s47 = "x47"
	s47 += "y"

	var s48 = "x48"
	s48 += "y"

	var s49 = "x49"
	s49 += "y"

	var s50 = "x50"
	s50 += "y"

	var s51 = "x51"
	s51 += "y"

	var s52 = "x52"
	s52 += "y"

	var s53 = "x53"
	s53 += "y"

	var s54 = "x54"
	s54 += "y"

	var s55 = "x55"
	s55 += "y"

	var s56 = "x56"
	s56 += "y"

	var s57 = "x57"
	s57 += "y"

	var s58 = "x58"
	s58 += "y"

	var s59 = "x59"
	s59 += "y"

	var s60 = "x60"
	s60 += "y"

	var s61 = "x61"
	s61 += "y"

	var s62 = "x62"
	s62 += "y"

	var s63 = "x63"
	s63 += "y"

	var s64 = "x64"
	s64 += "y"

	var s65 = "x65"
	s65 += "y"

	var s66 = "x66"
	s66 += "y"

	var s67 = "x67"
	s67 += "y"

	var s68 = "x68"
	s68 += "y"

	var s69 = "x69"
	s69 += "y"

	var s70 = "x70"
	s70 += "y"

	var s71 = "x71"
	s71 += "y"

	var s72 = "x72"
	s72 += "y"

	var s73 = "x73"
	s73 += "y"

	var s74 = "x74"
	s74 += "y"

	var s75 = "x75"
	s75 += "y"

	var s76 = "x76"
	s76 += "y"

	var s77 = "x77"
	s77 += "y"

	var s78 = "x78"
	s78 += "y"

	var s79 = "x79"
	s79 += "y"

	var s80 = "x80"
	s80 += "y"

	var s81 = "x81"
	s81 += "y"

	var s82 = "x82"
	s82 += "y"

	var s83 = "x83"
	s83 += "y"

	var s84 = "x84"
	s84 += "y"

	var s85 = "x85"
	s85 += "y"

	var s86 = "x86"
	s86 += "y"

	var s87 = "x87"
	s87 += "y"

	var s88 = "x88"
	s88 += "y"

	var s89 = "x89"
	s89 += "y"

	var s90 = "x90"
	s90 += "y"

	var s91 = "x91"
	s91 += "y"

	var s92 = "x92"
	s92 += "y"

	var s93 = "x93"
	s93 += "y"

	var s94 = "x94"
	s94 += "y"

	var s95 = "x95"
	s95 += "y"

	var s96 = "x96"
	s96 += "y"

	var s97 = "x97"
	s97 += "y"

	var s98 = "x98"
	s98 += "y"

	var s99 = "x99"
	s99 += "y"

	var s100 = "x100"
	s100 += "y"

	var s101 = "x101"
	s101 += "y"

	var s102 = "x102"
	s102 += "y"

	var s103 = "x103"
	s103 += "y"

	var s104 = "x104"
	s104 += "y"

	var s105 = "x105"
	s105 += "y"

	var s106 = "x106"
	s106 += "y"

	var s107 = "x107"
	s107 += "y"

	var s108 = "x108"
	s108 += "y"

	var s109 = "x109"
	s109 += "y"

	var s110 = "x110"
	s110 += "y"

	var s111 = "x111"
	s111 += "y"

	var s112 = "x112"
	s112 += "y"

	var s113 = "x113"
	s113 += "y"

	var s114 = "x114"
	s114 += "y"

	var s115 = "x115"
	s115 += "y"

	var s116 = "x116"
	s116 += "y"

	var s117 = "x117"
	s117 += "y"

	var s118 = "x118"
	s118 += "y"

	var s119 = "x119"
	s119 += "y"

	var s120 = "x120"
	s120 += "y"

	var s121 = "x121"
	s121 += "y"

	var s122 = "x122"
	s122 += "y"

	var s123 = "x123"
	s123 += "y"

	var s124 = "x124"
	s124 += "y"

	var s125 = "x125"
	s125 += "y"

	var s126 = "x126"
	s126 += "y"

	var s127 = "x127"
	s127 += "y"

	var s128 = "x128"
	s128 += "y"

	var s129 = "x129"
	s129 += "y"

	var s130 = "x130"
	s130 += "y"

	var s131 = "x131"
	s131 += "y"

	var s132 = "x132"
	s132 += "y"

	var s133 = "x133"
	s133 += "y"

	var s134 = "x134"
	s134 += "y"

	var s135 = "x135"
	s135 += "y"

	var s136 = "x136"
	s136 += "y"

	var s137 = "x137"
	s137 += "y"

	var s138 = "x138"
	s138 += "y"

	var s139 = "x139"
	s139 += "y"

	var s140 = "x140"
	s140 += "y"

	var s141 = "x141"
	s141 += "y"

	var s142 = "x142"
	s142 += "y"

	var s143 = "x143"
	s143 += "y"

	var s144 = "x144"
	s144 += "y"

	var s145 = "x145"
	s145 += "y"

	var s146 = "x146"
	s146 += "y"

	var s147 = "x147"
	s147 += "y"

	var s148 = "x148"
	s148 += "y"

	var s149 = "x149"
	s149 += "y"

	var s150 = "x150"
	s150 += "y"

	var s151 = "x151"
	s151 += "y"

	var s152 = "x152"
	s152 += "y"

	var s153 = "x153"
	s153 += "y"

	var s154 = "x154"
	s154 += "y"

	var s155 = "x155"
	s155 += "y"

	var s156 = "x156"
	s156 += "y"

	var s157 = "x157"
	s157 += "y"

	var s158 = "x158"
	s158 += "y"

	var s159 = "x159"
	s159 += "y"

	var s160 = "x160"
	s160 += "y"

	var s161 = "x161"
	s161 += "y"

	var s162 = "x162"
	s162 += "y"

	var s163 = "x163"
	s163 += "y"

	var s164 = "x164"
	s164 += "y"

	var s165 = "x165"
	s165 += "y"

	var s166 = "x166"
	s166 += "y"

	var s167 = "x167"
	s167 += "y"

	var s168 = "x168"
	s168 += "y"

	var s169 = "x169"
	s169 += "y"

	var s170 = "x170"
	s170 += "y"

	var s171 = "x171"
	s171 += "y"

	var s172 = "x172"
	s172 += "y"

	var s173 = "x173"
	s173 += "y"

	var s174 = "x174"
	s174 += "y"

	var s175 = "x175"
	s175 += "y"

	var s176 = "x176"
	s176 += "y"

	var s177 = "x177"
	s177 += "y"

	var s178 = "x178"
	s178 += "y"

	var s179 = "x179"
	s179 += "y"

	var s180 = "x180"
	s180 += "y"

	var s181 = "x181"
	s181 += "y"

	var s182 = "x182"
	s182 += "y"

	var s183 = "x183"
	s183 += "y"

	var s184 = "x184"
	s184 += "y"

	var s185 = "x185"
	s185 += "y"

	var s186 = "x186"
	s186 += "y"

	var s187 = "x187"
	s187 += "y"

	var s188 = "x188"
	s188 += "y"

	var s189 = "x189"
	s189 += "y"

	var s190 = "x190"
	s190 += "y"

	var s191 = "x191"
	s191 += "y"

	var s192 = "x192"
	s192 += "y"

	var s193 = "x193"
	s193 += "y"

	var s194 = "x194"
	s194 += "y"

	var s195 = "x195"
	s195 += "y"

	var s196 = "x196"
	s196 += "y"

	var s197 = "x197"
	s197 += "y"

	var s198 = "x198"
	s198 += "y"

	var s199 = "x199"
	s199 += "y"

	var s200 = "x200"
	s200 += "y"

	var s201 = "x201"
	s201 += "y"

	var s202 = "x202"
	s202 += "y"

	var s203 = "x203"
	s203 += "y"

	var s204 = "x204"
	s204 += "y"

	var s205 = "x205"
	s205 += "y"

	var s206 = "x206"
	s206 += "y"

	var s207 = "x207"
	s207 += "y"

	var s208 = "x208"
	s208 += "y"

	var s209 = "x209"
	s209 += "y"

	var s210 = "x210"
	s210 += "y"

	var s211 = "x211"
	s211 += "y"

	var s212 = "x212"
	s212 += "y"

	var s213 = "x213"
	s213 += "y"

	var s214 = "x214"
	s214 += "y"

	var s215 = "x215"
	s215 += "y"

	var s216 = "x216"
	s216 += "y"

	var s217 = "x217"
	s217 += "y"

	var s218 = "x218"
	s218 += "y"

	var s219 = "x219"
	s219 += "y"

	var s220 = "x220"
	s220 += "y"

	var s221 = "x221"
	s221 += "y"

	var s222 = "x222"
	s222 += "y"

	var s223 = "x223"
	s223 += "y"

	var s224 = "x224"
	s224 += "y"

	var s225 = "x225"
	s225 += "y"

	var s226 = "x226"
	s226 += "y"

	var s227 = "x227"
	s227 += "y"

	var s228 = "x228"
	s228 += "y"

	var s229 = "x229"
	s229 += "y"

	var s230 = "x230"
	s230 += "y"

	var s231 = "x231"
	s231 += "y"

	var s232 = "x232"
	s232 += "y"

	var s233 = "x233"
	s233 += "y"

	var s234 = "x234"
	s234 += "y"

	var s235 = "x235"
	s235 += "y"

	var s236 = "x236"
	s236 += "y"

	var s237 = "x237"
	s237 += "y"

	var s238 = "x238"
	s238 += "y"

	var s239 = "x239"
	s239 += "y"

	var s240 = "x240"
	s240 += "y"

	var s241 = "x241"
	s241 += "y"

	var s242 = "x242"
	s242 += "y"

	var s243 = "x243"
	s243 += "y"

	var s244 = "x244"
	s244 += "y"

	var s245 = "x245"
	s245 += "y"

	var s246 = "x246"
	s246 += "y"

	var s247 = "x247"
	s247 += "y"

	var s248 = "x248"
	s248 += "y"

	var s249 = "x249"
	s249 += "y"

	var s250 = "x250"
	s250 += "y"

	var s251 = "x251"
	s251 += "y"

	var s252 = "x252"
	s252 += "y"

	var s253 = "x253"
	s253 += "y"

	var s254 = "x254"
	s254 += "y"

	var s255 = "x255"
	s255 += "y"

	var s256 = "x256"
	s256 += "y"

	var s257 = "x257"
	s257 += "y"

	var s258 = "x258"
	s258 += "y"

	var s259 = "x259"
	s259 += "y"

	var all = ""
	all += s0
	all += s1
	all += s2
	all += s3
	all += s4
	all += s5
	all += s6
	all += s7
	all += s8
	all += s9
	all += s10
	all += s11
	all += s12
	all += s13
	all += s14
	all += s15
	all += s16
	all += s17
	all += s18
	all += s19
	all += s20
	all += s21
	all += s22
	all += s23
	all += s24
	all += s25
	all += s26
	all += s27
	all += s28
	all += s29
	all += s30
	all += s31
	all += s32
	all += s33
	all += s34
	all += s35
	all += s36
	all += s37
	all += s38
	all += s39
	all += s40
	all += s41
	all += s42
	all += s43
	all += s44
	all += s45
	all += s46
	all += s47
	all += s48
	all += s49
	all += s50
	all += s51
	all += s52
	all += s53
	all += s54
	all += s55
	all += s56
	all += s57
	all += s58
	all += s59
	all += s60
	all += s61
	all += s62
	all += s63
	all += s64
	all += s65
	all += s66
	all += s67
	all += s68
	all += s69
	all += s70
	all += s71
	all += s72
	all += s73
	all += s74
	all += s75
	all += s76
	all += s77
	all += s78
	all += s79
	all += s80
	all += s81
	all += s82
	all += s83
	all += s84
	all += s85
	all += s86
	all += s87
	all += s88
	all += s89
	all += s90
	all += s91
	all += s92
	all += s93
	all += s94
	all += s95
	all += s96
	all += s97
	all += s98
	all += s99
	all += s100
	all += s101
	all += s102
	all += s103
	all += s104
	all += s105
	all += s106
	all += s107
	all += s108
	all += s109
	all += s110
	all += s111
	all += s112
	all += s113
	all += s114
	all += s115
	all += s116
	all += s117
	all += s118
	all += s119
	all += s120
	all += s121
	all += s122
	all += s123
	all += s124
	all += s125
	all += s126
	all += s127
	all += s128
	all += s129
	all += s130
	all += s131
	all += s132
	all += s133
	all += s134
	all += s135
	all += s136
	all += s137
	all += s138
	all += s139
	all += s140
	all += s141
	all += s142
	all += s143
	all += s144
	all += s145
	all += s146
	all += s147
	all += s148
	all += s149
	all += s150
	all += s151
	all += s152
	all += s153
	all += s154
	all += s155
	all += s156
	all += s157
	all += s158
	all += s159
	all += s160
	all += s161
	all += s162
	all += s163
	all += s164
	all += s165
	all += s166
	all += s167
	all += s168
	all += s169
	all += s170
	all += s171
	all += s172
	all += s173
	all += s174
	all += s175
	all += s176
	all += s177
	all += s178
	all += s179
	all += s180
	all += s181
	all += s182
	all += s183
	all += s184
	all += s185
	all += s186
	all += s187
	all += s188
	all += s189
	all += s190
	all += s191
	all += s192
	all += s193
	all += s194
	all += s195
	all += s196
	all += s197
	all += s198
	all += s199
	all += s200
	all += s201
	all += s202
	all += s203
	all += s204
	all += s205
	all += s206
	all += s207
	all += s208
	all += s209
	all += s210
	all += s211
	all += s212
	all += s213
	all += s214
	all += s215
	all += s216
	all += s217
	all += s218
	all += s219
	all += s220
	all += s221
	all += s222
	all += s223
	all += s224
	all += s225
	all += s226
	all += s227
	all += s228
	all += s229
	all += s230
	all += s231
	all += s232
	all += s233
	all += s234
	all += s235
	all += s236
	all += s237
	all += s238
	all += s239
	all += s240
	all += s241
	all += s242
	all += s243
	all += s244
	all += s245
	all += s246
	all += s247
	all += s248
	all += s249
	all += s250
	all += s251
	all += s252
	all += s253
	all += s254
	all += s255
	all += s256
	all += s257
	all += s258
	all += s259
	print(all.length())
}
// expect-exit: 0
// expect-stdout: 26
// expect-stdout: v0
// expect-stdout: v69
// expect-stdout: none
// expect-stdout: 1
// expect-stdout: 1190

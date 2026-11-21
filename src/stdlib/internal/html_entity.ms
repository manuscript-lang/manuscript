// Named character references for `@std/data/html.ms`, from the HTML5 table in
// golang.org/x/net/html/entity.go plus `nGt;` and `nLt;`, which HTML5 defines and that
// table omits. Names are sorted bytewise so `entity_index` can bisect them.
// `entity_text` gives the text a reference decodes to: one scalar, or two for 93 of
// them.

// The number of named references.
ENTITY_COUNT := 2231

// Finds `name` (with its `;` when it has one) and returns its index, or -1.
export fn entity_index(name: String) Int:
	var low = 0
	var high = ENTITY_COUNT

	while low < high:
		mid := (low + high) / 2
		probe := entity_name(mid)
		if probe == name: return mid

		if probe < name:
			low = mid + 1
		else:
			high = mid

	return -1

// The sorted names and their texts are balanced `if` trees over the index: a `match`
// this large is far slower, and a lookup bisects, so each lookup stays at about 11
// tests. Workaround for issue #4635; replace the trees with a flat `match` once it is
// fixed.
fn entity_name(index: Int) String:
	if index < 1115:
		if index < 557:
			if index < 278:
				if index < 139:
					if index < 69:
						if index < 34:
							if index < 17:
								if index < 8:
									match index:
										0: return "AElig"
										1: return "AElig;"
										2: return "AMP"
										3: return "AMP;"
										4: return "Aacute"
										5: return "Aacute;"
										6: return "Abreve;"
										7: return "Acirc"
										_: return ""
								else:
									if index < 12:
										match index:
											8: return "Acirc;"
											9: return "Acy;"
											10: return "Afr;"
											11: return "Agrave"
											_: return ""
									else:
										match index:
											12: return "Agrave;"
											13: return "Alpha;"
											14: return "Amacr;"
											15: return "And;"
											16: return "Aogon;"
											_: return ""
							else:
								if index < 25:
									match index:
										17: return "Aopf;"
										18: return "ApplyFunction;"
										19: return "Aring"
										20: return "Aring;"
										21: return "Ascr;"
										22: return "Assign;"
										23: return "Atilde"
										24: return "Atilde;"
										_: return ""
								else:
									if index < 29:
										match index:
											25: return "Auml"
											26: return "Auml;"
											27: return "Backslash;"
											28: return "Barv;"
											_: return ""
									else:
										match index:
											29: return "Barwed;"
											30: return "Bcy;"
											31: return "Because;"
											32: return "Bernoullis;"
											33: return "Beta;"
											_: return ""
						else:
							if index < 51:
								if index < 42:
									match index:
										34: return "Bfr;"
										35: return "Bopf;"
										36: return "Breve;"
										37: return "Bscr;"
										38: return "Bumpeq;"
										39: return "CHcy;"
										40: return "COPY"
										41: return "COPY;"
										_: return ""
								else:
									if index < 46:
										match index:
											42: return "Cacute;"
											43: return "Cap;"
											44: return "CapitalDifferentialD;"
											45: return "Cayleys;"
											_: return ""
									else:
										match index:
											46: return "Ccaron;"
											47: return "Ccedil"
											48: return "Ccedil;"
											49: return "Ccirc;"
											50: return "Cconint;"
											_: return ""
							else:
								if index < 60:
									if index < 55:
										match index:
											51: return "Cdot;"
											52: return "Cedilla;"
											53: return "CenterDot;"
											54: return "Cfr;"
											_: return ""
									else:
										match index:
											55: return "Chi;"
											56: return "CircleDot;"
											57: return "CircleMinus;"
											58: return "CirclePlus;"
											59: return "CircleTimes;"
											_: return ""
								else:
									if index < 64:
										match index:
											60: return "ClockwiseContourIntegral;"
											61: return "CloseCurlyDoubleQuote;"
											62: return "CloseCurlyQuote;"
											63: return "Colon;"
											_: return ""
									else:
										match index:
											64: return "Colone;"
											65: return "Congruent;"
											66: return "Conint;"
											67: return "ContourIntegral;"
											68: return "Copf;"
											_: return ""
					else:
						if index < 104:
							if index < 86:
								if index < 77:
									match index:
										69: return "Coproduct;"
										70: return "CounterClockwiseContourIntegral;"
										71: return "Cross;"
										72: return "Cscr;"
										73: return "Cup;"
										74: return "CupCap;"
										75: return "DD;"
										76: return "DDotrahd;"
										_: return ""
								else:
									if index < 81:
										match index:
											77: return "DJcy;"
											78: return "DScy;"
											79: return "DZcy;"
											80: return "Dagger;"
											_: return ""
									else:
										match index:
											81: return "Darr;"
											82: return "Dashv;"
											83: return "Dcaron;"
											84: return "Dcy;"
											85: return "Del;"
											_: return ""
							else:
								if index < 95:
									if index < 90:
										match index:
											86: return "Delta;"
											87: return "Dfr;"
											88: return "DiacriticalAcute;"
											89: return "DiacriticalDot;"
											_: return ""
									else:
										match index:
											90: return "DiacriticalDoubleAcute;"
											91: return "DiacriticalGrave;"
											92: return "DiacriticalTilde;"
											93: return "Diamond;"
											94: return "DifferentialD;"
											_: return ""
								else:
									if index < 99:
										match index:
											95: return "Dopf;"
											96: return "Dot;"
											97: return "DotDot;"
											98: return "DotEqual;"
											_: return ""
									else:
										match index:
											99: return "DoubleContourIntegral;"
											100: return "DoubleDot;"
											101: return "DoubleDownArrow;"
											102: return "DoubleLeftArrow;"
											103: return "DoubleLeftRightArrow;"
											_: return ""
						else:
							if index < 121:
								if index < 112:
									match index:
										104: return "DoubleLeftTee;"
										105: return "DoubleLongLeftArrow;"
										106: return "DoubleLongLeftRightArrow;"
										107: return "DoubleLongRightArrow;"
										108: return "DoubleRightArrow;"
										109: return "DoubleRightTee;"
										110: return "DoubleUpArrow;"
										111: return "DoubleUpDownArrow;"
										_: return ""
								else:
									if index < 116:
										match index:
											112: return "DoubleVerticalBar;"
											113: return "DownArrow;"
											114: return "DownArrowBar;"
											115: return "DownArrowUpArrow;"
											_: return ""
									else:
										match index:
											116: return "DownBreve;"
											117: return "DownLeftRightVector;"
											118: return "DownLeftTeeVector;"
											119: return "DownLeftVector;"
											120: return "DownLeftVectorBar;"
											_: return ""
							else:
								if index < 130:
									if index < 125:
										match index:
											121: return "DownRightTeeVector;"
											122: return "DownRightVector;"
											123: return "DownRightVectorBar;"
											124: return "DownTee;"
											_: return ""
									else:
										match index:
											125: return "DownTeeArrow;"
											126: return "Downarrow;"
											127: return "Dscr;"
											128: return "Dstrok;"
											129: return "ENG;"
											_: return ""
								else:
									if index < 134:
										match index:
											130: return "ETH"
											131: return "ETH;"
											132: return "Eacute"
											133: return "Eacute;"
											_: return ""
									else:
										match index:
											134: return "Ecaron;"
											135: return "Ecirc"
											136: return "Ecirc;"
											137: return "Ecy;"
											138: return "Edot;"
											_: return ""
				else:
					if index < 208:
						if index < 173:
							if index < 156:
								if index < 147:
									match index:
										139: return "Efr;"
										140: return "Egrave"
										141: return "Egrave;"
										142: return "Element;"
										143: return "Emacr;"
										144: return "EmptySmallSquare;"
										145: return "EmptyVerySmallSquare;"
										146: return "Eogon;"
										_: return ""
								else:
									if index < 151:
										match index:
											147: return "Eopf;"
											148: return "Epsilon;"
											149: return "Equal;"
											150: return "EqualTilde;"
											_: return ""
									else:
										match index:
											151: return "Equilibrium;"
											152: return "Escr;"
											153: return "Esim;"
											154: return "Eta;"
											155: return "Euml"
											_: return ""
							else:
								if index < 164:
									match index:
										156: return "Euml;"
										157: return "Exists;"
										158: return "ExponentialE;"
										159: return "Fcy;"
										160: return "Ffr;"
										161: return "FilledSmallSquare;"
										162: return "FilledVerySmallSquare;"
										163: return "Fopf;"
										_: return ""
								else:
									if index < 168:
										match index:
											164: return "ForAll;"
											165: return "Fouriertrf;"
											166: return "Fscr;"
											167: return "GJcy;"
											_: return ""
									else:
										match index:
											168: return "GT"
											169: return "GT;"
											170: return "Gamma;"
											171: return "Gammad;"
											172: return "Gbreve;"
											_: return ""
						else:
							if index < 190:
								if index < 181:
									match index:
										173: return "Gcedil;"
										174: return "Gcirc;"
										175: return "Gcy;"
										176: return "Gdot;"
										177: return "Gfr;"
										178: return "Gg;"
										179: return "Gopf;"
										180: return "GreaterEqual;"
										_: return ""
								else:
									if index < 185:
										match index:
											181: return "GreaterEqualLess;"
											182: return "GreaterFullEqual;"
											183: return "GreaterGreater;"
											184: return "GreaterLess;"
											_: return ""
									else:
										match index:
											185: return "GreaterSlantEqual;"
											186: return "GreaterTilde;"
											187: return "Gscr;"
											188: return "Gt;"
											189: return "HARDcy;"
											_: return ""
							else:
								if index < 199:
									if index < 194:
										match index:
											190: return "Hacek;"
											191: return "Hat;"
											192: return "Hcirc;"
											193: return "Hfr;"
											_: return ""
									else:
										match index:
											194: return "HilbertSpace;"
											195: return "Hopf;"
											196: return "HorizontalLine;"
											197: return "Hscr;"
											198: return "Hstrok;"
											_: return ""
								else:
									if index < 203:
										match index:
											199: return "HumpDownHump;"
											200: return "HumpEqual;"
											201: return "IEcy;"
											202: return "IJlig;"
											_: return ""
									else:
										match index:
											203: return "IOcy;"
											204: return "Iacute"
											205: return "Iacute;"
											206: return "Icirc"
											207: return "Icirc;"
											_: return ""
					else:
						if index < 243:
							if index < 225:
								if index < 216:
									match index:
										208: return "Icy;"
										209: return "Idot;"
										210: return "Ifr;"
										211: return "Igrave"
										212: return "Igrave;"
										213: return "Im;"
										214: return "Imacr;"
										215: return "ImaginaryI;"
										_: return ""
								else:
									if index < 220:
										match index:
											216: return "Implies;"
											217: return "Int;"
											218: return "Integral;"
											219: return "Intersection;"
											_: return ""
									else:
										match index:
											220: return "InvisibleComma;"
											221: return "InvisibleTimes;"
											222: return "Iogon;"
											223: return "Iopf;"
											224: return "Iota;"
											_: return ""
							else:
								if index < 234:
									if index < 229:
										match index:
											225: return "Iscr;"
											226: return "Itilde;"
											227: return "Iukcy;"
											228: return "Iuml"
											_: return ""
									else:
										match index:
											229: return "Iuml;"
											230: return "Jcirc;"
											231: return "Jcy;"
											232: return "Jfr;"
											233: return "Jopf;"
											_: return ""
								else:
									if index < 238:
										match index:
											234: return "Jscr;"
											235: return "Jsercy;"
											236: return "Jukcy;"
											237: return "KHcy;"
											_: return ""
									else:
										match index:
											238: return "KJcy;"
											239: return "Kappa;"
											240: return "Kcedil;"
											241: return "Kcy;"
											242: return "Kfr;"
											_: return ""
						else:
							if index < 260:
								if index < 251:
									match index:
										243: return "Kopf;"
										244: return "Kscr;"
										245: return "LJcy;"
										246: return "LT"
										247: return "LT;"
										248: return "Lacute;"
										249: return "Lambda;"
										250: return "Lang;"
										_: return ""
								else:
									if index < 255:
										match index:
											251: return "Laplacetrf;"
											252: return "Larr;"
											253: return "Lcaron;"
											254: return "Lcedil;"
											_: return ""
									else:
										match index:
											255: return "Lcy;"
											256: return "LeftAngleBracket;"
											257: return "LeftArrow;"
											258: return "LeftArrowBar;"
											259: return "LeftArrowRightArrow;"
											_: return ""
							else:
								if index < 269:
									if index < 264:
										match index:
											260: return "LeftCeiling;"
											261: return "LeftDoubleBracket;"
											262: return "LeftDownTeeVector;"
											263: return "LeftDownVector;"
											_: return ""
									else:
										match index:
											264: return "LeftDownVectorBar;"
											265: return "LeftFloor;"
											266: return "LeftRightArrow;"
											267: return "LeftRightVector;"
											268: return "LeftTee;"
											_: return ""
								else:
									if index < 273:
										match index:
											269: return "LeftTeeArrow;"
											270: return "LeftTeeVector;"
											271: return "LeftTriangle;"
											272: return "LeftTriangleBar;"
											_: return ""
									else:
										match index:
											273: return "LeftTriangleEqual;"
											274: return "LeftUpDownVector;"
											275: return "LeftUpTeeVector;"
											276: return "LeftUpVector;"
											277: return "LeftUpVectorBar;"
											_: return ""
			else:
				if index < 417:
					if index < 347:
						if index < 312:
							if index < 295:
								if index < 286:
									match index:
										278: return "LeftVector;"
										279: return "LeftVectorBar;"
										280: return "Leftarrow;"
										281: return "Leftrightarrow;"
										282: return "LessEqualGreater;"
										283: return "LessFullEqual;"
										284: return "LessGreater;"
										285: return "LessLess;"
										_: return ""
								else:
									if index < 290:
										match index:
											286: return "LessSlantEqual;"
											287: return "LessTilde;"
											288: return "Lfr;"
											289: return "Ll;"
											_: return ""
									else:
										match index:
											290: return "Lleftarrow;"
											291: return "Lmidot;"
											292: return "LongLeftArrow;"
											293: return "LongLeftRightArrow;"
											294: return "LongRightArrow;"
											_: return ""
							else:
								if index < 303:
									match index:
										295: return "Longleftarrow;"
										296: return "Longleftrightarrow;"
										297: return "Longrightarrow;"
										298: return "Lopf;"
										299: return "LowerLeftArrow;"
										300: return "LowerRightArrow;"
										301: return "Lscr;"
										302: return "Lsh;"
										_: return ""
								else:
									if index < 307:
										match index:
											303: return "Lstrok;"
											304: return "Lt;"
											305: return "Map;"
											306: return "Mcy;"
											_: return ""
									else:
										match index:
											307: return "MediumSpace;"
											308: return "Mellintrf;"
											309: return "Mfr;"
											310: return "MinusPlus;"
											311: return "Mopf;"
											_: return ""
						else:
							if index < 329:
								if index < 320:
									match index:
										312: return "Mscr;"
										313: return "Mu;"
										314: return "NJcy;"
										315: return "Nacute;"
										316: return "Ncaron;"
										317: return "Ncedil;"
										318: return "Ncy;"
										319: return "NegativeMediumSpace;"
										_: return ""
								else:
									if index < 324:
										match index:
											320: return "NegativeThickSpace;"
											321: return "NegativeThinSpace;"
											322: return "NegativeVeryThinSpace;"
											323: return "NestedGreaterGreater;"
											_: return ""
									else:
										match index:
											324: return "NestedLessLess;"
											325: return "NewLine;"
											326: return "Nfr;"
											327: return "NoBreak;"
											328: return "NonBreakingSpace;"
											_: return ""
							else:
								if index < 338:
									if index < 333:
										match index:
											329: return "Nopf;"
											330: return "Not;"
											331: return "NotCongruent;"
											332: return "NotCupCap;"
											_: return ""
									else:
										match index:
											333: return "NotDoubleVerticalBar;"
											334: return "NotElement;"
											335: return "NotEqual;"
											336: return "NotEqualTilde;"
											337: return "NotExists;"
											_: return ""
								else:
									if index < 342:
										match index:
											338: return "NotGreater;"
											339: return "NotGreaterEqual;"
											340: return "NotGreaterFullEqual;"
											341: return "NotGreaterGreater;"
											_: return ""
									else:
										match index:
											342: return "NotGreaterLess;"
											343: return "NotGreaterSlantEqual;"
											344: return "NotGreaterTilde;"
											345: return "NotHumpDownHump;"
											346: return "NotHumpEqual;"
											_: return ""
					else:
						if index < 382:
							if index < 364:
								if index < 355:
									match index:
										347: return "NotLeftTriangle;"
										348: return "NotLeftTriangleBar;"
										349: return "NotLeftTriangleEqual;"
										350: return "NotLess;"
										351: return "NotLessEqual;"
										352: return "NotLessGreater;"
										353: return "NotLessLess;"
										354: return "NotLessSlantEqual;"
										_: return ""
								else:
									if index < 359:
										match index:
											355: return "NotLessTilde;"
											356: return "NotNestedGreaterGreater;"
											357: return "NotNestedLessLess;"
											358: return "NotPrecedes;"
											_: return ""
									else:
										match index:
											359: return "NotPrecedesEqual;"
											360: return "NotPrecedesSlantEqual;"
											361: return "NotReverseElement;"
											362: return "NotRightTriangle;"
											363: return "NotRightTriangleBar;"
											_: return ""
							else:
								if index < 373:
									if index < 368:
										match index:
											364: return "NotRightTriangleEqual;"
											365: return "NotSquareSubset;"
											366: return "NotSquareSubsetEqual;"
											367: return "NotSquareSuperset;"
											_: return ""
									else:
										match index:
											368: return "NotSquareSupersetEqual;"
											369: return "NotSubset;"
											370: return "NotSubsetEqual;"
											371: return "NotSucceeds;"
											372: return "NotSucceedsEqual;"
											_: return ""
								else:
									if index < 377:
										match index:
											373: return "NotSucceedsSlantEqual;"
											374: return "NotSucceedsTilde;"
											375: return "NotSuperset;"
											376: return "NotSupersetEqual;"
											_: return ""
									else:
										match index:
											377: return "NotTilde;"
											378: return "NotTildeEqual;"
											379: return "NotTildeFullEqual;"
											380: return "NotTildeTilde;"
											381: return "NotVerticalBar;"
											_: return ""
						else:
							if index < 399:
								if index < 390:
									match index:
										382: return "Nscr;"
										383: return "Ntilde"
										384: return "Ntilde;"
										385: return "Nu;"
										386: return "OElig;"
										387: return "Oacute"
										388: return "Oacute;"
										389: return "Ocirc"
										_: return ""
								else:
									if index < 394:
										match index:
											390: return "Ocirc;"
											391: return "Ocy;"
											392: return "Odblac;"
											393: return "Ofr;"
											_: return ""
									else:
										match index:
											394: return "Ograve"
											395: return "Ograve;"
											396: return "Omacr;"
											397: return "Omega;"
											398: return "Omicron;"
											_: return ""
							else:
								if index < 408:
									if index < 403:
										match index:
											399: return "Oopf;"
											400: return "OpenCurlyDoubleQuote;"
											401: return "OpenCurlyQuote;"
											402: return "Or;"
											_: return ""
									else:
										match index:
											403: return "Oscr;"
											404: return "Oslash"
											405: return "Oslash;"
											406: return "Otilde"
											407: return "Otilde;"
											_: return ""
								else:
									if index < 412:
										match index:
											408: return "Otimes;"
											409: return "Ouml"
											410: return "Ouml;"
											411: return "OverBar;"
											_: return ""
									else:
										match index:
											412: return "OverBrace;"
											413: return "OverBracket;"
											414: return "OverParenthesis;"
											415: return "PartialD;"
											416: return "Pcy;"
											_: return ""
				else:
					if index < 487:
						if index < 452:
							if index < 434:
								if index < 425:
									match index:
										417: return "Pfr;"
										418: return "Phi;"
										419: return "Pi;"
										420: return "PlusMinus;"
										421: return "Poincareplane;"
										422: return "Popf;"
										423: return "Pr;"
										424: return "Precedes;"
										_: return ""
								else:
									if index < 429:
										match index:
											425: return "PrecedesEqual;"
											426: return "PrecedesSlantEqual;"
											427: return "PrecedesTilde;"
											428: return "Prime;"
											_: return ""
									else:
										match index:
											429: return "Product;"
											430: return "Proportion;"
											431: return "Proportional;"
											432: return "Pscr;"
											433: return "Psi;"
											_: return ""
							else:
								if index < 443:
									if index < 438:
										match index:
											434: return "QUOT"
											435: return "QUOT;"
											436: return "Qfr;"
											437: return "Qopf;"
											_: return ""
									else:
										match index:
											438: return "Qscr;"
											439: return "RBarr;"
											440: return "REG"
											441: return "REG;"
											442: return "Racute;"
											_: return ""
								else:
									if index < 447:
										match index:
											443: return "Rang;"
											444: return "Rarr;"
											445: return "Rarrtl;"
											446: return "Rcaron;"
											_: return ""
									else:
										match index:
											447: return "Rcedil;"
											448: return "Rcy;"
											449: return "Re;"
											450: return "ReverseElement;"
											451: return "ReverseEquilibrium;"
											_: return ""
						else:
							if index < 469:
								if index < 460:
									match index:
										452: return "ReverseUpEquilibrium;"
										453: return "Rfr;"
										454: return "Rho;"
										455: return "RightAngleBracket;"
										456: return "RightArrow;"
										457: return "RightArrowBar;"
										458: return "RightArrowLeftArrow;"
										459: return "RightCeiling;"
										_: return ""
								else:
									if index < 464:
										match index:
											460: return "RightDoubleBracket;"
											461: return "RightDownTeeVector;"
											462: return "RightDownVector;"
											463: return "RightDownVectorBar;"
											_: return ""
									else:
										match index:
											464: return "RightFloor;"
											465: return "RightTee;"
											466: return "RightTeeArrow;"
											467: return "RightTeeVector;"
											468: return "RightTriangle;"
											_: return ""
							else:
								if index < 478:
									if index < 473:
										match index:
											469: return "RightTriangleBar;"
											470: return "RightTriangleEqual;"
											471: return "RightUpDownVector;"
											472: return "RightUpTeeVector;"
											_: return ""
									else:
										match index:
											473: return "RightUpVector;"
											474: return "RightUpVectorBar;"
											475: return "RightVector;"
											476: return "RightVectorBar;"
											477: return "Rightarrow;"
											_: return ""
								else:
									if index < 482:
										match index:
											478: return "Ropf;"
											479: return "RoundImplies;"
											480: return "Rrightarrow;"
											481: return "Rscr;"
											_: return ""
									else:
										match index:
											482: return "Rsh;"
											483: return "RuleDelayed;"
											484: return "SHCHcy;"
											485: return "SHcy;"
											486: return "SOFTcy;"
											_: return ""
					else:
						if index < 522:
							if index < 504:
								if index < 495:
									match index:
										487: return "Sacute;"
										488: return "Sc;"
										489: return "Scaron;"
										490: return "Scedil;"
										491: return "Scirc;"
										492: return "Scy;"
										493: return "Sfr;"
										494: return "ShortDownArrow;"
										_: return ""
								else:
									if index < 499:
										match index:
											495: return "ShortLeftArrow;"
											496: return "ShortRightArrow;"
											497: return "ShortUpArrow;"
											498: return "Sigma;"
											_: return ""
									else:
										match index:
											499: return "SmallCircle;"
											500: return "Sopf;"
											501: return "Sqrt;"
											502: return "Square;"
											503: return "SquareIntersection;"
											_: return ""
							else:
								if index < 513:
									if index < 508:
										match index:
											504: return "SquareSubset;"
											505: return "SquareSubsetEqual;"
											506: return "SquareSuperset;"
											507: return "SquareSupersetEqual;"
											_: return ""
									else:
										match index:
											508: return "SquareUnion;"
											509: return "Sscr;"
											510: return "Star;"
											511: return "Sub;"
											512: return "Subset;"
											_: return ""
								else:
									if index < 517:
										match index:
											513: return "SubsetEqual;"
											514: return "Succeeds;"
											515: return "SucceedsEqual;"
											516: return "SucceedsSlantEqual;"
											_: return ""
									else:
										match index:
											517: return "SucceedsTilde;"
											518: return "SuchThat;"
											519: return "Sum;"
											520: return "Sup;"
											521: return "Superset;"
											_: return ""
						else:
							if index < 539:
								if index < 530:
									match index:
										522: return "SupersetEqual;"
										523: return "Supset;"
										524: return "THORN"
										525: return "THORN;"
										526: return "TRADE;"
										527: return "TSHcy;"
										528: return "TScy;"
										529: return "Tab;"
										_: return ""
								else:
									if index < 534:
										match index:
											530: return "Tau;"
											531: return "Tcaron;"
											532: return "Tcedil;"
											533: return "Tcy;"
											_: return ""
									else:
										match index:
											534: return "Tfr;"
											535: return "Therefore;"
											536: return "Theta;"
											537: return "ThickSpace;"
											538: return "ThinSpace;"
											_: return ""
							else:
								if index < 548:
									if index < 543:
										match index:
											539: return "Tilde;"
											540: return "TildeEqual;"
											541: return "TildeFullEqual;"
											542: return "TildeTilde;"
											_: return ""
									else:
										match index:
											543: return "Topf;"
											544: return "TripleDot;"
											545: return "Tscr;"
											546: return "Tstrok;"
											547: return "Uacute"
											_: return ""
								else:
									if index < 552:
										match index:
											548: return "Uacute;"
											549: return "Uarr;"
											550: return "Uarrocir;"
											551: return "Ubrcy;"
											_: return ""
									else:
										match index:
											552: return "Ubreve;"
											553: return "Ucirc"
											554: return "Ucirc;"
											555: return "Ucy;"
											556: return "Udblac;"
											_: return ""
		else:
			if index < 836:
				if index < 696:
					if index < 626:
						if index < 591:
							if index < 574:
								if index < 565:
									match index:
										557: return "Ufr;"
										558: return "Ugrave"
										559: return "Ugrave;"
										560: return "Umacr;"
										561: return "UnderBar;"
										562: return "UnderBrace;"
										563: return "UnderBracket;"
										564: return "UnderParenthesis;"
										_: return ""
								else:
									if index < 569:
										match index:
											565: return "Union;"
											566: return "UnionPlus;"
											567: return "Uogon;"
											568: return "Uopf;"
											_: return ""
									else:
										match index:
											569: return "UpArrow;"
											570: return "UpArrowBar;"
											571: return "UpArrowDownArrow;"
											572: return "UpDownArrow;"
											573: return "UpEquilibrium;"
											_: return ""
							else:
								if index < 582:
									match index:
										574: return "UpTee;"
										575: return "UpTeeArrow;"
										576: return "Uparrow;"
										577: return "Updownarrow;"
										578: return "UpperLeftArrow;"
										579: return "UpperRightArrow;"
										580: return "Upsi;"
										581: return "Upsilon;"
										_: return ""
								else:
									if index < 586:
										match index:
											582: return "Uring;"
											583: return "Uscr;"
											584: return "Utilde;"
											585: return "Uuml"
											_: return ""
									else:
										match index:
											586: return "Uuml;"
											587: return "VDash;"
											588: return "Vbar;"
											589: return "Vcy;"
											590: return "Vdash;"
											_: return ""
						else:
							if index < 608:
								if index < 599:
									match index:
										591: return "Vdashl;"
										592: return "Vee;"
										593: return "Verbar;"
										594: return "Vert;"
										595: return "VerticalBar;"
										596: return "VerticalLine;"
										597: return "VerticalSeparator;"
										598: return "VerticalTilde;"
										_: return ""
								else:
									if index < 603:
										match index:
											599: return "VeryThinSpace;"
											600: return "Vfr;"
											601: return "Vopf;"
											602: return "Vscr;"
											_: return ""
									else:
										match index:
											603: return "Vvdash;"
											604: return "Wcirc;"
											605: return "Wedge;"
											606: return "Wfr;"
											607: return "Wopf;"
											_: return ""
							else:
								if index < 617:
									if index < 612:
										match index:
											608: return "Wscr;"
											609: return "Xfr;"
											610: return "Xi;"
											611: return "Xopf;"
											_: return ""
									else:
										match index:
											612: return "Xscr;"
											613: return "YAcy;"
											614: return "YIcy;"
											615: return "YUcy;"
											616: return "Yacute"
											_: return ""
								else:
									if index < 621:
										match index:
											617: return "Yacute;"
											618: return "Ycirc;"
											619: return "Ycy;"
											620: return "Yfr;"
											_: return ""
									else:
										match index:
											621: return "Yopf;"
											622: return "Yscr;"
											623: return "Yuml;"
											624: return "ZHcy;"
											625: return "Zacute;"
											_: return ""
					else:
						if index < 661:
							if index < 643:
								if index < 634:
									match index:
										626: return "Zcaron;"
										627: return "Zcy;"
										628: return "Zdot;"
										629: return "ZeroWidthSpace;"
										630: return "Zeta;"
										631: return "Zfr;"
										632: return "Zopf;"
										633: return "Zscr;"
										_: return ""
								else:
									if index < 638:
										match index:
											634: return "aacute"
											635: return "aacute;"
											636: return "abreve;"
											637: return "ac;"
											_: return ""
									else:
										match index:
											638: return "acE;"
											639: return "acd;"
											640: return "acirc"
											641: return "acirc;"
											642: return "acute"
											_: return ""
							else:
								if index < 652:
									if index < 647:
										match index:
											643: return "acute;"
											644: return "acy;"
											645: return "aelig"
											646: return "aelig;"
											_: return ""
									else:
										match index:
											647: return "af;"
											648: return "afr;"
											649: return "agrave"
											650: return "agrave;"
											651: return "alefsym;"
											_: return ""
								else:
									if index < 656:
										match index:
											652: return "aleph;"
											653: return "alpha;"
											654: return "amacr;"
											655: return "amalg;"
											_: return ""
									else:
										match index:
											656: return "amp"
											657: return "amp;"
											658: return "and;"
											659: return "andand;"
											660: return "andd;"
											_: return ""
						else:
							if index < 678:
								if index < 669:
									match index:
										661: return "andslope;"
										662: return "andv;"
										663: return "ang;"
										664: return "ange;"
										665: return "angle;"
										666: return "angmsd;"
										667: return "angmsdaa;"
										668: return "angmsdab;"
										_: return ""
								else:
									if index < 673:
										match index:
											669: return "angmsdac;"
											670: return "angmsdad;"
											671: return "angmsdae;"
											672: return "angmsdaf;"
											_: return ""
									else:
										match index:
											673: return "angmsdag;"
											674: return "angmsdah;"
											675: return "angrt;"
											676: return "angrtvb;"
											677: return "angrtvbd;"
											_: return ""
							else:
								if index < 687:
									if index < 682:
										match index:
											678: return "angsph;"
											679: return "angst;"
											680: return "angzarr;"
											681: return "aogon;"
											_: return ""
									else:
										match index:
											682: return "aopf;"
											683: return "ap;"
											684: return "apE;"
											685: return "apacir;"
											686: return "ape;"
											_: return ""
								else:
									if index < 691:
										match index:
											687: return "apid;"
											688: return "apos;"
											689: return "approx;"
											690: return "approxeq;"
											_: return ""
									else:
										match index:
											691: return "aring"
											692: return "aring;"
											693: return "ascr;"
											694: return "ast;"
											695: return "asymp;"
											_: return ""
				else:
					if index < 766:
						if index < 731:
							if index < 713:
								if index < 704:
									match index:
										696: return "asympeq;"
										697: return "atilde"
										698: return "atilde;"
										699: return "auml"
										700: return "auml;"
										701: return "awconint;"
										702: return "awint;"
										703: return "bNot;"
										_: return ""
								else:
									if index < 708:
										match index:
											704: return "backcong;"
											705: return "backepsilon;"
											706: return "backprime;"
											707: return "backsim;"
											_: return ""
									else:
										match index:
											708: return "backsimeq;"
											709: return "barvee;"
											710: return "barwed;"
											711: return "barwedge;"
											712: return "bbrk;"
											_: return ""
							else:
								if index < 722:
									if index < 717:
										match index:
											713: return "bbrktbrk;"
											714: return "bcong;"
											715: return "bcy;"
											716: return "bdquo;"
											_: return ""
									else:
										match index:
											717: return "becaus;"
											718: return "because;"
											719: return "bemptyv;"
											720: return "bepsi;"
											721: return "bernou;"
											_: return ""
								else:
									if index < 726:
										match index:
											722: return "beta;"
											723: return "beth;"
											724: return "between;"
											725: return "bfr;"
											_: return ""
									else:
										match index:
											726: return "bigcap;"
											727: return "bigcirc;"
											728: return "bigcup;"
											729: return "bigodot;"
											730: return "bigoplus;"
											_: return ""
						else:
							if index < 748:
								if index < 739:
									match index:
										731: return "bigotimes;"
										732: return "bigsqcup;"
										733: return "bigstar;"
										734: return "bigtriangledown;"
										735: return "bigtriangleup;"
										736: return "biguplus;"
										737: return "bigvee;"
										738: return "bigwedge;"
										_: return ""
								else:
									if index < 743:
										match index:
											739: return "bkarow;"
											740: return "blacklozenge;"
											741: return "blacksquare;"
											742: return "blacktriangle;"
											_: return ""
									else:
										match index:
											743: return "blacktriangledown;"
											744: return "blacktriangleleft;"
											745: return "blacktriangleright;"
											746: return "blank;"
											747: return "blk12;"
											_: return ""
							else:
								if index < 757:
									if index < 752:
										match index:
											748: return "blk14;"
											749: return "blk34;"
											750: return "block;"
											751: return "bne;"
											_: return ""
									else:
										match index:
											752: return "bnequiv;"
											753: return "bnot;"
											754: return "bopf;"
											755: return "bot;"
											756: return "bottom;"
											_: return ""
								else:
									if index < 761:
										match index:
											757: return "bowtie;"
											758: return "boxDL;"
											759: return "boxDR;"
											760: return "boxDl;"
											_: return ""
									else:
										match index:
											761: return "boxDr;"
											762: return "boxH;"
											763: return "boxHD;"
											764: return "boxHU;"
											765: return "boxHd;"
											_: return ""
					else:
						if index < 801:
							if index < 783:
								if index < 774:
									match index:
										766: return "boxHu;"
										767: return "boxUL;"
										768: return "boxUR;"
										769: return "boxUl;"
										770: return "boxUr;"
										771: return "boxV;"
										772: return "boxVH;"
										773: return "boxVL;"
										_: return ""
								else:
									if index < 778:
										match index:
											774: return "boxVR;"
											775: return "boxVh;"
											776: return "boxVl;"
											777: return "boxVr;"
											_: return ""
									else:
										match index:
											778: return "boxbox;"
											779: return "boxdL;"
											780: return "boxdR;"
											781: return "boxdl;"
											782: return "boxdr;"
											_: return ""
							else:
								if index < 792:
									if index < 787:
										match index:
											783: return "boxh;"
											784: return "boxhD;"
											785: return "boxhU;"
											786: return "boxhd;"
											_: return ""
									else:
										match index:
											787: return "boxhu;"
											788: return "boxminus;"
											789: return "boxplus;"
											790: return "boxtimes;"
											791: return "boxuL;"
											_: return ""
								else:
									if index < 796:
										match index:
											792: return "boxuR;"
											793: return "boxul;"
											794: return "boxur;"
											795: return "boxv;"
											_: return ""
									else:
										match index:
											796: return "boxvH;"
											797: return "boxvL;"
											798: return "boxvR;"
											799: return "boxvh;"
											800: return "boxvl;"
											_: return ""
						else:
							if index < 818:
								if index < 809:
									match index:
										801: return "boxvr;"
										802: return "bprime;"
										803: return "breve;"
										804: return "brvbar"
										805: return "brvbar;"
										806: return "bscr;"
										807: return "bsemi;"
										808: return "bsim;"
										_: return ""
								else:
									if index < 813:
										match index:
											809: return "bsime;"
											810: return "bsol;"
											811: return "bsolb;"
											812: return "bsolhsub;"
											_: return ""
									else:
										match index:
											813: return "bull;"
											814: return "bullet;"
											815: return "bump;"
											816: return "bumpE;"
											817: return "bumpe;"
											_: return ""
							else:
								if index < 827:
									if index < 822:
										match index:
											818: return "bumpeq;"
											819: return "cacute;"
											820: return "cap;"
											821: return "capand;"
											_: return ""
									else:
										match index:
											822: return "capbrcup;"
											823: return "capcap;"
											824: return "capcup;"
											825: return "capdot;"
											826: return "caps;"
											_: return ""
								else:
									if index < 831:
										match index:
											827: return "caret;"
											828: return "caron;"
											829: return "ccaps;"
											830: return "ccaron;"
											_: return ""
									else:
										match index:
											831: return "ccedil"
											832: return "ccedil;"
											833: return "ccirc;"
											834: return "ccups;"
											835: return "ccupssm;"
											_: return ""
			else:
				if index < 975:
					if index < 905:
						if index < 870:
							if index < 853:
								if index < 844:
									match index:
										836: return "cdot;"
										837: return "cedil"
										838: return "cedil;"
										839: return "cemptyv;"
										840: return "cent"
										841: return "cent;"
										842: return "centerdot;"
										843: return "cfr;"
										_: return ""
								else:
									if index < 848:
										match index:
											844: return "chcy;"
											845: return "check;"
											846: return "checkmark;"
											847: return "chi;"
											_: return ""
									else:
										match index:
											848: return "cir;"
											849: return "cirE;"
											850: return "circ;"
											851: return "circeq;"
											852: return "circlearrowleft;"
											_: return ""
							else:
								if index < 861:
									match index:
										853: return "circlearrowright;"
										854: return "circledR;"
										855: return "circledS;"
										856: return "circledast;"
										857: return "circledcirc;"
										858: return "circleddash;"
										859: return "cire;"
										860: return "cirfnint;"
										_: return ""
								else:
									if index < 865:
										match index:
											861: return "cirmid;"
											862: return "cirscir;"
											863: return "clubs;"
											864: return "clubsuit;"
											_: return ""
									else:
										match index:
											865: return "colon;"
											866: return "colone;"
											867: return "coloneq;"
											868: return "comma;"
											869: return "commat;"
											_: return ""
						else:
							if index < 887:
								if index < 878:
									match index:
										870: return "comp;"
										871: return "compfn;"
										872: return "complement;"
										873: return "complexes;"
										874: return "cong;"
										875: return "congdot;"
										876: return "conint;"
										877: return "copf;"
										_: return ""
								else:
									if index < 882:
										match index:
											878: return "coprod;"
											879: return "copy"
											880: return "copy;"
											881: return "copysr;"
											_: return ""
									else:
										match index:
											882: return "crarr;"
											883: return "cross;"
											884: return "cscr;"
											885: return "csub;"
											886: return "csube;"
											_: return ""
							else:
								if index < 896:
									if index < 891:
										match index:
											887: return "csup;"
											888: return "csupe;"
											889: return "ctdot;"
											890: return "cudarrl;"
											_: return ""
									else:
										match index:
											891: return "cudarrr;"
											892: return "cuepr;"
											893: return "cuesc;"
											894: return "cularr;"
											895: return "cularrp;"
											_: return ""
								else:
									if index < 900:
										match index:
											896: return "cup;"
											897: return "cupbrcap;"
											898: return "cupcap;"
											899: return "cupcup;"
											_: return ""
									else:
										match index:
											900: return "cupdot;"
											901: return "cupor;"
											902: return "cups;"
											903: return "curarr;"
											904: return "curarrm;"
											_: return ""
					else:
						if index < 940:
							if index < 922:
								if index < 913:
									match index:
										905: return "curlyeqprec;"
										906: return "curlyeqsucc;"
										907: return "curlyvee;"
										908: return "curlywedge;"
										909: return "curren"
										910: return "curren;"
										911: return "curvearrowleft;"
										912: return "curvearrowright;"
										_: return ""
								else:
									if index < 917:
										match index:
											913: return "cuvee;"
											914: return "cuwed;"
											915: return "cwconint;"
											916: return "cwint;"
											_: return ""
									else:
										match index:
											917: return "cylcty;"
											918: return "dArr;"
											919: return "dHar;"
											920: return "dagger;"
											921: return "daleth;"
											_: return ""
							else:
								if index < 931:
									if index < 926:
										match index:
											922: return "darr;"
											923: return "dash;"
											924: return "dashv;"
											925: return "dbkarow;"
											_: return ""
									else:
										match index:
											926: return "dblac;"
											927: return "dcaron;"
											928: return "dcy;"
											929: return "dd;"
											930: return "ddagger;"
											_: return ""
								else:
									if index < 935:
										match index:
											931: return "ddarr;"
											932: return "ddotseq;"
											933: return "deg"
											934: return "deg;"
											_: return ""
									else:
										match index:
											935: return "delta;"
											936: return "demptyv;"
											937: return "dfisht;"
											938: return "dfr;"
											939: return "dharl;"
											_: return ""
						else:
							if index < 957:
								if index < 948:
									match index:
										940: return "dharr;"
										941: return "diam;"
										942: return "diamond;"
										943: return "diamondsuit;"
										944: return "diams;"
										945: return "die;"
										946: return "digamma;"
										947: return "disin;"
										_: return ""
								else:
									if index < 952:
										match index:
											948: return "div;"
											949: return "divide"
											950: return "divide;"
											951: return "divideontimes;"
											_: return ""
									else:
										match index:
											952: return "divonx;"
											953: return "djcy;"
											954: return "dlcorn;"
											955: return "dlcrop;"
											956: return "dollar;"
											_: return ""
							else:
								if index < 966:
									if index < 961:
										match index:
											957: return "dopf;"
											958: return "dot;"
											959: return "doteq;"
											960: return "doteqdot;"
											_: return ""
									else:
										match index:
											961: return "dotminus;"
											962: return "dotplus;"
											963: return "dotsquare;"
											964: return "doublebarwedge;"
											965: return "downarrow;"
											_: return ""
								else:
									if index < 970:
										match index:
											966: return "downdownarrows;"
											967: return "downharpoonleft;"
											968: return "downharpoonright;"
											969: return "drbkarow;"
											_: return ""
									else:
										match index:
											970: return "drcorn;"
											971: return "drcrop;"
											972: return "dscr;"
											973: return "dscy;"
											974: return "dsol;"
											_: return ""
				else:
					if index < 1045:
						if index < 1010:
							if index < 992:
								if index < 983:
									match index:
										975: return "dstrok;"
										976: return "dtdot;"
										977: return "dtri;"
										978: return "dtrif;"
										979: return "duarr;"
										980: return "duhar;"
										981: return "dwangle;"
										982: return "dzcy;"
										_: return ""
								else:
									if index < 987:
										match index:
											983: return "dzigrarr;"
											984: return "eDDot;"
											985: return "eDot;"
											986: return "eacute"
											_: return ""
									else:
										match index:
											987: return "eacute;"
											988: return "easter;"
											989: return "ecaron;"
											990: return "ecir;"
											991: return "ecirc"
											_: return ""
							else:
								if index < 1001:
									if index < 996:
										match index:
											992: return "ecirc;"
											993: return "ecolon;"
											994: return "ecy;"
											995: return "edot;"
											_: return ""
									else:
										match index:
											996: return "ee;"
											997: return "efDot;"
											998: return "efr;"
											999: return "eg;"
											1000: return "egrave"
											_: return ""
								else:
									if index < 1005:
										match index:
											1001: return "egrave;"
											1002: return "egs;"
											1003: return "egsdot;"
											1004: return "el;"
											_: return ""
									else:
										match index:
											1005: return "elinters;"
											1006: return "ell;"
											1007: return "els;"
											1008: return "elsdot;"
											1009: return "emacr;"
											_: return ""
						else:
							if index < 1027:
								if index < 1018:
									match index:
										1010: return "empty;"
										1011: return "emptyset;"
										1012: return "emptyv;"
										1013: return "emsp13;"
										1014: return "emsp14;"
										1015: return "emsp;"
										1016: return "eng;"
										1017: return "ensp;"
										_: return ""
								else:
									if index < 1022:
										match index:
											1018: return "eogon;"
											1019: return "eopf;"
											1020: return "epar;"
											1021: return "eparsl;"
											_: return ""
									else:
										match index:
											1022: return "eplus;"
											1023: return "epsi;"
											1024: return "epsilon;"
											1025: return "epsiv;"
											1026: return "eqcirc;"
											_: return ""
							else:
								if index < 1036:
									if index < 1031:
										match index:
											1027: return "eqcolon;"
											1028: return "eqsim;"
											1029: return "eqslantgtr;"
											1030: return "eqslantless;"
											_: return ""
									else:
										match index:
											1031: return "equals;"
											1032: return "equest;"
											1033: return "equiv;"
											1034: return "equivDD;"
											1035: return "eqvparsl;"
											_: return ""
								else:
									if index < 1040:
										match index:
											1036: return "erDot;"
											1037: return "erarr;"
											1038: return "escr;"
											1039: return "esdot;"
											_: return ""
									else:
										match index:
											1040: return "esim;"
											1041: return "eta;"
											1042: return "eth"
											1043: return "eth;"
											1044: return "euml"
											_: return ""
					else:
						if index < 1080:
							if index < 1062:
								if index < 1053:
									match index:
										1045: return "euml;"
										1046: return "euro;"
										1047: return "excl;"
										1048: return "exist;"
										1049: return "expectation;"
										1050: return "exponentiale;"
										1051: return "fallingdotseq;"
										1052: return "fcy;"
										_: return ""
								else:
									if index < 1057:
										match index:
											1053: return "female;"
											1054: return "ffilig;"
											1055: return "fflig;"
											1056: return "ffllig;"
											_: return ""
									else:
										match index:
											1057: return "ffr;"
											1058: return "filig;"
											1059: return "fjlig;"
											1060: return "flat;"
											1061: return "fllig;"
											_: return ""
							else:
								if index < 1071:
									if index < 1066:
										match index:
											1062: return "fltns;"
											1063: return "fnof;"
											1064: return "fopf;"
											1065: return "forall;"
											_: return ""
									else:
										match index:
											1066: return "fork;"
											1067: return "forkv;"
											1068: return "fpartint;"
											1069: return "frac12"
											1070: return "frac12;"
											_: return ""
								else:
									if index < 1075:
										match index:
											1071: return "frac13;"
											1072: return "frac14"
											1073: return "frac14;"
											1074: return "frac15;"
											_: return ""
									else:
										match index:
											1075: return "frac16;"
											1076: return "frac18;"
											1077: return "frac23;"
											1078: return "frac25;"
											1079: return "frac34"
											_: return ""
						else:
							if index < 1097:
								if index < 1088:
									match index:
										1080: return "frac34;"
										1081: return "frac35;"
										1082: return "frac38;"
										1083: return "frac45;"
										1084: return "frac56;"
										1085: return "frac58;"
										1086: return "frac78;"
										1087: return "frasl;"
										_: return ""
								else:
									if index < 1092:
										match index:
											1088: return "frown;"
											1089: return "fscr;"
											1090: return "gE;"
											1091: return "gEl;"
											_: return ""
									else:
										match index:
											1092: return "gacute;"
											1093: return "gamma;"
											1094: return "gammad;"
											1095: return "gap;"
											1096: return "gbreve;"
											_: return ""
							else:
								if index < 1106:
									if index < 1101:
										match index:
											1097: return "gcirc;"
											1098: return "gcy;"
											1099: return "gdot;"
											1100: return "ge;"
											_: return ""
									else:
										match index:
											1101: return "gel;"
											1102: return "geq;"
											1103: return "geqq;"
											1104: return "geqslant;"
											1105: return "ges;"
											_: return ""
								else:
									if index < 1110:
										match index:
											1106: return "gescc;"
											1107: return "gesdot;"
											1108: return "gesdoto;"
											1109: return "gesdotol;"
											_: return ""
									else:
										match index:
											1110: return "gesl;"
											1111: return "gesles;"
											1112: return "gfr;"
											1113: return "gg;"
											1114: return "ggg;"
											_: return ""
	else:
		if index < 1673:
			if index < 1394:
				if index < 1254:
					if index < 1184:
						if index < 1149:
							if index < 1132:
								if index < 1123:
									match index:
										1115: return "gimel;"
										1116: return "gjcy;"
										1117: return "gl;"
										1118: return "glE;"
										1119: return "gla;"
										1120: return "glj;"
										1121: return "gnE;"
										1122: return "gnap;"
										_: return ""
								else:
									if index < 1127:
										match index:
											1123: return "gnapprox;"
											1124: return "gne;"
											1125: return "gneq;"
											1126: return "gneqq;"
											_: return ""
									else:
										match index:
											1127: return "gnsim;"
											1128: return "gopf;"
											1129: return "grave;"
											1130: return "gscr;"
											1131: return "gsim;"
											_: return ""
							else:
								if index < 1140:
									match index:
										1132: return "gsime;"
										1133: return "gsiml;"
										1134: return "gt"
										1135: return "gt;"
										1136: return "gtcc;"
										1137: return "gtcir;"
										1138: return "gtdot;"
										1139: return "gtlPar;"
										_: return ""
								else:
									if index < 1144:
										match index:
											1140: return "gtquest;"
											1141: return "gtrapprox;"
											1142: return "gtrarr;"
											1143: return "gtrdot;"
											_: return ""
									else:
										match index:
											1144: return "gtreqless;"
											1145: return "gtreqqless;"
											1146: return "gtrless;"
											1147: return "gtrsim;"
											1148: return "gvertneqq;"
											_: return ""
						else:
							if index < 1166:
								if index < 1157:
									match index:
										1149: return "gvnE;"
										1150: return "hArr;"
										1151: return "hairsp;"
										1152: return "half;"
										1153: return "hamilt;"
										1154: return "hardcy;"
										1155: return "harr;"
										1156: return "harrcir;"
										_: return ""
								else:
									if index < 1161:
										match index:
											1157: return "harrw;"
											1158: return "hbar;"
											1159: return "hcirc;"
											1160: return "hearts;"
											_: return ""
									else:
										match index:
											1161: return "heartsuit;"
											1162: return "hellip;"
											1163: return "hercon;"
											1164: return "hfr;"
											1165: return "hksearow;"
											_: return ""
							else:
								if index < 1175:
									if index < 1170:
										match index:
											1166: return "hkswarow;"
											1167: return "hoarr;"
											1168: return "homtht;"
											1169: return "hookleftarrow;"
											_: return ""
									else:
										match index:
											1170: return "hookrightarrow;"
											1171: return "hopf;"
											1172: return "horbar;"
											1173: return "hscr;"
											1174: return "hslash;"
											_: return ""
								else:
									if index < 1179:
										match index:
											1175: return "hstrok;"
											1176: return "hybull;"
											1177: return "hyphen;"
											1178: return "iacute"
											_: return ""
									else:
										match index:
											1179: return "iacute;"
											1180: return "ic;"
											1181: return "icirc"
											1182: return "icirc;"
											1183: return "icy;"
											_: return ""
					else:
						if index < 1219:
							if index < 1201:
								if index < 1192:
									match index:
										1184: return "iecy;"
										1185: return "iexcl"
										1186: return "iexcl;"
										1187: return "iff;"
										1188: return "ifr;"
										1189: return "igrave"
										1190: return "igrave;"
										1191: return "ii;"
										_: return ""
								else:
									if index < 1196:
										match index:
											1192: return "iiiint;"
											1193: return "iiint;"
											1194: return "iinfin;"
											1195: return "iiota;"
											_: return ""
									else:
										match index:
											1196: return "ijlig;"
											1197: return "imacr;"
											1198: return "image;"
											1199: return "imagline;"
											1200: return "imagpart;"
											_: return ""
							else:
								if index < 1210:
									if index < 1205:
										match index:
											1201: return "imath;"
											1202: return "imof;"
											1203: return "imped;"
											1204: return "in;"
											_: return ""
									else:
										match index:
											1205: return "incare;"
											1206: return "infin;"
											1207: return "infintie;"
											1208: return "inodot;"
											1209: return "int;"
											_: return ""
								else:
									if index < 1214:
										match index:
											1210: return "intcal;"
											1211: return "integers;"
											1212: return "intercal;"
											1213: return "intlarhk;"
											_: return ""
									else:
										match index:
											1214: return "intprod;"
											1215: return "iocy;"
											1216: return "iogon;"
											1217: return "iopf;"
											1218: return "iota;"
											_: return ""
						else:
							if index < 1236:
								if index < 1227:
									match index:
										1219: return "iprod;"
										1220: return "iquest"
										1221: return "iquest;"
										1222: return "iscr;"
										1223: return "isin;"
										1224: return "isinE;"
										1225: return "isindot;"
										1226: return "isins;"
										_: return ""
								else:
									if index < 1231:
										match index:
											1227: return "isinsv;"
											1228: return "isinv;"
											1229: return "it;"
											1230: return "itilde;"
											_: return ""
									else:
										match index:
											1231: return "iukcy;"
											1232: return "iuml"
											1233: return "iuml;"
											1234: return "jcirc;"
											1235: return "jcy;"
											_: return ""
							else:
								if index < 1245:
									if index < 1240:
										match index:
											1236: return "jfr;"
											1237: return "jmath;"
											1238: return "jopf;"
											1239: return "jscr;"
											_: return ""
									else:
										match index:
											1240: return "jsercy;"
											1241: return "jukcy;"
											1242: return "kappa;"
											1243: return "kappav;"
											1244: return "kcedil;"
											_: return ""
								else:
									if index < 1249:
										match index:
											1245: return "kcy;"
											1246: return "kfr;"
											1247: return "kgreen;"
											1248: return "khcy;"
											_: return ""
									else:
										match index:
											1249: return "kjcy;"
											1250: return "kopf;"
											1251: return "kscr;"
											1252: return "lAarr;"
											1253: return "lArr;"
											_: return ""
				else:
					if index < 1324:
						if index < 1289:
							if index < 1271:
								if index < 1262:
									match index:
										1254: return "lAtail;"
										1255: return "lBarr;"
										1256: return "lE;"
										1257: return "lEg;"
										1258: return "lHar;"
										1259: return "lacute;"
										1260: return "laemptyv;"
										1261: return "lagran;"
										_: return ""
								else:
									if index < 1266:
										match index:
											1262: return "lambda;"
											1263: return "lang;"
											1264: return "langd;"
											1265: return "langle;"
											_: return ""
									else:
										match index:
											1266: return "lap;"
											1267: return "laquo"
											1268: return "laquo;"
											1269: return "larr;"
											1270: return "larrb;"
											_: return ""
							else:
								if index < 1280:
									if index < 1275:
										match index:
											1271: return "larrbfs;"
											1272: return "larrfs;"
											1273: return "larrhk;"
											1274: return "larrlp;"
											_: return ""
									else:
										match index:
											1275: return "larrpl;"
											1276: return "larrsim;"
											1277: return "larrtl;"
											1278: return "lat;"
											1279: return "latail;"
											_: return ""
								else:
									if index < 1284:
										match index:
											1280: return "late;"
											1281: return "lates;"
											1282: return "lbarr;"
											1283: return "lbbrk;"
											_: return ""
									else:
										match index:
											1284: return "lbrace;"
											1285: return "lbrack;"
											1286: return "lbrke;"
											1287: return "lbrksld;"
											1288: return "lbrkslu;"
											_: return ""
						else:
							if index < 1306:
								if index < 1297:
									match index:
										1289: return "lcaron;"
										1290: return "lcedil;"
										1291: return "lceil;"
										1292: return "lcub;"
										1293: return "lcy;"
										1294: return "ldca;"
										1295: return "ldquo;"
										1296: return "ldquor;"
										_: return ""
								else:
									if index < 1301:
										match index:
											1297: return "ldrdhar;"
											1298: return "ldrushar;"
											1299: return "ldsh;"
											1300: return "le;"
											_: return ""
									else:
										match index:
											1301: return "leftarrow;"
											1302: return "leftarrowtail;"
											1303: return "leftharpoondown;"
											1304: return "leftharpoonup;"
											1305: return "leftleftarrows;"
											_: return ""
							else:
								if index < 1315:
									if index < 1310:
										match index:
											1306: return "leftrightarrow;"
											1307: return "leftrightarrows;"
											1308: return "leftrightharpoons;"
											1309: return "leftrightsquigarrow;"
											_: return ""
									else:
										match index:
											1310: return "leftthreetimes;"
											1311: return "leg;"
											1312: return "leq;"
											1313: return "leqq;"
											1314: return "leqslant;"
											_: return ""
								else:
									if index < 1319:
										match index:
											1315: return "les;"
											1316: return "lescc;"
											1317: return "lesdot;"
											1318: return "lesdoto;"
											_: return ""
									else:
										match index:
											1319: return "lesdotor;"
											1320: return "lesg;"
											1321: return "lesges;"
											1322: return "lessapprox;"
											1323: return "lessdot;"
											_: return ""
					else:
						if index < 1359:
							if index < 1341:
								if index < 1332:
									match index:
										1324: return "lesseqgtr;"
										1325: return "lesseqqgtr;"
										1326: return "lessgtr;"
										1327: return "lesssim;"
										1328: return "lfisht;"
										1329: return "lfloor;"
										1330: return "lfr;"
										1331: return "lg;"
										_: return ""
								else:
									if index < 1336:
										match index:
											1332: return "lgE;"
											1333: return "lhard;"
											1334: return "lharu;"
											1335: return "lharul;"
											_: return ""
									else:
										match index:
											1336: return "lhblk;"
											1337: return "ljcy;"
											1338: return "ll;"
											1339: return "llarr;"
											1340: return "llcorner;"
											_: return ""
							else:
								if index < 1350:
									if index < 1345:
										match index:
											1341: return "llhard;"
											1342: return "lltri;"
											1343: return "lmidot;"
											1344: return "lmoust;"
											_: return ""
									else:
										match index:
											1345: return "lmoustache;"
											1346: return "lnE;"
											1347: return "lnap;"
											1348: return "lnapprox;"
											1349: return "lne;"
											_: return ""
								else:
									if index < 1354:
										match index:
											1350: return "lneq;"
											1351: return "lneqq;"
											1352: return "lnsim;"
											1353: return "loang;"
											_: return ""
									else:
										match index:
											1354: return "loarr;"
											1355: return "lobrk;"
											1356: return "longleftarrow;"
											1357: return "longleftrightarrow;"
											1358: return "longmapsto;"
											_: return ""
						else:
							if index < 1376:
								if index < 1367:
									match index:
										1359: return "longrightarrow;"
										1360: return "looparrowleft;"
										1361: return "looparrowright;"
										1362: return "lopar;"
										1363: return "lopf;"
										1364: return "loplus;"
										1365: return "lotimes;"
										1366: return "lowast;"
										_: return ""
								else:
									if index < 1371:
										match index:
											1367: return "lowbar;"
											1368: return "loz;"
											1369: return "lozenge;"
											1370: return "lozf;"
											_: return ""
									else:
										match index:
											1371: return "lpar;"
											1372: return "lparlt;"
											1373: return "lrarr;"
											1374: return "lrcorner;"
											1375: return "lrhar;"
											_: return ""
							else:
								if index < 1385:
									if index < 1380:
										match index:
											1376: return "lrhard;"
											1377: return "lrm;"
											1378: return "lrtri;"
											1379: return "lsaquo;"
											_: return ""
									else:
										match index:
											1380: return "lscr;"
											1381: return "lsh;"
											1382: return "lsim;"
											1383: return "lsime;"
											1384: return "lsimg;"
											_: return ""
								else:
									if index < 1389:
										match index:
											1385: return "lsqb;"
											1386: return "lsquo;"
											1387: return "lsquor;"
											1388: return "lstrok;"
											_: return ""
									else:
										match index:
											1389: return "lt"
											1390: return "lt;"
											1391: return "ltcc;"
											1392: return "ltcir;"
											1393: return "ltdot;"
											_: return ""
			else:
				if index < 1533:
					if index < 1463:
						if index < 1428:
							if index < 1411:
								if index < 1402:
									match index:
										1394: return "lthree;"
										1395: return "ltimes;"
										1396: return "ltlarr;"
										1397: return "ltquest;"
										1398: return "ltrPar;"
										1399: return "ltri;"
										1400: return "ltrie;"
										1401: return "ltrif;"
										_: return ""
								else:
									if index < 1406:
										match index:
											1402: return "lurdshar;"
											1403: return "luruhar;"
											1404: return "lvertneqq;"
											1405: return "lvnE;"
											_: return ""
									else:
										match index:
											1406: return "mDDot;"
											1407: return "macr"
											1408: return "macr;"
											1409: return "male;"
											1410: return "malt;"
											_: return ""
							else:
								if index < 1419:
									match index:
										1411: return "maltese;"
										1412: return "map;"
										1413: return "mapsto;"
										1414: return "mapstodown;"
										1415: return "mapstoleft;"
										1416: return "mapstoup;"
										1417: return "marker;"
										1418: return "mcomma;"
										_: return ""
								else:
									if index < 1423:
										match index:
											1419: return "mcy;"
											1420: return "mdash;"
											1421: return "measuredangle;"
											1422: return "mfr;"
											_: return ""
									else:
										match index:
											1423: return "mho;"
											1424: return "micro"
											1425: return "micro;"
											1426: return "mid;"
											1427: return "midast;"
											_: return ""
						else:
							if index < 1445:
								if index < 1436:
									match index:
										1428: return "midcir;"
										1429: return "middot"
										1430: return "middot;"
										1431: return "minus;"
										1432: return "minusb;"
										1433: return "minusd;"
										1434: return "minusdu;"
										1435: return "mlcp;"
										_: return ""
								else:
									if index < 1440:
										match index:
											1436: return "mldr;"
											1437: return "mnplus;"
											1438: return "models;"
											1439: return "mopf;"
											_: return ""
									else:
										match index:
											1440: return "mp;"
											1441: return "mscr;"
											1442: return "mstpos;"
											1443: return "mu;"
											1444: return "multimap;"
											_: return ""
							else:
								if index < 1454:
									if index < 1449:
										match index:
											1445: return "mumap;"
											1446: return "nGg;"
											1447: return "nGt;"
											1448: return "nGtv;"
											_: return ""
									else:
										match index:
											1449: return "nLeftarrow;"
											1450: return "nLeftrightarrow;"
											1451: return "nLl;"
											1452: return "nLt;"
											1453: return "nLtv;"
											_: return ""
								else:
									if index < 1458:
										match index:
											1454: return "nRightarrow;"
											1455: return "nVDash;"
											1456: return "nVdash;"
											1457: return "nabla;"
											_: return ""
									else:
										match index:
											1458: return "nacute;"
											1459: return "nang;"
											1460: return "nap;"
											1461: return "napE;"
											1462: return "napid;"
											_: return ""
					else:
						if index < 1498:
							if index < 1480:
								if index < 1471:
									match index:
										1463: return "napos;"
										1464: return "napprox;"
										1465: return "natur;"
										1466: return "natural;"
										1467: return "naturals;"
										1468: return "nbsp"
										1469: return "nbsp;"
										1470: return "nbump;"
										_: return ""
								else:
									if index < 1475:
										match index:
											1471: return "nbumpe;"
											1472: return "ncap;"
											1473: return "ncaron;"
											1474: return "ncedil;"
											_: return ""
									else:
										match index:
											1475: return "ncong;"
											1476: return "ncongdot;"
											1477: return "ncup;"
											1478: return "ncy;"
											1479: return "ndash;"
											_: return ""
							else:
								if index < 1489:
									if index < 1484:
										match index:
											1480: return "ne;"
											1481: return "neArr;"
											1482: return "nearhk;"
											1483: return "nearr;"
											_: return ""
									else:
										match index:
											1484: return "nearrow;"
											1485: return "nedot;"
											1486: return "nequiv;"
											1487: return "nesear;"
											1488: return "nesim;"
											_: return ""
								else:
									if index < 1493:
										match index:
											1489: return "nexist;"
											1490: return "nexists;"
											1491: return "nfr;"
											1492: return "ngE;"
											_: return ""
									else:
										match index:
											1493: return "nge;"
											1494: return "ngeq;"
											1495: return "ngeqq;"
											1496: return "ngeqslant;"
											1497: return "nges;"
											_: return ""
						else:
							if index < 1515:
								if index < 1506:
									match index:
										1498: return "ngsim;"
										1499: return "ngt;"
										1500: return "ngtr;"
										1501: return "nhArr;"
										1502: return "nharr;"
										1503: return "nhpar;"
										1504: return "ni;"
										1505: return "nis;"
										_: return ""
								else:
									if index < 1510:
										match index:
											1506: return "nisd;"
											1507: return "niv;"
											1508: return "njcy;"
											1509: return "nlArr;"
											_: return ""
									else:
										match index:
											1510: return "nlE;"
											1511: return "nlarr;"
											1512: return "nldr;"
											1513: return "nle;"
											1514: return "nleftarrow;"
											_: return ""
							else:
								if index < 1524:
									if index < 1519:
										match index:
											1515: return "nleftrightarrow;"
											1516: return "nleq;"
											1517: return "nleqq;"
											1518: return "nleqslant;"
											_: return ""
									else:
										match index:
											1519: return "nles;"
											1520: return "nless;"
											1521: return "nlsim;"
											1522: return "nlt;"
											1523: return "nltri;"
											_: return ""
								else:
									if index < 1528:
										match index:
											1524: return "nltrie;"
											1525: return "nmid;"
											1526: return "nopf;"
											1527: return "not"
											_: return ""
									else:
										match index:
											1528: return "not;"
											1529: return "notin;"
											1530: return "notinE;"
											1531: return "notindot;"
											1532: return "notinva;"
											_: return ""
				else:
					if index < 1603:
						if index < 1568:
							if index < 1550:
								if index < 1541:
									match index:
										1533: return "notinvb;"
										1534: return "notinvc;"
										1535: return "notni;"
										1536: return "notniva;"
										1537: return "notnivb;"
										1538: return "notnivc;"
										1539: return "npar;"
										1540: return "nparallel;"
										_: return ""
								else:
									if index < 1545:
										match index:
											1541: return "nparsl;"
											1542: return "npart;"
											1543: return "npolint;"
											1544: return "npr;"
											_: return ""
									else:
										match index:
											1545: return "nprcue;"
											1546: return "npre;"
											1547: return "nprec;"
											1548: return "npreceq;"
											1549: return "nrArr;"
											_: return ""
							else:
								if index < 1559:
									if index < 1554:
										match index:
											1550: return "nrarr;"
											1551: return "nrarrc;"
											1552: return "nrarrw;"
											1553: return "nrightarrow;"
											_: return ""
									else:
										match index:
											1554: return "nrtri;"
											1555: return "nrtrie;"
											1556: return "nsc;"
											1557: return "nsccue;"
											1558: return "nsce;"
											_: return ""
								else:
									if index < 1563:
										match index:
											1559: return "nscr;"
											1560: return "nshortmid;"
											1561: return "nshortparallel;"
											1562: return "nsim;"
											_: return ""
									else:
										match index:
											1563: return "nsime;"
											1564: return "nsimeq;"
											1565: return "nsmid;"
											1566: return "nspar;"
											1567: return "nsqsube;"
											_: return ""
						else:
							if index < 1585:
								if index < 1576:
									match index:
										1568: return "nsqsupe;"
										1569: return "nsub;"
										1570: return "nsubE;"
										1571: return "nsube;"
										1572: return "nsubset;"
										1573: return "nsubseteq;"
										1574: return "nsubseteqq;"
										1575: return "nsucc;"
										_: return ""
								else:
									if index < 1580:
										match index:
											1576: return "nsucceq;"
											1577: return "nsup;"
											1578: return "nsupE;"
											1579: return "nsupe;"
											_: return ""
									else:
										match index:
											1580: return "nsupset;"
											1581: return "nsupseteq;"
											1582: return "nsupseteqq;"
											1583: return "ntgl;"
											1584: return "ntilde"
											_: return ""
							else:
								if index < 1594:
									if index < 1589:
										match index:
											1585: return "ntilde;"
											1586: return "ntlg;"
											1587: return "ntriangleleft;"
											1588: return "ntrianglelefteq;"
											_: return ""
									else:
										match index:
											1589: return "ntriangleright;"
											1590: return "ntrianglerighteq;"
											1591: return "nu;"
											1592: return "num;"
											1593: return "numero;"
											_: return ""
								else:
									if index < 1598:
										match index:
											1594: return "numsp;"
											1595: return "nvDash;"
											1596: return "nvHarr;"
											1597: return "nvap;"
											_: return ""
									else:
										match index:
											1598: return "nvdash;"
											1599: return "nvge;"
											1600: return "nvgt;"
											1601: return "nvinfin;"
											1602: return "nvlArr;"
											_: return ""
					else:
						if index < 1638:
							if index < 1620:
								if index < 1611:
									match index:
										1603: return "nvle;"
										1604: return "nvlt;"
										1605: return "nvltrie;"
										1606: return "nvrArr;"
										1607: return "nvrtrie;"
										1608: return "nvsim;"
										1609: return "nwArr;"
										1610: return "nwarhk;"
										_: return ""
								else:
									if index < 1615:
										match index:
											1611: return "nwarr;"
											1612: return "nwarrow;"
											1613: return "nwnear;"
											1614: return "oS;"
											_: return ""
									else:
										match index:
											1615: return "oacute"
											1616: return "oacute;"
											1617: return "oast;"
											1618: return "ocir;"
											1619: return "ocirc"
											_: return ""
							else:
								if index < 1629:
									if index < 1624:
										match index:
											1620: return "ocirc;"
											1621: return "ocy;"
											1622: return "odash;"
											1623: return "odblac;"
											_: return ""
									else:
										match index:
											1624: return "odiv;"
											1625: return "odot;"
											1626: return "odsold;"
											1627: return "oelig;"
											1628: return "ofcir;"
											_: return ""
								else:
									if index < 1633:
										match index:
											1629: return "ofr;"
											1630: return "ogon;"
											1631: return "ograve"
											1632: return "ograve;"
											_: return ""
									else:
										match index:
											1633: return "ogt;"
											1634: return "ohbar;"
											1635: return "ohm;"
											1636: return "oint;"
											1637: return "olarr;"
											_: return ""
						else:
							if index < 1655:
								if index < 1646:
									match index:
										1638: return "olcir;"
										1639: return "olcross;"
										1640: return "oline;"
										1641: return "olt;"
										1642: return "omacr;"
										1643: return "omega;"
										1644: return "omicron;"
										1645: return "omid;"
										_: return ""
								else:
									if index < 1650:
										match index:
											1646: return "ominus;"
											1647: return "oopf;"
											1648: return "opar;"
											1649: return "operp;"
											_: return ""
									else:
										match index:
											1650: return "oplus;"
											1651: return "or;"
											1652: return "orarr;"
											1653: return "ord;"
											1654: return "order;"
											_: return ""
							else:
								if index < 1664:
									if index < 1659:
										match index:
											1655: return "orderof;"
											1656: return "ordf"
											1657: return "ordf;"
											1658: return "ordm"
											_: return ""
									else:
										match index:
											1659: return "ordm;"
											1660: return "origof;"
											1661: return "oror;"
											1662: return "orslope;"
											1663: return "orv;"
											_: return ""
								else:
									if index < 1668:
										match index:
											1664: return "oscr;"
											1665: return "oslash"
											1666: return "oslash;"
											1667: return "osol;"
											_: return ""
									else:
										match index:
											1668: return "otilde"
											1669: return "otilde;"
											1670: return "otimes;"
											1671: return "otimesas;"
											1672: return "ouml"
											_: return ""
		else:
			if index < 1952:
				if index < 1812:
					if index < 1742:
						if index < 1707:
							if index < 1690:
								if index < 1681:
									match index:
										1673: return "ouml;"
										1674: return "ovbar;"
										1675: return "par;"
										1676: return "para"
										1677: return "para;"
										1678: return "parallel;"
										1679: return "parsim;"
										1680: return "parsl;"
										_: return ""
								else:
									if index < 1685:
										match index:
											1681: return "part;"
											1682: return "pcy;"
											1683: return "percnt;"
											1684: return "period;"
											_: return ""
									else:
										match index:
											1685: return "permil;"
											1686: return "perp;"
											1687: return "pertenk;"
											1688: return "pfr;"
											1689: return "phi;"
											_: return ""
							else:
								if index < 1698:
									match index:
										1690: return "phiv;"
										1691: return "phmmat;"
										1692: return "phone;"
										1693: return "pi;"
										1694: return "pitchfork;"
										1695: return "piv;"
										1696: return "planck;"
										1697: return "planckh;"
										_: return ""
								else:
									if index < 1702:
										match index:
											1698: return "plankv;"
											1699: return "plus;"
											1700: return "plusacir;"
											1701: return "plusb;"
											_: return ""
									else:
										match index:
											1702: return "pluscir;"
											1703: return "plusdo;"
											1704: return "plusdu;"
											1705: return "pluse;"
											1706: return "plusmn"
											_: return ""
						else:
							if index < 1724:
								if index < 1715:
									match index:
										1707: return "plusmn;"
										1708: return "plussim;"
										1709: return "plustwo;"
										1710: return "pm;"
										1711: return "pointint;"
										1712: return "popf;"
										1713: return "pound"
										1714: return "pound;"
										_: return ""
								else:
									if index < 1719:
										match index:
											1715: return "pr;"
											1716: return "prE;"
											1717: return "prap;"
											1718: return "prcue;"
											_: return ""
									else:
										match index:
											1719: return "pre;"
											1720: return "prec;"
											1721: return "precapprox;"
											1722: return "preccurlyeq;"
											1723: return "preceq;"
											_: return ""
							else:
								if index < 1733:
									if index < 1728:
										match index:
											1724: return "precnapprox;"
											1725: return "precneqq;"
											1726: return "precnsim;"
											1727: return "precsim;"
											_: return ""
									else:
										match index:
											1728: return "prime;"
											1729: return "primes;"
											1730: return "prnE;"
											1731: return "prnap;"
											1732: return "prnsim;"
											_: return ""
								else:
									if index < 1737:
										match index:
											1733: return "prod;"
											1734: return "profalar;"
											1735: return "profline;"
											1736: return "profsurf;"
											_: return ""
									else:
										match index:
											1737: return "prop;"
											1738: return "propto;"
											1739: return "prsim;"
											1740: return "prurel;"
											1741: return "pscr;"
											_: return ""
					else:
						if index < 1777:
							if index < 1759:
								if index < 1750:
									match index:
										1742: return "psi;"
										1743: return "puncsp;"
										1744: return "qfr;"
										1745: return "qint;"
										1746: return "qopf;"
										1747: return "qprime;"
										1748: return "qscr;"
										1749: return "quaternions;"
										_: return ""
								else:
									if index < 1754:
										match index:
											1750: return "quatint;"
											1751: return "quest;"
											1752: return "questeq;"
											1753: return "quot"
											_: return ""
									else:
										match index:
											1754: return "quot;"
											1755: return "rAarr;"
											1756: return "rArr;"
											1757: return "rAtail;"
											1758: return "rBarr;"
											_: return ""
							else:
								if index < 1768:
									if index < 1763:
										match index:
											1759: return "rHar;"
											1760: return "race;"
											1761: return "racute;"
											1762: return "radic;"
											_: return ""
									else:
										match index:
											1763: return "raemptyv;"
											1764: return "rang;"
											1765: return "rangd;"
											1766: return "range;"
											1767: return "rangle;"
											_: return ""
								else:
									if index < 1772:
										match index:
											1768: return "raquo"
											1769: return "raquo;"
											1770: return "rarr;"
											1771: return "rarrap;"
											_: return ""
									else:
										match index:
											1772: return "rarrb;"
											1773: return "rarrbfs;"
											1774: return "rarrc;"
											1775: return "rarrfs;"
											1776: return "rarrhk;"
											_: return ""
						else:
							if index < 1794:
								if index < 1785:
									match index:
										1777: return "rarrlp;"
										1778: return "rarrpl;"
										1779: return "rarrsim;"
										1780: return "rarrtl;"
										1781: return "rarrw;"
										1782: return "ratail;"
										1783: return "ratio;"
										1784: return "rationals;"
										_: return ""
								else:
									if index < 1789:
										match index:
											1785: return "rbarr;"
											1786: return "rbbrk;"
											1787: return "rbrace;"
											1788: return "rbrack;"
											_: return ""
									else:
										match index:
											1789: return "rbrke;"
											1790: return "rbrksld;"
											1791: return "rbrkslu;"
											1792: return "rcaron;"
											1793: return "rcedil;"
											_: return ""
							else:
								if index < 1803:
									if index < 1798:
										match index:
											1794: return "rceil;"
											1795: return "rcub;"
											1796: return "rcy;"
											1797: return "rdca;"
											_: return ""
									else:
										match index:
											1798: return "rdldhar;"
											1799: return "rdquo;"
											1800: return "rdquor;"
											1801: return "rdsh;"
											1802: return "real;"
											_: return ""
								else:
									if index < 1807:
										match index:
											1803: return "realine;"
											1804: return "realpart;"
											1805: return "reals;"
											1806: return "rect;"
											_: return ""
									else:
										match index:
											1807: return "reg"
											1808: return "reg;"
											1809: return "rfisht;"
											1810: return "rfloor;"
											1811: return "rfr;"
											_: return ""
				else:
					if index < 1882:
						if index < 1847:
							if index < 1829:
								if index < 1820:
									match index:
										1812: return "rhard;"
										1813: return "rharu;"
										1814: return "rharul;"
										1815: return "rho;"
										1816: return "rhov;"
										1817: return "rightarrow;"
										1818: return "rightarrowtail;"
										1819: return "rightharpoondown;"
										_: return ""
								else:
									if index < 1824:
										match index:
											1820: return "rightharpoonup;"
											1821: return "rightleftarrows;"
											1822: return "rightleftharpoons;"
											1823: return "rightrightarrows;"
											_: return ""
									else:
										match index:
											1824: return "rightsquigarrow;"
											1825: return "rightthreetimes;"
											1826: return "ring;"
											1827: return "risingdotseq;"
											1828: return "rlarr;"
											_: return ""
							else:
								if index < 1838:
									if index < 1833:
										match index:
											1829: return "rlhar;"
											1830: return "rlm;"
											1831: return "rmoust;"
											1832: return "rmoustache;"
											_: return ""
									else:
										match index:
											1833: return "rnmid;"
											1834: return "roang;"
											1835: return "roarr;"
											1836: return "robrk;"
											1837: return "ropar;"
											_: return ""
								else:
									if index < 1842:
										match index:
											1838: return "ropf;"
											1839: return "roplus;"
											1840: return "rotimes;"
											1841: return "rpar;"
											_: return ""
									else:
										match index:
											1842: return "rpargt;"
											1843: return "rppolint;"
											1844: return "rrarr;"
											1845: return "rsaquo;"
											1846: return "rscr;"
											_: return ""
						else:
							if index < 1864:
								if index < 1855:
									match index:
										1847: return "rsh;"
										1848: return "rsqb;"
										1849: return "rsquo;"
										1850: return "rsquor;"
										1851: return "rthree;"
										1852: return "rtimes;"
										1853: return "rtri;"
										1854: return "rtrie;"
										_: return ""
								else:
									if index < 1859:
										match index:
											1855: return "rtrif;"
											1856: return "rtriltri;"
											1857: return "ruluhar;"
											1858: return "rx;"
											_: return ""
									else:
										match index:
											1859: return "sacute;"
											1860: return "sbquo;"
											1861: return "sc;"
											1862: return "scE;"
											1863: return "scap;"
											_: return ""
							else:
								if index < 1873:
									if index < 1868:
										match index:
											1864: return "scaron;"
											1865: return "sccue;"
											1866: return "sce;"
											1867: return "scedil;"
											_: return ""
									else:
										match index:
											1868: return "scirc;"
											1869: return "scnE;"
											1870: return "scnap;"
											1871: return "scnsim;"
											1872: return "scpolint;"
											_: return ""
								else:
									if index < 1877:
										match index:
											1873: return "scsim;"
											1874: return "scy;"
											1875: return "sdot;"
											1876: return "sdotb;"
											_: return ""
									else:
										match index:
											1877: return "sdote;"
											1878: return "seArr;"
											1879: return "searhk;"
											1880: return "searr;"
											1881: return "searrow;"
											_: return ""
					else:
						if index < 1917:
							if index < 1899:
								if index < 1890:
									match index:
										1882: return "sect"
										1883: return "sect;"
										1884: return "semi;"
										1885: return "seswar;"
										1886: return "setminus;"
										1887: return "setmn;"
										1888: return "sext;"
										1889: return "sfr;"
										_: return ""
								else:
									if index < 1894:
										match index:
											1890: return "sfrown;"
											1891: return "sharp;"
											1892: return "shchcy;"
											1893: return "shcy;"
											_: return ""
									else:
										match index:
											1894: return "shortmid;"
											1895: return "shortparallel;"
											1896: return "shy"
											1897: return "shy;"
											1898: return "sigma;"
											_: return ""
							else:
								if index < 1908:
									if index < 1903:
										match index:
											1899: return "sigmaf;"
											1900: return "sigmav;"
											1901: return "sim;"
											1902: return "simdot;"
											_: return ""
									else:
										match index:
											1903: return "sime;"
											1904: return "simeq;"
											1905: return "simg;"
											1906: return "simgE;"
											1907: return "siml;"
											_: return ""
								else:
									if index < 1912:
										match index:
											1908: return "simlE;"
											1909: return "simne;"
											1910: return "simplus;"
											1911: return "simrarr;"
											_: return ""
									else:
										match index:
											1912: return "slarr;"
											1913: return "smallsetminus;"
											1914: return "smashp;"
											1915: return "smeparsl;"
											1916: return "smid;"
											_: return ""
						else:
							if index < 1934:
								if index < 1925:
									match index:
										1917: return "smile;"
										1918: return "smt;"
										1919: return "smte;"
										1920: return "smtes;"
										1921: return "softcy;"
										1922: return "sol;"
										1923: return "solb;"
										1924: return "solbar;"
										_: return ""
								else:
									if index < 1929:
										match index:
											1925: return "sopf;"
											1926: return "spades;"
											1927: return "spadesuit;"
											1928: return "spar;"
											_: return ""
									else:
										match index:
											1929: return "sqcap;"
											1930: return "sqcaps;"
											1931: return "sqcup;"
											1932: return "sqcups;"
											1933: return "sqsub;"
											_: return ""
							else:
								if index < 1943:
									if index < 1938:
										match index:
											1934: return "sqsube;"
											1935: return "sqsubset;"
											1936: return "sqsubseteq;"
											1937: return "sqsup;"
											_: return ""
									else:
										match index:
											1938: return "sqsupe;"
											1939: return "sqsupset;"
											1940: return "sqsupseteq;"
											1941: return "squ;"
											1942: return "square;"
											_: return ""
								else:
									if index < 1947:
										match index:
											1943: return "squarf;"
											1944: return "squf;"
											1945: return "srarr;"
											1946: return "sscr;"
											_: return ""
									else:
										match index:
											1947: return "ssetmn;"
											1948: return "ssmile;"
											1949: return "sstarf;"
											1950: return "star;"
											1951: return "starf;"
											_: return ""
			else:
				if index < 2091:
					if index < 2021:
						if index < 1986:
							if index < 1969:
								if index < 1960:
									match index:
										1952: return "straightepsilon;"
										1953: return "straightphi;"
										1954: return "strns;"
										1955: return "sub;"
										1956: return "subE;"
										1957: return "subdot;"
										1958: return "sube;"
										1959: return "subedot;"
										_: return ""
								else:
									if index < 1964:
										match index:
											1960: return "submult;"
											1961: return "subnE;"
											1962: return "subne;"
											1963: return "subplus;"
											_: return ""
									else:
										match index:
											1964: return "subrarr;"
											1965: return "subset;"
											1966: return "subseteq;"
											1967: return "subseteqq;"
											1968: return "subsetneq;"
											_: return ""
							else:
								if index < 1977:
									match index:
										1969: return "subsetneqq;"
										1970: return "subsim;"
										1971: return "subsub;"
										1972: return "subsup;"
										1973: return "succ;"
										1974: return "succapprox;"
										1975: return "succcurlyeq;"
										1976: return "succeq;"
										_: return ""
								else:
									if index < 1981:
										match index:
											1977: return "succnapprox;"
											1978: return "succneqq;"
											1979: return "succnsim;"
											1980: return "succsim;"
											_: return ""
									else:
										match index:
											1981: return "sum;"
											1982: return "sung;"
											1983: return "sup1"
											1984: return "sup1;"
											1985: return "sup2"
											_: return ""
						else:
							if index < 2003:
								if index < 1994:
									match index:
										1986: return "sup2;"
										1987: return "sup3"
										1988: return "sup3;"
										1989: return "sup;"
										1990: return "supE;"
										1991: return "supdot;"
										1992: return "supdsub;"
										1993: return "supe;"
										_: return ""
								else:
									if index < 1998:
										match index:
											1994: return "supedot;"
											1995: return "suphsol;"
											1996: return "suphsub;"
											1997: return "suplarr;"
											_: return ""
									else:
										match index:
											1998: return "supmult;"
											1999: return "supnE;"
											2000: return "supne;"
											2001: return "supplus;"
											2002: return "supset;"
											_: return ""
							else:
								if index < 2012:
									if index < 2007:
										match index:
											2003: return "supseteq;"
											2004: return "supseteqq;"
											2005: return "supsetneq;"
											2006: return "supsetneqq;"
											_: return ""
									else:
										match index:
											2007: return "supsim;"
											2008: return "supsub;"
											2009: return "supsup;"
											2010: return "swArr;"
											2011: return "swarhk;"
											_: return ""
								else:
									if index < 2016:
										match index:
											2012: return "swarr;"
											2013: return "swarrow;"
											2014: return "swnwar;"
											2015: return "szlig"
											_: return ""
									else:
										match index:
											2016: return "szlig;"
											2017: return "target;"
											2018: return "tau;"
											2019: return "tbrk;"
											2020: return "tcaron;"
											_: return ""
					else:
						if index < 2056:
							if index < 2038:
								if index < 2029:
									match index:
										2021: return "tcedil;"
										2022: return "tcy;"
										2023: return "tdot;"
										2024: return "telrec;"
										2025: return "tfr;"
										2026: return "there4;"
										2027: return "therefore;"
										2028: return "theta;"
										_: return ""
								else:
									if index < 2033:
										match index:
											2029: return "thetasym;"
											2030: return "thetav;"
											2031: return "thickapprox;"
											2032: return "thicksim;"
											_: return ""
									else:
										match index:
											2033: return "thinsp;"
											2034: return "thkap;"
											2035: return "thksim;"
											2036: return "thorn"
											2037: return "thorn;"
											_: return ""
							else:
								if index < 2047:
									if index < 2042:
										match index:
											2038: return "tilde;"
											2039: return "times"
											2040: return "times;"
											2041: return "timesb;"
											_: return ""
									else:
										match index:
											2042: return "timesbar;"
											2043: return "timesd;"
											2044: return "tint;"
											2045: return "toea;"
											2046: return "top;"
											_: return ""
								else:
									if index < 2051:
										match index:
											2047: return "topbot;"
											2048: return "topcir;"
											2049: return "topf;"
											2050: return "topfork;"
											_: return ""
									else:
										match index:
											2051: return "tosa;"
											2052: return "tprime;"
											2053: return "trade;"
											2054: return "triangle;"
											2055: return "triangledown;"
											_: return ""
						else:
							if index < 2073:
								if index < 2064:
									match index:
										2056: return "triangleleft;"
										2057: return "trianglelefteq;"
										2058: return "triangleq;"
										2059: return "triangleright;"
										2060: return "trianglerighteq;"
										2061: return "tridot;"
										2062: return "trie;"
										2063: return "triminus;"
										_: return ""
								else:
									if index < 2068:
										match index:
											2064: return "triplus;"
											2065: return "trisb;"
											2066: return "tritime;"
											2067: return "trpezium;"
											_: return ""
									else:
										match index:
											2068: return "tscr;"
											2069: return "tscy;"
											2070: return "tshcy;"
											2071: return "tstrok;"
											2072: return "twixt;"
											_: return ""
							else:
								if index < 2082:
									if index < 2077:
										match index:
											2073: return "twoheadleftarrow;"
											2074: return "twoheadrightarrow;"
											2075: return "uArr;"
											2076: return "uHar;"
											_: return ""
									else:
										match index:
											2077: return "uacute"
											2078: return "uacute;"
											2079: return "uarr;"
											2080: return "ubrcy;"
											2081: return "ubreve;"
											_: return ""
								else:
									if index < 2086:
										match index:
											2082: return "ucirc"
											2083: return "ucirc;"
											2084: return "ucy;"
											2085: return "udarr;"
											_: return ""
									else:
										match index:
											2086: return "udblac;"
											2087: return "udhar;"
											2088: return "ufisht;"
											2089: return "ufr;"
											2090: return "ugrave"
											_: return ""
				else:
					if index < 2161:
						if index < 2126:
							if index < 2108:
								if index < 2099:
									match index:
										2091: return "ugrave;"
										2092: return "uharl;"
										2093: return "uharr;"
										2094: return "uhblk;"
										2095: return "ulcorn;"
										2096: return "ulcorner;"
										2097: return "ulcrop;"
										2098: return "ultri;"
										_: return ""
								else:
									if index < 2103:
										match index:
											2099: return "umacr;"
											2100: return "uml"
											2101: return "uml;"
											2102: return "uogon;"
											_: return ""
									else:
										match index:
											2103: return "uopf;"
											2104: return "uparrow;"
											2105: return "updownarrow;"
											2106: return "upharpoonleft;"
											2107: return "upharpoonright;"
											_: return ""
							else:
								if index < 2117:
									if index < 2112:
										match index:
											2108: return "uplus;"
											2109: return "upsi;"
											2110: return "upsih;"
											2111: return "upsilon;"
											_: return ""
									else:
										match index:
											2112: return "upuparrows;"
											2113: return "urcorn;"
											2114: return "urcorner;"
											2115: return "urcrop;"
											2116: return "uring;"
											_: return ""
								else:
									if index < 2121:
										match index:
											2117: return "urtri;"
											2118: return "uscr;"
											2119: return "utdot;"
											2120: return "utilde;"
											_: return ""
									else:
										match index:
											2121: return "utri;"
											2122: return "utrif;"
											2123: return "uuarr;"
											2124: return "uuml"
											2125: return "uuml;"
											_: return ""
						else:
							if index < 2143:
								if index < 2134:
									match index:
										2126: return "uwangle;"
										2127: return "vArr;"
										2128: return "vBar;"
										2129: return "vBarv;"
										2130: return "vDash;"
										2131: return "vangrt;"
										2132: return "varepsilon;"
										2133: return "varkappa;"
										_: return ""
								else:
									if index < 2138:
										match index:
											2134: return "varnothing;"
											2135: return "varphi;"
											2136: return "varpi;"
											2137: return "varpropto;"
											_: return ""
									else:
										match index:
											2138: return "varr;"
											2139: return "varrho;"
											2140: return "varsigma;"
											2141: return "varsubsetneq;"
											2142: return "varsubsetneqq;"
											_: return ""
							else:
								if index < 2152:
									if index < 2147:
										match index:
											2143: return "varsupsetneq;"
											2144: return "varsupsetneqq;"
											2145: return "vartheta;"
											2146: return "vartriangleleft;"
											_: return ""
									else:
										match index:
											2147: return "vartriangleright;"
											2148: return "vcy;"
											2149: return "vdash;"
											2150: return "vee;"
											2151: return "veebar;"
											_: return ""
								else:
									if index < 2156:
										match index:
											2152: return "veeeq;"
											2153: return "vellip;"
											2154: return "verbar;"
											2155: return "vert;"
											_: return ""
									else:
										match index:
											2156: return "vfr;"
											2157: return "vltri;"
											2158: return "vnsub;"
											2159: return "vnsup;"
											2160: return "vopf;"
											_: return ""
					else:
						if index < 2196:
							if index < 2178:
								if index < 2169:
									match index:
										2161: return "vprop;"
										2162: return "vrtri;"
										2163: return "vscr;"
										2164: return "vsubnE;"
										2165: return "vsubne;"
										2166: return "vsupnE;"
										2167: return "vsupne;"
										2168: return "vzigzag;"
										_: return ""
								else:
									if index < 2173:
										match index:
											2169: return "wcirc;"
											2170: return "wedbar;"
											2171: return "wedge;"
											2172: return "wedgeq;"
											_: return ""
									else:
										match index:
											2173: return "weierp;"
											2174: return "wfr;"
											2175: return "wopf;"
											2176: return "wp;"
											2177: return "wr;"
											_: return ""
							else:
								if index < 2187:
									if index < 2182:
										match index:
											2178: return "wreath;"
											2179: return "wscr;"
											2180: return "xcap;"
											2181: return "xcirc;"
											_: return ""
									else:
										match index:
											2182: return "xcup;"
											2183: return "xdtri;"
											2184: return "xfr;"
											2185: return "xhArr;"
											2186: return "xharr;"
											_: return ""
								else:
									if index < 2191:
										match index:
											2187: return "xi;"
											2188: return "xlArr;"
											2189: return "xlarr;"
											2190: return "xmap;"
											_: return ""
									else:
										match index:
											2191: return "xnis;"
											2192: return "xodot;"
											2193: return "xopf;"
											2194: return "xoplus;"
											2195: return "xotime;"
											_: return ""
						else:
							if index < 2213:
								if index < 2204:
									match index:
										2196: return "xrArr;"
										2197: return "xrarr;"
										2198: return "xscr;"
										2199: return "xsqcup;"
										2200: return "xuplus;"
										2201: return "xutri;"
										2202: return "xvee;"
										2203: return "xwedge;"
										_: return ""
								else:
									if index < 2208:
										match index:
											2204: return "yacute"
											2205: return "yacute;"
											2206: return "yacy;"
											2207: return "ycirc;"
											_: return ""
									else:
										match index:
											2208: return "ycy;"
											2209: return "yen"
											2210: return "yen;"
											2211: return "yfr;"
											2212: return "yicy;"
											_: return ""
							else:
								if index < 2222:
									if index < 2217:
										match index:
											2213: return "yopf;"
											2214: return "yscr;"
											2215: return "yucy;"
											2216: return "yuml"
											_: return ""
									else:
										match index:
											2217: return "yuml;"
											2218: return "zacute;"
											2219: return "zcaron;"
											2220: return "zcy;"
											2221: return "zdot;"
											_: return ""
								else:
									if index < 2226:
										match index:
											2222: return "zeetrf;"
											2223: return "zeta;"
											2224: return "zfr;"
											2225: return "zhcy;"
											_: return ""
									else:
										match index:
											2226: return "zigrarr;"
											2227: return "zopf;"
											2228: return "zscr;"
											2229: return "zwj;"
											2230: return "zwnj;"
											_: return ""

export fn entity_text(index: Int) String:
	if index < 1115:
		if index < 557:
			if index < 278:
				if index < 139:
					if index < 69:
						if index < 34:
							if index < 17:
								if index < 8:
									match index:
										0: return "\u{c6}"
										1: return "\u{c6}"
										2: return "\u{26}"
										3: return "\u{26}"
										4: return "\u{c1}"
										5: return "\u{c1}"
										6: return "\u{102}"
										7: return "\u{c2}"
										_: return ""
								else:
									if index < 12:
										match index:
											8: return "\u{c2}"
											9: return "\u{410}"
											10: return "\u{1d504}"
											11: return "\u{c0}"
											_: return ""
									else:
										match index:
											12: return "\u{c0}"
											13: return "\u{391}"
											14: return "\u{100}"
											15: return "\u{2a53}"
											16: return "\u{104}"
											_: return ""
							else:
								if index < 25:
									match index:
										17: return "\u{1d538}"
										18: return "\u{2061}"
										19: return "\u{c5}"
										20: return "\u{c5}"
										21: return "\u{1d49c}"
										22: return "\u{2254}"
										23: return "\u{c3}"
										24: return "\u{c3}"
										_: return ""
								else:
									if index < 29:
										match index:
											25: return "\u{c4}"
											26: return "\u{c4}"
											27: return "\u{2216}"
											28: return "\u{2ae7}"
											_: return ""
									else:
										match index:
											29: return "\u{2306}"
											30: return "\u{411}"
											31: return "\u{2235}"
											32: return "\u{212c}"
											33: return "\u{392}"
											_: return ""
						else:
							if index < 51:
								if index < 42:
									match index:
										34: return "\u{1d505}"
										35: return "\u{1d539}"
										36: return "\u{2d8}"
										37: return "\u{212c}"
										38: return "\u{224e}"
										39: return "\u{427}"
										40: return "\u{a9}"
										41: return "\u{a9}"
										_: return ""
								else:
									if index < 46:
										match index:
											42: return "\u{106}"
											43: return "\u{22d2}"
											44: return "\u{2145}"
											45: return "\u{212d}"
											_: return ""
									else:
										match index:
											46: return "\u{10c}"
											47: return "\u{c7}"
											48: return "\u{c7}"
											49: return "\u{108}"
											50: return "\u{2230}"
											_: return ""
							else:
								if index < 60:
									if index < 55:
										match index:
											51: return "\u{10a}"
											52: return "\u{b8}"
											53: return "\u{b7}"
											54: return "\u{212d}"
											_: return ""
									else:
										match index:
											55: return "\u{3a7}"
											56: return "\u{2299}"
											57: return "\u{2296}"
											58: return "\u{2295}"
											59: return "\u{2297}"
											_: return ""
								else:
									if index < 64:
										match index:
											60: return "\u{2232}"
											61: return "\u{201d}"
											62: return "\u{2019}"
											63: return "\u{2237}"
											_: return ""
									else:
										match index:
											64: return "\u{2a74}"
											65: return "\u{2261}"
											66: return "\u{222f}"
											67: return "\u{222e}"
											68: return "\u{2102}"
											_: return ""
					else:
						if index < 104:
							if index < 86:
								if index < 77:
									match index:
										69: return "\u{2210}"
										70: return "\u{2233}"
										71: return "\u{2a2f}"
										72: return "\u{1d49e}"
										73: return "\u{22d3}"
										74: return "\u{224d}"
										75: return "\u{2145}"
										76: return "\u{2911}"
										_: return ""
								else:
									if index < 81:
										match index:
											77: return "\u{402}"
											78: return "\u{405}"
											79: return "\u{40f}"
											80: return "\u{2021}"
											_: return ""
									else:
										match index:
											81: return "\u{21a1}"
											82: return "\u{2ae4}"
											83: return "\u{10e}"
											84: return "\u{414}"
											85: return "\u{2207}"
											_: return ""
							else:
								if index < 95:
									if index < 90:
										match index:
											86: return "\u{394}"
											87: return "\u{1d507}"
											88: return "\u{b4}"
											89: return "\u{2d9}"
											_: return ""
									else:
										match index:
											90: return "\u{2dd}"
											91: return "\u{60}"
											92: return "\u{2dc}"
											93: return "\u{22c4}"
											94: return "\u{2146}"
											_: return ""
								else:
									if index < 99:
										match index:
											95: return "\u{1d53b}"
											96: return "\u{a8}"
											97: return "\u{20dc}"
											98: return "\u{2250}"
											_: return ""
									else:
										match index:
											99: return "\u{222f}"
											100: return "\u{a8}"
											101: return "\u{21d3}"
											102: return "\u{21d0}"
											103: return "\u{21d4}"
											_: return ""
						else:
							if index < 121:
								if index < 112:
									match index:
										104: return "\u{2ae4}"
										105: return "\u{27f8}"
										106: return "\u{27fa}"
										107: return "\u{27f9}"
										108: return "\u{21d2}"
										109: return "\u{22a8}"
										110: return "\u{21d1}"
										111: return "\u{21d5}"
										_: return ""
								else:
									if index < 116:
										match index:
											112: return "\u{2225}"
											113: return "\u{2193}"
											114: return "\u{2913}"
											115: return "\u{21f5}"
											_: return ""
									else:
										match index:
											116: return "\u{311}"
											117: return "\u{2950}"
											118: return "\u{295e}"
											119: return "\u{21bd}"
											120: return "\u{2956}"
											_: return ""
							else:
								if index < 130:
									if index < 125:
										match index:
											121: return "\u{295f}"
											122: return "\u{21c1}"
											123: return "\u{2957}"
											124: return "\u{22a4}"
											_: return ""
									else:
										match index:
											125: return "\u{21a7}"
											126: return "\u{21d3}"
											127: return "\u{1d49f}"
											128: return "\u{110}"
											129: return "\u{14a}"
											_: return ""
								else:
									if index < 134:
										match index:
											130: return "\u{d0}"
											131: return "\u{d0}"
											132: return "\u{c9}"
											133: return "\u{c9}"
											_: return ""
									else:
										match index:
											134: return "\u{11a}"
											135: return "\u{ca}"
											136: return "\u{ca}"
											137: return "\u{42d}"
											138: return "\u{116}"
											_: return ""
				else:
					if index < 208:
						if index < 173:
							if index < 156:
								if index < 147:
									match index:
										139: return "\u{1d508}"
										140: return "\u{c8}"
										141: return "\u{c8}"
										142: return "\u{2208}"
										143: return "\u{112}"
										144: return "\u{25fb}"
										145: return "\u{25ab}"
										146: return "\u{118}"
										_: return ""
								else:
									if index < 151:
										match index:
											147: return "\u{1d53c}"
											148: return "\u{395}"
											149: return "\u{2a75}"
											150: return "\u{2242}"
											_: return ""
									else:
										match index:
											151: return "\u{21cc}"
											152: return "\u{2130}"
											153: return "\u{2a73}"
											154: return "\u{397}"
											155: return "\u{cb}"
											_: return ""
							else:
								if index < 164:
									match index:
										156: return "\u{cb}"
										157: return "\u{2203}"
										158: return "\u{2147}"
										159: return "\u{424}"
										160: return "\u{1d509}"
										161: return "\u{25fc}"
										162: return "\u{25aa}"
										163: return "\u{1d53d}"
										_: return ""
								else:
									if index < 168:
										match index:
											164: return "\u{2200}"
											165: return "\u{2131}"
											166: return "\u{2131}"
											167: return "\u{403}"
											_: return ""
									else:
										match index:
											168: return "\u{3e}"
											169: return "\u{3e}"
											170: return "\u{393}"
											171: return "\u{3dc}"
											172: return "\u{11e}"
											_: return ""
						else:
							if index < 190:
								if index < 181:
									match index:
										173: return "\u{122}"
										174: return "\u{11c}"
										175: return "\u{413}"
										176: return "\u{120}"
										177: return "\u{1d50a}"
										178: return "\u{22d9}"
										179: return "\u{1d53e}"
										180: return "\u{2265}"
										_: return ""
								else:
									if index < 185:
										match index:
											181: return "\u{22db}"
											182: return "\u{2267}"
											183: return "\u{2aa2}"
											184: return "\u{2277}"
											_: return ""
									else:
										match index:
											185: return "\u{2a7e}"
											186: return "\u{2273}"
											187: return "\u{1d4a2}"
											188: return "\u{226b}"
											189: return "\u{42a}"
											_: return ""
							else:
								if index < 199:
									if index < 194:
										match index:
											190: return "\u{2c7}"
											191: return "\u{5e}"
											192: return "\u{124}"
											193: return "\u{210c}"
											_: return ""
									else:
										match index:
											194: return "\u{210b}"
											195: return "\u{210d}"
											196: return "\u{2500}"
											197: return "\u{210b}"
											198: return "\u{126}"
											_: return ""
								else:
									if index < 203:
										match index:
											199: return "\u{224e}"
											200: return "\u{224f}"
											201: return "\u{415}"
											202: return "\u{132}"
											_: return ""
									else:
										match index:
											203: return "\u{401}"
											204: return "\u{cd}"
											205: return "\u{cd}"
											206: return "\u{ce}"
											207: return "\u{ce}"
											_: return ""
					else:
						if index < 243:
							if index < 225:
								if index < 216:
									match index:
										208: return "\u{418}"
										209: return "\u{130}"
										210: return "\u{2111}"
										211: return "\u{cc}"
										212: return "\u{cc}"
										213: return "\u{2111}"
										214: return "\u{12a}"
										215: return "\u{2148}"
										_: return ""
								else:
									if index < 220:
										match index:
											216: return "\u{21d2}"
											217: return "\u{222c}"
											218: return "\u{222b}"
											219: return "\u{22c2}"
											_: return ""
									else:
										match index:
											220: return "\u{2063}"
											221: return "\u{2062}"
											222: return "\u{12e}"
											223: return "\u{1d540}"
											224: return "\u{399}"
											_: return ""
							else:
								if index < 234:
									if index < 229:
										match index:
											225: return "\u{2110}"
											226: return "\u{128}"
											227: return "\u{406}"
											228: return "\u{cf}"
											_: return ""
									else:
										match index:
											229: return "\u{cf}"
											230: return "\u{134}"
											231: return "\u{419}"
											232: return "\u{1d50d}"
											233: return "\u{1d541}"
											_: return ""
								else:
									if index < 238:
										match index:
											234: return "\u{1d4a5}"
											235: return "\u{408}"
											236: return "\u{404}"
											237: return "\u{425}"
											_: return ""
									else:
										match index:
											238: return "\u{40c}"
											239: return "\u{39a}"
											240: return "\u{136}"
											241: return "\u{41a}"
											242: return "\u{1d50e}"
											_: return ""
						else:
							if index < 260:
								if index < 251:
									match index:
										243: return "\u{1d542}"
										244: return "\u{1d4a6}"
										245: return "\u{409}"
										246: return "\u{3c}"
										247: return "\u{3c}"
										248: return "\u{139}"
										249: return "\u{39b}"
										250: return "\u{27ea}"
										_: return ""
								else:
									if index < 255:
										match index:
											251: return "\u{2112}"
											252: return "\u{219e}"
											253: return "\u{13d}"
											254: return "\u{13b}"
											_: return ""
									else:
										match index:
											255: return "\u{41b}"
											256: return "\u{27e8}"
											257: return "\u{2190}"
											258: return "\u{21e4}"
											259: return "\u{21c6}"
											_: return ""
							else:
								if index < 269:
									if index < 264:
										match index:
											260: return "\u{2308}"
											261: return "\u{27e6}"
											262: return "\u{2961}"
											263: return "\u{21c3}"
											_: return ""
									else:
										match index:
											264: return "\u{2959}"
											265: return "\u{230a}"
											266: return "\u{2194}"
											267: return "\u{294e}"
											268: return "\u{22a3}"
											_: return ""
								else:
									if index < 273:
										match index:
											269: return "\u{21a4}"
											270: return "\u{295a}"
											271: return "\u{22b2}"
											272: return "\u{29cf}"
											_: return ""
									else:
										match index:
											273: return "\u{22b4}"
											274: return "\u{2951}"
											275: return "\u{2960}"
											276: return "\u{21bf}"
											277: return "\u{2958}"
											_: return ""
			else:
				if index < 417:
					if index < 347:
						if index < 312:
							if index < 295:
								if index < 286:
									match index:
										278: return "\u{21bc}"
										279: return "\u{2952}"
										280: return "\u{21d0}"
										281: return "\u{21d4}"
										282: return "\u{22da}"
										283: return "\u{2266}"
										284: return "\u{2276}"
										285: return "\u{2aa1}"
										_: return ""
								else:
									if index < 290:
										match index:
											286: return "\u{2a7d}"
											287: return "\u{2272}"
											288: return "\u{1d50f}"
											289: return "\u{22d8}"
											_: return ""
									else:
										match index:
											290: return "\u{21da}"
											291: return "\u{13f}"
											292: return "\u{27f5}"
											293: return "\u{27f7}"
											294: return "\u{27f6}"
											_: return ""
							else:
								if index < 303:
									match index:
										295: return "\u{27f8}"
										296: return "\u{27fa}"
										297: return "\u{27f9}"
										298: return "\u{1d543}"
										299: return "\u{2199}"
										300: return "\u{2198}"
										301: return "\u{2112}"
										302: return "\u{21b0}"
										_: return ""
								else:
									if index < 307:
										match index:
											303: return "\u{141}"
											304: return "\u{226a}"
											305: return "\u{2905}"
											306: return "\u{41c}"
											_: return ""
									else:
										match index:
											307: return "\u{205f}"
											308: return "\u{2133}"
											309: return "\u{1d510}"
											310: return "\u{2213}"
											311: return "\u{1d544}"
											_: return ""
						else:
							if index < 329:
								if index < 320:
									match index:
										312: return "\u{2133}"
										313: return "\u{39c}"
										314: return "\u{40a}"
										315: return "\u{143}"
										316: return "\u{147}"
										317: return "\u{145}"
										318: return "\u{41d}"
										319: return "\u{200b}"
										_: return ""
								else:
									if index < 324:
										match index:
											320: return "\u{200b}"
											321: return "\u{200b}"
											322: return "\u{200b}"
											323: return "\u{226b}"
											_: return ""
									else:
										match index:
											324: return "\u{226a}"
											325: return "\u{a}"
											326: return "\u{1d511}"
											327: return "\u{2060}"
											328: return "\u{a0}"
											_: return ""
							else:
								if index < 338:
									if index < 333:
										match index:
											329: return "\u{2115}"
											330: return "\u{2aec}"
											331: return "\u{2262}"
											332: return "\u{226d}"
											_: return ""
									else:
										match index:
											333: return "\u{2226}"
											334: return "\u{2209}"
											335: return "\u{2260}"
											336: return "\u{2242}\u{338}"
											337: return "\u{2204}"
											_: return ""
								else:
									if index < 342:
										match index:
											338: return "\u{226f}"
											339: return "\u{2271}"
											340: return "\u{2267}\u{338}"
											341: return "\u{226b}\u{338}"
											_: return ""
									else:
										match index:
											342: return "\u{2279}"
											343: return "\u{2a7e}\u{338}"
											344: return "\u{2275}"
											345: return "\u{224e}\u{338}"
											346: return "\u{224f}\u{338}"
											_: return ""
					else:
						if index < 382:
							if index < 364:
								if index < 355:
									match index:
										347: return "\u{22ea}"
										348: return "\u{29cf}\u{338}"
										349: return "\u{22ec}"
										350: return "\u{226e}"
										351: return "\u{2270}"
										352: return "\u{2278}"
										353: return "\u{226a}\u{338}"
										354: return "\u{2a7d}\u{338}"
										_: return ""
								else:
									if index < 359:
										match index:
											355: return "\u{2274}"
											356: return "\u{2aa2}\u{338}"
											357: return "\u{2aa1}\u{338}"
											358: return "\u{2280}"
											_: return ""
									else:
										match index:
											359: return "\u{2aaf}\u{338}"
											360: return "\u{22e0}"
											361: return "\u{220c}"
											362: return "\u{22eb}"
											363: return "\u{29d0}\u{338}"
											_: return ""
							else:
								if index < 373:
									if index < 368:
										match index:
											364: return "\u{22ed}"
											365: return "\u{228f}\u{338}"
											366: return "\u{22e2}"
											367: return "\u{2290}\u{338}"
											_: return ""
									else:
										match index:
											368: return "\u{22e3}"
											369: return "\u{2282}\u{20d2}"
											370: return "\u{2288}"
											371: return "\u{2281}"
											372: return "\u{2ab0}\u{338}"
											_: return ""
								else:
									if index < 377:
										match index:
											373: return "\u{22e1}"
											374: return "\u{227f}\u{338}"
											375: return "\u{2283}\u{20d2}"
											376: return "\u{2289}"
											_: return ""
									else:
										match index:
											377: return "\u{2241}"
											378: return "\u{2244}"
											379: return "\u{2247}"
											380: return "\u{2249}"
											381: return "\u{2224}"
											_: return ""
						else:
							if index < 399:
								if index < 390:
									match index:
										382: return "\u{1d4a9}"
										383: return "\u{d1}"
										384: return "\u{d1}"
										385: return "\u{39d}"
										386: return "\u{152}"
										387: return "\u{d3}"
										388: return "\u{d3}"
										389: return "\u{d4}"
										_: return ""
								else:
									if index < 394:
										match index:
											390: return "\u{d4}"
											391: return "\u{41e}"
											392: return "\u{150}"
											393: return "\u{1d512}"
											_: return ""
									else:
										match index:
											394: return "\u{d2}"
											395: return "\u{d2}"
											396: return "\u{14c}"
											397: return "\u{3a9}"
											398: return "\u{39f}"
											_: return ""
							else:
								if index < 408:
									if index < 403:
										match index:
											399: return "\u{1d546}"
											400: return "\u{201c}"
											401: return "\u{2018}"
											402: return "\u{2a54}"
											_: return ""
									else:
										match index:
											403: return "\u{1d4aa}"
											404: return "\u{d8}"
											405: return "\u{d8}"
											406: return "\u{d5}"
											407: return "\u{d5}"
											_: return ""
								else:
									if index < 412:
										match index:
											408: return "\u{2a37}"
											409: return "\u{d6}"
											410: return "\u{d6}"
											411: return "\u{203e}"
											_: return ""
									else:
										match index:
											412: return "\u{23de}"
											413: return "\u{23b4}"
											414: return "\u{23dc}"
											415: return "\u{2202}"
											416: return "\u{41f}"
											_: return ""
				else:
					if index < 487:
						if index < 452:
							if index < 434:
								if index < 425:
									match index:
										417: return "\u{1d513}"
										418: return "\u{3a6}"
										419: return "\u{3a0}"
										420: return "\u{b1}"
										421: return "\u{210c}"
										422: return "\u{2119}"
										423: return "\u{2abb}"
										424: return "\u{227a}"
										_: return ""
								else:
									if index < 429:
										match index:
											425: return "\u{2aaf}"
											426: return "\u{227c}"
											427: return "\u{227e}"
											428: return "\u{2033}"
											_: return ""
									else:
										match index:
											429: return "\u{220f}"
											430: return "\u{2237}"
											431: return "\u{221d}"
											432: return "\u{1d4ab}"
											433: return "\u{3a8}"
											_: return ""
							else:
								if index < 443:
									if index < 438:
										match index:
											434: return "\u{22}"
											435: return "\u{22}"
											436: return "\u{1d514}"
											437: return "\u{211a}"
											_: return ""
									else:
										match index:
											438: return "\u{1d4ac}"
											439: return "\u{2910}"
											440: return "\u{ae}"
											441: return "\u{ae}"
											442: return "\u{154}"
											_: return ""
								else:
									if index < 447:
										match index:
											443: return "\u{27eb}"
											444: return "\u{21a0}"
											445: return "\u{2916}"
											446: return "\u{158}"
											_: return ""
									else:
										match index:
											447: return "\u{156}"
											448: return "\u{420}"
											449: return "\u{211c}"
											450: return "\u{220b}"
											451: return "\u{21cb}"
											_: return ""
						else:
							if index < 469:
								if index < 460:
									match index:
										452: return "\u{296f}"
										453: return "\u{211c}"
										454: return "\u{3a1}"
										455: return "\u{27e9}"
										456: return "\u{2192}"
										457: return "\u{21e5}"
										458: return "\u{21c4}"
										459: return "\u{2309}"
										_: return ""
								else:
									if index < 464:
										match index:
											460: return "\u{27e7}"
											461: return "\u{295d}"
											462: return "\u{21c2}"
											463: return "\u{2955}"
											_: return ""
									else:
										match index:
											464: return "\u{230b}"
											465: return "\u{22a2}"
											466: return "\u{21a6}"
											467: return "\u{295b}"
											468: return "\u{22b3}"
											_: return ""
							else:
								if index < 478:
									if index < 473:
										match index:
											469: return "\u{29d0}"
											470: return "\u{22b5}"
											471: return "\u{294f}"
											472: return "\u{295c}"
											_: return ""
									else:
										match index:
											473: return "\u{21be}"
											474: return "\u{2954}"
											475: return "\u{21c0}"
											476: return "\u{2953}"
											477: return "\u{21d2}"
											_: return ""
								else:
									if index < 482:
										match index:
											478: return "\u{211d}"
											479: return "\u{2970}"
											480: return "\u{21db}"
											481: return "\u{211b}"
											_: return ""
									else:
										match index:
											482: return "\u{21b1}"
											483: return "\u{29f4}"
											484: return "\u{429}"
											485: return "\u{428}"
											486: return "\u{42c}"
											_: return ""
					else:
						if index < 522:
							if index < 504:
								if index < 495:
									match index:
										487: return "\u{15a}"
										488: return "\u{2abc}"
										489: return "\u{160}"
										490: return "\u{15e}"
										491: return "\u{15c}"
										492: return "\u{421}"
										493: return "\u{1d516}"
										494: return "\u{2193}"
										_: return ""
								else:
									if index < 499:
										match index:
											495: return "\u{2190}"
											496: return "\u{2192}"
											497: return "\u{2191}"
											498: return "\u{3a3}"
											_: return ""
									else:
										match index:
											499: return "\u{2218}"
											500: return "\u{1d54a}"
											501: return "\u{221a}"
											502: return "\u{25a1}"
											503: return "\u{2293}"
											_: return ""
							else:
								if index < 513:
									if index < 508:
										match index:
											504: return "\u{228f}"
											505: return "\u{2291}"
											506: return "\u{2290}"
											507: return "\u{2292}"
											_: return ""
									else:
										match index:
											508: return "\u{2294}"
											509: return "\u{1d4ae}"
											510: return "\u{22c6}"
											511: return "\u{22d0}"
											512: return "\u{22d0}"
											_: return ""
								else:
									if index < 517:
										match index:
											513: return "\u{2286}"
											514: return "\u{227b}"
											515: return "\u{2ab0}"
											516: return "\u{227d}"
											_: return ""
									else:
										match index:
											517: return "\u{227f}"
											518: return "\u{220b}"
											519: return "\u{2211}"
											520: return "\u{22d1}"
											521: return "\u{2283}"
											_: return ""
						else:
							if index < 539:
								if index < 530:
									match index:
										522: return "\u{2287}"
										523: return "\u{22d1}"
										524: return "\u{de}"
										525: return "\u{de}"
										526: return "\u{2122}"
										527: return "\u{40b}"
										528: return "\u{426}"
										529: return "\u{9}"
										_: return ""
								else:
									if index < 534:
										match index:
											530: return "\u{3a4}"
											531: return "\u{164}"
											532: return "\u{162}"
											533: return "\u{422}"
											_: return ""
									else:
										match index:
											534: return "\u{1d517}"
											535: return "\u{2234}"
											536: return "\u{398}"
											537: return "\u{205f}\u{200a}"
											538: return "\u{2009}"
											_: return ""
							else:
								if index < 548:
									if index < 543:
										match index:
											539: return "\u{223c}"
											540: return "\u{2243}"
											541: return "\u{2245}"
											542: return "\u{2248}"
											_: return ""
									else:
										match index:
											543: return "\u{1d54b}"
											544: return "\u{20db}"
											545: return "\u{1d4af}"
											546: return "\u{166}"
											547: return "\u{da}"
											_: return ""
								else:
									if index < 552:
										match index:
											548: return "\u{da}"
											549: return "\u{219f}"
											550: return "\u{2949}"
											551: return "\u{40e}"
											_: return ""
									else:
										match index:
											552: return "\u{16c}"
											553: return "\u{db}"
											554: return "\u{db}"
											555: return "\u{423}"
											556: return "\u{170}"
											_: return ""
		else:
			if index < 836:
				if index < 696:
					if index < 626:
						if index < 591:
							if index < 574:
								if index < 565:
									match index:
										557: return "\u{1d518}"
										558: return "\u{d9}"
										559: return "\u{d9}"
										560: return "\u{16a}"
										561: return "\u{5f}"
										562: return "\u{23df}"
										563: return "\u{23b5}"
										564: return "\u{23dd}"
										_: return ""
								else:
									if index < 569:
										match index:
											565: return "\u{22c3}"
											566: return "\u{228e}"
											567: return "\u{172}"
											568: return "\u{1d54c}"
											_: return ""
									else:
										match index:
											569: return "\u{2191}"
											570: return "\u{2912}"
											571: return "\u{21c5}"
											572: return "\u{2195}"
											573: return "\u{296e}"
											_: return ""
							else:
								if index < 582:
									match index:
										574: return "\u{22a5}"
										575: return "\u{21a5}"
										576: return "\u{21d1}"
										577: return "\u{21d5}"
										578: return "\u{2196}"
										579: return "\u{2197}"
										580: return "\u{3d2}"
										581: return "\u{3a5}"
										_: return ""
								else:
									if index < 586:
										match index:
											582: return "\u{16e}"
											583: return "\u{1d4b0}"
											584: return "\u{168}"
											585: return "\u{dc}"
											_: return ""
									else:
										match index:
											586: return "\u{dc}"
											587: return "\u{22ab}"
											588: return "\u{2aeb}"
											589: return "\u{412}"
											590: return "\u{22a9}"
											_: return ""
						else:
							if index < 608:
								if index < 599:
									match index:
										591: return "\u{2ae6}"
										592: return "\u{22c1}"
										593: return "\u{2016}"
										594: return "\u{2016}"
										595: return "\u{2223}"
										596: return "\u{7c}"
										597: return "\u{2758}"
										598: return "\u{2240}"
										_: return ""
								else:
									if index < 603:
										match index:
											599: return "\u{200a}"
											600: return "\u{1d519}"
											601: return "\u{1d54d}"
											602: return "\u{1d4b1}"
											_: return ""
									else:
										match index:
											603: return "\u{22aa}"
											604: return "\u{174}"
											605: return "\u{22c0}"
											606: return "\u{1d51a}"
											607: return "\u{1d54e}"
											_: return ""
							else:
								if index < 617:
									if index < 612:
										match index:
											608: return "\u{1d4b2}"
											609: return "\u{1d51b}"
											610: return "\u{39e}"
											611: return "\u{1d54f}"
											_: return ""
									else:
										match index:
											612: return "\u{1d4b3}"
											613: return "\u{42f}"
											614: return "\u{407}"
											615: return "\u{42e}"
											616: return "\u{dd}"
											_: return ""
								else:
									if index < 621:
										match index:
											617: return "\u{dd}"
											618: return "\u{176}"
											619: return "\u{42b}"
											620: return "\u{1d51c}"
											_: return ""
									else:
										match index:
											621: return "\u{1d550}"
											622: return "\u{1d4b4}"
											623: return "\u{178}"
											624: return "\u{416}"
											625: return "\u{179}"
											_: return ""
					else:
						if index < 661:
							if index < 643:
								if index < 634:
									match index:
										626: return "\u{17d}"
										627: return "\u{417}"
										628: return "\u{17b}"
										629: return "\u{200b}"
										630: return "\u{396}"
										631: return "\u{2128}"
										632: return "\u{2124}"
										633: return "\u{1d4b5}"
										_: return ""
								else:
									if index < 638:
										match index:
											634: return "\u{e1}"
											635: return "\u{e1}"
											636: return "\u{103}"
											637: return "\u{223e}"
											_: return ""
									else:
										match index:
											638: return "\u{223e}\u{333}"
											639: return "\u{223f}"
											640: return "\u{e2}"
											641: return "\u{e2}"
											642: return "\u{b4}"
											_: return ""
							else:
								if index < 652:
									if index < 647:
										match index:
											643: return "\u{b4}"
											644: return "\u{430}"
											645: return "\u{e6}"
											646: return "\u{e6}"
											_: return ""
									else:
										match index:
											647: return "\u{2061}"
											648: return "\u{1d51e}"
											649: return "\u{e0}"
											650: return "\u{e0}"
											651: return "\u{2135}"
											_: return ""
								else:
									if index < 656:
										match index:
											652: return "\u{2135}"
											653: return "\u{3b1}"
											654: return "\u{101}"
											655: return "\u{2a3f}"
											_: return ""
									else:
										match index:
											656: return "\u{26}"
											657: return "\u{26}"
											658: return "\u{2227}"
											659: return "\u{2a55}"
											660: return "\u{2a5c}"
											_: return ""
						else:
							if index < 678:
								if index < 669:
									match index:
										661: return "\u{2a58}"
										662: return "\u{2a5a}"
										663: return "\u{2220}"
										664: return "\u{29a4}"
										665: return "\u{2220}"
										666: return "\u{2221}"
										667: return "\u{29a8}"
										668: return "\u{29a9}"
										_: return ""
								else:
									if index < 673:
										match index:
											669: return "\u{29aa}"
											670: return "\u{29ab}"
											671: return "\u{29ac}"
											672: return "\u{29ad}"
											_: return ""
									else:
										match index:
											673: return "\u{29ae}"
											674: return "\u{29af}"
											675: return "\u{221f}"
											676: return "\u{22be}"
											677: return "\u{299d}"
											_: return ""
							else:
								if index < 687:
									if index < 682:
										match index:
											678: return "\u{2222}"
											679: return "\u{c5}"
											680: return "\u{237c}"
											681: return "\u{105}"
											_: return ""
									else:
										match index:
											682: return "\u{1d552}"
											683: return "\u{2248}"
											684: return "\u{2a70}"
											685: return "\u{2a6f}"
											686: return "\u{224a}"
											_: return ""
								else:
									if index < 691:
										match index:
											687: return "\u{224b}"
											688: return "\u{27}"
											689: return "\u{2248}"
											690: return "\u{224a}"
											_: return ""
									else:
										match index:
											691: return "\u{e5}"
											692: return "\u{e5}"
											693: return "\u{1d4b6}"
											694: return "\u{2a}"
											695: return "\u{2248}"
											_: return ""
				else:
					if index < 766:
						if index < 731:
							if index < 713:
								if index < 704:
									match index:
										696: return "\u{224d}"
										697: return "\u{e3}"
										698: return "\u{e3}"
										699: return "\u{e4}"
										700: return "\u{e4}"
										701: return "\u{2233}"
										702: return "\u{2a11}"
										703: return "\u{2aed}"
										_: return ""
								else:
									if index < 708:
										match index:
											704: return "\u{224c}"
											705: return "\u{3f6}"
											706: return "\u{2035}"
											707: return "\u{223d}"
											_: return ""
									else:
										match index:
											708: return "\u{22cd}"
											709: return "\u{22bd}"
											710: return "\u{2305}"
											711: return "\u{2305}"
											712: return "\u{23b5}"
											_: return ""
							else:
								if index < 722:
									if index < 717:
										match index:
											713: return "\u{23b6}"
											714: return "\u{224c}"
											715: return "\u{431}"
											716: return "\u{201e}"
											_: return ""
									else:
										match index:
											717: return "\u{2235}"
											718: return "\u{2235}"
											719: return "\u{29b0}"
											720: return "\u{3f6}"
											721: return "\u{212c}"
											_: return ""
								else:
									if index < 726:
										match index:
											722: return "\u{3b2}"
											723: return "\u{2136}"
											724: return "\u{226c}"
											725: return "\u{1d51f}"
											_: return ""
									else:
										match index:
											726: return "\u{22c2}"
											727: return "\u{25ef}"
											728: return "\u{22c3}"
											729: return "\u{2a00}"
											730: return "\u{2a01}"
											_: return ""
						else:
							if index < 748:
								if index < 739:
									match index:
										731: return "\u{2a02}"
										732: return "\u{2a06}"
										733: return "\u{2605}"
										734: return "\u{25bd}"
										735: return "\u{25b3}"
										736: return "\u{2a04}"
										737: return "\u{22c1}"
										738: return "\u{22c0}"
										_: return ""
								else:
									if index < 743:
										match index:
											739: return "\u{290d}"
											740: return "\u{29eb}"
											741: return "\u{25aa}"
											742: return "\u{25b4}"
											_: return ""
									else:
										match index:
											743: return "\u{25be}"
											744: return "\u{25c2}"
											745: return "\u{25b8}"
											746: return "\u{2423}"
											747: return "\u{2592}"
											_: return ""
							else:
								if index < 757:
									if index < 752:
										match index:
											748: return "\u{2591}"
											749: return "\u{2593}"
											750: return "\u{2588}"
											751: return "\u{3d}\u{20e5}"
											_: return ""
									else:
										match index:
											752: return "\u{2261}\u{20e5}"
											753: return "\u{2310}"
											754: return "\u{1d553}"
											755: return "\u{22a5}"
											756: return "\u{22a5}"
											_: return ""
								else:
									if index < 761:
										match index:
											757: return "\u{22c8}"
											758: return "\u{2557}"
											759: return "\u{2554}"
											760: return "\u{2556}"
											_: return ""
									else:
										match index:
											761: return "\u{2553}"
											762: return "\u{2550}"
											763: return "\u{2566}"
											764: return "\u{2569}"
											765: return "\u{2564}"
											_: return ""
					else:
						if index < 801:
							if index < 783:
								if index < 774:
									match index:
										766: return "\u{2567}"
										767: return "\u{255d}"
										768: return "\u{255a}"
										769: return "\u{255c}"
										770: return "\u{2559}"
										771: return "\u{2551}"
										772: return "\u{256c}"
										773: return "\u{2563}"
										_: return ""
								else:
									if index < 778:
										match index:
											774: return "\u{2560}"
											775: return "\u{256b}"
											776: return "\u{2562}"
											777: return "\u{255f}"
											_: return ""
									else:
										match index:
											778: return "\u{29c9}"
											779: return "\u{2555}"
											780: return "\u{2552}"
											781: return "\u{2510}"
											782: return "\u{250c}"
											_: return ""
							else:
								if index < 792:
									if index < 787:
										match index:
											783: return "\u{2500}"
											784: return "\u{2565}"
											785: return "\u{2568}"
											786: return "\u{252c}"
											_: return ""
									else:
										match index:
											787: return "\u{2534}"
											788: return "\u{229f}"
											789: return "\u{229e}"
											790: return "\u{22a0}"
											791: return "\u{255b}"
											_: return ""
								else:
									if index < 796:
										match index:
											792: return "\u{2558}"
											793: return "\u{2518}"
											794: return "\u{2514}"
											795: return "\u{2502}"
											_: return ""
									else:
										match index:
											796: return "\u{256a}"
											797: return "\u{2561}"
											798: return "\u{255e}"
											799: return "\u{253c}"
											800: return "\u{2524}"
											_: return ""
						else:
							if index < 818:
								if index < 809:
									match index:
										801: return "\u{251c}"
										802: return "\u{2035}"
										803: return "\u{2d8}"
										804: return "\u{a6}"
										805: return "\u{a6}"
										806: return "\u{1d4b7}"
										807: return "\u{204f}"
										808: return "\u{223d}"
										_: return ""
								else:
									if index < 813:
										match index:
											809: return "\u{22cd}"
											810: return "\u{5c}"
											811: return "\u{29c5}"
											812: return "\u{27c8}"
											_: return ""
									else:
										match index:
											813: return "\u{2022}"
											814: return "\u{2022}"
											815: return "\u{224e}"
											816: return "\u{2aae}"
											817: return "\u{224f}"
											_: return ""
							else:
								if index < 827:
									if index < 822:
										match index:
											818: return "\u{224f}"
											819: return "\u{107}"
											820: return "\u{2229}"
											821: return "\u{2a44}"
											_: return ""
									else:
										match index:
											822: return "\u{2a49}"
											823: return "\u{2a4b}"
											824: return "\u{2a47}"
											825: return "\u{2a40}"
											826: return "\u{2229}\u{fe00}"
											_: return ""
								else:
									if index < 831:
										match index:
											827: return "\u{2041}"
											828: return "\u{2c7}"
											829: return "\u{2a4d}"
											830: return "\u{10d}"
											_: return ""
									else:
										match index:
											831: return "\u{e7}"
											832: return "\u{e7}"
											833: return "\u{109}"
											834: return "\u{2a4c}"
											835: return "\u{2a50}"
											_: return ""
			else:
				if index < 975:
					if index < 905:
						if index < 870:
							if index < 853:
								if index < 844:
									match index:
										836: return "\u{10b}"
										837: return "\u{b8}"
										838: return "\u{b8}"
										839: return "\u{29b2}"
										840: return "\u{a2}"
										841: return "\u{a2}"
										842: return "\u{b7}"
										843: return "\u{1d520}"
										_: return ""
								else:
									if index < 848:
										match index:
											844: return "\u{447}"
											845: return "\u{2713}"
											846: return "\u{2713}"
											847: return "\u{3c7}"
											_: return ""
									else:
										match index:
											848: return "\u{25cb}"
											849: return "\u{29c3}"
											850: return "\u{2c6}"
											851: return "\u{2257}"
											852: return "\u{21ba}"
											_: return ""
							else:
								if index < 861:
									match index:
										853: return "\u{21bb}"
										854: return "\u{ae}"
										855: return "\u{24c8}"
										856: return "\u{229b}"
										857: return "\u{229a}"
										858: return "\u{229d}"
										859: return "\u{2257}"
										860: return "\u{2a10}"
										_: return ""
								else:
									if index < 865:
										match index:
											861: return "\u{2aef}"
											862: return "\u{29c2}"
											863: return "\u{2663}"
											864: return "\u{2663}"
											_: return ""
									else:
										match index:
											865: return "\u{3a}"
											866: return "\u{2254}"
											867: return "\u{2254}"
											868: return "\u{2c}"
											869: return "\u{40}"
											_: return ""
						else:
							if index < 887:
								if index < 878:
									match index:
										870: return "\u{2201}"
										871: return "\u{2218}"
										872: return "\u{2201}"
										873: return "\u{2102}"
										874: return "\u{2245}"
										875: return "\u{2a6d}"
										876: return "\u{222e}"
										877: return "\u{1d554}"
										_: return ""
								else:
									if index < 882:
										match index:
											878: return "\u{2210}"
											879: return "\u{a9}"
											880: return "\u{a9}"
											881: return "\u{2117}"
											_: return ""
									else:
										match index:
											882: return "\u{21b5}"
											883: return "\u{2717}"
											884: return "\u{1d4b8}"
											885: return "\u{2acf}"
											886: return "\u{2ad1}"
											_: return ""
							else:
								if index < 896:
									if index < 891:
										match index:
											887: return "\u{2ad0}"
											888: return "\u{2ad2}"
											889: return "\u{22ef}"
											890: return "\u{2938}"
											_: return ""
									else:
										match index:
											891: return "\u{2935}"
											892: return "\u{22de}"
											893: return "\u{22df}"
											894: return "\u{21b6}"
											895: return "\u{293d}"
											_: return ""
								else:
									if index < 900:
										match index:
											896: return "\u{222a}"
											897: return "\u{2a48}"
											898: return "\u{2a46}"
											899: return "\u{2a4a}"
											_: return ""
									else:
										match index:
											900: return "\u{228d}"
											901: return "\u{2a45}"
											902: return "\u{222a}\u{fe00}"
											903: return "\u{21b7}"
											904: return "\u{293c}"
											_: return ""
					else:
						if index < 940:
							if index < 922:
								if index < 913:
									match index:
										905: return "\u{22de}"
										906: return "\u{22df}"
										907: return "\u{22ce}"
										908: return "\u{22cf}"
										909: return "\u{a4}"
										910: return "\u{a4}"
										911: return "\u{21b6}"
										912: return "\u{21b7}"
										_: return ""
								else:
									if index < 917:
										match index:
											913: return "\u{22ce}"
											914: return "\u{22cf}"
											915: return "\u{2232}"
											916: return "\u{2231}"
											_: return ""
									else:
										match index:
											917: return "\u{232d}"
											918: return "\u{21d3}"
											919: return "\u{2965}"
											920: return "\u{2020}"
											921: return "\u{2138}"
											_: return ""
							else:
								if index < 931:
									if index < 926:
										match index:
											922: return "\u{2193}"
											923: return "\u{2010}"
											924: return "\u{22a3}"
											925: return "\u{290f}"
											_: return ""
									else:
										match index:
											926: return "\u{2dd}"
											927: return "\u{10f}"
											928: return "\u{434}"
											929: return "\u{2146}"
											930: return "\u{2021}"
											_: return ""
								else:
									if index < 935:
										match index:
											931: return "\u{21ca}"
											932: return "\u{2a77}"
											933: return "\u{b0}"
											934: return "\u{b0}"
											_: return ""
									else:
										match index:
											935: return "\u{3b4}"
											936: return "\u{29b1}"
											937: return "\u{297f}"
											938: return "\u{1d521}"
											939: return "\u{21c3}"
											_: return ""
						else:
							if index < 957:
								if index < 948:
									match index:
										940: return "\u{21c2}"
										941: return "\u{22c4}"
										942: return "\u{22c4}"
										943: return "\u{2666}"
										944: return "\u{2666}"
										945: return "\u{a8}"
										946: return "\u{3dd}"
										947: return "\u{22f2}"
										_: return ""
								else:
									if index < 952:
										match index:
											948: return "\u{f7}"
											949: return "\u{f7}"
											950: return "\u{f7}"
											951: return "\u{22c7}"
											_: return ""
									else:
										match index:
											952: return "\u{22c7}"
											953: return "\u{452}"
											954: return "\u{231e}"
											955: return "\u{230d}"
											956: return "\u{24}"
											_: return ""
							else:
								if index < 966:
									if index < 961:
										match index:
											957: return "\u{1d555}"
											958: return "\u{2d9}"
											959: return "\u{2250}"
											960: return "\u{2251}"
											_: return ""
									else:
										match index:
											961: return "\u{2238}"
											962: return "\u{2214}"
											963: return "\u{22a1}"
											964: return "\u{2306}"
											965: return "\u{2193}"
											_: return ""
								else:
									if index < 970:
										match index:
											966: return "\u{21ca}"
											967: return "\u{21c3}"
											968: return "\u{21c2}"
											969: return "\u{2910}"
											_: return ""
									else:
										match index:
											970: return "\u{231f}"
											971: return "\u{230c}"
											972: return "\u{1d4b9}"
											973: return "\u{455}"
											974: return "\u{29f6}"
											_: return ""
				else:
					if index < 1045:
						if index < 1010:
							if index < 992:
								if index < 983:
									match index:
										975: return "\u{111}"
										976: return "\u{22f1}"
										977: return "\u{25bf}"
										978: return "\u{25be}"
										979: return "\u{21f5}"
										980: return "\u{296f}"
										981: return "\u{29a6}"
										982: return "\u{45f}"
										_: return ""
								else:
									if index < 987:
										match index:
											983: return "\u{27ff}"
											984: return "\u{2a77}"
											985: return "\u{2251}"
											986: return "\u{e9}"
											_: return ""
									else:
										match index:
											987: return "\u{e9}"
											988: return "\u{2a6e}"
											989: return "\u{11b}"
											990: return "\u{2256}"
											991: return "\u{ea}"
											_: return ""
							else:
								if index < 1001:
									if index < 996:
										match index:
											992: return "\u{ea}"
											993: return "\u{2255}"
											994: return "\u{44d}"
											995: return "\u{117}"
											_: return ""
									else:
										match index:
											996: return "\u{2147}"
											997: return "\u{2252}"
											998: return "\u{1d522}"
											999: return "\u{2a9a}"
											1000: return "\u{e8}"
											_: return ""
								else:
									if index < 1005:
										match index:
											1001: return "\u{e8}"
											1002: return "\u{2a96}"
											1003: return "\u{2a98}"
											1004: return "\u{2a99}"
											_: return ""
									else:
										match index:
											1005: return "\u{23e7}"
											1006: return "\u{2113}"
											1007: return "\u{2a95}"
											1008: return "\u{2a97}"
											1009: return "\u{113}"
											_: return ""
						else:
							if index < 1027:
								if index < 1018:
									match index:
										1010: return "\u{2205}"
										1011: return "\u{2205}"
										1012: return "\u{2205}"
										1013: return "\u{2004}"
										1014: return "\u{2005}"
										1015: return "\u{2003}"
										1016: return "\u{14b}"
										1017: return "\u{2002}"
										_: return ""
								else:
									if index < 1022:
										match index:
											1018: return "\u{119}"
											1019: return "\u{1d556}"
											1020: return "\u{22d5}"
											1021: return "\u{29e3}"
											_: return ""
									else:
										match index:
											1022: return "\u{2a71}"
											1023: return "\u{3b5}"
											1024: return "\u{3b5}"
											1025: return "\u{3f5}"
											1026: return "\u{2256}"
											_: return ""
							else:
								if index < 1036:
									if index < 1031:
										match index:
											1027: return "\u{2255}"
											1028: return "\u{2242}"
											1029: return "\u{2a96}"
											1030: return "\u{2a95}"
											_: return ""
									else:
										match index:
											1031: return "\u{3d}"
											1032: return "\u{225f}"
											1033: return "\u{2261}"
											1034: return "\u{2a78}"
											1035: return "\u{29e5}"
											_: return ""
								else:
									if index < 1040:
										match index:
											1036: return "\u{2253}"
											1037: return "\u{2971}"
											1038: return "\u{212f}"
											1039: return "\u{2250}"
											_: return ""
									else:
										match index:
											1040: return "\u{2242}"
											1041: return "\u{3b7}"
											1042: return "\u{f0}"
											1043: return "\u{f0}"
											1044: return "\u{eb}"
											_: return ""
					else:
						if index < 1080:
							if index < 1062:
								if index < 1053:
									match index:
										1045: return "\u{eb}"
										1046: return "\u{20ac}"
										1047: return "\u{21}"
										1048: return "\u{2203}"
										1049: return "\u{2130}"
										1050: return "\u{2147}"
										1051: return "\u{2252}"
										1052: return "\u{444}"
										_: return ""
								else:
									if index < 1057:
										match index:
											1053: return "\u{2640}"
											1054: return "\u{fb03}"
											1055: return "\u{fb00}"
											1056: return "\u{fb04}"
											_: return ""
									else:
										match index:
											1057: return "\u{1d523}"
											1058: return "\u{fb01}"
											1059: return "\u{66}\u{6a}"
											1060: return "\u{266d}"
											1061: return "\u{fb02}"
											_: return ""
							else:
								if index < 1071:
									if index < 1066:
										match index:
											1062: return "\u{25b1}"
											1063: return "\u{192}"
											1064: return "\u{1d557}"
											1065: return "\u{2200}"
											_: return ""
									else:
										match index:
											1066: return "\u{22d4}"
											1067: return "\u{2ad9}"
											1068: return "\u{2a0d}"
											1069: return "\u{bd}"
											1070: return "\u{bd}"
											_: return ""
								else:
									if index < 1075:
										match index:
											1071: return "\u{2153}"
											1072: return "\u{bc}"
											1073: return "\u{bc}"
											1074: return "\u{2155}"
											_: return ""
									else:
										match index:
											1075: return "\u{2159}"
											1076: return "\u{215b}"
											1077: return "\u{2154}"
											1078: return "\u{2156}"
											1079: return "\u{be}"
											_: return ""
						else:
							if index < 1097:
								if index < 1088:
									match index:
										1080: return "\u{be}"
										1081: return "\u{2157}"
										1082: return "\u{215c}"
										1083: return "\u{2158}"
										1084: return "\u{215a}"
										1085: return "\u{215d}"
										1086: return "\u{215e}"
										1087: return "\u{2044}"
										_: return ""
								else:
									if index < 1092:
										match index:
											1088: return "\u{2322}"
											1089: return "\u{1d4bb}"
											1090: return "\u{2267}"
											1091: return "\u{2a8c}"
											_: return ""
									else:
										match index:
											1092: return "\u{1f5}"
											1093: return "\u{3b3}"
											1094: return "\u{3dd}"
											1095: return "\u{2a86}"
											1096: return "\u{11f}"
											_: return ""
							else:
								if index < 1106:
									if index < 1101:
										match index:
											1097: return "\u{11d}"
											1098: return "\u{433}"
											1099: return "\u{121}"
											1100: return "\u{2265}"
											_: return ""
									else:
										match index:
											1101: return "\u{22db}"
											1102: return "\u{2265}"
											1103: return "\u{2267}"
											1104: return "\u{2a7e}"
											1105: return "\u{2a7e}"
											_: return ""
								else:
									if index < 1110:
										match index:
											1106: return "\u{2aa9}"
											1107: return "\u{2a80}"
											1108: return "\u{2a82}"
											1109: return "\u{2a84}"
											_: return ""
									else:
										match index:
											1110: return "\u{22db}\u{fe00}"
											1111: return "\u{2a94}"
											1112: return "\u{1d524}"
											1113: return "\u{226b}"
											1114: return "\u{22d9}"
											_: return ""
	else:
		if index < 1673:
			if index < 1394:
				if index < 1254:
					if index < 1184:
						if index < 1149:
							if index < 1132:
								if index < 1123:
									match index:
										1115: return "\u{2137}"
										1116: return "\u{453}"
										1117: return "\u{2277}"
										1118: return "\u{2a92}"
										1119: return "\u{2aa5}"
										1120: return "\u{2aa4}"
										1121: return "\u{2269}"
										1122: return "\u{2a8a}"
										_: return ""
								else:
									if index < 1127:
										match index:
											1123: return "\u{2a8a}"
											1124: return "\u{2a88}"
											1125: return "\u{2a88}"
											1126: return "\u{2269}"
											_: return ""
									else:
										match index:
											1127: return "\u{22e7}"
											1128: return "\u{1d558}"
											1129: return "\u{60}"
											1130: return "\u{210a}"
											1131: return "\u{2273}"
											_: return ""
							else:
								if index < 1140:
									match index:
										1132: return "\u{2a8e}"
										1133: return "\u{2a90}"
										1134: return "\u{3e}"
										1135: return "\u{3e}"
										1136: return "\u{2aa7}"
										1137: return "\u{2a7a}"
										1138: return "\u{22d7}"
										1139: return "\u{2995}"
										_: return ""
								else:
									if index < 1144:
										match index:
											1140: return "\u{2a7c}"
											1141: return "\u{2a86}"
											1142: return "\u{2978}"
											1143: return "\u{22d7}"
											_: return ""
									else:
										match index:
											1144: return "\u{22db}"
											1145: return "\u{2a8c}"
											1146: return "\u{2277}"
											1147: return "\u{2273}"
											1148: return "\u{2269}\u{fe00}"
											_: return ""
						else:
							if index < 1166:
								if index < 1157:
									match index:
										1149: return "\u{2269}\u{fe00}"
										1150: return "\u{21d4}"
										1151: return "\u{200a}"
										1152: return "\u{bd}"
										1153: return "\u{210b}"
										1154: return "\u{44a}"
										1155: return "\u{2194}"
										1156: return "\u{2948}"
										_: return ""
								else:
									if index < 1161:
										match index:
											1157: return "\u{21ad}"
											1158: return "\u{210f}"
											1159: return "\u{125}"
											1160: return "\u{2665}"
											_: return ""
									else:
										match index:
											1161: return "\u{2665}"
											1162: return "\u{2026}"
											1163: return "\u{22b9}"
											1164: return "\u{1d525}"
											1165: return "\u{2925}"
											_: return ""
							else:
								if index < 1175:
									if index < 1170:
										match index:
											1166: return "\u{2926}"
											1167: return "\u{21ff}"
											1168: return "\u{223b}"
											1169: return "\u{21a9}"
											_: return ""
									else:
										match index:
											1170: return "\u{21aa}"
											1171: return "\u{1d559}"
											1172: return "\u{2015}"
											1173: return "\u{1d4bd}"
											1174: return "\u{210f}"
											_: return ""
								else:
									if index < 1179:
										match index:
											1175: return "\u{127}"
											1176: return "\u{2043}"
											1177: return "\u{2010}"
											1178: return "\u{ed}"
											_: return ""
									else:
										match index:
											1179: return "\u{ed}"
											1180: return "\u{2063}"
											1181: return "\u{ee}"
											1182: return "\u{ee}"
											1183: return "\u{438}"
											_: return ""
					else:
						if index < 1219:
							if index < 1201:
								if index < 1192:
									match index:
										1184: return "\u{435}"
										1185: return "\u{a1}"
										1186: return "\u{a1}"
										1187: return "\u{21d4}"
										1188: return "\u{1d526}"
										1189: return "\u{ec}"
										1190: return "\u{ec}"
										1191: return "\u{2148}"
										_: return ""
								else:
									if index < 1196:
										match index:
											1192: return "\u{2a0c}"
											1193: return "\u{222d}"
											1194: return "\u{29dc}"
											1195: return "\u{2129}"
											_: return ""
									else:
										match index:
											1196: return "\u{133}"
											1197: return "\u{12b}"
											1198: return "\u{2111}"
											1199: return "\u{2110}"
											1200: return "\u{2111}"
											_: return ""
							else:
								if index < 1210:
									if index < 1205:
										match index:
											1201: return "\u{131}"
											1202: return "\u{22b7}"
											1203: return "\u{1b5}"
											1204: return "\u{2208}"
											_: return ""
									else:
										match index:
											1205: return "\u{2105}"
											1206: return "\u{221e}"
											1207: return "\u{29dd}"
											1208: return "\u{131}"
											1209: return "\u{222b}"
											_: return ""
								else:
									if index < 1214:
										match index:
											1210: return "\u{22ba}"
											1211: return "\u{2124}"
											1212: return "\u{22ba}"
											1213: return "\u{2a17}"
											_: return ""
									else:
										match index:
											1214: return "\u{2a3c}"
											1215: return "\u{451}"
											1216: return "\u{12f}"
											1217: return "\u{1d55a}"
											1218: return "\u{3b9}"
											_: return ""
						else:
							if index < 1236:
								if index < 1227:
									match index:
										1219: return "\u{2a3c}"
										1220: return "\u{bf}"
										1221: return "\u{bf}"
										1222: return "\u{1d4be}"
										1223: return "\u{2208}"
										1224: return "\u{22f9}"
										1225: return "\u{22f5}"
										1226: return "\u{22f4}"
										_: return ""
								else:
									if index < 1231:
										match index:
											1227: return "\u{22f3}"
											1228: return "\u{2208}"
											1229: return "\u{2062}"
											1230: return "\u{129}"
											_: return ""
									else:
										match index:
											1231: return "\u{456}"
											1232: return "\u{ef}"
											1233: return "\u{ef}"
											1234: return "\u{135}"
											1235: return "\u{439}"
											_: return ""
							else:
								if index < 1245:
									if index < 1240:
										match index:
											1236: return "\u{1d527}"
											1237: return "\u{237}"
											1238: return "\u{1d55b}"
											1239: return "\u{1d4bf}"
											_: return ""
									else:
										match index:
											1240: return "\u{458}"
											1241: return "\u{454}"
											1242: return "\u{3ba}"
											1243: return "\u{3f0}"
											1244: return "\u{137}"
											_: return ""
								else:
									if index < 1249:
										match index:
											1245: return "\u{43a}"
											1246: return "\u{1d528}"
											1247: return "\u{138}"
											1248: return "\u{445}"
											_: return ""
									else:
										match index:
											1249: return "\u{45c}"
											1250: return "\u{1d55c}"
											1251: return "\u{1d4c0}"
											1252: return "\u{21da}"
											1253: return "\u{21d0}"
											_: return ""
				else:
					if index < 1324:
						if index < 1289:
							if index < 1271:
								if index < 1262:
									match index:
										1254: return "\u{291b}"
										1255: return "\u{290e}"
										1256: return "\u{2266}"
										1257: return "\u{2a8b}"
										1258: return "\u{2962}"
										1259: return "\u{13a}"
										1260: return "\u{29b4}"
										1261: return "\u{2112}"
										_: return ""
								else:
									if index < 1266:
										match index:
											1262: return "\u{3bb}"
											1263: return "\u{27e8}"
											1264: return "\u{2991}"
											1265: return "\u{27e8}"
											_: return ""
									else:
										match index:
											1266: return "\u{2a85}"
											1267: return "\u{ab}"
											1268: return "\u{ab}"
											1269: return "\u{2190}"
											1270: return "\u{21e4}"
											_: return ""
							else:
								if index < 1280:
									if index < 1275:
										match index:
											1271: return "\u{291f}"
											1272: return "\u{291d}"
											1273: return "\u{21a9}"
											1274: return "\u{21ab}"
											_: return ""
									else:
										match index:
											1275: return "\u{2939}"
											1276: return "\u{2973}"
											1277: return "\u{21a2}"
											1278: return "\u{2aab}"
											1279: return "\u{2919}"
											_: return ""
								else:
									if index < 1284:
										match index:
											1280: return "\u{2aad}"
											1281: return "\u{2aad}\u{fe00}"
											1282: return "\u{290c}"
											1283: return "\u{2772}"
											_: return ""
									else:
										match index:
											1284: return "\u{7b}"
											1285: return "\u{5b}"
											1286: return "\u{298b}"
											1287: return "\u{298f}"
											1288: return "\u{298d}"
											_: return ""
						else:
							if index < 1306:
								if index < 1297:
									match index:
										1289: return "\u{13e}"
										1290: return "\u{13c}"
										1291: return "\u{2308}"
										1292: return "\u{7b}"
										1293: return "\u{43b}"
										1294: return "\u{2936}"
										1295: return "\u{201c}"
										1296: return "\u{201e}"
										_: return ""
								else:
									if index < 1301:
										match index:
											1297: return "\u{2967}"
											1298: return "\u{294b}"
											1299: return "\u{21b2}"
											1300: return "\u{2264}"
											_: return ""
									else:
										match index:
											1301: return "\u{2190}"
											1302: return "\u{21a2}"
											1303: return "\u{21bd}"
											1304: return "\u{21bc}"
											1305: return "\u{21c7}"
											_: return ""
							else:
								if index < 1315:
									if index < 1310:
										match index:
											1306: return "\u{2194}"
											1307: return "\u{21c6}"
											1308: return "\u{21cb}"
											1309: return "\u{21ad}"
											_: return ""
									else:
										match index:
											1310: return "\u{22cb}"
											1311: return "\u{22da}"
											1312: return "\u{2264}"
											1313: return "\u{2266}"
											1314: return "\u{2a7d}"
											_: return ""
								else:
									if index < 1319:
										match index:
											1315: return "\u{2a7d}"
											1316: return "\u{2aa8}"
											1317: return "\u{2a7f}"
											1318: return "\u{2a81}"
											_: return ""
									else:
										match index:
											1319: return "\u{2a83}"
											1320: return "\u{22da}\u{fe00}"
											1321: return "\u{2a93}"
											1322: return "\u{2a85}"
											1323: return "\u{22d6}"
											_: return ""
					else:
						if index < 1359:
							if index < 1341:
								if index < 1332:
									match index:
										1324: return "\u{22da}"
										1325: return "\u{2a8b}"
										1326: return "\u{2276}"
										1327: return "\u{2272}"
										1328: return "\u{297c}"
										1329: return "\u{230a}"
										1330: return "\u{1d529}"
										1331: return "\u{2276}"
										_: return ""
								else:
									if index < 1336:
										match index:
											1332: return "\u{2a91}"
											1333: return "\u{21bd}"
											1334: return "\u{21bc}"
											1335: return "\u{296a}"
											_: return ""
									else:
										match index:
											1336: return "\u{2584}"
											1337: return "\u{459}"
											1338: return "\u{226a}"
											1339: return "\u{21c7}"
											1340: return "\u{231e}"
											_: return ""
							else:
								if index < 1350:
									if index < 1345:
										match index:
											1341: return "\u{296b}"
											1342: return "\u{25fa}"
											1343: return "\u{140}"
											1344: return "\u{23b0}"
											_: return ""
									else:
										match index:
											1345: return "\u{23b0}"
											1346: return "\u{2268}"
											1347: return "\u{2a89}"
											1348: return "\u{2a89}"
											1349: return "\u{2a87}"
											_: return ""
								else:
									if index < 1354:
										match index:
											1350: return "\u{2a87}"
											1351: return "\u{2268}"
											1352: return "\u{22e6}"
											1353: return "\u{27ec}"
											_: return ""
									else:
										match index:
											1354: return "\u{21fd}"
											1355: return "\u{27e6}"
											1356: return "\u{27f5}"
											1357: return "\u{27f7}"
											1358: return "\u{27fc}"
											_: return ""
						else:
							if index < 1376:
								if index < 1367:
									match index:
										1359: return "\u{27f6}"
										1360: return "\u{21ab}"
										1361: return "\u{21ac}"
										1362: return "\u{2985}"
										1363: return "\u{1d55d}"
										1364: return "\u{2a2d}"
										1365: return "\u{2a34}"
										1366: return "\u{2217}"
										_: return ""
								else:
									if index < 1371:
										match index:
											1367: return "\u{5f}"
											1368: return "\u{25ca}"
											1369: return "\u{25ca}"
											1370: return "\u{29eb}"
											_: return ""
									else:
										match index:
											1371: return "\u{28}"
											1372: return "\u{2993}"
											1373: return "\u{21c6}"
											1374: return "\u{231f}"
											1375: return "\u{21cb}"
											_: return ""
							else:
								if index < 1385:
									if index < 1380:
										match index:
											1376: return "\u{296d}"
											1377: return "\u{200e}"
											1378: return "\u{22bf}"
											1379: return "\u{2039}"
											_: return ""
									else:
										match index:
											1380: return "\u{1d4c1}"
											1381: return "\u{21b0}"
											1382: return "\u{2272}"
											1383: return "\u{2a8d}"
											1384: return "\u{2a8f}"
											_: return ""
								else:
									if index < 1389:
										match index:
											1385: return "\u{5b}"
											1386: return "\u{2018}"
											1387: return "\u{201a}"
											1388: return "\u{142}"
											_: return ""
									else:
										match index:
											1389: return "\u{3c}"
											1390: return "\u{3c}"
											1391: return "\u{2aa6}"
											1392: return "\u{2a79}"
											1393: return "\u{22d6}"
											_: return ""
			else:
				if index < 1533:
					if index < 1463:
						if index < 1428:
							if index < 1411:
								if index < 1402:
									match index:
										1394: return "\u{22cb}"
										1395: return "\u{22c9}"
										1396: return "\u{2976}"
										1397: return "\u{2a7b}"
										1398: return "\u{2996}"
										1399: return "\u{25c3}"
										1400: return "\u{22b4}"
										1401: return "\u{25c2}"
										_: return ""
								else:
									if index < 1406:
										match index:
											1402: return "\u{294a}"
											1403: return "\u{2966}"
											1404: return "\u{2268}\u{fe00}"
											1405: return "\u{2268}\u{fe00}"
											_: return ""
									else:
										match index:
											1406: return "\u{223a}"
											1407: return "\u{af}"
											1408: return "\u{af}"
											1409: return "\u{2642}"
											1410: return "\u{2720}"
											_: return ""
							else:
								if index < 1419:
									match index:
										1411: return "\u{2720}"
										1412: return "\u{21a6}"
										1413: return "\u{21a6}"
										1414: return "\u{21a7}"
										1415: return "\u{21a4}"
										1416: return "\u{21a5}"
										1417: return "\u{25ae}"
										1418: return "\u{2a29}"
										_: return ""
								else:
									if index < 1423:
										match index:
											1419: return "\u{43c}"
											1420: return "\u{2014}"
											1421: return "\u{2221}"
											1422: return "\u{1d52a}"
											_: return ""
									else:
										match index:
											1423: return "\u{2127}"
											1424: return "\u{b5}"
											1425: return "\u{b5}"
											1426: return "\u{2223}"
											1427: return "\u{2a}"
											_: return ""
						else:
							if index < 1445:
								if index < 1436:
									match index:
										1428: return "\u{2af0}"
										1429: return "\u{b7}"
										1430: return "\u{b7}"
										1431: return "\u{2212}"
										1432: return "\u{229f}"
										1433: return "\u{2238}"
										1434: return "\u{2a2a}"
										1435: return "\u{2adb}"
										_: return ""
								else:
									if index < 1440:
										match index:
											1436: return "\u{2026}"
											1437: return "\u{2213}"
											1438: return "\u{22a7}"
											1439: return "\u{1d55e}"
											_: return ""
									else:
										match index:
											1440: return "\u{2213}"
											1441: return "\u{1d4c2}"
											1442: return "\u{223e}"
											1443: return "\u{3bc}"
											1444: return "\u{22b8}"
											_: return ""
							else:
								if index < 1454:
									if index < 1449:
										match index:
											1445: return "\u{22b8}"
											1446: return "\u{22d9}\u{338}"
											1447: return "\u{226b}\u{20d2}"
											1448: return "\u{226b}\u{338}"
											_: return ""
									else:
										match index:
											1449: return "\u{21cd}"
											1450: return "\u{21ce}"
											1451: return "\u{22d8}\u{338}"
											1452: return "\u{226a}\u{20d2}"
											1453: return "\u{226a}\u{338}"
											_: return ""
								else:
									if index < 1458:
										match index:
											1454: return "\u{21cf}"
											1455: return "\u{22af}"
											1456: return "\u{22ae}"
											1457: return "\u{2207}"
											_: return ""
									else:
										match index:
											1458: return "\u{144}"
											1459: return "\u{2220}\u{20d2}"
											1460: return "\u{2249}"
											1461: return "\u{2a70}\u{338}"
											1462: return "\u{224b}\u{338}"
											_: return ""
					else:
						if index < 1498:
							if index < 1480:
								if index < 1471:
									match index:
										1463: return "\u{149}"
										1464: return "\u{2249}"
										1465: return "\u{266e}"
										1466: return "\u{266e}"
										1467: return "\u{2115}"
										1468: return "\u{a0}"
										1469: return "\u{a0}"
										1470: return "\u{224e}\u{338}"
										_: return ""
								else:
									if index < 1475:
										match index:
											1471: return "\u{224f}\u{338}"
											1472: return "\u{2a43}"
											1473: return "\u{148}"
											1474: return "\u{146}"
											_: return ""
									else:
										match index:
											1475: return "\u{2247}"
											1476: return "\u{2a6d}\u{338}"
											1477: return "\u{2a42}"
											1478: return "\u{43d}"
											1479: return "\u{2013}"
											_: return ""
							else:
								if index < 1489:
									if index < 1484:
										match index:
											1480: return "\u{2260}"
											1481: return "\u{21d7}"
											1482: return "\u{2924}"
											1483: return "\u{2197}"
											_: return ""
									else:
										match index:
											1484: return "\u{2197}"
											1485: return "\u{2250}\u{338}"
											1486: return "\u{2262}"
											1487: return "\u{2928}"
											1488: return "\u{2242}\u{338}"
											_: return ""
								else:
									if index < 1493:
										match index:
											1489: return "\u{2204}"
											1490: return "\u{2204}"
											1491: return "\u{1d52b}"
											1492: return "\u{2267}\u{338}"
											_: return ""
									else:
										match index:
											1493: return "\u{2271}"
											1494: return "\u{2271}"
											1495: return "\u{2267}\u{338}"
											1496: return "\u{2a7e}\u{338}"
											1497: return "\u{2a7e}\u{338}"
											_: return ""
						else:
							if index < 1515:
								if index < 1506:
									match index:
										1498: return "\u{2275}"
										1499: return "\u{226f}"
										1500: return "\u{226f}"
										1501: return "\u{21ce}"
										1502: return "\u{21ae}"
										1503: return "\u{2af2}"
										1504: return "\u{220b}"
										1505: return "\u{22fc}"
										_: return ""
								else:
									if index < 1510:
										match index:
											1506: return "\u{22fa}"
											1507: return "\u{220b}"
											1508: return "\u{45a}"
											1509: return "\u{21cd}"
											_: return ""
									else:
										match index:
											1510: return "\u{2266}\u{338}"
											1511: return "\u{219a}"
											1512: return "\u{2025}"
											1513: return "\u{2270}"
											1514: return "\u{219a}"
											_: return ""
							else:
								if index < 1524:
									if index < 1519:
										match index:
											1515: return "\u{21ae}"
											1516: return "\u{2270}"
											1517: return "\u{2266}\u{338}"
											1518: return "\u{2a7d}\u{338}"
											_: return ""
									else:
										match index:
											1519: return "\u{2a7d}\u{338}"
											1520: return "\u{226e}"
											1521: return "\u{2274}"
											1522: return "\u{226e}"
											1523: return "\u{22ea}"
											_: return ""
								else:
									if index < 1528:
										match index:
											1524: return "\u{22ec}"
											1525: return "\u{2224}"
											1526: return "\u{1d55f}"
											1527: return "\u{ac}"
											_: return ""
									else:
										match index:
											1528: return "\u{ac}"
											1529: return "\u{2209}"
											1530: return "\u{22f9}\u{338}"
											1531: return "\u{22f5}\u{338}"
											1532: return "\u{2209}"
											_: return ""
				else:
					if index < 1603:
						if index < 1568:
							if index < 1550:
								if index < 1541:
									match index:
										1533: return "\u{22f7}"
										1534: return "\u{22f6}"
										1535: return "\u{220c}"
										1536: return "\u{220c}"
										1537: return "\u{22fe}"
										1538: return "\u{22fd}"
										1539: return "\u{2226}"
										1540: return "\u{2226}"
										_: return ""
								else:
									if index < 1545:
										match index:
											1541: return "\u{2afd}\u{20e5}"
											1542: return "\u{2202}\u{338}"
											1543: return "\u{2a14}"
											1544: return "\u{2280}"
											_: return ""
									else:
										match index:
											1545: return "\u{22e0}"
											1546: return "\u{2aaf}\u{338}"
											1547: return "\u{2280}"
											1548: return "\u{2aaf}\u{338}"
											1549: return "\u{21cf}"
											_: return ""
							else:
								if index < 1559:
									if index < 1554:
										match index:
											1550: return "\u{219b}"
											1551: return "\u{2933}\u{338}"
											1552: return "\u{219d}\u{338}"
											1553: return "\u{219b}"
											_: return ""
									else:
										match index:
											1554: return "\u{22eb}"
											1555: return "\u{22ed}"
											1556: return "\u{2281}"
											1557: return "\u{22e1}"
											1558: return "\u{2ab0}\u{338}"
											_: return ""
								else:
									if index < 1563:
										match index:
											1559: return "\u{1d4c3}"
											1560: return "\u{2224}"
											1561: return "\u{2226}"
											1562: return "\u{2241}"
											_: return ""
									else:
										match index:
											1563: return "\u{2244}"
											1564: return "\u{2244}"
											1565: return "\u{2224}"
											1566: return "\u{2226}"
											1567: return "\u{22e2}"
											_: return ""
						else:
							if index < 1585:
								if index < 1576:
									match index:
										1568: return "\u{22e3}"
										1569: return "\u{2284}"
										1570: return "\u{2ac5}\u{338}"
										1571: return "\u{2288}"
										1572: return "\u{2282}\u{20d2}"
										1573: return "\u{2288}"
										1574: return "\u{2ac5}\u{338}"
										1575: return "\u{2281}"
										_: return ""
								else:
									if index < 1580:
										match index:
											1576: return "\u{2ab0}\u{338}"
											1577: return "\u{2285}"
											1578: return "\u{2ac6}\u{338}"
											1579: return "\u{2289}"
											_: return ""
									else:
										match index:
											1580: return "\u{2283}\u{20d2}"
											1581: return "\u{2289}"
											1582: return "\u{2ac6}\u{338}"
											1583: return "\u{2279}"
											1584: return "\u{f1}"
											_: return ""
							else:
								if index < 1594:
									if index < 1589:
										match index:
											1585: return "\u{f1}"
											1586: return "\u{2278}"
											1587: return "\u{22ea}"
											1588: return "\u{22ec}"
											_: return ""
									else:
										match index:
											1589: return "\u{22eb}"
											1590: return "\u{22ed}"
											1591: return "\u{3bd}"
											1592: return "\u{23}"
											1593: return "\u{2116}"
											_: return ""
								else:
									if index < 1598:
										match index:
											1594: return "\u{2007}"
											1595: return "\u{22ad}"
											1596: return "\u{2904}"
											1597: return "\u{224d}\u{20d2}"
											_: return ""
									else:
										match index:
											1598: return "\u{22ac}"
											1599: return "\u{2265}\u{20d2}"
											1600: return "\u{3e}\u{20d2}"
											1601: return "\u{29de}"
											1602: return "\u{2902}"
											_: return ""
					else:
						if index < 1638:
							if index < 1620:
								if index < 1611:
									match index:
										1603: return "\u{2264}\u{20d2}"
										1604: return "\u{3c}\u{20d2}"
										1605: return "\u{22b4}\u{20d2}"
										1606: return "\u{2903}"
										1607: return "\u{22b5}\u{20d2}"
										1608: return "\u{223c}\u{20d2}"
										1609: return "\u{21d6}"
										1610: return "\u{2923}"
										_: return ""
								else:
									if index < 1615:
										match index:
											1611: return "\u{2196}"
											1612: return "\u{2196}"
											1613: return "\u{2927}"
											1614: return "\u{24c8}"
											_: return ""
									else:
										match index:
											1615: return "\u{f3}"
											1616: return "\u{f3}"
											1617: return "\u{229b}"
											1618: return "\u{229a}"
											1619: return "\u{f4}"
											_: return ""
							else:
								if index < 1629:
									if index < 1624:
										match index:
											1620: return "\u{f4}"
											1621: return "\u{43e}"
											1622: return "\u{229d}"
											1623: return "\u{151}"
											_: return ""
									else:
										match index:
											1624: return "\u{2a38}"
											1625: return "\u{2299}"
											1626: return "\u{29bc}"
											1627: return "\u{153}"
											1628: return "\u{29bf}"
											_: return ""
								else:
									if index < 1633:
										match index:
											1629: return "\u{1d52c}"
											1630: return "\u{2db}"
											1631: return "\u{f2}"
											1632: return "\u{f2}"
											_: return ""
									else:
										match index:
											1633: return "\u{29c1}"
											1634: return "\u{29b5}"
											1635: return "\u{3a9}"
											1636: return "\u{222e}"
											1637: return "\u{21ba}"
											_: return ""
						else:
							if index < 1655:
								if index < 1646:
									match index:
										1638: return "\u{29be}"
										1639: return "\u{29bb}"
										1640: return "\u{203e}"
										1641: return "\u{29c0}"
										1642: return "\u{14d}"
										1643: return "\u{3c9}"
										1644: return "\u{3bf}"
										1645: return "\u{29b6}"
										_: return ""
								else:
									if index < 1650:
										match index:
											1646: return "\u{2296}"
											1647: return "\u{1d560}"
											1648: return "\u{29b7}"
											1649: return "\u{29b9}"
											_: return ""
									else:
										match index:
											1650: return "\u{2295}"
											1651: return "\u{2228}"
											1652: return "\u{21bb}"
											1653: return "\u{2a5d}"
											1654: return "\u{2134}"
											_: return ""
							else:
								if index < 1664:
									if index < 1659:
										match index:
											1655: return "\u{2134}"
											1656: return "\u{aa}"
											1657: return "\u{aa}"
											1658: return "\u{ba}"
											_: return ""
									else:
										match index:
											1659: return "\u{ba}"
											1660: return "\u{22b6}"
											1661: return "\u{2a56}"
											1662: return "\u{2a57}"
											1663: return "\u{2a5b}"
											_: return ""
								else:
									if index < 1668:
										match index:
											1664: return "\u{2134}"
											1665: return "\u{f8}"
											1666: return "\u{f8}"
											1667: return "\u{2298}"
											_: return ""
									else:
										match index:
											1668: return "\u{f5}"
											1669: return "\u{f5}"
											1670: return "\u{2297}"
											1671: return "\u{2a36}"
											1672: return "\u{f6}"
											_: return ""
		else:
			if index < 1952:
				if index < 1812:
					if index < 1742:
						if index < 1707:
							if index < 1690:
								if index < 1681:
									match index:
										1673: return "\u{f6}"
										1674: return "\u{233d}"
										1675: return "\u{2225}"
										1676: return "\u{b6}"
										1677: return "\u{b6}"
										1678: return "\u{2225}"
										1679: return "\u{2af3}"
										1680: return "\u{2afd}"
										_: return ""
								else:
									if index < 1685:
										match index:
											1681: return "\u{2202}"
											1682: return "\u{43f}"
											1683: return "\u{25}"
											1684: return "\u{2e}"
											_: return ""
									else:
										match index:
											1685: return "\u{2030}"
											1686: return "\u{22a5}"
											1687: return "\u{2031}"
											1688: return "\u{1d52d}"
											1689: return "\u{3c6}"
											_: return ""
							else:
								if index < 1698:
									match index:
										1690: return "\u{3d5}"
										1691: return "\u{2133}"
										1692: return "\u{260e}"
										1693: return "\u{3c0}"
										1694: return "\u{22d4}"
										1695: return "\u{3d6}"
										1696: return "\u{210f}"
										1697: return "\u{210e}"
										_: return ""
								else:
									if index < 1702:
										match index:
											1698: return "\u{210f}"
											1699: return "\u{2b}"
											1700: return "\u{2a23}"
											1701: return "\u{229e}"
											_: return ""
									else:
										match index:
											1702: return "\u{2a22}"
											1703: return "\u{2214}"
											1704: return "\u{2a25}"
											1705: return "\u{2a72}"
											1706: return "\u{b1}"
											_: return ""
						else:
							if index < 1724:
								if index < 1715:
									match index:
										1707: return "\u{b1}"
										1708: return "\u{2a26}"
										1709: return "\u{2a27}"
										1710: return "\u{b1}"
										1711: return "\u{2a15}"
										1712: return "\u{1d561}"
										1713: return "\u{a3}"
										1714: return "\u{a3}"
										_: return ""
								else:
									if index < 1719:
										match index:
											1715: return "\u{227a}"
											1716: return "\u{2ab3}"
											1717: return "\u{2ab7}"
											1718: return "\u{227c}"
											_: return ""
									else:
										match index:
											1719: return "\u{2aaf}"
											1720: return "\u{227a}"
											1721: return "\u{2ab7}"
											1722: return "\u{227c}"
											1723: return "\u{2aaf}"
											_: return ""
							else:
								if index < 1733:
									if index < 1728:
										match index:
											1724: return "\u{2ab9}"
											1725: return "\u{2ab5}"
											1726: return "\u{22e8}"
											1727: return "\u{227e}"
											_: return ""
									else:
										match index:
											1728: return "\u{2032}"
											1729: return "\u{2119}"
											1730: return "\u{2ab5}"
											1731: return "\u{2ab9}"
											1732: return "\u{22e8}"
											_: return ""
								else:
									if index < 1737:
										match index:
											1733: return "\u{220f}"
											1734: return "\u{232e}"
											1735: return "\u{2312}"
											1736: return "\u{2313}"
											_: return ""
									else:
										match index:
											1737: return "\u{221d}"
											1738: return "\u{221d}"
											1739: return "\u{227e}"
											1740: return "\u{22b0}"
											1741: return "\u{1d4c5}"
											_: return ""
					else:
						if index < 1777:
							if index < 1759:
								if index < 1750:
									match index:
										1742: return "\u{3c8}"
										1743: return "\u{2008}"
										1744: return "\u{1d52e}"
										1745: return "\u{2a0c}"
										1746: return "\u{1d562}"
										1747: return "\u{2057}"
										1748: return "\u{1d4c6}"
										1749: return "\u{210d}"
										_: return ""
								else:
									if index < 1754:
										match index:
											1750: return "\u{2a16}"
											1751: return "\u{3f}"
											1752: return "\u{225f}"
											1753: return "\u{22}"
											_: return ""
									else:
										match index:
											1754: return "\u{22}"
											1755: return "\u{21db}"
											1756: return "\u{21d2}"
											1757: return "\u{291c}"
											1758: return "\u{290f}"
											_: return ""
							else:
								if index < 1768:
									if index < 1763:
										match index:
											1759: return "\u{2964}"
											1760: return "\u{223d}\u{331}"
											1761: return "\u{155}"
											1762: return "\u{221a}"
											_: return ""
									else:
										match index:
											1763: return "\u{29b3}"
											1764: return "\u{27e9}"
											1765: return "\u{2992}"
											1766: return "\u{29a5}"
											1767: return "\u{27e9}"
											_: return ""
								else:
									if index < 1772:
										match index:
											1768: return "\u{bb}"
											1769: return "\u{bb}"
											1770: return "\u{2192}"
											1771: return "\u{2975}"
											_: return ""
									else:
										match index:
											1772: return "\u{21e5}"
											1773: return "\u{2920}"
											1774: return "\u{2933}"
											1775: return "\u{291e}"
											1776: return "\u{21aa}"
											_: return ""
						else:
							if index < 1794:
								if index < 1785:
									match index:
										1777: return "\u{21ac}"
										1778: return "\u{2945}"
										1779: return "\u{2974}"
										1780: return "\u{21a3}"
										1781: return "\u{219d}"
										1782: return "\u{291a}"
										1783: return "\u{2236}"
										1784: return "\u{211a}"
										_: return ""
								else:
									if index < 1789:
										match index:
											1785: return "\u{290d}"
											1786: return "\u{2773}"
											1787: return "\u{7d}"
											1788: return "\u{5d}"
											_: return ""
									else:
										match index:
											1789: return "\u{298c}"
											1790: return "\u{298e}"
											1791: return "\u{2990}"
											1792: return "\u{159}"
											1793: return "\u{157}"
											_: return ""
							else:
								if index < 1803:
									if index < 1798:
										match index:
											1794: return "\u{2309}"
											1795: return "\u{7d}"
											1796: return "\u{440}"
											1797: return "\u{2937}"
											_: return ""
									else:
										match index:
											1798: return "\u{2969}"
											1799: return "\u{201d}"
											1800: return "\u{201d}"
											1801: return "\u{21b3}"
											1802: return "\u{211c}"
											_: return ""
								else:
									if index < 1807:
										match index:
											1803: return "\u{211b}"
											1804: return "\u{211c}"
											1805: return "\u{211d}"
											1806: return "\u{25ad}"
											_: return ""
									else:
										match index:
											1807: return "\u{ae}"
											1808: return "\u{ae}"
											1809: return "\u{297d}"
											1810: return "\u{230b}"
											1811: return "\u{1d52f}"
											_: return ""
				else:
					if index < 1882:
						if index < 1847:
							if index < 1829:
								if index < 1820:
									match index:
										1812: return "\u{21c1}"
										1813: return "\u{21c0}"
										1814: return "\u{296c}"
										1815: return "\u{3c1}"
										1816: return "\u{3f1}"
										1817: return "\u{2192}"
										1818: return "\u{21a3}"
										1819: return "\u{21c1}"
										_: return ""
								else:
									if index < 1824:
										match index:
											1820: return "\u{21c0}"
											1821: return "\u{21c4}"
											1822: return "\u{21cc}"
											1823: return "\u{21c9}"
											_: return ""
									else:
										match index:
											1824: return "\u{219d}"
											1825: return "\u{22cc}"
											1826: return "\u{2da}"
											1827: return "\u{2253}"
											1828: return "\u{21c4}"
											_: return ""
							else:
								if index < 1838:
									if index < 1833:
										match index:
											1829: return "\u{21cc}"
											1830: return "\u{200f}"
											1831: return "\u{23b1}"
											1832: return "\u{23b1}"
											_: return ""
									else:
										match index:
											1833: return "\u{2aee}"
											1834: return "\u{27ed}"
											1835: return "\u{21fe}"
											1836: return "\u{27e7}"
											1837: return "\u{2986}"
											_: return ""
								else:
									if index < 1842:
										match index:
											1838: return "\u{1d563}"
											1839: return "\u{2a2e}"
											1840: return "\u{2a35}"
											1841: return "\u{29}"
											_: return ""
									else:
										match index:
											1842: return "\u{2994}"
											1843: return "\u{2a12}"
											1844: return "\u{21c9}"
											1845: return "\u{203a}"
											1846: return "\u{1d4c7}"
											_: return ""
						else:
							if index < 1864:
								if index < 1855:
									match index:
										1847: return "\u{21b1}"
										1848: return "\u{5d}"
										1849: return "\u{2019}"
										1850: return "\u{2019}"
										1851: return "\u{22cc}"
										1852: return "\u{22ca}"
										1853: return "\u{25b9}"
										1854: return "\u{22b5}"
										_: return ""
								else:
									if index < 1859:
										match index:
											1855: return "\u{25b8}"
											1856: return "\u{29ce}"
											1857: return "\u{2968}"
											1858: return "\u{211e}"
											_: return ""
									else:
										match index:
											1859: return "\u{15b}"
											1860: return "\u{201a}"
											1861: return "\u{227b}"
											1862: return "\u{2ab4}"
											1863: return "\u{2ab8}"
											_: return ""
							else:
								if index < 1873:
									if index < 1868:
										match index:
											1864: return "\u{161}"
											1865: return "\u{227d}"
											1866: return "\u{2ab0}"
											1867: return "\u{15f}"
											_: return ""
									else:
										match index:
											1868: return "\u{15d}"
											1869: return "\u{2ab6}"
											1870: return "\u{2aba}"
											1871: return "\u{22e9}"
											1872: return "\u{2a13}"
											_: return ""
								else:
									if index < 1877:
										match index:
											1873: return "\u{227f}"
											1874: return "\u{441}"
											1875: return "\u{22c5}"
											1876: return "\u{22a1}"
											_: return ""
									else:
										match index:
											1877: return "\u{2a66}"
											1878: return "\u{21d8}"
											1879: return "\u{2925}"
											1880: return "\u{2198}"
											1881: return "\u{2198}"
											_: return ""
					else:
						if index < 1917:
							if index < 1899:
								if index < 1890:
									match index:
										1882: return "\u{a7}"
										1883: return "\u{a7}"
										1884: return "\u{3b}"
										1885: return "\u{2929}"
										1886: return "\u{2216}"
										1887: return "\u{2216}"
										1888: return "\u{2736}"
										1889: return "\u{1d530}"
										_: return ""
								else:
									if index < 1894:
										match index:
											1890: return "\u{2322}"
											1891: return "\u{266f}"
											1892: return "\u{449}"
											1893: return "\u{448}"
											_: return ""
									else:
										match index:
											1894: return "\u{2223}"
											1895: return "\u{2225}"
											1896: return "\u{ad}"
											1897: return "\u{ad}"
											1898: return "\u{3c3}"
											_: return ""
							else:
								if index < 1908:
									if index < 1903:
										match index:
											1899: return "\u{3c2}"
											1900: return "\u{3c2}"
											1901: return "\u{223c}"
											1902: return "\u{2a6a}"
											_: return ""
									else:
										match index:
											1903: return "\u{2243}"
											1904: return "\u{2243}"
											1905: return "\u{2a9e}"
											1906: return "\u{2aa0}"
											1907: return "\u{2a9d}"
											_: return ""
								else:
									if index < 1912:
										match index:
											1908: return "\u{2a9f}"
											1909: return "\u{2246}"
											1910: return "\u{2a24}"
											1911: return "\u{2972}"
											_: return ""
									else:
										match index:
											1912: return "\u{2190}"
											1913: return "\u{2216}"
											1914: return "\u{2a33}"
											1915: return "\u{29e4}"
											1916: return "\u{2223}"
											_: return ""
						else:
							if index < 1934:
								if index < 1925:
									match index:
										1917: return "\u{2323}"
										1918: return "\u{2aaa}"
										1919: return "\u{2aac}"
										1920: return "\u{2aac}\u{fe00}"
										1921: return "\u{44c}"
										1922: return "\u{2f}"
										1923: return "\u{29c4}"
										1924: return "\u{233f}"
										_: return ""
								else:
									if index < 1929:
										match index:
											1925: return "\u{1d564}"
											1926: return "\u{2660}"
											1927: return "\u{2660}"
											1928: return "\u{2225}"
											_: return ""
									else:
										match index:
											1929: return "\u{2293}"
											1930: return "\u{2293}\u{fe00}"
											1931: return "\u{2294}"
											1932: return "\u{2294}\u{fe00}"
											1933: return "\u{228f}"
											_: return ""
							else:
								if index < 1943:
									if index < 1938:
										match index:
											1934: return "\u{2291}"
											1935: return "\u{228f}"
											1936: return "\u{2291}"
											1937: return "\u{2290}"
											_: return ""
									else:
										match index:
											1938: return "\u{2292}"
											1939: return "\u{2290}"
											1940: return "\u{2292}"
											1941: return "\u{25a1}"
											1942: return "\u{25a1}"
											_: return ""
								else:
									if index < 1947:
										match index:
											1943: return "\u{25aa}"
											1944: return "\u{25aa}"
											1945: return "\u{2192}"
											1946: return "\u{1d4c8}"
											_: return ""
									else:
										match index:
											1947: return "\u{2216}"
											1948: return "\u{2323}"
											1949: return "\u{22c6}"
											1950: return "\u{2606}"
											1951: return "\u{2605}"
											_: return ""
			else:
				if index < 2091:
					if index < 2021:
						if index < 1986:
							if index < 1969:
								if index < 1960:
									match index:
										1952: return "\u{3f5}"
										1953: return "\u{3d5}"
										1954: return "\u{af}"
										1955: return "\u{2282}"
										1956: return "\u{2ac5}"
										1957: return "\u{2abd}"
										1958: return "\u{2286}"
										1959: return "\u{2ac3}"
										_: return ""
								else:
									if index < 1964:
										match index:
											1960: return "\u{2ac1}"
											1961: return "\u{2acb}"
											1962: return "\u{228a}"
											1963: return "\u{2abf}"
											_: return ""
									else:
										match index:
											1964: return "\u{2979}"
											1965: return "\u{2282}"
											1966: return "\u{2286}"
											1967: return "\u{2ac5}"
											1968: return "\u{228a}"
											_: return ""
							else:
								if index < 1977:
									match index:
										1969: return "\u{2acb}"
										1970: return "\u{2ac7}"
										1971: return "\u{2ad5}"
										1972: return "\u{2ad3}"
										1973: return "\u{227b}"
										1974: return "\u{2ab8}"
										1975: return "\u{227d}"
										1976: return "\u{2ab0}"
										_: return ""
								else:
									if index < 1981:
										match index:
											1977: return "\u{2aba}"
											1978: return "\u{2ab6}"
											1979: return "\u{22e9}"
											1980: return "\u{227f}"
											_: return ""
									else:
										match index:
											1981: return "\u{2211}"
											1982: return "\u{266a}"
											1983: return "\u{b9}"
											1984: return "\u{b9}"
											1985: return "\u{b2}"
											_: return ""
						else:
							if index < 2003:
								if index < 1994:
									match index:
										1986: return "\u{b2}"
										1987: return "\u{b3}"
										1988: return "\u{b3}"
										1989: return "\u{2283}"
										1990: return "\u{2ac6}"
										1991: return "\u{2abe}"
										1992: return "\u{2ad8}"
										1993: return "\u{2287}"
										_: return ""
								else:
									if index < 1998:
										match index:
											1994: return "\u{2ac4}"
											1995: return "\u{27c9}"
											1996: return "\u{2ad7}"
											1997: return "\u{297b}"
											_: return ""
									else:
										match index:
											1998: return "\u{2ac2}"
											1999: return "\u{2acc}"
											2000: return "\u{228b}"
											2001: return "\u{2ac0}"
											2002: return "\u{2283}"
											_: return ""
							else:
								if index < 2012:
									if index < 2007:
										match index:
											2003: return "\u{2287}"
											2004: return "\u{2ac6}"
											2005: return "\u{228b}"
											2006: return "\u{2acc}"
											_: return ""
									else:
										match index:
											2007: return "\u{2ac8}"
											2008: return "\u{2ad4}"
											2009: return "\u{2ad6}"
											2010: return "\u{21d9}"
											2011: return "\u{2926}"
											_: return ""
								else:
									if index < 2016:
										match index:
											2012: return "\u{2199}"
											2013: return "\u{2199}"
											2014: return "\u{292a}"
											2015: return "\u{df}"
											_: return ""
									else:
										match index:
											2016: return "\u{df}"
											2017: return "\u{2316}"
											2018: return "\u{3c4}"
											2019: return "\u{23b4}"
											2020: return "\u{165}"
											_: return ""
					else:
						if index < 2056:
							if index < 2038:
								if index < 2029:
									match index:
										2021: return "\u{163}"
										2022: return "\u{442}"
										2023: return "\u{20db}"
										2024: return "\u{2315}"
										2025: return "\u{1d531}"
										2026: return "\u{2234}"
										2027: return "\u{2234}"
										2028: return "\u{3b8}"
										_: return ""
								else:
									if index < 2033:
										match index:
											2029: return "\u{3d1}"
											2030: return "\u{3d1}"
											2031: return "\u{2248}"
											2032: return "\u{223c}"
											_: return ""
									else:
										match index:
											2033: return "\u{2009}"
											2034: return "\u{2248}"
											2035: return "\u{223c}"
											2036: return "\u{fe}"
											2037: return "\u{fe}"
											_: return ""
							else:
								if index < 2047:
									if index < 2042:
										match index:
											2038: return "\u{2dc}"
											2039: return "\u{d7}"
											2040: return "\u{d7}"
											2041: return "\u{22a0}"
											_: return ""
									else:
										match index:
											2042: return "\u{2a31}"
											2043: return "\u{2a30}"
											2044: return "\u{222d}"
											2045: return "\u{2928}"
											2046: return "\u{22a4}"
											_: return ""
								else:
									if index < 2051:
										match index:
											2047: return "\u{2336}"
											2048: return "\u{2af1}"
											2049: return "\u{1d565}"
											2050: return "\u{2ada}"
											_: return ""
									else:
										match index:
											2051: return "\u{2929}"
											2052: return "\u{2034}"
											2053: return "\u{2122}"
											2054: return "\u{25b5}"
											2055: return "\u{25bf}"
											_: return ""
						else:
							if index < 2073:
								if index < 2064:
									match index:
										2056: return "\u{25c3}"
										2057: return "\u{22b4}"
										2058: return "\u{225c}"
										2059: return "\u{25b9}"
										2060: return "\u{22b5}"
										2061: return "\u{25ec}"
										2062: return "\u{225c}"
										2063: return "\u{2a3a}"
										_: return ""
								else:
									if index < 2068:
										match index:
											2064: return "\u{2a39}"
											2065: return "\u{29cd}"
											2066: return "\u{2a3b}"
											2067: return "\u{23e2}"
											_: return ""
									else:
										match index:
											2068: return "\u{1d4c9}"
											2069: return "\u{446}"
											2070: return "\u{45b}"
											2071: return "\u{167}"
											2072: return "\u{226c}"
											_: return ""
							else:
								if index < 2082:
									if index < 2077:
										match index:
											2073: return "\u{219e}"
											2074: return "\u{21a0}"
											2075: return "\u{21d1}"
											2076: return "\u{2963}"
											_: return ""
									else:
										match index:
											2077: return "\u{fa}"
											2078: return "\u{fa}"
											2079: return "\u{2191}"
											2080: return "\u{45e}"
											2081: return "\u{16d}"
											_: return ""
								else:
									if index < 2086:
										match index:
											2082: return "\u{fb}"
											2083: return "\u{fb}"
											2084: return "\u{443}"
											2085: return "\u{21c5}"
											_: return ""
									else:
										match index:
											2086: return "\u{171}"
											2087: return "\u{296e}"
											2088: return "\u{297e}"
											2089: return "\u{1d532}"
											2090: return "\u{f9}"
											_: return ""
				else:
					if index < 2161:
						if index < 2126:
							if index < 2108:
								if index < 2099:
									match index:
										2091: return "\u{f9}"
										2092: return "\u{21bf}"
										2093: return "\u{21be}"
										2094: return "\u{2580}"
										2095: return "\u{231c}"
										2096: return "\u{231c}"
										2097: return "\u{230f}"
										2098: return "\u{25f8}"
										_: return ""
								else:
									if index < 2103:
										match index:
											2099: return "\u{16b}"
											2100: return "\u{a8}"
											2101: return "\u{a8}"
											2102: return "\u{173}"
											_: return ""
									else:
										match index:
											2103: return "\u{1d566}"
											2104: return "\u{2191}"
											2105: return "\u{2195}"
											2106: return "\u{21bf}"
											2107: return "\u{21be}"
											_: return ""
							else:
								if index < 2117:
									if index < 2112:
										match index:
											2108: return "\u{228e}"
											2109: return "\u{3c5}"
											2110: return "\u{3d2}"
											2111: return "\u{3c5}"
											_: return ""
									else:
										match index:
											2112: return "\u{21c8}"
											2113: return "\u{231d}"
											2114: return "\u{231d}"
											2115: return "\u{230e}"
											2116: return "\u{16f}"
											_: return ""
								else:
									if index < 2121:
										match index:
											2117: return "\u{25f9}"
											2118: return "\u{1d4ca}"
											2119: return "\u{22f0}"
											2120: return "\u{169}"
											_: return ""
									else:
										match index:
											2121: return "\u{25b5}"
											2122: return "\u{25b4}"
											2123: return "\u{21c8}"
											2124: return "\u{fc}"
											2125: return "\u{fc}"
											_: return ""
						else:
							if index < 2143:
								if index < 2134:
									match index:
										2126: return "\u{29a7}"
										2127: return "\u{21d5}"
										2128: return "\u{2ae8}"
										2129: return "\u{2ae9}"
										2130: return "\u{22a8}"
										2131: return "\u{299c}"
										2132: return "\u{3f5}"
										2133: return "\u{3f0}"
										_: return ""
								else:
									if index < 2138:
										match index:
											2134: return "\u{2205}"
											2135: return "\u{3d5}"
											2136: return "\u{3d6}"
											2137: return "\u{221d}"
											_: return ""
									else:
										match index:
											2138: return "\u{2195}"
											2139: return "\u{3f1}"
											2140: return "\u{3c2}"
											2141: return "\u{228a}\u{fe00}"
											2142: return "\u{2acb}\u{fe00}"
											_: return ""
							else:
								if index < 2152:
									if index < 2147:
										match index:
											2143: return "\u{228b}\u{fe00}"
											2144: return "\u{2acc}\u{fe00}"
											2145: return "\u{3d1}"
											2146: return "\u{22b2}"
											_: return ""
									else:
										match index:
											2147: return "\u{22b3}"
											2148: return "\u{432}"
											2149: return "\u{22a2}"
											2150: return "\u{2228}"
											2151: return "\u{22bb}"
											_: return ""
								else:
									if index < 2156:
										match index:
											2152: return "\u{225a}"
											2153: return "\u{22ee}"
											2154: return "\u{7c}"
											2155: return "\u{7c}"
											_: return ""
									else:
										match index:
											2156: return "\u{1d533}"
											2157: return "\u{22b2}"
											2158: return "\u{2282}\u{20d2}"
											2159: return "\u{2283}\u{20d2}"
											2160: return "\u{1d567}"
											_: return ""
					else:
						if index < 2196:
							if index < 2178:
								if index < 2169:
									match index:
										2161: return "\u{221d}"
										2162: return "\u{22b3}"
										2163: return "\u{1d4cb}"
										2164: return "\u{2acb}\u{fe00}"
										2165: return "\u{228a}\u{fe00}"
										2166: return "\u{2acc}\u{fe00}"
										2167: return "\u{228b}\u{fe00}"
										2168: return "\u{299a}"
										_: return ""
								else:
									if index < 2173:
										match index:
											2169: return "\u{175}"
											2170: return "\u{2a5f}"
											2171: return "\u{2227}"
											2172: return "\u{2259}"
											_: return ""
									else:
										match index:
											2173: return "\u{2118}"
											2174: return "\u{1d534}"
											2175: return "\u{1d568}"
											2176: return "\u{2118}"
											2177: return "\u{2240}"
											_: return ""
							else:
								if index < 2187:
									if index < 2182:
										match index:
											2178: return "\u{2240}"
											2179: return "\u{1d4cc}"
											2180: return "\u{22c2}"
											2181: return "\u{25ef}"
											_: return ""
									else:
										match index:
											2182: return "\u{22c3}"
											2183: return "\u{25bd}"
											2184: return "\u{1d535}"
											2185: return "\u{27fa}"
											2186: return "\u{27f7}"
											_: return ""
								else:
									if index < 2191:
										match index:
											2187: return "\u{3be}"
											2188: return "\u{27f8}"
											2189: return "\u{27f5}"
											2190: return "\u{27fc}"
											_: return ""
									else:
										match index:
											2191: return "\u{22fb}"
											2192: return "\u{2a00}"
											2193: return "\u{1d569}"
											2194: return "\u{2a01}"
											2195: return "\u{2a02}"
											_: return ""
						else:
							if index < 2213:
								if index < 2204:
									match index:
										2196: return "\u{27f9}"
										2197: return "\u{27f6}"
										2198: return "\u{1d4cd}"
										2199: return "\u{2a06}"
										2200: return "\u{2a04}"
										2201: return "\u{25b3}"
										2202: return "\u{22c1}"
										2203: return "\u{22c0}"
										_: return ""
								else:
									if index < 2208:
										match index:
											2204: return "\u{fd}"
											2205: return "\u{fd}"
											2206: return "\u{44f}"
											2207: return "\u{177}"
											_: return ""
									else:
										match index:
											2208: return "\u{44b}"
											2209: return "\u{a5}"
											2210: return "\u{a5}"
											2211: return "\u{1d536}"
											2212: return "\u{457}"
											_: return ""
							else:
								if index < 2222:
									if index < 2217:
										match index:
											2213: return "\u{1d56a}"
											2214: return "\u{1d4ce}"
											2215: return "\u{44e}"
											2216: return "\u{ff}"
											_: return ""
									else:
										match index:
											2217: return "\u{ff}"
											2218: return "\u{17a}"
											2219: return "\u{17e}"
											2220: return "\u{437}"
											2221: return "\u{17c}"
											_: return ""
								else:
									if index < 2226:
										match index:
											2222: return "\u{2128}"
											2223: return "\u{3b6}"
											2224: return "\u{1d537}"
											2225: return "\u{436}"
											_: return ""
									else:
										match index:
											2226: return "\u{21dd}"
											2227: return "\u{1d56b}"
											2228: return "\u{1d4cf}"
											2229: return "\u{200d}"
											2230: return "\u{200c}"
											_: return ""

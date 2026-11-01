import expect_contains, expect_fault from "@std/test/test.ms"

# Every call keeps 1500 locals live across the recursive call, so the frame is large enough
# that the 1 GiB main stack runs out after only a few hundred thousand calls.
fn fat(n: Int) Int:
    let a0 = n + 0
    let a1 = n + 1
    let a2 = n + 2
    let a3 = n + 3
    let a4 = n + 4
    let a5 = n + 5
    let a6 = n + 6
    let a7 = n + 7
    let a8 = n + 8
    let a9 = n + 9
    let a10 = n + 10
    let a11 = n + 11
    let a12 = n + 12
    let a13 = n + 13
    let a14 = n + 14
    let a15 = n + 15
    let a16 = n + 16
    let a17 = n + 17
    let a18 = n + 18
    let a19 = n + 19
    let a20 = n + 20
    let a21 = n + 21
    let a22 = n + 22
    let a23 = n + 23
    let a24 = n + 24
    let a25 = n + 25
    let a26 = n + 26
    let a27 = n + 27
    let a28 = n + 28
    let a29 = n + 29
    let a30 = n + 30
    let a31 = n + 31
    let a32 = n + 32
    let a33 = n + 33
    let a34 = n + 34
    let a35 = n + 35
    let a36 = n + 36
    let a37 = n + 37
    let a38 = n + 38
    let a39 = n + 39
    let a40 = n + 40
    let a41 = n + 41
    let a42 = n + 42
    let a43 = n + 43
    let a44 = n + 44
    let a45 = n + 45
    let a46 = n + 46
    let a47 = n + 47
    let a48 = n + 48
    let a49 = n + 49
    let a50 = n + 50
    let a51 = n + 51
    let a52 = n + 52
    let a53 = n + 53
    let a54 = n + 54
    let a55 = n + 55
    let a56 = n + 56
    let a57 = n + 57
    let a58 = n + 58
    let a59 = n + 59
    let a60 = n + 60
    let a61 = n + 61
    let a62 = n + 62
    let a63 = n + 63
    let a64 = n + 64
    let a65 = n + 65
    let a66 = n + 66
    let a67 = n + 67
    let a68 = n + 68
    let a69 = n + 69
    let a70 = n + 70
    let a71 = n + 71
    let a72 = n + 72
    let a73 = n + 73
    let a74 = n + 74
    let a75 = n + 75
    let a76 = n + 76
    let a77 = n + 77
    let a78 = n + 78
    let a79 = n + 79
    let a80 = n + 80
    let a81 = n + 81
    let a82 = n + 82
    let a83 = n + 83
    let a84 = n + 84
    let a85 = n + 85
    let a86 = n + 86
    let a87 = n + 87
    let a88 = n + 88
    let a89 = n + 89
    let a90 = n + 90
    let a91 = n + 91
    let a92 = n + 92
    let a93 = n + 93
    let a94 = n + 94
    let a95 = n + 95
    let a96 = n + 96
    let a97 = n + 97
    let a98 = n + 98
    let a99 = n + 99
    let a100 = n + 100
    let a101 = n + 101
    let a102 = n + 102
    let a103 = n + 103
    let a104 = n + 104
    let a105 = n + 105
    let a106 = n + 106
    let a107 = n + 107
    let a108 = n + 108
    let a109 = n + 109
    let a110 = n + 110
    let a111 = n + 111
    let a112 = n + 112
    let a113 = n + 113
    let a114 = n + 114
    let a115 = n + 115
    let a116 = n + 116
    let a117 = n + 117
    let a118 = n + 118
    let a119 = n + 119
    let a120 = n + 120
    let a121 = n + 121
    let a122 = n + 122
    let a123 = n + 123
    let a124 = n + 124
    let a125 = n + 125
    let a126 = n + 126
    let a127 = n + 127
    let a128 = n + 128
    let a129 = n + 129
    let a130 = n + 130
    let a131 = n + 131
    let a132 = n + 132
    let a133 = n + 133
    let a134 = n + 134
    let a135 = n + 135
    let a136 = n + 136
    let a137 = n + 137
    let a138 = n + 138
    let a139 = n + 139
    let a140 = n + 140
    let a141 = n + 141
    let a142 = n + 142
    let a143 = n + 143
    let a144 = n + 144
    let a145 = n + 145
    let a146 = n + 146
    let a147 = n + 147
    let a148 = n + 148
    let a149 = n + 149
    let a150 = n + 150
    let a151 = n + 151
    let a152 = n + 152
    let a153 = n + 153
    let a154 = n + 154
    let a155 = n + 155
    let a156 = n + 156
    let a157 = n + 157
    let a158 = n + 158
    let a159 = n + 159
    let a160 = n + 160
    let a161 = n + 161
    let a162 = n + 162
    let a163 = n + 163
    let a164 = n + 164
    let a165 = n + 165
    let a166 = n + 166
    let a167 = n + 167
    let a168 = n + 168
    let a169 = n + 169
    let a170 = n + 170
    let a171 = n + 171
    let a172 = n + 172
    let a173 = n + 173
    let a174 = n + 174
    let a175 = n + 175
    let a176 = n + 176
    let a177 = n + 177
    let a178 = n + 178
    let a179 = n + 179
    let a180 = n + 180
    let a181 = n + 181
    let a182 = n + 182
    let a183 = n + 183
    let a184 = n + 184
    let a185 = n + 185
    let a186 = n + 186
    let a187 = n + 187
    let a188 = n + 188
    let a189 = n + 189
    let a190 = n + 190
    let a191 = n + 191
    let a192 = n + 192
    let a193 = n + 193
    let a194 = n + 194
    let a195 = n + 195
    let a196 = n + 196
    let a197 = n + 197
    let a198 = n + 198
    let a199 = n + 199
    let a200 = n + 200
    let a201 = n + 201
    let a202 = n + 202
    let a203 = n + 203
    let a204 = n + 204
    let a205 = n + 205
    let a206 = n + 206
    let a207 = n + 207
    let a208 = n + 208
    let a209 = n + 209
    let a210 = n + 210
    let a211 = n + 211
    let a212 = n + 212
    let a213 = n + 213
    let a214 = n + 214
    let a215 = n + 215
    let a216 = n + 216
    let a217 = n + 217
    let a218 = n + 218
    let a219 = n + 219
    let a220 = n + 220
    let a221 = n + 221
    let a222 = n + 222
    let a223 = n + 223
    let a224 = n + 224
    let a225 = n + 225
    let a226 = n + 226
    let a227 = n + 227
    let a228 = n + 228
    let a229 = n + 229
    let a230 = n + 230
    let a231 = n + 231
    let a232 = n + 232
    let a233 = n + 233
    let a234 = n + 234
    let a235 = n + 235
    let a236 = n + 236
    let a237 = n + 237
    let a238 = n + 238
    let a239 = n + 239
    let a240 = n + 240
    let a241 = n + 241
    let a242 = n + 242
    let a243 = n + 243
    let a244 = n + 244
    let a245 = n + 245
    let a246 = n + 246
    let a247 = n + 247
    let a248 = n + 248
    let a249 = n + 249
    let a250 = n + 250
    let a251 = n + 251
    let a252 = n + 252
    let a253 = n + 253
    let a254 = n + 254
    let a255 = n + 255
    let a256 = n + 256
    let a257 = n + 257
    let a258 = n + 258
    let a259 = n + 259
    let a260 = n + 260
    let a261 = n + 261
    let a262 = n + 262
    let a263 = n + 263
    let a264 = n + 264
    let a265 = n + 265
    let a266 = n + 266
    let a267 = n + 267
    let a268 = n + 268
    let a269 = n + 269
    let a270 = n + 270
    let a271 = n + 271
    let a272 = n + 272
    let a273 = n + 273
    let a274 = n + 274
    let a275 = n + 275
    let a276 = n + 276
    let a277 = n + 277
    let a278 = n + 278
    let a279 = n + 279
    let a280 = n + 280
    let a281 = n + 281
    let a282 = n + 282
    let a283 = n + 283
    let a284 = n + 284
    let a285 = n + 285
    let a286 = n + 286
    let a287 = n + 287
    let a288 = n + 288
    let a289 = n + 289
    let a290 = n + 290
    let a291 = n + 291
    let a292 = n + 292
    let a293 = n + 293
    let a294 = n + 294
    let a295 = n + 295
    let a296 = n + 296
    let a297 = n + 297
    let a298 = n + 298
    let a299 = n + 299
    let a300 = n + 300
    let a301 = n + 301
    let a302 = n + 302
    let a303 = n + 303
    let a304 = n + 304
    let a305 = n + 305
    let a306 = n + 306
    let a307 = n + 307
    let a308 = n + 308
    let a309 = n + 309
    let a310 = n + 310
    let a311 = n + 311
    let a312 = n + 312
    let a313 = n + 313
    let a314 = n + 314
    let a315 = n + 315
    let a316 = n + 316
    let a317 = n + 317
    let a318 = n + 318
    let a319 = n + 319
    let a320 = n + 320
    let a321 = n + 321
    let a322 = n + 322
    let a323 = n + 323
    let a324 = n + 324
    let a325 = n + 325
    let a326 = n + 326
    let a327 = n + 327
    let a328 = n + 328
    let a329 = n + 329
    let a330 = n + 330
    let a331 = n + 331
    let a332 = n + 332
    let a333 = n + 333
    let a334 = n + 334
    let a335 = n + 335
    let a336 = n + 336
    let a337 = n + 337
    let a338 = n + 338
    let a339 = n + 339
    let a340 = n + 340
    let a341 = n + 341
    let a342 = n + 342
    let a343 = n + 343
    let a344 = n + 344
    let a345 = n + 345
    let a346 = n + 346
    let a347 = n + 347
    let a348 = n + 348
    let a349 = n + 349
    let a350 = n + 350
    let a351 = n + 351
    let a352 = n + 352
    let a353 = n + 353
    let a354 = n + 354
    let a355 = n + 355
    let a356 = n + 356
    let a357 = n + 357
    let a358 = n + 358
    let a359 = n + 359
    let a360 = n + 360
    let a361 = n + 361
    let a362 = n + 362
    let a363 = n + 363
    let a364 = n + 364
    let a365 = n + 365
    let a366 = n + 366
    let a367 = n + 367
    let a368 = n + 368
    let a369 = n + 369
    let a370 = n + 370
    let a371 = n + 371
    let a372 = n + 372
    let a373 = n + 373
    let a374 = n + 374
    let a375 = n + 375
    let a376 = n + 376
    let a377 = n + 377
    let a378 = n + 378
    let a379 = n + 379
    let a380 = n + 380
    let a381 = n + 381
    let a382 = n + 382
    let a383 = n + 383
    let a384 = n + 384
    let a385 = n + 385
    let a386 = n + 386
    let a387 = n + 387
    let a388 = n + 388
    let a389 = n + 389
    let a390 = n + 390
    let a391 = n + 391
    let a392 = n + 392
    let a393 = n + 393
    let a394 = n + 394
    let a395 = n + 395
    let a396 = n + 396
    let a397 = n + 397
    let a398 = n + 398
    let a399 = n + 399
    let a400 = n + 400
    let a401 = n + 401
    let a402 = n + 402
    let a403 = n + 403
    let a404 = n + 404
    let a405 = n + 405
    let a406 = n + 406
    let a407 = n + 407
    let a408 = n + 408
    let a409 = n + 409
    let a410 = n + 410
    let a411 = n + 411
    let a412 = n + 412
    let a413 = n + 413
    let a414 = n + 414
    let a415 = n + 415
    let a416 = n + 416
    let a417 = n + 417
    let a418 = n + 418
    let a419 = n + 419
    let a420 = n + 420
    let a421 = n + 421
    let a422 = n + 422
    let a423 = n + 423
    let a424 = n + 424
    let a425 = n + 425
    let a426 = n + 426
    let a427 = n + 427
    let a428 = n + 428
    let a429 = n + 429
    let a430 = n + 430
    let a431 = n + 431
    let a432 = n + 432
    let a433 = n + 433
    let a434 = n + 434
    let a435 = n + 435
    let a436 = n + 436
    let a437 = n + 437
    let a438 = n + 438
    let a439 = n + 439
    let a440 = n + 440
    let a441 = n + 441
    let a442 = n + 442
    let a443 = n + 443
    let a444 = n + 444
    let a445 = n + 445
    let a446 = n + 446
    let a447 = n + 447
    let a448 = n + 448
    let a449 = n + 449
    let a450 = n + 450
    let a451 = n + 451
    let a452 = n + 452
    let a453 = n + 453
    let a454 = n + 454
    let a455 = n + 455
    let a456 = n + 456
    let a457 = n + 457
    let a458 = n + 458
    let a459 = n + 459
    let a460 = n + 460
    let a461 = n + 461
    let a462 = n + 462
    let a463 = n + 463
    let a464 = n + 464
    let a465 = n + 465
    let a466 = n + 466
    let a467 = n + 467
    let a468 = n + 468
    let a469 = n + 469
    let a470 = n + 470
    let a471 = n + 471
    let a472 = n + 472
    let a473 = n + 473
    let a474 = n + 474
    let a475 = n + 475
    let a476 = n + 476
    let a477 = n + 477
    let a478 = n + 478
    let a479 = n + 479
    let a480 = n + 480
    let a481 = n + 481
    let a482 = n + 482
    let a483 = n + 483
    let a484 = n + 484
    let a485 = n + 485
    let a486 = n + 486
    let a487 = n + 487
    let a488 = n + 488
    let a489 = n + 489
    let a490 = n + 490
    let a491 = n + 491
    let a492 = n + 492
    let a493 = n + 493
    let a494 = n + 494
    let a495 = n + 495
    let a496 = n + 496
    let a497 = n + 497
    let a498 = n + 498
    let a499 = n + 499
    let a500 = n + 500
    let a501 = n + 501
    let a502 = n + 502
    let a503 = n + 503
    let a504 = n + 504
    let a505 = n + 505
    let a506 = n + 506
    let a507 = n + 507
    let a508 = n + 508
    let a509 = n + 509
    let a510 = n + 510
    let a511 = n + 511
    let a512 = n + 512
    let a513 = n + 513
    let a514 = n + 514
    let a515 = n + 515
    let a516 = n + 516
    let a517 = n + 517
    let a518 = n + 518
    let a519 = n + 519
    let a520 = n + 520
    let a521 = n + 521
    let a522 = n + 522
    let a523 = n + 523
    let a524 = n + 524
    let a525 = n + 525
    let a526 = n + 526
    let a527 = n + 527
    let a528 = n + 528
    let a529 = n + 529
    let a530 = n + 530
    let a531 = n + 531
    let a532 = n + 532
    let a533 = n + 533
    let a534 = n + 534
    let a535 = n + 535
    let a536 = n + 536
    let a537 = n + 537
    let a538 = n + 538
    let a539 = n + 539
    let a540 = n + 540
    let a541 = n + 541
    let a542 = n + 542
    let a543 = n + 543
    let a544 = n + 544
    let a545 = n + 545
    let a546 = n + 546
    let a547 = n + 547
    let a548 = n + 548
    let a549 = n + 549
    let a550 = n + 550
    let a551 = n + 551
    let a552 = n + 552
    let a553 = n + 553
    let a554 = n + 554
    let a555 = n + 555
    let a556 = n + 556
    let a557 = n + 557
    let a558 = n + 558
    let a559 = n + 559
    let a560 = n + 560
    let a561 = n + 561
    let a562 = n + 562
    let a563 = n + 563
    let a564 = n + 564
    let a565 = n + 565
    let a566 = n + 566
    let a567 = n + 567
    let a568 = n + 568
    let a569 = n + 569
    let a570 = n + 570
    let a571 = n + 571
    let a572 = n + 572
    let a573 = n + 573
    let a574 = n + 574
    let a575 = n + 575
    let a576 = n + 576
    let a577 = n + 577
    let a578 = n + 578
    let a579 = n + 579
    let a580 = n + 580
    let a581 = n + 581
    let a582 = n + 582
    let a583 = n + 583
    let a584 = n + 584
    let a585 = n + 585
    let a586 = n + 586
    let a587 = n + 587
    let a588 = n + 588
    let a589 = n + 589
    let a590 = n + 590
    let a591 = n + 591
    let a592 = n + 592
    let a593 = n + 593
    let a594 = n + 594
    let a595 = n + 595
    let a596 = n + 596
    let a597 = n + 597
    let a598 = n + 598
    let a599 = n + 599
    let a600 = n + 600
    let a601 = n + 601
    let a602 = n + 602
    let a603 = n + 603
    let a604 = n + 604
    let a605 = n + 605
    let a606 = n + 606
    let a607 = n + 607
    let a608 = n + 608
    let a609 = n + 609
    let a610 = n + 610
    let a611 = n + 611
    let a612 = n + 612
    let a613 = n + 613
    let a614 = n + 614
    let a615 = n + 615
    let a616 = n + 616
    let a617 = n + 617
    let a618 = n + 618
    let a619 = n + 619
    let a620 = n + 620
    let a621 = n + 621
    let a622 = n + 622
    let a623 = n + 623
    let a624 = n + 624
    let a625 = n + 625
    let a626 = n + 626
    let a627 = n + 627
    let a628 = n + 628
    let a629 = n + 629
    let a630 = n + 630
    let a631 = n + 631
    let a632 = n + 632
    let a633 = n + 633
    let a634 = n + 634
    let a635 = n + 635
    let a636 = n + 636
    let a637 = n + 637
    let a638 = n + 638
    let a639 = n + 639
    let a640 = n + 640
    let a641 = n + 641
    let a642 = n + 642
    let a643 = n + 643
    let a644 = n + 644
    let a645 = n + 645
    let a646 = n + 646
    let a647 = n + 647
    let a648 = n + 648
    let a649 = n + 649
    let a650 = n + 650
    let a651 = n + 651
    let a652 = n + 652
    let a653 = n + 653
    let a654 = n + 654
    let a655 = n + 655
    let a656 = n + 656
    let a657 = n + 657
    let a658 = n + 658
    let a659 = n + 659
    let a660 = n + 660
    let a661 = n + 661
    let a662 = n + 662
    let a663 = n + 663
    let a664 = n + 664
    let a665 = n + 665
    let a666 = n + 666
    let a667 = n + 667
    let a668 = n + 668
    let a669 = n + 669
    let a670 = n + 670
    let a671 = n + 671
    let a672 = n + 672
    let a673 = n + 673
    let a674 = n + 674
    let a675 = n + 675
    let a676 = n + 676
    let a677 = n + 677
    let a678 = n + 678
    let a679 = n + 679
    let a680 = n + 680
    let a681 = n + 681
    let a682 = n + 682
    let a683 = n + 683
    let a684 = n + 684
    let a685 = n + 685
    let a686 = n + 686
    let a687 = n + 687
    let a688 = n + 688
    let a689 = n + 689
    let a690 = n + 690
    let a691 = n + 691
    let a692 = n + 692
    let a693 = n + 693
    let a694 = n + 694
    let a695 = n + 695
    let a696 = n + 696
    let a697 = n + 697
    let a698 = n + 698
    let a699 = n + 699
    let a700 = n + 700
    let a701 = n + 701
    let a702 = n + 702
    let a703 = n + 703
    let a704 = n + 704
    let a705 = n + 705
    let a706 = n + 706
    let a707 = n + 707
    let a708 = n + 708
    let a709 = n + 709
    let a710 = n + 710
    let a711 = n + 711
    let a712 = n + 712
    let a713 = n + 713
    let a714 = n + 714
    let a715 = n + 715
    let a716 = n + 716
    let a717 = n + 717
    let a718 = n + 718
    let a719 = n + 719
    let a720 = n + 720
    let a721 = n + 721
    let a722 = n + 722
    let a723 = n + 723
    let a724 = n + 724
    let a725 = n + 725
    let a726 = n + 726
    let a727 = n + 727
    let a728 = n + 728
    let a729 = n + 729
    let a730 = n + 730
    let a731 = n + 731
    let a732 = n + 732
    let a733 = n + 733
    let a734 = n + 734
    let a735 = n + 735
    let a736 = n + 736
    let a737 = n + 737
    let a738 = n + 738
    let a739 = n + 739
    let a740 = n + 740
    let a741 = n + 741
    let a742 = n + 742
    let a743 = n + 743
    let a744 = n + 744
    let a745 = n + 745
    let a746 = n + 746
    let a747 = n + 747
    let a748 = n + 748
    let a749 = n + 749
    let a750 = n + 750
    let a751 = n + 751
    let a752 = n + 752
    let a753 = n + 753
    let a754 = n + 754
    let a755 = n + 755
    let a756 = n + 756
    let a757 = n + 757
    let a758 = n + 758
    let a759 = n + 759
    let a760 = n + 760
    let a761 = n + 761
    let a762 = n + 762
    let a763 = n + 763
    let a764 = n + 764
    let a765 = n + 765
    let a766 = n + 766
    let a767 = n + 767
    let a768 = n + 768
    let a769 = n + 769
    let a770 = n + 770
    let a771 = n + 771
    let a772 = n + 772
    let a773 = n + 773
    let a774 = n + 774
    let a775 = n + 775
    let a776 = n + 776
    let a777 = n + 777
    let a778 = n + 778
    let a779 = n + 779
    let a780 = n + 780
    let a781 = n + 781
    let a782 = n + 782
    let a783 = n + 783
    let a784 = n + 784
    let a785 = n + 785
    let a786 = n + 786
    let a787 = n + 787
    let a788 = n + 788
    let a789 = n + 789
    let a790 = n + 790
    let a791 = n + 791
    let a792 = n + 792
    let a793 = n + 793
    let a794 = n + 794
    let a795 = n + 795
    let a796 = n + 796
    let a797 = n + 797
    let a798 = n + 798
    let a799 = n + 799
    let a800 = n + 800
    let a801 = n + 801
    let a802 = n + 802
    let a803 = n + 803
    let a804 = n + 804
    let a805 = n + 805
    let a806 = n + 806
    let a807 = n + 807
    let a808 = n + 808
    let a809 = n + 809
    let a810 = n + 810
    let a811 = n + 811
    let a812 = n + 812
    let a813 = n + 813
    let a814 = n + 814
    let a815 = n + 815
    let a816 = n + 816
    let a817 = n + 817
    let a818 = n + 818
    let a819 = n + 819
    let a820 = n + 820
    let a821 = n + 821
    let a822 = n + 822
    let a823 = n + 823
    let a824 = n + 824
    let a825 = n + 825
    let a826 = n + 826
    let a827 = n + 827
    let a828 = n + 828
    let a829 = n + 829
    let a830 = n + 830
    let a831 = n + 831
    let a832 = n + 832
    let a833 = n + 833
    let a834 = n + 834
    let a835 = n + 835
    let a836 = n + 836
    let a837 = n + 837
    let a838 = n + 838
    let a839 = n + 839
    let a840 = n + 840
    let a841 = n + 841
    let a842 = n + 842
    let a843 = n + 843
    let a844 = n + 844
    let a845 = n + 845
    let a846 = n + 846
    let a847 = n + 847
    let a848 = n + 848
    let a849 = n + 849
    let a850 = n + 850
    let a851 = n + 851
    let a852 = n + 852
    let a853 = n + 853
    let a854 = n + 854
    let a855 = n + 855
    let a856 = n + 856
    let a857 = n + 857
    let a858 = n + 858
    let a859 = n + 859
    let a860 = n + 860
    let a861 = n + 861
    let a862 = n + 862
    let a863 = n + 863
    let a864 = n + 864
    let a865 = n + 865
    let a866 = n + 866
    let a867 = n + 867
    let a868 = n + 868
    let a869 = n + 869
    let a870 = n + 870
    let a871 = n + 871
    let a872 = n + 872
    let a873 = n + 873
    let a874 = n + 874
    let a875 = n + 875
    let a876 = n + 876
    let a877 = n + 877
    let a878 = n + 878
    let a879 = n + 879
    let a880 = n + 880
    let a881 = n + 881
    let a882 = n + 882
    let a883 = n + 883
    let a884 = n + 884
    let a885 = n + 885
    let a886 = n + 886
    let a887 = n + 887
    let a888 = n + 888
    let a889 = n + 889
    let a890 = n + 890
    let a891 = n + 891
    let a892 = n + 892
    let a893 = n + 893
    let a894 = n + 894
    let a895 = n + 895
    let a896 = n + 896
    let a897 = n + 897
    let a898 = n + 898
    let a899 = n + 899
    let a900 = n + 900
    let a901 = n + 901
    let a902 = n + 902
    let a903 = n + 903
    let a904 = n + 904
    let a905 = n + 905
    let a906 = n + 906
    let a907 = n + 907
    let a908 = n + 908
    let a909 = n + 909
    let a910 = n + 910
    let a911 = n + 911
    let a912 = n + 912
    let a913 = n + 913
    let a914 = n + 914
    let a915 = n + 915
    let a916 = n + 916
    let a917 = n + 917
    let a918 = n + 918
    let a919 = n + 919
    let a920 = n + 920
    let a921 = n + 921
    let a922 = n + 922
    let a923 = n + 923
    let a924 = n + 924
    let a925 = n + 925
    let a926 = n + 926
    let a927 = n + 927
    let a928 = n + 928
    let a929 = n + 929
    let a930 = n + 930
    let a931 = n + 931
    let a932 = n + 932
    let a933 = n + 933
    let a934 = n + 934
    let a935 = n + 935
    let a936 = n + 936
    let a937 = n + 937
    let a938 = n + 938
    let a939 = n + 939
    let a940 = n + 940
    let a941 = n + 941
    let a942 = n + 942
    let a943 = n + 943
    let a944 = n + 944
    let a945 = n + 945
    let a946 = n + 946
    let a947 = n + 947
    let a948 = n + 948
    let a949 = n + 949
    let a950 = n + 950
    let a951 = n + 951
    let a952 = n + 952
    let a953 = n + 953
    let a954 = n + 954
    let a955 = n + 955
    let a956 = n + 956
    let a957 = n + 957
    let a958 = n + 958
    let a959 = n + 959
    let a960 = n + 960
    let a961 = n + 961
    let a962 = n + 962
    let a963 = n + 963
    let a964 = n + 964
    let a965 = n + 965
    let a966 = n + 966
    let a967 = n + 967
    let a968 = n + 968
    let a969 = n + 969
    let a970 = n + 970
    let a971 = n + 971
    let a972 = n + 972
    let a973 = n + 973
    let a974 = n + 974
    let a975 = n + 975
    let a976 = n + 976
    let a977 = n + 977
    let a978 = n + 978
    let a979 = n + 979
    let a980 = n + 980
    let a981 = n + 981
    let a982 = n + 982
    let a983 = n + 983
    let a984 = n + 984
    let a985 = n + 985
    let a986 = n + 986
    let a987 = n + 987
    let a988 = n + 988
    let a989 = n + 989
    let a990 = n + 990
    let a991 = n + 991
    let a992 = n + 992
    let a993 = n + 993
    let a994 = n + 994
    let a995 = n + 995
    let a996 = n + 996
    let a997 = n + 997
    let a998 = n + 998
    let a999 = n + 999
    let a1000 = n + 1000
    let a1001 = n + 1001
    let a1002 = n + 1002
    let a1003 = n + 1003
    let a1004 = n + 1004
    let a1005 = n + 1005
    let a1006 = n + 1006
    let a1007 = n + 1007
    let a1008 = n + 1008
    let a1009 = n + 1009
    let a1010 = n + 1010
    let a1011 = n + 1011
    let a1012 = n + 1012
    let a1013 = n + 1013
    let a1014 = n + 1014
    let a1015 = n + 1015
    let a1016 = n + 1016
    let a1017 = n + 1017
    let a1018 = n + 1018
    let a1019 = n + 1019
    let a1020 = n + 1020
    let a1021 = n + 1021
    let a1022 = n + 1022
    let a1023 = n + 1023
    let a1024 = n + 1024
    let a1025 = n + 1025
    let a1026 = n + 1026
    let a1027 = n + 1027
    let a1028 = n + 1028
    let a1029 = n + 1029
    let a1030 = n + 1030
    let a1031 = n + 1031
    let a1032 = n + 1032
    let a1033 = n + 1033
    let a1034 = n + 1034
    let a1035 = n + 1035
    let a1036 = n + 1036
    let a1037 = n + 1037
    let a1038 = n + 1038
    let a1039 = n + 1039
    let a1040 = n + 1040
    let a1041 = n + 1041
    let a1042 = n + 1042
    let a1043 = n + 1043
    let a1044 = n + 1044
    let a1045 = n + 1045
    let a1046 = n + 1046
    let a1047 = n + 1047
    let a1048 = n + 1048
    let a1049 = n + 1049
    let a1050 = n + 1050
    let a1051 = n + 1051
    let a1052 = n + 1052
    let a1053 = n + 1053
    let a1054 = n + 1054
    let a1055 = n + 1055
    let a1056 = n + 1056
    let a1057 = n + 1057
    let a1058 = n + 1058
    let a1059 = n + 1059
    let a1060 = n + 1060
    let a1061 = n + 1061
    let a1062 = n + 1062
    let a1063 = n + 1063
    let a1064 = n + 1064
    let a1065 = n + 1065
    let a1066 = n + 1066
    let a1067 = n + 1067
    let a1068 = n + 1068
    let a1069 = n + 1069
    let a1070 = n + 1070
    let a1071 = n + 1071
    let a1072 = n + 1072
    let a1073 = n + 1073
    let a1074 = n + 1074
    let a1075 = n + 1075
    let a1076 = n + 1076
    let a1077 = n + 1077
    let a1078 = n + 1078
    let a1079 = n + 1079
    let a1080 = n + 1080
    let a1081 = n + 1081
    let a1082 = n + 1082
    let a1083 = n + 1083
    let a1084 = n + 1084
    let a1085 = n + 1085
    let a1086 = n + 1086
    let a1087 = n + 1087
    let a1088 = n + 1088
    let a1089 = n + 1089
    let a1090 = n + 1090
    let a1091 = n + 1091
    let a1092 = n + 1092
    let a1093 = n + 1093
    let a1094 = n + 1094
    let a1095 = n + 1095
    let a1096 = n + 1096
    let a1097 = n + 1097
    let a1098 = n + 1098
    let a1099 = n + 1099
    let a1100 = n + 1100
    let a1101 = n + 1101
    let a1102 = n + 1102
    let a1103 = n + 1103
    let a1104 = n + 1104
    let a1105 = n + 1105
    let a1106 = n + 1106
    let a1107 = n + 1107
    let a1108 = n + 1108
    let a1109 = n + 1109
    let a1110 = n + 1110
    let a1111 = n + 1111
    let a1112 = n + 1112
    let a1113 = n + 1113
    let a1114 = n + 1114
    let a1115 = n + 1115
    let a1116 = n + 1116
    let a1117 = n + 1117
    let a1118 = n + 1118
    let a1119 = n + 1119
    let a1120 = n + 1120
    let a1121 = n + 1121
    let a1122 = n + 1122
    let a1123 = n + 1123
    let a1124 = n + 1124
    let a1125 = n + 1125
    let a1126 = n + 1126
    let a1127 = n + 1127
    let a1128 = n + 1128
    let a1129 = n + 1129
    let a1130 = n + 1130
    let a1131 = n + 1131
    let a1132 = n + 1132
    let a1133 = n + 1133
    let a1134 = n + 1134
    let a1135 = n + 1135
    let a1136 = n + 1136
    let a1137 = n + 1137
    let a1138 = n + 1138
    let a1139 = n + 1139
    let a1140 = n + 1140
    let a1141 = n + 1141
    let a1142 = n + 1142
    let a1143 = n + 1143
    let a1144 = n + 1144
    let a1145 = n + 1145
    let a1146 = n + 1146
    let a1147 = n + 1147
    let a1148 = n + 1148
    let a1149 = n + 1149
    let a1150 = n + 1150
    let a1151 = n + 1151
    let a1152 = n + 1152
    let a1153 = n + 1153
    let a1154 = n + 1154
    let a1155 = n + 1155
    let a1156 = n + 1156
    let a1157 = n + 1157
    let a1158 = n + 1158
    let a1159 = n + 1159
    let a1160 = n + 1160
    let a1161 = n + 1161
    let a1162 = n + 1162
    let a1163 = n + 1163
    let a1164 = n + 1164
    let a1165 = n + 1165
    let a1166 = n + 1166
    let a1167 = n + 1167
    let a1168 = n + 1168
    let a1169 = n + 1169
    let a1170 = n + 1170
    let a1171 = n + 1171
    let a1172 = n + 1172
    let a1173 = n + 1173
    let a1174 = n + 1174
    let a1175 = n + 1175
    let a1176 = n + 1176
    let a1177 = n + 1177
    let a1178 = n + 1178
    let a1179 = n + 1179
    let a1180 = n + 1180
    let a1181 = n + 1181
    let a1182 = n + 1182
    let a1183 = n + 1183
    let a1184 = n + 1184
    let a1185 = n + 1185
    let a1186 = n + 1186
    let a1187 = n + 1187
    let a1188 = n + 1188
    let a1189 = n + 1189
    let a1190 = n + 1190
    let a1191 = n + 1191
    let a1192 = n + 1192
    let a1193 = n + 1193
    let a1194 = n + 1194
    let a1195 = n + 1195
    let a1196 = n + 1196
    let a1197 = n + 1197
    let a1198 = n + 1198
    let a1199 = n + 1199
    let a1200 = n + 1200
    let a1201 = n + 1201
    let a1202 = n + 1202
    let a1203 = n + 1203
    let a1204 = n + 1204
    let a1205 = n + 1205
    let a1206 = n + 1206
    let a1207 = n + 1207
    let a1208 = n + 1208
    let a1209 = n + 1209
    let a1210 = n + 1210
    let a1211 = n + 1211
    let a1212 = n + 1212
    let a1213 = n + 1213
    let a1214 = n + 1214
    let a1215 = n + 1215
    let a1216 = n + 1216
    let a1217 = n + 1217
    let a1218 = n + 1218
    let a1219 = n + 1219
    let a1220 = n + 1220
    let a1221 = n + 1221
    let a1222 = n + 1222
    let a1223 = n + 1223
    let a1224 = n + 1224
    let a1225 = n + 1225
    let a1226 = n + 1226
    let a1227 = n + 1227
    let a1228 = n + 1228
    let a1229 = n + 1229
    let a1230 = n + 1230
    let a1231 = n + 1231
    let a1232 = n + 1232
    let a1233 = n + 1233
    let a1234 = n + 1234
    let a1235 = n + 1235
    let a1236 = n + 1236
    let a1237 = n + 1237
    let a1238 = n + 1238
    let a1239 = n + 1239
    let a1240 = n + 1240
    let a1241 = n + 1241
    let a1242 = n + 1242
    let a1243 = n + 1243
    let a1244 = n + 1244
    let a1245 = n + 1245
    let a1246 = n + 1246
    let a1247 = n + 1247
    let a1248 = n + 1248
    let a1249 = n + 1249
    let a1250 = n + 1250
    let a1251 = n + 1251
    let a1252 = n + 1252
    let a1253 = n + 1253
    let a1254 = n + 1254
    let a1255 = n + 1255
    let a1256 = n + 1256
    let a1257 = n + 1257
    let a1258 = n + 1258
    let a1259 = n + 1259
    let a1260 = n + 1260
    let a1261 = n + 1261
    let a1262 = n + 1262
    let a1263 = n + 1263
    let a1264 = n + 1264
    let a1265 = n + 1265
    let a1266 = n + 1266
    let a1267 = n + 1267
    let a1268 = n + 1268
    let a1269 = n + 1269
    let a1270 = n + 1270
    let a1271 = n + 1271
    let a1272 = n + 1272
    let a1273 = n + 1273
    let a1274 = n + 1274
    let a1275 = n + 1275
    let a1276 = n + 1276
    let a1277 = n + 1277
    let a1278 = n + 1278
    let a1279 = n + 1279
    let a1280 = n + 1280
    let a1281 = n + 1281
    let a1282 = n + 1282
    let a1283 = n + 1283
    let a1284 = n + 1284
    let a1285 = n + 1285
    let a1286 = n + 1286
    let a1287 = n + 1287
    let a1288 = n + 1288
    let a1289 = n + 1289
    let a1290 = n + 1290
    let a1291 = n + 1291
    let a1292 = n + 1292
    let a1293 = n + 1293
    let a1294 = n + 1294
    let a1295 = n + 1295
    let a1296 = n + 1296
    let a1297 = n + 1297
    let a1298 = n + 1298
    let a1299 = n + 1299
    let a1300 = n + 1300
    let a1301 = n + 1301
    let a1302 = n + 1302
    let a1303 = n + 1303
    let a1304 = n + 1304
    let a1305 = n + 1305
    let a1306 = n + 1306
    let a1307 = n + 1307
    let a1308 = n + 1308
    let a1309 = n + 1309
    let a1310 = n + 1310
    let a1311 = n + 1311
    let a1312 = n + 1312
    let a1313 = n + 1313
    let a1314 = n + 1314
    let a1315 = n + 1315
    let a1316 = n + 1316
    let a1317 = n + 1317
    let a1318 = n + 1318
    let a1319 = n + 1319
    let a1320 = n + 1320
    let a1321 = n + 1321
    let a1322 = n + 1322
    let a1323 = n + 1323
    let a1324 = n + 1324
    let a1325 = n + 1325
    let a1326 = n + 1326
    let a1327 = n + 1327
    let a1328 = n + 1328
    let a1329 = n + 1329
    let a1330 = n + 1330
    let a1331 = n + 1331
    let a1332 = n + 1332
    let a1333 = n + 1333
    let a1334 = n + 1334
    let a1335 = n + 1335
    let a1336 = n + 1336
    let a1337 = n + 1337
    let a1338 = n + 1338
    let a1339 = n + 1339
    let a1340 = n + 1340
    let a1341 = n + 1341
    let a1342 = n + 1342
    let a1343 = n + 1343
    let a1344 = n + 1344
    let a1345 = n + 1345
    let a1346 = n + 1346
    let a1347 = n + 1347
    let a1348 = n + 1348
    let a1349 = n + 1349
    let a1350 = n + 1350
    let a1351 = n + 1351
    let a1352 = n + 1352
    let a1353 = n + 1353
    let a1354 = n + 1354
    let a1355 = n + 1355
    let a1356 = n + 1356
    let a1357 = n + 1357
    let a1358 = n + 1358
    let a1359 = n + 1359
    let a1360 = n + 1360
    let a1361 = n + 1361
    let a1362 = n + 1362
    let a1363 = n + 1363
    let a1364 = n + 1364
    let a1365 = n + 1365
    let a1366 = n + 1366
    let a1367 = n + 1367
    let a1368 = n + 1368
    let a1369 = n + 1369
    let a1370 = n + 1370
    let a1371 = n + 1371
    let a1372 = n + 1372
    let a1373 = n + 1373
    let a1374 = n + 1374
    let a1375 = n + 1375
    let a1376 = n + 1376
    let a1377 = n + 1377
    let a1378 = n + 1378
    let a1379 = n + 1379
    let a1380 = n + 1380
    let a1381 = n + 1381
    let a1382 = n + 1382
    let a1383 = n + 1383
    let a1384 = n + 1384
    let a1385 = n + 1385
    let a1386 = n + 1386
    let a1387 = n + 1387
    let a1388 = n + 1388
    let a1389 = n + 1389
    let a1390 = n + 1390
    let a1391 = n + 1391
    let a1392 = n + 1392
    let a1393 = n + 1393
    let a1394 = n + 1394
    let a1395 = n + 1395
    let a1396 = n + 1396
    let a1397 = n + 1397
    let a1398 = n + 1398
    let a1399 = n + 1399
    let a1400 = n + 1400
    let a1401 = n + 1401
    let a1402 = n + 1402
    let a1403 = n + 1403
    let a1404 = n + 1404
    let a1405 = n + 1405
    let a1406 = n + 1406
    let a1407 = n + 1407
    let a1408 = n + 1408
    let a1409 = n + 1409
    let a1410 = n + 1410
    let a1411 = n + 1411
    let a1412 = n + 1412
    let a1413 = n + 1413
    let a1414 = n + 1414
    let a1415 = n + 1415
    let a1416 = n + 1416
    let a1417 = n + 1417
    let a1418 = n + 1418
    let a1419 = n + 1419
    let a1420 = n + 1420
    let a1421 = n + 1421
    let a1422 = n + 1422
    let a1423 = n + 1423
    let a1424 = n + 1424
    let a1425 = n + 1425
    let a1426 = n + 1426
    let a1427 = n + 1427
    let a1428 = n + 1428
    let a1429 = n + 1429
    let a1430 = n + 1430
    let a1431 = n + 1431
    let a1432 = n + 1432
    let a1433 = n + 1433
    let a1434 = n + 1434
    let a1435 = n + 1435
    let a1436 = n + 1436
    let a1437 = n + 1437
    let a1438 = n + 1438
    let a1439 = n + 1439
    let a1440 = n + 1440
    let a1441 = n + 1441
    let a1442 = n + 1442
    let a1443 = n + 1443
    let a1444 = n + 1444
    let a1445 = n + 1445
    let a1446 = n + 1446
    let a1447 = n + 1447
    let a1448 = n + 1448
    let a1449 = n + 1449
    let a1450 = n + 1450
    let a1451 = n + 1451
    let a1452 = n + 1452
    let a1453 = n + 1453
    let a1454 = n + 1454
    let a1455 = n + 1455
    let a1456 = n + 1456
    let a1457 = n + 1457
    let a1458 = n + 1458
    let a1459 = n + 1459
    let a1460 = n + 1460
    let a1461 = n + 1461
    let a1462 = n + 1462
    let a1463 = n + 1463
    let a1464 = n + 1464
    let a1465 = n + 1465
    let a1466 = n + 1466
    let a1467 = n + 1467
    let a1468 = n + 1468
    let a1469 = n + 1469
    let a1470 = n + 1470
    let a1471 = n + 1471
    let a1472 = n + 1472
    let a1473 = n + 1473
    let a1474 = n + 1474
    let a1475 = n + 1475
    let a1476 = n + 1476
    let a1477 = n + 1477
    let a1478 = n + 1478
    let a1479 = n + 1479
    let a1480 = n + 1480
    let a1481 = n + 1481
    let a1482 = n + 1482
    let a1483 = n + 1483
    let a1484 = n + 1484
    let a1485 = n + 1485
    let a1486 = n + 1486
    let a1487 = n + 1487
    let a1488 = n + 1488
    let a1489 = n + 1489
    let a1490 = n + 1490
    let a1491 = n + 1491
    let a1492 = n + 1492
    let a1493 = n + 1493
    let a1494 = n + 1494
    let a1495 = n + 1495
    let a1496 = n + 1496
    let a1497 = n + 1497
    let a1498 = n + 1498
    let a1499 = n + 1499
    let deeper = fat(n % 1000 + 1)
    return (
        deeper
        + (
            a0
            + a1
            + a2
            + a3
            + a4
            + a5
            + a6
            + a7
            + a8
            + a9
            + a10
            + a11
            + a12
            + a13
            + a14
            + a15
            + a16
            + a17
            + a18
            + a19
            + a20
            + a21
            + a22
            + a23
            + a24
            + a25
            + a26
            + a27
            + a28
            + a29
            + a30
            + a31
            + a32
            + a33
            + a34
            + a35
            + a36
            + a37
            + a38
            + a39
            + a40
            + a41
            + a42
            + a43
            + a44
            + a45
            + a46
            + a47
            + a48
            + a49
            + a50
            + a51
            + a52
            + a53
            + a54
            + a55
            + a56
            + a57
            + a58
            + a59
            + a60
            + a61
            + a62
            + a63
            + a64
            + a65
            + a66
            + a67
            + a68
            + a69
            + a70
            + a71
            + a72
            + a73
            + a74
            + a75
            + a76
            + a77
            + a78
            + a79
            + a80
            + a81
            + a82
            + a83
            + a84
            + a85
            + a86
            + a87
            + a88
            + a89
            + a90
            + a91
            + a92
            + a93
            + a94
            + a95
            + a96
            + a97
            + a98
            + a99
            + a100
            + a101
            + a102
            + a103
            + a104
            + a105
            + a106
            + a107
            + a108
            + a109
            + a110
            + a111
            + a112
            + a113
            + a114
            + a115
            + a116
            + a117
            + a118
            + a119
            + a120
            + a121
            + a122
            + a123
            + a124
            + a125
            + a126
            + a127
            + a128
            + a129
            + a130
            + a131
            + a132
            + a133
            + a134
            + a135
            + a136
            + a137
            + a138
            + a139
            + a140
            + a141
            + a142
            + a143
            + a144
            + a145
            + a146
            + a147
            + a148
            + a149
            + a150
            + a151
            + a152
            + a153
            + a154
            + a155
            + a156
            + a157
            + a158
            + a159
            + a160
            + a161
            + a162
            + a163
            + a164
            + a165
            + a166
            + a167
            + a168
            + a169
            + a170
            + a171
            + a172
            + a173
            + a174
            + a175
            + a176
            + a177
            + a178
            + a179
            + a180
            + a181
            + a182
            + a183
            + a184
            + a185
            + a186
            + a187
            + a188
            + a189
            + a190
            + a191
            + a192
            + a193
            + a194
            + a195
            + a196
            + a197
            + a198
            + a199
            + a200
            + a201
            + a202
            + a203
            + a204
            + a205
            + a206
            + a207
            + a208
            + a209
            + a210
            + a211
            + a212
            + a213
            + a214
            + a215
            + a216
            + a217
            + a218
            + a219
            + a220
            + a221
            + a222
            + a223
            + a224
            + a225
            + a226
            + a227
            + a228
            + a229
            + a230
            + a231
            + a232
            + a233
            + a234
            + a235
            + a236
            + a237
            + a238
            + a239
            + a240
            + a241
            + a242
            + a243
            + a244
            + a245
            + a246
            + a247
            + a248
            + a249
            + a250
            + a251
            + a252
            + a253
            + a254
            + a255
            + a256
            + a257
            + a258
            + a259
            + a260
            + a261
            + a262
            + a263
            + a264
            + a265
            + a266
            + a267
            + a268
            + a269
            + a270
            + a271
            + a272
            + a273
            + a274
            + a275
            + a276
            + a277
            + a278
            + a279
            + a280
            + a281
            + a282
            + a283
            + a284
            + a285
            + a286
            + a287
            + a288
            + a289
            + a290
            + a291
            + a292
            + a293
            + a294
            + a295
            + a296
            + a297
            + a298
            + a299
            + a300
            + a301
            + a302
            + a303
            + a304
            + a305
            + a306
            + a307
            + a308
            + a309
            + a310
            + a311
            + a312
            + a313
            + a314
            + a315
            + a316
            + a317
            + a318
            + a319
            + a320
            + a321
            + a322
            + a323
            + a324
            + a325
            + a326
            + a327
            + a328
            + a329
            + a330
            + a331
            + a332
            + a333
            + a334
            + a335
            + a336
            + a337
            + a338
            + a339
            + a340
            + a341
            + a342
            + a343
            + a344
            + a345
            + a346
            + a347
            + a348
            + a349
            + a350
            + a351
            + a352
            + a353
            + a354
            + a355
            + a356
            + a357
            + a358
            + a359
            + a360
            + a361
            + a362
            + a363
            + a364
            + a365
            + a366
            + a367
            + a368
            + a369
            + a370
            + a371
            + a372
            + a373
            + a374
            + a375
            + a376
            + a377
            + a378
            + a379
            + a380
            + a381
            + a382
            + a383
            + a384
            + a385
            + a386
            + a387
            + a388
            + a389
            + a390
            + a391
            + a392
            + a393
            + a394
            + a395
            + a396
            + a397
            + a398
            + a399
            + a400
            + a401
            + a402
            + a403
            + a404
            + a405
            + a406
            + a407
            + a408
            + a409
            + a410
            + a411
            + a412
            + a413
            + a414
            + a415
            + a416
            + a417
            + a418
            + a419
            + a420
            + a421
            + a422
            + a423
            + a424
            + a425
            + a426
            + a427
            + a428
            + a429
            + a430
            + a431
            + a432
            + a433
            + a434
            + a435
            + a436
            + a437
            + a438
            + a439
            + a440
            + a441
            + a442
            + a443
            + a444
            + a445
            + a446
            + a447
            + a448
            + a449
            + a450
            + a451
            + a452
            + a453
            + a454
            + a455
            + a456
            + a457
            + a458
            + a459
            + a460
            + a461
            + a462
            + a463
            + a464
            + a465
            + a466
            + a467
            + a468
            + a469
            + a470
            + a471
            + a472
            + a473
            + a474
            + a475
            + a476
            + a477
            + a478
            + a479
            + a480
            + a481
            + a482
            + a483
            + a484
            + a485
            + a486
            + a487
            + a488
            + a489
            + a490
            + a491
            + a492
            + a493
            + a494
            + a495
            + a496
            + a497
            + a498
            + a499
            + a500
            + a501
            + a502
            + a503
            + a504
            + a505
            + a506
            + a507
            + a508
            + a509
            + a510
            + a511
            + a512
            + a513
            + a514
            + a515
            + a516
            + a517
            + a518
            + a519
            + a520
            + a521
            + a522
            + a523
            + a524
            + a525
            + a526
            + a527
            + a528
            + a529
            + a530
            + a531
            + a532
            + a533
            + a534
            + a535
            + a536
            + a537
            + a538
            + a539
            + a540
            + a541
            + a542
            + a543
            + a544
            + a545
            + a546
            + a547
            + a548
            + a549
            + a550
            + a551
            + a552
            + a553
            + a554
            + a555
            + a556
            + a557
            + a558
            + a559
            + a560
            + a561
            + a562
            + a563
            + a564
            + a565
            + a566
            + a567
            + a568
            + a569
            + a570
            + a571
            + a572
            + a573
            + a574
            + a575
            + a576
            + a577
            + a578
            + a579
            + a580
            + a581
            + a582
            + a583
            + a584
            + a585
            + a586
            + a587
            + a588
            + a589
            + a590
            + a591
            + a592
            + a593
            + a594
            + a595
            + a596
            + a597
            + a598
            + a599
            + a600
            + a601
            + a602
            + a603
            + a604
            + a605
            + a606
            + a607
            + a608
            + a609
            + a610
            + a611
            + a612
            + a613
            + a614
            + a615
            + a616
            + a617
            + a618
            + a619
            + a620
            + a621
            + a622
            + a623
            + a624
            + a625
            + a626
            + a627
            + a628
            + a629
            + a630
            + a631
            + a632
            + a633
            + a634
            + a635
            + a636
            + a637
            + a638
            + a639
            + a640
            + a641
            + a642
            + a643
            + a644
            + a645
            + a646
            + a647
            + a648
            + a649
            + a650
            + a651
            + a652
            + a653
            + a654
            + a655
            + a656
            + a657
            + a658
            + a659
            + a660
            + a661
            + a662
            + a663
            + a664
            + a665
            + a666
            + a667
            + a668
            + a669
            + a670
            + a671
            + a672
            + a673
            + a674
            + a675
            + a676
            + a677
            + a678
            + a679
            + a680
            + a681
            + a682
            + a683
            + a684
            + a685
            + a686
            + a687
            + a688
            + a689
            + a690
            + a691
            + a692
            + a693
            + a694
            + a695
            + a696
            + a697
            + a698
            + a699
            + a700
            + a701
            + a702
            + a703
            + a704
            + a705
            + a706
            + a707
            + a708
            + a709
            + a710
            + a711
            + a712
            + a713
            + a714
            + a715
            + a716
            + a717
            + a718
            + a719
            + a720
            + a721
            + a722
            + a723
            + a724
            + a725
            + a726
            + a727
            + a728
            + a729
            + a730
            + a731
            + a732
            + a733
            + a734
            + a735
            + a736
            + a737
            + a738
            + a739
            + a740
            + a741
            + a742
            + a743
            + a744
            + a745
            + a746
            + a747
            + a748
            + a749
            + a750
            + a751
            + a752
            + a753
            + a754
            + a755
            + a756
            + a757
            + a758
            + a759
            + a760
            + a761
            + a762
            + a763
            + a764
            + a765
            + a766
            + a767
            + a768
            + a769
            + a770
            + a771
            + a772
            + a773
            + a774
            + a775
            + a776
            + a777
            + a778
            + a779
            + a780
            + a781
            + a782
            + a783
            + a784
            + a785
            + a786
            + a787
            + a788
            + a789
            + a790
            + a791
            + a792
            + a793
            + a794
            + a795
            + a796
            + a797
            + a798
            + a799
            + a800
            + a801
            + a802
            + a803
            + a804
            + a805
            + a806
            + a807
            + a808
            + a809
            + a810
            + a811
            + a812
            + a813
            + a814
            + a815
            + a816
            + a817
            + a818
            + a819
            + a820
            + a821
            + a822
            + a823
            + a824
            + a825
            + a826
            + a827
            + a828
            + a829
            + a830
            + a831
            + a832
            + a833
            + a834
            + a835
            + a836
            + a837
            + a838
            + a839
            + a840
            + a841
            + a842
            + a843
            + a844
            + a845
            + a846
            + a847
            + a848
            + a849
            + a850
            + a851
            + a852
            + a853
            + a854
            + a855
            + a856
            + a857
            + a858
            + a859
            + a860
            + a861
            + a862
            + a863
            + a864
            + a865
            + a866
            + a867
            + a868
            + a869
            + a870
            + a871
            + a872
            + a873
            + a874
            + a875
            + a876
            + a877
            + a878
            + a879
            + a880
            + a881
            + a882
            + a883
            + a884
            + a885
            + a886
            + a887
            + a888
            + a889
            + a890
            + a891
            + a892
            + a893
            + a894
            + a895
            + a896
            + a897
            + a898
            + a899
            + a900
            + a901
            + a902
            + a903
            + a904
            + a905
            + a906
            + a907
            + a908
            + a909
            + a910
            + a911
            + a912
            + a913
            + a914
            + a915
            + a916
            + a917
            + a918
            + a919
            + a920
            + a921
            + a922
            + a923
            + a924
            + a925
            + a926
            + a927
            + a928
            + a929
            + a930
            + a931
            + a932
            + a933
            + a934
            + a935
            + a936
            + a937
            + a938
            + a939
            + a940
            + a941
            + a942
            + a943
            + a944
            + a945
            + a946
            + a947
            + a948
            + a949
            + a950
            + a951
            + a952
            + a953
            + a954
            + a955
            + a956
            + a957
            + a958
            + a959
            + a960
            + a961
            + a962
            + a963
            + a964
            + a965
            + a966
            + a967
            + a968
            + a969
            + a970
            + a971
            + a972
            + a973
            + a974
            + a975
            + a976
            + a977
            + a978
            + a979
            + a980
            + a981
            + a982
            + a983
            + a984
            + a985
            + a986
            + a987
            + a988
            + a989
            + a990
            + a991
            + a992
            + a993
            + a994
            + a995
            + a996
            + a997
            + a998
            + a999
            + a1000
            + a1001
            + a1002
            + a1003
            + a1004
            + a1005
            + a1006
            + a1007
            + a1008
            + a1009
            + a1010
            + a1011
            + a1012
            + a1013
            + a1014
            + a1015
            + a1016
            + a1017
            + a1018
            + a1019
            + a1020
            + a1021
            + a1022
            + a1023
            + a1024
            + a1025
            + a1026
            + a1027
            + a1028
            + a1029
            + a1030
            + a1031
            + a1032
            + a1033
            + a1034
            + a1035
            + a1036
            + a1037
            + a1038
            + a1039
            + a1040
            + a1041
            + a1042
            + a1043
            + a1044
            + a1045
            + a1046
            + a1047
            + a1048
            + a1049
            + a1050
            + a1051
            + a1052
            + a1053
            + a1054
            + a1055
            + a1056
            + a1057
            + a1058
            + a1059
            + a1060
            + a1061
            + a1062
            + a1063
            + a1064
            + a1065
            + a1066
            + a1067
            + a1068
            + a1069
            + a1070
            + a1071
            + a1072
            + a1073
            + a1074
            + a1075
            + a1076
            + a1077
            + a1078
            + a1079
            + a1080
            + a1081
            + a1082
            + a1083
            + a1084
            + a1085
            + a1086
            + a1087
            + a1088
            + a1089
            + a1090
            + a1091
            + a1092
            + a1093
            + a1094
            + a1095
            + a1096
            + a1097
            + a1098
            + a1099
            + a1100
            + a1101
            + a1102
            + a1103
            + a1104
            + a1105
            + a1106
            + a1107
            + a1108
            + a1109
            + a1110
            + a1111
            + a1112
            + a1113
            + a1114
            + a1115
            + a1116
            + a1117
            + a1118
            + a1119
            + a1120
            + a1121
            + a1122
            + a1123
            + a1124
            + a1125
            + a1126
            + a1127
            + a1128
            + a1129
            + a1130
            + a1131
            + a1132
            + a1133
            + a1134
            + a1135
            + a1136
            + a1137
            + a1138
            + a1139
            + a1140
            + a1141
            + a1142
            + a1143
            + a1144
            + a1145
            + a1146
            + a1147
            + a1148
            + a1149
            + a1150
            + a1151
            + a1152
            + a1153
            + a1154
            + a1155
            + a1156
            + a1157
            + a1158
            + a1159
            + a1160
            + a1161
            + a1162
            + a1163
            + a1164
            + a1165
            + a1166
            + a1167
            + a1168
            + a1169
            + a1170
            + a1171
            + a1172
            + a1173
            + a1174
            + a1175
            + a1176
            + a1177
            + a1178
            + a1179
            + a1180
            + a1181
            + a1182
            + a1183
            + a1184
            + a1185
            + a1186
            + a1187
            + a1188
            + a1189
            + a1190
            + a1191
            + a1192
            + a1193
            + a1194
            + a1195
            + a1196
            + a1197
            + a1198
            + a1199
            + a1200
            + a1201
            + a1202
            + a1203
            + a1204
            + a1205
            + a1206
            + a1207
            + a1208
            + a1209
            + a1210
            + a1211
            + a1212
            + a1213
            + a1214
            + a1215
            + a1216
            + a1217
            + a1218
            + a1219
            + a1220
            + a1221
            + a1222
            + a1223
            + a1224
            + a1225
            + a1226
            + a1227
            + a1228
            + a1229
            + a1230
            + a1231
            + a1232
            + a1233
            + a1234
            + a1235
            + a1236
            + a1237
            + a1238
            + a1239
            + a1240
            + a1241
            + a1242
            + a1243
            + a1244
            + a1245
            + a1246
            + a1247
            + a1248
            + a1249
            + a1250
            + a1251
            + a1252
            + a1253
            + a1254
            + a1255
            + a1256
            + a1257
            + a1258
            + a1259
            + a1260
            + a1261
            + a1262
            + a1263
            + a1264
            + a1265
            + a1266
            + a1267
            + a1268
            + a1269
            + a1270
            + a1271
            + a1272
            + a1273
            + a1274
            + a1275
            + a1276
            + a1277
            + a1278
            + a1279
            + a1280
            + a1281
            + a1282
            + a1283
            + a1284
            + a1285
            + a1286
            + a1287
            + a1288
            + a1289
            + a1290
            + a1291
            + a1292
            + a1293
            + a1294
            + a1295
            + a1296
            + a1297
            + a1298
            + a1299
            + a1300
            + a1301
            + a1302
            + a1303
            + a1304
            + a1305
            + a1306
            + a1307
            + a1308
            + a1309
            + a1310
            + a1311
            + a1312
            + a1313
            + a1314
            + a1315
            + a1316
            + a1317
            + a1318
            + a1319
            + a1320
            + a1321
            + a1322
            + a1323
            + a1324
            + a1325
            + a1326
            + a1327
            + a1328
            + a1329
            + a1330
            + a1331
            + a1332
            + a1333
            + a1334
            + a1335
            + a1336
            + a1337
            + a1338
            + a1339
            + a1340
            + a1341
            + a1342
            + a1343
            + a1344
            + a1345
            + a1346
            + a1347
            + a1348
            + a1349
            + a1350
            + a1351
            + a1352
            + a1353
            + a1354
            + a1355
            + a1356
            + a1357
            + a1358
            + a1359
            + a1360
            + a1361
            + a1362
            + a1363
            + a1364
            + a1365
            + a1366
            + a1367
            + a1368
            + a1369
            + a1370
            + a1371
            + a1372
            + a1373
            + a1374
            + a1375
            + a1376
            + a1377
            + a1378
            + a1379
            + a1380
            + a1381
            + a1382
            + a1383
            + a1384
            + a1385
            + a1386
            + a1387
            + a1388
            + a1389
            + a1390
            + a1391
            + a1392
            + a1393
            + a1394
            + a1395
            + a1396
            + a1397
            + a1398
            + a1399
            + a1400
            + a1401
            + a1402
            + a1403
            + a1404
            + a1405
            + a1406
            + a1407
            + a1408
            + a1409
            + a1410
            + a1411
            + a1412
            + a1413
            + a1414
            + a1415
            + a1416
            + a1417
            + a1418
            + a1419
            + a1420
            + a1421
            + a1422
            + a1423
            + a1424
            + a1425
            + a1426
            + a1427
            + a1428
            + a1429
            + a1430
            + a1431
            + a1432
            + a1433
            + a1434
            + a1435
            + a1436
            + a1437
            + a1438
            + a1439
            + a1440
            + a1441
            + a1442
            + a1443
            + a1444
            + a1445
            + a1446
            + a1447
            + a1448
            + a1449
            + a1450
            + a1451
            + a1452
            + a1453
            + a1454
            + a1455
            + a1456
            + a1457
            + a1458
            + a1459
            + a1460
            + a1461
            + a1462
            + a1463
            + a1464
            + a1465
            + a1466
            + a1467
            + a1468
            + a1469
            + a1470
            + a1471
            + a1472
            + a1473
            + a1474
            + a1475
            + a1476
            + a1477
            + a1478
            + a1479
            + a1480
            + a1481
            + a1482
            + a1483
            + a1484
            + a1485
            + a1486
            + a1487
            + a1488
            + a1489
            + a1490
            + a1491
            + a1492
            + a1493
            + a1494
            + a1495
            + a1496
            + a1497
            + a1498
            + a1499
        ) % 7
    )

test "stack exhaustion is reported as a stack overflow":
    let message = try expect_fault(
        fn:
            let _ignored = fat(0)
    )
    message | try expect_contains("stack overflow")

//
//  DiffMatchPatchTest.m
//  DiffMatchPatch
//
//  Created by Jesse Grosjean on 12/18/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import "DiffMatchPatchTest.h"
#import "DiffMatchPatch.h"

@implementation DiffMatchPatchTest

- (void)setUp {
	dmp = [[DiffMatchPatch alloc] init];
}

- (void)tearDown {
}

- (void)testDiffCommonPrefix {
	STAssertEquals(0, [dmp diffCommonPrefixText1:@"abc" text2:@"xyz"], @"diff_commonPrefix: Null case.");
	STAssertEquals(4, [dmp diffCommonPrefixText1:@"1234abcdef" text2:@"1234xyz"], @"diff_commonPrefix: Non-null case.");
}

- (void)testDiffCommonSuffix {
	STAssertEquals(0, [dmp diffCommonSuffixText1:@"abc" text2:@"xyz"], @"diff_commonSuffix: Null case.");
	STAssertEquals(4, [dmp diffCommonSuffixText1:@"abcdef1234" text2:@"xyz1234"], @"diff_commonSuffix: Non-null case.");
}

- (void)testDiffHalfMatch {
	id expected;
	STAssertNil([dmp diffHalfMatchText1:@"1234567890" text2:@"abcdef"], nil);
	expected = [NSArray arrayWithObjects:@"12", @"90", @"a", @"z", @"345678", nil];
	STAssertEqualObjects(expected, [dmp diffHalfMatchText1:@"1234567890" text2:@"a345678z"], nil);
	expected = [NSArray arrayWithObjects:@"a", @"z", @"12", @"90", @"345678", nil];
	STAssertEqualObjects(expected, [dmp diffHalfMatchText1:@"a345678z" text2:@"1234567890"], nil);
	expected = [NSArray arrayWithObjects:@"12123", @"123121", @"a", @"z", @"1234123451234", nil];
	STAssertEqualObjects(expected, [dmp diffHalfMatchText1:@"121231234123451234123121" text2:@"a1234123451234z"], nil);
	expected = [NSArray arrayWithObjects:@"", @"-=-=-=-=-=", @"x", @"", @"x-=-=-=-=-=-=-=", nil];
	STAssertEqualObjects(expected, [dmp diffHalfMatchText1:@"x-=-=-=-=-=-=-=-=-=-=-=-=" text2:@"xx-=-=-=-=-=-=-="], nil);
	expected = [NSArray arrayWithObjects:@"-=-=-=-=-=", @"", @"", @"y", @"-=-=-=-=-=-=-=y", nil];
	STAssertEqualObjects(expected, [dmp diffHalfMatchText1:@"-=-=-=-=-=-=-=-=-=-=-=-=y" text2:@"-=-=-=-=-=-=-=yy"], nil);
}

- (void)testDiffCleanupMerge {
	id expected;
	
	NSMutableArray *diffs = [NSMutableArray array];
	[dmp diffCleanupMerge:diffs];
	STAssertEqualObjects(diffs, [NSArray array], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"b"], [BDiff insert:@"c"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"b"], [BDiff insert:@"c"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff equal:@"b"], [BDiff equal:@"c"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"abc"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff delete:@"b"], [BDiff delete:@"c"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abc"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"a"], [BDiff insert:@"b"], [BDiff insert:@"c"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff insert:@"abc"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"b"], [BDiff delete:@"c"], [BDiff insert:@"d"], [BDiff equal:@"e"], [BDiff equal:@"f"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"ac"], [BDiff insert:@"bd"], [BDiff equal:@"ef"], nil];
	STAssertEqualObjects(diffs, expected, nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"abc"], [BDiff delete:@"dc"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"d"], [BDiff insert:@"b"], [BDiff equal:@"c"], nil];
	STAssertEqualObjects(diffs, expected, nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff insert:@"ba"], [BDiff equal:@"c"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff insert:@"ab"], [BDiff equal:@"ac"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"c"], [BDiff insert:@"ab"], [BDiff equal:@"a"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"ca"], [BDiff insert:@"ba"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"b"], [BDiff equal:@"c"], [BDiff delete:@"ac"], [BDiff equal:@"x"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abc"], [BDiff equal:@"acx"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"x"], [BDiff delete:@"ca"], [BDiff equal:@"c"], [BDiff delete:@"b"], [BDiff equal:@"a"], nil];
	[dmp diffCleanupMerge:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"xca"], [BDiff delete:@"cba"], nil];
	STAssertEqualObjects(diffs, expected, nil);
}

- (void)testDiffCleanupSemanticLossless {
	id expected;

	NSMutableArray *diffs = [NSMutableArray array];
	[dmp diffCleanupSemanticLossless:diffs];
	STAssertEqualObjects(diffs, [NSArray array], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"AAA\r\n\r\nBBB"], [BDiff insert:@"\r\nDDD\r\n\r\nBBB"], [BDiff equal:@"\r\nEEE"], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"AAA\r\n\r\n"], [BDiff insert:@"BBB\r\nDDD\r\n\r\n"], [BDiff equal:@"BBB\r\nEEE"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"AAA\r\nBBB"], [BDiff insert:@" DDD\r\nBBB"], [BDiff equal:@" EEE"], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"AAA\r\n"], [BDiff insert:@"BBB DDD\r\n"], [BDiff equal:@"BBB EEE"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"The c"], [BDiff insert:@"ow and the c"], [BDiff equal:@"at."], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"The "], [BDiff insert:@"cow and the "], [BDiff equal:@"cat."], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"The-c"], [BDiff insert:@"ow-and-the-c"], [BDiff equal:@"at."], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"The-"], [BDiff insert:@"cow-and-the-"], [BDiff equal:@"cat."], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"a"], [BDiff equal:@"ax"], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff equal:@"aax"], nil];
	STAssertEqualObjects(diffs, expected, nil);	

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"xa"], [BDiff delete:@"a"], [BDiff equal:@"a"], nil];
	[dmp diffCleanupSemanticLossless:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"xaa"], [BDiff delete:@"a"], nil];
	STAssertEqualObjects(diffs, expected, nil);	
}

- (void)testDiffCleanupSemantic {
	id expected;
	
	NSMutableArray *diffs = [NSMutableArray array];
	[dmp diffCleanupSemantic:diffs];
	STAssertEqualObjects(diffs, [NSArray array], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"b"], [BDiff equal:@"cd"], [BDiff delete:@"e"], nil];
	[dmp diffCleanupSemantic:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"b"], [BDiff equal:@"cd"], [BDiff delete:@"e"], nil];
	STAssertEqualObjects(diffs, expected, nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff equal:@"b"], [BDiff delete:@"c"], nil];
	[dmp diffCleanupSemantic:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abc"], [BDiff insert:@"b"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff equal:@"cd"], [BDiff delete:@"e"], [BDiff equal:@"f"], [BDiff insert:@"g"], nil];
	[dmp diffCleanupSemantic:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abcdef"], [BDiff insert:@"cdfg"], nil];
	STAssertEqualObjects(diffs, expected, nil);	
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"1"], [BDiff equal:@"A"], [BDiff delete:@"B"], [BDiff insert:@"2"], [BDiff equal:@"_"], [BDiff insert:@"1"], [BDiff equal:@"A"], [BDiff delete:@"B"], [BDiff insert:@"2"], nil];
	[dmp diffCleanupSemantic:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"AB_AB"], [BDiff insert:@"1A2_1A2"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"The c"], [BDiff delete:@"ow and the c"], [BDiff equal:@"at."], nil];
	[dmp diffCleanupSemantic:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff equal:@"The "], [BDiff delete:@"cow and the "], [BDiff equal:@"cat."], nil];
	STAssertEqualObjects(diffs, expected, nil);
}

- (void)testDiffCleanupEfficiency {
	id expected;
	dmp.Diff_EditCost = 4;
	NSMutableArray *diffs = [NSMutableArray array];
	[dmp diffCleanupEfficiency:diffs];
	STAssertEqualObjects(diffs, [NSArray array], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff insert:@"12"], [BDiff equal:@"wxyz"], [BDiff delete:@"cd"], [BDiff insert:@"34"], nil];
	[dmp diffCleanupEfficiency:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff insert:@"12"], [BDiff equal:@"wxyz"], [BDiff delete:@"cd"], [BDiff insert:@"34"], nil];
	STAssertEqualObjects(diffs, expected, nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff insert:@"12"], [BDiff equal:@"xyz"], [BDiff delete:@"cd"], [BDiff insert:@"34"], nil];
	[dmp diffCleanupEfficiency:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abxyzcd"], [BDiff insert:@"12xyz34"], nil];
	STAssertEqualObjects(diffs, expected, nil);	

	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"12"], [BDiff equal:@"x"], [BDiff delete:@"cd"], [BDiff insert:@"34"], nil];
	[dmp diffCleanupEfficiency:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"xcd"], [BDiff insert:@"12x34"], nil];
	STAssertEqualObjects(diffs, expected, nil);	

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff insert:@"12"], [BDiff equal:@"xy"], [BDiff insert:@"34"], [BDiff equal:@"z"], [BDiff delete:@"cd"], [BDiff insert:@"56"],  nil];
	[dmp diffCleanupEfficiency:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abxyzcd"], [BDiff insert:@"12xy34z56"], nil];
	STAssertEqualObjects(diffs, expected, nil);	
	
	dmp.Diff_EditCost = 5;
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"ab"], [BDiff insert:@"12"], [BDiff equal:@"wxyz"], [BDiff delete:@"cd"], [BDiff insert:@"34"], nil];
	[dmp diffCleanupEfficiency:diffs];
	expected = [NSMutableArray arrayWithObjects:[BDiff delete:@"abwxyzcd"], [BDiff insert:@"12wxyz34"], nil];
	STAssertEqualObjects(diffs, expected, nil);	
}

- (void)testDiffPrettyHtml {
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a\n"], [BDiff delete:@"<B>b</B>"], [BDiff insert:@"c&d"], nil];
	STAssertEqualObjects(@"<SPAN TITLE=\"i=0\">a&para;<BR></SPAN><DEL STYLE=\"background:#FFE6E6;\" TITLE=\"i=2\">&lt;B&gt;b&lt;/B&gt;</DEL><INS STYLE=\"background:#E6FFE6;\" TITLE=\"i=2\">c&amp;d</INS>", [dmp diffPrettyHTML:diffs], nil);
}

- (void)testDiffText {
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"jump"], [BDiff delete:@"s"], [BDiff insert:@"ed"], [BDiff equal:@" over "], [BDiff delete:@"the"], [BDiff insert:@"a"], [BDiff equal:@" lazy"], nil];
	STAssertEqualObjects(@"jumps over the lazy", [dmp diffText1:diffs], nil);
	STAssertEqualObjects(@"jumped over a lazy", [dmp diffText2:diffs], nil);
}

- (void)testDiffDelta {
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"jump"], [BDiff delete:@"s"], [BDiff insert:@"ed"], [BDiff equal:@" over "], [BDiff delete:@"the"], [BDiff insert:@"a"], [BDiff equal:@" lazy"], [BDiff insert:@"old dog"], nil];
	NSString *text1 = [dmp diffText1:diffs];
	STAssertEqualObjects(@"jumps over the lazy", text1, nil);
	
	NSString *delta = [dmp diffToDelta:diffs];
	STAssertEqualObjects(@"=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta, nil);
	
	STAssertEqualObjects(diffs, [dmp diffFromDeltaText1:text1 delta:(NSString *)delta], nil);
	
	/*
	 // Generates error (19 < 20).
	 try {
	 dmp.diff_fromDelta(text1 + "x", delta);
	 fail("diff_fromDelta: Too long.");
	 } catch (IllegalArgumentException ex) {
	 // Exception expected.
	 }
	 
	 // Generates error (19 > 18).
	 try {
	 dmp.diff_fromDelta(text1.substring(1), delta);
	 fail("diff_fromDelta: Too short.");
	 } catch (IllegalArgumentException ex) {
	 // Exception expected.
	 }
	 
	 // Generates error (%c3%xy invalid Unicode).
	 try {
	 dmp.diff_fromDelta("", "+%c3%xy");
	 fail("diff_fromDelta: Invalid character.");
	 } catch (IllegalArgumentException ex) {
	 // Exception expected.
	 }
*/
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"\u0680 \000 \t %"], [BDiff delete:@"\u0681 \001 \n ^"], [BDiff insert:@"\u0682 \002 \\ |"], nil];
	text1 = [dmp diffText1:diffs];
	STAssertEqualObjects(@"\u0680 \000 \t %\u0681 \001 \n ^", text1, nil);
	
	delta = [dmp diffToDelta:diffs];
	STAssertEqualObjects(@"=7\t-7\t+%DA%82 %02 %5C %7C", delta, nil);

	STAssertEqualObjects(diffs, [dmp diffFromDeltaText1:text1 delta:delta], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # "], nil];
	NSString *text2 = [dmp diffText2:diffs];
	STAssertEqualObjects(@"A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", text2, nil);

	delta = [dmp diffToDelta:diffs];
	STAssertEqualObjects(@"+A-Z a-z 0-9 - _ . ! ~ * \' ( ) ; / ? : @ & = + $ , # ", delta, nil);

	STAssertEqualObjects(diffs, [dmp diffFromDeltaText1:@"" delta:delta], nil);
}

- (void)testDiffXIndex {
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"1234"], [BDiff equal:@"xyz"], nil];
	STAssertEquals(5, [dmp diffXIndex:diffs location:2], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"1234"], [BDiff equal:@"xyz"], nil];
	STAssertEquals(1, [dmp diffXIndex:diffs location:3], nil);
}

- (void)testDiffPath {
	STAssertTrue([dmp diffFootprintX:1 y:10] != [dmp diffFootprintX:10 y:1], nil);
	STAssertEqualObjects([dmp diffFootprintX:1 y:10], [dmp diffFootprintX:1 y:10], nil);

	NSMutableArray *vMap = [NSMutableArray array];
	NSMutableSet *rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:1]];
	[rowSet addObject:[dmp diffFootprintX:1 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:2]];
	[rowSet addObject:[dmp diffFootprintX:2 y:0]];
	[rowSet addObject:[dmp diffFootprintX:2 y:2]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:3]];
	[rowSet addObject:[dmp diffFootprintX:2 y:3]];
	[rowSet addObject:[dmp diffFootprintX:3 y:0]];
	[rowSet addObject:[dmp diffFootprintX:4 y:3]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:4]];
	[rowSet addObject:[dmp diffFootprintX:2 y:4]];
	[rowSet addObject:[dmp diffFootprintX:4 y:0]];
	[rowSet addObject:[dmp diffFootprintX:4 y:4]];
	[rowSet addObject:[dmp diffFootprintX:5 y:3]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:5]];
	[rowSet addObject:[dmp diffFootprintX:2 y:5]];
	[rowSet addObject:[dmp diffFootprintX:4 y:5]];
	[rowSet addObject:[dmp diffFootprintX:5 y:0]];
	[rowSet addObject:[dmp diffFootprintX:6 y:3]];
	[rowSet addObject:[dmp diffFootprintX:6 y:5]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:6]];
	[rowSet addObject:[dmp diffFootprintX:2 y:6]];
	[rowSet addObject:[dmp diffFootprintX:4 y:6]];
	[rowSet addObject:[dmp diffFootprintX:6 y:6]];
	[rowSet addObject:[dmp diffFootprintX:7 y:5]];
	[vMap addObject:rowSet];
	
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"W"], [BDiff delete:@"A"], [BDiff equal:@"1"], [BDiff delete:@"B"], [BDiff equal:@"2"], [BDiff insert:@"X"], [BDiff delete:@"C"], [BDiff equal:@"3"], [BDiff delete:@"D"], nil];
	STAssertEqualObjects(diffs, [dmp diffPath1:vMap text1:@"A1B2C3D" text2:@"W12X3"], nil);

	[vMap removeLastObject];
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"4"], [BDiff delete:@"E"], [BDiff insert:@"Y"], [BDiff equal:@"5"], [BDiff delete:@"F"], [BDiff equal:@"6"], [BDiff delete:@"G"], [BDiff insert:@"Z"], nil];
	STAssertEqualObjects(diffs, [dmp diffPath2:vMap text1:@"4E5F6G" text2:@"4Y56Z"], nil);
	
	vMap = [NSMutableArray array];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:1]];
	[rowSet addObject:[dmp diffFootprintX:1 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:2]];
	[rowSet addObject:[dmp diffFootprintX:1 y:1]];
	[rowSet addObject:[dmp diffFootprintX:2 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:3]];
	[rowSet addObject:[dmp diffFootprintX:1 y:2]];
	[rowSet addObject:[dmp diffFootprintX:2 y:1]];
	[rowSet addObject:[dmp diffFootprintX:3 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:4]];
	[rowSet addObject:[dmp diffFootprintX:1 y:3]];
	[rowSet addObject:[dmp diffFootprintX:3 y:1]];
	[rowSet addObject:[dmp diffFootprintX:4 y:0]];
	[rowSet addObject:[dmp diffFootprintX:4 y:4]];
	[vMap addObject:rowSet];
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"WX"], [BDiff delete:@"AB"], [BDiff equal:@"12"], nil];
	STAssertEqualObjects(diffs, [dmp diffPath1:vMap text1:@"AB12" text2:@"WX12"], nil);

	vMap = [NSMutableArray array];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:0 y:1]];
	[rowSet addObject:[dmp diffFootprintX:1 y:0]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:1 y:1]];
	[rowSet addObject:[dmp diffFootprintX:2 y:0]];
	[rowSet addObject:[dmp diffFootprintX:2 y:4]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:2 y:1]];
	[rowSet addObject:[dmp diffFootprintX:2 y:5]];
	[rowSet addObject:[dmp diffFootprintX:3 y:0]];
	[rowSet addObject:[dmp diffFootprintX:3 y:4]];
	[vMap addObject:rowSet];
	rowSet = [NSMutableSet set];
	[rowSet addObject:[dmp diffFootprintX:2 y:6]];
	[rowSet addObject:[dmp diffFootprintX:3 y:5]];
	[rowSet addObject:[dmp diffFootprintX:4 y:4]];
	[vMap addObject:rowSet];
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"CD"], [BDiff equal:@"34"], [BDiff insert:@"YZ"], nil];
	STAssertEqualObjects(diffs, [dmp diffPath2:vMap text1:@"CD34" text2:@"34YZ"], nil);
}

- (void)testDiffMain {
	NSMutableArray *diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"abc"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"abc" text2:@"abc"], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"ab"], [BDiff insert:@"123"], [BDiff equal:@"c"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"abc" text2:@"ab123c"], nil);
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"123"], [BDiff equal:@"bc"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"a123bc" text2:@"abc"], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff insert:@"123"], [BDiff equal:@"b"], [BDiff insert:@"456"], [BDiff equal:@"c"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"abc" text2:@"a123b456c"], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"a"], [BDiff delete:@"123"], [BDiff equal:@"b"], [BDiff delete:@"456"], [BDiff equal:@"c"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"a123b456c" text2:@"abc"], nil);
	
	dmp.Diff_Timeout = 0;
	dmp.Diff_DualThreshold = 32;
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"b"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"a" text2:@"b"], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"Apple"], [BDiff insert:@"Banana"], [BDiff equal:@"s are a"], [BDiff insert:@"lso"], [BDiff equal:@" fruit."], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"Apples are a fruit." text2:@"Bananas are also fruit."], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"a"], [BDiff insert:@"\u0680"], [BDiff equal:@"x"], [BDiff delete:@"\t"], [BDiff insert:@"\000"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"ax\t" text2:@"\u0680x\000"], nil);

	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"1"], [BDiff equal:@"a"], [BDiff delete:@"y"], [BDiff equal:@"b"], [BDiff delete:@"2"], [BDiff insert:@"xab"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"1ayb2" text2:@"abxab"], nil);	

	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"xaxcx"], [BDiff equal:@"abc"], [BDiff delete:@"y"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"abcy" text2:@"xaxcxabc"], nil);	

	dmp.Diff_DualThreshold = 2;
	diffs = [NSMutableArray arrayWithObjects:[BDiff insert:@"x"], [BDiff equal:@"a"], [BDiff delete:@"b"], [BDiff insert:@"x"], [BDiff equal:@"c"], [BDiff delete:@"y"], [BDiff insert:@"xabc"], nil];
	STAssertEqualObjects(diffs, [dmp diffMainText1:@"abcy" text2:@"xaxcxabc"], nil);
}

- (void)testMatchAlphabet {
	NSMutableDictionary *bitmask;
	bitmask = [NSMutableDictionary dictionary];
	[bitmask setObject:[NSNumber numberWithInteger:4] forKey:[NSNumber numberWithUnsignedChar:'a']];
	[bitmask setObject:[NSNumber numberWithInteger:2] forKey:[NSNumber numberWithUnsignedChar:'b']];
	[bitmask setObject:[NSNumber numberWithInteger:1] forKey:[NSNumber numberWithUnsignedChar:'c']];
	STAssertEqualObjects(bitmask, [dmp matchAlphabet:@"abc"], nil);
	bitmask = [NSMutableDictionary dictionary];
	[bitmask setObject:[NSNumber numberWithInteger:37] forKey:[NSNumber numberWithUnsignedChar:'a']];
	[bitmask setObject:[NSNumber numberWithInteger:18] forKey:[NSNumber numberWithUnsignedChar:'b']];
	[bitmask setObject:[NSNumber numberWithInteger:8] forKey:[NSNumber numberWithUnsignedChar:'c']];
	STAssertEqualObjects(bitmask, [dmp matchAlphabet:@"abcaba"], nil);	
}

- (void)testMatchBitmap {
	dmp.Match_Balance = 0.5;
	dmp.Match_Threshold = 0.5;
	dmp.Match_MinLength = 100;
	dmp.Match_MaxLength = 1000;

	STAssertEquals(5, [dmp matchBitap:@"abcdefghijk" pattern:@"fgh" loc:5], nil);
	STAssertEquals(5, [dmp matchBitap:@"abcdefghijk" pattern:@"fgh" loc:0], nil);
	STAssertEquals(4, [dmp matchBitap:@"abcdefghijk" pattern:@"efxhi" loc:0], nil);
	STAssertEquals(2, [dmp matchBitap:@"abcdefghijk" pattern:@"cdefxyhijk" loc:5], nil);
		
	STAssertEquals(-1, [dmp matchBitap:@"abcdefghijk" pattern:@"bxy" loc:1], nil);
	STAssertEquals(2, [dmp matchBitap:@"123456789xx0" pattern:@"3456789x0" loc:2], nil);

	dmp.Match_Threshold = 0.75;
	STAssertEquals(4, [dmp matchBitap:@"abcdefghijk" pattern:@"efxyhi" loc:1], nil);
	
	dmp.Match_Threshold = 0.1;
	STAssertEquals(1, [dmp matchBitap:@"abcdefghijk" pattern:@"bcdef" loc:1], nil);

	dmp.Match_Threshold = 0.5;
	STAssertEquals(0, [dmp matchBitap:@"abcdexyzabcde" pattern:@"abccde" loc:3], nil);
	STAssertEquals(8, [dmp matchBitap:@"abcdexyzabcde" pattern:@"abccde" loc:5], nil);

	dmp.Match_Balance = 0.6;
	STAssertEquals(-1, [dmp matchBitap:@"abcdefghijklmnopqrstuvwxyz" pattern:@"abcdefg" loc:24], nil);
	[dmp matchBitap:@"abcdefghijklmnopqrstuvwxyz" pattern:@"abcdefg" loc:24];
	
	STAssertEquals(0, [dmp matchBitap:@"abcdefghijklmnopqrstuvwxyz" pattern:@"abcxdxexfgh" loc:1], nil);

	dmp.Match_Balance = 0.4;
	STAssertEquals(0, [dmp matchBitap:@"abcdefghijklmnopqrstuvwxyz" pattern:@"abcdefg" loc:24], nil);
	STAssertEquals(-1, [dmp matchBitap:@"abcdefghijklmnopqrstuvwxyz" pattern:@"abcxdxexfgh" loc:1], nil);
}

- (void)testMatchMain {
	STAssertEquals(0, [dmp matchMain:@"abcdef" pattern:@"abcdef" loc:1000], nil);
	STAssertEquals(-1, [dmp matchMain:@"" pattern:@"abcdef" loc:1], nil);
	STAssertEquals(3, [dmp matchMain:@"abcdef" pattern:@"" loc:3], nil);
	STAssertEquals(3, [dmp matchMain:@"abcdef" pattern:@"de" loc:3], nil);

	dmp.Match_Threshold = 0.7;
	STAssertEquals(4, [dmp matchMain:@"I am the very model of a modern major general." pattern:@" that berry " loc:5], nil);
}

- (void)testPatchObj {
	BPatch *p = [[BPatch alloc] init];
	p.start1 = 20;
	p.start2 = 21;
	p.length1 = 18;
	p.length2 = 17;
	p.diffs = [NSMutableArray arrayWithObjects:[BDiff equal:@"jump"], [BDiff delete:@"s"], [BDiff insert:@"ed"], [BDiff equal:@" over "], [BDiff delete:@"the"], [BDiff insert:@"a"], [BDiff equal:@"\nlaz"], nil];
	NSString *strp = @"@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";
	STAssertEqualObjects(strp, [p description], nil);
}

- (void)testPatchFromText {
	STAssertTrue([[dmp patchFromText:@""] count] == 0, nil);
	
	NSString *strp = @"@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";
	STAssertEqualObjects(strp, [[[dmp patchFromText:strp] objectAtIndex:0] description], nil);
	STAssertEqualObjects(@"@@ -1 +1 @@\n-a\n+b\n", [[[dmp patchFromText:@"@@ -1 +1 @@\n-a\n+b\n"] objectAtIndex:0] description], nil);
	STAssertEqualObjects(@"@@ -1,3 +0,0 @@\n-abc\n", [[[dmp patchFromText:@"@@ -1,3 +0,0 @@\n-abc\n"] objectAtIndex:0] description], nil);
	STAssertEqualObjects(@"@@ -0,0 +1,3 @@\n+abc\n", [[[dmp patchFromText:@"@@ -0,0 +1,3 @@\n+abc\n"] objectAtIndex:0] description], nil);
	@try {
		[dmp patchFromText:@"Bad\nPatch\n"];
		STAssertFalse(YES, @"shouldn't get here, excpetion exptected.");
	} @catch (NSException * e) {
	}	
}

- (void)testPatchToText {
	NSString *strp = @"@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
	NSArray *patches = [dmp patchFromText:strp];
	STAssertEqualObjects(strp, [dmp patchToText:patches], nil);
	
	strp = @"@@ -1,9 +1,9 @@\n-f\n+F\n oo+fooba\n@@ -7,9 +7,9 @@\n obar\n-,\n+.\n  tes\n";
	patches = [dmp patchFromText:strp];
	STAssertEqualObjects(strp, [dmp patchToText:patches], nil);
}

- (void)testPatchAddContext {
	dmp.Patch_Margin = 4;
	BPatch *p;
	p = [[dmp patchFromText:@"@@ -21,4 +21,10 @@\n-jump\n+somersault\n"] objectAtIndex:0];
	[dmp patchAddContext:p text:@"The quick brown fox jumps over the lazy dog."];
	STAssertEqualObjects(@"@@ -17,12 +17,18 @@\n fox \n-jump\n+somersault\n s ov\n", [p description], nil);

	p = [[dmp patchFromText:@"@@ -21,4 +21,10 @@\n-jump\n+somersault\n"] objectAtIndex:0];
	[dmp patchAddContext:p text:@"The quick brown fox jumps."];
	STAssertEqualObjects(@"@@ -17,10 +17,16 @@\n fox \n-jump\n+somersault\n s.\n", [p description], nil);

	p = [[dmp patchFromText:@"@@ -3 +3,2 @@\n-e\n+at\n"] objectAtIndex:0];
	[dmp patchAddContext:p text:@"The quick brown fox jumps."];
	STAssertEqualObjects(@"@@ -1,7 +1,8 @@\n Th\n-e\n+at\n  qui\n", [p description], nil);
	p = [[dmp patchFromText:@"@@ -3 +3,2 @@\n-e\n+at\n"] objectAtIndex:0];
	[dmp patchAddContext:p text:@"The quick brown fox jumps.  The quick brown fox crashes."];
	STAssertEqualObjects(@"@@ -1,27 +1,28 @@\n Th\n-e\n+at\n  quick brown fox jumps. \n", [p description], nil);
}

- (void)testPatchMake {
	NSMutableArray *patches;
	NSString *text1 = @"The quick brown fox jumps over the lazy dog.";
	NSString *text2 = @"That quick brown fox jumped over a lazy dog.";
	NSMutableArray *diffs = [dmp diffMainText1:text1 text2:text2];
	
	NSString *expectedPatch = @"@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n";
	patches = [dmp patchMakeText1:text1 text2:text2];
	STAssertEqualObjects(expectedPatch, [dmp patchToText:patches], nil);
	
	patches = [dmp patchMakeDiffs:diffs];
	STAssertEqualObjects(expectedPatch, [dmp patchToText:patches], nil);	

	patches = [dmp patchMakeText1:text1 diffs:diffs];
	STAssertEqualObjects(expectedPatch, [dmp patchToText:patches], nil);	

	patches = [dmp patchMakeText1:@"`1234567890-=[]\\;',./" text2:@"~!@#$%^&*()_+{}|:\"<>?"];
	STAssertEqualObjects(@"@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n", [dmp patchToText:patches], nil);	
	
	diffs = [NSMutableArray arrayWithObjects:[BDiff delete:@"`1234567890-=[]\\;',./"], [BDiff insert:@"~!@#$%^&*()_+{}|:\"<>?"], nil];
	STAssertEqualObjects(diffs, [[[dmp patchFromText:@"@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n"] objectAtIndex:0] diffs], nil);
}

- (void)testPatchSplitMax {
	NSMutableArray *patches = [dmp patchMakeText1:@"abcdef1234567890123456789012345678901234567890123456789012345678901234567890uvwxyz" text2:@"abcdefuvwxyz"];
	[dmp patchSplitMax:patches];
	STAssertEqualObjects(@"@@ -3,32 +3,8 @@\n cdef\n-123456789012345678901234\n 5678\n@@ -27,32 +3,8 @@\n cdef\n-567890123456789012345678\n 9012\n@@ -51,30 +3,8 @@\n cdef\n-9012345678901234567890\n uvwx\n", [dmp patchToText:patches], nil);

	patches = [dmp patchMakeText1:@"1234567890123456789012345678901234567890123456789012345678901234567890" text2:@"abc"];
	[dmp patchSplitMax:patches];
	STAssertEqualObjects(@"@@ -1,32 +1,4 @@\n-1234567890123456789012345678\n 9012\n@@ -29,32 +1,4 @@\n-9012345678901234567890123456\n 7890\n@@ -57,14 +1,3 @@\n-78901234567890\n+abc\n", [dmp patchToText:patches], nil);

	patches = [dmp patchMakeText1:@"abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1" text2:@"abcdefghij , h : 1 , t : 1 abcdefghij , h : 1 , t : 1 abcdefghij , h : 0 , t : 1"];
	[dmp patchSplitMax:patches];
	STAssertEqualObjects(@"@@ -2,32 +2,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n@@ -29,32 +29,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n", [dmp patchToText:patches], nil);
}

- (void)testPatchAddPadding {
	NSMutableArray *patches = [dmp patchMakeText1:@"" text2:@"test"];
	STAssertEqualObjects(@"@@ -0,0 +1,4 @@\n+test\n", [dmp patchToText:patches], nil);
	[dmp patchAddPadding:patches];
	STAssertEqualObjects(@"@@ -1,8 +1,12 @@\n %00%01%02%03\n+test\n %00%01%02%03\n", [dmp patchToText:patches], nil);
	
	patches = [dmp patchMakeText1:@"XY" text2:@"XtestY"];
	STAssertEqualObjects(@"@@ -1,2 +1,6 @@\n X\n+test\n Y\n", [dmp patchToText:patches], nil);
	[dmp patchAddPadding:patches];
	STAssertEqualObjects(@"@@ -2,8 +2,12 @@\n %01%02%03X\n+test\n Y%00%01%02\n", [dmp patchToText:patches], nil);

	patches = [dmp patchMakeText1:@"XXXXYYYY" text2:@"XXXXtestYYYY"];
	STAssertEqualObjects(@"@@ -1,8 +1,12 @@\n XXXX\n+test\n YYYY\n", [dmp patchToText:patches], nil);
	[dmp patchAddPadding:patches];
	STAssertEqualObjects(@"@@ -5,8 +5,12 @@\n XXXX\n+test\n YYYY\n", [dmp patchToText:patches], nil);
}

- (void)testPatchApply {
	NSMutableArray *patches;
	patches = [dmp patchMakeText1:@"The quick brown fox jumps over the lazy dog." text2:@"That quick brown fox jumped over a lazy dog."];
	NSArray *results = [dmp patchApply:patches text:@"The quick brown fox jumps over the lazy dog."];
	NSArray *boolArray = [results objectAtIndex:1];
	NSString *resultStr = [NSString stringWithFormat:@"%@\t%i\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue], [[boolArray objectAtIndex:1] integerValue]];
	STAssertEqualObjects(@"That quick brown fox jumped over a lazy dog.\t1\t1", resultStr, nil);

	results = [dmp patchApply:patches text:@"The quick red rabbit jumps over the tired tiger."];
	boolArray = [results objectAtIndex:1];
	resultStr = [NSString stringWithFormat:@"%@\t%i\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue], [[boolArray objectAtIndex:1] integerValue]];
	STAssertEqualObjects(@"That quick red rabbit jumped over a tired tiger.\t1\t1", resultStr, nil);
	
	results = [dmp patchApply:patches text:@"I am the very model of a modern major general."];
	boolArray = [results objectAtIndex:1];
	resultStr = [NSString stringWithFormat:@"%@\t%i\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue], [[boolArray objectAtIndex:1] integerValue]];
	STAssertEqualObjects(@"I am the very model of a modern major general.\t0\t0", resultStr, nil);
	
	patches = [dmp patchMakeText1:@"" text2:@"test"];
	NSString *patchStr = [dmp patchToText:patches];
	[dmp patchApply:patches text:@""];
	STAssertEqualObjects(patchStr, [dmp patchToText:patches], nil);

	patches = [dmp patchMakeText1:@"The quick brown fox jumps over the lazy dog." text2:@"Woof"];
	NSString *patchStr = [dmp patchToText:patches];
	[dmp patchApply:patches text:@"The quick brown fox jumps over the lazy dog."];
	STAssertEqualObjects(patchStr, [dmp patchToText:patches], nil);
		
	patches = [dmp patchMakeText1:@"" text2:@"test"];
	results = [dmp patchApply:patches text:@""];
	boolArray = [results objectAtIndex:1];
	resultStr = [NSString stringWithFormat:@"%@\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue]];
	STAssertEqualObjects(@"test\t1", resultStr, nil);
	
	patches = [dmp patchMakeText1:@"XY" text2:@"XtestY"];
	results = [dmp patchApply:patches text:@"XY"];
	boolArray = [results objectAtIndex:1];
	resultStr = [NSString stringWithFormat:@"%@\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue]];
	STAssertEqualObjects(@"XtestY\t1", resultStr, nil);	
	
	patches = [dmp patchMakeText1:@"y" text2:@"y123"];
	results = [dmp patchApply:patches text:@"x"];
	boolArray = [results objectAtIndex:1];
	resultStr = [NSString stringWithFormat:@"%@\t%i", [results objectAtIndex:0], [[boolArray objectAtIndex:0] integerValue]];
	STAssertEqualObjects(@"x123\t1", resultStr, nil);
}

@end

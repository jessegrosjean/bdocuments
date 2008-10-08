//
//  BDocumentDiffMatchPatch.m
//  BDocuments
//
//  Created by Jesse Grosjean on 10/4/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import "BDocumentDiffMatchPatch.h"


@interface BDocumentDiffMatchPatch (BDocumentsPrivate)
- (NSMutableArray *)diffComputeText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffMapText1:(NSString *)text1 text2:(NSString *)text2;
- (NSArray *)diffHalfMatchText1:(NSString *)text1 text2:(NSString *)text2;
- (NSArray *)diffHalfMatch1LongText:(NSString *)longText shortText:(NSString *)shortText i:(NSInteger)i;
- (NSInteger)diffFootprintX:(NSInteger)x y:(NSInteger)y;
- (NSInteger)diffCommonPrefixText1:(NSString *)text1 text2:(NSString *)text2;
- (NSInteger)diffCommonSuffixText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffPath1:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffPath2:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2;
@end

@implementation BDocumentDiffMatchPatch

- (id)init {
	self = [super init];
	Diff_Timeout = 1.0f;
	Diff_EditCost = 4;
	Diff_DualThreshold = 32;
	Match_Balance = 0.5f;
	Match_Threshold = 0.5f;
	Match_MinLength = 100;
	Match_MaxLength = 1000;
	Patch_Margin = 4;
	Match_MaxBits = 32;
	return self;
}

// XXXXX substringWithRange is all wrong because range expects length as second argument

- (NSMutableArray *)diffMainText1:(NSString *)text1 text2:(NSString *)text2 {	
	if ([text1 isEqualToString:text2]) {
		return [NSArray arrayWithObject:[BDocumentDiff equalDiffWithText:text1]];
	}
	
	NSInteger commonLength = [self diffCommonPrefixText1:text1 text2:text2];
	NSString *commonPrefix = [text1 substringToIndex:commonLength];
	text1 = [text1 substringFromIndex:commonLength];
	text2 = [text2 substringFromIndex:commonLength];

	commonLength = [self diffCommonSuffixText1:text1 text2:text2];
	NSString *commonSuffix = [text1 substringFromIndex:[text1 length] - commonLength];
	text1 = [text1 substringToIndex:[text1 length] - commonLength];
	text2 = [text2 substringToIndex:[text2 length] - commonLength];
	
	NSMutableArray *diffs = [self diffComputeText1:text1 text2:text2];
	if ([commonPrefix length] > 0) [diffs insertObject:[BDocumentDiff equalDiffWithText:commonPrefix] atIndex:0];
	if ([commonSuffix length] > 0) [diffs addObject:[BDocumentDiff equalDiffWithText:commonSuffix]];		
	[self diffCleanupMerge:diffs];
	
	return diffs;
}

- (NSMutableArray *)diffComputeText1:(NSString *)text1 text2:(NSString *)text2 {
	if ([text1 length] == 0) return [NSMutableArray arrayWithObject:[BDocumentDiff insertDiffWithText:text2]];
	if ([text2 length] == 0) return [NSMutableArray arrayWithObject:[BDocumentDiff deleteDiffWithText:text1]];

	NSMutableArray *diffs = [NSMutableArray array];
	NSString *longText = [text1 length] > [text2 length] ? text1 : text2;
	NSString *shortText = [text1 length] > [text2 length] ? text2 : text1;
	NSUInteger i = [longText rangeOfString:shortText].location;

	if (i != NSNotFound) {
		BDocumentDiffOperation op = [text1 length] > [text2 length] ? BDocumentDiffDelete : BDocumentDiffInsert;
		[diffs addObject:[BDocumentDiff diffWithOperationType:op text:[longText substringToIndex:i]]];
		[diffs addObject:[BDocumentDiff equalDiffWithText:shortText]];
		[diffs addObject:[BDocumentDiff diffWithOperationType:op text:[longText substringFromIndex:i + [shortText length]]]];
		return diffs;
	}
	
	longText = shortText = nil;
	
	NSArray *hm = [self diffHalfMatchText1:text1 text2:text2];
	if (hm) {
		NSString *text1A = [hm objectAtIndex:0];
		NSString *text1B = [hm objectAtIndex:1];
		NSString *text2A = [hm objectAtIndex:2];
		NSString *text2B = [hm objectAtIndex:3];
		NSString *midCommon = [hm objectAtIndex:4];
		NSMutableArray *diffsA = [self diffMainText1:text1A text2:text2A];
		NSMutableArray *diffsB = [self diffMainText1:text1B text2:text2B];
		diffs = diffsA;
		[diffs addObject:[BDocumentDiff equalDiffWithText:midCommon]];
		[diffs addObjectsFromArray:diffsB];
		return diffs;
	}

    diffs = [self diffMapText1:text1 text2:text2];
	
    if (!diffs) {
		diffs = [NSMutableArray arrayWithCapacity:2];
		[diffs addObject:[BDocumentDiff deleteDiffWithText:text1]];
		[diffs addObject:[BDocumentDiff insertDiffWithText:text2]];
    }
	
    return diffs;
}

- (NSMutableArray *)diffMapText1:(NSString *)text1 text2:(NSString *)text2 {
	NSUInteger maxD = [text1 length] + [text2 length];
	BOOL doubleEnd = Diff_DualThreshold * 2 < maxD;
	NSMutableArray *vMap1 = [NSMutableArray array];
	NSMutableArray *vMap2 = [NSMutableArray array];
	NSMapTable *v1 = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSIntegerMapValueCallBacks, 32);
	NSMapTable *v2 = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSIntegerMapValueCallBacks, 32);
	NSMapInsert(v1, (const void*)1, (const void*)0);
	NSMapInsert(v2, (const void*)1, (const void*)0);
	NSInteger x, y;
	NSInteger footstep = 0;
	NSMapTable *footsteps = NSCreateMapTable(NSIntegerMapKeyCallBacks, NSIntegerMapValueCallBacks, 32);
	BOOL done = NO;
	BOOL front = (([text1 length] + [text2 length]) % 2 == 1);
	for (NSUInteger d = 0; d < maxD; d++) {
		[vMap1 addObject:NSCreateHashTable(NSIntegerHashCallBacks, 32)];
		for (NSUInteger k = -d; k <= d; k += 2) {
			if (k == -d || k != d && NSMapGet(v1, (const void*)k - 1) < NSMapGet(v1, (const void*)k + 1)) {
				x = (NSInteger) NSMapGet(v1, (const void*)k + 1);
			} else {
				x = (NSInteger) NSMapGet(v1, (const void*)k - 1) + 1;
			}
			y = x - k;
			if (doubleEnd) {
				footstep = [self diffFootprintX:x y:y];
				if (front && (NSMapGet(footsteps, (const void*)footstep) != NULL)) {
					done = YES;
				}
				if (!front) {
					NSMapInsert(footsteps, (const void*)footstep, (const void*)d);
				}
			}
			while (!done && x < [text1 length] && y < [text2 length] && [text1 characterAtIndex:x] == [text2 characterAtIndex:y]) {
				x++;
				y++;
				if (doubleEnd) {
					footstep = [self diffFootprintX:x y:y];
					if (front && (NSMapGet(footsteps, (const void*)footstep) != NULL)) {
						done = YES;
					}
					if (!front) {
						NSMapInsert(footsteps, (const void*)footstep, (const void*)d);
					}
				}
			}
			NSMapInsert(v1, (const void*)k, (const void*)x);
			NSHashInsert([vMap1 objectAtIndex:d], (const void*)[self diffFootprintX:x y:y]);
			if (x == [text1 length] && y == [text2 length]) {
				return [self diffPath1:vMap1 text1:text1 text2:text2];
			} else if (done) {
				vMap2 = [[[vMap2 subarrayWithRange:NSMakeRange(0, (NSInteger) NSMapGet(footsteps, (const void*)footstep) + 1)] mutableCopy] autorelease];
				NSMutableArray *a = [self diffPath1:vMap1 text1:[text1 substringToIndex:x] text2:[text2 substringToIndex:y]];
				[a addObjectsFromArray:[self diffPath2:vMap2 text1:[text1 substringFromIndex:x] text2:[text2 substringFromIndex:y]]];
				return a;
			}			
		}
		
		if (doubleEnd) {
			[vMap2 addObject:NSCreateHashTable(NSIntegerHashCallBacks, 32)];
			for (NSUInteger k = -d; k <= d; k += 2) {
				if (k == -d || k != d && NSMapGet(v2, (const void*)k - 1) < NSMapGet(v2, (const void*)k + 1)) {
					x = (NSInteger) NSMapGet(v2, (const void*)k + 1);
				} else {
					x = (NSInteger) NSMapGet(v2, (const void*)k - 1) + 1;
				}
				y = x - k;
				footstep = [self diffFootprintX:[text1 length] - x y:[text2 length] - y];
				if (front && (NSMapGet(footsteps, (const void*)footstep) != NULL)) {
					done = YES;
				}
				if (front) {
					NSMapInsert(footsteps, (const void*)footstep, (const void*)d);
				}
				while (!done && x < [text1 length] && y < [text2 length] && [text1 characterAtIndex:[text1 length] - x - 1] == [text2 characterAtIndex:[text2 length] - y - 1]) {
					x++;
					y++;
					footstep = [self diffFootprintX:[text1 length] - x y:[text2 length] - y];
					if (front && (NSMapGet(footsteps, (const void*)footstep) != NULL)) {
						done = YES;
					}
					if (front) {
						NSMapInsert(footsteps, (const void*)footstep, (const void*)d);
					}
				}
				NSMapInsert(v2, (const void*)k, (const void*)x);
				NSHashInsert([vMap2 objectAtIndex:d], (const void*)[self diffFootprintX:x y:y]);
				if (done) {
					vMap1 = [[[vMap1 subarrayWithRange:NSMakeRange(0, (NSInteger) NSMapGet(footsteps, (const void*)footstep) + 1)] mutableCopy] autorelease];
					NSMutableArray *a = [self diffPath1:vMap1 text1:[text1 substringToIndex:[text1 length] - x] text2:[text2 substringToIndex:[text2 length] - y]];
					[a addObjectsFromArray:[self diffPath2:vMap2 text1:[text1 substringFromIndex:[text1 length] - x] text2:[text2 substringFromIndex:[text2 length] - y]]];
					return a;
				}
			}
		}
	}
	return nil;
}

- (NSMutableArray *)diffPath1:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2 {
	NSMutableArray *path = [NSMutableArray array];
	NSUInteger x = [text1 length];
	NSUInteger y = [text2 length];
	BDocumentDiffOperation lastOp = 0;
	for (NSUInteger d = [vMap count] - 2; d >= 0; d--) {
		while (YES) {
			if (NSHashGet([vMap objectAtIndex:d], (const void*)[self diffFootprintX:x - 1 y:y]) != NULL) {
				x--;
				if (lastOp == BDocumentDiffDelete) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text1 characterAtIndex:x], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDocumentDiff deleteDiffWithText:[text1 substringWithRange:NSMakeRange(x, x + 1)]] atIndex:0];
				}
				lastOp = BDocumentDiffDelete;
				break;
			} else if (NSHashGet([vMap objectAtIndex:d], (const void*)[self diffFootprintX:x y:y - 1]) != NULL) {
				y--;
				if (lastOp == BDocumentDiffInsert) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text2 characterAtIndex:y], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDocumentDiff insertDiffWithText:[text2 substringWithRange:NSMakeRange(y, y + 1)]] atIndex:0];
				}
				lastOp = BDocumentDiffInsert;
				break;
			} else {
				x--;
				y--;
				if (lastOp == BDocumentDiffEqual) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text1 characterAtIndex:x], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDocumentDiff equalDiffWithText:[text1 substringWithRange:NSMakeRange(x, x + 1)]] atIndex:0];
				}
				lastOp = BDocumentDiffEqual;
			}
		}
	}
	return path;
}

- (NSMutableArray *)diffPath2:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2 {
	NSMutableArray *path = [NSMutableArray array];
	NSUInteger x = [text1 length];
	NSUInteger y = [text2 length];
	BDocumentDiffOperation lastOp = 0;
	for (NSUInteger d = [vMap count] - 2; d >= 0; d--) {
		while (YES) {
			if (NSHashGet([vMap objectAtIndex:d], (const void*)[self diffFootprintX:x - 1 y:y]) != NULL) {
				x--;
				if (lastOp == BDocumentDiffDelete) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path lastObject] text], [text1 characterAtIndex:[text1 length] - x - 1]]];
				} else {
					[path addObject:[BDocumentDiff deleteDiffWithText:[text1 substringWithRange:NSMakeRange([text1 length] - x - 1, [text1 length] - x)]]];
				}
				lastOp = BDocumentDiffDelete;
				break;
			} else if (NSHashGet([vMap objectAtIndex:d], (const void*)[self diffFootprintX:x y:y - 1]) != NULL) {
				y--;
				if (lastOp == BDocumentDiffInsert) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path lastObject] text], [text2 characterAtIndex:[text2 length] - y - 1]]];
				} else {
					[path addObject:[BDocumentDiff insertDiffWithText:[text2 substringWithRange:NSMakeRange([text2 length] - y - 1, [text2 length] - y)]]];
				}
				lastOp = BDocumentDiffInsert;
				break;
			} else {
				x--;
				y--;
				if (lastOp == BDocumentDiffEqual) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path objectAtIndex:0] text], [text1 characterAtIndex:[text1 length] - x - 1]]];
				} else {
					[path addObject:[BDocumentDiff equalDiffWithText:[text1 substringWithRange:NSMakeRange([text1 length] - x - 1, [text1 length] - x)]]];
				}
				lastOp = BDocumentDiffEqual;
			}
		}
	}
	return path;
}

- (NSInteger)diffFootprintX:(NSInteger)x y:(NSInteger)y {
	// should find out size of NSInteger. Assert that both x and y are less then half integer size. and then shift half size.
	NSInteger result = x;
	result = (result << 32); // XXX not right!!!
	result += y;
	return result;
}

- (NSInteger)diffCommonPrefixText1:(NSString *)text1 text2:(NSString *)text2 {
	NSInteger n = MIN([text1 length], [text2 length]);
	for (NSInteger i = 0; i < n; i++) {
		if ([text1 characterAtIndex:i] != [text2 characterAtIndex:i]) {
			return i;
		}
	}
	return n;
}

- (NSInteger)diffCommonSuffixText1:(NSString *)text1 text2:(NSString *)text2 {
	NSInteger l1 = [text1 length];
	NSInteger l2 = [text2 length];
	NSInteger n = MIN(l1, l2);
	for (NSInteger i = 0; i < n; i++) {
		if ([text1 characterAtIndex:l1 - i - 1] != [text2 characterAtIndex:l2 - i - 1]) {
			return i;
		}
	}
	return n;
}

- (NSArray *)diffHalfMatchText1:(NSString *)text1 text2:(NSString *)text2 {
	NSInteger l1 = [text1 length];
	NSInteger l2 = [text2 length];
	NSString *longText = l1 > l2 ? text1 : text2;
	NSString *shortText = l1 > l2 ? text2 : text1;
	if ([longText length] < 10 || [shortText length] < 1) {
		return nil;
	}
	
	NSArray *hm1 = [self diffHalfMatch1LongText:longText shortText:shortText i:([longText length] + 1) / 4];
	NSArray *hm2 = [self diffHalfMatch1LongText:longText shortText:shortText i:([longText length] + 1) / 2];
	NSArray *hm = nil;

	if (hm1 == nil && hm2 == nil) {
		return nil;
	} else if (hm2 == nil) {
		hm = hm1;
	} else if (hm1 == nil) {
		hm = hm2;
	} else {
		hm = [[hm1 objectAtIndex:4] length] > [[hm2 objectAtIndex:4] length] ? hm1 : hm2;
	}
	
	if (l1 > l2) {
		return hm;
	} else {
		return [NSArray arrayWithObjects:[hm objectAtIndex:2], [hm objectAtIndex:3], [hm objectAtIndex:0], [hm objectAtIndex:1], [hm objectAtIndex:4], nil];
	}
	
	return nil;
}

- (NSArray *)diffHalfMatch1LongText:(NSString *)longText shortText:(NSString *)shortText i:(NSInteger)i {
	NSString *seed = [longText substringWithRange:NSMakeRange(i, i + (NSInteger) floor([longText length] / 4))];
	NSInteger j = -1;
	NSString *bestCommon = @"";
	NSString *bestLongTextA = @"";
	NSString *bestLongTextB = @"";
	NSString *bestShortTextA = @"";
	NSString *bestShortTextB = @"";
//	while (j = [shortText rangeOfString:seed options:NSLiteralSearch range:NSMakeRange(j + 1, [shortText length] - (j + 1))] != NSNotFound) {
//		NSInteger prefixLength = [self diffCommonPrefixText1: text2:]; working...
//	}
	return nil;
}

- (void)diffCleanupMerge:(NSMutableArray *)diffs {	
}

@end

@implementation BDocumentDiff

+ (id)equalDiffWithText:(NSString *)text {
	return nil;
}

+ (id)insertDiffWithText:(NSString *)text {
	return nil;
}

+ (id)deleteDiffWithText:(NSString *)text {
	return nil;
}

+ (id)diffWithOperationType:(BDocumentDiffOperation)operation text:(NSString *)text {
	return nil;
}

@synthesize text;

@end

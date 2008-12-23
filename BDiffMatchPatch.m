//
//  BDiffMatchPatch.m
//  BDocuments
//
//  Created by Jesse Grosjean on 10/4/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import "BDiffMatchPatch.h"

@interface NSString (BDocumentsPrivate)

- (NSInteger)JindexOf:(NSString *)aString;
- (NSInteger)JindexOf:(NSString *)aString :(NSUInteger)fromIndex;
- (NSInteger)JlastIndexOf:(NSString *)aString;
- (NSInteger)JlastIndexOf:(NSString *)aString :(NSUInteger)fromIndex;
- (NSString *)Jsubstring:(NSInteger)beginIndex;
- (NSString *)Jsubstring:(NSInteger)beginIndex :(NSInteger)endIndex;
- (NSString *)URLEncode;
- (NSString *)URLDecode;

@end

@interface NSMutableString (BDocumentsPrivate)

- (void)unescapeForEncodeUriCompatability;

@end

@interface NSMutableArray (BDocumentsPrivate)

- (NSMutableArray *)JsubList:(NSInteger)fromIndex :(NSInteger)toIndex;

@end

@interface BArrayIterator : NSObject {
	NSMutableArray *array;
	NSInteger cursor;
	NSInteger lastRet;
}

- (id)initWithArray:(NSMutableArray *)anArray;

- (BOOL)hasNext;
- (BOOL)hasPrevious;
- (id)next;
- (id)previous;
- (void)set:(id)object;
- (void)add:(id)object;
- (void)remove;

@end

@implementation BDiffMatchPatch

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

@synthesize Diff_Timeout;
@synthesize Diff_EditCost;
@synthesize Diff_DualThreshold;
@synthesize Match_Balance;
@synthesize Match_Threshold;
@synthesize Match_MinLength;
@synthesize Match_MaxLength;
@synthesize Patch_Margin;
@synthesize Match_MaxBits;

- (NSMutableArray *)diffMainText1:(NSString *)text1 text2:(NSString *)text2 {	
	if ([text1 isEqualToString:text2]) {
		return [NSArray arrayWithObject:[BDiff equal:text1]];
	}
	
	NSInteger commonLength = [self diffCommonPrefixText1:text1 text2:text2];
	NSString *commonPrefix = [text1 Jsubstring:0 :commonLength];
	text1 = [text1 Jsubstring:commonLength];
	text2 = [text2 Jsubstring:commonLength];

	commonLength = [self diffCommonSuffixText1:text1 text2:text2];
	NSString *commonSuffix = [text1 Jsubstring:[text1 length] - commonLength];
	text1 = [text1 Jsubstring:0 :[text1 length] - commonLength];
	text2 = [text2 Jsubstring:0 :[text2 length] - commonLength];
	
	NSMutableArray *diffs = [self diffComputeText1:text1 text2:text2];
	
	if ([commonPrefix length] > 0) [diffs insertObject:[BDiff equal:commonPrefix] atIndex:0];
	if ([commonSuffix length] > 0) [diffs addObject:[BDiff equal:commonSuffix]];		

	[self diffCleanupMerge:diffs];
	
	return diffs;
}

- (NSMutableArray *)diffComputeText1:(NSString *)text1 text2:(NSString *)text2 {
	if ([text1 length] == 0) return [NSMutableArray arrayWithObject:[BDiff insert:text2]];
	if ([text2 length] == 0) return [NSMutableArray arrayWithObject:[BDiff delete:text1]];

	NSMutableArray *diffs = [NSMutableArray array];
	NSString *longText = [text1 length] > [text2 length] ? text1 : text2;
	NSString *shortText = [text1 length] > [text2 length] ? text2 : text1;
	NSUInteger i = [longText rangeOfString:shortText].location;

	if (i != NSNotFound) {
		BDiffOperation op = [text1 length] > [text2 length] ? BDiffDelete : BDiffInsert;
		[diffs addObject:[BDiff diffWithOperationType:op text:[longText Jsubstring:0 :i]]];
		[diffs addObject:[BDiff equal:shortText]];
		[diffs addObject:[BDiff diffWithOperationType:op text:[longText Jsubstring:i + [shortText length]]]];
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
		[diffs addObject:[BDiff equal:midCommon]];
		[diffs addObjectsFromArray:diffsB];
		return diffs;
	}

    diffs = [self diffMapText1:text1 text2:text2];
	
    if (!diffs) {
		diffs = [NSMutableArray arrayWithObjects:
				 [BDiff delete:text1],
				 [BDiff insert:text2],
				 nil];
    }
	
    return diffs;
}

- (NSMutableArray *)diffMapText1:(NSString *)text1 text2:(NSString *)text2 {
	NSTimeInterval timeEnd = [NSDate timeIntervalSinceReferenceDate] + Diff_Timeout;
	NSInteger maxD = [text1 length] + [text2 length] - 1;
	BOOL doubleEnd = Diff_DualThreshold * 2 < maxD;
	NSMutableArray *vMap1 = [NSMutableArray array];
	NSMutableArray *vMap2 = [NSMutableArray array];
	NSMutableDictionary *v1 = [NSMutableDictionary dictionary];
	NSMutableDictionary *v2 = [NSMutableDictionary dictionary];
	[v1 setObject:[NSNumber numberWithInteger:1] forKey:[NSNumber numberWithInteger:0]];
	[v2 setObject:[NSNumber numberWithInteger:1] forKey:[NSNumber numberWithInteger:0]];
	NSInteger x, y;
	NSNumber *footstep = nil;
	NSMutableDictionary *footsteps = [NSMutableDictionary dictionary];
	BOOL done = NO;
	BOOL front = (([text1 length] + [text2 length]) % 2 == 1);
	for (NSInteger d = 0; d < maxD; d++) {
		if (Diff_Timeout > 0 && [NSDate timeIntervalSinceReferenceDate] > timeEnd) {
			return nil;
		}
		
		[vMap1 addObject:[NSMutableSet set]];
		for (NSInteger k = -d; k <= d; k += 2) {
			if (k == -d || k != d && [[v1 objectForKey:[NSNumber numberWithInteger:k - 1]] integerValue] < [[v1 objectForKey:[NSNumber numberWithInteger:k + 1]] integerValue]) {
				x = [[v1 objectForKey:[NSNumber numberWithInteger:k + 1]] integerValue];
			} else {
				x = [[v1 objectForKey:[NSNumber numberWithInteger:k - 1]] integerValue] + 1;
			}
			y = x - k;
			if (doubleEnd) {
				footstep = [self diffFootprintX:x y:y];
				if (front && ([footsteps objectForKey:footstep] != NULL)) {
					done = YES;
				}
				if (!front) {
					[footsteps setObject:[NSNumber numberWithInteger:d] forKey:footstep];
				}
			}
			while (!done && x < [text1 length] && y < [text2 length] && [text1 characterAtIndex:x] == [text2 characterAtIndex:y]) {
				x++;
				y++;
				if (doubleEnd) {
					footstep = [self diffFootprintX:x y:y];
					if (front && ([footsteps objectForKey:footstep] != NULL)) {
						done = YES;
					}
					if (!front) {
						[footsteps setObject:[NSNumber numberWithInteger:d] forKey:footstep];
					}
				}
			}

			[v1 setObject:[NSNumber numberWithInteger:x] forKey:[NSNumber numberWithInteger:k]];
			[[vMap1 objectAtIndex:d] addObject:[self diffFootprintX:x y:y]];			
			if (x == [text1 length] && y == [text2 length]) {
				return [self diffPath1:vMap1 text1:text1 text2:text2];
			} else if (done) {
				vMap2 = [vMap2 JsubList:0 : [[footsteps objectForKey:footstep] integerValue] + 1];
				NSMutableArray *a = [self diffPath1:vMap1 text1:[text1 Jsubstring:0 :x] text2:[text2 Jsubstring:0 :y]];
				[a addObjectsFromArray:[self diffPath2:vMap2 text1:[text1 Jsubstring:x] text2:[text2 Jsubstring:y]]];
				return a;
			}			
		}
		
		if (doubleEnd) {
			[vMap2 addObject:[NSMutableSet set]];
			for (NSInteger k = -d; k <= d; k += 2) {
				if (k == -d || k != d && [[v2 objectForKey:[NSNumber numberWithInteger:k - 1]] integerValue] < [[v2 objectForKey:[NSNumber numberWithInteger:k + 1]] integerValue]) {
					x = [[v2 objectForKey:[NSNumber numberWithInteger:k + 1]] integerValue];
				} else {
					x = [[v2 objectForKey:[NSNumber numberWithInteger:k - 1]] integerValue] + 1;
				}
				y = x - k;
				footstep = [self diffFootprintX:[text1 length] - x y:[text2 length] - y];
				if (front && ([footsteps objectForKey:footstep] != NULL)) {
					done = YES;
				}
				if (front) {
					[footsteps setObject:[NSNumber numberWithInteger:d] forKey:footstep];
				}
				while (!done && x < [text1 length] && y < [text2 length] && [text1 characterAtIndex:[text1 length] - x - 1] == [text2 characterAtIndex:[text2 length] - y - 1]) {
					x++;
					y++;
					footstep = [self diffFootprintX:[text1 length] - x y:[text2 length] - y];
					if (front && ([footsteps objectForKey:footstep] != NULL)) {
						done = YES;
					}
					if (front) {
						[footsteps setObject:[NSNumber numberWithInteger:d] forKey:footstep];
					}
				}

				[v2 setObject:[NSNumber numberWithInteger:x] forKey:[NSNumber numberWithInteger:k]];
				[[vMap2 objectAtIndex:d] addObject:[self diffFootprintX:x y:y]];			
				if (done) {
					vMap1 = [vMap1 JsubList:0 :[[footsteps objectForKey:footstep] integerValue] + 1];
					NSMutableArray *a = [self diffPath1:vMap1 text1:[text1 Jsubstring:0 :[text1 length] - x] text2:[text2 Jsubstring:0 :[text2 length] - y]];
					[a addObjectsFromArray:[self diffPath2:vMap2 text1:[text1 Jsubstring:[text1 length] - x] text2:[text2 Jsubstring:[text2 length] - y]]];
					return a;
				}
			}
		}
	}
	return nil;
}

- (NSMutableArray *)diffPath1:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2 {
	NSMutableArray *path = [NSMutableArray array];
	NSInteger x = [text1 length];
	NSInteger y = [text2 length];
	BDiffOperation lastOp = 0;
	for (NSInteger d = [vMap count] - 2; d >= 0; d--) {
		while (YES) {
			if ([[vMap objectAtIndex:d] containsObject:[self diffFootprintX:x - 1 y:y]]) {
				x--;
				if (lastOp == BDiffDelete) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text1 characterAtIndex:x], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDiff delete:[text1 Jsubstring:x :x + 1]] atIndex:0];
				}
				lastOp = BDiffDelete;
				break;
			} else if ([[vMap objectAtIndex:d] containsObject:[self diffFootprintX:x y:y - 1]]) {
				y--;
				if (lastOp == BDiffInsert) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text2 characterAtIndex:y], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDiff insert:[text2 Jsubstring:y :y + 1]] atIndex:0];
				}
				lastOp = BDiffInsert;
				break;
			} else {
				x--;
				y--;
				if (lastOp == BDiffEqual) {
					[[path objectAtIndex:0] setText:[NSString stringWithFormat:@"%C%@", [text1 characterAtIndex:x], [[path objectAtIndex:0] text]]];
				} else {
					[path insertObject:[BDiff equal:[text1 Jsubstring:x :x + 1]] atIndex:0];
				}
				lastOp = BDiffEqual;
			}
		}
	}
	return path;
}

- (NSMutableArray *)diffPath2:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2 {
	NSMutableArray *path = [NSMutableArray array];
	NSInteger x = [text1 length];
	NSInteger y = [text2 length];
	BDiffOperation lastOp = 0;
	for (NSInteger d = [vMap count] - 2; d >= 0; d--) {
		while (YES) {
			if ([[vMap objectAtIndex:d] containsObject:[self diffFootprintX:x - 1 y:y]]) {
				x--;
				if (lastOp == BDiffDelete) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path lastObject] text], [text1 characterAtIndex:[text1 length] - x - 1]]];
				} else {
					[path addObject:[BDiff delete:[text1 Jsubstring:[text1 length] - x - 1 :[text1 length] - x]]];
				}
				lastOp = BDiffDelete;
				break;
			} else if ([[vMap objectAtIndex:d] containsObject:[self diffFootprintX:x y:y - 1]]) {
				y--;
				if (lastOp == BDiffInsert) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path lastObject] text], [text2 characterAtIndex:[text2 length] - y - 1]]];
				} else {
					[path addObject:[BDiff insert:[text2 Jsubstring:[text2 length] - y - 1  :[text2 length] - y]]];
				}
				lastOp = BDiffInsert;
				break;
			} else {
				x--;
				y--;
				if (lastOp == BDiffEqual) {
					[[path lastObject] setText:[NSString stringWithFormat:@"%@%C", [[path lastObject] text], [text1 characterAtIndex:[text1 length] - x - 1]]];
				} else {
					[path addObject:[BDiff equal:[text1 Jsubstring:[text1 length] - x - 1 :[text1 length] - x]]];
				}
				lastOp = BDiffEqual;
			}
		}
	}
	return path;
}

- (NSNumber *)diffFootprintX:(NSInteger)x y:(NSInteger)y {
	long long result = x;
	result = (result << 32);
	result += y;
	return [NSNumber numberWithLongLong:result];
}
 
- (NSInteger)diffCommonPrefixText1:(NSString *)text1 text2:(NSString *)text2 {
	NSInteger temp1 = [text1 length];
	NSInteger temp2 = [text2 length];
	NSInteger n = MIN(temp1, temp2);
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
	
	NSArray *hm1 = [self diffHalfMatch1LongText:longText shortText:shortText i:([longText length] + 3) / 4];
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
	NSString *seed = [longText Jsubstring:i :i + (NSInteger) floor([longText length] / 4)];
	NSInteger j = -1;
	NSString *bestCommon = @"";
	NSString *bestLongTextA = @"";
	NSString *bestLongTextB = @"";
	NSString *bestShortTextA = @"";
	NSString *bestShortTextB = @"";
	while ((j = [shortText JindexOf:seed :j + 1]) != -1) {
		NSInteger prefixLength = [self diffCommonPrefixText1:[longText Jsubstring:i] text2:[shortText Jsubstring:j]];
		NSInteger suffixLength = [self diffCommonSuffixText1:[longText Jsubstring:0 :i] text2:[shortText Jsubstring:0 :j]];
		if ([bestCommon length] < suffixLength + prefixLength) {
			bestCommon = [[shortText Jsubstring:j - suffixLength :j] stringByAppendingString:[shortText Jsubstring:j : j + prefixLength]];
			bestLongTextA = [longText Jsubstring:0 :i - suffixLength];
			bestLongTextB = [longText Jsubstring:i + prefixLength];
			bestShortTextA = [shortText Jsubstring:0 :j - suffixLength];
			bestShortTextB = [shortText Jsubstring:j + prefixLength];
		}
	}
	if ([bestCommon length] >= [longText length] / 2) {
		return [NSArray arrayWithObjects:bestLongTextA, bestLongTextB, bestShortTextA, bestShortTextB, bestCommon, nil];
	} else {
		return nil;
	}
}

- (void)diffCleanupSemantic:(NSMutableArray *)diffs {
	if ([diffs count] == 0) return;

	BOOL changes = NO;
	NSMutableArray *equalities = [NSMutableArray array];
	NSString *lastEquality = nil;
	BArrayIterator *pointer = [[BArrayIterator alloc] initWithArray:diffs];
	NSInteger lengthChanges1 = 0;
	NSInteger lengthChanges2 = 0;
	BDiff *thisDiff = [pointer next];
	while (thisDiff) {
		if (thisDiff.operation == BDiffEqual) {
			[equalities addObject:thisDiff];
			lengthChanges1 = lengthChanges2;
			lengthChanges2 = 0;
			lastEquality = [thisDiff.text copy];
		} else {
			lengthChanges2 += [thisDiff.text length];
			if (lastEquality != nil && ([lastEquality length] <= lengthChanges1) && ([lastEquality length] <= lengthChanges2)) {
				while (thisDiff != [equalities lastObject]) {
					thisDiff = [pointer previous];
				}
				[pointer next];
				[pointer set:[BDiff delete:lastEquality]];
				[pointer add:[BDiff insert:lastEquality]];
				
				[equalities removeLastObject];				
				if ([equalities count] != 0) {
					[equalities removeLastObject];
				}				
				if ([equalities count] == 0) {
					while ([pointer hasPrevious]) {
						[pointer previous];
					}					
				} else {
					thisDiff = [equalities lastObject];
					while (thisDiff != [pointer previous]) {
						// empty
					}
				}
				
				lengthChanges1 = 0;
				lengthChanges2 = 0;
				lastEquality = nil;
				changes = YES;
			}
		}
		thisDiff = [pointer hasNext] ? [pointer next] : nil;
	}
	
	if (changes) {
		[self diffCleanupMerge:diffs];
	}
	[self diffCleanupSemanticLossless:diffs];
}

- (void)diffCleanupSemanticLossless:(NSMutableArray *)diffs {
	NSString *equality1 = nil;
	NSString *edit = nil;
	NSString *equality2 = nil;
	NSString *commonString = nil;
	NSInteger commonOffset = 0;
	NSInteger score = 0;
	NSInteger bestScore = 0;
	NSString *bestEquality1 = nil;
	NSString *bestEdit = nil;
	NSString *bestEquality2 = nil;
	BArrayIterator *pointer = [[BArrayIterator alloc] initWithArray:diffs];
	BDiff *prevDiff = [pointer hasNext] ? [pointer next] : nil;
	BDiff *thisDiff = [pointer hasNext] ? [pointer next] : nil;
	BDiff *nextDiff = [pointer hasNext] ? [pointer next] : nil;
	
	while (nextDiff) {
		if (prevDiff.operation == BDiffEqual && nextDiff.operation == BDiffEqual) {
			equality1 = [prevDiff.text copy];
			edit = [thisDiff.text copy];
			equality2 = [nextDiff.text copy];
			
			commonOffset = [self diffCommonSuffixText1:equality1 text2:edit];
			if (commonOffset != 0) {
				commonString = [edit Jsubstring:[edit length] - commonOffset];
				equality1 = [equality1 Jsubstring:0 :[equality1 length] - commonOffset];
				edit = [commonString stringByAppendingString:[edit Jsubstring:0 :[edit length] - commonOffset]];
				equality2 = [commonString stringByAppendingString:equality2];
			}
			
			bestEquality1 = equality1;
			bestEdit = edit;
			bestEquality2 = equality2;
			bestScore = [self diffCleanupSemanticScoreText1:equality1 text2:edit] + [self diffCleanupSemanticScoreText1:edit text2:equality2];
			while ([edit length] != 0 && [equality2 length] != 0 && [edit characterAtIndex:0] == [equality2 characterAtIndex:0]) {
				equality1 = [equality1 stringByAppendingFormat:@"%C", [edit characterAtIndex:0]];
				edit = [[edit Jsubstring:1] stringByAppendingFormat:@"%C", [equality2 characterAtIndex:0]];
				equality2 = [equality2 Jsubstring:1];
				score = [self diffCleanupSemanticScoreText1:equality1 text2:edit] + [self diffCleanupSemanticScoreText1:edit text2:equality2];
				if (score >= bestScore) {
					bestScore = score;
					bestEquality1 = equality1;
					bestEdit = edit;
					bestEquality2 = equality2;
				}
			}
			
			if (![prevDiff.text isEqualToString:bestEquality1]) {
				if ([bestEquality1 length] != 0) {
					prevDiff.text = bestEquality1;
				} else {
					[pointer previous];
					[pointer previous];
					[pointer previous];
					[pointer remove];
					[pointer next];
					[pointer next];
				}
				thisDiff.text = bestEdit;
				if ([bestEquality2 length] != 0) {
					nextDiff.text = bestEquality2;
				} else {
					[pointer remove];
					nextDiff = thisDiff;
					thisDiff = prevDiff;
				}
			}
		}
		prevDiff = thisDiff;
		thisDiff = nextDiff;
		nextDiff = [pointer hasNext] ? [pointer next] : nil;
	}
}

- (NSInteger)diffCleanupSemanticScoreText1:(NSString *)one text2:(NSString *)two {
	if ([one length] == 0 || [two length] == 0) return 5;	
	NSCharacterSet *letterOrDigit = [NSCharacterSet alphanumericCharacterSet];
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSCharacterSet *control = [NSCharacterSet controlCharacterSet];	
	NSInteger score = 0;	
	if (![letterOrDigit characterIsMember:[one characterAtIndex:[one length] - 1]] || 
		![letterOrDigit characterIsMember:[two characterAtIndex:0]]) {
		score++;
		if ([whitespace characterIsMember:[one characterAtIndex:[one length] - 1]] ||
			[whitespace characterIsMember:[two characterAtIndex:0]]) {
			score++;
			if ([control characterIsMember:[one characterAtIndex:[one length] - 1]] ||
				[control characterIsMember:[two characterAtIndex:0]]) {
				score++;
				if ([one rangeOfRegex:@"\\n\\r?\\n$"].location != NSNotFound || [two rangeOfRegex:@"^\\r?\\n\\r?\\n"].location != NSNotFound) {
					score++;
				}
			}
		}
	}
	return score;
}

- (void)diffCleanupEfficiency:(NSMutableArray *)diffs {
	if ([diffs count] == 0) return;
	
	BOOL changes = NO;
	NSMutableArray *equalities = [NSMutableArray array];
	NSString *lastEquality = nil;
	BArrayIterator *pointer = [[BArrayIterator alloc] initWithArray:diffs];
	BOOL preIns = NO;
	BOOL preDel = NO;
	BOOL postIns = NO;
	BOOL postDel = NO;
	BDiff *thisDiff = [pointer next];
	BDiff *safeDiff = thisDiff;
	while (thisDiff) {
		if (thisDiff.operation == BDiffEqual) {
			if ([thisDiff.text length] < Diff_EditCost && (postIns || postDel)) {
				[equalities addObject:thisDiff];
				preIns = postIns;
				preDel = postDel;
				lastEquality = [thisDiff.text copy];
			} else {
				[equalities removeAllObjects];
				lastEquality = nil;
				safeDiff = thisDiff;
			}
			postIns = postDel = NO;
		} else {
			if (thisDiff.operation == BDiffDelete) {
				postDel = YES;
			} else {
				postIns = YES;
			}
			
			if (lastEquality != nil
				&& ((preIns && preDel & postIns && postDel)
				|| (([lastEquality length] < Diff_EditCost / 2)
					&& ((preIns ? 1 : 0) + (preDel ? 1 : 0)
						+ (postIns ? 1 : 0) + (postDel ? 1 : 0)) == 3))) {
				while (thisDiff != [equalities lastObject]) {
					thisDiff = [pointer previous];
				}
				[pointer next];
				
				[pointer set:[BDiff delete:lastEquality]];
				thisDiff = [BDiff insert:lastEquality];
				[pointer add:thisDiff];
				[equalities removeLastObject];
				lastEquality = nil;
				if (preIns && preDel) {
					postIns = postDel = YES;
					[equalities removeAllObjects];
					safeDiff = thisDiff;
				} else {
					if ([equalities count] != 0) {
						[equalities removeLastObject];
					}
					if ([equalities count] == 0) {
						thisDiff = safeDiff;
					} else {
						thisDiff = [equalities lastObject];
					}
					while (thisDiff != [pointer previous]) {
						// empty
					}
					postIns = postDel = NO;
				}
				changes = YES;
			}
		}
		thisDiff = [pointer hasNext] ? [pointer next] : nil;
	}
	if (changes) {
		[self diffCleanupMerge:diffs];
	}
}

- (void)diffCleanupMerge:(NSMutableArray *)diffs {
	[diffs addObject:[BDiff equal:@""]];
	BArrayIterator *pointer = [[BArrayIterator alloc] initWithArray:diffs];
	NSInteger countDelete = 0;
	NSInteger countInsert = 0;
	NSMutableString *textDelete = [NSMutableString string];
	NSMutableString *textInsert = [NSMutableString string];
	BDiff *thisDiff = [pointer next];
	BDiff *prevEqual = nil;
	NSInteger commonLength;
	while (thisDiff) {
		switch (thisDiff.operation) {
			case BDiffInsert: {
				countInsert++;
				[textInsert appendString:thisDiff.text];
				prevEqual = nil;
				break;
			}
			case BDiffDelete: {
				countDelete++;
				[textDelete appendString:thisDiff.text];
				prevEqual = nil;
				break;
			}
			case BDiffEqual: {
				if (countDelete != 0 || countInsert != 0) {
					[pointer previous];
					while (countDelete-- > 0) {
						[pointer previous];
						[pointer remove];
					}
					while (countInsert-- > 0) {
						[pointer previous];
						[pointer remove];
					}
					if (countDelete != 0 && countInsert != 0) {
						commonLength = [self diffCommonPrefixText1:textInsert text2:textDelete];
						if (commonLength != 0) {
							if ([pointer hasPrevious]) {
								thisDiff = [pointer previous];
								[thisDiff.text appendString:[textInsert Jsubstring:0 :commonLength]];
								[pointer next];
							} else {
								[pointer add:[BDiff equal:[textInsert Jsubstring:0 :commonLength]]];
							}
							textInsert = [[textInsert Jsubstring:commonLength] mutableCopy];
							textDelete = [[textDelete Jsubstring:commonLength] mutableCopy];
						}
						commonLength = [self diffCommonSuffixText1:textInsert text2:textDelete];
						if (commonLength != 0) {
							thisDiff = [pointer next];
							[thisDiff.text insertString:[textInsert Jsubstring:[textInsert length] - commonLength] atIndex:0];
							textInsert = [[textInsert Jsubstring:0 :[textInsert length] - commonLength] mutableCopy];
							textDelete = [[textDelete Jsubstring:0 :[textDelete length] - commonLength] mutableCopy];
							[pointer previous];
						}
					}
					if ([textDelete length] != 0) {
						[pointer add:[BDiff delete:textDelete]];
					}
					if ([textInsert length] != 0) {
						[pointer add:[BDiff insert:textInsert]];
					}
					thisDiff = [pointer hasNext] ? [pointer next] : nil;
				} else if (prevEqual != nil) {
					[prevEqual.text appendString:thisDiff.text];
					[pointer remove];
					thisDiff = [pointer previous];
					[pointer next];
				}
				countInsert = 0;
				countDelete = 0;
				textDelete = [NSMutableString string];
				textInsert = [NSMutableString string];
				prevEqual = thisDiff;
				break;
			}
		}
		thisDiff = [pointer hasNext] ? [pointer next] : nil;
	}
	if ([[[diffs lastObject] text] length] == 0) {
		[diffs removeLastObject];
	}
	
	BOOL changes = NO;
	pointer = [[BArrayIterator alloc] initWithArray:diffs];
	BDiff *prevDiff = [pointer hasNext] ? [pointer next] : nil;
	thisDiff = [pointer hasNext] ? [pointer next] : nil;
	BDiff *nextDiff = [pointer hasNext] ? [pointer next] : nil;
	while (nextDiff != nil) {
		if (prevDiff.operation == BDiffEqual && nextDiff.operation == BDiffEqual) {
			if ([thisDiff.text hasSuffix:prevDiff.text]) {
				thisDiff.text = [NSString stringWithFormat:@"%@%@", prevDiff.text, [thisDiff.text Jsubstring:0 :[thisDiff.text length] - [prevDiff.text length]]];
				[nextDiff.text insertString:prevDiff.text atIndex:0];
				[pointer previous];
				[pointer previous];
				[pointer previous];
				[pointer remove];
				[pointer next];
				thisDiff = [pointer next];
				nextDiff = [pointer hasNext] ? [pointer next] : nil;
				changes = YES;
			} else if ([thisDiff.text hasPrefix:nextDiff.text]) {
				[prevDiff.text appendString:nextDiff.text];
				thisDiff.text = [NSString stringWithFormat:@"%@%@", [thisDiff.text Jsubstring:[nextDiff.text length]], nextDiff.text];
				[pointer remove];
				nextDiff = [pointer hasNext] ? [pointer next] : nil;
				changes = YES;
			}
		}
		prevDiff = thisDiff;
		thisDiff = nextDiff;
		nextDiff = [pointer hasNext] ? [pointer next] : nil;
	}
	if (changes) {
		[self diffCleanupMerge:diffs];
	}
}

- (NSInteger)diffXIndex:(NSArray *)diffs location:(NSInteger)location {
	NSInteger chars1 = 0;
	NSInteger chars2 = 0;
	NSInteger lastChars1 = 0;
	NSInteger lastChars2 = 0;
	BDiff *lastDiff = nil;
	for (BDiff *aDiff in diffs) {
		if (aDiff.operation != BDiffInsert) {
			chars1 += [aDiff.text length];
		}
		if (aDiff.operation != BDiffDelete) {
			chars2 += [aDiff.text length];
		}
		if (chars1 > location) {
			lastDiff = aDiff;
			break;
		}
		lastChars1 = chars1;
		lastChars2 = chars2;
	}
	if (lastDiff != nil && lastDiff.operation == BDiffDelete) {
		return lastChars2;
	}
	return lastChars2 + (location - lastChars1);
}

- (NSString *)diffPrettyHTML:(NSArray *)diffs {
	NSMutableString *html = [NSMutableString string];
	NSInteger i = 0;
	for (BDiff *aDiff in diffs) {
		NSMutableString *text = [aDiff.text mutableCopy];
		[text replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [text length])];
		[text replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [text length])];
		[text replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [text length])];
		[text replaceOccurrencesOfString:@"\n" withString:@"&para;<BR>" options:0 range:NSMakeRange(0, [text length])];
		
		switch (aDiff.operation) {
			case BDiffInsert:
				[html appendFormat:@"<INS STYLE=\"background:#E6FFE6;\" TITLE=\"i=%i\">%@</INS>", i, text];
				break;
			case BDiffDelete:
				[html appendFormat:@"<DEL STYLE=\"background:#FFE6E6;\" TITLE=\"i=%i\">%@</DEL>", i, text];
				break;
			case BDiffEqual:
				[html appendFormat:@"<SPAN TITLE=\"i=%i\">%@</SPAN>", i, text];
				break;
		}
		if (aDiff.operation != BDiffDelete) {
			i += [aDiff.text length];
		}
	}
	return html;
}

- (NSString *)diffText1:(NSArray *)diffs {
	NSMutableString *text = [NSMutableString string];
	for (BDiff *aDiff in diffs) {
		if (aDiff.operation != BDiffInsert) {
			[text appendString:aDiff.text];
		}
	}
	return text;
}

- (NSString *)diffText2:(NSArray *)diffs {
	NSMutableString *text = [NSMutableString string];
	for (BDiff *aDiff in diffs) {
		if (aDiff.operation != BDiffDelete) {
			[text appendString:aDiff.text];
		}
	}
	return text;
}

- (NSString *)diffToDelta:(NSArray *)diffs {
	NSMutableString *text = [NSMutableString string];
	for (BDiff *aDiff in diffs) {
		switch (aDiff.operation) {
			case BDiffInsert:
				[text appendString:@"+"];
				[text appendString:[[aDiff.text URLEncode] stringByReplacingOccurrencesOfString:@"+" withString:@" "]];
				[text appendString:@"\t"];
				break;
			case BDiffDelete:
				[text appendFormat:@"-%i\t", [aDiff.text length]];
				break;
			case BDiffEqual:
				[text appendFormat:@"=%i\t", [aDiff.text length]];
				break;
		}
	}
	NSMutableString *delta = text;
	if ([delta length] != 0) {
		[delta replaceCharactersInRange:NSMakeRange([delta length] - 1, 1) withString:@""];
		[delta unescapeForEncodeUriCompatability];
	}
	return delta;
}

- (NSMutableArray *)diffFromDeltaText1:(NSString *)text1 delta:(NSString *)delta {
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	NSMutableArray *diffs = [NSMutableArray array];
	int pointer = 0;
	for (NSString *token in [delta componentsSeparatedByString:@"\t"]) {
		if ([token length] == 0) {
			continue;
		}
		NSString *param = [token Jsubstring:1];
		switch ([token characterAtIndex:0]) {
			case '+':
				param = [param stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
				param = [param URLDecode];
				[diffs addObject:[BDiff insert:param]];
				break;
			case '-':
				// Fall through
			case '=': {
				NSInteger n = [[numberFormatter numberFromString:param] integerValue];
				NSString *text = [text1 Jsubstring:pointer :pointer + n];
				pointer += n;
				if ([token characterAtIndex:0] == '=') {
					[diffs addObject:[BDiff equal:text]];
				} else {
					[diffs addObject:[BDiff delete:text]];
				}
				break;
			}
			default:
			[NSException raise:@"BAD!" format:@""];
		}
	}
	return diffs;
}


- (NSInteger)matchMain:(NSString *)text pattern:(NSString *)pattern loc:(NSInteger)loc {
	NSInteger temp = [text length] - [pattern length];
	loc = MAX(0, MIN(loc, temp));
	if ([text isEqualToString:pattern]) {
		return 0;
	} else if ([text length] == 0) {
		return -1;
	} else if ([[text Jsubstring:loc :loc + [pattern length]] isEqualToString:pattern]) {
		return loc;
	} else {
		return [self matchBitap:text pattern:pattern loc:loc];
	}
}

- (NSInteger)matchBitap:(NSString *)text pattern:(NSString *)pattern loc:(NSInteger)loc {
	NSDictionary *s = [self matchAlphabet:pattern];
	NSInteger scoreTextLength = [text length];
	scoreTextLength = MAX(scoreTextLength, Match_MinLength);
	scoreTextLength = MIN(scoreTextLength, Match_MaxLength);
	double scoreThreshold = Match_Threshold;
	NSInteger bestLoc = [text JindexOf:pattern :loc];
	if (bestLoc != -1) {
		double score = [self matchBitapScore:0 x:bestLoc loc:loc scoreTextLength:scoreTextLength pattern:pattern];
		scoreThreshold = MIN(score, scoreThreshold); 
	}
	bestLoc  = [text JlastIndexOf:pattern :loc + [pattern length]];
	if (bestLoc != -1) {
		double score = [self matchBitapScore:0 x:bestLoc loc:loc scoreTextLength:scoreTextLength pattern:pattern];
		scoreThreshold = MIN(score, scoreThreshold);
	}
	NSInteger matchmask = 1 << ([pattern length] - 1);
	bestLoc = -1;
	
	NSInteger binMin, binMid;
	NSInteger temp = [text length];
	NSInteger binMax = MAX(loc + loc, temp);
	NSInteger *lastRd = NULL;
	for (NSInteger d = 0; d < [pattern length]; d++) {
		NSInteger *rd = malloc([text length] * sizeof(NSInteger));
		binMin = loc;
		binMid = binMax;
		while (binMin < binMid) {
			if ([self matchBitapScore:d x:binMid loc:loc scoreTextLength:scoreTextLength pattern:pattern] < scoreThreshold) {
				binMin = binMid;
			} else {
				binMax = binMid;
			}
			binMid = (binMax - binMin) / 2 + binMin;
		}
		binMax = binMid;
		NSInteger start = MAX(0, loc - (binMid - loc) - 1);
		NSInteger temp1 = [text length];
		NSInteger temp2 = [pattern length]; 
		NSInteger finish = MIN(temp1 - 1, temp2 + binMid);
		if ([text characterAtIndex:finish] == [pattern characterAtIndex:[pattern length] - 1]) {
			rd[finish] = (1 << (d + 1)) - 1;
		} else {
			rd[finish] = (1 << d) - 1;
		}
		for (NSInteger j = finish - 1; j >= start; j--) {
			NSNumber *value = [s objectForKey:[NSNumber numberWithInteger:[text characterAtIndex:j]]];
			if (d == 0) {
				rd[j] = ((rd[j + 1] << 1) | 1) & (value != nil ? [value integerValue] : 0);
			} else {
				rd[j] = ((rd[j + 1] << 1) | 1) & (value != nil ? [value integerValue] : 0) | ((lastRd[j + 1] << 1) | 1) | ((lastRd[j] << 1) | 1) | lastRd[j + 1];
			}
			if ((rd[j] & matchmask) != 0) {
				double score = [self matchBitapScore:d x:j loc:loc scoreTextLength:scoreTextLength pattern:pattern];
				if (score <= scoreThreshold) {
					scoreThreshold = score;
					bestLoc = j;
					if (j > loc) {
						start = MAX(0, loc - (j - loc));
					} else {
						break;
					}
				}
			}
		}
		if ([self matchBitapScore:d + 1 x:loc loc:loc scoreTextLength:scoreTextLength pattern:pattern] > scoreThreshold) {
			break;
		}
		if (lastRd) {
			free(lastRd);
		}
		lastRd = rd;
	}
	
	if (lastRd) {
		free(lastRd);
	}
	
	return bestLoc;
}

- (double)matchBitapScore:(NSInteger)e x:(NSInteger)x loc:(NSInteger)loc scoreTextLength:(NSInteger)scoreTextLength pattern:(NSString *)pattern {
	return (e / (float) [pattern length] / Match_Balance) + (ABS(loc - x) / (float) scoreTextLength / (1.0 - Match_Balance));
}

- (NSDictionary *)matchAlphabet:(NSString *)pattern {
	NSMutableDictionary *s = [NSMutableDictionary dictionary];
	NSUInteger length = [pattern length];
	for (NSUInteger i = 0; i < length; i++) {
		[s setObject:[NSNumber numberWithInteger:0] forKey:[NSNumber numberWithInteger:[pattern characterAtIndex:i]]];
	}
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [pattern characterAtIndex:i];
		NSNumber *key = [NSNumber numberWithInteger:c];
		[s setObject:[NSNumber numberWithInteger:[[s objectForKey:key] integerValue] | (1 << ([pattern length] - i - 1))] forKey:key];
	}
	return s;
}

- (void)patchAddContext:(BPatch *)patch text:(NSString *)text {
	NSString *pattern = [text Jsubstring:patch.start2 :patch.start2 + patch.length1];
	NSInteger padding = 0;
	while ([text JindexOf:pattern] != [text JlastIndexOf:pattern] && [pattern length] < Match_MaxBits - Patch_Margin - Patch_Margin) {
		padding += Patch_Margin;
		NSInteger temp = [text length];
		pattern = [text Jsubstring:MAX(0, patch.start2 - padding) :MIN(temp, patch.start2 + patch.length1 + padding)]; 
	}
	padding += Patch_Margin;
	NSString *prefix = [text Jsubstring:MAX(0, patch.start2 - padding) :patch.start2];
	if ([prefix length] != 0) {
		[patch.diffs insertObject:[BDiff equal:prefix] atIndex:0];
	}
	NSInteger temp = [text length];
	NSString *suffix = [text Jsubstring:patch.start2 + patch.length1 :MIN(temp, patch.start2 + patch.length1 + padding)];
	if ([suffix length] != 0) {
		[patch.diffs addObject:[BDiff equal:suffix]];
	}
	patch.start1 -= [prefix length];
	patch.start2 -= [prefix length];
	patch.length1 += [prefix length] + [suffix length];
	patch.length2 += [prefix length] + [suffix length];
}

- (NSMutableArray *)patchMakeText1:(NSString *)text1 text2:(NSString *)text2 {
	NSMutableArray *diffs = [self diffMainText1:text1 text2:text2];
	if ([diffs count] > 2) {
		[self diffCleanupSemantic:diffs];
		[self diffCleanupEfficiency:diffs];
	}
	return [self patchMakeText1:text1 diffs:diffs];
}

- (NSMutableArray *)patchMakeDiffs:(NSArray *)diffs {
	NSString *text1 = [self diffText1:diffs];
	return [self patchMakeText1:text1 diffs:diffs];
}

- (NSMutableArray *)patchMakeText1:(NSString *)text1 diffs:(NSArray *)diffs {
	NSMutableArray *patches = [NSMutableArray array];
	if ([diffs count] == 0) {
		return patches;
	}
	BPatch *patch = [[BPatch alloc] init];
	NSInteger charCount1 = 0;
	NSInteger charCount2 = 0;
	NSString *prepatchText = text1;
	NSString *postPatchText = text1;
	for (BDiff *aDiff in diffs) {
		if ([patch.diffs count] == 0 && aDiff.operation != BDiffEqual) {
			patch.start1 = charCount1;
			patch.start2 = charCount2;
		}
		switch (aDiff.operation) {
			case BDiffInsert:
				[patch.diffs addObject:aDiff];
				patch.length2 += [aDiff.text length];
				postPatchText = [NSString stringWithFormat:@"%@%@%@", [postPatchText Jsubstring:0 :charCount2], aDiff.text, [postPatchText Jsubstring:charCount2]];
				break;
			case BDiffDelete:
				patch.length1 += [aDiff.text length];
				[patch.diffs addObject:aDiff];
				postPatchText = [NSString stringWithFormat:@"%@%@", [postPatchText Jsubstring:0 :charCount2], [postPatchText Jsubstring:charCount2 + [aDiff.text length]]];
				break;
			case BDiffEqual:
				if ([aDiff.text length] <= 2 * Patch_Margin && [patch.diffs count] != 0 && aDiff != [diffs lastObject]) {
					[patch.diffs addObject:aDiff];
					patch.length1 += [aDiff.text length];
					patch.length2 += [aDiff.text length];
				}
				if ([aDiff.text length] >=  2 * Patch_Margin) {
					if ([patch.diffs count] != 0) {
						[self patchAddContext:patch text:prepatchText];
						[patches addObject:patch];
						patch = [[BPatch alloc] init];
						prepatchText = postPatchText;
					}
				}
				break;
		}
		
		if (aDiff.operation != BDiffInsert) {
			charCount1 += [aDiff.text length];
		}
		if (aDiff.operation != BDiffDelete) {
			charCount2 += [aDiff.text length];
		}
	}
	
	if ([patch.diffs count] != 0) {
		[self patchAddContext:patch text:prepatchText];
		[patches addObject:patch];
	}
	
	return patches;
}

- (NSArray *)patchApply:(NSMutableArray *)patches text:(NSString *)text {
	NSMutableString *textResult = [text mutableCopy];
	if ([patches count] == 0) {
		return [NSArray array];
	}
	NSMutableArray *patchesCopy = [NSMutableArray array];
	for (BPatch *aPatch in patches) {
		BPatch *patchCopy = [[[BPatch alloc] init] autorelease];
		for (BDiff *aDiff in aPatch.diffs) {
			BDiff *diffCopy = [BDiff diffWithOperationType:aDiff.operation text:[[aDiff.text mutableCopy] autorelease]];
			[patchCopy.diffs addObject:diffCopy];
		}
		patchCopy.start1 = aPatch.start1;
		patchCopy.start2 = aPatch.start2;
		patchCopy.length1 = aPatch.length1;
		patchCopy.length2 = aPatch.length2;
		[patchesCopy addObject:patchCopy];
	}
	patches = patchesCopy;
	NSString *nullPadding = [self patchAddPadding:patches];
	[textResult insertString:nullPadding atIndex:0];
	[textResult appendString:nullPadding];
	[self patchSplitMax:patches];
	NSInteger x = 0;
	NSInteger delta = 0;
	NSMutableArray *results = [NSMutableArray arrayWithCapacity:[patches count]];
	NSInteger expectedLoc, startLoc;
	NSString *text1;
	NSString *text2;
	NSInteger index1, index2;
	for (BPatch *aPatch in patches) {
		expectedLoc = aPatch.start2 + delta;
		text1 = [self diffText1:aPatch.diffs];
		startLoc = [self matchMain:textResult pattern:text1 loc:expectedLoc];
		if (startLoc == -1) {
			[results addObject:[NSNumber numberWithBool:NO]];
		} else {
			[results addObject:[NSNumber numberWithBool:YES]];
			delta = startLoc - expectedLoc;
			text2 = [textResult Jsubstring:startLoc : MIN(startLoc + [text1 length], [textResult length])];
			if ([text1 isEqualToString:text2]) {
				[textResult replaceCharactersInRange:NSMakeRange(startLoc, [text1 length]) withString:[self diffText2:aPatch.diffs]];
			} else {
				NSMutableArray *diffs = [self diffMapText1:text1 text2:text2];
				[self diffCleanupSemanticLossless:diffs];
				index1 = 0;
				for (BDiff *aDiff in aPatch.diffs) {
					if (aDiff.operation != BDiffEqual) {
						index2 = [self diffXIndex:diffs location:index1];
						if (aDiff.operation == BDiffInsert) {
							[textResult insertString:aDiff.text atIndex:startLoc + index2];
						} else if (aDiff.operation == BDiffDelete) {
							NSInteger start = startLoc + index2;
							NSInteger diff = [self diffXIndex:diffs location:index1 + [aDiff.text length]];
							NSRange range = NSMakeRange(start, (startLoc + diff) - start);
							[textResult replaceCharactersInRange:range withString:@""];
						}
					}
					if (aDiff.operation != BDiffDelete) {
						index1 += [aDiff.text length];
					}
				}
			}
		}
		x++;
	}
	[textResult replaceCharactersInRange:NSMakeRange(0, [nullPadding length]) withString:@""];
	[textResult replaceCharactersInRange:NSMakeRange([textResult length] - [nullPadding length], [nullPadding length]) withString:@""];
	return [NSArray arrayWithObjects:textResult, results, nil];
}

- (NSString *)patchAddPadding:(NSArray *)patches {
	NSMutableArray *diffs;
	NSMutableString *nullPadding = [NSMutableString string];
	for (NSInteger x = 0; x < Patch_Margin; x++) {
		[nullPadding appendFormat:@"%C", (char) x];
	}
	for (BPatch *aPatch in patches) {
		aPatch.start1 += [nullPadding length];
		aPatch.start2 += [nullPadding length];
	}
	BPatch *patch = [patches objectAtIndex:0];
	diffs = patch.diffs;
	if ([diffs count] == 0 || [[diffs objectAtIndex:0] operation] != BDiffEqual) {
		[diffs insertObject:[BDiff equal:nullPadding] atIndex:0];
		patch.start1 -= [nullPadding length];
		patch.start2 -= [nullPadding length];
		patch.length1 += [nullPadding length];
		patch.length2 += [nullPadding length];
	} else if ([nullPadding length] > [[[diffs objectAtIndex:0] text] length]) {
		BDiff *firstDiff = [diffs objectAtIndex:0];
		NSInteger extraLength = [nullPadding length] - [firstDiff.text length];
		[firstDiff.text insertString:[nullPadding Jsubstring:[firstDiff.text length]] atIndex:0];
		patch.start1 -= extraLength;
		patch.start2 -= extraLength;
		patch.length1 += extraLength;
		patch.length2 += extraLength;
	}
	patch = [patches lastObject];
	diffs = patch.diffs;
	if ([diffs count] == 0 || [[diffs lastObject] operation] != BDiffEqual) {
		[diffs addObject:[BDiff equal:nullPadding]];
		patch.length1 += [nullPadding length];
		patch.length2 += [nullPadding length];
	} else if ([nullPadding length] > [[[diffs lastObject] text] length]) {
		BDiff *lastDiff = [diffs lastObject];
		NSInteger extraLength = [nullPadding length] - [[[diffs lastObject] text] length];
		[lastDiff.text appendString:[nullPadding Jsubstring:0 :extraLength]];
		patch.length1 += extraLength;
		patch.length2 += extraLength;
	}
	return nullPadding;
}

- (void)patchSplitMax:(NSMutableArray *)patches {
	NSInteger patchSize;
	NSString *precontext;
	NSString *postcontext;
	BPatch *patch;
	NSInteger start1, start2;
	BOOL empty;
	BDiffOperation diffType;
	NSString *diffText;
	BArrayIterator *pointer = [[[BArrayIterator alloc] initWithArray:patches] autorelease];
	BPatch *bigpatch = [pointer hasNext] ? [pointer next] : nil;
	while (bigpatch != nil) {
		if (bigpatch.length1 <= Match_MaxBits) {
			bigpatch = [pointer hasNext] ? [pointer next] : nil;
			continue;
		}
		[pointer remove];
		patchSize = Match_MaxBits;
		start1 = bigpatch.start1;
		start2 = bigpatch.start2;
		precontext = @"";
		while ([bigpatch.diffs count] != 0) {
			patch = [[[BPatch alloc] init] autorelease];
			empty = YES;
			patch.start1 = start1 - [precontext length];
			patch.start2 = start2 - [precontext length];
			if ([precontext length] != 0) {
				patch.length1 = [precontext length];
				patch.length2 = [precontext length];
				[patch.diffs addObject:[BDiff equal:precontext]];
			}
			while ([bigpatch.diffs count] != 0 && patch.length1 < patchSize - Patch_Margin) {
				diffType = [[bigpatch.diffs objectAtIndex:0] operation];
				diffText = [[bigpatch.diffs objectAtIndex:0] text];
				if (diffType == BDiffInsert) {
					patch.length2 += [diffText length];
					start2 += [diffText length];
					[patch.diffs addObject:[bigpatch.diffs objectAtIndex:0]];
					[bigpatch.diffs removeObjectAtIndex:0];
					empty = NO;
				} else {
					NSInteger temp = [diffText length];
					diffText = [diffText Jsubstring:0 :MIN(temp, patchSize - patch.length1 - Patch_Margin)];
					patch.length1 += [diffText length];
					start1 += [diffText length];
					if (diffType == BDiffEqual) {
						patch.length2 += [diffText length];
						start2 += [diffText length];
					} else {
						empty = NO;
					}
					[patch.diffs addObject:[BDiff diffWithOperationType:diffType text:diffText]];
					if ([diffText isEqualToString:[[bigpatch.diffs objectAtIndex:0] text]]) {
						[bigpatch.diffs removeObjectAtIndex:0];
					} else {
						[[bigpatch.diffs objectAtIndex:0] setText:[[[bigpatch.diffs objectAtIndex:0] text] Jsubstring:[diffText length]]];
					}
				}
			}
			precontext = [self diffText2:patch.diffs];
			NSInteger temp = [precontext length];
			precontext = [precontext Jsubstring:MAX(0, temp - Patch_Margin)];
			NSString *diffText1 = [self diffText1:bigpatch.diffs];
			if ([diffText1 length] > Patch_Margin) {
				postcontext = [diffText1 Jsubstring:0 :Patch_Margin];
			} else {
				postcontext = diffText1;
			}
			if ([postcontext length] != 0) {
				patch.length1 += [postcontext length];
				patch.length2 += [postcontext length];
				if ([patch.diffs count] != 0 && [[patch.diffs lastObject] operation] == BDiffEqual) {
					[[[patch.diffs lastObject] text] appendString:postcontext];
				} else {
					[patch.diffs addObject:[BDiff equal:postcontext]];
				}
			}
			if (!empty) {
				[pointer add:patch];
			}
		}
		bigpatch = [pointer hasNext] ? [pointer next] : nil;
	}
}

- (NSString *)patchToText:(NSArray *)patches {
	NSMutableString *text = [NSMutableString string];
	for (BPatch *aPatch in patches) {
		[text appendString:[aPatch description]];
	}
	return text;
}

- (NSArray *)patchFromText:(NSString *)textline {
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	NSMutableArray *patches = [NSMutableArray array];
	if ([textline length] == 0) {
		return patches;
	}
	NSMutableArray *text = [[[textline componentsSeparatedByString:@"\n"] mutableCopy] autorelease];
	BPatch *patch;
	NSString *patchHeader = @"^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@$";
	unichar sign;
	NSString *line;
	while ([text count] != 0) {
		NSString *firstText = [text objectAtIndex:0];
		NSRange capture1Range = [firstText rangeOfRegex:patchHeader capture:1];
		NSRange capture2Range = [firstText rangeOfRegex:patchHeader capture:2];
		NSRange capture3Range = [firstText rangeOfRegex:patchHeader capture:3];
		NSRange capture4Range = [firstText rangeOfRegex:patchHeader capture:4];
		NSString *capture1String = [firstText substringWithRange:capture1Range];
		NSString *capture2String = [firstText substringWithRange:capture2Range];
		NSString *capture3String = [firstText substringWithRange:capture3Range];
		NSString *capture4String = [firstText substringWithRange:capture4Range];
		
		patch = [[[BPatch alloc] init] autorelease];
		[patches addObject:patch];
		patch.start1 = [[numberFormatter numberFromString:capture1String] integerValue];
		if ([capture2String length] == 0) {
			patch.start1--;
			patch.length1 = 1;
		} else if ([capture2String isEqualToString:@"0"]) {
			patch.length1 = 0;
		} else {
			patch.start1--;
			patch.length1 = [[numberFormatter numberFromString:capture2String] integerValue];
		}
		
		patch.start2 = [[numberFormatter numberFromString:capture3String] integerValue];
		if ([capture4String length] == 0) {
			patch.start2--;
			patch.length2 = 1;
		} else if ([capture4String isEqualToString:@"0"]) {
			patch.length2 = 0;
		} else {
			patch.start2--;
			patch.length2 = [[numberFormatter numberFromString:capture4String] integerValue];
		}
		[text removeObjectAtIndex:0];
		
		while ([text count] != 0) {
			firstText = [text objectAtIndex:0];
			if ([firstText length] > 0) { // not blank line
				sign = [firstText characterAtIndex:0];
				line = [[text objectAtIndex:0] Jsubstring:1];
				line = [line stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
				line = [line URLDecode];
				if (sign == '-') {
					[patch.diffs addObject:[BDiff delete:line]];
				} else if (sign == '+') {
					[patch.diffs addObject:[BDiff insert:line]];
				} else if (sign == ' ') {
					[patch.diffs addObject:[BDiff equal:line]];
				} else if (sign == '@') {
					break;
				} else {
					[NSException raise:@"Invalid patch mode" format:nil];
				}
			}
			[text removeObjectAtIndex:0];
		}
	}
	return patches;
}

@end

@implementation BDiff

+ (id)equal:(NSString *)text {
	return [self diffWithOperationType:BDiffEqual text:text];
}

+ (id)insert:(NSString *)text {
	return [self diffWithOperationType:BDiffInsert text:text];
}

+ (id)delete:(NSString *)text {
	return [self diffWithOperationType:BDiffDelete text:text];
}

+ (id)diffWithOperationType:(BDiffOperation)operation text:(NSString *)text {
	return [[BDiff alloc] initWithText:text operation:operation];
}

- (id)initWithText:(NSString *)aText operation:(BDiffOperation)anOperation {
	if (self = [super init]) {
		text = [aText mutableCopy];
		operation = anOperation;
	}
	return self;
}

- (BOOL)isEqual:(id)anObject {
	if ([anObject isKindOfClass:[self class]]) {
		BDiff *other = (id) anObject;
		return other.operation == self.operation && [other.text isEqual:self.text];
	}
	return NO;
}

- (NSUInteger)hash {
	return [self.text hash] + self.operation;
}

@synthesize operation;
@synthesize text;

- (void)setText:(id)aString {
	text = [aString mutableCopy];
}

- (NSString *)description {
	NSString *prettyText = [self.text stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
	prettyText = [prettyText stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
	NSString *op = @"EQUAL";
	if (operation == BDiffInsert) {
		op = @"INSERT";
	} else if (operation == BDiffDelete) {
		op = @"DELETE";
	}
	return [NSString stringWithFormat:@"Diff(%@, \"%@\")", op, prettyText];
}

@end

@implementation BPatch

- (id)init {
	if (self = [super init]) {
		diffs = [[NSMutableArray array] retain];
	}
	return self;
}

@synthesize diffs;
@synthesize start1;
@synthesize start2;
@synthesize length1;
@synthesize length2;

- (NSString *)description {
	NSString *coords1;
	NSString *coords2;
	if (length1 == 0) {
		coords1 = [NSString stringWithFormat:@"%i,0", start1];
	} else if (length1 == 1) {
		coords1 = [NSString stringWithFormat:@"%i", start1 + 1];
	} else {
		coords1 = [NSString stringWithFormat:@"%i,%i", start1 + 1, length1];
	}
	
	if (length2 == 0) {
		coords2 = [NSString stringWithFormat:@"%i,0", start2];
	} else if (length2 == 1) {
		coords2 = [NSString stringWithFormat:@"%i", start2 + 1];
	} else {
		coords2 = [NSString stringWithFormat:@"%i,%i", start2 + 1, length2];
	}
	
	NSMutableString *text = [NSMutableString string];
	[text appendString:[NSString stringWithFormat:@"@@ -%@ +%@ @@\n", coords1, coords2]];
	for (BDiff *aDiff in diffs) {
		switch (aDiff.operation) {
			case BDiffInsert:
				[text appendString:@"+"];
				break;
			case BDiffDelete:
				[text appendString:@"-"];
				break;
			case BDiffEqual:
				[text appendString:@" "];
				break;
		}
		[text appendString:[[aDiff.text URLEncode] stringByReplacingOccurrencesOfString:@"+" withString:@" "]];
		[text appendString:@"\n"];
	}
	
	[text unescapeForEncodeUriCompatability];
	return text;
}

@end

@implementation NSString (BDocumentsPrivate)

- (NSInteger)JindexOf:(NSString *)aString {
	return [self JindexOf:aString :0];
}

- (NSInteger)JindexOf:(NSString *)aString :(NSUInteger)fromIndex {
	NSUInteger r = [self rangeOfString:aString options:0 range:NSMakeRange(fromIndex, [self length] - fromIndex)].location;
	if (r == NSNotFound) {
		return -1;
	}
	return r;
}

- (NSInteger)JlastIndexOf:(NSString *)aString {
	NSUInteger r = [self rangeOfString:aString options:NSBackwardsSearch].location;
	if (r == NSNotFound) {
		return -1;
	}
	return r;
	
}

- (NSInteger)JlastIndexOf:(NSString *)aString :(NSUInteger)fromIndex {
	NSUInteger r = [self rangeOfString:aString options:NSBackwardsSearch range:NSMakeRange(0, fromIndex < [self length] ? fromIndex : [self length]) locale:nil].location;
	if (r == NSNotFound) {
		return -1;
	}
	return r;
}

- (NSString *)Jsubstring:(NSInteger)beginIndex {
	return [self substringFromIndex:beginIndex];
}

- (NSString *)Jsubstring:(NSInteger)beginIndex :(NSInteger)endIndex {
	return [self substringWithRange:NSMakeRange(beginIndex, endIndex - beginIndex)];
}

- (NSString *)URLEncode {
	// From Google Data Objective-C client 
	// NSURL's stringByAddingPercentEscapesUsingEncoding: does not escape
	// some characters that should be escaped in URL parameters, like / and ?; 
	// we'll use CFURL to force the encoding of those
	//
	// We'll explicitly leave spaces unescaped now, and replace them with +'s
	//
	// Reference: http://www.ietf.org/rfc/rfc3986.txt
	
	NSString *resultStr = self;
	CFStringRef originalString = (CFStringRef) self;
	CFStringRef leaveUnescaped = CFSTR(" ");
	CFStringRef forceEscaped = CFSTR("!'();:@&=+$,/?%#[]"); // XXX different that what I did have!
	CFStringRef escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, originalString, leaveUnescaped, forceEscaped, kCFStringEncodingUTF8);
	
	if (escapedStr) {
		NSMutableString *mutableStr = [NSMutableString stringWithString:(NSString *)escapedStr];
		CFRelease(escapedStr);
		[mutableStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [mutableStr length])];
		resultStr = mutableStr;
	}
	
	return resultStr;	
}

- (NSString *)URLDecode {
	return [[self stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}


@end

@implementation NSMutableString (BDocumentsPrivate)

- (void)unescapeForEncodeUriCompatability {
	[self replaceOccurrencesOfString:@"%21" withString:@"!" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%7E" withString:@"~" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%27" withString:@"'" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%28" withString:@"(" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%29" withString:@")" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%3B" withString:@";" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%2F" withString:@"/" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%3F" withString:@"?" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%3A" withString:@":" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%40" withString:@"@" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%26" withString:@"&" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%3D" withString:@"=" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%2B" withString:@"+" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%24" withString:@"$" options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%2C" withString:@"," options:0 range:NSMakeRange(0, [self length])];
	[self replaceOccurrencesOfString:@"%23" withString:@"#" options:0 range:NSMakeRange(0, [self length])];
}

@end

@implementation NSMutableArray (BDocumentsPrivate)

- (NSMutableArray *)JsubList:(NSInteger)fromIndex :(NSInteger)toIndex {
	return [[self subarrayWithRange:NSMakeRange(fromIndex, toIndex - fromIndex)] mutableCopy];
}

@end

@implementation BArrayIterator

- (id)initWithArray:(NSMutableArray *)anArray {
	if (self = [super init]) {
		array = anArray;
	}
	return self;
}

- (BOOL)hasNext {
	return cursor != [array count];
}

- (BOOL)hasPrevious {
	return cursor != 0;
}

- (id)next {
	lastRet = cursor;
	cursor++;
	return [array objectAtIndex:lastRet];
}

- (id)previous {
	cursor--;
	lastRet = cursor;
	return [array objectAtIndex:cursor];
}

- (void)set:(id)object {
	[array replaceObjectAtIndex:lastRet withObject:object];
}

- (void)add:(id)object {
	[array insertObject:object atIndex:cursor];
	cursor++;
	lastRet = -1;
}

- (void)remove {
	[array removeObjectAtIndex:lastRet];
	cursor = lastRet;
	lastRet = -1;
}

@end
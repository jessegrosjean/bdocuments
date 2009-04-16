//
//  DiffMatchPatch.h
//  BDocuments
//
//  Created by Jesse Grosjean on 10/4/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

enum {
    BDiffDelete = 1,
    BDiffInsert = 2,
    BDiffEqual = 3
};
typedef NSUInteger BDiffOperation;

@class BPatch;

@interface DiffMatchPatch : NSObject {
	NSTimeInterval Diff_Timeout;
	NSInteger Diff_EditCost;
	NSInteger Diff_DualThreshold;
	double Match_Balance;
	double Match_Threshold;
	NSInteger Match_MinLength;
	NSInteger Match_MaxLength;
	NSInteger Patch_Margin;
	NSInteger Match_MaxBits;
}

@property(assign) NSTimeInterval Diff_Timeout;
@property(assign) NSInteger Diff_EditCost;
@property(assign) NSInteger Diff_DualThreshold;
@property(assign) double Match_Balance;
@property(assign) double Match_Threshold;
@property(assign) NSInteger Match_MinLength;
@property(assign) NSInteger Match_MaxLength;
@property(assign) NSInteger Patch_Margin;
@property(assign) NSInteger Match_MaxBits;

- (NSMutableArray *)diffMainText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffComputeText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffMapText1:(NSString *)text1 text2:(NSString *)text2;
- (NSArray *)diffHalfMatchText1:(NSString *)text1 text2:(NSString *)text2;
- (NSArray *)diffHalfMatch1LongText:(NSString *)longText shortText:(NSString *)shortText i:(NSInteger)i;
- (NSNumber *)diffFootprintX:(NSInteger)x y:(NSInteger)y;
- (NSInteger)diffCommonPrefixText1:(NSString *)text1 text2:(NSString *)text2;
- (NSInteger)diffCommonSuffixText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffPath1:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)diffPath2:(NSMutableArray *)vMap text1:(NSString *)text1 text2:(NSString *)text2;
- (void)diffCleanupSemantic:(NSMutableArray *)diffs;
- (void)diffCleanupSemanticLossless:(NSMutableArray *)diffs;
- (NSInteger)diffCleanupSemanticScoreText1:(NSString *)text1 text2:(NSString *)text2;
- (void)diffCleanupEfficiency:(NSMutableArray *)diffs;
- (void)diffCleanupMerge:(NSMutableArray *)diffs;
- (NSInteger)diffXIndex:(NSArray *)diffs location:(NSInteger)location;
- (NSString *)diffPrettyHTML:(NSArray *)diffs;
- (NSString *)diffText1:(NSArray *)diffs;
- (NSString *)diffText2:(NSArray *)diffs;
- (NSString *)diffToDelta:(NSArray *)diffs;
- (NSMutableArray *)diffFromDeltaText1:(NSString *)text1 delta:(NSString *)delta;
- (NSInteger)matchMain:(NSString *)text pattern:(NSString *)pattern loc:(NSInteger)loc;
- (NSInteger)matchBitap:(NSString *)text pattern:(NSString *)pattern loc:(NSInteger)loc;
- (double)matchBitapScore:(NSInteger)e x:(NSInteger)x loc:(NSInteger)loc scoreTextLength:(NSInteger)scoreTextLength pattern:(NSString *)pattern;
- (NSDictionary *)matchAlphabet:(NSString *)pattern;
- (void)patchAddContext:(BPatch *)patch text:(NSString *)text;
- (NSMutableArray *)patchMakeText1:(NSString *)text1 text2:(NSString *)text2;
- (NSMutableArray *)patchMakeDiffs:(NSArray *)diffs;
- (NSMutableArray *)patchMakeText1:(NSString *)text1 diffs:(NSArray *)diffs;
- (NSArray *)patchApply:(NSMutableArray *)patches text:(NSString *)text;
- (NSString *)patchAddPadding:(NSArray *)patches;
- (void)patchSplitMax:(NSMutableArray *)patches;
- (NSString *)patchToText:(NSArray *)patches;
- (NSMutableArray *)patchFromText:(NSString *)textline;
@end

@interface BDiff : NSObject {
	BDiffOperation operation;
	NSMutableString *text;
}

+ (id)equal:(NSString *)text;
+ (id)insert:(NSString *)text;
+ (id)delete:(NSString *)text;
+ (id)diffWithOperationType:(BDiffOperation)operation text:(NSString *)text;
- (id)initWithText:(NSString *)aText operation:(BDiffOperation)anOperation;

@property(readonly) BDiffOperation operation;
@property(retain) id text;

@end

@interface BPatch : NSObject {
	NSMutableArray *diffs;
	NSInteger start1;
	NSInteger start2;
	NSInteger length1;
	NSInteger length2;
}

@property(retain) NSMutableArray *diffs;
@property(assign) NSInteger start1;
@property(assign) NSInteger start2;
@property(assign) NSInteger length1;
@property(assign) NSInteger length2;

@end

extern NSString *DiffTypeAttributeName;
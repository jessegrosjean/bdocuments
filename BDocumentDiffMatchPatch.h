//
//  BDocumentDiffMatchPatch.h
//  BDocuments
//
//  Created by Jesse Grosjean on 10/4/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


enum {
    BDocumentDiffDelete = 1,
    BDocumentDiffInsert = 2,
    BDocumentDiffEqual = 3
};
typedef NSUInteger BDocumentDiffOperation;

@interface BDocumentDiffMatchPatch : NSObject {
	CGFloat Diff_Timeout;
	NSInteger Diff_EditCost;
	NSInteger Diff_DualThreshold;
	CGFloat Match_Balance;
	CGFloat Match_Threshold;
	NSInteger Match_MinLength;
	NSInteger Match_MaxLength;
	NSInteger Patch_Margin;
	NSInteger Match_MaxBits;
}

- (NSMutableArray *)diffMainText1:(NSString *)text1 text2:(NSString *)text2;
- (void)diffCleanupMerge:(NSMutableArray *)diffs;
@end

@interface BDocumentDiff : NSObject {
	NSString *text;
}

+ (id)equalDiffWithText:(NSString *)text;
+ (id)insertDiffWithText:(NSString *)text;
+ (id)deleteDiffWithText:(NSString *)text;
+ (id)diffWithOperationType:(BDocumentDiffOperation)operation text:(NSString *)text;

@property(retain) NSString *text;

@end
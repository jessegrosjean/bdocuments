//
//  BDocumentDifferencesWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 1/7/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BDocumentDifferencesWindowController.h"
#import "BDiffMatchPatch.h"

@implementation BDocumentDifferencesWindowController

- (id)init {
	if (self = [super initWithWindowNibName:@"BDocumentDifferencesWindow"]) {
	}
	return self;
}

- (id)initWithText1:(NSString *)aText1 text2:(NSString *)aText2 {
	if (self = [self init]) {
		text1 = aText1;
		text2 = aText2;
	}
	return self;
}

- (void)awakeFromNib {
	BDiffMatchPatch *dmp = [[BDiffMatchPatch alloc] init];
	NSMutableArray *diffs = [dmp diffMainText1:text1 text2:text2];
	[dmp diffCleanupSemantic:diffs];
	NSAttributedString *prettyAttributedString = [dmp diffPrettyAttributedString:diffs];
	[[textView textStorage] replaceCharactersInRange:NSMakeRange(0, 0) withAttributedString:prettyAttributedString];
}

- (IBAction)nextChange:(id)sender {
	NSTextStorage *textStorage = [textView textStorage];
	NSRange selectedRange = [textView selectedRange];
	NSRange limitRange = NSMakeRange(NSMaxRange(selectedRange), [textStorage length] - NSMaxRange(selectedRange));
	NSRange effectiveRange;
	NSNumber *changetype;
	BOOL firstPass = NO;
	
	while (limitRange.length > 0) {
		changetype = [textStorage attribute:BDocumentDiffTypeAttributeName atIndex:limitRange.location longestEffectiveRange:&effectiveRange inRange:limitRange];
		if (firstPass) {
			firstPass = NO;
		} else if ([changetype integerValue] != BDiffEqual) {
			[textView scrollRangeToVisible:effectiveRange];
			[textView setSelectedRange:effectiveRange];
			[textView showFindIndicatorForRange:effectiveRange];
			break;
		}
		limitRange = NSMakeRange(NSMaxRange(effectiveRange), NSMaxRange(limitRange) - NSMaxRange(effectiveRange));
		if (limitRange.length == 0) {
			limitRange = NSMakeRange(0, [textStorage length]);
		}
	}
}

- (void)processChanges:(BOOL)acceptingChanges {
	NSTextStorage *textStorage = [textView textStorage];
	NSRange selectedRange = [textView selectedRange];
	NSRange limitRange = NSMakeRange(NSMaxRange(selectedRange), [textStorage length] - NSMaxRange(selectedRange));
	NSRange effectiveRange;
	NSNumber *changetype;
	
	while (limitRange.length > 0) {
		changetype = [textStorage attribute:BDocumentDiffTypeAttributeName atIndex:limitRange.location longestEffectiveRange:&effectiveRange inRange:limitRange];
		if ([changetype integerValue] == BDiffDelete) {
			if (acceptingChanges) {
				[textStorage replaceCharactersInRange:effectiveRange withString:@""];
			} else {
				[textStorage removeAttribute:BDocumentDiffTypeAttributeName range:effectiveRange];
				[textStorage removeAttribute:NSBackgroundColorAttributeName range:effectiveRange];
			}
		} else if ([changetype integerValue] == BDiffInsert) {
			if (acceptingChanges) {
				[textStorage removeAttribute:BDocumentDiffTypeAttributeName range:effectiveRange];
				[textStorage removeAttribute:NSBackgroundColorAttributeName range:effectiveRange];
			} else {
				[textStorage replaceCharactersInRange:effectiveRange withString:@""];
			}
		}
		limitRange = NSMakeRange(NSMaxRange(effectiveRange), NSMaxRange(limitRange) - NSMaxRange(effectiveRange));
	}	
}

- (IBAction)previousChange:(id)sender {
	
}

- (IBAction)acceptChange:(id)sender {
	
}

- (IBAction)rejectChange:(id)sender {
	
}

- (IBAction)close:(id)sender {
	[NSApp endSheet:[self window]];
}

@end

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

- (IBAction)close:(id)sender {
	[NSApp endSheet:[self window]];
}

@end

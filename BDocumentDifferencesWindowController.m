//
//  BDocumentDifferencesWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 1/7/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BDocumentDifferencesWindowController.h"
#import "DiffMatchPatch.h"

@implementation BDocumentDifferencesWindowController

- (id)init {
	if (self = [super initWithWindowNibName:@"BDocumentDifferencesWindow"]) {
	}
	return self;
}

- (id)initWithDiffs:(NSMutableArray *)aDiffs {
	if (self = [self init]) {
		diffs = aDiffs;
	}
	return self;
}

- (id)initWithText1:(NSString *)aText1 text2:(NSString *)aText2 {
	return [self initWithDiffs:[[[DiffMatchPatch alloc] init] diffMainText1:aText1 text2:aText2]];
}

- (void)awakeFromNib {
	WebFrame *frame = [webView mainFrame];
	DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
	[dmp diffCleanupSemantic:diffs];
	NSString *prettyHTML = [dmp diffPrettyHTML:diffs];
	[frame loadHTMLString:prettyHTML baseURL:nil];
}

- (void)setMessageText:(NSString *)messageText {
	[self window];
	[messageTextField setStringValue:messageText];
}

- (IBAction)close:(id)sender {
	[NSApp endSheet:[self window]];
}

@end

//
//  BDocumentDifferencesWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 1/7/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


@interface BDocumentDifferencesWindowController : NSWindowController {
	IBOutlet NSTextField *messageTextField;
	IBOutlet WebView *webView;
	NSMutableArray *diffs;
}

- (id)initWithDiffs:(NSMutableArray *)diffs;
- (id)initWithText1:(NSString *)text1 text2:(NSString *)text2;

- (void)setMessageText:(NSString *)messageText;

- (IBAction)close:(id)sender;

@end

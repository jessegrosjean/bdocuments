//
//  BDocumentDifferencesWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 1/7/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BDocumentDifferencesWindowController : NSWindowController {
	IBOutlet NSTextView *textView;
	NSString *text1;
	NSString *text2;
}

- (id)initWithText1:(NSString *)text1 text2:(NSString *)text2;

- (IBAction)nextChange:(id)sender;
- (IBAction)previousChange:(id)sender;
- (IBAction)acceptChange:(id)sender;
- (IBAction)rejectChange:(id)sender;
- (IBAction)close:(id)sender;

@end

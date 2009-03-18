//
//  BCloudNameWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 3/2/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BCloudNameWindowController : NSWindowController {
	IBOutlet NSTextField *message;
	IBOutlet NSTextField *nameTextField;
}

@property(retain) NSString *name;

- (IBAction)cancel:(id)sender;
- (IBAction)ok:(id)sender;

@end

//
//  BCloudSyncWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 2/27/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BCloudSyncWindowController : NSWindowController {
	IBOutlet NSProgressIndicator *progressIndicator;
}

+ (id)sharedInstance;

@property(assign) double progress;

- (IBAction)cancel:(id)sender;

@end

//
//  BCloudSyncWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 2/27/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BCloudSyncWindowController.h"
#import "BCloudDocumentsService.h"


@implementation BCloudSyncWindowController

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id)init {
	if (self = [super initWithWindowNibName:@"BCloudSyncWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	[progressIndicator setUsesThreadedAnimation:YES];
	[progressIndicator setMaxValue:1.0];
	[[self window] setTitle:[NSString stringWithFormat:BLocalizedString(@"%@ Sync...", nil), [[BCloudDocumentsService sharedInstance] serviceLabel]]];
	[[self window] setLevel:NSFloatingWindowLevel];
}

- (double)progress {
	return [progressIndicator doubleValue];
}

- (void)setProgress:(double)progress {
	[progressIndicator setDoubleValue:progress];
}

- (IBAction)showWindow:(id)sender {
	[[self window] center];
	[progressIndicator startAnimation:nil];
	[super showWindow:sender];
}

- (IBAction)cancel:(id)sender {
	[[BCloudDocumentsService sharedInstance] cancelSync:nil];
}

- (void)close {
	[super close];
	[progressIndicator stopAnimation:nil];
}

@end

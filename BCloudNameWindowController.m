//
//  BCloudNameWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 3/2/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BCloudNameWindowController.h"
#import "BCloudDocumentsService.h"


@implementation BCloudNameWindowController

- (id)init {
	if (self = [super initWithWindowNibName:@"BCloudNameWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	NSString *serviceLabel = [[BCloudDocumentsService sharedInstance] serviceLabel];
	[message setStringValue:[NSString stringWithFormat:[message stringValue], serviceLabel, nil]];
	
}

- (NSString *)name {
	return [nameTextField stringValue];
}

- (void)setName:(NSString *)newName {
	[nameTextField setStringValue:newName];
}

- (IBAction)ok:(id)sender {
	[NSApp endSheet:[self window] returnCode:NSOKButton];
	[self close];
}

- (IBAction)cancel:(id)sender {
	[NSApp endSheet:[self window] returnCode:NSCancelButton];
	[self close];
}

@end

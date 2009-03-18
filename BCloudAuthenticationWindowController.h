//
//  BCloudAuthenticationWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 1/30/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BCloudAuthenticationWindowController : NSWindowController {
	IBOutlet NSTextField *heading;
	IBOutlet NSTextField *message;
	IBOutlet NSTextField *usernameTextField;
	IBOutlet NSTextField *passwordTextField;
}

- (id)initWithUsername:(NSString *)aUsername password:(NSString *)aPassword;

@property(retain) NSString *username;
@property(retain) NSString *password;

- (IBAction)createNewAccount:(id)sender;
- (IBAction)foregotPassword:(id)sender;
- (IBAction)learnMore:(id)sender;
- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
	
@end

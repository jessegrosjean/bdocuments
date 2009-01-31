//
//  BDocumentsServiceAuthenticationWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 1/30/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BDocumentsServiceAuthenticationWindowController : NSWindowController {
	IBOutlet NSTextField *usernameTextField;
	IBOutlet NSTextField *passwordTextField;
}

- (id)initWithUsername:(NSString *)aUsername password:(NSString *)aPassword;

@property(retain) NSString *username;
@property(retain) NSString *password;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
	
@end

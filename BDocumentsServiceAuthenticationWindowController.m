//
//  BDocumentsServiceAuthenticationWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 1/30/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BDocumentsServiceAuthenticationWindowController.h"
#import "BDocumentsService.h"


@implementation BDocumentsServiceAuthenticationWindowController

- (id)init {
	return [self initWithUsername:nil password:nil];
}

- (id)initWithUsername:(NSString *)aUsername password:(NSString *)aPassword {
	if (self = [super initWithWindowNibName:@"BDocumentsServiceAuthenticationWindow"]) {
		self.username = aUsername;
		self.password = aPassword;
	}
	return self;
}

- (void)awakeFromNib {
	[heading setStringValue:[NSString stringWithFormat:[heading stringValue], [[BDocumentsService sharedInstance] serviceLabel]]];
}

- (NSString *)username {
	return [usernameTextField stringValue];
}

- (void)setUsername:(NSString *)aUsername {
	[usernameTextField setStringValue:aUsername];
}

- (NSString *)password {
	return [passwordTextField stringValue];
}

- (void)setPassword:(NSString *)aPassword {
	[passwordTextField setStringValue:aPassword];
}

- (IBAction)createNewAccount:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.google.com/accounts/NewAccount"]];
	[self cancel:sender];
}

- (IBAction)foregotPassword:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.google.com/accounts/ForgotPasswd"]];
	[self cancel:sender];
}

- (IBAction)ok:(id)sender {
	[NSApp stopModalWithCode:NSOKButton];
	[self close];
}

- (IBAction)cancel:(id)sender {
	[NSApp stopModalWithCode:NSCancelButton];
	[self close];
}

@end

//
//  SyncedDocumentsControllerDelegate.h
//  BDocuments
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//


@class SyncedDocument;

@interface SyncedDocumentsControllerDelegate : NSObject {
}

+ (id)sharedInstance;
+ (BOOL)isSyncedDocumentURL:(NSURL *)url;
+ (SyncedDocument *)syncedDocumentForEditableFileURL:(NSURL *)url;
+ (NSURL *)editableFileURLForSyncedDocument:(SyncedDocument *)syncedDocument;
+ (NSString *)displayNameForSyncedDocument:(NSURL *)url;
+ (NSString *)syncedDocumentsFolder;
+ (NSString *)syncedDocumentsEditableFilesFolder;
+ (NSDictionary *)localFileAttributes;
	
@end

@interface BSyncedDocumentsNameWindowController : NSWindowController {
	IBOutlet NSTextField *message;
	IBOutlet NSTextField *nameTextField;
}

@property(retain) NSString *name;

- (IBAction)cancel:(id)sender;
- (IBAction)ok:(id)sender;

@end

@interface BSyncedDocumentsAuthenticationWindowController : NSWindowController {
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

@interface BSyncedDocumentsSyncWindowController : NSWindowController {
	IBOutlet NSProgressIndicator *progressIndicator;
}

+ (BSyncedDocumentsSyncWindowController *)sharedInstance;

@property(assign) double progress;

- (IBAction)cancel:(id)sender;

@end

APPKIT_EXTERN NSString *SyncedDocumentsFolderKey;

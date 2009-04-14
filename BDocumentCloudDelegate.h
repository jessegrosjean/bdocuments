//
//  BDocumentCloudDelegate.h
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//


@class BCloudCacheDocument;

@interface BDocumentCloudDelegate : NSObject {
    NSPersistentStoreCoordinator *persistentStoreCoordinator;
    NSManagedObjectModel *managedObjectModel;
    NSManagedObjectContext *managedObjectContext;
}

+ (id)sharedInstance;
+ (NSString *)displayNameForCloudDocument:(NSURL *)url;
+ (BOOL)isCloudDocumentURL:(NSURL *)url;

#pragma mark Local Cache File System

- (NSString *)cloudFolder;
- (NSString *)cloudCacheDirectory;
- (NSDictionary *)localFileAttributes;

#pragma mark Local Cache Database

- (void)initLocalCacheDatabase;
- (NSArray *)cloudCacheDocuments:(NSError **)error;
- (BCloudCacheDocument *)cloudCacheDocumentForID:(NSString *)documentID error:(NSError **)error;
	
@end

@interface BCloudCacheDocument : NSManagedObject {
	BOOL isScheduledForDeleteOnClient;
	BOOL isDeletedFromServer;
	BOOL isScheduledForInsertOnClient;
}

@property(nonatomic, retain) NSString *documentID;
@property(nonatomic, retain) NSString *localName;
@property(nonatomic, retain) NSString *localShadowName;
@property(nonatomic, retain) NSString *localContent;
@property(nonatomic, retain) NSString *localShadowContent;
@property(nonatomic, retain) NSString *localShadowVersion;
@property(nonatomic, assign) BOOL isScheduledForDeleteOnClient;
@property(nonatomic, assign) BOOL isDeletedFromServer;
@property(nonatomic, assign) BOOL isScheduledForInsertOnClient;

- (NSString *)fileSystemPath;
- (NSString *)fileSystemPathForID:(NSString *)documentID name:(NSString *)name;

@end

@interface BCloudNameWindowController : NSWindowController {
	IBOutlet NSTextField *message;
	IBOutlet NSTextField *nameTextField;
}

@property(retain) NSString *name;

- (IBAction)cancel:(id)sender;
- (IBAction)ok:(id)sender;

@end

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

@interface BCloudSyncWindowController : NSWindowController {
	IBOutlet NSProgressIndicator *progressIndicator;
}

+ (BCloudSyncWindowController *)sharedInstance;

@property(assign) double progress;

- (IBAction)cancel:(id)sender;

@end

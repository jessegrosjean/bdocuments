//
//  DocumentsController.h
//  Documents
//
//  Created by Jesse Grosjean on 4/22/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//


@class SyncedDocument;
@class HTTPClient;

@interface SyncedDocumentsController : NSObject {
	NSString *service;
	NSString *serviceLabel;
	NSString *serviceRootURLString;
	NSString *servicePassword;
	NSMutableArray *activeClients;
	NSMutableArray *queuedClients;
	NSInteger totalQueuedClients;
	NSMutableString *conflicts;
	NSString *documentDatabaseDirectory;
    NSManagedObjectModel *managedObjectModel;
    NSManagedObjectContext *managedObjectContext;	    
    NSPersistentStoreCoordinator *persistentStoreCoordinator;
	id syncDelegate;
}

+ (id)sharedInstance;

@property(readonly) NSString *service;
@property(readonly) NSString *serviceLabel;
@property(readonly) NSString *serviceRootURLString;
@property(retain) NSString *serviceUsername;
@property(retain) NSString *servicePassword;
@property(retain) NSString *documentDatabaseDirectory;
@property(readonly) NSManagedObjectModel *managedObjectModel;
@property(readonly) NSManagedObjectContext *managedObjectContext;
@property(readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property(assign) id syncDelegate;

- (NSArray *)documents:(NSError **)error;
- (SyncedDocument *)newDocumentWithValues:(NSDictionary *)values error:(NSError **)error;
- (BOOL)userDeleteDocument:(SyncedDocument *)document error:(NSError **)error;
- (BOOL)deleteDocument:(SyncedDocument *)document error:(NSError **)error;
- (BOOL)save:(NSError **)error;

@property(readonly) BOOL isSyncing;
- (IBAction)beginSync:(id)sender;
- (IBAction)cancelSync:(id)sender;
- (IBAction)toggleAuthentication:(id)sender;
- (void)signOut;

@end

@interface NSObject (DocumentsControllerSyncDelegate)

- (void)documentsControllerSyncNewCredentials:(SyncedDocumentsController *)documentsController;
- (void)documentsControllerWillBeginSync:(SyncedDocumentsController *)documentsController;
- (void)documentsController:(SyncedDocumentsController *)documentsController syncProgress:(CGFloat)progress;
- (void)documentsController:(SyncedDocumentsController *)documentsController syncClient:(HTTPClient *)aClient networkFailed:(NSError *)error;
- (void)documentsController:(SyncedDocumentsController *)documentsController syncClient:(HTTPClient *)aClient failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data;
- (void)documentsControllerDidCompleteSync:(SyncedDocumentsController *)documentsController conflicts:(NSString *)conflicts;

@end

extern NSString *DocumentSharingPort;
extern NSString *DocumentSharingServiceName;
extern NSString *DisableAutoLockWhenSharingDocuments;
extern NSString *DocumentsDefaultEmail;

//
//  BSyncedDocumentService.h
//  BDocuments
//
//  Created by Jesse Grosjean on 2/28/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Blocks/Blocks.h>


@class BCloudDocument;
@class FMDatabase;

@interface BCloudDocumentsService : NSObject {
	NSString *service;
	NSString *serviceLabel;
	NSString *serviceRootURLString;
	NSMutableArray *activeFetchers;
	NSInteger totalActiveFetchers;
	NSMutableString *failedPatches;
	FMDatabase *shadowStorage;
}

+ (id)sharedInstance;
+ (BOOL)isDocumentURLManagedByDocumentsService:(NSURL *)aURL;
+ (NSString *)displayNameForDocumentsServiceDocument:(NSURL *)aURL;

@property(readonly) NSString *service;
@property(readonly) NSString *serviceLabel;
@property(readonly) NSString *serviceRootURLString;

- (IBAction)beginSync:(id)sender;
- (IBAction)cancelSync:(id)sender;
- (IBAction)newCloudDocument:(id)sender;
//- (IBAction)renameCloudDocument:(id)sender;
- (IBAction)deleteCloudDocument:(id)sender;
- (IBAction)browseCloudDocumentsOnline:(id)sender;
- (IBAction)browseCloudDocumentsOnlineAboutPage:(id)sender;
- (IBAction)toggleDocumentsServiceAuthentication:(id)sender;

#pragma mark Local Storage

- (BOOL)initDB;
- (NSArray *)localDocumentIDs;
- (void)scheduleForInsertOnClientWithName:(NSString *)name;
- (void)scheduledForDeleteOnClient:(BCloudDocument *)syncingDocument;
- (void)updateLocalDocumentState:(BCloudDocument *)syncingDocument originalDocumentID:(NSString *)originalDocumentID;
- (void)deleteLocalDocumentStateForDocumentID:(NSString *)documentID;
- (BCloudDocument *)cloudDocumentForID:(NSString *)documentID serverState:(NSDictionary *)serverState;
- (NSString *)onlineDocumentCacheFolder;
	
#pragma mark Server Requests

- (void)GETServerDocuments;
- (void)POSTServerDocument:(BCloudDocument *)syncingDocument;
- (void)GETServerDocument:(BCloudDocument *)syncingDocument;
- (void)POSTServerDocumentEdits:(BCloudDocument *)syncingDocument;
- (void)GETServerDocumentEdits:(BCloudDocument *)syncingDocument;
- (void)DELETEServerDocument:(BCloudDocument *)syncingDocument;
- (void)noteFailedPatches:(NSString *)patches;


@end

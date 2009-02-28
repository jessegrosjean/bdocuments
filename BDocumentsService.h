//
//  BDocumentsService.h
//  BDocuments
//
//  Created by Jesse Grosjean on 1/29/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class BDocumentsHTTPFetcher;
@class BDocumentsServiceHandler;

@interface BDocumentsService : NSObject {
	NSMutableArray *activeHandlers;
	NSInteger totalActiveHandlers;
	NSString *service;
	NSString *serviceLabel;
	NSString *serviceRootURLString;
	NSString *localRootURLString;
	NSString *localDocumentsPath;
	NSString *localNewDocumentsPath;
	NSString *localDocumentShadowsPath;
}

+ (id)sharedInstance;
+ (BOOL)isDocumentURLManagedByDocumentsService:(NSURL *)aURL;
+ (NSString *)displayNameForDocumentsServiceDocument:(NSURL *)aURL;

@property(readonly) NSString *service;
@property(readonly) NSString *serviceLabel;
@property(readonly) NSString *serviceRootURLString;
@property(retain) NSString *serviceUserName;

- (IBAction)beginSync:(id)sender;
- (IBAction)cancelSync:(id)sender;
- (IBAction)openDocumentsService:(id)sender;
- (IBAction)openDocumentsServiceAboutPage:(id)sender;
- (IBAction)toggleDocumentsServiceAuthentication:(id)sender;

- (void)addActiveHandler:(BDocumentsServiceHandler *)aHandler;
- (void)removeActiveHandler:(BDocumentsServiceHandler *)aHandler;

@end

@interface BDocumentsServiceDocument : NSObject {
	NSString *documentID;
	NSString *localVersion;
	NSString *serverVersion;
	NSString *name;
	NSString *content;
	NSString *localShadowContent;
}

- (id)initWithDocumentID:(NSString *)aDocumentID localVersion:(NSString *)aLocalVersion serverVersion:(NSString *)aServerVersion name:(NSString *)aName content:(NSString *)aContent localShadowContent:(NSString *)aLocalShadowContent;

@property(readonly) NSString *documentID;
@property(readonly) NSString *localVersion;
@property(readonly) NSString *serverVersion;
@property(readonly) NSString *name;
@property(readonly) NSString *content;
@property(readonly) NSString *localShadowContent;

- (BOOL)hasLocalEdits;
- (BOOL)hasServerEdits;
- (BOOL)isDeletedFromServer;

@end

@interface BDocumentsServiceHandler : NSObject {
	NSURLRequest *request;
	BDocumentsHTTPFetcher *fetcher;
}

- (id)initWithFetcher:(BDocumentsHTTPFetcher *)aFetcher;

@property(readonly) BDocumentsHTTPFetcher *fetcher;

- (void)cancel;
- (void)handleResponse:(NSData *)data;

@end

@interface BDocumentsServiceGetDocumentsHandler : BDocumentsServiceHandler {
}
@end

@interface BDocumentsServiceGetDocumentHandler : BDocumentsServiceHandler {
}
- (id)initWithDocumentID:(NSString *)documentID;
@end

@interface BDocumentsServicePostLocalEditsHandler : BDocumentsServiceHandler {
	BDocumentsServiceDocument *localDocument;
}
- (id)initWithLocalDocument:(BDocumentsServiceDocument *)aLocalDocument;
@end

@interface BDocumentsServicePostNewDocumentHandler : BDocumentsServiceHandler {
	NSString *newDocumentContent;
	NSString *newDocumentPath;
}
- (id)initWithNewDocumentPath:(NSString *)aNewDocumentPath;
@end

@interface BDocumentsServiceGetServerEditsHandler : BDocumentsServiceHandler {
	BDocumentsServiceDocument *localDocument;
}
- (id)initWithLocalDocument:(BDocumentsServiceDocument *)aLocalDocument;
@end
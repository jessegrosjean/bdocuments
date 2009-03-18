//
//  BSyncedDocument.h
//  BDocuments
//
//  Created by Jesse Grosjean on 2/28/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


enum {
    BSyncResponseUpdateLocal,
    BSyncResponseDeleteLocal
};
typedef NSUInteger BSyncResponseBehavior;

@class BDocument;
@class BCloudDocumentsService;

@interface BCloudDocument : NSObject {
	BDocument *openNSDocument;
	NSString *documentID;
	NSString *name;
	NSString *localContent;
	NSString *localShadowContent;
	NSString *localShadowContentVersion;
	NSString *serverVersion;
	BOOL isScheduledForDeleteOnClient;
	BOOL isDeletedFromServer;
	BOOL isScheduledForInsertOnClient;
	BSyncResponseBehavior syncResponseBehavior;
}

@property(retain) BDocument *openNSDocument;
@property(retain) NSString *documentID;
@property(retain) NSString *name;
@property(retain) NSString *localContent;
@property(retain) NSString *localShadowContent;
@property(retain) NSString *localShadowContentVersion;
@property(retain) NSString *serverVersion;

@property(assign) BOOL isScheduledForDeleteOnClient;
@property(assign) BOOL isDeletedFromServer;
@property(assign) BOOL isScheduledForInsertOnClient;
@property(readonly) BOOL isInsertedFromServer;

- (BOOL)hasLocalEdits;
- (NSDictionary *)localEdits;
- (BOOL)hasServerEdits;
- (void)applyServerEdits:(NSDictionary *)edits;

- (void)scheduleSyncRequest;
- (void)processSyncResponse:(NSData *)data;

@end

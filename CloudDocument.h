//
//  CloudDocument.h
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/9/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//


@class HTTPFetcher;

@interface CloudDocument : NSObject {
	NSString *documentID;
	NSString *localName;
	NSString *localShadowName;
	NSString *localContent;
	NSString *localShadowContent;
	NSString *localShadowVersion;
	NSString *serverVersion;
	BOOL isScheduledForDeleteOnClient;
	BOOL isDeletedFromServer;
	BOOL isScheduledForInsertOnClient;
}

@property(retain) NSString *documentID;
@property(retain) NSString *localName;
@property(retain) NSString *localShadowName;
@property(retain) NSString *localContent;
@property(retain) NSString *localShadowContent;
@property(retain) NSString *localShadowVersion;
@property(retain) NSString *serverVersion;

#pragma mark Edits

- (BOOL)hasLocalEdits;
- (NSDictionary *)localEdits;
- (BOOL)hasServerEdits;

#pragma mark Sync Process

@property(assign) BOOL isScheduledForDeleteOnClient;
@property(assign) BOOL isDeletedFromServer;
@property(assign) BOOL isScheduledForInsertOnClient;
@property(readonly) BOOL isInsertedFromServer;

- (HTTPFetcher *)buildSyncRequest;
- (void)processSyncResponse:(NSData *)data;

@end

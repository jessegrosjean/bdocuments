//
//  Document.h
//  Documents
//
//  Created by Jesse Grosjean on 4/22/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@class HTTPClient;

@interface SyncedDocument : NSManagedObject {
	NSInteger serverVersion;
	BOOL isDeletedFromServer;
}

@property(nonatomic, retain) NSString *name;
@property (readonly) NSString *displayName;
@property(nonatomic, retain) NSDate *created;
@property(nonatomic, retain) NSDate *modified;
@property(nonatomic, retain) NSString *content;
@property(nonatomic, retain) NSString *tags;
@property(nonatomic, retain) NSString *users;

@property(nonatomic, retain) NSString *shadowID;
@property(nonatomic, retain) NSNumber *shadowVersion;
@property(nonatomic, retain) NSString *shadowName;
@property(nonatomic, retain) NSString *shadowContent;
@property(nonatomic, retain) NSString *shadowTags;
@property(nonatomic, retain) NSString *shadowUsers;

@property(nonatomic, assign) NSInteger serverVersion;


#pragma mark Sharing

- (NSDictionary *)toIndexDictionary;
- (NSDictionary *)toDocumentDictionary;

#pragma mark Edits

- (NSDictionary *)localEdits;
- (BOOL)hasServerEdits;

#pragma mark Sync Process

@property(readonly) BOOL isServerDocument;
@property(assign) BOOL isDeletedFromServer;
@property(nonatomic, retain) NSNumber *userDeleted;

@property(readonly) BOOL isInsertedFromServer;

- (HTTPClient *)buildSyncRequest;
- (void)processSyncResponse:(NSData *)data;

@end
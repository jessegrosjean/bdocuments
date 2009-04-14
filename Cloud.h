//
//  Cloud.h
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/8/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import <SystemConfiguration/SCNetworkReachability.h>


@class CloudDocument;
@class HTTPFetcher;

@interface Cloud : NSObject {
	NSString *service;
	NSString *serviceLabel;
	NSString *serviceRootURLString;
	NSString *servicePassword;
	NSMutableArray *activeFetchers;
	NSMutableArray *queuedFetchers;
	NSInteger totalQueuedFetchers;
	NSMutableString *conflicts;
	id delegate;
}

+ (id)sharedInstance;
//+ (BOOL)hasActiveWiFiConnection;
//+ (BOOL)hasNetworkConnection;

@property(readonly) NSString *service;
@property(readonly) NSString *serviceLabel;
@property(readonly) NSString *serviceRootURLString;
@property(retain) NSString *serviceUsername;
@property(retain) NSString *servicePassword;
@property(assign) id delegate;

- (IBAction)beginSync:(id)sender;
@property(readonly) BOOL isSyncing;
- (IBAction)cancelSync:(id)sender;
- (IBAction)toggleAuthentication:(id)sender;

- (void)signOut;

@end

@interface NSObject (CloudDelegate)

- (void)cloudSyncNewCredentials:(Cloud *)cloud;
- (void)cloudWillBeginSync:(Cloud *)cloud;
- (NSArray *)cloudSyncLocalDocuments;
- (BOOL)cloudSyncUpdateOrInsertLocalDocument:(CloudDocument *)aDocument originalDocumentID:(NSString *)originalDocumentID;
- (BOOL)cloudSyncDeleteLocalDocument:(NSString *)documentID;
- (void)cloudSyncProgress:(CGFloat)progress cloud:(Cloud *)cloud;
- (void)cloudSyncFetcher:(HTTPFetcher *)aFetcher networkFailed:(NSError *)error;
- (void)cloudSyncFetcher:(HTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data;
- (void)cloudDidCompleteSync:(Cloud *)cloud conflicts:(NSString *)conflicts;

@end
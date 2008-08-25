//
//  BDocument.h
//  BDocuments
//
//  Created by Jesse Grosjean on 10/16/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface BDocument : NSDocument {
	NSMutableDictionary *documentUserDefaults;
	BOOL fromExternal;
	NSString *externalDisplayName;
	NSAppleEventDescriptor *externalSender;
	NSAppleEventDescriptor *externalToken;
}

#pragma mark Document Defaults Repository

+ (NSDictionary *)loadDocumentUserDefaultsForDocumentURL:(NSURL *)documentURL;
+ (BOOL)storeDocumentUserDefaults:(NSDictionary *)documentUserDefaults forDocumentURL:(NSURL *)documentURL;
+ (BOOL)synchronizeDocumentUserDefaultsRepository;

#pragma mark Document User Defaults

@property(readonly) NSDictionary *defaultDocumentUserDefaults;
@property(readonly) NSDictionary *documentUserDefaults;
- (id)documentUserDefaultForKey:(NSString *)key;
- (void)setDocumentUserDefault:(id)documentUserDefault forKey:(NSString *)key;
- (void)addDocumentUserDefaultsFromDictionary:(NSDictionary *)newDocumentUserDefaults;

#pragma mark ODB Editor Suite support

@property(readonly) BOOL fromExternal;
@property(readonly) NSAppleEventDescriptor *externalSender;
@property(readonly) NSAppleEventDescriptor *externalToken;

#pragma mark External File Modificed Notification

- (void)fileWasChangedExternallyByAnotherApplication:(NSDate *)newModificationDate;

@end

APPKIT_EXTERN NSString *BDocumentUserDefaultsWillSynchronizeNotification;
APPKIT_EXTERN NSString *BDocumentUserDefaultsDidSynchronizeNotification;
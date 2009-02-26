//
//  BDocuments.h
//  BDocuments
//
//  Created by Jesse Grosjean on 9/7/07.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Blocks/Blocks.h>
#import "BDocumentController.h"
#import "BDocument.h"
#import "BDocumentWindowController.h"


@interface NSApplication (BDocumentsAdditions)

@property(readonly) id currentDocument;
@property(readonly) id currentDocumentWindowController;

@end


@interface NSFileManager (BDocumentsAdditions)

+ (NSArray*)allKeysAtPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (void)setData:(NSData*)data forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (void)setObject:(id)obj forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (void)setString:(NSString*)str forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (NSMutableData*)dataForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (id)objectForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
+ (id)stringForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk;
	
@property(readonly) NSString *processesCachesFolder;
@property(readonly) NSString *processesApplicationSupportFolder;
- (NSString *)findSystemFolderType:(NSInteger)folderType forDomain:(NSInteger)domain;
- (BOOL)createDirectoriesForPath:(NSString *)path;

@end

@interface NSString (BDocumentsAdditions)

- (NSComparisonResult)naturalCompare:(NSString *)aString;
- (NSString *)stringByURLEncodingStringParameter;

@end

APPKIT_EXTERN NSString *BDocumentControllerDocumentAddedNotification;
APPKIT_EXTERN NSString *BDocumentControllerDocumentRemovedNotification;

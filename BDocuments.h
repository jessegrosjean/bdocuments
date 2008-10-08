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

@property(readonly) NSString *processesCachesFolder;
@property(readonly) NSString *processesApplicationSupportFolder;
- (NSString *)findSystemFolderType:(NSInteger)folderType forDomain:(NSInteger)domain;
- (BOOL)createDirectoriesForPath:(NSString *)path;

@end

@interface NSString (BDocumentsAdditions)

- (NSComparisonResult)naturalCompare:(NSString *)aString;

@end
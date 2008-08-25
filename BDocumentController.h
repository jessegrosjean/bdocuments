//
//  BDocumentController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 9/7/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "BDocuments.h"


@protocol BDocumentControllerDelegate <NSObject>
@property(readonly) NSString *defaultType;
@end

@interface BDocumentController : NSDocumentController {
	NSMutableArray *documentTypeDeclarations;
	NSMutableDictionary *documentTypeDeclarationsToPlugins;
	BOOL applicationMayBeTerminating;
}

#pragma mark Class Methods

+ (id)sharedInstance;

#pragma mark Loading Document Workspace

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender;

@end

APPKIT_EXTERN NSString *BDocumentsAutosavingDelayKey;
APPKIT_EXTERN NSString *BDocumentsLastDocumentWorkspaceKey;
APPKIT_EXTERN NSString *BDocumentsReopenLastDocumentWorkspaceKey;
APPKIT_EXTERN NSString *BAutomaticallySaveDocumentsWhenQuiting;

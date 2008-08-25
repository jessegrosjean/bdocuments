//
//  BDocumentWindowController.h
//  BDocuments
//
//  Created by Jesse Grosjean on 10/16/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class BDocumentWindowController;
@class BDocument;

@protocol BDocumentWindowControllerFactory <NSObject>
- (BDocumentWindowController *)createDocumentWindowControllerForDocument:(BDocument *)document;
@end

@interface BDocumentWindowController : NSWindowController {
	NSString *windowControllerUserDefaultsKey;
	NSString *savedWindowControllerUserDefaultsKey;
}

#pragma mark Init

- (id)initWithWindowControllerUserDefaultsKey:(NSString *)newDefaultsKey;
- (id)initWithWindowControllerUserDefaultsKey:(NSString *)newDefaultsKey nibName:(NSString *)nibName;

#pragma mark WindowController Use Defaults

@property(retain) NSString *windowControllerUserDefaultsKey;
- (id)windowControllerUserDefaultForKey:(NSString *)key;
- (void)setWindowControllerUserDefault:(id)newUserInfo forKey:(NSString *)key;
- (void)readWindowControllerUserDefaults;
- (void)writeWindowControllerUserDefaults;

#pragma mark Printing

- (NSView *)printViewForPrintInfo:(NSPrintInfo *)printInfo;
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError **)outError;

@end

APPKIT_EXTERN NSString *BWindowFrameKey;
APPKIT_EXTERN NSString *BWindowIsMainKey;
APPKIT_EXTERN NSString *BWindowIsMiniturizedKey;
APPKIT_EXTERN NSString *BDocumentsWindowControllersDefaultsKey;
APPKIT_EXTERN NSString *BNumberPagesWhenPrinting;
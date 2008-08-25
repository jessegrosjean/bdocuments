//
//  BDocumentWindowController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 10/16/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "BDocumentWindowController.h"
#import "BDocument.h"


@implementation BDocumentWindowController

#pragma mark Class Methods

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], BNumberPagesWhenPrinting,
		nil]];
}

#pragma mark Init

- (id)initWithWindowControllerUserDefaultsKey:(NSString *)newDefaultsKey {
    if (self = [self initWithWindowControllerUserDefaultsKey:newDefaultsKey nibName:nil]) {
    }
    return self;
}

- (id)initWithWindowControllerUserDefaultsKey:(NSString *)newDefaultsKey nibName:(NSString *)nibName {
    if (self = [super initWithWindowNibName:nibName]) {
		savedWindowControllerUserDefaultsKey = newDefaultsKey;
		if (!savedWindowControllerUserDefaultsKey) {
			CFUUIDRef uuid = CFUUIDCreate(NULL);
			savedWindowControllerUserDefaultsKey = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
			CFRelease(uuid);
		}
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(writeWindowControllerUserDefaults) name:BDocumentUserDefaultsWillSynchronizeNotification object:nil];
    }
    return self;
}

#pragma mark awake from nib like methods

- (void)awakeFromNib {
	[self setWindowControllerUserDefaultsKey:savedWindowControllerUserDefaultsKey];
}

#pragma mark WindowController Use Defaults

- (NSString *)windowControllerUserDefaultsKey {
	return windowControllerUserDefaultsKey;
}

- (void)setWindowControllerUserDefaultsKey:(NSString *)newDefaultsKey {
	windowControllerUserDefaultsKey = newDefaultsKey;
	
	if (windowControllerUserDefaultsKey) {
		[self readWindowControllerUserDefaults];
	}
}

- (NSMutableDictionary *)windowControllerUserDefaults {
	return [[[self document] documentUserDefaultForKey:BDocumentsWindowControllersDefaultsKey] objectForKey:[self windowControllerUserDefaultsKey]];
}

- (id)windowControllerUserDefaultForKey:(NSString *)key {
	return [[self windowControllerUserDefaults] objectForKey:key];
}

- (void)setWindowControllerUserDefault:(id)newDefault forKey:(NSString *)key {
	if ([self windowControllerUserDefaultsKey]) {
		NSMutableDictionary *windowControllerState = [[[self document] documentUserDefaultForKey:BDocumentsWindowControllersDefaultsKey] objectForKey:windowControllerUserDefaultsKey];
		
		if (newDefault) {
			[windowControllerState setObject:newDefault forKey:key];
		} else {
			[windowControllerState removeObjectForKey:key];
		}
	}
}

- (void)readWindowControllerUserDefaults {
	BDocument *document = [self document];
	NSMutableDictionary *windowControllersState = [document documentUserDefaultForKey:BDocumentsWindowControllersDefaultsKey];
	
	if (!windowControllersState) {
		windowControllersState = [NSMutableDictionary dictionary];
		[document setDocumentUserDefault:windowControllersState forKey:BDocumentsWindowControllersDefaultsKey];
	}
	
	NSMutableDictionary *windowControllerState = [windowControllersState objectForKey:windowControllerUserDefaultsKey];
	if (!windowControllerState) {
		windowControllerState = [NSMutableDictionary dictionary];
		[windowControllersState setObject:windowControllerState forKey:windowControllerUserDefaultsKey];
	}
	
	[self setWindowControllerUserDefault:NSStringFromClass([self class]) forKey:@"class"];
	
	NSValue *windowFrameValue = [[self windowControllerUserDefaultForKey:BWindowFrameKey] copy];
	NSNumber *windowIsMiniturized = [[self windowControllerUserDefaultForKey:BWindowIsMiniturizedKey] copy];
	NSNumber *windowIsMain = [[self windowControllerUserDefaultForKey:BWindowIsMainKey] copy];		
	
	if (windowFrameValue) {
		[self setShouldCascadeWindows:NO];
		[[self window] setFrame:[windowFrameValue rectValue] display:NO];
	}
	
	if (windowIsMiniturized && [windowIsMiniturized boolValue]) {
		[[self window] performSelector:@selector(performMiniaturize:) withObject:self afterDelay:0];
	}
	
	if (windowIsMain && [windowIsMain boolValue]) {
		[[self window] performSelector:@selector(makeMainWindow) withObject:nil afterDelay:0];
	}	
}

- (void)writeWindowControllerUserDefaults {
	[self setWindowControllerUserDefault:[NSValue valueWithRect:[[self window] frame]] forKey:BWindowFrameKey];
	[self setWindowControllerUserDefault:[NSNumber numberWithBool:[[self window] isMiniaturized]] forKey:BWindowIsMiniturizedKey];
	[self setWindowControllerUserDefault:[NSNumber numberWithBool:[[self window] isMainWindow]] forKey:BWindowIsMainKey];
}

- (void)setDocument:(NSDocument *)newDocument {
	if (!newDocument) {
		[self writeWindowControllerUserDefaults];
	}
	[super setDocument:newDocument];
}

#pragma mark Printing

- (NSView *)printViewForPrintInfo:(NSPrintInfo *)printInfo {
	return [[self window] contentView];
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError **)outError {
	NSPrintInfo *printInfo = [[[self document] printInfo] copy];
	[[printInfo dictionary] addEntriesFromDictionary:printSettings];
	[[printInfo dictionary] setValue:[[NSUserDefaults standardUserDefaults] objectForKey:BNumberPagesWhenPrinting] forKey:NSPrintHeaderAndFooter];
	NSView *printView = [self printViewForPrintInfo:printInfo];
	NSPrintOperation *printOperation = [NSPrintOperation printOperationWithView:printView printInfo:printInfo];
	[printOperation setJobTitle:[[self document] displayName]];
	[printOperation setShowPanels:YES];
	return printOperation;
}

@end

NSString *BWindowFrameKey = @"BWindowFrameKey";
NSString *BWindowIsMainKey = @"BWindowIsMainKey";
NSString *BWindowIsMiniturizedKey = @"BWindowIsMiniturizedKey";
NSString *BDocumentsWindowControllersDefaultsKey = @"BDocumentsWindowControllersDefaultsKey";
NSString *BNumberPagesWhenPrinting = @"BNumberPagesWhenPrinting";
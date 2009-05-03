//
//  BDocumentController.m
//  BDocuments
//
//  Created by Jesse Grosjean on 9/7/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "BDocumentController.h"
#import "BUserInterfaceController.h"
#import <objc/runtime.h>
#import "SyncedDocumentsController.h"
#import "SyncedDocumentsControllerDelegate.h"


@implementation BDocumentController

#pragma mark Class Methods

+ (void)initialize {				
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithBool:YES], BDocumentsReopenLastDocumentWorkspaceKey,
		[NSNumber numberWithInteger:5], BDocumentsAutosavingDelayKey,
		nil]];
}

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
		BLogAssert(sharedInstance == [NSDocumentController sharedDocumentController], @"BDocumentController must be set as standard document controller.");
    }
    return sharedInstance;
}

#pragma mark Init

- (id)init {
	if (self = [super init]) {
		[self bind:@"autosavingDelay" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.BDocumentsAutosavingDelayKey" options:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeMainNotification:) name:NSWindowDidBecomeMainNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillCloseNotification:) name:NSWindowWillCloseNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActiveNotification:) name:NSApplicationDidBecomeActiveNotification object:[NSApplication sharedApplication]];
		
	}
	return self;
}

#pragma mark Dynamic Document types

- (NSArray *)documentTypeDeclarations {
	if (!documentTypeDeclarations) {		
		documentTypeDeclarations = [[NSMutableArray alloc] init];
		documentTypeDeclarationsToPlugins = [[NSMutableDictionary alloc] init];
		
		for (BPlugin *each in [[BExtensionRegistry sharedInstance] plugins]) {
			for (NSDictionary *eachBundleDocumentType in [[[each bundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"]) {
				[documentTypeDeclarations addObject:eachBundleDocumentType];
				[documentTypeDeclarationsToPlugins setObject:each forKey:eachBundleDocumentType];
			}
		}
	}
	
	return documentTypeDeclarations;
}

- (NSArray *)documentClassNames {
	NSMutableArray *documentClassNames = [[super documentClassNames] mutableCopy];
	
	for (NSDictionary *each in [self documentTypeDeclarations]) {
		NSString *documentClassName = [each objectForKey:@"NSDocumentClass"];
		
		if (documentClassName) {
			if (![documentClassNames containsObject:each]) {
				[documentClassNames addObject:documentClassName];
			}
		} else {
			BLogWarning([NSString stringWithFormat:@"Failed to find NSDocumentClass key in documentType dictionary %@", each]);
		}
	}
		
	return documentClassNames;
}

- (Class)documentClassForType:(NSString *)documentTypeName {
	for (NSDictionary *each in [self documentTypeDeclarations]) {
		NSString *eachDocumentTypeName = [each objectForKey:@"CFBundleTypeName"];
		
		if (eachDocumentTypeName) {
			if ([eachDocumentTypeName isEqualToString:documentTypeName]) {
				BPlugin *plugin = [documentTypeDeclarationsToPlugins objectForKey:each];
				Class pluginDocumentClass = [plugin classNamed:[each objectForKey:@"NSDocumentClass"]];
				
				if (pluginDocumentClass) {
					Class defaultDocumentClass = [super documentClassForType:documentTypeName];
					
					if (!defaultDocumentClass) {
						return pluginDocumentClass;
					} else if (pluginDocumentClass != defaultDocumentClass) {
						BLogInfo([NSString stringWithFormat:@"Main bundle plist and plugin declare difference document classes for the same document type %@, will use class declared in main bundle plist", documentTypeName]);
						return defaultDocumentClass;
					}
				}
			}
		} else {
			BLogWarning([NSString stringWithFormat:@"Failed to find CFBundleTypeName key in documentType dictionary %@", each]);
		}
	}
	
	return [super documentClassForType:documentTypeName];
}

- (NSString *)defaultType {
	NSString *documentTypeName = [super defaultType];
	
	for (BConfigurationElement *each in [[BExtensionRegistry sharedInstance] configurationElementsFor:@"com.blocks.BDocuments.documentControllerDelegate"]) {
		id <BDocumentControllerDelegate> documentControllerDelegate = [each createExecutableExtensionFromAttribute:@"class" conformingToClass:nil conformingToProtocol:@protocol(BDocumentControllerDelegate) respondingToSelectors:nil];
		NSString *overrideDocumentTypeName = [documentControllerDelegate defaultType];
		if (overrideDocumentTypeName) {
			return overrideDocumentTypeName;
		}
	}
		
	if (documentTypeName == nil || [documentTypeName isEqualToString:@"WildcardDocumentType"]) {
		for (NSDictionary *each in [self documentTypeDeclarations]) {
			NSString *eachDocumentTypeName = [each objectForKey:@"CFBundleTypeName"];
			if (eachDocumentTypeName) {
				return eachDocumentTypeName;
			}
		}
	}
	
	return documentTypeName;
}


- (NSString *)displayNameForType:(NSString *)documentTypeName {
	NSString *displayNameForType = [super displayNameForType:documentTypeName];
	
	if ([displayNameForType isEqualToString:documentTypeName]) {
		for (NSDictionary *each in [self documentTypeDeclarations]) {
			NSString *eachDocumentTypeName = [each objectForKey:@"CFBundleTypeName"];
			if (eachDocumentTypeName) {
				if ([eachDocumentTypeName isEqualToString:documentTypeName]) {
					NSString *typeName = [each objectForKey:@"NSTypeName"];
					if (typeName) {
						return typeName;
					}
				}
			}
		}
	}
	
	return displayNameForType;
}

- (NSArray *)fileExtensionsFromType:(NSString *)documentTypeName {
	NSMutableArray *fileExtensionsFromType = [[super fileExtensionsFromType:documentTypeName] mutableCopy];
	
	for (NSDictionary *each in [self documentTypeDeclarations]) {
		NSString *eachDocumentTypeName = [each objectForKey:@"CFBundleTypeName"];
		
		if (eachDocumentTypeName) {
			if ([eachDocumentTypeName isEqualToString:documentTypeName]) {
				NSMutableArray *fileExtensions = [[each objectForKey:@"CFBundleTypeExtensions"] mutableCopy];
				if (fileExtensions) {
					[fileExtensions removeObjectsInArray:fileExtensionsFromType];
					[fileExtensionsFromType addObjectsFromArray:fileExtensions];
				}
			}
		}
	}
		
	return fileExtensionsFromType;
}

- (NSString *)typeFromFileExtension:(NSString *)fileExtensionOrHFSFileType {
	NSString *documentTypeName = [super typeFromFileExtension:fileExtensionOrHFSFileType];
	
	if (!documentTypeName || [documentTypeName isEqualToString:@"WildcardDocumentType"]) {
		for (NSDictionary *each in [self documentTypeDeclarations]) {
			NSString *eachDocumentTypeName = [each objectForKey:@"CFBundleTypeName"];
			
			if (eachDocumentTypeName) {
				NSArray *typeExtensions = [each objectForKey:@"CFBundleTypeExtensions"];
				if ([typeExtensions containsObject:fileExtensionOrHFSFileType]) {
					return eachDocumentTypeName;
				}
			}
		}
	}
	
	return documentTypeName;
}

#pragma mark Notifications

- (void)windowDidBecomeMainNotification:(NSNotification *)notification {
	NSWindow *window = [notification object];
	NSWindowController *windowController = [window windowController];
	NSDocument *document = [windowController document];
	
	if (document) {
		[NSApp setValue:document forKey:@"currentDocument"];
		[NSApp setValue:windowController forKey:@"currentDocumentWindowController"];
		[document checkForModificationOfFileOnDisk];
	}
}

- (void)windowWillCloseNotification:(NSNotification *)notification {
	NSWindow *window = [notification object];
	
	if (window == [[NSApp currentDocumentWindowController] window]) {
		[NSApp setValue:nil forKey:@"currentDocumentWindowController"];
		[NSApp setValue:nil forKey:@"currentDocument"];
	}
}

- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification {
	[[NSApp currentDocument] checkForModificationOfFileOnDisk];
}

#pragma mark Lifecycle Callback

- (void)applicationLaunching {
}

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BUserInterface.menus.main.file.openRecent"] setDelegate:self];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		[menu removeItem:each];
	}

	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	
	for (NSURL *each in [self recentDocumentURLs]) {
		NSString *path = [each path];
		NSString *title = nil;
		
//		if ([BCloudDocumentsService isCloudDocumentURL:each]) {
//			title = [[BCloudDocumentsService displayNameForCloudDocument:each] stringByAppendingFormat:@"—%@", [[BCloudDocumentsService sharedInstance] serviceLabel]];
//		} else {
			title = [path lastPathComponent];
//		}
		NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(openRecentDocument:) keyEquivalent:@""];
		[eachMenuItem setRepresentedObject:each];
		NSImage *icon = [workspace iconForFile:path];
		[icon setSize:NSMakeSize(16, 16)];
		[eachMenuItem setImage:icon];
		[menu addItem:eachMenuItem];
	}
	
	if ([menu numberOfItems] > 0) {
		[menu addItem:[NSMenuItem separatorItem]];
	}
	
	[menu addItemWithTitle:BLocalizedString(@"Clear Menu", nil) action:@selector(clearRecentDocuments:) keyEquivalent:@""];	
}

- (void)openRecentDocument:(NSMenuItem *)aMenuItem {
	NSError *error = nil;
	if (![self openDocumentWithContentsOfURL:[aMenuItem representedObject] display:YES error:&error]) {
		if (error) {
			[self presentError:error];
		} else {
			NSBeep();
		}
	}
}

- (void)applicationMayTerminateNotification {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	applicationMayBeTerminating = YES;
	
	BOOL automaticallySaveDocumentsWhenQuiting = [defaults boolForKey:BAutomaticallySaveDocumentsWhenQuiting];
	
	for (BDocument *each in [self documents]) {
		if ([each fileURL]) {
			if (automaticallySaveDocumentsWhenQuiting) [each saveDocument:nil];
			[BDocument storeDocumentUserDefaults:[each documentUserDefaults] forDocumentURL:[each fileURL]];
		}
	}
	
	if ([[self documents] count] > 0) {
		[defaults setObject:[NSArray array] forKey:BDocumentsLastDocumentWorkspaceKey];
	}
}

- (void)applicationCancledTerminateNotification {	
	if ([[self documents] count] > 0) {
		[[NSUserDefaults standardUserDefaults] setObject:[NSArray array] forKey:BDocumentsLastDocumentWorkspaceKey];
	}
	applicationMayBeTerminating = NO;
}

- (void)applicationWillTerminate {
	[BDocument synchronizeDocumentUserDefaultsRepository];
}

#pragma mark Loading Document Workspace

- (void)removeRecentDocumentURL:(NSURL *)removedURL {
	NSArray *recentDocumentURLs = [self recentDocumentURLs];
	[self clearRecentDocuments:nil];
	for (NSURL *each in recentDocumentURLs) {
		if (![each isEqual:removedURL]) {
			[self noteNewRecentDocumentURL:each];
		}
	}
}

- (void)addDocument:(NSDocument *)document {
	[super addDocument:document];
	[[NSNotificationCenter defaultCenter] postNotificationName:BDocumentControllerDocumentAddedNotification object:self userInfo:[NSDictionary dictionaryWithObject:document forKey:@"document"]];
}

- (void)removeDocument:(NSDocument *)document {
	if (applicationMayBeTerminating || [[self documents] count] == 1) {
		NSString *path = [[document fileURL] path];
		if (path) {
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			[defaults setObject:[[defaults valueForKey:BDocumentsLastDocumentWorkspaceKey] arrayByAddingObject:path] forKey:BDocumentsLastDocumentWorkspaceKey];
			if ([[self documents] count] == 1) {
				[defaults synchronize];
			}
		}
	}
	[super removeDocument:document];	
	[[NSNotificationCenter defaultCenter] postNotificationName:BDocumentControllerDocumentRemovedNotification object:self userInfo:[NSDictionary dictionaryWithObject:document forKey:@"document"]];
}

- (void)openLastDocumentWorkspace {
	NSError *error = nil;
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if ([userDefaults boolForKey:BDocumentsReopenLastDocumentWorkspaceKey]) {
		for (NSString *each in [userDefaults objectForKey:BDocumentsLastDocumentWorkspaceKey]) {
			if ([fileManager fileExistsAtPath:each]) {
				if (![self openDocumentWithContentsOfURL:[NSURL fileURLWithPath:each] display:YES error:&error]) {
					[self presentError:error];
				}
			}
		}
		
		if ([[self documents] count] == 0) {
			NSURL *lastDocumentURL = [[self recentDocumentURLs] lastObject];
			if ([fileManager fileExistsAtPath:[lastDocumentURL path]]) {
				if (![self openDocumentWithContentsOfURL:lastDocumentURL display:YES error:&error]) {
					[self presentError:error];
				}
			}
		}
	}
	
	[[NSUserDefaults standardUserDefaults] setObject:[NSArray array] forKey:BDocumentsLastDocumentWorkspaceKey];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
	[self openLastDocumentWorkspace];
	
	if ([[self documents] count] == 0) {
		return YES;
	}
	
	return NO;
}

@end

@implementation NSApplication (BDocumentControllerMethodReplacements)

+ (void)load {
    if (self == [NSApplication class]) {
		[self replaceMethod:@selector(_handleAEOpen:) withMethod:@selector(BDocumentController_handleAEOpen:)];
		[self replaceMethod:@selector(_handleAEQuitWithActivating:documentSaving:) withMethod:@selector(BDocumentController_handleAEQuitWithActivating:documentSaving:)];
    }
}

- (void)BDocumentController_handleAEOpen:(NSAppleEventDescriptor *)event {
	NSParameterAssert(_cmd == @selector(_handleAEOpen:));
	[self BDocumentController_handleAEOpen:event];
	
	// Normally applications are not asked to applicationShouldOpenUntitledFile when opened as a login item. But if there is a saved
	// workspace we want to open that. So here were are checking for keyAELaunchedAsLogInItem and if found give the (our subclass) 
	// document controller the chance to open last workspace.
	NSAppleEventDescriptor *currentEvent = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];
	if ([[[NSDocumentController sharedDocumentController] documents] count] == 0 && [[currentEvent paramDescriptorForKeyword:keyAEPropData] typeCodeValue] == keyAELaunchedAsLogInItem) {
		[[NSDocumentController sharedDocumentController] openLastDocumentWorkspace];
	}
}

- (short)BDocumentController_handleAEQuitWithActivating:(BOOL)fp8 documentSaving:(unsigned int)fp12 {
	// Hack, goal is to call applicationMayTerminateNotification when application starts to quit. Normally this can be done by overriding
	// [App terminate:], but that doesn't seem to get called when app is quit via applescript, so in that case we need to use this method.
	NSParameterAssert(_cmd == @selector(_handleAEQuitWithActivating:documentSaving:));
	[[BDocumentController sharedInstance] applicationMayTerminateNotification];
	return [self BDocumentController_handleAEQuitWithActivating:fp8 documentSaving:fp12];
}

@end

NSString *BDocumentsAutosavingDelayKey = @"BDocumentsAutosavingDelayKey";
NSString *BDocumentsLastDocumentWorkspaceKey = @"BDocumentsLastDocumentWorkspaceKey";
NSString *BDocumentsReopenLastDocumentWorkspaceKey = @"BDocumentsReopenLastDocumentWorkspaceKey";
NSString *BAutomaticallySaveDocumentsWhenQuiting = @"BAutomaticallySaveDocumentsWhenQuiting";
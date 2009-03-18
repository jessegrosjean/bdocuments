//
//  BSyncedDocumentService.m
//  BDocuments
//
//  Created by Jesse Grosjean on 2/28/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BCloudDocumentsService.h"
#import "BDocuments.h"
#import "BCloudDocument.h"
#import "BCloudHTTPFetcher.h"
#import "NSString+SBJSON.h"
#import "BCloudAuthenticationWindowController.h"
#import "BCloudSyncWindowController.h"
#import "BCloudNameWindowController.h"
#import "FMDatabase.h"


@interface BCloudDocumentsService (BDocumentsPrivate)

- (void)beginActiveFetcher:(BCloudHTTPFetcher *)aFetcher;
- (void)endActiveFetcher:(BCloudHTTPFetcher *)aFetcher;

@end
	
@implementation BCloudDocumentsService

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

+ (BOOL)isDocumentURLScheduledForInsertByDocumentsService:(NSURL *)aURL {
	return [[[[aURL path] lastPathComponent] stringByDeletingPathExtension] rangeOfString:@"NewDocument"].location == 0;
}

+ (BOOL)isDocumentURLManagedByDocumentsService:(NSURL *)aURL {
	if ([self isDocumentURLScheduledForInsertByDocumentsService:aURL]) {
		return YES;
	}
	NSString *path = [aURL path];
	NSString *name = [NSFileManager stringForKey:@"BDocumentName" atPath:path traverseLink:YES];
	NSString *version = [NSFileManager stringForKey:@"BDocumentVersion" atPath:path traverseLink:YES];
	return [version length] > 0 && [name length] > 0;
}

+ (BOOL)isDocumentURLScheduledForDeleteByDocumentsService:(NSURL *)aURL {
	return [[NSFileManager stringForKey:@"BDocumentScheduledForDelete" atPath:[aURL path] traverseLink:YES] isEqualToString:@"YES"];
}

+ (NSString *)displayNameForDocumentsServiceDocument:(NSURL *)aURL {
	NSString *path = [aURL path];
	NSString *name = [NSFileManager stringForKey:@"BDocumentName" atPath:path traverseLink:YES];
	return name;
}

- (id)init {
	if (self = [super init]) {
		service = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsService"] retain];
		serviceLabel = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsServiceLabel"] retain];
		serviceRootURLString = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsServiceURL"] retain];
		activeFetchers = [[NSMutableArray alloc] init];
		failedPatches = [[NSMutableString alloc] init];
		[self initDB];
	}
	return self;
}

@synthesize service;
@synthesize serviceLabel;
@synthesize serviceRootURLString;

- (NSString *)serviceUserName {
	return [[NSUserDefaults standardUserDefaults] stringForKey:@"BDocumentsServiceUsername"];
}

- (void)setServiceUserName:(NSString *)aUserName {
	if (aUserName) {
		[[NSUserDefaults standardUserDefaults] setObject:aUserName forKey:@"BDocumentsServiceUsername"];
	} else {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BDocumentsServiceUsername"];
	}
}

- (IBAction)beginSync:(id)sender {
	totalActiveFetchers = 0;
	[failedPatches replaceCharactersInRange:NSMakeRange(0, [failedPatches length]) withString:@""];
	
	for (BDocument *each in [[NSDocumentController sharedDocumentController] documents]) {
		if (each.fromDocumentsService) {
			[each saveDocument:nil];
		}
	}

	[self GETServerDocuments];
}

- (IBAction)cancelSync:(id)sender {
	for (BCloudHTTPFetcher *eachFetcher in [[activeFetchers copy] autorelease]) {
		[self endActiveFetcher:eachFetcher];
	}
}

- (IBAction)newCloudDocument:(id)sender {
	BCloudNameWindowController *nameWindowController = [[BCloudNameWindowController alloc] init];
	[[nameWindowController window] center];
	NSInteger result = [NSApp runModalForWindow:[nameWindowController window]];
	
	if (result == NSOKButton) {
		[self scheduleForInsertOnClientWithName:nameWindowController.name];
	}
}

/*
- (IBAction)renameCloudDocument:(id)sender {
	BDocumentWindowController *documentWindowController = [NSApp currentDocumentWindowController];
	BCloudNameWindowController *nameWindowController = [[BCloudNameWindowController alloc] init];
	NSDictionary *contextInfo = [NSDictionary dictionaryWithObjectsAndKeys:documentWindowController, @"documentWindowController", nameWindowController, @"nameWindowController", nil];
	[NSApp beginSheet:[nameWindowController window] modalForWindow:[documentWindowController window] modalDelegate:self didEndSelector:@selector(renameSheetDidEnd:returnCode:contextInfo:) contextInfo:contextInfo];
}

- (void)renameSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(NSDictionary *)contextInfo {
	if (returnCode == NSOKButton) {
		BDocumentWindowController *documentWindowController = [contextInfo objectForKey:@"documentWindowController"];
		BCloudNameWindowController *nameWindowController = [contextInfo objectForKey:@"nameWindowController"];
		BDocument *document = [documentWindowController document];
		NSString *documentID = [document documentsServiceID];
		BCloudDocument *cloudDocument = [self cloudDocumentForID:documentID serverState:nil];
		cloudDocument.name = nameWindowController.name;
		[self updateLocalDocumentState:cloudDocument];
	}
}
*/

- (IBAction)deleteCloudDocument:(id)sender {
	BDocumentWindowController *windowController = [NSApp currentDocumentWindowController];
	NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"Are you sure that you want to delete this document from %@?", nil), self.serviceLabel];
	NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"If you choose \"Delete\" this document will be deleted from your computer and then deleted from %@ next time you sync.", nil), self.serviceLabel];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Delete", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
	[alert beginSheetModalForWindow:[windowController window] modalDelegate:self didEndSelector:@selector(deleteCloudDocumentDidEnd:returnCode:contextInfo:) contextInfo:windowController];
}

- (void)deleteCloudDocumentDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(BDocumentWindowController *)windowController {
	if (returnCode == NSOKButton) {
		BDocument *document = [windowController document];
		NSString *documentID = [document documentsServiceID];
		[document saveDocument:nil];
		[document close];
		[self scheduledForDeleteOnClient:[self cloudDocumentForID:documentID serverState:nil]];
	}
}

- (IBAction)browseCloudDocumentsOnline:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[serviceRootURLString stringByAppendingPathComponent:@"documents"]]];
}

- (IBAction)browseCloudDocumentsOnlineAboutPage:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:serviceRootURLString]];	
}

- (IBAction)toggleDocumentsServiceAuthentication:(id)sender {
	NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	NSArray *cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:serviceRootURLString]];
	if ([cookies count] > 0) {
		for (NSHTTPCookie *each in cookies) {
			[cookieStorage deleteCookie:each];
		}
		for (BDocument *each in [[[NSDocumentController sharedDocumentController] documents] copy]) {
			if (each.fromDocumentsService) {
				[each saveDocument:nil];
				[each close];
			}
		}
		self.serviceUserName = nil;
	} else {
		[self beginSync:sender];
	}
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = [menuItem action];
	
	if (action == @selector(toggleDocumentsServiceAuthentication:)) {
		if (self.serviceUserName != nil) {
			[menuItem setTitle:[NSString stringWithFormat:BLocalizedString(@"Sign Out (%@)", nil), self.serviceUserName]];
		} else {
			[menuItem setTitle:BLocalizedString(@"Sign In / Create Account...", nil)];
		}
	} else if (action == @selector(beginSync:)) {
		return self.serviceUserName != nil;
	} else if (action == @selector(newCloudDocument:)) {
		return self.serviceUserName != nil;
	} else if (action == @selector(deleteCloudDocument:)) {
		return self.serviceUserName != nil && [[NSApp currentDocument] fromDocumentsService];
	} else if (action == @selector(browseCloudDocumentsOnline:)) {
		return self.serviceUserName != nil;
	}
	return YES;
}

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuItemForMenuItemExtensionPoint:@"com.blocks.BUserInterface.menus.main.file.cloudDocumentsService"] setTitle:self.serviceLabel];
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BUserInterface.menus.main.file.cloudDocumentsService"] setDelegate:self];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		if ([[each representedObject] isKindOfClass:[NSURL class]] || [each isSeparatorItem]) {
			[menu removeItem:each];
		}
	}
	
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	
	if (self.serviceUserName != nil) {
		BOOL addedSeparator = NO;
		NSMutableArray *menuItems = [NSMutableArray array];
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		
		for (NSString *each in [self localDocumentIDs]) {
			if (!addedSeparator) {
				addedSeparator = YES;
				[menuItems addObject:[NSMenuItem separatorItem]];
			}
			NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
			NSURL *eachURL = [NSURL fileURLWithPath:eachLocalPath];
			if (![BCloudDocumentsService isDocumentURLScheduledForDeleteByDocumentsService:eachURL]) {
				NSString *title = [BCloudDocumentsService displayNameForDocumentsServiceDocument:eachURL];
				NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(browseCloudDocumentsOnlineDocument:) keyEquivalent:@""];
				[eachMenuItem setRepresentedObject:[NSURL fileURLWithPath:eachLocalPath]];
				NSImage *icon = [workspace iconForFile:eachLocalPath];
				[icon setSize:NSMakeSize(16, 16)];
				[eachMenuItem setImage:icon];
				[eachMenuItem setTarget:self];
				[menuItems addObject:eachMenuItem];
			}
		}
		
		[menuItems sortUsingDescriptors:[NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES] autorelease]]];
		
		for (NSMenuItem *eachMenuItem in menuItems) {
			[menu addItem:eachMenuItem];
		}
	}
}

- (IBAction)browseCloudDocumentsOnlineDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[sender representedObject] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

#pragma mark Local Storage

- (BOOL)initDB {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];;
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	NSString *localDocumentShadowsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Shadows"];
	
	shadowStorage = [[FMDatabase alloc] initWithPath:@"shadowStorage.sqlite"];
	
	if (![shadowStorage open] || ![shadowStorage goodConnection]) {
		return NO;
	}
	
	if (![shadowStorage executeUpdate:@"CREATE TABLE IF NOT EXISTS documents (key INTEGER PRIMARY KEY, name TEXT, created REAL, modified REAL, content TEXT, version INTEGER, version_key TEXT, version_content TEXT)"]) {
		return NO;
	}
	
	if (![fileManager createDirectoriesForPath:localDocumentsPath]) {
		return NO;
	}
	
	if (![fileManager createDirectoriesForPath:localDocumentShadowsPath]) {
		return NO;
	}
	
	return YES;	
}

- (NSArray *)calculateCloudDocuments:(NSArray *)serverDocuments error:(NSError **)error {
	NSMutableDictionary *serverDocumentsByID = [NSMutableDictionary dictionary];
	for (NSDictionary *each in serverDocuments) {
		[serverDocumentsByID setObject:each forKey:[each objectForKey:@"id"]];
	}

	NSMutableArray *cloudDocuments = [NSMutableArray array];
	
	for (NSString *eachLocalID in self.localDocumentIDs) {
		BCloudDocument *eachCloudDocument = [self cloudDocumentForID:eachLocalID serverState:[serverDocumentsByID objectForKey:eachLocalID]];
		[cloudDocuments addObject:eachCloudDocument];
		[serverDocumentsByID removeObjectForKey:eachLocalID];
	}
	
	for (NSString *eachServerID in [serverDocumentsByID allKeys]) {
		[cloudDocuments addObject:[self cloudDocumentForID:eachServerID serverState:[serverDocumentsByID objectForKey:eachServerID]]];
	}
	
	return cloudDocuments;
}

- (NSArray *)localDocumentIDs {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];;
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	NSMutableArray *documentIDs = [NSMutableArray array];
	for (NSString *eachPotentialID in [fileManager contentsOfDirectoryAtPath:localDocumentsPath error:&error]) {
		if ([BCloudDocumentsService isDocumentURLManagedByDocumentsService:[NSURL fileURLWithPath:[localDocumentsPath stringByAppendingPathComponent:eachPotentialID]]]) {
			[documentIDs addObject:eachPotentialID];
		}
	}
	return documentIDs;
}

- (NSDictionary *)localFileattributes {
	static NSMutableDictionary *localFileattributes = nil;
	
	if (!localFileattributes) {
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		BDocument *document = [[documentController documents] lastObject];
		if (!document) {
			document = [[[documentController documentClassForType:[documentController defaultType]] alloc] init];
		}
		if (document && [document isKindOfClass:[BDocument class]]) {
			localFileattributes = [NSMutableDictionary dictionary];
			[localFileattributes setObject:[NSNumber numberWithUnsignedInteger:[document fileHFSCreatorCode]] forKey:NSFileHFSCreatorCode];
			[localFileattributes setObject:[NSNumber numberWithUnsignedInteger:[document fileHFSTypeCode]] forKey:NSFileHFSTypeCode];
		}
	}
	
	return localFileattributes;
}

- (void)scheduleForInsertOnClientWithName:(NSString *)name {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];;
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	NSString *newDocumentPath = nil;
	NSInteger i = 0;
	
	do  {
		i++;
		newDocumentPath = [localDocumentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"NewDocument %i", i]];
	} while ([fileManager fileExistsAtPath:newDocumentPath]);
	
	NSError *error = nil;
	
	if (![fileManager copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"CloudWelcomeText" ofType:@"txt"] toPath:newDocumentPath error:&error]) {
		NSBeep();
		return;
	}
	
	if (![fileManager setAttributes:[self localFileattributes] ofItemAtPath:newDocumentPath error:&error]) {
		NSBeep();
		return;
	}
	
	[NSFileManager setString:name forKey:@"BDocumentName" atPath:newDocumentPath traverseLink:YES];
	
	[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:newDocumentPath] display:YES error:&error];
}

- (void)updateLocalDocumentState:(BCloudDocument *)syncingDocument originalDocumentID:(NSString *)originalDocumentID {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];;
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	NSString *localDocumentShadowsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Shadows"];
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:syncingDocument.documentID];
	NSURL *documentURL = [NSURL fileURLWithPath:documentPath];
	NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:syncingDocument.documentID];

	if (![syncingDocument.documentID isEqualToString:originalDocumentID]) {
		BDocument *document = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:[localDocumentsPath stringByAppendingPathComponent:originalDocumentID]]];
		if (document) {
			[document setFileURL:documentURL];
			[document saveToURL:documentURL ofType:[document fileType] forSaveOperation:NSSaveAsOperation error:&error];
		}
		[self deleteLocalDocumentStateForDocumentID:originalDocumentID];
	}
	
	if ([syncingDocument.localContent writeToFile:documentPath atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
		if (syncingDocument.name) [NSFileManager setString:syncingDocument.name forKey:@"BDocumentName" atPath:documentPath traverseLink:YES];
		if (syncingDocument.serverVersion) { // If document is stil new pending on client then has no server version yet.
			[NSFileManager setString:[syncingDocument.serverVersion description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];
		}
		
		if (![fileManager setAttributes:[self localFileattributes] ofItemAtPath:documentPath error:&error]) {
			BLogError(@"Failed to set file attributes for %@", documentPath);
		}
		
		[fileManager removeFileAtPath:documentShadowPath handler:nil];
		
		if (![fileManager copyPath:documentPath toPath:documentShadowPath handler:nil]) {
			BLogError(@"Failed to update local shadow document at path %@", documentShadowPath);
		} else {
			if (syncingDocument.name) [NSFileManager setString:syncingDocument.name forKey:@"BDocumentName" atPath:documentShadowPath traverseLink:YES];
		}
	} else {
		BLogError(@"Failed to update local document at path %@", documentPath);
	}
	
	[[[NSDocumentController sharedDocumentController] documentForURL:documentURL] checkForModificationOfFileOnDisk];
}

- (void)scheduledForDeleteOnClient:(BCloudDocument *)syncingDocument {
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];
	NSString *documentPath = [[onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:syncingDocument.documentID];
	[NSFileManager setString:@"YES" forKey:@"BDocumentScheduledForDelete" atPath:documentPath traverseLink:YES];
	[[NSDocumentController sharedDocumentController] removeRecentDocumentURL:[NSURL fileURLWithPath:documentPath]];
}

- (void)deleteLocalDocumentStateForDocumentID:(NSString *)documentID {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];
	NSString *localDocumentsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"];
	NSString *localDocumentShadowsPath = [onlineDocumentCacheFolder stringByAppendingPathComponent:@"Shadows"];
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:documentID];
	BDocument *document = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:documentPath]];

	if (document) {
		[document close];
	}
	
	if (![fileManager removeItemAtPath:documentPath error:&error]) {
		BLogError(@"Error");
	}
	
	if (![fileManager removeItemAtPath:[localDocumentShadowsPath stringByAppendingPathComponent:documentID] error:&error]) {
		BLogError(@"Error");
	}
}

- (BCloudDocument *)cloudDocumentForID:(NSString *)documentID serverState:(NSDictionary *)serverState {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *onlineDocumentCacheFolder = [self onlineDocumentCacheFolder];
	NSString *localDocumentPath = [[onlineDocumentCacheFolder stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:documentID];
	NSString *localDocumentShadowPath = [[onlineDocumentCacheFolder stringByAppendingPathComponent:@"Shadows"] stringByAppendingPathComponent:documentID];
	BOOL hasLocalState = NO;
	
	BCloudDocument *cloudDocument = [[[BCloudDocument alloc] init] autorelease];
	
	if ([fileManager fileExistsAtPath:localDocumentPath]) {
		NSString *documentID = [[localDocumentPath lastPathComponent] stringByDeletingPathExtension];
		
		if ([documentID length] > 0) {
			hasLocalState = YES;
			cloudDocument.documentID = documentID;
			cloudDocument.name = [NSFileManager stringForKey:@"BDocumentName" atPath:localDocumentPath traverseLink:YES];
			cloudDocument.localContent = [NSString stringWithContentsOfFile:localDocumentPath encoding:NSUTF8StringEncoding error:&error];
			cloudDocument.isScheduledForDeleteOnClient = [BCloudDocumentsService isDocumentURLScheduledForDeleteByDocumentsService:[NSURL fileURLWithPath:localDocumentPath]];
			
			if (!cloudDocument.isScheduledForDeleteOnClient && [documentID rangeOfString:@"NewDocument"].location == 0) {
				cloudDocument.isScheduledForInsertOnClient = YES;
			} else {
				cloudDocument.localShadowContent = [NSString stringWithContentsOfFile:localDocumentShadowPath encoding:NSUTF8StringEncoding error:&error];
				cloudDocument.localShadowContentVersion = [NSFileManager stringForKey:@"BDocumentVersion" atPath:localDocumentPath traverseLink:YES];
				if (!serverState) {
					cloudDocument.isDeletedFromServer = YES;
				}
			}
		}
		
		cloudDocument.openNSDocument = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:localDocumentPath]];
	}
	
	if (serverState) {
		cloudDocument.serverVersion = [[serverState objectForKey:@"version"] description];
		cloudDocument.documentID = [serverState objectForKey:@"id"];
		cloudDocument.name = [serverState objectForKey:@"name"];
	} else if (!hasLocalState) {
		return nil;
	}

	return cloudDocument;
}

- (NSString *)onlineDocumentCacheFolder {
	return [[NSFileManager defaultManager].processesApplicationSupportFolder stringByAppendingPathComponent:self.serviceLabel];
}

#pragma mark Server Requests

- (void)beginActiveFetcher:(BCloudHTTPFetcher *)aFetcher {
	totalActiveFetchers++;
	[activeFetchers addObject:aFetcher];
	[aFetcher beginFetchWithDelegate:self];
	if (totalActiveFetchers == 1) {
		BCloudSyncWindowController *syncWindowController = [BCloudSyncWindowController sharedInstance];
		[syncWindowController showWindow:nil];
		syncWindowController.progress = 0.5;
	}
}

- (void)endActiveFetcher:(BCloudHTTPFetcher *)aFetcher {
	[aFetcher stopFetching];
	[activeFetchers removeObject:aFetcher];
	
	BCloudSyncWindowController *syncWindowController = [BCloudSyncWindowController sharedInstance];
	NSUInteger activeCount = [activeFetchers count];
	if (activeCount == 0) {
		syncWindowController.progress = 1.0;
		[syncWindowController close];
		
		if ([failedPatches length] > 0) {
			NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"%@ Syncing Conflicts", nil), self.serviceLabel];
			NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"Some of your edits could not be synced with %@ because they conflict with other recent edits on %@. Please go to the %@ website to resolve these conflicts.", nil), self.serviceLabel, self.serviceLabel, self.serviceLabel];
			NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Resolve Conflicts", nil) alternateButton:BLocalizedString(@"Close", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
			if ([alert runModal] == NSOKButton) {
				[self browseCloudDocumentsOnline:nil];
			}
		}
	} else {
		syncWindowController.progress = 0.5 + ((1.0 - ((float)activeCount / (float)totalActiveFetchers)) / 2.0);
	}
}

- (void)GETServerDocuments {
	NSMutableURLRequest *getDocumentsRequest = [[[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
	BCloudHTTPFetcher *getDocumentsFetcher = [BCloudHTTPFetcher fetcherWithRequest:getDocumentsRequest];
	[getDocumentsFetcher setUserData:self];
	[self beginActiveFetcher:getDocumentsFetcher];
}

- (void)POSTServerDocument:(BCloudDocument *)syncingDocument {
	NSMutableURLRequest *postNewDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]]];
	BCloudHTTPFetcher *postNewDocumentFetcher = [BCloudHTTPFetcher fetcherWithRequest:postNewDocumentRequest];
	[postNewDocumentFetcher setFormURLEncodedPostDictionary:[NSDictionary dictionaryWithObjectsAndKeys:syncingDocument.name, @"name", syncingDocument.localContent, @"content", nil]];
	[postNewDocumentFetcher setUserData:syncingDocument];
	[self beginActiveFetcher:postNewDocumentFetcher];
}

- (void)GETServerDocument:(BCloudDocument *)syncingDocument {
	NSMutableURLRequest *getDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@", self.serviceRootURLString, syncingDocument.documentID]]];
	BCloudHTTPFetcher *getDocumentRequestFetcher = [BCloudHTTPFetcher fetcherWithRequest:getDocumentRequest];
	[getDocumentRequestFetcher setUserData:syncingDocument];
	[self beginActiveFetcher:getDocumentRequestFetcher];
}

- (void)POSTServerDocumentEdits:(BCloudDocument *)syncingDocument {
	NSMutableURLRequest *postEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits", self.serviceRootURLString, syncingDocument.documentID]]];
	BCloudHTTPFetcher *postEditsRequestFetcher = [BCloudHTTPFetcher fetcherWithRequest:postEditsRequest];
	[postEditsRequestFetcher setFormURLEncodedPostDictionary:syncingDocument.localEdits];
	[postEditsRequestFetcher setUserData:syncingDocument];
	[self beginActiveFetcher:postEditsRequestFetcher];
}

- (void)GETServerDocumentEdits:(BCloudDocument *)syncingDocument {
	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	NSMutableURLRequest *getServerEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits/?start=%@&end=%@", self.serviceRootURLString, syncingDocument.documentID, [NSString stringWithFormat:@"%i", [[numberFormatter numberFromString:syncingDocument.localShadowContentVersion] intValue] + 1], syncingDocument.serverVersion]]];
	BCloudHTTPFetcher *getServerEditsFetcher = [BCloudHTTPFetcher fetcherWithRequest:getServerEditsRequest];
	[getServerEditsFetcher setUserData:syncingDocument];
	[self beginActiveFetcher:getServerEditsFetcher];
}

- (void)DELETEServerDocument:(BCloudDocument *)syncingDocument {
	NSMutableURLRequest *deleteDocumentRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@", self.serviceRootURLString, syncingDocument.documentID]]];
	[deleteDocumentRequest setHTTPMethod:@"DELETE"];
	BCloudHTTPFetcher *deleteDocumentFetcher = [BCloudHTTPFetcher fetcherWithRequest:deleteDocumentRequest];
	[deleteDocumentFetcher setUserData:syncingDocument];
	[self beginActiveFetcher:deleteDocumentFetcher];
}

- (void)noteFailedPatches:(NSString *)patches {
	[failedPatches appendString:patches];
}

#pragma mark Server Requests Delegates

- (void)clientLogin {
	BCloudAuthenticationWindowController *authenticationWindowController = [[[BCloudAuthenticationWindowController alloc] init] autorelease];
	NSInteger result = [NSApp runModalForWindow:[authenticationWindowController window]];
	
	if (result == NSOKButton) {
		NSURL *url = [NSURL URLWithString:@"https://www.google.com/accounts/ClientLogin"];
		NSMutableURLRequest *authTokenRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		BCloudHTTPFetcher *authTokenFetcher = [BCloudHTTPFetcher fetcherWithRequest:authTokenRequest];
		NSString *postString = [NSString stringWithFormat:@"Email=%@&Passwd=%@&source=%@&service=%@&accountType=%@", [authenticationWindowController.username stringByURLEncodingStringParameter], [authenticationWindowController.password stringByURLEncodingStringParameter], [self.service stringByURLEncodingStringParameter], @"ah", @"GOOGLE"];
		[authTokenFetcher setPostData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
		[self beginActiveFetcher:authTokenFetcher];
	} else {
		[self cancelSync:nil];
	}
}

- (void)fetcher:(BCloudHTTPFetcher *)aFetcher networkFailed:(NSError *)error {
	[[NSDocumentController sharedDocumentController] presentError:error];
	[self endActiveFetcher:aFetcher];
}

- (void)fetcher:(BCloudHTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	if (statusCode == 401 || statusCode == 403) {
		[self clientLogin];
	} else {
		[self endActiveFetcher:aFetcher];
		// should display error!
	}
}

- (void)fetcher:(BCloudHTTPFetcher *)aFetcher finishedWithData:(NSData *)data {
	NSString *absoluteString = [[[aFetcher request] URL] absoluteString];
	
	if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ServiceLogin"].location == 0) {
		[self clientLogin];
	} else if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
		NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary *responseDict = [BCloudHTTPFetcher dictionaryWithResponseString:responseString];
		NSString *authToken = [[responseDict objectForKey:@"Auth"] retain];
		NSString *requestString = [NSString stringWithFormat:@"%@/_ah/login?continue=%@&auth=%@", self.serviceRootURLString, [[[aFetcher.initialRequest URL] absoluteString] stringByURLEncodingStringParameter], authToken];
		NSURL *url = [NSURL URLWithString:requestString];
		NSMutableURLRequest *authenticationCookieRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		BCloudHTTPFetcher *authenticationCookieFetcher = [BCloudHTTPFetcher fetcherWithRequest:authenticationCookieRequest];
		[authenticationCookieFetcher beginFetchWithDelegate:self];
	} else if ([[aFetcher userData] respondsToSelector:@selector(processSyncResponse:)]) {
		[[aFetcher userData] processSyncResponse:data];
	}

	[self endActiveFetcher:aFetcher];
}

- (void)processSyncResponse:(NSData *)data {
	NSError *error = nil;
	NSArray *serverDocuments = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSArray *cloudDocuments = [self calculateCloudDocuments:serverDocuments error:&error];
	
	for (BCloudDocument *each in cloudDocuments) {
		[each scheduleSyncRequest];
	}
}

@end

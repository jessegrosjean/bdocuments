//
//  BDocumentCloudDelegate.m
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BDocumentCloudDelegate.h"
#import "BDocuments.h"
#import "Cloud.h"
#import "CloudDocument.h"
#import "HTTPFetcher.h"

@implementation BDocumentCloudDelegate

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

+ (BOOL)isCloudDocumentURL:(NSURL *)url {
	NSString *documentPath = [url path];
	NSString *documentIDPath = [documentPath stringByDeletingLastPathComponent];
	NSString *documentCacheDirectory = [documentIDPath stringByDeletingLastPathComponent];
	return [[[self sharedInstance] cloudCacheDirectory] isEqualToString:documentCacheDirectory];
}

+ (NSString *)displayNameForCloudDocument:(NSURL *)url {
	return [[[url path] lastPathComponent] stringByDeletingPathExtension];
//	return [[[[url path] lastPathComponent] stringByDeletingPathExtension] stringByAppendingString:BLocalizedString(@" (Synced)", nil)];
}

#pragma mark Init

- (id)init {
	if (self = [super init]) {
		[self initLocalCacheDatabase];
	}
	return self;
}

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BUserInterface.menus.main.cloudDocumentsService"] setDelegate:self];
	NSMenuItem *menuItem = [NSMenu menuItemForMenuItemExtensionPoint:@"com.blocks.BUserInterface.menus.main.cloudDocumentsService.openCloudDocumentsWebsite"];
	[menuItem setTitle:[[menuItem title] stringByAppendingFormat:@" (%@)", [[Cloud sharedInstance] serviceLabel]]];
	[[Cloud sharedInstance] setDelegate:self];
}

#pragma mark Actions

- (IBAction)beginSync:(NSMenuItem *)sender {
	[[Cloud sharedInstance] beginSync:sender];
}

- (IBAction)newCloudDocument:(NSMenuItem *)sender {
	BCloudNameWindowController *nameWindowController = [[BCloudNameWindowController alloc] init];
	[[nameWindowController window] center];
	NSInteger result = [NSApp runModalForWindow:[nameWindowController window]];
	
	if (result == NSOKButton) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *cloudCacheDirectory = [self cloudCacheDirectory];
		NSString *newDocumentIDPath = nil;
		NSInteger i = 0;
		
		do  {
			i++;
			newDocumentIDPath = [cloudCacheDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"NewDocument %i", i]];
		} while ([fileManager fileExistsAtPath:newDocumentIDPath]);
		
		if (![fileManager createDirectoriesForPath:newDocumentIDPath]) {
			NSBeep();
			return;
		}
		
		NSError *error = nil;
		NSString *name = [nameWindowController.name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if ([name length] == 0) {
			name = BLocalizedString(@"Untitled", nil);
		}
		
		NSString *newDocumentPath = [newDocumentIDPath stringByAppendingPathComponent:name];
				
		if (![fileManager copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"CloudWelcomeText" ofType:@"txt"] toPath:newDocumentPath error:&error]) {
			NSBeep();
			return;
		}
		
		if (![fileManager setAttributes:[self localFileAttributes] ofItemAtPath:newDocumentPath error:&error]) {
			NSBeep();
			return;
		}
		
		BCloudCacheDocument *cloudCacheDocument = [NSEntityDescription insertNewObjectForEntityForName:@"CloudCacheDocument" inManagedObjectContext:managedObjectContext];
		cloudCacheDocument.documentID = [newDocumentIDPath lastPathComponent];
		cloudCacheDocument.localName = name;
		cloudCacheDocument.isScheduledForInsertOnClient = YES;
		
		if (![managedObjectContext save:&error]) {
			NSBeep();
			BLogError([error description]);
		}
		
		[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:newDocumentPath] display:YES error:&error];
	}
}

- (IBAction)openCloudDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[sender representedObject] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

- (IBAction)deleteCloudDocument:(id)sender {
	Cloud *cloud = [Cloud sharedInstance];
	BDocumentWindowController *windowController = [NSApp currentDocumentWindowController];
	NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"Are you sure that you want to delete this document from %@?", nil), cloud.serviceLabel];
	NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"If you choose \"Delete\" this document will be deleted from your computer and then deleted from %@ next time you sync.", nil), cloud.serviceLabel];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Delete", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
	[alert beginSheetModalForWindow:[windowController window] modalDelegate:self didEndSelector:@selector(deleteCloudDocumentDidEnd:returnCode:contextInfo:) contextInfo:windowController];
}

- (void)deleteCloudDocumentDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(BDocumentWindowController *)windowController {
	if (returnCode == NSOKButton) {
		NSError *error = nil;
		BDocument *document = [windowController document];
		NSString *documentID = [document cloudID];
		BCloudCacheDocument *cloudCachedDocument = [self cloudCacheDocumentForID:documentID error:&error];
		
		if (cloudCachedDocument) {
			[document saveDocument:nil];
			[document close];
			cloudCachedDocument.isScheduledForDeleteOnClient = YES;
			if (![managedObjectContext save:&error]) {
				BLogError([error description]);
			} else {
				[[NSFileManager defaultManager] removeItemAtPath:[[cloudCachedDocument fileSystemPath] stringByDeletingLastPathComponent] error:&error];
			}
		}
	}
}

- (IBAction)openCloudDocumentsWebsite:(NSMenuItem *)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[[Cloud sharedInstance] serviceRootURLString] stringByAppendingString:@"/documents/"]]];
}

- (IBAction)toggleCloudDocumentsAuthentication:(id)sender {
	[[Cloud sharedInstance] toggleAuthentication:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = [menuItem action];
	Cloud *cloud = [Cloud sharedInstance];
	
	if (action == @selector(toggleCloudDocumentsAuthentication:)) {
		if (cloud.serviceUsername != nil) {
			[menuItem setTitle:[NSString stringWithFormat:BLocalizedString(@"Sign Out (%@)", nil), cloud.serviceUsername]];
		} else {
			[menuItem setTitle:BLocalizedString(@"Sign In / Create Account...", nil)];
		}
	} else if (action == @selector(beginSync:)) {
		return cloud.serviceUsername != nil;
	} else if (action == @selector(newCloudDocument:)) {
		return cloud.serviceUsername != nil;
	} else if (action == @selector(deleteCloudDocument:)) {
		return cloud.serviceUsername != nil && [[NSApp currentDocument] fromCloud];
	} else if (action == @selector(openCloudDocumentsWebsite:)) {
		return cloud.serviceUsername != nil;
	}
	
	return YES;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		if ([[each representedObject] isKindOfClass:[NSURL class]] || [each isSeparatorItem]) {
			[menu removeItem:each];
		}
	}
	
	Cloud *cloud = [Cloud sharedInstance];
	
	if (cloud.serviceUsername != nil) {
		BOOL addedSeparator = NO;
		NSError *error = nil;
		NSMutableArray *menuItems = [NSMutableArray array];
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		
		for (BCloudCacheDocument *eachCloudCacheDocument in [self cloudCacheDocuments:&error]) {
			if (!eachCloudCacheDocument.isScheduledForDeleteOnClient) {
				NSString *eachFileSystemPath = [eachCloudCacheDocument fileSystemPath];
				if (!addedSeparator) {
					addedSeparator = YES;
					[menuItems addObject:[NSMenuItem separatorItem]];
				}
				
				NSURL *eachURL = [NSURL fileURLWithPath:eachFileSystemPath];
				NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:[BDocumentCloudDelegate displayNameForCloudDocument:eachURL] action:@selector(openCloudDocument:) keyEquivalent:@""];
				[eachMenuItem setRepresentedObject:eachURL];
				NSImage *icon = [workspace iconForFile:eachFileSystemPath];
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

#pragma mark Local Cache File System

- (NSString *)cloudFolder {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *cloudFolder = [fileManager.processesApplicationSupportFolder stringByAppendingPathComponent:[[Cloud sharedInstance] serviceLabel]];
	if ([fileManager createDirectoriesForPath:cloudFolder]) {
		return cloudFolder;
	}
	return nil;
}

- (NSString *)cloudCacheDirectory {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *cloudCacheDirectory = [[self cloudFolder] stringByAppendingPathComponent:@"CloudCacheDirectory"];
	if ([fileManager createDirectoriesForPath:cloudCacheDirectory]) {
		return cloudCacheDirectory;
	}
	return nil;
}

- (NSDictionary *)localFileAttributes {
	static NSMutableDictionary *localFileAttributes = nil;
	
	if (!localFileAttributes) {
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		BDocument *document = [[documentController documents] lastObject];
		if (!document) {
			document = [[[documentController documentClassForType:[documentController defaultType]] alloc] init];
		}
		if (document && [document isKindOfClass:[BDocument class]]) {
			localFileAttributes = [NSMutableDictionary dictionary];
			[localFileAttributes setObject:[NSNumber numberWithUnsignedInteger:[document fileHFSCreatorCode]] forKey:NSFileHFSCreatorCode];
			[localFileAttributes setObject:[NSNumber numberWithUnsignedInteger:[document fileHFSTypeCode]] forKey:NSFileHFSTypeCode];
		}
	}
		
	return localFileAttributes;
}

#pragma mark Local Cache Database

- (void)initLocalCacheDatabase {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *objectModelPath = [bundle pathForResource:@"BDocumentCloudCache" ofType:@"mom"];
	
	managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:objectModelPath]];
	persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
	
	NSError *error;
	if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[NSURL fileURLWithPath:[[self cloudFolder] stringByAppendingPathComponent: @"CloudCache.sqlite"]] options:nil error:&error]){
		[[NSApplication sharedApplication] presentError:error];
	}
	
	managedObjectContext = [[NSManagedObjectContext alloc] init];
	[managedObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
}

- (NSArray *)cloudCacheDocuments:(NSError **)error {
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"CloudCacheDocument" inManagedObjectContext:managedObjectContext];
	[request setEntity:entityDescription];
	return [managedObjectContext executeFetchRequest:request error:error];
}

- (BCloudCacheDocument *)cloudCacheDocumentForID:(NSString *)documentID error:(NSError **)error {
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	[request setEntity:[NSEntityDescription entityForName:@"CloudCacheDocument" inManagedObjectContext:managedObjectContext]];
	[request setPredicate:[NSPredicate predicateWithFormat:@"documentID = %@", documentID]];	
	return [[managedObjectContext executeFetchRequest:request error:error] lastObject];
}

#pragma mark Cloud Callbacks

- (void)cloudSyncNewCredentials:(Cloud *)cloud {
	BCloudAuthenticationWindowController *authenticationWindowController = [[[BCloudAuthenticationWindowController alloc] init] autorelease];
	NSInteger result = [NSApp runModalForWindow:[authenticationWindowController window]];
	
	if (result == NSOKButton) {
		[cloud setServiceUsername:authenticationWindowController.username];
		[cloud setServicePassword:authenticationWindowController.password];
		[cloud beginSync:nil];
	}
}

- (void)cloudWillBeginSync:(Cloud *)cloud {
	[[BCloudSyncWindowController sharedInstance] showWindow:nil];
	[BCloudSyncWindowController sharedInstance].progress = 0.5;

	for (NSDocument *eachDocument in [[NSDocumentController sharedDocumentController] documents]) {
		if ([eachDocument isKindOfClass:[BDocument class]]) {
			if ([(BDocument *)eachDocument fromCloud]) {
				[eachDocument saveDocument:nil];
			}
		}
	}
	
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *cloudCacheDocuments = [self cloudCacheDocuments:&error];
	BOOL isDirectory;

	if (!cloudCacheDocuments) {
		BLogError([error description]);
	}
	
	for (BCloudCacheDocument *eachCloudCacheDocument in cloudCacheDocuments) {
		NSString *eachPath = [eachCloudCacheDocument fileSystemPathForID:eachCloudCacheDocument.documentID name:eachCloudCacheDocument.localName];
		
		if ([fileManager fileExistsAtPath:eachPath isDirectory:&isDirectory] && !isDirectory) {
			NSString *localContent = [NSString stringWithContentsOfFile:eachPath encoding:NSUTF8StringEncoding error:&error];
			if (localContent) {
				if (![eachCloudCacheDocument.localContent isEqualToString:localContent]) {
					eachCloudCacheDocument.localContent = localContent;
				}
			} else {
				BLogError([error description]);
			}
		}
	}
		
	if (![managedObjectContext save:&error]) {
		BLogError([error description]);
	}
}

- (NSArray *)cloudSyncLocalDocuments {
	NSError *error = nil;
	NSMutableArray *cloudDocuments = [NSMutableArray array];
	
	for (BCloudCacheDocument *eachCloudCacheDocument in [self cloudCacheDocuments:&error]) {
		CloudDocument *eachCloudDocument = [[[CloudDocument alloc] init] autorelease];
		
		eachCloudDocument.localName = eachCloudCacheDocument.localName;
		eachCloudDocument.localContent = eachCloudCacheDocument.localContent;
		eachCloudDocument.documentID = eachCloudCacheDocument.documentID;
		eachCloudDocument.localShadowName = eachCloudCacheDocument.localShadowName;
		eachCloudDocument.localShadowContent = eachCloudCacheDocument.localShadowContent;
		eachCloudDocument.localShadowVersion = eachCloudCacheDocument.localShadowVersion;	
		eachCloudDocument.isScheduledForDeleteOnClient = eachCloudCacheDocument.isScheduledForDeleteOnClient;
		eachCloudDocument.isScheduledForInsertOnClient = eachCloudCacheDocument.isScheduledForInsertOnClient;
		
		[cloudDocuments addObject:eachCloudDocument];
	}
	
	if (error) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
	
	return cloudDocuments;
}

- (BOOL)cloudSyncUpdateOrInsertLocalDocument:(CloudDocument *)aCloudDocument originalDocumentID:(NSString *)originalDocumentID {
	NSError *error = nil;
	BCloudCacheDocument *cloudCacheDocument = [self cloudCacheDocumentForID:originalDocumentID error:&error];
	NSString *originalName = nil;
	NSDocument *document = nil;
	
	if (!cloudCacheDocument) {
		if (error) {
			BLogError([error description]);
			return NO;
		} else {
			cloudCacheDocument = [NSEntityDescription insertNewObjectForEntityForName:@"CloudCacheDocument" inManagedObjectContext:managedObjectContext];
		}
		originalName = aCloudDocument.localName;
	} else {
		originalName = cloudCacheDocument.localName;
		document = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:[cloudCacheDocument fileSystemPath]]];
	}
	
	cloudCacheDocument.documentID = aCloudDocument.documentID;
	cloudCacheDocument.localName = aCloudDocument.localName;
	cloudCacheDocument.localContent = aCloudDocument.localContent;
	cloudCacheDocument.localShadowName = aCloudDocument.localShadowName;
	cloudCacheDocument.localShadowContent = aCloudDocument.localShadowContent;
	cloudCacheDocument.localShadowVersion = aCloudDocument.localShadowVersion;
	cloudCacheDocument.isScheduledForInsertOnClient = NO;

	if (![managedObjectContext save:&error]) {
		BLogError([error description]);
		return NO;
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *originalFilePath = [cloudCacheDocument fileSystemPathForID:originalDocumentID name:originalName];
	NSString *newFilePath = [cloudCacheDocument fileSystemPathForID:cloudCacheDocument.documentID name:cloudCacheDocument.localName];
	
	if (originalFilePath) {
		if (![originalFilePath isEqualToString:newFilePath]) {
			if (![fileManager removeItemAtPath:[originalFilePath stringByDeletingLastPathComponent] error:&error]) {
				BLogError([error description]);
			}
		}
	}
	
	if (![fileManager createDirectoriesForPath:[newFilePath stringByDeletingLastPathComponent]]) {
		BLogError(@"Failed to create directories for cloud document.");
	}

	if (![cloudCacheDocument.localContent writeToFile:newFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
		BLogError([error description]);
	}
	
	if (![fileManager setAttributes:[self localFileAttributes] ofItemAtPath:newFilePath error:&error]) {
		BLogError([error description]);
	}

	[document setFileURL:[NSURL fileURLWithPath:newFilePath]];
	if ([document respondsToSelector:@selector(_resetMoveAndRenameSensing)]) {
		[document performSelector:@selector(_resetMoveAndRenameSensing)];
	}
	[document checkForModificationOfFileOnDisk]; // bring in changes from disk.
	[document saveDocument:nil]; // do final sync save.
	
	return YES;
}

- (BOOL)cloudSyncDeleteLocalDocument:(NSString *)documentID {
	NSError *error = nil;
	BCloudCacheDocument *cloudCacheDocument = [self cloudCacheDocumentForID:documentID error:&error];

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *deletedFilePath = [cloudCacheDocument fileSystemPath];

	NSDocument *document = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:deletedFilePath]];
	if (document) {
		[document saveDocument:nil];
		[document close];
	}
	
	if ([fileManager fileExistsAtPath:[deletedFilePath stringByDeletingLastPathComponent]]) {
		if (![fileManager removeItemAtPath:[deletedFilePath stringByDeletingLastPathComponent] error:&error]) {
			BLogError([error description]);
		}
	}
	
	[managedObjectContext deleteObject:cloudCacheDocument];
	
	if (![managedObjectContext save:&error]) {
		BLogError([error description]);
		return NO;
	}
	
	return YES;
}

- (void)cloudSyncProgress:(CGFloat)progress cloud:(Cloud *)cloud {
	[BCloudSyncWindowController sharedInstance].progress = progress;
}

- (void)cloudSyncFetcher:(HTTPFetcher *)aFetcher networkFailed:(NSError *)error {
	Cloud *cloud = [Cloud sharedInstance];
	NSString *serviceLabel = [cloud serviceLabel];
	NSString *messageText = [NSString stringWithFormat:NSLocalizedString(@"%@ Sync Network Failed", nil), serviceLabel];
	NSString *informativeText = [NSString stringWithFormat:NSLocalizedString(@"\"%@\".", nil), [error localizedDescription]];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Retry", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeText];
	if ([alert runModal] == NSOKButton) {
		[self beginSync:nil];
	}
}

- (void)cloudSyncFetcher:(HTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	Cloud *cloud = [Cloud sharedInstance];
	NSString *serviceLabel = [cloud serviceLabel];
	NSString *messageText = [NSString stringWithFormat:NSLocalizedString(@"%@ Sync Error", nil), serviceLabel];
	NSString *informativeText = [NSString stringWithFormat:NSLocalizedString(@"%@ (%i)\n\"%@\".", nil), [[aFetcher.request URL] path], statusCode, [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Retry", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeText];
	if ([alert runModal] == NSOKButton) {
		[self beginSync:nil];
	}
}

- (void)cloudDidCompleteSync:(Cloud *)cloud conflicts:(NSString *)conflicts {
	[BCloudSyncWindowController sharedInstance].progress = 1.0;
	[[BCloudSyncWindowController sharedInstance] close];
	
	if ([conflicts length] > 0) {
		NSString *serviceLabel = [[Cloud sharedInstance] serviceLabel];
		NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"%@ Conflicts", nil), serviceLabel];
		NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"Some of your edits conflict with recent changes made on %@. Please go to the website to resolve these conflicts.", nil), serviceLabel];
		NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Resolve", nil) alternateButton:BLocalizedString(@"Close", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
		if ([alert runModal] == NSOKButton) {
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[[Cloud sharedInstance] serviceRootURLString] stringByAppendingString:@"/documents/#conflicts"]]];
		}
	}
}

@end

@implementation BCloudCacheDocument

@dynamic documentID, localName, localShadowName, localContent, localShadowContent, localShadowVersion;

- (BOOL)isScheduledForDeleteOnClient {
    [self willAccessValueForKey:@"isScheduledForDeleteOnClient"];
    BOOL result = isScheduledForDeleteOnClient;
    [self didAccessValueForKey:@"isScheduledForDeleteOnClient"];
    return result;
}

- (void)setIsScheduledForDeleteOnClient:(BOOL)newIsScheduledForDeleteOnClient {
    [self willChangeValueForKey:@"isScheduledForDeleteOnClient"];
    isScheduledForDeleteOnClient = newIsScheduledForDeleteOnClient;
    [self didChangeValueForKey:@"isScheduledForDeleteOnClient"];
}

- (BOOL)isDeletedFromServer {
    [self willAccessValueForKey:@"isDeletedFromServer"];
    BOOL result = isDeletedFromServer;
    [self didAccessValueForKey:@"isDeletedFromServer"];
    return result;
}

- (void)setIsDeletedFromServer:(BOOL)newIsDeletedFromServer {
    [self willChangeValueForKey:@"isDeletedFromServer"];
    isDeletedFromServer = newIsDeletedFromServer;
    [self didChangeValueForKey:@"isDeletedFromServer"];
}

- (BOOL)isScheduledForInsertOnClient {
    [self willAccessValueForKey:@"isScheduledForInsertOnClient"];
    BOOL result = isScheduledForInsertOnClient;
    [self didAccessValueForKey:@"isScheduledForInsertOnClient"];
    return result;
}

- (void)setIsScheduledForInsertOnClient:(BOOL)newIsScheduledForInsertOnClient {
    [self willChangeValueForKey:@"isScheduledForInsertOnClient"];
    isScheduledForInsertOnClient = newIsScheduledForInsertOnClient;
    [self didChangeValueForKey:@"isScheduledForInsertOnClient"];
}

- (NSString *)fileSystemPath {
	return [self fileSystemPathForID:self.documentID name:self.localName];
}

- (NSString *)fileSystemPathForID:(NSString *)documentID name:(NSString *)name {
	return [[[[BDocumentCloudDelegate sharedInstance] cloudCacheDirectory] stringByAppendingPathComponent:documentID] stringByAppendingPathComponent:name];
}

@end

@implementation BCloudNameWindowController

- (id)init {
	if (self = [super initWithWindowNibName:@"BCloudNameWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	NSString *serviceLabel = [[Cloud sharedInstance] serviceLabel];
	[message setStringValue:[NSString stringWithFormat:[message stringValue], serviceLabel, nil]];
	
}

- (NSString *)name {
	return [nameTextField stringValue];
}

- (void)setName:(NSString *)newName {
	[nameTextField setStringValue:newName];
}

- (IBAction)ok:(id)sender {
	[NSApp endSheet:[self window] returnCode:NSOKButton];
	[self close];
}

- (IBAction)cancel:(id)sender {
	[NSApp endSheet:[self window] returnCode:NSCancelButton];
	[self close];
}

@end

@implementation BCloudAuthenticationWindowController

- (id)init {
	return [self initWithUsername:nil password:nil];
}

- (id)initWithUsername:(NSString *)aUsername password:(NSString *)aPassword {
	if (self = [super initWithWindowNibName:@"BCloudAuthenticationWindow"]) {
		self.username = aUsername;
		self.password = aPassword;
	}
	return self;
}

- (void)awakeFromNib {
	NSString *serviceLabel = [[Cloud sharedInstance] serviceLabel];
	[heading setStringValue:[NSString stringWithFormat:[heading stringValue], serviceLabel]];
	[message setStringValue:[NSString stringWithFormat:[message stringValue], serviceLabel, serviceLabel, nil]];
}

- (NSString *)username {
	return [usernameTextField stringValue];
}

- (void)setUsername:(NSString *)aUsername {
	[usernameTextField setStringValue:aUsername];
}

- (NSString *)password {
	return [passwordTextField stringValue];
}

- (void)setPassword:(NSString *)aPassword {
	[passwordTextField setStringValue:aPassword];
}

- (IBAction)createNewAccount:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.google.com/accounts/NewAccount"]];
	[self cancel:sender];
}

- (IBAction)foregotPassword:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.google.com/accounts/ForgotPasswd"]];
	[self cancel:sender];
}

- (IBAction)learnMore:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[Cloud sharedInstance] serviceRootURLString]]];
}

- (IBAction)ok:(id)sender {
	[NSApp stopModalWithCode:NSOKButton];
	[self close];
}

- (IBAction)cancel:(id)sender {
	[NSApp stopModalWithCode:NSCancelButton];
	[self close];
}

@end

@implementation BCloudSyncWindowController

+ (BCloudSyncWindowController *)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id)init {
	if (self = [super initWithWindowNibName:@"BCloudSyncWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	[progressIndicator setUsesThreadedAnimation:YES];
	[progressIndicator setMaxValue:1.0];
	[[self window] setTitle:[NSString stringWithFormat:BLocalizedString(@"%@ Sync...", nil), [[Cloud sharedInstance] serviceLabel]]];
	[[self window] setLevel:NSFloatingWindowLevel];
}

- (double)progress {
	return [progressIndicator doubleValue];
}

- (void)setProgress:(double)progress {
	[progressIndicator setDoubleValue:progress];
}

- (IBAction)showWindow:(id)sender {
	[[self window] center];
	[progressIndicator startAnimation:nil];
	[super showWindow:sender];
}

- (IBAction)cancel:(id)sender {
	[[Cloud sharedInstance] cancelSync:nil];
}

- (void)close {
	[super close];
	[progressIndicator stopAnimation:nil];
}

@end
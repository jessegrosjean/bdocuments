//
//  BDocumentCloudDelegate.m
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/16/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "SyncedDocumentsControllerDelegate.h"
#import "SyncedDocumentsController.h"
#import "SyncedDocument.h"
#import "HTTPClient.h"
#import "BDocuments.h"
#import "NDAlias.h"


@implementation SyncedDocumentsControllerDelegate

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
															 [[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:[[SyncedDocumentsController sharedInstance] serviceLabel]] stringByAppendingString:BLocalizedString(@" Synced/", nil)], SyncedDocumentsFolderKey,
															 nil]];
}

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

+ (NSString *)syncedDocumentsFolder {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *syncedDocumentsFolder = [[NSUserDefaults standardUserDefaults] objectForKey:SyncedDocumentsFolderKey];
	if ([fileManager createDirectoriesForPath:syncedDocumentsFolder]) {
		return syncedDocumentsFolder;
	}
	return nil;
}

+ (BOOL)isSyncedDocumentURL:(NSURL *)url {
	return [[url path] rangeOfString:[self syncedDocumentsFolder]].location == 0;
}

+ (NSString *)displayNameForSyncedDocument:(NSURL *)url {
	NSDate *modificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath:[url path] traverseLink:YES] objectForKey:NSFileModificationDate];
	NSDate *lastSyncDate = [NSDate dateWithString:[NSFileManager stringForKey:@"BDocumentsLastSyncDate" atPath:[url path] traverseLink:YES]];
	NSString *name = [[url path] lastPathComponent];
	
	//if (lastSyncDate == nil || abs(floor([lastSyncDate timeIntervalSinceDate:modificationDate])) > 1) {
	//	return [NSString stringWithFormat:@"[SYNC] %@", name];
	//} else {
		return name;
	//}
	/*
	SyncedDocument *syncedDocument = [self syncedDocumentForEditableFileURL:url];
	NSDate *syncModificationDate = syncedDocument.modified;
	NSDate *localModificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath:[url path] traverseLink:YES] objectForKey:NSFileModificationDate];
	int difference = abs(floor([syncModificationDate timeIntervalSinceDate:localModificationDate]));
	
	if (difference > 0) {
		return [NSString stringWithFormat:@"%@ (Sync)", syncedDocument.name];
		//return [NSString stringWithFormat:@"%@ (↺)", syncedDocument.name];
	} else {
		return syncedDocument.name;
	}*/
}

+ (NSArray *)localSyncedDocumentPaths {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *syncedDocumentsFolder = [SyncedDocumentsControllerDelegate syncedDocumentsFolder];
	NSArray *localSyncedDocumentPaths = [fileManager contentsOfDirectoryAtPath:syncedDocumentsFolder error:&error];
	NSMutableArray *results = [NSMutableArray array];
	BOOL isDirectory;
	
	if (!localSyncedDocumentPaths) {
		BLogError([error description]);
	}
		
	for (NSString *eachLocalSyncedDocumentPath in localSyncedDocumentPaths) {
		eachLocalSyncedDocumentPath = [syncedDocumentsFolder stringByAppendingPathComponent:eachLocalSyncedDocumentPath];
		if ([fileManager fileExistsAtPath:eachLocalSyncedDocumentPath isDirectory:&isDirectory] && !isDirectory) {
			NSString *filename = [[eachLocalSyncedDocumentPath lastPathComponent] stringByDeletingPathExtension];
			if (![filename rangeOfString:@"."].location == 0 && ![[filename substringWithRange:NSMakeRange([filename length] - 1, 1)] isEqualToString:@"~"]) {
				[results addObject:eachLocalSyncedDocumentPath];
			}
		}
	}
	
	return results;
}

+ (NSDictionary *)localFileAttributes {
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

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BUserInterface.menus.main.syncedDocumentsService"] setDelegate:self];
	NSMenuItem *menuItem = [NSMenu menuItemForMenuItemExtensionPoint:@"com.blocks.BUserInterface.menus.main.syncedDocumentsService.openSyncedDocumentsWebsite"];
	[menuItem setTitle:[[menuItem title] stringByAppendingFormat:@" (%@)", [[SyncedDocumentsController sharedInstance] serviceLabel]]];
	[[SyncedDocumentsController sharedInstance] setDocumentDatabaseDirectory:[SyncedDocumentsControllerDelegate syncedDocumentsFolder]];
	[[SyncedDocumentsController sharedInstance] setSyncDelegate:self];
}

#pragma mark Actions

- (IBAction)beginSync:(NSMenuItem *)sender {
	[[SyncedDocumentsController sharedInstance] beginSync:sender];
}

- (IBAction)openSyncedDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[sender representedObject] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

- (IBAction)openSyncedDocumentsFolder:(NSMenuItem *)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[[NSUserDefaults standardUserDefaults] stringForKey:SyncedDocumentsFolderKey]]];
}

- (IBAction)openSyncedDocumentsWebsite:(NSMenuItem *)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[[SyncedDocumentsController sharedInstance] serviceRootURLString] stringByAppendingString:@"/documents/"]]];
}

- (IBAction)toggleSyncedDocumentsAuthentication:(id)sender {
	[[SyncedDocumentsController sharedInstance] toggleAuthentication:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = [menuItem action];
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	
	if (action == @selector(toggleSyncedDocumentsAuthentication:)) {
		if (syncedDocumentsController.serviceUsername != nil) {
			[menuItem setTitle:[NSString stringWithFormat:BLocalizedString(@"Sign Out (%@)", nil), syncedDocumentsController.serviceUsername]];
		} else {
			[menuItem setTitle:BLocalizedString(@"Sign In / Create Account...", nil)];
		}
	} else if (action == @selector(beginSync:)) {
		return syncedDocumentsController.serviceUsername != nil;
	} else if (action == @selector(openSyncedDocumentsWebsite:)) {
		return syncedDocumentsController.serviceUsername != nil;
	}
	
	return YES;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		if ([[each representedObject] isKindOfClass:[NSURL class]] || [each isSeparatorItem]) {
			[menu removeItem:each];
		}
	}
	
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	
	if (syncedDocumentsController.serviceUsername != nil) {
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		NSMutableArray *menuItems = [NSMutableArray array];
		BOOL addedSeparator = NO;
		
		for (NSString *eachLocalSyncedDocumentPath in [SyncedDocumentsControllerDelegate localSyncedDocumentPaths]) {
			NSURL *eachLocalSyncedDocumentURL = [NSURL fileURLWithPath:eachLocalSyncedDocumentPath];;

			if (!addedSeparator) {
				addedSeparator = YES;
				[menuItems addObject:[NSMenuItem separatorItem]];
			}
			
			NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:[SyncedDocumentsControllerDelegate displayNameForSyncedDocument:eachLocalSyncedDocumentURL] action:@selector(openSyncedDocument:) keyEquivalent:@""];
			[eachMenuItem setRepresentedObject:eachLocalSyncedDocumentURL];
			NSImage *icon = [workspace iconForFile:[eachLocalSyncedDocumentURL path]];
			[icon setSize:NSMakeSize(16, 16)];
			[eachMenuItem setImage:icon];
			[eachMenuItem setTarget:self];
			[menuItems addObject:eachMenuItem];
		}
				
		[menuItems sortUsingDescriptors:[NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES] autorelease]]];
		
		for (NSMenuItem *eachMenuItem in menuItems) {
			[menu addItem:eachMenuItem];
		}
	}
}

#pragma mark SyncedDocumentsController Callbacks

- (void)documentsControllerSyncNewCredentials:(SyncedDocumentsController *)documentsController {
	BSyncedDocumentsAuthenticationWindowController *authenticationWindowController = [[[BSyncedDocumentsAuthenticationWindowController alloc] init] autorelease];
	NSInteger result = [NSApp runModalForWindow:[authenticationWindowController window]];
	
	if (result == NSOKButton) {
		[documentsController setServiceUsername:authenticationWindowController.username];
		[documentsController setServicePassword:authenticationWindowController.password];
		[documentsController beginSync:nil];
	}
}

- (void)documentsControllerWillBeginSync:(SyncedDocumentsController *)documentsController {	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:[[SyncedDocumentsController sharedInstance] managedObjectContext]];
	 
	[[BSyncedDocumentsSyncWindowController sharedInstance] showWindow:nil];
	[BSyncedDocumentsSyncWindowController sharedInstance].progress = 0.5;
	
	for (NSDocument *eachDocument in [[NSDocumentController sharedDocumentController] documents]) {
		if ([eachDocument isKindOfClass:[BDocument class]]) {
			if ([(BDocument *)eachDocument fromSyncedDocument]) {
				[eachDocument saveDocument:nil];
			}
		}
	}

	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];

	NSError *error = nil;
	NSMutableArray *syncedDocuments = [[[syncedDocumentsController documents:&error] mutableCopy] autorelease];
	NSMutableDictionary *fileAliasPathsToSyncedDocuments = [NSMutableDictionary dictionary];
	NSString *syncedDocumentsFolder = [SyncedDocumentsControllerDelegate syncedDocumentsFolder];
		
	// 1. Update mapping of database documents to disk documents. If mapping fails schedule database document for user delete.
	if (!syncedDocuments) {
		BLogError([error description]);
	} else {
		for (SyncedDocument *eachSyncedDocument in [syncedDocuments copy]) {
			NDAlias *eachFileAlias = [NDAlias aliasWithData:eachSyncedDocument.fileAliasData];
			NSString *eachFileAliasPath = [eachFileAlias path];
			if (eachFileAliasPath) {
				[fileAliasPathsToSyncedDocuments setObject:eachSyncedDocument forKey:eachFileAliasPath];
				if ([eachFileAlias changed]) {
					eachSyncedDocument.fileAliasData = [eachFileAlias data];
				}
			} else {
				if (![syncedDocumentsController userDeleteDocument:eachSyncedDocument error:&error]) {
					NSLog([error description]);
				}
				[syncedDocuments removeObject:eachSyncedDocument];
			}
		}
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	//NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	
	// 2. Scan file system, updating database to match.
	for (NSString *eachLocalSyncedDocumentPath in [SyncedDocumentsControllerDelegate localSyncedDocumentPaths]) {
		SyncedDocument *eachSyncedDocument = [fileAliasPathsToSyncedDocuments objectForKey:eachLocalSyncedDocumentPath];
		NSDictionary *fileAttributes = [fileManager fileAttributesAtPath:eachLocalSyncedDocumentPath traverseLink:YES];
		NSString *name = [eachLocalSyncedDocumentPath substringFromIndex:[syncedDocumentsFolder length]];

		// 2.a If mapping from filesystem to database document. Then update database document if needed.
		if (eachSyncedDocument) {
			if ([eachSyncedDocument isUpdated] || abs(floor([eachSyncedDocument.modified timeIntervalSinceDate:[fileAttributes objectForKey:NSFileModificationDate]])) > 1) {
				NSString *eachLocalSyncedDocumentPathContent = [NSString stringWithContentsOfFile:eachLocalSyncedDocumentPath encoding:NSUTF8StringEncoding error:&error];
				if (eachLocalSyncedDocumentPathContent) {
					eachSyncedDocument.name = name;
					eachSyncedDocument.content = eachLocalSyncedDocumentPathContent;
					eachSyncedDocument.modified = [fileAttributes objectForKey:NSFileModificationDate];
				} else {
					BLogWarning(@"Failed to load text file: %@", eachLocalSyncedDocumentPath);
				}
			}
			[syncedDocuments removeObject:eachSyncedDocument];
		// 2.b If no mapping then create new database document. 
		} else {
			//NSString *uti = [workspace typeOfFile:eachLocalSyncedDocumentPath error:&error];
			//if (uti == nil || [workspace type:uti conformsToType:@"public.plain-text"]) {
				NSString *eachLocalSyncedDocumentPathContent = [NSString stringWithContentsOfFile:eachLocalSyncedDocumentPath encoding:NSUTF8StringEncoding error:&error];			
				if (eachLocalSyncedDocumentPathContent) {
					if (![documentsController newDocumentWithValues:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", [fileAttributes objectForKey:NSFileCreationDate], @"created", [fileAttributes objectForKey:NSFileModificationDate], @"modified", eachLocalSyncedDocumentPathContent, @"content", [[NDAlias aliasWithPath:eachLocalSyncedDocumentPath] data], @"fileAliasData", nil] error:&error]) {
						BLogError([error description]);
					}
				} else {
					BLogWarning(@"Failed to load text file: %@", eachLocalSyncedDocumentPath);
				}
			//}
		}
	}
	
	// 3. For each remaining database document that hasn't been mapped to file system, schedule for delete.
	for (SyncedDocument *eachSyncedDocument in syncedDocuments) {
		eachSyncedDocument.fileAliasData = nil;
		if (![documentsController userDeleteDocument:eachSyncedDocument error:&error]) {
			BLogError([error description]);
		}
	}
	
	if (![syncedDocumentsController save:&error]) {
		BLogError([error description]);
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncedDocumentsManagedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:[[SyncedDocumentsController sharedInstance] managedObjectContext]];
}

- (void)documentsController:(SyncedDocumentsController *)documentsController syncProgress:(CGFloat)progress {
	[BSyncedDocumentsSyncWindowController sharedInstance].progress = progress;	
}

- (void)documentsController:(SyncedDocumentsController *)documentsController syncClient:(HTTPClient *)aClient networkFailed:(NSError *)error {
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	NSString *serviceLabel = [syncedDocumentsController serviceLabel];
	NSString *messageText = [NSString stringWithFormat:NSLocalizedString(@"%@ Sync Network Failed", nil), serviceLabel];
	NSString *informativeText = [NSString stringWithFormat:NSLocalizedString(@"\"%@\".", nil), [error localizedDescription]];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Retry", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeText];
	if ([alert runModal] == NSOKButton) {
		[self beginSync:nil];
	}
}

- (void)documentsController:(SyncedDocumentsController *)documentsController syncClient:(HTTPClient *)aClient failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	NSString *serviceLabel = [syncedDocumentsController serviceLabel];
	NSString *messageText = [NSString stringWithFormat:NSLocalizedString(@"%@ Sync Error", nil), serviceLabel];
	NSString *informativeText = [NSString stringWithFormat:NSLocalizedString(@"%@ (%i)\n\"%@\".", nil), [[aClient.request URL] path], statusCode, [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Retry", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeText];
	if ([alert runModal] == NSOKButton) {
		[self beginSync:nil];
	}
}

- (void)documentsControllerDidCompleteSync:(SyncedDocumentsController *)documentsController conflicts:(NSString *)conflicts {
	[BSyncedDocumentsSyncWindowController sharedInstance].progress = 1.0;
	[[BSyncedDocumentsSyncWindowController sharedInstance] close];
	
	if ([conflicts length] > 0) {
		NSString *serviceLabel = [[SyncedDocumentsController sharedInstance] serviceLabel];
		NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"%@ Conflicts", nil), serviceLabel];
		NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"Some of your edits conflict with recent changes made on %@. Please go to the website to resolve these conflicts.", nil), serviceLabel];
		NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Resolve", nil) alternateButton:BLocalizedString(@"Close", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
		if ([alert runModal] == NSOKButton) {
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[[SyncedDocumentsController sharedInstance] serviceRootURLString] stringByAppendingString:@"/documents/#conflicts"]]];
		}
	}
}

- (NSString *)filenameForSyncedDocument:(SyncedDocument *)syncedDocument {
	NSString *filename = syncedDocument.displayName;
	filename = [filename stringByReplacingOccurrencesOfString:@"/" withString:@":"];
	return filename;
}

- (NSURL *)uniqueLocalURLForSyncedDocument:(SyncedDocument *)syncedDocument {
	NSString *syncedDocumentsFolder = [SyncedDocumentsControllerDelegate syncedDocumentsFolder];
	NDAlias *originalFileAlias = [NDAlias aliasWithData:syncedDocument.fileAliasData];

	if ([originalFileAlias changed]) {
		syncedDocument.fileAliasData = [originalFileAlias data];
	}
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *originalLocalPath = [originalFileAlias path];
	NSString *newLocalPath = [syncedDocumentsFolder stringByAppendingPathComponent:[self filenameForSyncedDocument:syncedDocument]];

	if (![originalLocalPath isEqualToString:newLocalPath]) {
		NSString *uniqueNewLocalPath = newLocalPath;
		NSUInteger i = 1;
		
		while ([fileManager fileExistsAtPath:uniqueNewLocalPath]) {
			uniqueNewLocalPath = [NSString stringWithFormat:@"%@ %i", newLocalPath, i];		
			i++;
		}
		
		newLocalPath = uniqueNewLocalPath;
	}
		
	return [NSURL fileURLWithPath:newLocalPath];
}

- (void)syncedDocumentsManagedObjectContextDidSave:(NSNotification *)notification {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSMutableDictionary *localFileAttributes = [[SyncedDocumentsControllerDelegate localFileAttributes] mutableCopy];
	
	// 1. For each inserted database document (from server) map the documents content to the file system.
	for (SyncedDocument *eachInserted in [[notification userInfo] objectForKey:NSInsertedObjectsKey]) {
		NSURL *eachNewLocalFileURL = [self uniqueLocalURLForSyncedDocument:eachInserted];
		
		[localFileAttributes setObject:eachInserted.created forKey:NSFileCreationDate];
		[localFileAttributes setObject:eachInserted.modified forKey:NSFileModificationDate];
		
		if (![fileManager createFileAtPath:[eachNewLocalFileURL path] contents:[eachInserted.content dataUsingEncoding:NSUTF8StringEncoding] attributes:localFileAttributes]) {
			BLogError(@"Failed to create fileAtPath %@", [eachNewLocalFileURL path]);
		} else {
			eachInserted.fileAliasData = [[NDAlias aliasWithPath:[eachNewLocalFileURL path]] data];
			[NSFileManager setString:[eachInserted.modified description] forKey:@"BDocumentsLastSyncDate" atPath:[eachNewLocalFileURL path] traverseLink:YES];
		}
	}

	// 2. For each updated document sync changes back to file sysem.
	for (SyncedDocument *eachUpdated in [[notification userInfo] objectForKey:NSUpdatedObjectsKey]) {
		NDAlias *eachUpdatedFileAlias = [NDAlias aliasWithData:eachUpdated.fileAliasData];
		NSString *eachLocalFilePath = [eachUpdatedFileAlias path];
		NSURL *eachNewLocalFileURL = [self uniqueLocalURLForSyncedDocument:eachUpdated];
		NSURL *eachLocalFileURL = nil;

		// 2.a If mapping to file system isn't broken, update alias and update file at that path.
		if (eachLocalFilePath) {
			if ([eachUpdatedFileAlias changed]) {
				eachUpdated.fileAliasData = [eachUpdatedFileAlias data];
			}
			eachLocalFileURL = [NSURL fileURLWithPath:eachLocalFilePath];
		}

		BDocument *eachDocument = [[NSDocumentController sharedDocumentController] documentForURL:eachLocalFileURL];

		if (![eachLocalFileURL isEqual:eachNewLocalFileURL]) {
			if (eachLocalFileURL) {
				if (![fileManager moveItemAtPath:[eachLocalFileURL path] toPath:[eachNewLocalFileURL path] error:&error]) {
					BLogError([error description]);
				}
			}
		}
		
		if (eachDocument) {
			if (![[eachDocument fileURL] isEqual:eachNewLocalFileURL]) {
				[eachDocument setFileURL:eachNewLocalFileURL];
			}
			[eachDocument setTextContents:eachUpdated.content];
			[eachDocument saveDocument:nil];
		} else {
			if (![[eachUpdated.content dataUsingEncoding:NSUTF8StringEncoding] writeToURL:eachNewLocalFileURL atomically:NO]) {
				BLogError(@"Failed to create fileAtPath %@", [eachNewLocalFileURL path]);
			}
		}

		eachUpdated.fileAliasData = [[NDAlias aliasWithURL:eachNewLocalFileURL] data];
		[localFileAttributes setObject:eachUpdated.modified forKey:NSFileModificationDate];
		[fileManager setAttributes:localFileAttributes ofItemAtPath:[eachNewLocalFileURL path] error:NULL];
		[NSFileManager setString:[eachUpdated.modified description] forKey:@"BDocumentsLastSyncDate" atPath:[eachNewLocalFileURL path] traverseLink:YES];
		[[eachDocument windowControllers] makeObjectsPerformSelector:@selector(synchronizeWindowTitleWithDocumentName)];
	}

	// 3. For each deleted database document (deleted on server) remove file system representation.
	for (SyncedDocument *eachDeleted in [[notification userInfo] objectForKey:NSDeletedObjectsKey]) {
		if (![eachDeleted.userDeleted boolValue]) {
			NDAlias *eachDeletedFileAlias = [NDAlias aliasWithData:eachDeleted.fileAliasData];
			NSString *eachDeletedFilePath = [eachDeletedFileAlias path];
			if (eachDeletedFilePath) {
				BDocument *eachDocument = [[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:eachDeletedFilePath]];
				if (![fileManager removeItemAtPath:eachDeletedFilePath error:&error]) {
					BLogError([error description]);
				}
				// XXX should show sheet. This document has been deleted on the server. Close or save as.
			}
		}

	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:[[SyncedDocumentsController sharedInstance] managedObjectContext]];

	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	if (![syncedDocumentsController save:&error]) {
		BLogError([error description]);
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncedDocumentsManagedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:[[SyncedDocumentsController sharedInstance] managedObjectContext]];
}

@end

@implementation BSyncedDocumentsNameWindowController

- (id)init {
	if (self = [super initWithWindowNibName:@"BSyncedDocumentsNameWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	NSString *serviceLabel = [[SyncedDocumentsController sharedInstance] serviceLabel];
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

@implementation BSyncedDocumentsAuthenticationWindowController

- (id)init {
	return [self initWithUsername:nil password:nil];
}

- (id)initWithUsername:(NSString *)aUsername password:(NSString *)aPassword {
	if (self = [super initWithWindowNibName:@"BSyncedDocumentsAuthenticationWindow"]) {
		self.username = aUsername;
		self.password = aPassword;
	}
	return self;
}

- (void)awakeFromNib {
	NSString *serviceLabel = [[SyncedDocumentsController sharedInstance] serviceLabel];
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
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[[SyncedDocumentsController sharedInstance] serviceRootURLString]]];
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

@implementation BSyncedDocumentsSyncWindowController

+ (BSyncedDocumentsSyncWindowController *)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id)init {
	if (self = [super initWithWindowNibName:@"BSyncedDocumentsSyncWindow"]) {
	}
	return self;
}

- (void)awakeFromNib {
	[progressIndicator setUsesThreadedAnimation:YES];
	[progressIndicator setMaxValue:1.0];
	[[self window] setTitle:[NSString stringWithFormat:BLocalizedString(@"%@ Sync...", nil), [[SyncedDocumentsController sharedInstance] serviceLabel]]];
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
	[[SyncedDocumentsController sharedInstance] cancelSync:nil];
}

- (void)close {
	[super close];
	[progressIndicator stopAnimation:nil];
}

@end

NSString *SyncedDocumentsFolderKey = @"SyncedDocumentsFolderKey";
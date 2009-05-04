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


@implementation SyncedDocumentsControllerDelegate

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
															 [[[NSFileManager defaultManager] processesApplicationSupportFolder] stringByAppendingPathComponent:[[SyncedDocumentsController sharedInstance] serviceLabel]], SyncedDocumentsFolderKey,
															 nil]];
}

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

+ (BOOL)isSyncedDocumentURL:(NSURL *)url {
	return [[url path] rangeOfString:[self syncedDocumentsEditableFilesFolder]].location == 0;
}

+ (SyncedDocument *)syncedDocumentForEditableFileURL:(NSURL *)url {
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	NSURL *URIRepresentation = [NSURL URLWithString:[NSString stringWithFormat:@"x-coredata://%@", [[[[url path] stringByDeletingLastPathComponent] lastPathComponent] stringByReplacingOccurrencesOfString:@"_" withString:@"/"]]];
	NSManagedObjectID *objectID = [syncedDocumentsController.persistentStoreCoordinator managedObjectIDForURIRepresentation:URIRepresentation];
	if (objectID) {
		return (id) [syncedDocumentsController.managedObjectContext objectWithID:objectID];
	} else {
		return nil;
	}
}

+ (NSString *)validFilenameForSyncedDocument:(SyncedDocument *)syncedDocument {
	NSString *name = syncedDocument.displayName;
	name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];	
	if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
		name = @"reserved";
	}
	if ([name length] > 255) {
		name = [name substringToIndex:255];
	}
	return name;
}

+ (NSURL *)editableFileURLForSyncedDocument:(SyncedDocument *)syncedDocument {
	NSURL *URIRepresentation = [[syncedDocument objectID] URIRepresentation];
	NSString *normalizedPath = [[URIRepresentation path] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	return [NSURL fileURLWithPath:[[NSString stringWithFormat:@"%@/%@%@", [self syncedDocumentsEditableFilesFolder], [URIRepresentation host], normalizedPath] stringByAppendingPathComponent:[self validFilenameForSyncedDocument:syncedDocument]]];
}

+ (NSString *)displayNameForSyncedDocument:(NSURL *)url {
	SyncedDocument *syncedDocument = [self syncedDocumentForEditableFileURL:url];
	NSDate *syncModificationDate = syncedDocument.modified;
	NSDate *localModificationDate = [[[NSFileManager defaultManager] fileAttributesAtPath:[url path] traverseLink:YES] objectForKey:NSFileModificationDate];
	int difference = abs(floor([syncModificationDate timeIntervalSinceDate:localModificationDate]));
	
	if (difference > 0) {
		return [NSString stringWithFormat:@"%@ (Sync)", syncedDocument.name];
		//return [NSString stringWithFormat:@"%@ (↺)", syncedDocument.name];
	} else {
		return syncedDocument.name;
	}
}

+ (NSString *)syncedDocumentsFolder {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *syncedDocumentsFolder = [[NSUserDefaults standardUserDefaults] objectForKey:SyncedDocumentsFolderKey];
	if ([fileManager createDirectoriesForPath:syncedDocumentsFolder]) {
		return syncedDocumentsFolder;
	}
	return nil;
}

+ (NSString *)syncedDocumentsEditableFilesFolder {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *syncedDocumentsEditableFiles = [[self syncedDocumentsFolder] stringByAppendingPathComponent:@"SyncedDocumentsEditableFiles"];
	if ([fileManager createDirectoriesForPath:syncedDocumentsEditableFiles]) {
		return syncedDocumentsEditableFiles;
	}
	return nil;
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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncedDocumentsManagedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:[[SyncedDocumentsController sharedInstance] managedObjectContext]];
}

#pragma mark Actions

- (IBAction)beginSync:(NSMenuItem *)sender {
	[[SyncedDocumentsController sharedInstance] beginSync:sender];
}

- (IBAction)newSyncedDocument:(NSMenuItem *)sender {
	BSyncedDocumentsNameWindowController *nameWindowController = [[BSyncedDocumentsNameWindowController alloc] init];
	[[nameWindowController window] center];
	NSInteger result = [NSApp runModalForWindow:[nameWindowController window]];	
	
	if (result == NSOKButton) {
		NSError *error = nil;
		NSMutableDictionary *newDocumentValues = [NSMutableDictionary dictionary];
		NSString *name = [nameWindowController.name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if ([name length] == 0) {
			name = BLocalizedString(@"Untitled", nil);
		}
		
		[newDocumentValues setObject:name forKey:@"name"];
		
		NSString *content = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"CloudWelcomeText" ofType:@"txt"] encoding:NSUTF8StringEncoding error:&error];
		if (content) {
			[newDocumentValues setObject:content forKey:@"content"];
		}
		
		SyncedDocument *newDocument = [[SyncedDocumentsController sharedInstance] newDocumentWithValues:newDocumentValues error:&error];
		
		if (!newDocument) {
			NSBeep();
			BLogError([error description]);
		} else {
			[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:newDocument] display:YES error:&error];
		}
	}
}

- (IBAction)openSyncedDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[sender representedObject] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

- (IBAction)deleteSyncedDocument :(id)sender {
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	BDocumentWindowController *windowController = [NSApp currentDocumentWindowController];
	NSString *messageText = [NSString stringWithFormat:BLocalizedString(@"Are you sure that you want to delete this document from %@?", nil), syncedDocumentsController.serviceLabel];
	NSString *informativeTextText = [NSString stringWithFormat:BLocalizedString(@"If you choose \"Delete\" this document will be deleted from your computer and then deleted from %@ next time you sync.", nil), syncedDocumentsController.serviceLabel];
	NSAlert *alert = [NSAlert alertWithMessageText:messageText defaultButton:BLocalizedString(@"Delete", nil) alternateButton:BLocalizedString(@"Cancel", nil) otherButton:nil informativeTextWithFormat:informativeTextText];
	[alert beginSheetModalForWindow:[windowController window] modalDelegate:self didEndSelector:@selector(deleteSyncedDocumentDidEnd:returnCode:contextInfo:) contextInfo:windowController];
}

- (void)deleteSyncedDocumentDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(BDocumentWindowController *)windowController {
	if (returnCode == NSOKButton) {
		NSError *error = nil;
		BDocument *document = [windowController document];
		SyncedDocument *syncedDocument = [SyncedDocumentsControllerDelegate syncedDocumentForEditableFileURL:[document fileURL]];
		
		if (syncedDocument) {
			[document saveDocument:nil];
			[document close];
			if (![[SyncedDocumentsController sharedInstance] userDeleteDocument:syncedDocument error:&error]) {
				BLogError([error description]);
			}
		}
	}
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
	} else if (action == @selector(newSyncedDocument:)) {
		return syncedDocumentsController.serviceUsername != nil;
	} else if (action == @selector(deleteSyncedDocument :)) {
		return syncedDocumentsController.serviceUsername != nil && [[NSApp currentDocument] fromSyncedDocument];
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
		BOOL addedSeparator = NO;
		NSError *error = nil;
		NSMutableArray *menuItems = [NSMutableArray array];
		
		for (SyncedDocument *eachSyncedDocument in [syncedDocumentsController documents:&error]) {
			if (![eachSyncedDocument.userDeleted boolValue]) {
				NSURL *eachEditableFileURL = [SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:eachSyncedDocument];
				if (!addedSeparator) {
					addedSeparator = YES;
					[menuItems addObject:[NSMenuItem separatorItem]];
				}
				
				NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:[SyncedDocumentsControllerDelegate displayNameForSyncedDocument:eachEditableFileURL] action:@selector(openSyncedDocument:) keyEquivalent:@""];
				[eachMenuItem setRepresentedObject:eachEditableFileURL];
				NSImage *icon = [workspace iconForFile:[eachEditableFileURL path]];
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
	[[BSyncedDocumentsSyncWindowController sharedInstance] showWindow:nil];
	[BSyncedDocumentsSyncWindowController sharedInstance].progress = 0.5;
	
	for (NSDocument *eachDocument in [[NSDocumentController sharedDocumentController] documents]) {
		if ([eachDocument isKindOfClass:[BDocument class]]) {
			if ([(BDocument *)eachDocument fromSyncedDocument]) {
				[eachDocument saveDocument:nil];
			}
		}
	}
	
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	SyncedDocumentsController *syncedDocumentsController = [SyncedDocumentsController sharedInstance];
	NSArray *syncedDocuments = [syncedDocumentsController documents:&error];
	BOOL isDirectory;
	
	if (!syncedDocuments) {
		BLogError([error description]);
	}
	
	for (SyncedDocument *eachSyncedDocument in syncedDocuments) {
		NSString *eachEditableFilePath = [[SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:eachSyncedDocument] path];
		
		if ([fileManager fileExistsAtPath:eachEditableFilePath isDirectory:&isDirectory] && !isDirectory) {
			NSString *editableFileContent = [NSString stringWithContentsOfFile:eachEditableFilePath encoding:NSUTF8StringEncoding error:&error];
			if (editableFileContent) {
				if (![eachSyncedDocument.content isEqualToString:editableFileContent]) {
					eachSyncedDocument.content = editableFileContent;
				}
			} else {
				BLogError([error description]);
			}
		}
	}
	
	if (![syncedDocumentsController save:&error]) {
		BLogError([error description]);
	}
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

- (BOOL)deleteEditableFileForSyncedDocument:(SyncedDocument *)syncedDocument {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *eachEditableFileURL = [SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:syncedDocument];
	NSDocument *eachDocument = [[NSDocumentController sharedDocumentController] documentForURL:eachEditableFileURL];
	if (eachDocument) {
		[eachDocument saveDocument:nil];
		[eachDocument close];
	}
	if ([fileManager fileExistsAtPath:[eachEditableFileURL path]]) {
		if (![fileManager removeItemAtPath:[[eachEditableFileURL path] stringByDeletingLastPathComponent] error:&error]) {
			return NO;
		}
	}
	return YES;
}

- (void)syncedDocumentsManagedObjectContextDidSave:(NSNotification *)notification {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSMutableDictionary *localFileAttributes = [[SyncedDocumentsControllerDelegate localFileAttributes] mutableCopy];
	
	for (SyncedDocument *eachInserted in [[notification userInfo] objectForKey:NSInsertedObjectsKey]) {
		NSURL *eachEditableFileURL = [SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:eachInserted];
		
		if (![fileManager createDirectoriesForPath:[[eachEditableFileURL path] stringByDeletingLastPathComponent]]) {
			BLogError(@"");
		}

		[localFileAttributes setObject:eachInserted.modified forKey:NSFileModificationDate];
		
		if (![fileManager createFileAtPath:[eachEditableFileURL path] contents:[eachInserted.content dataUsingEncoding:NSUTF8StringEncoding] attributes:localFileAttributes]) {
			BLogError(@"");
		}
	}

	for (SyncedDocument *eachUpdated in [[notification userInfo] objectForKey:NSUpdatedObjectsKey]) {
		if ([eachUpdated.userDeleted boolValue]) {
			if (![self deleteEditableFileForSyncedDocument:eachUpdated]) {
				BLogError(@"");
			}
		} else {
			NSURL *eachEditableFileURL = [SyncedDocumentsControllerDelegate editableFileURLForSyncedDocument:eachUpdated];
			NSDocument *eachDocument = [[NSDocumentController sharedDocumentController] documentForURL:eachEditableFileURL];
			
			if (![fileManager createDirectoriesForPath:[[eachEditableFileURL path] stringByDeletingLastPathComponent]]) {
				BLogError(@"");
			}
			
			[localFileAttributes setObject:eachUpdated.modified forKey:NSFileModificationDate];

			if (![fileManager createFileAtPath:[eachEditableFileURL path] contents:[eachUpdated.content dataUsingEncoding:NSUTF8StringEncoding] attributes:localFileAttributes]) {
				BLogError(@"");
			}
			
			if (eachDocument) {
				if (![[eachDocument fileURL] isEqual:eachEditableFileURL]) {
					[eachDocument setFileURL:eachEditableFileURL];
					if ([eachDocument respondsToSelector:@selector(_resetMoveAndRenameSensing)]) {
						[eachDocument performSelector:@selector(_resetMoveAndRenameSensing)];
					}
				}
				[eachDocument checkForModificationOfFileOnDisk];
				[eachDocument saveDocument:nil];				
				[fileManager setAttributes:localFileAttributes ofItemAtPath:[eachEditableFileURL path] error:NULL];
				[[eachDocument windowControllers] makeObjectsPerformSelector:@selector(synchronizeWindowTitleWithDocumentName)];
			}
	
			NSString *eachEditableFileURLFolderPath = [[eachEditableFileURL path] stringByDeletingLastPathComponent];
			for (NSString *eachFilename in [fileManager contentsOfDirectoryAtPath:eachEditableFileURLFolderPath error:nil]) {
				NSString *eachPath = [eachEditableFileURLFolderPath stringByAppendingPathComponent:eachFilename];
				if (![eachPath isEqualToString:[eachEditableFileURL path]]) {
					[fileManager removeItemAtPath:eachPath error:nil]; // delete old files in case of rename.
				}
			}
		}
	}

	for (SyncedDocument *eachDeleted in [[notification userInfo] objectForKey:NSDeletedObjectsKey]) {
		if (![self deleteEditableFileForSyncedDocument:eachDeleted]) {
			BLogError(@"");
		}
	}
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
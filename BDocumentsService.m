//
//  BDocumentsService.m
//  BDocuments
//
//  Created by Jesse Grosjean on 1/29/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "BDocumentsService.h"
#import "BDocuments.h"
#import "BDocumentsHTTPFetcher.h"
#import "BDiffMatchPatch.h"
#import "NSString+SBJSON.h"
#import "BDocumentsServiceAuthenticationWindowController.h"
#import "BDocumentsServiceSyncWindowController.h"


@implementation BDocumentsService

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

+ (BOOL)isDocumentURLManagedByDocumentsService:(NSURL *)aURL {
	NSString *path = [aURL path];
	NSString *name = [NSFileManager stringForKey:@"BDocumentName" atPath:path traverseLink:YES];
	NSString *version = [NSFileManager stringForKey:@"BDocumentVersion" atPath:path traverseLink:YES];
	return [version length] > 0 && [name length] > 0;
}

+ (NSString *)displayNameForDocumentsServiceDocument:(NSURL *)aURL {
	NSString *path = [aURL path];
	NSString *name = [NSFileManager stringForKey:@"BDocumentName" atPath:path traverseLink:YES];
	return name;
}

- (id)init {
	if (self = [super init]) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *sync = [fileManager.processesApplicationSupportFolder stringByAppendingPathComponent:@"Sync"];
		
		service = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsService"] retain];
		serviceLabel = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsServiceLabel"] retain];
		serviceRootURLString = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"BDocumentsServiceURL"] retain];
		localDocumentsPath = [sync stringByAppendingPathComponent:@"Documents"];
		localNewDocumentsPath = [sync stringByAppendingPathComponent:@"New"];
		localDocumentShadowsPath = [sync stringByAppendingPathComponent:@"Shadows"];
		
		if (![fileManager createDirectoriesForPath:localDocumentsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localNewDocumentsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentShadowsPath]) {
			return nil;
		}
		
		activeHandlers = [[NSMutableArray alloc] init];
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
	totalActiveHandlers = 0;
	
	for (BDocument *each in [[NSDocumentController sharedDocumentController] documents]) {
		if (each.fromDocumentsService) {
			[each saveDocument:nil];
		}
	}
	[self addActiveHandler:[[[BDocumentsServiceGetDocumentsHandler alloc] init] autorelease]];
}

- (IBAction)cancelSync:(id)sender {
	for (BDocumentsServiceHandler *each in [[activeHandlers copy] autorelease]) {
		[each cancel];
	}
}

- (IBAction)openDocumentsService:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[serviceRootURLString stringByAppendingPathComponent:@"documents"]]];
}

- (IBAction)openDocumentsServiceAboutPage:(id)sender {
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
	if ([menuItem action] == @selector(toggleDocumentsServiceAuthentication:)) {
		if (self.serviceUserName != nil) {
			[menuItem setTitle:[NSString stringWithFormat:@"Sign Out (%@)", self.serviceUserName]];
		} else {
			[menuItem setTitle:@"Sign In..."];
		}
	}
	return YES;
}


- (NSArray *)newLocalDocuments:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *newLocalDocumentFileNames = [fileManager contentsOfDirectoryAtPath:localNewDocumentsPath error:error];
	if (!newLocalDocumentFileNames) {
		BLogError(@"Failed to get new local document list, aborting sync");
	} else {
		NSMutableArray *newLocalDocuments = [NSMutableArray array];
		for (NSString *each in newLocalDocumentFileNames) {
			NSString *eachNewLocalPath = [localNewDocumentsPath stringByAppendingPathComponent:each];
			[newLocalDocuments addObject:eachNewLocalPath];
		}
		return newLocalDocuments;
	}
	return nil;
}

- (NSArray *)localDocuments:(NSDictionary *)serverDocumentsByID error:(NSError **)error {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *localDocumentFileNames = [fileManager contentsOfDirectoryAtPath:localDocumentsPath error:error];
	if (!localDocumentFileNames) {
		BLogError(@"Failed to get local document list, aborting sync");
	} else {
		NSMutableArray *localDocuments = [NSMutableArray array];
		for (NSString *each in localDocumentFileNames) {
			NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
			NSString *eachDocumentID = [NSFileManager stringForKey:@"BDocumentID" atPath:eachLocalPath traverseLink:YES];
			
			if ([eachDocumentID length] > 0) {
				NSString *eachLocalContent = [NSString stringWithContentsOfFile:eachLocalPath encoding:NSUTF8StringEncoding error:error];
				NSString *eachLocalVersion = [NSFileManager stringForKey:@"BDocumentVersion" atPath:eachLocalPath traverseLink:YES];
				NSString *eachLocalName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalPath traverseLink:YES];
				NSString *eachLocalShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:eachDocumentID];
				NSString *eachLocalShadowContent = [NSString stringWithContentsOfFile:eachLocalShadowPath encoding:NSUTF8StringEncoding error:error];
				NSString *eachServerVersion = [[[serverDocumentsByID objectForKey:eachDocumentID] objectForKey:@"version"] description];
				BDocumentsServiceDocument *eachLocalDocument = [[[BDocumentsServiceDocument alloc] initWithDocumentID:eachDocumentID localVersion:eachLocalVersion serverVersion:eachServerVersion name:eachLocalName content:eachLocalContent localShadowContent:eachLocalShadowContent] autorelease];
				[localDocuments addObject:eachLocalDocument];
			}
		}
		return localDocuments;
	}
	return nil;
}

- (void)updateLocal:(BDocumentsServiceDocument *)aDocument {
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

	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:aDocument.documentID];
	NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:aDocument.documentID];
	
	if ([aDocument.content writeToFile:documentPath atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
		[NSFileManager setString:aDocument.documentID forKey:@"BDocumentID" atPath:documentPath traverseLink:YES];
		if (aDocument.name) [NSFileManager setString:aDocument.name forKey:@"BDocumentName" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:[aDocument.serverVersion description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];
		
		if (localFileattributes) {
			if (![fileManager setAttributes:localFileattributes ofItemAtPath:documentPath error:&error]) {
				NSLog(@"error");
			}
		}
		
		[fileManager removeFileAtPath:documentShadowPath handler:nil];
		
		if (![fileManager copyPath:documentPath toPath:documentShadowPath handler:nil]) {
			BLogError(@"Failed to update local shadow document at path %@", documentShadowPath);
		} else {
			if (aDocument.name) [NSFileManager setString:aDocument.name forKey:@"BDocumentName" atPath:documentShadowPath traverseLink:YES];
		}
	} else {
		BLogError(@"Failed to update local document at path %@", documentPath);
	}
	
	[[[NSDocumentController sharedDocumentController] documentForURL:[NSURL fileURLWithPath:documentPath]] checkForModificationOfFileOnDisk];
}

- (void)deleteLocal:(BDocumentsServiceDocument *)aDocument {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:aDocument.documentID];
	NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:aDocument.documentID];
	
	if (![fileManager removeItemAtPath:documentPath error:&error]) {
		BLogError(@"Failed to remove local document deleted from server %@", documentPath);
	}
	
	if (![fileManager removeItemAtPath:documentShadowPath error:&error]) {
		BLogError(@"Failed to remove local shadow document deleted from server %@", documentShadowPath);							
	}
}

- (void)addActiveHandler:(BDocumentsServiceHandler *)aHandler {
	BDocumentsServiceSyncWindowController *syncWindowController = [BDocumentsServiceSyncWindowController sharedInstance];
	[activeHandlers addObject:aHandler];
	totalActiveHandlers++;
	if (totalActiveHandlers == 1) {
		[syncWindowController showWindow:nil];
		syncWindowController.progress = 0.5;
	}
}

- (void)removeActiveHandler:(BDocumentsServiceHandler *)aHandler {
	BDocumentsServiceSyncWindowController *syncWindowController = [BDocumentsServiceSyncWindowController sharedInstance];
	[activeHandlers removeObject:aHandler];
	NSUInteger activeCount = [activeHandlers count];
	
	if (activeCount == 0) {
		syncWindowController.progress = 1.0;
		[syncWindowController close];
	} else {
		syncWindowController.progress = 0.5 + ((1.0 - ((float)activeCount / (float)totalActiveHandlers)) / 2.0);
	}
}

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BDocuments.menus.main.file.documentsService"] setDelegate:self];
} 

- (void)menuNeedsUpdate:(NSMenu *)menu {
	BOOL remove = NO;
	for (NSMenuItem *each in [menu itemArray]) {
		if (remove) {
			[menu removeItem:each];
		} else if ([each isSeparatorItem]) {
			remove = YES;
		}
	}

	NSArray *localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:localDocumentsPath error:nil];

	if (self.serviceUserName != nil) {
		NSMutableArray *menuItems = [NSMutableArray array];
		NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
		
		for (NSString *each in localDocuments) {
			NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
			NSURL *eachURL = [NSURL fileURLWithPath:eachLocalPath];
			if ([BDocumentsService isDocumentURLManagedByDocumentsService:eachURL]) {
				NSString *title = [BDocumentsService displayNameForDocumentsServiceDocument:eachURL];
				NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(openDocumentsServiceDocument:) keyEquivalent:@""];
				[eachMenuItem setRepresentedObject:eachLocalPath];
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
	} else {
		[menu addItemWithTitle:BLocalizedString(@"Sign In to List Synced Documents", nil) action:nil keyEquivalent:@""];
	}
}

- (IBAction)openDocumentsServiceDocument:(NSMenuItem *)sender {
	NSError *error = nil;
	if (![[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:[NSURL fileURLWithPath:[sender representedObject]] display:YES error:&error]) {
		[[NSDocumentController sharedDocumentController] presentError:error];
	}
}

@end

@implementation BDocumentsServiceDocument

- (id)initWithData:(NSData *)data {
	NSDictionary *dataDictionary = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];

	if (self = [self initWithDocumentID:[dataDictionary objectForKey:@"id"]
				   localVersion:nil
				  serverVersion:[[dataDictionary objectForKey:@"version"] description]
				   name:[dataDictionary objectForKey:@"name"]
				   content:[dataDictionary objectForKey:@"content"]
			 localShadowContent:nil]) {
	}
	return self;	
}

- (id)initWithData:(NSData *)data content:(NSString *)aString {
	if (self = [self initWithData:data]) {
		[content release];
		content = [aString retain];
	}
	return self;
}

- (id)initWithDocumentID:(NSString *)aDocumentID localVersion:(NSString *)aLocalVersion serverVersion:(NSString *)aServerVersion name:(NSString *)aName content:(NSString *)aContent localShadowContent:(NSString *)aLocalShadowContent {
	if (self = [super init]) {
		documentID = [aDocumentID retain];
		localVersion = [aLocalVersion retain];
		serverVersion = [aServerVersion retain];
		name = [aName retain];
		content = [aContent retain];
		localShadowContent = [aLocalShadowContent retain];
	}
	return self;
}

- (void)dealloc {
	[documentID release];
	[localVersion release];
	[serverVersion release];
	[name release];
	[content release];
	[localShadowContent release];
	[super dealloc];
}

@synthesize documentID;
@synthesize localVersion;
@synthesize serverVersion;
@synthesize name;
@synthesize content;
@synthesize localShadowContent;

- (BOOL)hasLocalEdits {
	return ![content isEqualToString:localShadowContent];
}

- (BOOL)hasServerEdits {
	return ![localVersion isEqualToString:serverVersion];
}

- (BOOL)isDeletedFromServer {
	return serverVersion == nil;
}

- (void)backUpConflicts {
	/*
	 if (![fileManager copyPath:eachLocalPath toPath:[localDocumentsConflictsPath stringByAppendingPathComponent:eachLocalID] handler:nil]) {
	 BLogError(@"Local changes to document are being lost because document was deleted from server %@ and failed to copy to %@", eachLocalID, [localDocumentsConflictsPath stringByAppendingPathComponent:eachLocalID]);
	 } else {
	 BLogError(@"Local changes to document %@ as being saved to Conflicts because document was deleted from server but there are local changes", eachLocalID);
	 }	 
	 */
}

- (void)applyEdits:(NSDictionary *)edits {
	if ([edits objectForKey:@"version"]) {
		[localVersion autorelease];
		localVersion = [[[edits objectForKey:@"version"] description] retain];
		[serverVersion autorelease];
		serverVersion = [[[edits objectForKey:@"version"] description] retain];
	}
	
	if ([edits objectForKey:@"name"]) {
		[name autorelease];
		name = [[edits objectForKey:@"name"] retain];
	}
	
	if ([edits objectForKey:@"patches"] != nil && [[edits objectForKey:@"patches"] length] > 0) {
		BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];
		NSMutableArray *patches = [diffMatchPatch patchFromText:[edits objectForKey:@"patches"]];
		NSString *newContent = [[diffMatchPatch patchApply:patches text:localShadowContent] objectAtIndex:0];
		[content release];
		content = [newContent retain];
	}
}

- (void)updateLocal {
	[[BDocumentsService sharedInstance] updateLocal:self];
}

- (void)delete {
	if ([self hasLocalEdits]) {
		[self backUpConflicts];
	}
	
	[[BDocumentsService sharedInstance] deleteLocal:self];
}

@end


@implementation BDocumentsServiceHandler

- (id)initWithFetcher:(BDocumentsHTTPFetcher *)aFetcher {
	if (self = [super init]) {
		request = [aFetcher request];
		fetcher = [aFetcher retain];
	}
	return self;
}

- (void)dealloc {
	[request release];
	[fetcher release];
	[super dealloc];
}

@synthesize fetcher;

- (void)clientLogin {
	BDocumentsServiceAuthenticationWindowController *authenticationWindowController = [[[BDocumentsServiceAuthenticationWindowController alloc] init] autorelease];
	NSInteger result = [NSApp runModalForWindow:[authenticationWindowController window]];
	
	if (result == NSOKButton) {
		BDocumentsService *documentsService = [BDocumentsService sharedInstance];
		NSURL *url = [NSURL URLWithString:@"https://www.google.com/accounts/ClientLogin"];
		NSMutableURLRequest *authTokenRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		BDocumentsHTTPFetcher *authTokenFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:authTokenRequest];
		NSString *postString = [NSString stringWithFormat:@"Email=%@&Passwd=%@&source=%@&service=%@&accountType=%@", [authenticationWindowController.username stringByURLEncodingStringParameter], [authenticationWindowController.password stringByURLEncodingStringParameter], [documentsService.service stringByURLEncodingStringParameter], @"ah", @"GOOGLE"];
		[authTokenFetcher setPostData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
		[authTokenFetcher beginFetchWithDelegate:self];
	} else {
		[[BDocumentsService sharedInstance] cancelSync:nil];
	}
}

- (void)fetcher:(BDocumentsHTTPFetcher *)aFetcher networkFailed:(NSError *)error {
	[[BDocumentsService sharedInstance] removeActiveHandler:self];
	[[NSDocumentController sharedDocumentController] presentError:error];
}

- (void)fetcher:(BDocumentsHTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	if (statusCode == 401 || statusCode == 403) {
		[self clientLogin];
	} else {
		[[BDocumentsService sharedInstance] removeActiveHandler:self];
		// should display error!
	}
}

- (void)fetcher:(BDocumentsHTTPFetcher *)aFetcher finishedWithData:(NSData *)data {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSString *absoluteString = [[[aFetcher request] URL] absoluteString];
	
	if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ServiceLogin"].location == 0) {
		[self clientLogin];
	} else if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
		NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary *responseDict = [BDocumentsHTTPFetcher dictionaryWithResponseString:responseString];
		NSString *authToken = [[responseDict objectForKey:@"Auth"] retain];
		NSString *requestString = [NSString stringWithFormat:@"%@/_ah/login?continue=%@&auth=%@", documentsService.serviceRootURLString, [[[request URL] absoluteString] stringByURLEncodingStringParameter], authToken];
		NSURL *url = [NSURL URLWithString:requestString];
		NSMutableURLRequest *authenticationCookieRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		BDocumentsHTTPFetcher *authenticationCookieFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:authenticationCookieRequest];
		[authenticationCookieFetcher beginFetchWithDelegate:self];
	} else {
		[self handleResponse:data];
	}
	
	[[BDocumentsService sharedInstance] removeActiveHandler:self];
}

- (void)cancel {
	[fetcher stopFetching];
	[[BDocumentsService sharedInstance] removeActiveHandler:self];
}

- (void)handleResponse:(NSData *)data {	
}

@end

@implementation BDocumentsServiceGetDocumentsHandler

- (id)init {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", documentsService.serviceRootURLString]];
	NSMutableURLRequest *getDocumentsRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
	BDocumentsHTTPFetcher *getDocumentsFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:getDocumentsRequest];
	
	if (self = [super initWithFetcher:getDocumentsFetcher]) {
		[getDocumentsFetcher beginFetchWithDelegate:self];
	}
	
	return self;
}

- (void)handleResponse:(NSData *)data {
	NSError *error = nil;
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSArray *documents = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSMutableDictionary *serverDocumentsByID = [[NSMutableDictionary dictionary] retain];
	
	for (NSDictionary *each in documents) {
		[serverDocumentsByID setObject:each forKey:[each objectForKey:@"id"]];
	}
	
	for (BDocumentsServiceDocument *eachLocalDocument in [documentsService localDocuments:serverDocumentsByID error:&error]) {
		if ([eachLocalDocument isDeletedFromServer]) {
			[eachLocalDocument delete];
		} else {
			if ([eachLocalDocument hasLocalEdits]) {
				[documentsService addActiveHandler:[[[BDocumentsServicePostLocalEditsHandler alloc] initWithLocalDocument:eachLocalDocument] autorelease]];
			} else {
				if ([eachLocalDocument hasServerEdits]) {
					[documentsService addActiveHandler:[[[BDocumentsServiceGetServerEditsHandler alloc] initWithLocalDocument:eachLocalDocument] autorelease]];
				}
			}
			[serverDocumentsByID removeObjectForKey:eachLocalDocument.documentID];
		}		
	}
	
	for (NSString *eachServerID in [serverDocumentsByID keyEnumerator]) {
		[documentsService addActiveHandler:[[[BDocumentsServiceGetDocumentHandler alloc] initWithDocumentID:eachServerID] autorelease]];
	}
	
	for (NSString *eachNewDocumentPath in [documentsService newLocalDocuments:&error]) {
		[documentsService addActiveHandler:[[[BDocumentsServicePostNewDocumentHandler alloc] initWithNewDocumentPath:eachNewDocumentPath] autorelease]];
	}
}

@end

@implementation BDocumentsServiceGetDocumentHandler

- (id)initWithDocumentID:(NSString *)documentID {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@", documentsService.serviceRootURLString, documentID]];
	NSMutableURLRequest *getDocumentRequest = [NSMutableURLRequest requestWithURL:url];
	BDocumentsHTTPFetcher *getDocumentFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:getDocumentRequest];

	if (self = [super initWithFetcher:getDocumentFetcher]) {
		[getDocumentFetcher beginFetchWithDelegate:self];
	}
	
	return self;
}

- (void)handleResponse:(NSData *)data {	
	BDocumentsServiceDocument *serverDocument = [[[BDocumentsServiceDocument alloc] initWithData:data] autorelease];
	if (!serverDocument) {
		BLogError(@"Failed to get server document %@", serverDocument.documentID);
	} else {
		[serverDocument updateLocal];
	}
}


@end

@implementation BDocumentsServicePostLocalEditsHandler

- (id)initWithLocalDocument:(BDocumentsServiceDocument *)aLocalDocument {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSMutableURLRequest *postLocalEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits", documentsService.serviceRootURLString, aLocalDocument.documentID]]];
	BDocumentsHTTPFetcher *postLocalEditsFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:postLocalEditsRequest];
	
	if (self = [super initWithFetcher:postLocalEditsFetcher]) {
		BDiffMatchPatch *diffMatchPatch = [[[BDiffMatchPatch alloc] init] autorelease];
		NSString *patches = [diffMatchPatch patchToText:[diffMatchPatch patchMakeText1:aLocalDocument.localShadowContent text2:aLocalDocument.content]];
		[postLocalEditsFetcher setFormURLEncodedPostDictionary:[NSDictionary dictionaryWithObjectsAndKeys:patches, @"patches", aLocalDocument.localVersion, @"version", nil]];
		[postLocalEditsFetcher beginFetchWithDelegate:self];
		localDocument = [aLocalDocument retain];
	}
	return self;
}

- (void)dealloc {
	[localDocument release];
	[super dealloc];
}

- (void)handleResponse:(NSData *)data {	
	NSDictionary *serverEdits = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	[localDocument applyEdits:serverEdits];
	[localDocument updateLocal];
}

@end

@implementation BDocumentsServicePostNewDocumentHandler : BDocumentsServiceHandler

- (id)initWithNewDocumentPath:(NSString *)aNewDocumentPath {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSMutableURLRequest *postLocalEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", documentsService.serviceRootURLString]]];
	BDocumentsHTTPFetcher *postLocalEditsFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:postLocalEditsRequest];
	
	if (self = [super initWithFetcher:postLocalEditsFetcher]) {
		newDocumentPath = aNewDocumentPath;
		newDocumentContent = [NSString stringWithContentsOfFile:newDocumentPath];
		[postLocalEditsFetcher setFormURLEncodedPostDictionary:[NSDictionary dictionaryWithObjectsAndKeys:[newDocumentPath lastPathComponent], @"name", newDocumentContent, @"content", nil]];
		[postLocalEditsFetcher beginFetchWithDelegate:self];
	}
	return self;
}

- (void)dealloc {
	[newDocumentContent release];
	[newDocumentPath release];
	[super dealloc];
}

- (void)handleResponse:(NSData *)data {	
	BDocumentsServiceDocument *localDocument = [[BDocumentsServiceDocument alloc] initWithData:data content:newDocumentContent];
	[localDocument updateLocal];
	if (![[NSFileManager defaultManager] removeFileAtPath:newDocumentPath handler:nil]) {
		NSLog(@"failed to remove new document path");
	}
}

@end

@implementation BDocumentsServiceGetServerEditsHandler

- (id)initWithLocalDocument:(BDocumentsServiceDocument *)aLocalDocument {
	BDocumentsService *documentsService = [BDocumentsService sharedInstance];
	NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
	NSMutableURLRequest *getServerEditsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents/%@/edits/?start=%@&end=%@", documentsService.serviceRootURLString, aLocalDocument.documentID, [NSString stringWithFormat:@"%i", [[numberFormatter numberFromString:aLocalDocument.localVersion] intValue] + 1], aLocalDocument.serverVersion]]];
	BDocumentsHTTPFetcher *getServerEditsFetcher = [BDocumentsHTTPFetcher fetcherWithRequest:getServerEditsRequest];

	if (self = [super initWithFetcher:getServerEditsFetcher]) {
		[getServerEditsFetcher beginFetchWithDelegate:self];
		localDocument = [aLocalDocument retain];
	}
	
	return self;
}

- (void)dealloc {
	[localDocument release];
	[super dealloc];
}

- (void)handleResponse:(NSData *)data {
	NSDictionary *serverEdits = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	[localDocument applyEdits:serverEdits];
	[localDocument updateLocal];
}

@end
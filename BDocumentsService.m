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


@implementation BDocumentsService

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (id)init {
	if (self = [super init]) {
		//serviceRootURLString = @"http://localhost:8093/v1/documents";
		//serviceRootURLString = @"http://writeroom-com.appspot.com";
		serviceRootURLString = @"http://restapitests.appspot.com";
		service = @"restapitests";
		
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *cloud = [fileManager.processesApplicationSupportFolder stringByAppendingPathComponent:@"Cloud"];
		
		localDocumentsPath = [cloud stringByAppendingPathComponent:@"Documents"];
		localDocumentShadowsPath = [cloud stringByAppendingPathComponent:@"Shadows"];
		localDocumentsConflictsPath = [cloud stringByAppendingPathComponent:@"Conflicts"];
		
		if (![fileManager createDirectoriesForPath:localDocumentsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentShadowsPath]) {
			return nil;
		}
		if (![fileManager createDirectoriesForPath:localDocumentsConflictsPath]) {
			return nil;
		}
		
		activeHandlers = [[NSMutableArray alloc] init];
	}
	return self;
}

@synthesize serviceRootURLString;
@synthesize service;

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

- (IBAction)beginSync:(id)sender {
	[self addActiveHandler:[[[BDocumentsServiceGetDocumentsHandler alloc] init] autorelease]];
}

- (IBAction)cancelSync:(id)sender {
	for (BDocumentsServiceHandler *each in [[activeHandlers copy] autorelease]) {
		[each cancel];
	}
}

- (IBAction)openWebsite:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:serviceRootURLString]];
}


- (void)updateLocal:(BDocumentsServiceDocument *)aDocument {
	NSError *error = nil;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *documentPath = [localDocumentsPath stringByAppendingPathComponent:aDocument.documentID];
	NSString *documentShadowPath = [localDocumentShadowsPath stringByAppendingPathComponent:aDocument.documentID];
	
	if ([aDocument.content writeToFile:documentPath atomically:NO encoding:NSUTF8StringEncoding error:&error]) {
		[NSFileManager setString:aDocument.documentID forKey:@"BDocumentID" atPath:documentPath traverseLink:YES];
		if (aDocument.name) [NSFileManager setString:aDocument.name forKey:@"BDocumentName" atPath:documentPath traverseLink:YES];
		[NSFileManager setString:[aDocument.serverVersion description] forKey:@"BDocumentVersion" atPath:documentPath traverseLink:YES];

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
	[activeHandlers addObject:aHandler];
}

- (void)removeActiveHandler:(BDocumentsServiceHandler *)aHandler {
	[activeHandlers removeObject:aHandler];
}

#pragma mark Lifecycle Callback

- (void)applicationDidFinishLaunching {
	[[NSMenu menuForMenuExtensionPoint:@"com.blocks.BDocuments.menus.main.share"] setDelegate:self];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	for (NSMenuItem *each in [menu itemArray]) {
		[menu removeItem:each];
	}
	
	[menu addItemWithTitle:BLocalizedString(@"Open Website", nil) action:@selector(openWebsite:) keyEquivalent:@""];
	[[[menu itemArray] lastObject] setTarget:self];
	
	[menu addItem:[NSMenuItem separatorItem]];
	
	[menu addItemWithTitle:BLocalizedString(@"Synced Documents", nil) action:NULL keyEquivalent:@""];
	
	NSArray *localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:localDocumentsPath error:nil];
	
	for (NSString *each in localDocuments) {
		NSString *eachLocalPath = [localDocumentsPath stringByAppendingPathComponent:each];
		NSString *eachName = [NSFileManager stringForKey:@"BDocumentName" atPath:eachLocalPath traverseLink:YES];
		if ([eachName length] > 0) {
			NSMenuItem *eachMenuItem = [[NSMenuItem alloc] initWithTitle:eachName action:@selector(openDocumentsServiceDocument:) keyEquivalent:@""];
			[eachMenuItem setIndentationLevel:1];
			[eachMenuItem setRepresentedObject:eachLocalPath];
			[eachMenuItem setTarget:self];
			[menu addItem:eachMenuItem];
		}
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	
	[menu addItemWithTitle:BLocalizedString(@"Sync to Website...", nil) action:@selector(sync:) keyEquivalent:@""];
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
		localVersion = [[edits objectForKey:@"version"] retain];
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
	}
}

- (void)fetcher:(BDocumentsHTTPFetcher *)aFetcher networkFailed:(NSError *)error {
}

- (void)fetcher:(BDocumentsHTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	if (statusCode == 401 || statusCode == 403) {
		[self clientLogin];
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
}

- (void)cancel {
	[fetcher stopFetching];
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
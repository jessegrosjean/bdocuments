//
//  DocumentsController.m
//  Documents
//
//  Created by Jesse Grosjean on 4/22/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "SyncedDocumentsController.h"
#import "SyncedDocument.h"
#import "HTTPClient.h"
#import "NSString+SBJSON.h"
#import "NSObject+SBJSON.h"


@interface SyncedDocumentsController (DocumentsPrivate)

- (void)queueClient:(HTTPClient *)aClient;
- (void)beginActiveClient:(HTTPClient *)aClient;
- (void)endActiveClient:(HTTPClient *)aClient;
- (HTTPClient *)GETServerDocuments;

@end

@implementation SyncedDocumentsController

+ (id)sharedInstance {
	static SyncedDocumentsController *sharedInstance = nil;
	if (!sharedInstance) {
		sharedInstance = [[SyncedDocumentsController alloc] init];
	}
	return sharedInstance;
}

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
															 [NSNumber numberWithInteger:52332], DocumentSharingPort,
															 [NSString stringWithFormat:NSLocalizedString(@"%@ Documents", nil), [[NSProcessInfo processInfo] processName]], DocumentSharingServiceName,
															 [NSNumber numberWithBool:YES], DisableAutoLockWhenSharingDocuments,
															 @"change@settings.com", DocumentsDefaultEmail,
															 nil]];
}

#pragma mark Init

- (id)init {
	if (self = [super init]) {
		service = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"Cloud"] retain];
		serviceLabel = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CloudLabel"] retain];
		serviceRootURLString = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CloudURL"] retain];
		activeClients = [[NSMutableArray alloc] init];
		queuedClients = [[NSMutableArray alloc] init];
		conflicts = [[NSMutableString alloc] init];
	}
	return self;
}

- (void)dealloc {
	//[self stopDocumentSharing];
	[service release];
	[serviceLabel release];
	[serviceRootURLString release];
	[servicePassword release];
	[activeClients release];
	[queuedClients release];
	[conflicts release];
	[documentDatabaseDirectory release];
    [managedObjectContext release];
    [managedObjectModel release];
    [persistentStoreCoordinator release];
	[super dealloc];
}

@synthesize service;
@synthesize serviceLabel;
@synthesize serviceRootURLString;

- (NSString *)serviceUsername {
	return [[NSUserDefaults standardUserDefaults] stringForKey:@"CloudServiceUsername"];
}

- (void)setServiceUsername:(NSString *)aUsername {
	if (aUsername) {
		[[NSUserDefaults standardUserDefaults] setObject:aUsername forKey:@"CloudServiceUsername"];
	} else {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CloudServiceUsername"];
	}
}

@synthesize servicePassword;
@synthesize documentDatabaseDirectory;

- (NSString *)documentDatabaseDirectory {
	if (!documentDatabaseDirectory) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
		documentDatabaseDirectory = [basePath retain];
	}
	return documentDatabaseDirectory;
}

- (NSManagedObjectContext *) managedObjectContext {
	if (managedObjectContext != nil) return managedObjectContext;
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        managedObjectContext = [[NSManagedObjectContext alloc] init];
        [managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return managedObjectContext;
}

- (NSManagedObjectModel *)managedObjectModel {
    if (managedObjectModel != nil) return managedObjectModel;
    managedObjectModel = [[NSManagedObjectModel mergedModelFromBundles:[NSArray arrayWithObject:[NSBundle bundleForClass:[self class]]]] retain];    
    return managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (persistentStoreCoordinator != nil) return persistentStoreCoordinator;
	NSError *error;
    NSURL *storeUrl = [NSURL fileURLWithPath:[[self documentDatabaseDirectory] stringByAppendingPathComponent:@"SyncedDocuments.coredata"]];
	
	[[NSFileManager defaultManager] removeItemAtPath:[storeUrl path] error:nil];
	
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:nil error:&error]) {
        return nil;
    }    
    return persistentStoreCoordinator;
}

@synthesize syncDelegate;

#pragma mark Actions

- (NSArray *)documents:(NSError **)error {
	NSFetchRequest *fetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entity = [NSEntityDescription entityForName:@"SyncedDocument" inManagedObjectContext:self.managedObjectContext];
	[fetchRequest setEntity:entity];
	return [self.managedObjectContext executeFetchRequest:fetchRequest error:error];
}

- (SyncedDocument *)newDocumentWithValues:(NSDictionary *)values error:(NSError **)error {
	SyncedDocument *newDocument = [NSEntityDescription insertNewObjectForEntityForName:@"SyncedDocument" inManagedObjectContext:self.managedObjectContext];

	for (NSString *eachKey in [values keyEnumerator]) {
		[newDocument setValue:[values objectForKey:eachKey] forKey:eachKey];
	}
	
	if ([self save:error]) {
		return newDocument;
	} else {
		return nil;
	}
}

- (BOOL)userDeleteDocument:(SyncedDocument *)document error:(NSError **)error {
	if (document.shadowID) {
		document.userDeleted = [NSNumber numberWithBool:YES];
	} else {
		[self.managedObjectContext deleteObject:document];	
	}
	return [self save:error];
}

- (BOOL)deleteDocument:(SyncedDocument *)document error:(NSError **)error {
	[self.managedObjectContext deleteObject:document];	
	return [self save:error];
}

- (BOOL)save:(NSError **)error {
	if ([[self managedObjectContext] hasChanges]) {
		if (![[self managedObjectContext] save:error]) {
			return NO;
		}
	}
	return YES;
}

- (IBAction)beginSync:(id)sender {
	totalQueuedClients = 0;
	[activeClients removeAllObjects];
	[queuedClients removeAllObjects];
	[conflicts replaceCharactersInRange:NSMakeRange(0, [conflicts length]) withString:@""];
	[self queueClient:[self GETServerDocuments]];
}

- (BOOL)isSyncing {
	return [activeClients count] > 0 || [queuedClients count] > 0;
}

- (IBAction)cancelSync:(id)sender {
	[queuedClients removeAllObjects];
	for (HTTPClient *eachClient in [[activeClients copy] autorelease]) {
		[self endActiveClient:eachClient];
	}
}

- (IBAction)toggleAuthentication:(id)sender {
	NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	NSArray *cookies = [cookieStorage cookiesForURL:[NSURL URLWithString:serviceRootURLString]];
	if ([cookies count] > 0) {
		[self signOut];
	} else {
		[self beginSync:sender];
	}
}

- (void)signOut {
	NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
	for (NSHTTPCookie *each in [cookieStorage cookiesForURL:[NSURL URLWithString:serviceRootURLString]]) {
		[cookieStorage deleteCookie:each];
	}
	self.serviceUsername = nil;
}

#pragma mark Client Requests

- (void)queueClient:(HTTPClient *)aClient {
	totalQueuedClients++;
	if ([activeClients count] == 0) {
		[self beginActiveClient:aClient];
	} else {
		[queuedClients insertObject:aClient atIndex:0];
	}
}

- (void)beginActiveClient:(HTTPClient *)aClient {
	if (!self.isSyncing) {
		[self.syncDelegate documentsControllerWillBeginSync:self];
		[self.syncDelegate documentsController:self syncProgress:0.5];
	}
	[activeClients addObject:aClient];
	[aClient beginFetchWithDelegate:self];
}

- (void)endActiveClient:(HTTPClient *)aClient {
	[aClient stopFetching];
	[activeClients removeObject:aClient];
	
	if (!self.isSyncing) {
		[self.syncDelegate documentsController:self syncProgress:1.0];
		[self.syncDelegate documentsControllerDidCompleteSync:self conflicts:[[conflicts copy] autorelease]];
		[conflicts replaceCharactersInRange:NSMakeRange(0, [conflicts length]) withString:@""];
	} else {
		[self.syncDelegate documentsController:self syncProgress:0.5 + ((1.0 - ((float)[queuedClients count] / (float)totalQueuedClients)) / 2.0)];
		if ([activeClients count] == 0 && [queuedClients count] > 0) {
			[self beginActiveClient:[queuedClients lastObject]];
			[queuedClients removeLastObject];
		}
	}
}

- (HTTPClient *)GETServerDocuments {
	NSMutableURLRequest *getDocumentsRequest = [[[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
	HTTPClient *getDocumentsClient = [HTTPClient clientWithRequest:getDocumentsRequest];
	[getDocumentsClient setUserData:self];
	return getDocumentsClient;
}

#pragma mark Client Requests Delegates

- (void)clientLogin:(HTTPClient *)aClient {
	if (self.serviceUsername != nil && self.servicePassword != nil) {
		NSURL *url = [NSURL URLWithString:@"https://www.google.com/accounts/ClientLogin"];
		NSMutableURLRequest *authTokenRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		aClient.request = authTokenRequest;
		HTTPClient *authTokenClient = [HTTPClient clientWithRequest:authTokenRequest];
		NSString *postString = [NSString stringWithFormat:@"Email=%@&Passwd=%@&source=%@&service=%@&accountType=%@", [self.serviceUsername stringByURLEncodingStringParameter], [self.servicePassword stringByURLEncodingStringParameter], [self.service stringByURLEncodingStringParameter], @"ah", @"GOOGLE"];
		[authTokenClient setPostData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
		authTokenClient.initialRequest = aClient.initialRequest;
		authTokenClient.userData = aClient.userData;
		[self queueClient:authTokenClient];
		[self endActiveClient:aClient];
	} else {
		[[self syncDelegate] documentsControllerSyncNewCredentials:self];
		[self cancelSync:nil];
	}
}

- (void)client:(HTTPClient *)aClient networkFailed:(NSError *)error {
	[self cancelSync:nil];
	[[self syncDelegate] documentsController:self syncClient:aClient networkFailed:error];
}

- (void)client:(HTTPClient *)aClient failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	if (statusCode == 401 || statusCode == 403) {
		if ([[[[aClient request] URL] absoluteString] rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
			[self cancelSync:nil];
			[[self syncDelegate] documentsControllerSyncNewCredentials:self];
		} else {
			[self clientLogin:aClient];
		}
	} else {
		[self cancelSync:nil];
		[[self syncDelegate] documentsController:self syncClient:aClient failedWithStatusCode:statusCode data:data];
	}
}

- (void)client:(HTTPClient *)aClient finishedWithData:(NSData *)data {
	NSString *absoluteString = [[[aClient request] URL] absoluteString];
	
	if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ServiceLogin"].location == 0) {
		[self clientLogin:aClient];
	} else if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
		NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary *responseDict = [HTTPClient dictionaryWithResponseString:responseString];
		NSString *authToken = [[responseDict objectForKey:@"Auth"] retain];
		BOOL isInitialRequestAGET = [[aClient.initialRequest HTTPMethod] caseInsensitiveCompare:@"GET"] == NSOrderedSame;
		NSString *requestString = nil;
		
		if (isInitialRequestAGET) {
			requestString = [NSString stringWithFormat:@"%@/_ah/login?continue=%@&auth=%@", self.serviceRootURLString, [[[aClient.initialRequest URL] absoluteString] stringByURLEncodingStringParameter], authToken];
		} else {
			requestString = [NSString stringWithFormat:@"%@/_ah/login?auth=%@", self.serviceRootURLString, authToken];
		}
		
		NSURL *url = [NSURL URLWithString:requestString];
		NSMutableURLRequest *authenticationCookieRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		HTTPClient *authenticationCookieClient = [HTTPClient clientWithRequest:authenticationCookieRequest];
		authenticationCookieClient.initialRequest = aClient.initialRequest;
		authenticationCookieClient.userData = aClient.userData;
		[self queueClient:authenticationCookieClient];
	} else if ([absoluteString rangeOfString:@"/_ah/login?"].location != NSNotFound) {
		// XXX perform initial request... bit ungly to handle the case where authentication fails when making a PUT, POST, or DELETE request. In that case teh continue paramater of the cookie client will not work.
	} else if ([[aClient userData] respondsToSelector:@selector(processSyncResponse:)]) {
		[[aClient userData] processSyncResponse:data];
	}
	
	[self endActiveClient:aClient];
}

#pragma mark Process initial GETDocuments response

- (void)processSyncResponse:(NSData *)data {
	NSArray *serverDocuments = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSMutableDictionary *serverDocumentsByID = [NSMutableDictionary dictionary];
	NSEntityDescription *documentEntity = [NSEntityDescription entityForName:@"SyncedDocument" inManagedObjectContext:self.managedObjectContext];
	NSError *error = nil;
	
	// 1. Map server documents to ID's
	for (NSDictionary *each in serverDocuments) {
		[serverDocumentsByID setObject:each forKey:[each objectForKey:@"id"]];
	}
	
	// 2. Map local documents to server documents.
	NSMutableArray *syncingDocuments = [NSMutableArray array];
	NSArray *localDocuments = [self documents:&error];
	
	if (localDocuments) {
		for (SyncedDocument *eachDocument in localDocuments) {
			if (eachDocument.isServerDocument) {
				NSDictionary *eachServerState = [serverDocumentsByID objectForKey:eachDocument.shadowID];
				if (eachServerState) {
					eachDocument.serverVersion = [[eachServerState objectForKey:@"version"] integerValue];
					[serverDocumentsByID removeObjectForKey:eachDocument.shadowID];
					eachDocument.isDeletedFromServer = NO;
				} else {
					eachDocument.isDeletedFromServer = YES;
				}
			}
			[syncingDocuments addObject:eachDocument];
		}
	} else {
		NSLog([error description]);
	}
		
	// 3. Create new local documents for new server documents.
	for (NSString *eachServerID in [serverDocumentsByID allKeys]) {
		NSDictionary *eachServerState = [serverDocumentsByID objectForKey:eachServerID];		
		SyncedDocument *eachDocument = [[[SyncedDocument alloc] initWithEntity:documentEntity insertIntoManagedObjectContext:nil] autorelease];
		eachDocument.serverVersion = [[eachServerState objectForKey:@"version"] integerValue];
		eachDocument.shadowID = [eachServerState objectForKey:@"id"];
		[syncingDocuments addObject:eachDocument];
	}
	
	// 4. Beging processing requests.
	for (SyncedDocument *each in syncingDocuments) {
		HTTPClient *requestClient = [each buildSyncRequest];
		if (requestClient) {
			[self queueClient:requestClient];
		}
	}
}

@end

NSString *DocumentSharingPort = @"DocumentSharingPort";
NSString *DocumentSharingServiceName = @"DocumentSharingServiceName";
NSString *DisableAutoLockWhenSharingDocuments = @"DisableAutoLockWhenSharingDocuments";
NSString *DocumentsDefaultEmail = @"DocumentsDefaultEmail";

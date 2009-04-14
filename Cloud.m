//
//  Cloud.m
//  WriteRoom
//
//  Created by Jesse Grosjean on 3/8/09.
//  Copyright 2009 Hog Bay Software. All rights reserved.
//

#import "Cloud.h"
#import "CloudDocument.h"
#import "NSString+SBJSON.h"
#import "HTTPFetcher.h"
#import "Keychain.h"


@interface Cloud (DocumentsPrivate)

- (void)queueFetcher:(HTTPFetcher *)aFetcher;
- (void)beginActiveFetcher:(HTTPFetcher *)aFetcher;
- (void)endActiveFetcher:(HTTPFetcher *)aFetcher;
- (HTTPFetcher *)GETServerDocuments;

@end

@implementation Cloud

+ (id)sharedInstance {
    static id sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

/*
#define ReachableViaWiFiNetwork 2
#define ReachableDirectWWAN (1 << 18)
// fast wi-fi connection
+ (BOOL)hasActiveWiFiConnection {
	SCNetworkReachabilityFlags flags;
	SCNetworkReachabilityRef reachabilityRef = SCNetworkReachabilityCreateWithName(CFAllocatorGetDefault(),[@"www.apple.com" UTF8String]);
	BOOL gotFlags = SCNetworkReachabilityGetFlags(reachabilityRef, &flags);
	CFRelease(reachabilityRef);
    
	if (!gotFlags) return NO;
	if (flags & ReachableDirectWWAN) return NO;
	if (flags & ReachableViaWiFiNetwork) return YES;
    
	return NO;
}

// any type of internet connection (edge, 3g, wi-fi)
+ (BOOL)hasNetworkConnection {
    SCNetworkReachabilityFlags flags;
    SCNetworkReachabilityRef reachabilityRef = SCNetworkReachabilityCreateWithName(CFAllocatorGetDefault(), [@"www.apple.com" UTF8String]);
    BOOL gotFlags = SCNetworkReachabilityGetFlags(reachabilityRef, &flags);
    CFRelease(reachabilityRef);
	
    if (!gotFlags || (flags == 0)) return NO;
	
    return YES;
}
*/

- (id)init {
	if (self = [super init]) {
		service = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"Cloud"] retain];
		serviceLabel = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CloudLabel"] retain];
		serviceRootURLString = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CloudURL"] retain];
		activeFetchers = [[NSMutableArray alloc] init];
		queuedFetchers = [[NSMutableArray alloc] init];
		conflicts = [[NSMutableString alloc] init];
	}
	return self;
}

- (void)dealloc {
	[service release];
	[serviceLabel release];
	[serviceRootURLString release];
	[servicePassword release];
	[activeFetchers release];
	[queuedFetchers release];
	[conflicts release];
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

- (NSString *)servicePassword {
	return [[Keychain sharedInstance] objectForKey:@"CloudServicePassword"];
}

- (void)setServicePassword:(NSString *)password {
	[[Keychain sharedInstance] setObject:password forKey:@"CloudServicePassword"];
}

@synthesize delegate;

- (IBAction)beginSync:(id)sender {
	totalQueuedFetchers = 0;
	[activeFetchers removeAllObjects];
	[queuedFetchers removeAllObjects];
	[conflicts replaceCharactersInRange:NSMakeRange(0, [conflicts length]) withString:@""];
	[self queueFetcher:[self GETServerDocuments]];
}

- (BOOL)isSyncing {
	return [activeFetchers count] > 0 || [queuedFetchers count] > 0;
}

- (IBAction)cancelSync:(id)sender {
	[queuedFetchers removeAllObjects];
	for (HTTPFetcher *eachFetcher in [[activeFetchers copy] autorelease]) {
		[self endActiveFetcher:eachFetcher];
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

#pragma mark Server Requests

- (void)queueFetcher:(HTTPFetcher *)aFetcher {
	totalQueuedFetchers++;
	if ([activeFetchers count] == 0) {
		[self beginActiveFetcher:aFetcher];
	} else {
		[queuedFetchers insertObject:aFetcher atIndex:0];
	}
}

- (void)beginActiveFetcher:(HTTPFetcher *)aFetcher {
	if (!self.isSyncing) {
		[self.delegate cloudWillBeginSync:self];
		[self.delegate cloudSyncProgress:0.5 cloud:self];
	}
	[activeFetchers addObject:aFetcher];
	[aFetcher beginFetchWithDelegate:self];
}
	
- (void)endActiveFetcher:(HTTPFetcher *)aFetcher {
	[aFetcher stopFetching];
	[activeFetchers removeObject:aFetcher];

	if (!self.isSyncing) {
		[self.delegate cloudSyncProgress:1.0 cloud:self];
		[self.delegate cloudDidCompleteSync:self conflicts:[[conflicts copy] autorelease]];
		[conflicts replaceCharactersInRange:NSMakeRange(0, [conflicts length]) withString:@""];
	} else {
		[self.delegate cloudSyncProgress:0.5 + ((1.0 - ((float)[queuedFetchers count] / (float)totalQueuedFetchers)) / 2.0) cloud:self];
		if ([activeFetchers count] == 0 && [queuedFetchers count] > 0) {
			[self beginActiveFetcher:[queuedFetchers lastObject]];
			[queuedFetchers removeLastObject];
		}
	}
}

- (HTTPFetcher *)GETServerDocuments {
	NSMutableURLRequest *getDocumentsRequest = [[[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/documents", self.serviceRootURLString]] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
	HTTPFetcher *getDocumentsFetcher = [HTTPFetcher fetcherWithRequest:getDocumentsRequest];
	[getDocumentsFetcher setUserData:self];
	return getDocumentsFetcher;
}

#pragma mark Server Requests Delegates

- (void)clientLogin:(HTTPFetcher *)aFetcher {
	if (self.serviceUsername != nil && self.servicePassword != nil) {
		NSURL *url = [NSURL URLWithString:@"https://www.google.com/accounts/ClientLogin"];
		NSMutableURLRequest *authTokenRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		aFetcher.request = authTokenRequest;
		HTTPFetcher *authTokenFetcher = [HTTPFetcher fetcherWithRequest:authTokenRequest];
		NSString *postString = [NSString stringWithFormat:@"Email=%@&Passwd=%@&source=%@&service=%@&accountType=%@", [self.serviceUsername stringByURLEncodingStringParameter], [self.servicePassword stringByURLEncodingStringParameter], [self.service stringByURLEncodingStringParameter], @"ah", @"GOOGLE"];
		[authTokenFetcher setPostData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
		authTokenFetcher.initialRequest = aFetcher.initialRequest;
		authTokenFetcher.userData = aFetcher.userData;
		[self queueFetcher:authTokenFetcher];
		[self endActiveFetcher:aFetcher];
	} else {
		[[self delegate] cloudSyncNewCredentials:self];
		[self cancelSync:nil];
	}
}

- (void)fetcher:(HTTPFetcher *)aFetcher networkFailed:(NSError *)error {
	[self cancelSync:nil];
	[[self delegate] cloudSyncFetcher:aFetcher networkFailed:error];
}

- (void)fetcher:(HTTPFetcher *)aFetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data {
	if (statusCode == 401 || statusCode == 403) {
		if ([[[[aFetcher request] URL] absoluteString] rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
			[self cancelSync:nil];
			[[self delegate] cloudSyncNewCredentials:self];
		} else {
			[self clientLogin:aFetcher];
		}
	} else {
		[self cancelSync:nil];
		[[self delegate] cloudSyncFetcher:aFetcher failedWithStatusCode:statusCode data:data];
	}
}

- (void)fetcher:(HTTPFetcher *)aFetcher finishedWithData:(NSData *)data {
	NSString *absoluteString = [[[aFetcher request] URL] absoluteString];
	
	if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ServiceLogin"].location == 0) {
		[self clientLogin:aFetcher];
	} else if ([absoluteString rangeOfString:@"https://www.google.com/accounts/ClientLogin"].location == 0) {
		NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSDictionary *responseDict = [HTTPFetcher dictionaryWithResponseString:responseString];
		NSString *authToken = [[responseDict objectForKey:@"Auth"] retain];
		BOOL isInitialRequestAGET = [[aFetcher.initialRequest HTTPMethod] caseInsensitiveCompare:@"GET"] == NSOrderedSame;
		NSString *requestString = nil;
		
		if (isInitialRequestAGET) {
			requestString = [NSString stringWithFormat:@"%@/_ah/login?continue=%@&auth=%@", self.serviceRootURLString, [[[aFetcher.initialRequest URL] absoluteString] stringByURLEncodingStringParameter], authToken];
		} else {
			requestString = [NSString stringWithFormat:@"%@/_ah/login?auth=%@", self.serviceRootURLString, authToken];
		}
		
		NSURL *url = [NSURL URLWithString:requestString];
		NSMutableURLRequest *authenticationCookieRequest = [[[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60] autorelease];
		HTTPFetcher *authenticationCookieFetcher = [HTTPFetcher fetcherWithRequest:authenticationCookieRequest];
		authenticationCookieFetcher.initialRequest = aFetcher.initialRequest;
		authenticationCookieFetcher.userData = aFetcher.userData;
		[self queueFetcher:authenticationCookieFetcher];
	} else if ([absoluteString rangeOfString:@"/_ah/login?"].location != NSNotFound) {
		// XXX perform initial request... bit ungly to handle the case where authentication fails when making a PUT, POST, or DELETE request. In that case teh continue paramater of the cookie fetcher will not work.
	} else if ([[aFetcher userData] respondsToSelector:@selector(processSyncResponse:)]) {
		[[aFetcher userData] processSyncResponse:data];
	}
	
	[self endActiveFetcher:aFetcher];
}

#pragma mark Process initial GETDocuments response

- (void)processSyncResponse:(NSData *)data {
	NSArray *serverDocuments = [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] JSONValue];
	NSMutableDictionary *serverDocumentsByID = [NSMutableDictionary dictionary];

	for (NSDictionary *each in serverDocuments) {
		[serverDocumentsByID setObject:each forKey:[each objectForKey:@"id"]];
	}
	
	NSMutableArray *cloudDocuments = [NSMutableArray array];
	
	for (CloudDocument *eachCloudDocument in [self.delegate cloudSyncLocalDocuments]) {
		NSDictionary *eachServerState = [serverDocumentsByID objectForKey:eachCloudDocument.documentID];
		if (eachServerState) {
			eachCloudDocument.serverVersion = [[eachServerState objectForKey:@"version"] description];
			eachCloudDocument.documentID = [eachServerState objectForKey:@"id"];
		} else if (!eachCloudDocument.isScheduledForInsertOnClient) {
			eachCloudDocument.isDeletedFromServer = YES;
		}
		
		[cloudDocuments addObject:eachCloudDocument];
		[serverDocumentsByID removeObjectForKey:eachCloudDocument.documentID];
	}
	
	for (NSString *eachServerID in [serverDocumentsByID allKeys]) {
		NSDictionary *eachServerState = [serverDocumentsByID objectForKey:eachServerID];
		CloudDocument *eachCloudDocument = [[[CloudDocument alloc] init] autorelease];
		eachCloudDocument.serverVersion = [[eachServerState objectForKey:@"version"] description];
		eachCloudDocument.documentID = [eachServerState objectForKey:@"id"];
		[cloudDocuments addObject:eachCloudDocument];
	}
	
	for (CloudDocument *each in cloudDocuments) {
		HTTPFetcher *requestFetcher = [each buildSyncRequest];
		if (requestFetcher) {
			[self queueFetcher:requestFetcher];
		}
	}
}

@end
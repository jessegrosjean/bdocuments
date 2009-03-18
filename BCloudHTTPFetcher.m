//
//  BCloudHTTPFetcher.m
//

#import "BCloudHTTPFetcher.h"
#import "BDocuments.h"


@interface BCloudHTTPFetcher (BCloudHTTPFetcherPrivate)
- (void)setResponse:(NSURLResponse *)response;
- (void)setDelegate:(id)theDelegate; 
@end

@implementation BCloudHTTPFetcher

+ (BCloudHTTPFetcher *)fetcherWithRequest:(NSURLRequest *)request {
	return [[[BCloudHTTPFetcher alloc] initWithRequest:request] autorelease];
}

+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseString {	
	NSArray *allLines = [responseString componentsSeparatedByString:@"\n"];
	NSMutableDictionary *responseDict = [NSMutableDictionary dictionary];
	
	for (NSString *line in allLines) {
		NSScanner *scanner = [NSScanner scannerWithString:line];
		NSString *key;
		NSString *value;
		
		if ([scanner scanUpToString:@"=" intoString:&key]
			&& [scanner scanString:@"=" intoString:nil]
			&& [scanner scanUpToString:@"\n" intoString:&value]) {
			
			[responseDict setObject:value forKey:key];
		}
	}
	return responseDict;
}

#pragma mark Init

- (id)init {
	return [self initWithRequest:nil];
}

- (id)initWithRequest:(NSURLRequest *)aRequest {
	if ((self = [super init]) != nil) {
		initialRequest = [aRequest copy];
		request = [aRequest mutableCopy];
	}
	return self;
}

#pragma mark Dealloc

- (void)dealloc {
	[self stopFetching];
	[initialRequest release];
	[request release];
	[downloadedData release];
	[postData release];
	[response release];
	[userData release];
	[runLoopModes release];	
	[super dealloc];
}

#pragma mark Attributes

- (NSURLRequest *)initialRequest {
	return initialRequest;  
}

- (NSMutableURLRequest *)request {
	return request;  
}

- (void)setRequest:(NSURLRequest *)theRequest {
	[request autorelease];
	request = [theRequest mutableCopy];
}

- (NSData *)postData {
	return postData; 
}

- (void)setPostData:(NSData *)theData {
	[postData autorelease]; 
	postData = [theData retain];
}

- (void)setFormURLEncodedPostDictionary:(NSDictionary *)theDictionary {
	NSMutableString *postString = [NSMutableString string];
	for (NSString *key in [theDictionary keyEnumerator]) {
		[postString appendFormat:@"%@=%@&", [key stringByURLEncodingStringParameter], [[theDictionary objectForKey:key] stringByURLEncodingStringParameter]];
	}
	[postString replaceCharactersInRange:NSMakeRange([postString length] - 1, 1) withString:@""];
	[self setPostData:[postString dataUsingEncoding:NSUTF8StringEncoding]];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

}

- (id)delegate {
	return delegate; 
}

- (void)setDelegate:(id)theDelegate {
	if (connection) {
		[delegate autorelease];
		delegate = [theDelegate retain];
	} else {
		delegate = theDelegate; 
	}
}

- (NSURLResponse *)response {
	return response;
}

- (void)setResponse:(NSURLResponse *)theResponse {
	[response autorelease];
	response = [theResponse retain];
}

- (NSInteger)statusCode {
	NSInteger statusCode;
	if (response != nil && [response respondsToSelector:@selector(statusCode)]) {
		statusCode = [(NSHTTPURLResponse *)response statusCode];
	} else {
		statusCode = 0;
	}
	return statusCode;
}

- (NSDictionary *)responseHeaders {
	if (response != nil && [response respondsToSelector:@selector(allHeaderFields)]) {
		return [(NSHTTPURLResponse *)response allHeaderFields];
	}
	return nil;
}

- (NSData *)downloadedData {
	return downloadedData;
}

- (id)userData {
	return userData;
}

- (void)setUserData:(id)theObj {
	[userData autorelease]; 
	userData = [theObj retain];
}

- (NSArray *)runLoopModes {
	return runLoopModes;
}

- (void)setRunLoopModes:(NSArray *)modes {
	[runLoopModes autorelease]; 
	runLoopModes = [modes retain];
}

#pragma mark Fetching

- (BOOL)beginFetchWithDelegate:(id)aDelegate {
	NSAssert1(connection == nil, @"fetch object %@ being reused; this should never happen", self);
	NSAssert(request != nil, @"beginFetchWithDelegate requires a request");
	
	[downloadedData release];
	downloadedData = nil;
	
	[self setDelegate:aDelegate];
	
	if (postData) {
		if ([request HTTPMethod] == nil || [[request HTTPMethod] isEqual:@"GET"]) {
			[request setHTTPMethod:@"POST"];
		}		
		if (postData) {
			[request setHTTPBody:postData];
		}
	}
		
	if ([runLoopModes count] == 0) {
		connection = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
	} else {
		connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
		NSEnumerator *modeEnumerator = [runLoopModes objectEnumerator];
		NSString *mode;
		while ((mode = [modeEnumerator nextObject]) != nil) {
			[connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
		}
		[connection start];
	}
	
	if (!connection) {
		NSAssert(connection != nil, @"beginFetchWithDelegate could not create a connection");
		if ([delegate respondsToSelector:@selector(fetcher:networkFailed:)]) {
			NSError *error = [NSError errorWithDomain:@"com.bdocuments.BCloudHTTPFetcher" code:kBCloudHTTPFetcherErrorDownloadFailed userInfo:nil];
			[[self retain] autorelease]; // in case the callback releases us
			[delegate performSelector:@selector(fetcher:networkFailed:) withObject:self withObject:error];
		}
		return NO;
	}
	
	[delegate retain];
	downloadedData = [[NSMutableData alloc] init];
	return YES;
}

- (BOOL)isFetching {
	return connection != nil; 
}

- (void)stopFetching {	
	if (connection) {
		NSURLConnection* oldConnection = connection;
		connection = nil;
		[oldConnection cancel];
		[oldConnection autorelease]; 
		[delegate release];
	}
}

#pragma mark NSURLConnection Delegate Methods

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)redirectRequest redirectResponse:(NSURLResponse *)redirectResponse {
	if (redirectRequest && redirectResponse) {
		NSMutableURLRequest *newRequest = [[request mutableCopy] autorelease];
		NSURL *redirectURL = [redirectRequest URL];
		NSURL *url = [newRequest URL];
		NSString *redirectScheme = [url scheme];
		NSString *newScheme = [redirectURL scheme];
		NSString *newResourceSpecifier = [redirectURL resourceSpecifier];
		
		if ([redirectScheme caseInsensitiveCompare:@"http"] == NSOrderedSame && newScheme != nil && [newScheme caseInsensitiveCompare:@"https"] == NSOrderedSame) {
			redirectScheme = newScheme; 
		}
		
		NSString *newUrlString = [NSString stringWithFormat:@"%@:%@", redirectScheme, newResourceSpecifier];
		NSURL *newURL = [NSURL URLWithString:newUrlString];
		[newRequest setURL:newURL];
		
		NSDictionary *redirectHeaders = [redirectRequest allHTTPHeaderFields];
		if (redirectHeaders) {
			NSEnumerator *enumerator = [redirectHeaders keyEnumerator];
			NSString *key;
			while (nil != (key = [enumerator nextObject])) {
				NSString *value = [redirectHeaders objectForKey:key];
				[newRequest setValue:value forHTTPHeaderField:key];
			}
		}
		redirectRequest = newRequest;
		
		[self setResponse:redirectResponse];
		[self setRequest:redirectRequest];
	}
	return redirectRequest;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)aResponse {
	[downloadedData setLength:0];
	[self setResponse:aResponse];
}

-(void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
	NSLog(@"connection:didReceiveAuthenticationChallenge:");
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[downloadedData appendData:data];
	
	if ([delegate respondsToSelector:@selector(fetcher:receivedData:)]) {
		[delegate performSelector:@selector(fetcher:receivedData:) withObject:self withObject:downloadedData];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {	
	[[self retain] autorelease];
    
	NSInteger status = [self statusCode];

	if (status >= 300 && [delegate respondsToSelector:@selector(fetcher:failedWithStatusCode:data:)]) {
		NSMethodSignature *signature = [delegate methodSignatureForSelector:@selector(fetcher:failedWithStatusCode:data:)];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
		[invocation setSelector:@selector(fetcher:failedWithStatusCode:data:)];
		[invocation setTarget:delegate];
		[invocation setArgument:&self atIndex:2];
		[invocation setArgument:&status atIndex:3];
		[invocation setArgument:&downloadedData atIndex:4];
		[invocation invoke];
		[self stopFetching];
	} else if ([delegate respondsToSelector:@selector(fetcher:finishedWithData:)]) {
		[delegate performSelector:@selector(fetcher:finishedWithData:) withObject:self withObject:downloadedData];
		[self stopFetching];
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	if ([delegate respondsToSelector:@selector(fetcher:networkFailed:)]) {
		[[self retain] autorelease]; // in case the callback releases us
		[delegate performSelector:@selector(fetcher:networkFailed:) withObject:self withObject:error];
	}
	[self stopFetching];
}

@end
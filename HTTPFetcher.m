//
//  HTTPFetcher.m
//

#import "HTTPFetcher.h"
#import "NSObject+SBJSON.h"


@interface HTTPFetcher (HTTPFetcherPrivate)
- (void)setResponse:(NSURLResponse *)response;
- (void)setDelegate:(id)theDelegate; 
@end

@implementation HTTPFetcher

+ (HTTPFetcher *)fetcherWithRequest:(NSURLRequest *)request {
	return [[[HTTPFetcher alloc] initWithRequest:request] autorelease];
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
		initialRequest = [aRequest retain];
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

@synthesize initialRequest;
@synthesize request;
@synthesize postData;

- (void)setPostDataJSON:(NSObject *)theJSON {
	[self setPostDataString:[theJSON JSONRepresentation]];
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
}

- (void)setPostDataString:(NSString *)postDataString {
	[self setPostData:[postDataString dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)setFormURLEncodedPostDictionary:(NSDictionary *)theDictionary {
	NSMutableString *postString = [NSMutableString string];
	for (NSString *key in [theDictionary keyEnumerator]) {
		[postString appendFormat:@"%@=%@&", [key stringByURLEncodingStringParameter], [[theDictionary objectForKey:key] stringByURLEncodingStringParameter]];
	}
	[postString replaceCharactersInRange:NSMakeRange([postString length] - 1, 1) withString:@""];
	[self setPostDataString:postString];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

}

@synthesize delegate;

- (void)setDelegate:(id)theDelegate {
	if (connection) {
		[delegate autorelease];
		delegate = [theDelegate retain];
	} else {
		delegate = theDelegate; 
	}
}

@synthesize response;

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

@synthesize downloadedData;
@synthesize userData;
@synthesize runLoopModes;

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
			NSError *error = [NSError errorWithDomain:@"com.blocks.cloud.HTTPFetcher" code:kHTTPFetcherErrorDownloadFailed userInfo:[NSDictionary dictionaryWithObject:NSLocalizedString(@"could not create connection", nil) forKey:NSLocalizedDescriptionKey]];
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
		delegate = nil;
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
		[self setRequest:[[redirectRequest mutableCopy] autorelease]];
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

@implementation NSString (HTTPFetcherAdditions)

- (NSString *)stringByURLEncodingStringParameter {
	// From Google Data Objective-C client 
	// NSURL's stringByAddingPercentEscapesUsingEncoding: does not escape
	// some characters that should be escaped in URL parameters, like / and ?; 
	// we'll use CFURL to force the encoding of those
	//
	// We'll explicitly leave spaces unescaped now, and replace them with +'s
	//
	// Reference: http://www.ietf.org/rfc/rfc3986.txt
	
	NSString *resultStr = self;
	CFStringRef originalString = (CFStringRef) self;
	CFStringRef leaveUnescaped = CFSTR(" ");
	CFStringRef forceEscaped = CFSTR("!*'();:@&=+$,/?%#[]");
	CFStringRef escapedStr = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, originalString, leaveUnescaped, forceEscaped, kCFStringEncodingUTF8);
	
	if (escapedStr) {
		NSMutableString *mutableStr = [NSMutableString stringWithString:(NSString *)escapedStr];
		CFRelease(escapedStr);
		[mutableStr replaceOccurrencesOfString:@" " withString:@"+" options:0 range:NSMakeRange(0, [mutableStr length])];
		resultStr = mutableStr;
	}
	
	return resultStr;
}

@end

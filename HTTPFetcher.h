enum {
	kHTTPFetcherErrorDownloadFailed = -1,
};

@interface HTTPFetcher : NSObject {
	NSURLRequest *initialRequest;
	NSMutableURLRequest *request;
	NSURLConnection *connection;
	NSMutableData *downloadedData;
	NSData *postData;
	NSURLResponse *response;
	id delegate;
	id userData;
	NSArray *runLoopModes;
}

+ (HTTPFetcher *)fetcherWithRequest:(NSURLRequest *)request;
+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseString;

#pragma mark Init

- (id)initWithRequest:(NSURLRequest *)request;

#pragma mark Attributes

@property(retain) NSURLRequest *initialRequest;
@property(retain) NSMutableURLRequest *request;
@property(retain) NSData *postData;
- (void)setPostDataJSON:(NSObject *)theJSON;
- (void)setPostDataString:(NSString *)postDataString;
- (void)setFormURLEncodedPostDictionary:(NSDictionary *)theDictionary;
@property(retain) id delegate;
@property(retain) NSURLResponse *response;
@property(readonly) NSInteger statusCode;
@property(readonly) NSDictionary *responseHeaders;
@property(readonly) NSData *downloadedData;
@property(retain) id userData;
@property(retain) NSArray *runLoopModes;

#pragma mark Fetching

- (BOOL)beginFetchWithDelegate:(id)delegate;
- (BOOL)isFetching;
- (void)stopFetching;

@end

@interface NSObject (HTTPFetcherDelegate)
- (void)fetcher:(HTTPFetcher *)fetcher receivedData:(NSData *)dataReceivedSoFar;
- (void)fetcher:(HTTPFetcher *)fetcher finishedWithData:(NSData *)data;
- (void)fetcher:(HTTPFetcher *)fetcher networkFailed:(NSError *)error;
- (void)fetcher:(HTTPFetcher *)fetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data;
@end

@interface NSString (HTTPFetcherAdditions)
- (NSString *)stringByURLEncodingStringParameter;
@end

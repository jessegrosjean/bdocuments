#import <Foundation/Foundation.h>


enum {
	kBCloudHTTPFetcherErrorDownloadFailed = -1,
};

@interface BCloudHTTPFetcher : NSObject {
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

+ (BCloudHTTPFetcher *)fetcherWithRequest:(NSURLRequest *)request;
+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseString;

#pragma mark Init

- (id)initWithRequest:(NSURLRequest *)request;

#pragma mark Attributes

- (NSURLRequest *)initialRequest;
- (NSMutableURLRequest *)request;
- (void)setRequest:(NSURLRequest *)theRequest;
- (NSData *)postData;
- (void)setPostData:(NSData *)theData;
- (void)setFormURLEncodedPostDictionary:(NSDictionary *)theDictionary;
- (id)delegate;
- (NSURLResponse *)response;
- (NSInteger)statusCode;
- (NSDictionary *)responseHeaders;
- (NSData *)downloadedData;
- (id)userData;
- (void)setUserData:(id)theObj;
- (NSArray *)runLoopModes;
- (void)setRunLoopModes:(NSArray *)modes;

#pragma mark Fetching

- (BOOL)beginFetchWithDelegate:(id)delegate;
- (BOOL)isFetching;
- (void)stopFetching;

@end

@interface NSObject (BCloudHTTPFetcherDelegate)
- (void)fetcher:(BCloudHTTPFetcher *)fetcher receivedData:(NSData *)dataReceivedSoFar;
- (void)fetcher:(BCloudHTTPFetcher *)fetcher finishedWithData:(NSData *)data;
- (void)fetcher:(BCloudHTTPFetcher *)fetcher networkFailed:(NSError *)error;
- (void)fetcher:(BCloudHTTPFetcher *)fetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data;
@end

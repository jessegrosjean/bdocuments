#import <Foundation/Foundation.h>


enum {
	kBDocumentsHTTPFetcherErrorDownloadFailed = -1,
};

@interface BDocumentsHTTPFetcher : NSObject {
	NSMutableURLRequest *request;
	NSURLConnection *connection;
	NSMutableData *downloadedData;
	NSData *postData;
	NSURLResponse *response;
	id delegate;
	id userData;
	NSArray *runLoopModes;
}

+ (BDocumentsHTTPFetcher *)fetcherWithRequest:(NSURLRequest *)request;
+ (NSDictionary *)dictionaryWithResponseString:(NSString *)responseString;

#pragma mark Init

- (id)initWithRequest:(NSURLRequest *)request;

#pragma mark Attributes

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

@interface NSObject (BDocumentsHTTPFetcherDelegate)
- (void)fetcher:(BDocumentsHTTPFetcher *)fetcher receivedData:(NSData *)dataReceivedSoFar;
- (void)fetcher:(BDocumentsHTTPFetcher *)fetcher finishedWithData:(NSData *)data;
- (void)fetcher:(BDocumentsHTTPFetcher *)fetcher networkFailed:(NSError *)error;
- (void)fetcher:(BDocumentsHTTPFetcher *)fetcher failedWithStatusCode:(NSInteger)statusCode data:(NSData *)data;
@end

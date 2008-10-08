//
//  BDocumentCloud.m
//  BDocuments
//
//  Created by Jesse Grosjean on 9/29/08.
//  Copyright 2008 Hog Bay Software. All rights reserved.
//

#import "BDocumentCloud.h"
#import "SBJSON.h"


@implementation BDocumentCloud

+ (NSString *)stringByURLEncodingStringParameter:(NSString *)str {
	// From Google Data Objective-C client 
	// NSURL's stringByAddingPercentEscapesUsingEncoding: does not escape
	// some characters that should be escaped in URL parameters, like / and ?; 
	// we'll use CFURL to force the encoding of those
	//
	// We'll explicitly leave spaces unescaped now, and replace them with +'s
	//
	// Reference: http://www.ietf.org/rfc/rfc3986.txt
	
	NSString *resultStr = str;
	CFStringRef originalString = (CFStringRef) str;
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

+ (NSString *)URLencodedPOSTBody:(NSDictionary *)dictionary {
	NSMutableString *URLencodedPOSTBody = [NSMutableString string];
	BOOL started = NO;
	
	for (NSString *eachKey in [dictionary keyEnumerator]) {
		NSString *eachValue = [BDocumentCloud stringByURLEncodingStringParameter:[dictionary objectForKey:eachKey]];
		eachKey = [BDocumentCloud stringByURLEncodingStringParameter:eachKey];
		
		if (started) {
			[URLencodedPOSTBody appendString:@"&"];
		} else {
			started = YES;
		}
		
		[URLencodedPOSTBody appendFormat:@"%@=%@", eachKey, eachValue];
	}
	
	return URLencodedPOSTBody;
}

@synthesize serviceRootURLString;
@synthesize localRootURLString;

- (NSArray *)GETDocuments {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	NSError *error = nil;
	
	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error]) {
		NSString *responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
		NSArray *documents = [[[SBJSON alloc] init] objectWithString:responseBody error:&error];
		
		if (documents) {
			return documents;
		} else {
			if (error)
				BLogError([error description]);
			else
				BLogError([NSString stringWithFormat:@"failed with error code %i", [response statusCode]]);
		}
	} else {
		if (error)
			BLogError([error description]);
		else
			BLogError([NSString stringWithFormat:@"failed with error code %i", [response statusCode]]);
	}
	
	return nil;
}

- (NSString *)POSTDocument:(NSDictionary *)document {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serviceRootURLString]];	
	NSHTTPURLResponse *response;
	NSError *error = nil;

	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:document] dataUsingEncoding:NSUTF8StringEncoding]];

	[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

	if (!error && [response statusCode] == 201) { // created
		return [[[response allHeaderFields] objectForKey:@"Location"] lastPathComponent];
	} else {
		if (error)
			BLogError([error description]);
		else
			BLogError([NSString stringWithFormat:@"failed with error code %i", [response statusCode]]);
	}
	
	return nil;
}

- (NSArray *)PUTDocument:(NSDictionary *)document forKey:(NSString *)key {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	NSError *error = nil;
	
	[request setHTTPMethod:@"PUT"];
	[request setHTTPBody:[[BDocumentCloud URLencodedPOSTBody:document] dataUsingEncoding:NSUTF8StringEncoding]];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error]) {
		NSString *responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
		NSArray *patchesReport = [[[SBJSON alloc] init] objectWithString:responseBody error:&error];
		return patchesReport;
	} else {
		if (error)
			BLogError([error description]);
		else
			BLogError([NSString stringWithFormat:@"failed with error code %i", [response statusCode]]);
	}
	
	return nil;
}

- (NSDictionary *)GETDocumentForKey:(NSString *)key {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serviceRootURLString, key]]];
	NSHTTPURLResponse *response;
	NSData *responseData;
	NSError *error = nil;
	
	if (responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error]) {
		NSString *responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
		NSDictionary *document = [[[SBJSON alloc] init] objectWithString:responseBody error:&error];
		return document;
	} else {
		if (error)
			BLogError([error description]);
		else
			BLogError([NSString stringWithFormat:@"failed with error code %i", [response statusCode]]);
	}
	
	return nil;
}

#pragma mark Sync

- (void)sync {
	/*	NSFileManager *fileManager = [NSFileManager defaultManager];
	 NSString *applicationSupport = fileManager.processesApplicationSupportFolder;
	 NSString *cloud = [applicationSupport stringByAppendingPathComponent:@"Cloud"];
	 NSString *localMetaDataPath = [cloud stringByAppendingPathComponent:@"metadata.plist"];
	 NSString *loaclDocumentsPath = [cloud stringByAppendingPathComponent:@"Documents"];
	 NSString *localShadowsPath = [cloud stringByAppendingPathComponent:@"Shadows"];
	 
	 NSArray *localMetadata = [NSDictionary dictionaryWithContentsOfFile:localMetaDataPath];*/
	/*
	 NSError *error = nil;
	 NSData *responseData;
	 NSString *responseBody;
	 
	 NSMutableURLRequest *documentsRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://localhost:8093/documents"]];
	 
	 if (responseData = [NSURLConnection sendSynchronousRequest:documentsRequest returningResponse:NULL error:&error]) {
	 responseBody = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
	 }
	 
	 NSArray *cloudMetaData = nil; // fetch from server.
	 
	 // for local document
	 // if shadow exists
	 // compute diff against shadow
	 // if different
	 // put diff to server.
	 // look at results, and save patches that didn't patch.
	 // else
	 // post to sever
	 // get key from post response
	 // create shadow
	 // update local metadata
	 
	 // for local metadata document
	 // if it doesn't exist
	 
	 
	 // for cloud metadata document
	 // if local version exists:
	 // if version number doesn't match cloud version number
	 // download cloud version
	 // replace local and shodow
	 // update localmetadata
	 // else
	 // download cloud document.
	 // replace local and shodow
	 // update localmetadata
	 
	 //[fileManager directoryContentsAtPath:cloudDocuments]
	 */
}

@end

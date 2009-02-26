//
//  BDocuments.m
//  BDocuments
//
//  Created by Jesse Grosjean on 9/7/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "BDocuments.h"
#import <sys/xattr.h>

@implementation NSApplication (BDocumentsAdditions)

static NSDocument *currentDocument = nil;

- (id)currentDocument {
	return currentDocument;
}

- (void)setCurrentDocument:(NSDocument *)newCurrentDocument {
	currentDocument = newCurrentDocument;
}

static NSWindowController *currentDocumentWindowController = nil;

- (id)currentDocumentWindowController {
	return currentDocumentWindowController;
}

- (void)setCurrentDocumentWindowController:(NSWindowController *)newCurrentDocumentWindowController {
	currentDocumentWindowController = newCurrentDocumentWindowController;
}

@end

@implementation NSFileManager (BDocumentsAdditions)

//// From http://zathras.de/programming/cocoa/UKXattrMetadataStore.zip/UKXattrMetadataStore/UKXattrMetadataStore.m
+ (NSArray*)allKeysAtPath:(NSString*)path traverseLink:(BOOL)travLnk {
	NSMutableArray*	allKeys = [NSMutableArray array];
	size_t dataSize = listxattr([path fileSystemRepresentation], NULL, ULONG_MAX, (travLnk ? 0 :XATTR_NOFOLLOW));
	if( dataSize == ULONG_MAX )
		return allKeys;	// Empty list.
	
	NSMutableData*	listBuffer = [NSMutableData dataWithLength:dataSize];
	dataSize = listxattr([path fileSystemRepresentation], [listBuffer mutableBytes], [listBuffer length], (travLnk ? 0 :XATTR_NOFOLLOW) );
	char* nameStart = [listBuffer mutableBytes];
	int x;
	for(x = 0; x < dataSize; x++) {
		if(((char*)[listBuffer mutableBytes])[x] == 0) {
			NSString* str = [NSString stringWithUTF8String:nameStart];
			nameStart = [listBuffer mutableBytes] +x +1;
			[allKeys addObject:str];
		}
	}
	
	return allKeys;
}

+ (void)setData:(NSData*)data forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	setxattr([path fileSystemRepresentation], [key UTF8String], [data bytes], [data length], 0, (travLnk ? 0 :XATTR_NOFOLLOW));
}

+ (void)setObject:(id)obj forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	NSString *errMsg = nil;
	NSData *plistData = [NSPropertyListSerialization dataFromPropertyList:obj format:NSPropertyListXMLFormat_v1_0 errorDescription:&errMsg];
	if(errMsg) {
		[errMsg autorelease];
		[NSException raise:@"BDocumentsXattrMetastoreCantSerialize" format:@"%@", errMsg];
	} else {
		[[self class] setData:plistData forKey:key atPath:path traverseLink:travLnk];
	}
}

+ (void)setString:(NSString*)str forKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) [NSException raise:NSCharacterConversionException format:@"Couldn't convert string to UTF8 for xattr storage."];
	[[self class] setData:data forKey:key atPath:path traverseLink:travLnk];
}

+ (NSMutableData*)dataForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	size_t dataSize = getxattr([path fileSystemRepresentation], [key UTF8String], NULL, ULONG_MAX, 0, (travLnk ? 0 :XATTR_NOFOLLOW));
	if (dataSize == ULONG_MAX)
		return nil;
	
	NSMutableData *data = [NSMutableData dataWithLength:dataSize];
	getxattr([path fileSystemRepresentation], [key UTF8String], [data mutableBytes], [data length], 0, (travLnk ? 0 :XATTR_NOFOLLOW) );
	return data;
}

+ (id)objectForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	NSString* errMsg = nil;
	NSMutableData* data = [[self class] dataForKey:key atPath:path traverseLink:travLnk];
	NSPropertyListFormat outFormat = NSPropertyListXMLFormat_v1_0;
	id obj = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:&outFormat errorDescription:&errMsg];
	if(errMsg) {
		[errMsg autorelease];
		[NSException raise:@"BDocumentsXattrMetastoreCantUnserialize" format:@"%@", errMsg];
	}
	return obj;
}

+ (id)stringForKey:(NSString*)key atPath:(NSString*)path traverseLink:(BOOL)travLnk {
	return [[[NSString alloc] initWithData:[[self class] dataForKey:key atPath:path traverseLink:travLnk] encoding:NSUTF8StringEncoding] autorelease];
}
//// End From http://zathras.de/programming/cocoa/UKXattrMetadataStore.zip/UKXattrMetadataStore/UKXattrMetadataStore.m

- (NSString *)processesCachesFolder {
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *cacheFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
	NSString *processesCacheFolder = [cacheFolder stringByAppendingPathComponent:process];
	if ([self createDirectoriesForPath:processesCacheFolder]) {
		return processesCacheFolder;
	} else {
		return nil;
	}
}

- (NSString *)processesApplicationSupportFolder {
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *applicationSupportFolder = [[NSFileManager defaultManager] findSystemFolderType:kApplicationSupportFolderType forDomain:kUserDomain];
	NSString *processesApplicationSupportFolder = [applicationSupportFolder stringByAppendingPathComponent:process];
	if ([self createDirectoriesForPath:processesApplicationSupportFolder]) {
		return processesApplicationSupportFolder;
	} else {
		return nil;
	}
}

- (NSString *)findSystemFolderType:(NSInteger)folderType forDomain:(NSInteger)domain { 
	FSRef folder; 
	OSErr err = noErr; 
	CFURLRef url; 
	NSString *result = nil; 
	
	err = FSFindFolder(domain, folderType, false, &folder); 
	
	if (err == noErr) {
		url = CFURLCreateFromFSRef(kCFAllocatorDefault, &folder); 
		result = [(NSURL *)url path];
		CFRelease(url);
	}
	
	return result; 
}

- (BOOL)createDirectoriesForPath:(NSString *)path {
	NSMutableArray *pathComponents = [NSMutableArray array];
	
	while (![path isEqual:@"/"]) {
		[pathComponents addObject:[path lastPathComponent]];
		path = [path stringByDeletingLastPathComponent];
	}
	
	BOOL isDirectory;
	
	for (NSString *eachPathComponent in [pathComponents reverseObjectEnumerator]) {
		path = [path stringByAppendingPathComponent:eachPathComponent];
		
		if (![self fileExistsAtPath:path isDirectory:&isDirectory]) {
			if (![self createDirectoryAtPath:path attributes:nil]) {
				BLogError(([NSString stringWithFormat:@"failed to create directory %@", path]));
				return NO;
			}
		} else if (!isDirectory) {
			BLogError(([NSString stringWithFormat:@"non directory file already exists at %@", path]));
			return NO;
		}
	}
	
	return YES;
}

@end

@implementation NSString (BDocumentsAdditions)

// Fromn http://neop.gbtopia.com/?p=27
- (NSComparisonResult)naturalCompare:(NSString *)aString {
	SInt32 compareResult;
	CFIndex lhsLen = [self length];;
    CFIndex rhsLen = [aString length];

	UniChar *lhsBuf = malloc(lhsLen * sizeof(UniChar));
	UniChar *rhsBuf = malloc(rhsLen * sizeof(UniChar));
	
	[self getCharacters:lhsBuf];
	[aString getCharacters:rhsBuf];
	
	(void) UCCompareTextDefault(kUCCollateComposeInsensitiveMask | kUCCollateWidthInsensitiveMask | kUCCollateCaseInsensitiveMask | kUCCollateDigitsOverrideMask | kUCCollateDigitsAsNumberMask| kUCCollatePunctuationSignificantMask,lhsBuf,lhsLen,rhsBuf,rhsLen,NULL,&compareResult);
	
	free(lhsBuf);
	free(rhsBuf);
	
	if (compareResult == 0) {
		return NSOrderedSame;
	} else if (compareResult < 0) {
		return NSOrderedAscending;
	} else {
		return NSOrderedDescending;
	}
}

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

NSString *BDocumentControllerDocumentAddedNotification = @"BDocumentControllerDocumentAddedNotification";
NSString *BDocumentControllerDocumentRemovedNotification = @"BDocumentControllerDocumentRemovedNotification";
//
//  BDocuments.m
//  BDocuments
//
//  Created by Jesse Grosjean on 9/7/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "BDocuments.h"


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

- (NSString *)processesCachesFolder {
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *cacheFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"];
	NSString *processesCacheFolder = [cacheFolder stringByAppendingPathComponent:process];
	BOOL isDirectory;
	
	if (![self fileExistsAtPath:processesCacheFolder isDirectory:&isDirectory]) {
		if (![self createDirectoryAtPath:processesCacheFolder attributes:nil]) {
			BLogError(([NSString stringWithFormat:@"failed to create directory %@", processesCacheFolder]));
			return nil;
		}
	} else if (!isDirectory) {
		BLogError(([NSString stringWithFormat:@"non directory file already exists at %@", processesCacheFolder]));
		return nil;
	}
	
	return processesCacheFolder;
}

- (NSString *)processesApplicationSupportFolder {
	NSString *process = [[NSProcessInfo processInfo] processName];
	NSString *applicationSupportFolder = [[NSFileManager defaultManager] findSystemFolderType:kApplicationSupportFolderType forDomain:kUserDomain];
	NSString *processesApplicationSupportFolder = [applicationSupportFolder stringByAppendingPathComponent:process];
	BOOL isDirectory;
	
	if (![self fileExistsAtPath:processesApplicationSupportFolder isDirectory:&isDirectory]) {
		if (![self createDirectoryAtPath:processesApplicationSupportFolder attributes:nil]) {
			BLogError(([NSString stringWithFormat:@"failed to create directory %@", processesApplicationSupportFolder]));
			return nil;
		}
	} else if (!isDirectory) {
		BLogError(([NSString stringWithFormat:@"non directory file already exists at %@", processesApplicationSupportFolder]));
		return nil;
	}
	
	return processesApplicationSupportFolder;
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
	
	return (CFComparisonResult) compareResult;
}

@end

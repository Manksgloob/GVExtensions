//
//  License.m
//  test1
//
//  Created by Zhi Zheng on 10/19/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#include <sys/types.h>
#include <sys/sysctl.h>
#import <mach/mach_host.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
//#import "License.h"

#import <UIKit/UIKit.h>

// version symbols
// 1.0 - 'X'
// 1.1 - 'Y'
// 1.2.2 - 'Z'
static char _versionSymbol = 'Z';

static NSString *PATH_LICENSEKEY	=@"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.key";
static NSString *URL_LICENSEKEY		=@"http://smsgvextension.appspot.com/key?deviceid=";

#define kIODeviceTreePlane		"IODeviceTree"

enum {
    kIORegistryIterateRecursively	= 0x00000001,
    kIORegistryIterateParents		= 0x00000002
};

typedef mach_port_t	io_object_t;
typedef io_object_t	io_registry_entry_t;
typedef char		io_name_t[128];
typedef UInt32		IOOptionBits;

CFTypeRef IORegistryEntrySearchCFProperty(
								io_registry_entry_t	entry,
								const io_name_t		plane,
								CFStringRef		key,
								CFAllocatorRef		allocator,
								IOOptionBits		options );

kern_return_t
IOMasterPort( mach_port_t	bootstrapPort,
			 mach_port_t *	masterPort );

io_registry_entry_t
IORegistryGetRootEntry(
					   mach_port_t	masterPort );

CFTypeRef
IORegistryEntrySearchCFProperty(
								io_registry_entry_t	entry,
								const io_name_t		plane,
								CFStringRef		key,
								CFAllocatorRef		allocator,
								IOOptionBits		options );

kern_return_t   mach_port_deallocate
(ipc_space_t                               task,
 mach_port_name_t                          name);


static NSArray *__UIDevice_getValue(NSString *iosearch)
{
    mach_port_t          masterPort;
    CFTypeID             propID = (CFTypeID) NULL;
    unsigned int         bufSize;
	
    kern_return_t kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (kr != noErr) return nil;
	
    io_registry_entry_t entry = IORegistryGetRootEntry(masterPort);
    if (entry == MACH_PORT_NULL) return nil;
	
    CFTypeRef prop = IORegistryEntrySearchCFProperty(entry, kIODeviceTreePlane, (CFStringRef) iosearch, nil, kIORegistryIterateRecursively);
    if (!prop) return nil;
	
	propID = CFGetTypeID(prop);
    if (!(propID == CFDataGetTypeID())) 
	{
		mach_port_deallocate(mach_task_self(), masterPort);
		return nil;
	}
	
    CFDataRef propData = (CFDataRef) prop;
    if (!propData) return nil;
	
    bufSize = CFDataGetLength(propData);
    if (!bufSize) return nil;
	
    NSString *p1 = [[[NSString alloc] initWithBytes:CFDataGetBytePtr(propData) length:bufSize encoding:1] autorelease];
    mach_port_deallocate(mach_task_self(), masterPort);
    return [p1 componentsSeparatedByString:@"\0"];
}

NSString *__UIDevice_getIMEI()
{
	NSArray *results = __UIDevice_getValue(@"device-imei");
	NSString *imei = [results objectAtIndex:0];	
	double num = [imei doubleValue];
	
//	if (!(num<1000.0)) {
	if (num<1000.0) {
		// no IMEI
		num = 0.0;
		imei = [[UIDevice currentDevice] uniqueIdentifier];
		for(int i=[imei length]-1;i>=0&&i>=[imei length]-12;i--) {
			int c = [imei characterAtIndex:i];
			num *= 16.0;
			if(c>='0' && c<='9'){
				num += (double)(c-'0');
			}else if(c>='a' && c<='z'){
				num += (double)(c-'a'+10);
			}else if(c>='A' && c<='Z'){
				num += (double)(c-'A'+10);
			}else{
				num += 8.0;
			}
		}
		
		imei = [NSString stringWithFormat:@"%lld",(long long)num];
	}	
	
	return imei;
}

static NSString *__UIDevice_getSerialNnumber()
{
	NSArray *results = __UIDevice_getValue(@"serial-number");
	if (results) return [results objectAtIndex:0];
	return nil;
}

NSString *__getDeviceID(){
	NSString *imei = __UIDevice_getIMEI();
	double num = [imei doubleValue];

	char buffer[13];
	buffer[0] = _versionSymbol;
	buffer[12] = 0;

	for(int i=1;i<12;i++) {
		double quot = floor(num / 26.0);
		double reminder = num - quot * 26.0;
		buffer[i] = 'A' + (unsigned char)reminder;
		num = quot;
	}
	
	return [NSString stringWithUTF8String:buffer];
}

NSString *__getLicenseKey() {
	const static unsigned long long _values[25] = {
		345463, 783240, 20939102, 2393048, 99543, 2134, 435, 23432, 435432, 5343, 234435, 234, 43543, 2111,12312,
		4435, 54, 23434455, 54345, 75567654, 23324, 23654, 23543, 3211232, 23443543
	};
	const static unsigned long long _targets[15] = {
		435, 65, 345, 345654, 4566, 234, 5654, 452, 234, 34, 456546, 324342, 345, 2342, 42
	};
	
	NSString *str = @"";
	NSString *imei = __UIDevice_getIMEI();
	unsigned long long lbase = [imei longLongValue];
	lbase *= 10;
	lbase += 0x324FA1;
	for(int i=0,j=0; i<25;i++){
		unsigned long long temp = lbase % _values[i];
		temp += _targets[j];
		j = (j+1) % 15;
		str = [str stringByAppendingFormat:@"%qu", temp];
	}
	return str;
}

BOOL __checkLocalLicenseKey() {
	NSString *str = [NSString stringWithContentsOfFile:PATH_LICENSEKEY encoding:NSUTF8StringEncoding error:nil];
	if(!str)
		return NO;
	
	return [str isEqualToString:__getLicenseKey()];
}

BOOL __obtainRemoteKey() {
	NSString *devId = __getDeviceID();
	NSString *urlStr = [URL_LICENSEKEY stringByAppendingString:devId];
	NSURL *url = [NSURL URLWithString:urlStr];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];	
	
	if(!response || [response statusCode] != 200 || responseData == nil){
		return NO;
	}
	
	NSString *key = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
	[key writeToFile:PATH_LICENSEKEY atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[key release];
	
	return YES;
}

BOOL __hasValidLicenseKey() {
	if(__checkLocalLicenseKey())
		return YES;
	
	if(!__obtainRemoteKey())
		return NO;
	
	return __checkLocalLicenseKey();
}

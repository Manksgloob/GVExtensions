
#import "CoreTelephony/CDStructures.h"
#import "CoreTelephony/CTMessageCenter.h"
#import "CoreTelephony/CTMessage.h"
#import "CoreTelephony/CTMessagePart.h"
#import "CoreTelephony/CTPhoneNumber.h"
//#import <MobileMail/MailAppController.h>
//#import <Message/MailAccount.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "substrate.h"
#import "SendMsgThread.h"
#import "License.h"
#include <pthread.h>

#define		GV_BASEMESSAGEID					0x1234

#define		__ENABLE_DRM__
#define		__DRM_CHECKINTERVAL					50

BOOL _licenseStatus = NO;

static unsigned int currentMessageIdReceive = GV_BASEMESSAGEID;
static NSMutableDictionary *_dictMsgIdPaths = nil;

static NSString *PATH_MESSAGE_PREFIX			=@"_gvsms__";
static NSString *PATH_SETTINGS					=@"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.plist";
static NSString *PATH_LICENSEKEY				=@"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.key";

static NSString *CSMSGVSETTINGSNOTIFICATION		=@"kCSMSGVSettingsNotification";
static NSString *CSMSGVLICENSENOTIFICATION		=@"kCSMSGVLicenseNotification";
static NSString *CSMSGVCACHEREFRESHNOTIFICATION	=@"kCSMSGVRefreshContactsCacheNotification";

NSString *GV_username=nil;
NSString *GV_password=nil;
NSString *GV_sendsig=nil;
NSString *GV_recvsig=nil;

// callback related global definitions / constants
#define		COUNT_INTERESTEDNOTIFICATIONS		3
#define		ID_CTMESSAGERECEIVEDNOTIFICATION	0
#define		ID_CTMESSAGESENTNOTIFICATION		1
#define		ID_CTMESSAGESENDERRORNOTIFICATION	2
#define		CTMESSAGERECEIVEDNOTIFICATION		@"kCTMessageReceivedNotification"
#define		CTMESSAGESENTNOTIFICATION			@"kCTMessageSentNotification"
#define		CTMESSAGESENDERRORNOTIFICATION		@"kCTMessageSendErrorNotification"
static NSString *interestedNotifications[COUNT_INTERESTEDNOTIFICATIONS] = {
	CTMESSAGERECEIVEDNOTIFICATION,
	CTMESSAGESENTNOTIFICATION,
	CTMESSAGESENDERRORNOTIFICATION
};

// for each: nsnumber of func, id1, id2
NSMutableArray *arrayCallbacks[COUNT_INTERESTEDNOTIFICATIONS]={nil, nil, nil};

NSMutableDictionary *_dictContactsCache=nil;

// global status (from settings)
static BOOL GV_enableSend = YES;
static BOOL GV_enableReceive = YES;
static BOOL GV_enableReceiveOfficialGV = YES;
static int __licenseCounter;

// original CoreTelephony methods
static CDStruct_1ef3fb1f (* _orig_CTMessageCenter_sendSMS)(id, SEL, ...);
static CDStruct_1ef3fb1f (*_orig_CTMessageCenter_send)(id, SEL, ...);
static id (*_orig_CTMessageCenter_incomingMessageWithId_telephonyCenter_isDeferred)(id, SEL, ...);
static int (*_orig_CTMessageCenter_incomingMessageCount)(id, SEL, ...);
static id (*_orig_CTMessageCenter_allIncomingMessages)(id, SEL, ...);
static id (*_orig_CTMessageCenter_incomingMessageWithId)(id, SEL, ...);
static id (*_orig_CTMessageCenter_deferredMessageWithId)(id, SEL, ...);
static id (*_orig_CTMessageCenter_statusOfOutgoingMessages)(id, SEL, ...);
static BOOL (*_orig_CTMessageCenter_sendSMSWithText_serviceCenter_toAddress)(id, SEL, ...);

extern id CTTelephonyCenterGetDefault(void);
extern void CTTelephonyCenterAddObserver(id,id,CFNotificationCallback,NSString*,void*,int);

void (*_orig_CTTelephonyCenterAddObserver)(id,id,CFNotificationCallback,NSString*,void*,int);
static void _mymsgcallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mysettingscallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mynewmsgcallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mylicensecallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mylicensecallbackQuiet(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mycacherefreshcallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void readSettings();

static NSMutableArray *arraySendMsgIds=nil;

extern NSString *__UIDevice_getIMEI();
extern BOOL __obtainRemoteKey();

@interface UIAlertViewDelegateLicense : NSObject <UIAlertViewDelegate> 
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
@property (retain) NSString *deviceId;
@end

@implementation UIAlertViewDelegateLicense
#import <mach/mach_host.h>
@synthesize deviceId;
extern void GSEventSendApplicationOpenURL(CFURLRef url, mach_port_t port, bool asPanel);
extern mach_port_t GSCopyPurpleNamedPort(const char* bootstrap_name);
kern_return_t   mach_port_deallocate(ipc_space_t task, mach_port_name_t name);
static void __openURL(NSString *url) {
	NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
	if ([currSysVer characterAtIndex:0]=='5'){
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
	}else{
		const char* bootstrap_name = "PurpleSystemEventPort";
		mach_port_t port = GSCopyPurpleNamedPort(bootstrap_name);
		GSEventSendApplicationOpenURL((CFURLRef)[NSURL URLWithString:url], port, false);
		mach_port_deallocate(mach_task_self_, port);
	}
}
-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if(buttonIndex==1){
		NSString *url = [NSString stringWithFormat:@"http://smsgvextension.appspot.com/buy?deviceid=%@&client=iOS", deviceId];
		__openURL(url);
	}
}
-(void)dealloc {
	[deviceId release];
	[super dealloc];
}
@end

UIAlertViewDelegateLicense *licenseDelegate=nil;

static BOOL __enableLogging = FALSE;

static NSString *PATH_LOG = @"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.log.txt";

BOOL __is_logging() {
	return __enableLogging;
}

void __do_logging(NSString *str) {
	NSString *ff = [NSString stringWithContentsOfFile:PATH_LOG encoding:NSUTF8StringEncoding error:nil];
	if(!ff){
		ff = [@"SMS GV Extension Log File\n" stringByAppendingString:str];
	}else{
		ff = [ff stringByAppendingString:str];
	}
	[ff writeToFile:PATH_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static unsigned long long __time(){
	return (unsigned long long)([ [NSDate date] timeIntervalSince1970] * 1000.0);
}

static void __writeReceivedNumberAndTextToFile (NSString *number, NSString *text) {
	NSString *path = [NSString stringWithFormat:@"/var/tmp/%@%llu", PATH_MESSAGE_PREFIX, __time()];
	[[NSString stringWithFormat:@"%@\n%@", number, text] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

void _new_CTTelephonyCenterAddObserver(id id1,id id2,CFNotificationCallback f,
									   NSString* str,void* p,int n){
	
	static int firstRun = 1;
	
	if(firstRun){		
		firstRun=0;
		for(int i=0;i<COUNT_INTERESTEDNOTIFICATIONS;i++){
			CFNotificationCenterAddObserver(
											CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
											(CFNotificationCallback)&_mymsgcallback, (CFStringRef)(interestedNotifications[i]), NULL, 3);
			arrayCallbacks[i]=[[NSMutableArray alloc] init];

		}
		CFNotificationCenterAddObserver(
										CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
										(CFNotificationCallback)&_mysettingscallback, (CFStringRef)(CSMSGVSETTINGSNOTIFICATION), NULL, 3);	

		CFNotificationCenterAddObserver(
										CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
										(CFNotificationCallback)&_mycacherefreshcallback, (CFStringRef)(CSMSGVCACHEREFRESHNOTIFICATION), NULL, 3);	
		
#ifdef __ENABLE_DRM__
		_licenseStatus = FALSE;
		//////// LICENSE CODE ////////
		NSString *imei = __UIDevice_getIMEI();
		long long limei;
		if(!imei || [imei length]==0){
			limei=0;
		}else{
			limei = [imei longLongValue];
		}
		unsigned int _now = (unsigned int)[ [NSDate date] timeIntervalSince1970];
		
		NSString *strLicense = [NSString stringWithContentsOfFile:PATH_LICENSEKEY encoding:NSUTF8StringEncoding error:nil];
		if(strLicense && [strLicense length]>0){
			char *buf = (char *) [strLicense UTF8String];
			
			char c;
			int num = 0, num0;
			int rand = 1, lastsep=0;
			long long l1 = 0, l2=0, l3=0;
			int stage=0;
			
			while((c=*buf++)){
				if(c>'A'){
					c = c-'A'+'9';
				}
				if(c>'3'){
					num = num*10 + c - '4';
					lastsep=0;
				}else{
					if(lastsep){
						stage++;
						lastsep=0;
						num=0;
						continue;
					}else{
						lastsep =1;
					}
					if(!rand){
						int ch = (num0==0)?0:(num/num0);
						if(stage==0)
							l1 = l1*10 + ch - '0';
						else if(stage==1)
							l2 = l2*10 + ch - '0';
						else if(stage==2)
							l3 = l3*10 + ch - '0';
						
					}else{
						num0 = num;
					}
					num = 0;
					rand=!rand;
				}
				
			}
			
			if(l1==limei){
				if(l2==0){
					_licenseStatus = TRUE;
				}else if(l3>0 && l3<l2 && _now<l2 && _now>l3-86400){
//					_licenseStatus = TRUE;
					NSString *devId = __getDeviceID();
					licenseDelegate.deviceId = devId;
					NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nBuy from Settings | SMS GV Extension | Check License.", devId];
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//					[alert addButtonWithTitle:@"Buy"];
					[alert show];	
				}else if(l3==0 || _now <= l3-86400){
//					[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"Obtain License from Settings | SMS GV Extension | Check License."
//												delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];									
					NSString *devId = __getDeviceID();
					licenseDelegate.deviceId = devId;
					NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nBuy from Settings | SMS GV Extension | Check License.", devId];
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//					[alert addButtonWithTitle:@"Buy"];
					[alert show];	
				}else{
//					// expired
//					_licenseStatus = FALSE;
//					[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"License Expired."
//																	   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
					NSString *devId = __getDeviceID();
					licenseDelegate.deviceId = devId;
					NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nBuy from Settings | SMS GV Extension | Check License.", devId];
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//					[alert addButtonWithTitle:@"Buy"];
					[alert show];	
				}
			}else{
				// invalid license found
//				[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"Obtain License from Settings | SMS GV Extension | Check License."
//											delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];				
				NSString *devId = __getDeviceID();
				licenseDelegate.deviceId = devId;
				NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nBuy from Settings | SMS GV Extension | Check License.", devId];
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//				[alert addButtonWithTitle:@"Buy"];
				[alert show];	
			}
		}else{
			// no license found
//			[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"Obtain License from Settings | SMS GV Extension | Check License."
//										delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];				
			NSString *devId = __getDeviceID();
			licenseDelegate.deviceId = devId;
			NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nBuy from Settings | SMS GV Extension | Check License.", devId];
			UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//			[alert addButtonWithTitle:@"Buy"];
			[alert show];	
		}
		
		__licenseCounter = 1;
		
		CFNotificationCenterAddObserver(
										CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
										(CFNotificationCallback)&_mylicensecallback, (CFStringRef)(CSMSGVLICENSENOTIFICATION), NULL, 3);	
#else
		_licenseStatus=TRUE;
#endif // __ENABLE_DRM__
		
		arraySendMsgIds = [[NSMutableArray alloc] init];
		_dictContactsCache = [[NSMutableDictionary alloc] init];
		_dictMsgIdPaths = [[NSMutableDictionary alloc] init];
		readSettings();
	}		
	
	for(int i=0;i<COUNT_INTERESTEDNOTIFICATIONS;i++){
		if([str isEqualToString:interestedNotifications[i]]){
			NSString *nf = [NSString stringWithFormat:@"%d",(int)f];
			NSString *nid1 = [NSString stringWithFormat:@"%d",(int)id1];
			NSString *nid2 = [NSString stringWithFormat:@"%d",(int)id2];
			[arrayCallbacks[i] addObject:nf];
			[arrayCallbacks[i] addObject:nid1];
			[arrayCallbacks[i] addObject:nid2];
			break;
		}
	}
		
	_orig_CTTelephonyCenterAddObserver(id1,id2,f,str,p,n);
}

extern void postNotification(NSString *key, unsigned int msgId) {
	if([key isEqualToString:CTMESSAGESENTNOTIFICATION] || [key isEqualToString:CTMESSAGESENDERRORNOTIFICATION]){
		NSNumber *number = [NSNumber numberWithInt:msgId];
		[arraySendMsgIds addObject:number];
	}
	
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
										 (CFStringRef)key, NULL, NULL, TRUE);
}

static void readSettings() {
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1;
		n1 = [settings valueForKey:@"enableSend"];
		if(n1)
			GV_enableSend = [n1 boolValue];
		n1 = [settings valueForKey:@"enableReceive"];
		if(n1)
			GV_enableReceive = [n1 boolValue];
		n1 = [settings valueForKey:@"enableReceiveOfficialGV"];
		if(n1)
			GV_enableReceiveOfficialGV = [n1 boolValue];
		n1 = [settings valueForKey:@"enableLogging"];
		if(n1)
			__enableLogging = [n1 boolValue];
		[GV_username release];
		GV_username = [settings valueForKey:@"username"];
		if(GV_username && [GV_username rangeOfString:@"@"].location==NSNotFound){
			GV_username = [GV_username stringByAppendingString:@"@gmail.com"];
		}
		[GV_username retain];
		[GV_password release];
		GV_password = [settings valueForKey:@"password"];
		[GV_password retain];
		[GV_sendsig release];
		GV_sendsig = [settings valueForKey:@"sendsig"];
		[GV_sendsig retain];
		[GV_recvsig release];
		GV_recvsig = [settings valueForKey:@"recvsig"];
		[GV_recvsig retain];
	}			
}

static void _mysettingscallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	readSettings();
}

static void _mycacherefreshcallback(id id1, id id2, NSString *str, void *p, CFDictionaryRef dict) {
	[_dictContactsCache removeAllObjects];
}

static void _mylicensecallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
		
	BOOL bres = FALSE;
	
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1 = [settings valueForKey:@"promptForLicense"];
		if(n1)
			bres = [n1 boolValue];
	}
	
	if(bres) {
#ifdef __ENABLE_DRM__
		/*BOOL bres2 = */__obtainRemoteKey();
//		if(bres2){
			_licenseStatus = FALSE;
			//////// LICENSE CODE ////////
			NSString *imei = __UIDevice_getIMEI();
			long long limei;
			if(!imei || [imei length]==0){
				limei=0;
			}else{
				limei = [imei longLongValue];
			}
			unsigned int _now = (unsigned int)[ [NSDate date] timeIntervalSince1970];
			
			NSString *strLicense = [NSString stringWithContentsOfFile:PATH_LICENSEKEY encoding:NSUTF8StringEncoding error:nil];
			if(strLicense && [strLicense length]>0){
				char *buf = (char *) [strLicense UTF8String];
				
				char c;
				int num = 0, num0;
				int rand = 1, lastsep=0;
				long long l1 = 0, l2=0, l3=0;
				int stage=0;
				
				while((c=*buf++)){
					if(c>'A'){
						c = c-'A'+'9';
					}
					if(c>'3'){
						num = num*10 + c - '4';
						lastsep=0;
					}else{
						if(lastsep){
							stage++;
							lastsep=0;
							num=0;
							continue;
						}else{
							lastsep =1;
						}
						if(!rand){
							int ch = (num0==0)?0:(num/num0);
							if(stage==0)
								l1 = l1*10 + ch - '0';
							else if(stage==1)
								l2 = l2*10 + ch - '0';
							else if(stage==2)
								l3 = l3*10 + ch - '0';
							
						}else{
							num0 = num;
						}
						num = 0;
						rand=!rand;
					}
					
				}
								
				if(l1==limei){
					if(l2==0){
						_licenseStatus = TRUE;
						[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"License Status: Registered."
													delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
					}else if(l3>0 && l3<l2 && _now<l2 && _now>l3-86400){
//						_licenseStatus = TRUE;
//						NSString *devId = __getDeviceID();
//						licenseDelegate.deviceId = devId;
//						int nDays = (l2 - _now) / 86400;
//						NSString *message = [NSString stringWithFormat:@"License Status: Trial: %d Day(s).\nDevice ID: %@\nsmsgvextension.appspot.com", nDays, devId];
//						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//						[alert addButtonWithTitle:@"Buy"];
//						[alert show];	
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}else if(l3==0 || _now <= l3-86400){
//						// invalid license found
//						NSString *devId = __getDeviceID();
//						licenseDelegate.deviceId = devId;
//						NSString *message = [NSString stringWithFormat:@"License Status: Invalid.\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
//						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//						[alert addButtonWithTitle:@"Buy"];
//						[alert show];	
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}else{
//						// expired
//						//					_licenseStatus = FALSE;
//						NSString *devId = __getDeviceID();
//						licenseDelegate.deviceId = devId;
//						NSString *message = [NSString stringWithFormat:@"License Status: Expired.\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
//						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//						[alert addButtonWithTitle:@"Buy"];
//						[alert show];	
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}
				}else{
//					// invalid license found
//					NSString *devId = __getDeviceID();
//					licenseDelegate.deviceId = devId;
//					NSString *message = [NSString stringWithFormat:@"License Status: Invalid.\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
//					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//					[alert addButtonWithTitle:@"Buy"];
//					[alert show];	
					NSString *devId = __getDeviceID();
					licenseDelegate.deviceId = devId;
					NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
					[alert addButtonWithTitle:@"Buy"];
					[alert show];	
				}
			}else{
//				// no license found
//				NSString *devId = __getDeviceID();
//				licenseDelegate.deviceId = devId;
//				NSString *message = [NSString stringWithFormat:@"License Status: Not Found.\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
//				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
//				[alert addButtonWithTitle:@"Buy"];
//				[alert show];	
				NSString *devId = __getDeviceID();
				licenseDelegate.deviceId = devId;
				NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
				[alert addButtonWithTitle:@"Buy"];
				[alert show];	
			}
//		}
#else
		_licenseStatus=TRUE;
#endif // __ENABLE_DRM__

	}
}

static void __callCallbacks(NSArray *arrayCallbacksi, NSString *key, int msgId, void *p) {
	NSNumber *number = [NSNumber numberWithInt:msgId];
	NSNumber *type = [NSNumber numberWithInt:1];
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	[dict setObject:type forKey:@"kCTMessageTypeKey"];
	[dict setObject:number forKey:@"kCTMessageIdKey"];
	for(int j=0;j<[arrayCallbacksi count];){
		NSString *nf = [arrayCallbacksi objectAtIndex:j++];
		CFNotificationCallback f = (CFNotificationCallback)[nf intValue];
		NSString *nid1 = [arrayCallbacksi objectAtIndex:j++];
		CFNotificationCenterRef _id1 = (CFNotificationCenterRef)[nid1 intValue];
		NSString *nid2 = [arrayCallbacksi objectAtIndex:j++];
		id _id2 = (id)[nid2 intValue];
		f(_id1, _id2, (CFStringRef)key, p, (CFDictionaryRef)dict);
	}
	[dict release];
}

static void _mymsgcallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	for(int i=0;i<COUNT_INTERESTEDNOTIFICATIONS;i++){
		if([interestedNotifications[i] isEqualToString:key]){
			if([arrayCallbacks[i] count]>0){
				if([key isEqualToString:CTMESSAGESENTNOTIFICATION] || [key isEqualToString:CTMESSAGESENDERRORNOTIFICATION]){
					NSNumber *number = [arraySendMsgIds objectAtIndex:0];
					if(!number)
						return;
					__callCallbacks(arrayCallbacks[i],key, [number intValue], p);
					[arraySendMsgIds removeObjectAtIndex:0];
				}else{
					NSArray *msgs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/tmp" error:nil];
					if(msgs){
						for(int ii=0;ii<[msgs count];ii++){
							NSString *msgpath = [msgs objectAtIndex:ii];
							if([msgpath rangeOfString:PATH_MESSAGE_PREFIX].location==0){
								int msgId = currentMessageIdReceive++;
								NSString *sid = [NSString stringWithFormat:@"%d",msgId];
								[_dictMsgIdPaths setObject:[@"/var/tmp" stringByAppendingPathComponent:msgpath] forKey:sid];
								__callCallbacks(arrayCallbacks[i], key, msgId, p);
							}
						}
					}
				}
			}
		break;
		}
	}
}

// CoreTelephony methods
static CDStruct_1ef3fb1f _CTMessageCenter_sendSMS(CTMessageCenter *_CTMsgCenter, SEL _sel,
													  id _id) {		
	if(!GV_enableSend){
		return _orig_CTMessageCenter_sendSMS(_CTMsgCenter, _sel, _id);				
	}
		
	CDStruct_1ef3fb1f ret;
	ret._field1=0;
	ret._field2=0;	

	CTMessage *msg = (CTMessage *)_id;
		
	if(msg.messageType==1){
		CTMessagePart *part0 = [msg.items objectAtIndex:0];
		NSString *text = [[NSString alloc] initWithData:part0.data encoding:NSUTF8StringEncoding];
		[SendMsgThread invokeWithDestination:msg.recipients Text:text messageId:msg.messageId postNotification:&postNotification];
		[text release];

		return ret;
	}else{
		// for any other type than SMS, we let it pass through
		return _orig_CTMessageCenter_sendSMS(_CTMsgCenter, _sel, _id);				
	}
		
}

static CDStruct_1ef3fb1f _CTMessageCenter_send(CTMessageCenter *_CTMsgCenter,
													  SEL _sel,id _id) {	
	if(!GV_enableSend){
		return _orig_CTMessageCenter_send(_CTMsgCenter, _sel, _id);				
	}
	
	CDStruct_1ef3fb1f ret;
	ret._field1=0;
	ret._field2=0;	
	
	CTMessage *msg = (CTMessage *)_id;
		
	if(msg.messageType==0){
		msg.messageType=1;
		CTMessagePart *part0 = [msg.items objectAtIndex:0];
		NSString *text = [[NSString alloc] initWithData:part0.data encoding:NSUTF8StringEncoding];
		[SendMsgThread invokeWithDestination:msg.recipients Text:text messageId:msg.messageId postNotification:&postNotification];
		[text release];
				
		return ret;
	}else{
		// for any other type than SMS, we let it pass through
		return _orig_CTMessageCenter_send(_CTMsgCenter, _sel, _id);				
	}

}

static id __process_incomingMsg(unsigned int arg1) {
	
	NSString *key = [NSString stringWithFormat:@"%d",arg1];
	NSString *path = [_dictMsgIdPaths objectForKey:key];
	[_dictMsgIdPaths removeObjectForKey:key];
	if(!path)
		return nil;

	NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	if(!content)
		return nil;

	NSString *number;
	NSString *text;
	
	NSRange rn = [content rangeOfString:@"\n"];
	if(rn.location!=NSNotFound){
		number = [content substringToIndex:rn.location];
		text = [content substringFromIndex:rn.location+1];
	}
	else{
		number = content;
		text=@"";
	}
	
	if(GV_recvsig && [GV_recvsig length]>0){
		text = [text stringByAppendingFormat:@"\n%@", GV_recvsig];
	}		
		
	CTPhoneNumber *addr = [CTPhoneNumber phoneNumberWithDigits:number countryCode:@"1"];
	CTMessage *msg = [[[CTMessage alloc] init] autorelease];
	CTMessagePart *part0 = [[[CTMessagePart alloc] init] autorelease];
	part0.data=[text dataUsingEncoding:NSUTF8StringEncoding];
	[msg addPart:part0];
	msg.sender = addr;
	msg.messageId=arg1;
	msg.messageType=1;
		
//		msg.contentType=@"plain/text";
		
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];	
	
	return msg;
}

static id _CTMessageCenter_incomingMessageWithId_telephonyCenter_isDeferred(CTMessageCenter *_CTMsgCenter,
		SEL _sel,unsigned int arg1, void *arg2, BOOL arg3) {	
	CTMessage *msg = __process_incomingMsg(arg1);
	
	if(!msg) {
		// well, this is a system one
		msg = _orig_CTMessageCenter_incomingMessageWithId_telephonyCenter_isDeferred(_CTMsgCenter, _sel, arg1, arg2, arg3);
		if(msg){
			msg.messageId=currentMessageIdReceive++;
//			if(msg.messageType==0){
//				msg.messageType = 1;
//			}
		}
	}
	
	return msg;
}

static int _CTMessageCenter_incomingMessageCount(CTMessageCenter *_CTMsgCenter, SEL _sel) {	
	return _orig_CTMessageCenter_incomingMessageCount(_CTMsgCenter, _sel);
}

static id _CTMessageCenter_allIncomingMessages(CTMessageCenter *_CTMsgCenter, SEL _sel) {	
	return _orig_CTMessageCenter_allIncomingMessages(_CTMsgCenter, _sel);
}

static id _CTMessageCenter_incomingMessageWithId(CTMessageCenter *_CTMsgCenter,
																  SEL _sel, unsigned int arg1) {	
	CTMessage *msg = __process_incomingMsg(arg1);
	
	if(!msg) {
		// well, this is a system one
		msg = _orig_CTMessageCenter_incomingMessageWithId(_CTMsgCenter, _sel, arg1);
		if(msg){
			msg.messageId=currentMessageIdReceive++;
//			if(msg.messageType==0){
//				msg.messageType = 1;
//			}
		}
	}
	
	return msg;
}

static id _CTMessageCenter_deferredMessageWithId(CTMessageCenter *_CTMsgCenter,
													SEL _sel, unsigned int arg1) {	
	return _orig_CTMessageCenter_deferredMessageWithId(_CTMsgCenter, _sel, arg1);
}

static id _CTMessageCenter_statusOfOutgoingMessages(CTMessageCenter *_CTMsgCenter, SEL _sel) {	
	return _orig_CTMessageCenter_statusOfOutgoingMessages(_CTMsgCenter, _sel);
}

static BOOL _CTMessageCenter_sendSMSWithText_serviceCenter_toAddress(CTMessageCenter *_CTMsgCenter,
												 SEL _sel, id arg1, id arg2, id arg3) {	
	return _orig_CTMessageCenter_sendSMSWithText_serviceCenter_toAddress(_CTMsgCenter, _sel, arg1, arg2, arg3);
}

static BOOL __isPhoneNumber(NSString *str){
	const char *p = [str UTF8String];
	char c;
	while((c=*p++)){
		if(c=='+' || c=='-' || c=='(' || c==')' || c==' ' || (c>='0' && c<='9')){
		}else{
			return FALSE;
		}
	}
	return TRUE;
}

extern NSString *__cacheContact(NSString *sender);

static IMP old_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel = NULL;
static void replaced_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel(id self, SEL _cmd, id conn, NSString *topic, NSDictionary *userInfo) {
	
	if(!_licenseStatus || !GV_enableReceiveOfficialGV){
		old_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel(self, _cmd, conn, topic, userInfo);	
		return;
	}

	if(topic && [topic isEqualToString:@"com.google.GVDialer"] && userInfo){
		// Official GV app

#ifdef __ENABLE_DRM__
//		if(!checked){
//			checked=1;
			if(__licenseCounter>0){
				__licenseCounter --;
			}else{
				BOOL bres2 = __obtainRemoteKey();
				if(bres2){
					__licenseCounter = __DRM_CHECKINTERVAL;
					_licenseStatus = FALSE;
					//////// LICENSE CODE ////////
					NSString *imei = __UIDevice_getIMEI();
					long long limei;
					if(!imei || [imei length]==0){
						limei=0;
					}else{
						limei = [imei longLongValue];
					}
					unsigned int _now = (unsigned int)[ [NSDate date] timeIntervalSince1970];
					
					NSString *strLicense = [NSString stringWithContentsOfFile:PATH_LICENSEKEY encoding:NSUTF8StringEncoding error:nil];
					if(strLicense && [strLicense length]>0){
						char *buf = (char *) [strLicense UTF8String];
						
						char c;
						int num = 0, num0;
						int rand = 1, lastsep=0;
						long long l1 = 0, l2=0, l3=0;
						int stage=0;
						
						while((c=*buf++)){
							if(c>'A'){
								c = c-'A'+'9';
							}
							if(c>'3'){
								num = num*10 + c - '4';
								lastsep=0;
							}else{
								if(lastsep){
									stage++;
									lastsep=0;
									num=0;
									continue;
								}else{
									lastsep =1;
								}
								if(!rand){
									int ch = (num0==0)?0:(num/num0);
									if(stage==0)
										l1 = l1*10 + ch - '0';
									else if(stage==1)
										l2 = l2*10 + ch - '0';
									else if(stage==2)
										l3 = l3*10 + ch - '0';
									
								}else{
									num0 = num;
								}
								num = 0;
								rand=!rand;
							}
							
						}
						
						if(l1==limei){
							if(l2==0){
								_licenseStatus = TRUE;
							}else if(l3>0 && l3<l2 && _now<l2 && _now>l3-86400){
								//									_licenseStatus = TRUE;
								NSString *devId = __getDeviceID();
								licenseDelegate.deviceId = devId;
								NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
								UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
								[alert addButtonWithTitle:@"Buy"];
								[alert show];	
							}else if(l3==0 || _now <= l3-86400){
								// invalid license found
								NSString *devId = __getDeviceID();
								licenseDelegate.deviceId = devId;
								NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
								UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
								[alert addButtonWithTitle:@"Buy"];
								[alert show];	
							}else{
								// expired
								//					_licenseStatus = FALSE;
								NSString *devId = __getDeviceID();
								licenseDelegate.deviceId = devId;
								NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
								UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
								[alert addButtonWithTitle:@"Buy"];
								[alert show];	
							}
						}else{
							// invalid license found
							NSString *devId = __getDeviceID();
							licenseDelegate.deviceId = devId;
							NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
							UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
							[alert addButtonWithTitle:@"Buy"];
							[alert show];	
						}
					}else{
						// no license found
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						NSString *message = [NSString stringWithFormat:@"License Status: Trial (Send Only).\nDevice ID: %@\nsmsgvextension.appspot.com", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}
				}
			}
			if(!_licenseStatus){
				old_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel(self, _cmd, conn, topic, userInfo);	
				return;
			}
//		}
#endif //__ENABLE_DRM__
		
		NSDictionary *aps = [userInfo objectForKey:@"aps"];
		if(aps){
			NSString *alert = [aps objectForKey:@"alert"];
			if(alert){
				
				if(__is_logging()) {
					NSString *ss = [NSString stringWithFormat:@"%@\n%@\n",@"push alert received",alert];
					__do_logging(ss);
				}
				
				NSString *header = @"Text from ";
				NSRange range = [alert rangeOfString:header];
				if(range.location == 0){
					NSString *sender;
					NSString *text;
						
					NSRange r2 = [alert rangeOfString:@":\n"];
					if(r2.location!=NSNotFound && r2.location>[header length]){
						NSRange r3;
						r3.location = [header length];
						r3.length = r2.location - r3.location;
						sender = [alert substringWithRange:r3];
						text = [alert substringFromIndex:r3.location+r3.length+2];
					}else{
						sender = @"000000";
						text = [alert substringFromIndex:range.length];
					}
					if(!__isPhoneNumber(sender)){
						// need to find real phone number
						NSString *number = [_dictContactsCache objectForKey:sender];
						if(!number || [number length]<1){
							number = __cacheContact(sender);
						}
						sender = number;
					}
					if(!sender)
						sender = @"000000";
					__writeReceivedNumberAndTextToFile(sender, text);
					postNotification(CTMESSAGERECEIVEDNOTIFICATION, 0);		
					
					return;
				}
			}
		}
		
	}

	old_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel(self, _cmd, conn, topic, userInfo);	
}

void SMSGVExtensionInitialize() {
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	    
//	[[NSFileManager defaultManager] createDirectoryAtPath:PATH_TEMPDIR withIntermediateDirectories:NO attributes:nil error:nil];
//	[[NSFileManager defaultManager] createDirectoryAtPath:PATH_TEMPDIRMSGS withIntermediateDirectories:NO attributes:nil error:nil];
				
#ifdef		__ENABLE_DRM__
	licenseDelegate = [[UIAlertViewDelegateLicense alloc] init];
#endif // __ENABLE_DRM__
	
	MSHookFunction(&CTTelephonyCenterAddObserver, &_new_CTTelephonyCenterAddObserver, (void **)&_orig_CTTelephonyCenterAddObserver);
	
	// CoreTelephony overridings
	Class _$CTMessageCenter = objc_getClass("CTMessageCenter");
	MSHookMessageEx(_$CTMessageCenter, @selector(sendSMS:), (IMP) &_CTMessageCenter_sendSMS, (IMP *)&_orig_CTMessageCenter_sendSMS);
	MSHookMessageEx(_$CTMessageCenter, @selector(send:), (IMP) &_CTMessageCenter_send, (IMP *)&_orig_CTMessageCenter_send);
	MSHookMessageEx(_$CTMessageCenter, @selector(incomingMessageWithId:telephonyCenter:isDeferred:), (IMP) &_CTMessageCenter_incomingMessageWithId_telephonyCenter_isDeferred, (IMP *)&_orig_CTMessageCenter_incomingMessageWithId_telephonyCenter_isDeferred);
	MSHookMessageEx(_$CTMessageCenter, @selector(incomingMessageCount), (IMP) &_CTMessageCenter_incomingMessageCount, (IMP *)&_orig_CTMessageCenter_incomingMessageCount);
	MSHookMessageEx(_$CTMessageCenter, @selector(allIncomingMessages), (IMP) &_CTMessageCenter_allIncomingMessages, (IMP *)&_orig_CTMessageCenter_allIncomingMessages);
	MSHookMessageEx(_$CTMessageCenter, @selector(incomingMessageWithId:), (IMP) &_CTMessageCenter_incomingMessageWithId, (IMP *)&_orig_CTMessageCenter_incomingMessageWithId);
	MSHookMessageEx(_$CTMessageCenter, @selector(deferredMessageWithId:), (IMP) &_CTMessageCenter_deferredMessageWithId, (IMP *)&_orig_CTMessageCenter_deferredMessageWithId);
	MSHookMessageEx(_$CTMessageCenter, @selector(statusOfOutgoingMessages), (IMP) &_CTMessageCenter_statusOfOutgoingMessages, (IMP *)&_orig_CTMessageCenter_statusOfOutgoingMessages);
	MSHookMessageEx(_$CTMessageCenter, @selector(sendSMSWithText:serviceCenter:toAddress:), (IMP) &_CTMessageCenter_sendSMSWithText_serviceCenter_toAddress, (IMP *)&_orig_CTMessageCenter_sendSMSWithText_serviceCenter_toAddress);
	
	Class _$CPUSH = objc_getClass("SBRemoteNotificationServer");
	MSHookMessageEx(_$CPUSH, @selector(connection:didReceiveMessageForTopic:userInfo:),
					(IMP)&replaced_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel,
					(IMP *)&old_SBRemoteNotificationAlert_initWithApplication_body_showActionButton_actionLabel);
		
	[pool release];
	
}

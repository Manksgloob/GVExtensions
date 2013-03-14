
//#import <CoreTelephony/CDStructures.h>
//#import <CoreTelephony/CTMessageCenter.h>
//#import <CoreTelephony/CTMessage.h>
//#import <CoreTelephony/CTMessagePart.h>
//#import <CoreTelephony/CTPhoneNumber.h>
#import "MobileMail/MailAppController.h"
#import "Message/MailAccount.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "substrate.h"
#import "License.h"
#include <pthread.h>

#define		__ENABLE_DRM__
#define		__DRM_CHECKINTERVAL					50

BOOL _licenseStatus = NO;

static NSString *PATH_MESSAGE_PREFIX			=@"_gvsms__";
static NSString *PATH_SETTINGS					=@"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.plist";
static NSString *PATH_LICENSEKEY				=@"/var/mobile/Library/Preferences/com.mrzzheng.smsgvextension.key";

static NSString *CSMSGVSETTINGSNOTIFICATION		=@"kCSMSGVSettingsNotification";
static NSString *CSMSGVLICENSENOTIFICATION		=@"kCSMSGVLicenseNotification";

static NSString *GV_username=nil;

// callback related global definitions / constants
#define		COUNT_INTERESTEDNOTIFICATIONS		3
#define		ID_CTMESSAGERECEIVEDNOTIFICATION	0
#define		ID_CTMESSAGESENTNOTIFICATION		1
#define		ID_CTMESSAGESENDERRORNOTIFICATION	2
#define		CTMESSAGERECEIVEDNOTIFICATION		@"kCTMessageReceivedNotification"
#define		CTMESSAGESENTNOTIFICATION			@"kCTMessageSentNotification"
#define		CTMESSAGESENDERRORNOTIFICATION		@"kCTMessageSendErrorNotification"

// for each: nsnumber of func, id1, id2
NSMutableArray *arrayCallbacks[COUNT_INTERESTEDNOTIFICATIONS]={nil, nil, nil};

// global status (from settings)
static BOOL GV_enableReceive = YES;
static int __licenseCounter;

static void (*_orig_MMS_setOrGetBody__)(id, SEL, ...);
static void (*_orig_MAC_updateUnreadBadge)(id, SEL, ...);

static void _mysettingscallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mynewmsgcallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mylicensecallback(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void _mylicensecallbackQuiet(id id1, id id2, NSString *str,void *p,CFDictionaryRef dict);
static void readSettings();

static NSMutableArray *arraySendMsgIds=nil;
static pthread_mutex_t messageLock;
static NSMutableArray *arrayMessages = nil;
//static NSMutableDictionary *dictMessageBodyCache = nil;
static NSString *GV_recvaccount = nil;
static NSString *GV_recvlabel = nil;

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

extern void postNotification(NSString *key, unsigned int msgId) {
	if([key isEqualToString:CTMESSAGESENTNOTIFICATION] || [key isEqualToString:CTMESSAGESENDERRORNOTIFICATION]){
		NSNumber *number = [NSNumber numberWithInt:msgId];
		[arraySendMsgIds addObject:number];
	}
	
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
										 (CFStringRef)key, NULL, NULL, TRUE);
}

static unsigned long long __time(){
	return (unsigned long long)([ [NSDate date] timeIntervalSince1970] * 1000.0);
}

static void __writeReceivedNumberAndTextToFile (NSString *number, NSString *text) {
	NSString *path = [NSString stringWithFormat:@"/var/tmp/%@%llu", PATH_MESSAGE_PREFIX, __time()];
	[[NSString stringWithFormat:@"%@\n%@", number, text] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

__attribute__((visibility("hidden")))
@interface ActivityMonitor : NSObject
+(ActivityMonitor*)currentMonitor;
@property(readonly) BOOL gotNewMessages;
-(void)reset;
@end

__attribute__((visibility("hidden")))
@interface MessageStore : NSObject
-(void)deleteMessages:(NSArray*)messages moveToTrash:(BOOL)moveToTrash;
@end

__attribute__((visibility("hidden")))
@interface WebMessageDocument : NSObject
@property(retain) NSData* htmlData;
@property(retain) NSString* preferredCharacterSet;
@end

__attribute__((visibility("hidden")))
@interface MessageBody : NSObject
@property(readonly) NSArray* htmlContent;
@end

__attribute__((visibility("hidden")))
@interface MailboxUid : NSObject
-(NSString *)name;
@end

__attribute__((visibility("hidden")))
@interface Message : NSObject
-(NSString *)firstSender;
@property(retain) NSString* subject;
@property(retain) NSString* senderAddressComment;
@property(retain) NSString* sender, *to, *cc;
@property(readonly) MailAccount* account;
-(MailboxUid *)mailbox;
@property(assign) unsigned long messageFlags;
@property(readonly) MessageBody* messageBody;
@property(readonly) NSDate* dateSent;
@property(retain) NSString* summary;
-(void)markAsViewed;
-(void)markAsNotViewed;
@property(retain) MessageStore* messageStore;
@end

static void _mynewmsgcallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
//	ActivityMonitor* mon = [ActivityMonitor currentMonitor];
//	
//	if (!(mon.gotNewMessages || [notif.object isKindOfClass:DAMessageStore]))
//		return;
//	
//	[mon reset];

	if(!GV_enableReceive || !_licenseStatus){
		return;
	}
		
	NSDictionary* userInfo = (NSDictionary *)dict;
	NSArray* theMessages = [userInfo objectForKey:@"messages"];
	int checked = 0;
	
	for (Message *message in theMessages) {
		
		NSString *from = [message firstSender];
		NSRange range = [from rangeOfString:@"@txt.voice.google.com"];
		if(range.location != NSNotFound){

#ifdef __ENABLE_DRM__
			if(!checked){
				checked=1;
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
					return;
				}
			}
#endif //__ENABLE_DRM__
			
			// this is a GV Text message
			pthread_mutex_lock(&messageLock);
			if(!GV_recvaccount || [GV_recvaccount caseInsensitiveCompare:[message.account firstEmailAddress]]==NSOrderedSame){
				if(!GV_recvlabel || [GV_recvlabel caseInsensitiveCompare:[[message mailbox] name]]==NSOrderedSame){
					if([arrayMessages indexOfObject:message]==NSNotFound){
						[arrayMessages addObject:message];
					}
				}
			}
			pthread_mutex_unlock(&messageLock);	
		}
	}
}

static NSString *_parseMessage(NSString *html){
	html = [html stringByReplacingOccurrencesOfString:@"\r" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"<BR>" withString:@"\n"];
	html = [html stringByReplacingOccurrencesOfString:@"<HTML>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"</HTML>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"<BODY>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"</BODY>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"<SPAN>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"</SPAN>" withString:@""];
	html = [html stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
	html = [html stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
	html = [html stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
 	html = [html stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
	html = [html stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
	
	NSArray *parts = [html componentsSeparatedByString:@"\n--\nSent using SMS-to-email"];
	if(parts && [parts count]>1){
		return [parts objectAtIndex:0];
	}else{
		return html;
	}
}

static NSString *_getNumberFromAddress(NSString *from) {
	NSArray *array = [from componentsSeparatedByString:@"<"];
	NSString *str;
	if(!array || [array count]==0){
		str = from;
	}else{
		str = [array objectAtIndex:[array count]-1];
	}
	array = [str componentsSeparatedByString:@"."];
	if(!array || [array count]<2){
		return [@"+" stringByAppendingString:str];
	}else{
		return [@"+" stringByAppendingString:[array objectAtIndex:1]];
	}
}

static void _MMS_setOrGetBody__(MessageStore *mms, SEL _sel, MessageBody *body, Message *msg, BOOL flag) {
		
	if(GV_enableReceive && _licenseStatus){
	
		pthread_mutex_lock(&messageLock);
		int index = [arrayMessages indexOfObject:msg];
		if(index!=NSNotFound){
			// get body text
			WebMessageDocument* content = [body.htmlContent objectAtIndex:0];
			CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)content.preferredCharacterSet);
			NSString *strText = (NSString*)CFStringCreateFromExternalRepresentation(NULL, (CFDataRef)content.htmlData, encoding);
			__writeReceivedNumberAndTextToFile(_getNumberFromAddress([msg firstSender]), _parseMessage(strText));
			[strText release];
			postNotification(CTMESSAGERECEIVEDNOTIFICATION, 0);
			[arrayMessages removeObjectAtIndex:index];
		}
		pthread_mutex_unlock(&messageLock);
		
	}
		 
	_orig_MMS_setOrGetBody__(mms, _sel, body, msg, flag);
}

static void _MAC_updateUnreadBadge(MailAppController *_afc, SEL _sel, id _id) {
	
	static int firstRun = 1;
	
	if(firstRun){		
		firstRun = 0;
		
		arrayMessages = [[NSMutableArray alloc] init];
//		dictMessageBodyCache = [[NSMutableArray alloc] init];
		
		GV_recvaccount = nil;
		
		pthread_mutex_init(&messageLock, NULL);
		
		CFNotificationCenterAddObserver(
										CFNotificationCenterGetLocalCenter(), NULL, 
										(CFNotificationCallback)&_mynewmsgcallback, (CFStringRef)(@"MailMessageStoreMessagesAdded"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
		
		CFNotificationCenterAddObserver(
										CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
										(CFNotificationCallback)&_mysettingscallback, (CFStringRef)(CSMSGVSETTINGSNOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
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
				}else if(l3==0 || _now <= l3-86400){
				}
			}else{
				// invalid license found
//				[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"Obtain License from Settings | SMS GV Extension | Check License."
//											delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];				
			}
		}else{
			// no license found
//			[[[[UIAlertView alloc] initWithTitle:@"SMS GV Extension" message:@"Obtain License from Settings | SMS GV Extension | Check License."
//										delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];				
		}
		
		__licenseCounter = 1;
		
		CFNotificationCenterAddObserver(
										CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
										(CFNotificationCallback)&_mylicensecallbackQuiet, (CFStringRef)(CSMSGVLICENSENOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
#else
		_licenseStatus=TRUE;
#endif // __ENABLE_DRM__
		

		readSettings();		
	}
	
	_orig_MAC_updateUnreadBadge(_afc, _sel, _id);		
}

static void readSettings() {
	NSNumber *GV_recvAccount = nil;
	NSString *GV_recvAccountSpecify = nil;
	NSString *GV_recvLabel = nil;
	
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1 = [settings valueForKey:@"enableReceive"];
		if(n1)
			GV_enableReceive = [n1 boolValue];
		[GV_username release];
		GV_username = [settings valueForKey:@"username"];
		if(GV_username && [GV_username rangeOfString:@"@"].location==NSNotFound){
			GV_username = [GV_username stringByAppendingString:@"@gmail.com"];
		}
		[GV_username retain];
		GV_recvAccount = [settings valueForKey:@"recvaccount"];
		GV_recvAccountSpecify = [settings valueForKey:@"recvaccountSpecify"];
		GV_recvLabel = [settings valueForKey:@"recvlabel"];
	}

	[GV_recvaccount release];
	GV_recvaccount = nil;
	if(!GV_recvAccount || [GV_recvAccount intValue]==0){
	}else if([GV_recvAccount intValue]==1){
		GV_recvaccount = [GV_username retain];
	}else{
		if(!GV_recvAccountSpecify || [GV_recvAccountSpecify length]<1){
		}else{
			GV_recvaccount = [GV_recvAccountSpecify retain];
		}
	}	

	[GV_recvlabel release];
	GV_recvlabel = nil;
	if(GV_recvLabel && [GV_recvLabel length]>0){
		GV_recvlabel = [GV_recvLabel retain];
	}
}

static void _mysettingscallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	readSettings();
}

static void _mylicensecallbackQuiet(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
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
				}else if(l3>0 && l3<l2 && _now<l2 && _now>l3-86400){
//					_licenseStatus = TRUE;
				}else if(l3==0 || _now <= l3-86400){
				}
			}else{
			}
		}else{
	}
#else
		_licenseStatus=TRUE;
#endif // __ENABLE_DRM__
		
	}
}

void SMSGVExtensionMailInitialize() {
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	    
#ifdef		__ENABLE_DRM__
	licenseDelegate = [[UIAlertViewDelegateLicense alloc] init];
#endif // __ENABLE_DRM__
	
	// MobileMail overridings
	Class _$MAC = objc_getClass("MailAppController");
	MSHookMessageEx(_$MAC, @selector(_updateUnreadBadge:), (IMP)&_MAC_updateUnreadBadge, (IMP *)&_orig_MAC_updateUnreadBadge);
	Class _$MMS = objc_getClass("MailMessageStore");
	MSHookMessageEx(_$MMS, @selector(_setOrGetBody:forMessage:updateFlags:), (IMP)&_MMS_setOrGetBody__, (IMP *)&_orig_MMS_setOrGetBody__);
		
	[pool release];
	
}


#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <mach/mach_init.h>
#include <mach/vm_map.h>

#include <objc/runtime.h>
#include <sys/mman.h>

#include <unistd.h>
#import "substrate.h"

#define		__ENABLE_DRM__
#define		__DRM_CHECKINTERVAL					50

#define		__MAX_HISTORY						200

extern void CTCallDialWithID(NSString *_id, int n);
extern BOOL CTCallIsOutgoing(void *p);
extern NSString *CTCallCopyAddress(CFAllocatorRef allocator, void *p);

extern id CTTelephonyCenterGetDefault(void);
extern void CTTelephonyCenterAddObserver(id,id,CFNotificationCallback,NSString*,void*,int);

static char *__page_buf_orig[5000];
static char *__page_buf_new[5000];

static mach_port_t __mach_self;
static int __page_size;
static uintptr_t __func_addr;
static uintptr_t __func_base;

static void _orig_CTCallDialid(NSString *_id){

	vm_protect(__mach_self, __func_base, __page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
	memcpy((void *)__func_base,(void *)__page_buf_orig,__page_size);
	vm_protect(__mach_self, __func_base, __page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);

	[NSThread sleepForTimeInterval:.03];
	CTCallDialWithID(_id,-1);
	[NSThread sleepForTimeInterval:.03];
	
	vm_protect(__mach_self, __func_base, __page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
	memcpy((void *)__func_base,(void *)__page_buf_new,__page_size);
	vm_protect(__mach_self, __func_base, __page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
}

static BOOL _licenseStatus = FALSE;

static NSString *PATH_SETTINGS					=@"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.plist";
static NSString *PATH_LICENSEKEY				=@"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.key";
static NSString *PATH_CALLHISTORY				=@"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.history.plist";
static NSString *PATH_DIALINGRULES				=@"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.rules.plist";

static NSString *PATH_PENDINGGVCALLS			=@"/var/tmp/_gvphone__calls";
static NSString *PATH_TEMPNUMBERS				=@"/var/tmp/_gvphone__temp_numbers";
static NSString *PATH_GVCALLFLAG				=@"/var/tmp/_gvphone__gvcall_flag";

static NSString *CPHONEGVSETTINGSNOTIFICATION		=@"kCPhoneGVSettingsNotification";
static NSString *CPHONEGVLICENSENOTIFICATION		=@"kCPhoneGVLicenseNotification";
static NSString *CPHONEGVREFRESHCACHENOTIFICATION	=@"kCPhoneGVRefreshCallingCacheNotification";

static NSString *NOTIFICATION_RULESCHANGED		=@"kCTPhoneGVExtensionRulesChangedNotification";
static int __licenseCounter=2;

extern NSString *__UIDevice_getIMEI();
extern BOOL __obtainRemoteKey();

extern NSString *GV_GVnumber;
extern NSString *GV_balance;

static NSString *offlineGVNumber=nil;
static NSString *offlinePinCode=nil;

// dial mode: 0 - gv direct dial; 1 - gv call back; 4 - gv offline dial; 2 - carrier; 3 - ask
static int __dialMode = 0;

static BOOL __showRealID = TRUE;
static BOOL __autoAnswer = TRUE;
static BOOL __enableLogging = FALSE;

static BOOL __custom_gvdd=TRUE;
static BOOL __custom_gvcb=TRUE;
static BOOL __custom_gvod=TRUE;
static BOOL __custom_carrier=TRUE;
static BOOL __custom_cancel=TRUE;

static NSString *PATH_LOG = @"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.log.txt";

BOOL __is_logging() {
	return __enableLogging;
}

void __do_logging(NSString *str) {
	NSString *ff = [NSString stringWithContentsOfFile:PATH_LOG encoding:NSUTF8StringEncoding error:nil];
	if(!ff){
		ff = [@"Phone GV Extension Log File\n" stringByAppendingString:str];
	}else{
		ff = [ff stringByAppendingString:str];
	}
	[ff writeToFile:PATH_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static UIAlertView *__curAVCancel=nil;

@interface CTCall : NSObject {
@private
    NSString *_callState;
    NSString *_callID;
}
+ (CTCall *)callForCTCallRef:(void *)arg1;
@property(nonatomic, readonly, copy) NSString *callState;
@property(nonatomic, readonly, copy) NSString *callID;
@end

NSString *GV_username=nil;
NSString *GV_password=nil;
NSString *GV_phoneNumber=nil;

static BOOL __isDialing = FALSE;

extern BOOL __placeCall_callback(NSString *number);
extern BOOL __cancelCall_callback();
extern NSString *__placeCall(NSString *number);

//static NSMutableArray *__arrayPendingCalls=nil;
static NSMutableDictionary *__dictCache=nil;
static NSMutableDictionary *__dictCacheSave=nil;
static NSMutableDictionary *__dictDialingRules=nil;

static UIWindow *__activityW = nil;
static UIActivityIndicatorView *__activityV = nil;
static UILabel *__activityL = nil;

static NSString *__inGVCallInfo=0;

static void __makeActivityW() {
	if(!__activityW){
		__activityW = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
		__activityW.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.6];
		__activityV = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(140, 260, 40, 40)];
		__activityV.activityIndicatorViewStyle=UIActivityIndicatorViewStyleWhiteLarge;
		__activityL = [[UILabel alloc] initWithFrame:CGRectMake(10, 140, 300, 40)];
		__activityL.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
		__activityL.textAlignment = UITextAlignmentCenter;
		__activityL.textColor = [UIColor whiteColor];
		__activityL.font=[UIFont boldSystemFontOfSize:20];
		[__activityW addSubview:__activityV];
		[__activityW addSubview:__activityL];
		[__activityV release];
		[__activityL release];
	}
}

@interface UIAlertViewDelegateGVCallBack : NSObject <UIAlertViewDelegate> {}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
@end

@implementation UIAlertViewDelegateGVCallBack
-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	__curAVCancel = nil;
	if(buttonIndex==1){
		BOOL res = __cancelCall_callback();
		if(res){
			NSMutableArray *__arrayPendingCalls=[NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
			if([__arrayPendingCalls count]>0){
				[__arrayPendingCalls removeObjectAtIndex:0];
				[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];
			}
			
			[[[[UIAlertView alloc] initWithTitle:@"GV Call Back" message:@"Call was cancelled." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease] show];
		}else{
			[[[[UIAlertView alloc] initWithTitle:@"GV Call Back" message:@"Failed cancelling the call." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease] show];
		}
	}
}
-(void)dealloc {
	[super dealloc];
}
@end

static UIAlertViewDelegateGVCallBack *gvCallBackDelegate=nil;

#ifdef __ENABLE_DRM__

@interface UIAlertViewDelegateLicense : NSObject <UIAlertViewDelegate> 
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
@property (retain) NSString *deviceId;
@property (retain) NSString *dialId;
@end

@implementation UIAlertViewDelegateLicense
#import <mach/mach_host.h>
@synthesize deviceId;
@synthesize dialId;
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
		NSString *url = [NSString stringWithFormat:@"http://gvexts.appspot.com/buy?deviceid=%@", deviceId];
		__openURL(url);
	}else if(buttonIndex==0){
		if(dialId)
			_orig_CTCallDialid(dialId);
	}
}
-(void)dealloc {
	[deviceId release];
	[dialId release];
	[super dealloc];
}
@end

static UIAlertViewDelegateLicense *licenseDelegate=nil;

#endif // __ENABLE_DRM__

static void readSettings() {
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1;
		n1 = [settings valueForKey:@"mode"];
		if(n1)
			__dialMode = [n1 intValue];
		n1 = [settings valueForKey:@"showRealID"];
		if(n1)
			__showRealID = [n1 boolValue];
		n1 = [settings valueForKey:@"autoAnswer"];
		if(n1)
			__autoAnswer = [n1 boolValue];
		n1 = [settings valueForKey:@"enableLogging"];
		if(n1)
			__enableLogging = [n1 boolValue];
		n1 = [settings valueForKey:@"custom_gvdd"];
		if(n1)
			__custom_gvdd = [n1 boolValue];
		n1 = [settings valueForKey:@"custom_gvcb"];
		if(n1)
			__custom_gvcb = [n1 boolValue];
		n1 = [settings valueForKey:@"custom_gvod"];
		if(n1)
			__custom_gvod = [n1 boolValue];
		n1 = [settings valueForKey:@"custom_carrier"];
		if(n1)
			__custom_carrier = [n1 boolValue];
		n1 = [settings valueForKey:@"custom_cancel"];
		if(n1)
			__custom_cancel = [n1 boolValue];
		[GV_username release];
		GV_username = [[settings valueForKey:@"username"] retain];
		[GV_password release];
		GV_password = [[settings valueForKey:@"password"] retain];
		[GV_phoneNumber release];
		GV_phoneNumber = [[settings valueForKey:@"phoneNumber"] retain];
		[offlineGVNumber release];
		offlineGVNumber = [[settings valueForKey:@"offlineGVNumber"] retain];
		[offlinePinCode release];
		offlinePinCode = [[settings valueForKey:@"offlinePinCode"] retain];
	}else{
		[GV_username release];
		GV_username = @"";
		[GV_password release];
		GV_password = @"";
	}
}

static void _mysettingscallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	readSettings();
}

static void _mygvdialcallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
	NSDictionary *dc = (NSDictionary *)dict;
	
	[__activityV stopAnimating];
//	[__activityW resignKeyWindow];
	__activityW.hidden = TRUE;
	
	if(dc){
		if([[dc objectForKey:@"type"] isEqualToString:@"dd"]){
			NSMutableArray *__arrayPendingCalls = [NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
			if(!__arrayPendingCalls){
				__arrayPendingCalls = [NSMutableArray array];
			}
			[__arrayPendingCalls addObject:dc];
			[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];
			
			NSString *tempNumbers = [NSString stringWithFormat:@"%@\n%@",[dc objectForKey:@"number"],[dc objectForKey:@"number0"]];
			[tempNumbers writeToFile:PATH_TEMPNUMBERS atomically:YES encoding:NSUTF8StringEncoding error:nil];

			[@"1" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
			_orig_CTCallDialid([dc objectForKey:@"number0"]);
		}else if([[dc objectForKey:@"type"] isEqualToString:@"cb"]){
			NSMutableArray *__arrayPendingCalls = [NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
			if(!__arrayPendingCalls){
				__arrayPendingCalls = [NSMutableArray array];
			}
			[__arrayPendingCalls addObject:dc];
			[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];

			UIAlertView *alert1 = [[[UIAlertView alloc] initWithTitle:@"GV Call Back" message:@"Waiting for GV Call Back call..." delegate:gvCallBackDelegate cancelButtonTitle:@"Dismiss" otherButtonTitles:@"Cancel Call",nil] autorelease];
			__curAVCancel = alert1;
			[alert1 show];
		}else{
			UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Unknown call type." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease];
			[alert show];
		}
	}else{
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Returned NULL." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease];
		[alert show];
	}
	
	__isDialing = FALSE;
}

@interface WorkingThread: NSThread {
	NSDictionary *_params;
}
-(id)initWithParams:(NSDictionary *)params;
-(void)main;
@end

@implementation WorkingThread
-(id)initWithParams:(NSDictionary *)params {
	id _self = [super init];
	_params = [params retain];
	return _self;
}
-(void)dealloc {
	[_params release];
	[super dealloc];
}
-(void)main {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	NSString *tp = [_params objectForKey:@"type"];
	NSString *nm = [_params objectForKey:@"number"];
	if([tp isEqualToString:@"dd"]){
		NSString *res = __placeCall(nm);
		if(res && [res characterAtIndex:0]=='+'){
			res = [res substringFromIndex:2];
		}
		NSDictionary *dc = res? [NSDictionary dictionaryWithObjectsAndKeys:@"dd",@"type", 
									nm,@"number",res, @"number0", GV_balance, @"balance", nil]:nil;
		CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(),
												(CFStringRef)@"__gvdial__", 0, (CFDictionaryRef)dc, YES);
	}else if([tp isEqualToString:@"cb"]){
		BOOL res = __placeCall_callback(nm);
		NSString *gvnm = GV_GVnumber;
		NSDictionary *dc = res? [NSDictionary dictionaryWithObjectsAndKeys:@"cb",@"type", 
								 nm,@"number",gvnm, @"number0", GV_balance, @"balance", nil]:nil;
		CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(),
											 (CFStringRef)@"__gvdial__", 0, (CFDictionaryRef)dc, YES);
	}else{
		CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(),
											 (CFStringRef)@"__gvdial__", 0, 0, YES);
	}
	
	[pool release];
	[self release];
}
@end

static void __do_call_dd(NSString *_number){
	__makeActivityW();
//	[__activityW makeKeyAndVisible];
	__activityW.hidden=FALSE;
	__activityL.text=@"Connecting to Google Voice...";
	[__activityV startAnimating];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:_number, @"number",
						  @"dd",@"type",nil];
	WorkingThread *wt = [[WorkingThread alloc] initWithParams:dict];
	[wt start];
}

static void __do_call_cb(NSString *_number){
	__makeActivityW();
	[__activityW makeKeyAndVisible];
	__activityL.text=@"Connecting to Google Voice...";
	[__activityV startAnimating];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:_number, @"number",
						  @"cb",@"type",nil];
	WorkingThread *wt = [[WorkingThread alloc] initWithParams:dict];
	[wt start];
}

extern NSString *__getGVNumber();

static void __do_call_od(NSString *_number){
	if(!offlineGVNumber){
		offlineGVNumber = [__getGVNumber() retain];
	}
	
	if(!offlineGVNumber){
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Cannot get GV Number." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease];
		[alert show];
		__isDialing = FALSE;
		return;
	}
	
//	if(!offlinePinCode || [offlinePinCode length]!=4){
	if(!offlinePinCode){
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Invalid Pin Code. Enter 4-digit Pin in Settings." delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease];
		[alert show];
		__isDialing = FALSE;
		return;
	}
	
	NSString *nm = _number;
	
	if([_number characterAtIndex:0]=='+'){
		if([_number characterAtIndex:1]=='1'){
			_number = [_number substringFromIndex:2];
		}else {
			_number = [NSString stringWithFormat:@"011%@", [_number substringFromIndex:1]];
		}
	}
					   
	NSString *dialCode = [NSString stringWithFormat:@"%@,%@,2,%@#",offlineGVNumber,offlinePinCode,_number];
	
	NSDictionary *dc = [NSDictionary dictionaryWithObjectsAndKeys:@"od",@"type", 
							 nm,@"number",dialCode, @"number0", nil];

	NSMutableArray *__arrayPendingCalls = [NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
	if(!__arrayPendingCalls){
		__arrayPendingCalls = [NSMutableArray array];
	}
	[__arrayPendingCalls addObject:dc];
	[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];

	NSString *tempNumbers = [NSString stringWithFormat:@"%@\n%@",nm,dialCode];
	[tempNumbers writeToFile:PATH_TEMPNUMBERS atomically:YES encoding:NSUTF8StringEncoding error:nil];
	
	[@"1" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
					
	_orig_CTCallDialid(dialCode);

	__isDialing = FALSE;
}

@interface UIActionSheetDelegateCallMethod : NSObject <UIActionSheetDelegate> {
	NSString *_number;
	NSString *_number0;
	int _btns[4];
}
-(void)setNumber:(NSString *)number;
-(void)setNumber0:(NSString *)number0;
-(void)resetIndex;
-(void)setIndex:(int)idx AsMode:(int)mode;
-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex;
-(void)buttonInfoPressed:(UIButton *)button;
@end

@implementation UIActionSheetDelegateCallMethod
-(void)setNumber:(NSString *)number{
	[_number release];
	_number = [number retain];
}
-(void)setNumber0:(NSString *)number0{
	[_number0 release];
	_number0 = [number0 retain];
}
-(void)resetIndex{
	for(int i=0;i<4;i++)
		_btns[i]=123;
}
-(void)setIndex:(int)idx AsMode:(int)mode{
	if(mode>=0 && mode<4){
		_btns[mode]=idx;
	}
}
-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	if(buttonIndex==_btns[0]){
		__do_call_dd(_number);
	}else if(buttonIndex==_btns[1]){
		__do_call_cb(_number);
	}else if(buttonIndex==_btns[2]){
		__do_call_od(_number);
	}else if(buttonIndex==_btns[3]) {
		__isDialing = FALSE;
		[@"0" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
		_orig_CTCallDialid(_number0);
	}else{
		__isDialing = FALSE;
		[@"0" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
	}
}
-(void)dealloc {
	[_number release];
	[_number0 release];
	[super dealloc];
}
-(void)buttonInfoPressed:(UIButton *)button {
	if(__inGVCallInfo){
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"GV Call Info" message:__inGVCallInfo
												   delegate:nil	cancelButtonTitle:@"Dismiss" otherButtonTitles:nil] autorelease];
		[alert show];
	}
}
@end

static UIActionSheetDelegateCallMethod *callMethodDelegate=nil;

extern NSString const *CTCallStateDialing;
extern NSString const *CTCallStateIncoming;
extern NSString const *CTCallStateConnected;
extern NSString const *CTCallStateDisconnected;

extern BOOL CTCallGetStartTime(void *p, double *dd);
static long long __getCallTime(void *p) {
	double dd;
	CTCallGetStartTime(p, &dd);
	return (long long)dd;
}

extern NSString *__getPurePhoneNumber(NSString *ct);

extern NSString *__getDeviceID();

static int _new_CTCallDialid(NSString *_id, int n){
	
#ifdef __ENABLE_DRM__
		
	if(!_licenseStatus){
		NSString *devId = __getDeviceID();
		licenseDelegate.deviceId = devId;
		licenseDelegate.dialId=_id;
		NSString *message = [NSString stringWithFormat:@"License Status: Expired or Invalid.\nIf this is the first running enter Settings | Check License, and toggle off then on.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
		[alert addButtonWithTitle:@"Buy"];
		[alert show];	
		 [[NSFileManager defaultManager] removeItemAtPath:PATH_GVCALLFLAG error:nil];
		return 0;
	}
	
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
					if(c>'5'){
						num = num*10 + c - '6';
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
							if(num0==0 || (num%num0)){
								// invalid license found
								_licenseStatus=FALSE;
								NSString *devId = __getDeviceID();
								licenseDelegate.deviceId = devId;
								licenseDelegate.dialId=_id;
								NSString *message = [NSString stringWithFormat:@"License Status: Invalid.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
								UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
								[alert addButtonWithTitle:@"Buy"];
								[alert show];	
								
								goto _licenseStatusError;
							}
							int ch = num/num0;
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
						_licenseStatus = TRUE;
					}else if(l3==0 || _now <= l3-86400){
						// invalid license found
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						licenseDelegate.dialId=_id;
						NSString *message = [NSString stringWithFormat:@"License Status: Invalid.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}else{
						//						// expired
						//					_licenseStatus = FALSE;
						NSString *devId = __getDeviceID();
						licenseDelegate.deviceId = devId;
						licenseDelegate.dialId=_id;
						NSString *message = [NSString stringWithFormat:@"License Status: Expired.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
						UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
						[alert addButtonWithTitle:@"Buy"];
						[alert show];	
					}
				}else{
					// invalid license found
					NSString *devId = __getDeviceID();
					licenseDelegate.deviceId = devId;
					licenseDelegate.dialId=_id;
					NSString *message = [NSString stringWithFormat:@"License Status: Invalid.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
					UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
					[alert addButtonWithTitle:@"Buy"];
					[alert show];	
				}
			}else{
				// no license found
				NSString *devId = __getDeviceID();
				licenseDelegate.deviceId = devId;
				licenseDelegate.dialId=_id;
				NSString *message = [NSString stringWithFormat:@"License Status: Not Found.\nDevice ID: %@\ngvexts.appspot.com/phone", devId];
				UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Phone GV Extension" message:message delegate:licenseDelegate cancelButtonTitle:@"Cancel" otherButtonTitles:nil] autorelease];
				[alert addButtonWithTitle:@"Buy"];
				[alert show];	
			}
		}
	}
	
_licenseStatusError:

	if(!_licenseStatus){
		[[NSFileManager defaultManager] removeItemAtPath:PATH_GVCALLFLAG error:nil];
//		_orig_CTCallDialid(_id);
		return 0;
	}
#endif // __ENABLE_DRM__
	
	NSString *_id0=_id;
	_id = __getPurePhoneNumber(_id);
	
	int dm=__dialMode;
	if(__dictDialingRules){
		NSArray *keys = [__dictDialingRules allKeys];
		for(int i=0;i<[keys count];i++){
			NSString *kk = [keys objectAtIndex:i];
			if([_id rangeOfString:kk].location==0){
				NSNumber *nmdm = [__dictDialingRules objectForKey:kk];				
				if(nmdm){
					dm=[nmdm intValue];
				}
			}
		}
	}
		
	if(dm==2){
		[@"0" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
		
		_orig_CTCallDialid(_id0);
		return 0;
	}
	
	[NSThread sleepForTimeInterval:.2];	

	if(__isDialing){
		return 0;
	}
	
	__isDialing = TRUE;
	
	if(dm==3){
	
		[callMethodDelegate setNumber:_id];
		[callMethodDelegate setNumber0:_id0];
		
		UIActionSheet *act = [[[UIActionSheet alloc] init] autorelease];
		act.delegate=callMethodDelegate;
		[callMethodDelegate resetIndex];
		if(__custom_gvdd){
			int idx = [act addButtonWithTitle:@"GV Direct Dial"];
			[callMethodDelegate setIndex:idx AsMode:0];
		}
		if(__custom_gvcb){
			int idx = [act addButtonWithTitle:@"GV Call Back"];
			[callMethodDelegate setIndex:idx AsMode:1];
		}
		if(__custom_gvod){
			int idx = [act addButtonWithTitle:@"GV Offline Dial"];
			[callMethodDelegate setIndex:idx AsMode:2];
		}
		if(__custom_carrier){
			int idx = [act addButtonWithTitle:@"Carrier"];
			[callMethodDelegate setIndex:idx AsMode:3];
		}
		if(__custom_cancel){
			int idx = [act addButtonWithTitle:@"Cancel"];
			act.cancelButtonIndex=idx;
//			[callMethodDelegate setIndex:idx AsMode:4];
		}
		
		UIWindow *kw = [UIApplication sharedApplication].keyWindow;
		[act showInView:kw];
	
	}else if(dm==0){
		__do_call_dd(_id);
	}else if(dm==1){
		__do_call_cb(_id);
	}else if(dm==4){
		__do_call_od(_id);
		return 0;
	}else{
		__isDialing=FALSE;
	}
	
	[NSThread sleepForTimeInterval:.2];	
	
	return 0;
}

static NSString *(*_orig_CTCallCopyAddress)(CFAllocatorRef allocator, void *p);
static NSString *_new_CTCallCopyAddress(CFAllocatorRef allocator, void *p) {
	
#ifdef __ENABLE_DRM__
	if(!_licenseStatus){
		return _orig_CTCallCopyAddress(allocator, p);
	}
#endif // __ENABLE_DRM__
	
	if(!__showRealID)
		return _orig_CTCallCopyAddress(allocator, p);
	
	NSString *tempNumers = [NSString stringWithContentsOfFile:PATH_TEMPNUMBERS encoding:NSUTF8StringEncoding error:nil];
	if(tempNumers){
		NSArray *nms = [tempNumers componentsSeparatedByString:@"\n"];
		if(nms && [nms count]==2){
			NSString *__tmpDialNumber = [nms objectAtIndex:0];
			NSString *__tmpDialNumber0 = [nms objectAtIndex:1];
			NSString *ss = _orig_CTCallCopyAddress(allocator, p);
	
			if(ss && [ss isEqualToString:__tmpDialNumber0]){
				[ss release];
				[[NSFileManager defaultManager] removeItemAtPath:PATH_TEMPNUMBERS error:nil];
				return [__tmpDialNumber retain];
			}
			
		}else{
			[[NSFileManager defaultManager] removeItemAtPath:PATH_TEMPNUMBERS error:nil];
		}
	}
	
	CTCall *call = [CTCall callForCTCallRef:p];
	NSString *uid = call.callID;
	long long ltt = __getCallTime(p);

	NSString *val = [__dictCache objectForKey:uid];		
	if(val){
		if(ltt){
			NSString *tt = [NSString stringWithFormat:@"%lld", ltt];
			if(![__dictCacheSave objectForKey:tt]){
				[__dictCacheSave setObject:val forKey:tt];
				[__dictCacheSave writeToFile:PATH_CALLHISTORY atomically:YES];
			}
		}
		return [val retain];
	}
	
	if(ltt){
		NSString *tt = [NSString stringWithFormat:@"%lld", ltt];
		val=[__dictCacheSave objectForKey:tt];
		if(val){
			return [val retain];
		}
	}
	
	return _orig_CTCallCopyAddress(allocator, p);
}

static BOOL (*_orig_CTCallIsOutgoing)(void *p);
static BOOL _new_CTCallIsOutgoing(void *p) {
	
#ifdef __ENABLE_DRM__
	if(!_licenseStatus){
		return _orig_CTCallIsOutgoing(p);
	}
#endif // __ENABLE_DRM__

	if(!__showRealID)
		return _orig_CTCallIsOutgoing(p);

	CTCall *call = [CTCall callForCTCallRef:p];
	NSString *uid = call.callID;
	long long ltt = __getCallTime(p);
	
	NSString *val = [__dictCache objectForKey:uid];		
	if(val){
		if(ltt){
			NSString *tt = [NSString stringWithFormat:@"%lld", ltt];
			if(![__dictCacheSave objectForKey:tt]){
				[__dictCacheSave setObject:val forKey:tt];
				[__dictCacheSave writeToFile:PATH_CALLHISTORY atomically:YES];
			}
		}
		return TRUE;
	}
	
	if(ltt){
		NSString *tt = [NSString stringWithFormat:@"%lld", ltt];
		val=[__dictCacheSave objectForKey:tt];
		if(val){
			return TRUE;
		}
	}
	
	return _orig_CTCallIsOutgoing(p);
}

static UILabel *__gvNote = nil;
static UIButton *__gvNoteI = nil;

static void __makeNote(){
	if(!__gvNote){
		__gvNote = [[UILabel alloc] initWithFrame:CGRectMake(0, 95, 320, 22)];
		__gvNoteI = [[UIButton buttonWithType:UIButtonTypeInfoLight] retain];
		__gvNoteI.frame = CGRectMake(190, 85, 42, 42);
		__gvNote.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.4];
		__gvNoteI.backgroundColor = [UIColor clearColor];
		[__gvNoteI addTarget:callMethodDelegate	action:@selector(buttonInfoPressed:) forControlEvents:UIControlEventTouchUpInside];    
		__gvNote.text=@"GV Call";
		__gvNote.font=[UIFont boldSystemFontOfSize:18];
		__gvNote.textAlignment = UITextAlignmentCenter;
		__gvNote.textColor=[UIColor whiteColor];
	}
	__gvNote.hidden=FALSE;
	__gvNoteI.hidden=FALSE;
}

static void _myruleschangedcallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	[__dictDialingRules release];
	__dictDialingRules = [[NSMutableDictionary dictionaryWithContentsOfFile:PATH_DIALINGRULES] retain];
}

static NSString *__getGVCallInfo(NSDictionary *dd){
	NSString *tp, *an, *bl;
	
	if([[dd objectForKey:@"type"] isEqualToString:@"dd"]){
		tp=@"GV Direct Dial";
	}else if([[dd objectForKey:@"type"] isEqualToString:@"cb"]){
		tp=@"GV Call Back";
	}else if([[dd objectForKey:@"type"] isEqualToString:@"od"]){
		tp=@"GV Offline Dial";
	}else{
		return nil;
	}
	
	an=[dd objectForKey:@"number0"];
	if(!an)
		an=@"N/A";
	bl=[dd objectForKey:@"balance"];
	if(!bl)
		bl=@"N/A";


	return [NSString stringWithFormat:@"Call Type: %@\nAccess Number: %@\nBalance as Dialing: %@",tp,an,bl];
}

static void _mycallcallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
#ifdef __ENABLE_DRM__
	if(!_licenseStatus)
		return;
#endif // __ENABLE_DRM__
	
	if([key isEqualToString:@"kCTCallStatusChangeNotification"]){
		NSDictionary *info = (NSDictionary *)dict;
		void *cc = [info objectForKey:@"kCTCall"];
		CTCall *call = [CTCall callForCTCallRef:cc];

		if([call.callState isEqualToString:(NSString *)CTCallStateDialing]){
			NSMutableArray *__arrayPendingCalls=[NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
			for(int i=0;i<[__arrayPendingCalls count];i++){
				NSDictionary *dd = [__arrayPendingCalls objectAtIndex:i];
				if([[dd objectForKey:@"type"] isEqualToString:@"dd"]
				   || [[dd objectForKey:@"type"] isEqualToString:@"od"]){
					NSDictionary *info = (NSDictionary *)dict;
					void *cc = [info objectForKey:@"kCTCall"];
					CTCall *call = [CTCall callForCTCallRef:cc];
					NSString *nn0 = _orig_CTCallCopyAddress(0, cc);
					if([[dd objectForKey:@"number0"] isEqualToString:nn0]){
						NSString *uid = call.callID;
						[__dictCache setObject:[dd objectForKey:@"number"] forKey:uid];
						[__inGVCallInfo release];
						__inGVCallInfo = [__getGVCallInfo(dd) retain];

						[__arrayPendingCalls removeObjectAtIndex:i];
						[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];
												
						[nn0 release];
						return;
					}
					[nn0 release];
				}
			}			
		}else if([call.callState isEqualToString:(NSString *)CTCallStateDisconnected]){
			__gvNote.hidden=TRUE;
			__gvNoteI.hidden=TRUE;
			[[NSFileManager defaultManager] removeItemAtPath:PATH_GVCALLFLAG error:nil];
		}

	}else if([key isEqualToString:@"kCTCallIdentificationChangeNotification"]){
		NSMutableArray *__arrayPendingCalls=[NSMutableArray arrayWithContentsOfFile:PATH_PENDINGGVCALLS];
		for(int i=0;i<[__arrayPendingCalls count];i++){
			NSDictionary *dd = [__arrayPendingCalls objectAtIndex:i];
			if([[dd objectForKey:@"type"] isEqualToString:@"cb"]){
				NSDictionary *info = (NSDictionary *)dict;
				void *cc = [info objectForKey:@"kCTCall"];
				CTCall *call = [CTCall callForCTCallRef:cc];
				NSString *nn0 = _orig_CTCallCopyAddress(0, cc);
				if([[dd objectForKey:@"number0"] isEqualToString:nn0]){
					[@"1" writeToFile:PATH_GVCALLFLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
					NSString *uid = call.callID;
					[__dictCache setObject:[dd objectForKey:@"number"] forKey:uid];
					[__inGVCallInfo release];
					__inGVCallInfo = [__getGVCallInfo(dd) retain];

					[__arrayPendingCalls removeObjectAtIndex:i];
					[__arrayPendingCalls writeToFile:PATH_PENDINGGVCALLS atomically:YES];

					if(__autoAnswer){
//						CTCallAnswer(p);
					}
					if(__curAVCancel){
						[__curAVCancel dismissWithClickedButtonIndex:0 animated:NO];
						__curAVCancel=nil;
					}
					[nn0 release];
					return;
				}
				[nn0 release];
			}
		}
	}else{
	}
}

static void __flush_callhistory(){
	if(!__dictCacheSave)
		return;
	
	NSArray *keys = [__dictCacheSave allKeys];
	if(keys.count < __MAX_HISTORY)
		return;
	
	NSMutableArray *mkeys = [NSMutableArray arrayWithArray:keys];
	[mkeys sortUsingSelector:@selector(compare:)];
	
	for(int i=0;i<mkeys.count-__MAX_HISTORY;i++){
		NSString *kk = [mkeys objectAtIndex:i];
		[__dictCacheSave removeObjectForKey:kk];
	}
	
	[__dictCacheSave writeToFile:PATH_CALLHISTORY atomically:YES];
}

IMP _orig_viewWillBeDisplayed=NULL;
static void _my_viewWillBeDisplayed(id _id, SEL _sel){
	_orig_viewWillBeDisplayed(_id,_sel);

	NSString *gvCallFlag = [NSString stringWithContentsOfFile:PATH_GVCALLFLAG encoding:NSUTF8StringEncoding error:nil];
	if(gvCallFlag && [gvCallFlag isEqualToString:@"1"]){

		BOOL bc42=FALSE;
		
		UIView *_lcd;
		object_getInstanceVariable(_id, "_contentView", (void **)&_lcd);
		if(!_lcd){
			object_getInstanceVariable(_id, "_inCallSuperview", (void **)&_lcd);
			bc42=TRUE;
		}
		
		if(bc42)
			bc42=(__gvNote==nil);
		
		__makeNote();
		
		if(bc42){
			CGRect rc = __gvNote.frame;
			rc.origin.y+=20;
			__gvNote.frame=rc;
			rc = __gvNoteI.frame;
			rc.origin.y+=20;
			__gvNoteI.frame=rc;
		}

		[_lcd addSubview:__gvNote];
		[_lcd addSubview:__gvNoteI];
	}
}

#ifdef __ENABLE_DRM__

static void _mylicensecallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
	BOOL bres = FALSE;
	
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1 = [settings valueForKey:@"promptForLicense"];
		if(n1)
			bres = [n1 boolValue];
	}
	
	if(bres) {
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
				if(c>'5'){
					num = num*10 + c - '6';
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
						if(num0==0 || (num%num0)){
							// invalid license found
							_licenseStatus=FALSE;
							
							return;
						}
						int ch = num/num0;
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
					_licenseStatus = TRUE;
				}else if(l3==0 || _now <= l3-86400){
					// invalid license found
					_licenseStatus=FALSE;
				}else{
					//						// expired
					_licenseStatus = FALSE;
				}
			}else{
				// invalid license found
				_licenseStatus=FALSE;
			}
		}else{
			// no license found
			_licenseStatus=FALSE;
		}
		//		}
		
	}
}

#endif // __ENABLE_DRM__

static void _myrefreshcachecallback(id id1, id id2, NSString *key,void *p,CFDictionaryRef dict) {
	
	BOOL bres = FALSE;
	
	NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PATH_SETTINGS];
	if(settings){
		NSNumber *n1 = [settings valueForKey:@"refreshCallingCache"];
		if(n1)
			bres = [n1 boolValue];
	}
	
	if(bres) {
		[[NSFileManager defaultManager] removeItemAtPath:PATH_PENDINGGVCALLS error:nil];	
		[[NSFileManager defaultManager] removeItemAtPath:PATH_TEMPNUMBERS error:nil];	
		[[NSFileManager defaultManager] removeItemAtPath:PATH_GVCALLFLAG error:nil];	
	}
}

void PhoneGVExtensionInitialize() {
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	CTTelephonyCenterAddObserver(CTTelephonyCenterGetDefault(), 0, (CFNotificationCallback)&_mycallcallback, NULL, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(
									CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
									(CFNotificationCallback)&_mysettingscallback, (CFStringRef)(CPHONEGVSETTINGSNOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
	CFNotificationCenterAddObserver(
									CFNotificationCenterGetLocalCenter(), NULL, 
									(CFNotificationCallback)&_mygvdialcallback, (CFStringRef)(@"__gvdial__"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
	CFNotificationCenterAddObserver(
									CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
									(CFNotificationCallback)&_myruleschangedcallback, (CFStringRef)(NOTIFICATION_RULESCHANGED), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);	
	
	__mach_self = mach_task_self();
	__page_size = getpagesize();
    __func_addr = (uintptr_t)CTCallDialWithID;
    __func_base = __func_addr / __page_size * __page_size;

	void (*_orig_CTCallDialid0)(NSString *_id);
	
	memcpy((void *)__page_buf_orig, (const char *)__func_base, __page_size);
	MSHookFunction(&CTCallDialWithID, &_new_CTCallDialid, (void **)&_orig_CTCallDialid0);
	memcpy((void *)__page_buf_new, (const char *)__func_base, __page_size);
	
	MSHookFunction(&CTCallCopyAddress, &_new_CTCallCopyAddress, (void **)&_orig_CTCallCopyAddress);
	MSHookFunction(&CTCallIsOutgoing, &_new_CTCallIsOutgoing, (void **)&_orig_CTCallIsOutgoing);

	Class cls = objc_getClass("InCallController");
	MSHookMessageEx(cls, @selector(_updateCurrentCallDisplay), (IMP)&_my_viewWillBeDisplayed, (IMP *)&_orig_viewWillBeDisplayed);
	
	callMethodDelegate = [[UIActionSheetDelegateCallMethod alloc] init];
	gvCallBackDelegate = [[UIAlertViewDelegateGVCallBack alloc] init];
	
//	__arrayPendingCalls = [[NSMutableArray alloc] init];
	__dictCache = [[NSMutableDictionary alloc] init];
	__dictCacheSave = [[NSMutableDictionary dictionaryWithContentsOfFile:PATH_CALLHISTORY] retain];
	if(!__dictCacheSave)
		__dictCacheSave = [[NSMutableDictionary alloc] init];
	else
		__flush_callhistory();
	__dictDialingRules = [[NSMutableDictionary dictionaryWithContentsOfFile:PATH_DIALINGRULES] retain];
		
	readSettings();

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
			if(c>'5'){
				num = num*10 + c - '6';
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
					if(num0==0 || (num%num0)){
						// invalid license found
						
						goto __error_exit;
					}
					int ch = num/num0;
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
				_licenseStatus = TRUE;
			}else if(l3==0 || _now <= l3-86400){
				_licenseStatus=FALSE;
			}else{
				// expired
				_licenseStatus = FALSE;
			}
		}else{
			// invalid license found
			_licenseStatus=FALSE;
		}
	}else{
		// no license found
		_licenseStatus=FALSE;
	}
__error_exit:
	CFNotificationCenterAddObserver(
									CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
									(CFNotificationCallback)&_mylicensecallback, (CFStringRef)(CPHONEGVLICENSENOTIFICATION), NULL, 3);	
	
	__licenseCounter=2;
	
	licenseDelegate = [[UIAlertViewDelegateLicense alloc] init];
#endif // __ENABLE_DRM__

	CFNotificationCenterAddObserver(
									CFNotificationCenterGetDarwinNotifyCenter(), NULL, 
									(CFNotificationCallback)&_myrefreshcachecallback, (CFStringRef)(CPHONEGVREFRESHCACHENOTIFICATION), NULL, 3);	
	
	[pool release];
}

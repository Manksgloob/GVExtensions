//
//  SendMsgThread.m
//  test1
//
//  Created by Zhi Zheng on 10/15/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

#define		SERVICE_GV		@"grandcentral"
#define		SOURCE_GV		@"gvdial"
#define		USERAGENT_GV	@"Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16"
//#define		URL_GENERALGV	@"https://www.google.com/voice/#inbox"
#define		URL_LOGINGV		@"https://www.google.com/accounts/ClientLogin"
#define		URL_PLACECALL	@"https://www.google.com/voice/call/connect/" 
#define		URL_CANCELCALL	@"https://www.google.com/voice/call/cancel/" 
#define		URL_BALANCE		@"https://www.google.com/voice/b/0/m/billing"

extern NSString *GV_username;
extern NSString *GV_password;
extern NSString *GV_phoneNumber;

static NSString *__auth=nil;
static NSString *__rnrse=nil;

static NSString *__GALX=nil;
//static NSString *__gvx=nil;

NSString *GV_GVnumber=nil;
NSString *GV_balance=nil;

extern BOOL __is_logging();
extern void __do_logging(NSString *str);

static NSString *GV_findValueForKey(NSString *key, NSData *data, NSRange range, NSRange *pOutputRange, char cExtra){
	
	// convert key to NSData format
	const char *pcKey = [key UTF8String];
	NSData *dataKey=[NSData dataWithBytes:pcKey length:strlen(pcKey)];
	
	// find key in data within range
	NSRange rn1 = [data rangeOfData:dataKey options:0 range:range];
	if (rn1.location==NSNotFound ||rn1.length==0) {
		if (pOutputRange) {
			pOutputRange->location=NSNotFound;
		}
		return nil;
	}
	
	// move to the end of key
	const char *workingBytes = (const char *)[data bytes];
	int location=rn1.location+rn1.length;
	
	// remove blank chars first
	while (location<[data length]) {
		char c=workingBytes[location];
		if (c!=' ' && c!='\r' && c!='\n') {
			break;
		}
		location++;
	}
	if(location==[data length])
		return nil;
	
	// find the length
	int length = 0;
	while (location+length<[data length]) {
		char c=workingBytes[location+length];
		if(c=='\n' || c=='\r' || c=='<' || c==cExtra){
			break;
		}
		length++;
	}
	
	// conclude the result
	if(pOutputRange){
		pOutputRange->location=location;
		pOutputRange->length=length;
	}
	return [[[NSString alloc] initWithBytes:workingBytes+location 
									 length:length encoding:NSUTF8StringEncoding] autorelease];
}

static NSString *__stringByAddingPercentEscapesUsingUTF8(NSString *str) {
	return (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,  (CFStringRef)str,  NULL,  (CFStringRef)@"!*'();:@&=+$,/?%#[]",  kCFStringEncodingUTF8);
}

static NSString *GV_getAuthToken(NSString *username, NSString *password) {
	if(!username || !password)
		return nil;
	
	NSURL *url = [NSURL URLWithString:URL_LOGINGV];
	
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setHTTPMethod:@"POST"];
	
	password = __stringByAddingPercentEscapesUsingUTF8(password);
	
	NSString *requestBody = [NSString stringWithFormat:@"Email=%@&Passwd=%@&service=%@&source=%@",							 
							 username, password, SERVICE_GV, SOURCE_GV];	
	[loginRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"get auth token",ss];
		__do_logging(ss);
	}
	
	if ([response statusCode] == 200) {
		NSRange rn1;
		rn1.location=0;
		rn1.length=[responseData length];
		NSString *val=GV_findValueForKey(@"Auth=", responseData, rn1, nil, 0);
		return val;
	}else{
		return nil;
	}
}

static NSString *GV_getGALX(NSString *authToken) {
	if(!authToken)
		return nil;

	NSString *surl = [NSString stringWithFormat:@"https://www.google.com/voice/m?auth=%@", authToken];
	NSURL *url = [NSURL URLWithString:surl];
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
	[loginRequest setValue:USERAGENT_GV forHTTPHeaderField:@"User-Agent"];
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"get galx",ss];
		__do_logging(ss);
	}

	if([response statusCode]!=200){
		return nil;
	}
	
	NSArray *cookies1 = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
	if(cookies1){
		for(int i=0;i<[cookies1 count];i++){
			NSHTTPCookie *ck = [cookies1 objectAtIndex:i];
//			if([ck.name isEqualToString:@"GALX"]){
			if([ck.name isEqualToString:@"gvx"]){
				return ck.value;
			}
		}
	}	
	
	return nil;
}

NSString *__getPurePhoneNumber(NSString *ct) {
	if(!ct)
		return nil;
	
	int nn = [ct length];
	char *buf=(char *)malloc(nn+1);
	char *p=buf;
	
	int i=0;
	if([ct characterAtIndex:0]=='+'){
		*p++='+';
		i++;
	}

	while(i<nn){
		char c = (char)[ct characterAtIndex:i++];
		if(c>='0' && c<='9'){
			*p++=c;
		}
	}
	*p=0;
	
	NSString *res = [NSString stringWithUTF8String:buf];
	free(buf);
	return res;
}

static void __get_rnrse_and_fill_values(NSString *authToken){
	if(!authToken)
		return;

	NSURL *url = [NSURL URLWithString:URL_BALANCE];
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
	[loginRequest setValue:USERAGENT_GV forHTTPHeaderField:@"User-Agent"];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"get rnrse and fill values",ss];
		__do_logging(ss);
	}

	NSString *val=nil, *vv=nil;

	if ([response statusCode] == 200) {
		NSRange rn1;
		rn1.location=0;
		rn1.length=[responseData length];
		val=GV_findValueForKey(@"_rnr_se\" value=\"", responseData, rn1, nil, '"');
		if(val){
			vv=GV_findValueForKey(@"<b class=\"ms3\">", responseData, rn1, nil, 0); 
			if(vv){
				[GV_GVnumber release];
				GV_GVnumber = [__getPurePhoneNumber(vv) retain];
			}
			vv=GV_findValueForKey(@"color: #17A245; font-size: 16px; font-weight: bold;\">", responseData, rn1, nil, 0); 
			[GV_balance release];
			if(vv){
				GV_balance= [vv retain];
			}else{
				GV_balance = [@"N/A" retain];
			}
		}else{
			val=GV_findValueForKey(@"'_rnr_se': '", responseData, rn1, nil, '\'');
			if(val){
				vv=GV_findValueForKey(@"title=\"Go to phones\" href=\"#phones\">", responseData, rn1, nil, 0); 
				if(vv){
					[GV_GVnumber release];
					GV_GVnumber = [__getPurePhoneNumber(vv) retain];
				}
				[GV_balance release];
				GV_balance = [@"N/A" retain];	
			}
		}
	}
	
	[__rnrse release];
	__rnrse = [val retain];
}

static BOOL GV_placeCall(NSString *authToken, NSString *number) {
	if(!authToken)
		return NO;
	
	__get_rnrse_and_fill_values(authToken);
	if(!__rnrse)
		return 0;
	
	NSURL *url = [NSURL URLWithString:URL_PLACECALL];
	
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setHTTPMethod:@"POST"];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
		
	number = __stringByAddingPercentEscapesUsingUTF8(number);
	NSString *rnrse = __stringByAddingPercentEscapesUsingUTF8(__rnrse);

	NSString *requestBody = [NSString stringWithFormat:@"outgoingNumber=%@&forwardingNumber=%@&subscriberNumber=undefined&phoneType=&remember=0&_rnr_se=%@", number, GV_phoneNumber, rnrse];
	[loginRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
		
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"place call",ss];
		__do_logging(ss);
	}

	return [response statusCode] == 200;
}

static BOOL GV_cancelCall(NSString *authToken) {
	if(!authToken || !__rnrse)
		return NO;
	
	NSURL *url = [NSURL URLWithString:URL_CANCELCALL];
	
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setHTTPMethod:@"POST"];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
	
	NSString *rnrse = __stringByAddingPercentEscapesUsingUTF8(__rnrse);
	
	NSString *requestBody = [NSString stringWithFormat:@"outgoingNumber=undefined&forwardingNumber=undefined&cancelType=C2C&_rnr_se=%@", rnrse];
	[loginRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
		
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"cancel call",ss];
		__do_logging(ss);
	}

	return [response statusCode] == 200;
}

static NSString *GV_placeCall_DD(NSString *gvx, NSString *number) {
	if(!gvx)
		return nil;
	
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/voice/m/x?m=call&n=%@&f=%@", number, GV_phoneNumber]];
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setHTTPMethod:@"POST"];
	[loginRequest setValue:USERAGENT_GV forHTTPHeaderField:@"User-Agent"];
	[loginRequest setValue:@"https://www.google.com/voice/m" forHTTPHeaderField:@"Referer"];
	NSString *requestBody = [NSString stringWithFormat:@"{\"gvx\":\"%@\"}", gvx];	
	[loginRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
	NSHTTPURLResponse *response=nil;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"place call dd",ss];
		__do_logging(ss);
	}

	if([response statusCode]==200){
		NSRange rn1;
		rn1.location=0;
		rn1.length=[responseData length];
		NSString *val=GV_findValueForKey(@"\"access_number\":\"", responseData, rn1, nil, '"');
		[GV_balance release];
		GV_balance = [GV_findValueForKey(@"\"displayable_account_balance\":\"", responseData, rn1, nil, '"') retain];
		return val;
	}else{
		return nil;
	}
}

BOOL __placeCall_callback(NSString *number){
	BOOL res = GV_placeCall(__auth, number);
	if(res){
		return TRUE;
	}
	
	[__auth release];
	__auth = [GV_getAuthToken(GV_username, GV_password) retain];
	if(!__auth)
		return FALSE;
	
	return GV_placeCall(__auth, number);
}

BOOL __cancelCall_callback(){	
	return GV_cancelCall(__auth);
}

NSString *__placeCall(NSString *number){
	NSString *res = GV_placeCall_DD(__GALX, number);
	if(res){
		return res;
	}
	
//	NSArray *ac = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies];
//	for(int i=0;i<ac.count;i++){
//		[[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:[ac objectAtIndex:i]];
//	}
	
	[__GALX release];
	__GALX = [GV_getGALX(__auth) retain];
	if(!__GALX){
		[__auth release];
		__auth = [GV_getAuthToken(GV_username, GV_password) retain];
		__GALX = [GV_getGALX(__auth) retain];
	}
	
	return GV_placeCall_DD(__GALX, number);
}

NSString *__getGVNumber() {
	if(GV_GVnumber){
		return GV_GVnumber;
	}
	
	__get_rnrse_and_fill_values(__auth);
	if(!__rnrse){
		[__auth release];
		__auth = [GV_getAuthToken(GV_username, GV_password) retain];
		__get_rnrse_and_fill_values(__auth);
	}
	
	return GV_GVnumber;	
}

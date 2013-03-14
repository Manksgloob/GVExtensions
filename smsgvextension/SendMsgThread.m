//
//  SendMsgThread.m
//  test1
//
//  Created by Zhi Zheng on 10/15/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "CoreTelephony/CTMessage.h"
#import <UIKit/UIKit.h>
#import "SendMsgThread.h"

@implementation SendMsgThread

#define		SERVICE_GV		@"grandcentral"
#define		SOURCE_GV		@"gvmessage"
//#define		USERAGENT_GV	@"Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16"
//#define		URL_GENERALGV	@"https://www.google.com/voice/#inbox"
#define		URL_LOGINGV		@"https://www.google.com/accounts/ClientLogin"
#define		URL_SMS			@"https://www.google.com/voice/inbox/recent/sms"
#define		URL_SMSSEND		@"https://www.google.com/voice/sms/send/"
#define		URL_BALANCE		@"https://www.google.com/voice/b/0/m/billing"

#define		CTMESSAGESENTNOTIFICATION			@"kCTMessageSentNotification"
#define		CTMESSAGESENDERRORNOTIFICATION		@"kCTMessageSendErrorNotification"

extern NSString *GV_username;
extern NSString *GV_password;
extern NSString *GV_sendsig;
extern NSString *GV_recvsig;

static NSString *GV_authToken=nil;
static NSString *GV_rnrse=nil;

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

static NSString *GV_getRNRSE(NSString *authToken) {
	if(!authToken)
		return nil;
	
	NSURL *url = [NSURL URLWithString:URL_BALANCE];
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
//	[loginRequest setValue:USERAGENT_GV forHTTPHeaderField:@"User-Agent"];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"get rnrse",ss];
		__do_logging(ss);
	}
	
	NSString *val=0;

	if ([response statusCode] == 200) {
		NSRange rn1;
		rn1.location=0;
		rn1.length=[responseData length];
		val=GV_findValueForKey(@"_rnr_se\" value=\"", responseData, rn1, nil, '"');
		if(val){
		}else{
			val=GV_findValueForKey(@"'_rnr_se': '", responseData, rn1, nil, '\'');
		}
	}

	return val;
}

static BOOL GV_sendSMS(NSString *authToken, NSString *rnrse, NSString *msg, NSString *number) {
	if(!authToken || !rnrse)
		return NO;
	
	NSURL *url = [NSURL URLWithString:URL_SMSSEND];
	
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setHTTPMethod:@"POST"];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
	
	if(GV_sendsig && [GV_sendsig length]>0){
		msg = [msg stringByAppendingFormat:@"\n%@", GV_sendsig];
	}
	
	msg = __stringByAddingPercentEscapesUsingUTF8(msg);
	number = __stringByAddingPercentEscapesUsingUTF8(number);
	rnrse = __stringByAddingPercentEscapesUsingUTF8(rnrse);
	
	NSString *requestBody = [NSString stringWithFormat:@"phoneNumber=%@&text=%@&_rnr_se=%@", number, msg, rnrse];
	[loginRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	

	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"send sms",ss];
		__do_logging(ss);
	}
	
	return [response statusCode] == 200;
}


+(void)invokeWithDestination:(NSArray *)aDests Text:(NSString *)aText messageId:(unsigned int)msgId postNotification:(POSTNOTIFICATION)aPostNotifProc {
	SendMsgThread *thread = [[SendMsgThread alloc] initWithDestination:aDests Text:aText messageId:msgId postNotification:aPostNotifProc];
	[thread start];
}

-(id)initWithDestination:(NSArray *)aDests Text:(NSString *)aText messageId:(unsigned int)msgId postNotification:(POSTNOTIFICATION)aPostNotifProc {
	self=[super init];
	arrayDests = [aDests retain];
	text=[aText retain];
	messageId = msgId;
	postNotifProc = aPostNotifProc;
	
	return self;
}

-(void)dealloc {
	[arrayDests release];
	[text release];
	[super dealloc];
}


static NSData *GV_recvSMS(NSString *authToken) {
	if(!authToken)
		return nil;
	
	NSURL *url = [NSURL URLWithString:URL_SMS];
	NSMutableURLRequest *loginRequest = [NSMutableURLRequest requestWithURL:url];
	[loginRequest setValue:[NSString stringWithFormat:@"GoogleLogin auth=%@", authToken]
		forHTTPHeaderField:@"Authorization"];
	
	NSHTTPURLResponse *response = NULL;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:loginRequest returningResponse:&response error:nil];	
	
	if(__is_logging()) {
		NSString *ss = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
		ss = [NSString stringWithFormat:@"%@\n%@\n",@"recv sms",ss];
		__do_logging(ss);
	}

	if ([response statusCode] == 200) {
		return responseData;
	}else{
		return nil;
	}
}

extern NSMutableDictionary *_dictContactsCache;

static NSString *__getNumberFromContactType(NSString *ct) {
	if(!ct)
		return nil;
	
	char buf[12];
	buf[0]='1';
	int i, j;
	for(i=0,j=0;j<[ct length] && i<10;){
		char c = (char)[ct characterAtIndex:j++];
		if(c>='0' && c<='9'){
			buf[++i]=c;
		}
	}
	buf[i+1]=0;
	
	return [NSString stringWithUTF8String:buf];
}

static NSString *__parseSMSData(NSData *data, NSString *sender) {
	
	NSRange rn1, rn2;
	rn1.location=0;
	rn1.length=[data length];
	
	while(TRUE) {
		NSString *contactName=GV_findValueForKey(@"Go to contact\" href=\"javascript://\">" , data , rn1 , &rn2, 0);
		if(rn2.location == NSNotFound)
			return nil;
		rn1.location = rn2.location+rn2.length;
		rn1.length = [data length]-rn1.location;
		
		if(contactName){
			contactName = [contactName stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
			contactName = [contactName stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
			contactName = [contactName stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
			contactName = [contactName stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
			contactName = [contactName stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
		}
		
		if(contactName && [contactName isEqualToString:sender]) {
			NSString *contactType=GV_findValueForKey(@"gc-quickcall-ac\" value=\"", data , rn1 , nil, '"');
//			return __getNumberFromContactType(contactType);
			return contactType;
		}
	}
}

NSString *__cacheContact(NSString *sender){
	NSData *data = GV_recvSMS(GV_authToken);
	if(!data){
		[GV_authToken release];
		GV_authToken = GV_getAuthToken(GV_username, GV_password);
		[GV_authToken retain];
		if(!GV_authToken)
			return nil;
		data = GV_recvSMS(GV_authToken);
		if(!data)
			return nil;
	}
	
	NSString *number = __parseSMSData(data, sender);
	if(number){
		[_dictContactsCache setObject:number forKey:sender];
	}
	
	return number;
}

-(void)main {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];  
	
	if(arrayDests && [arrayDests count]>0){
		// try sending to the first one; if failed, re-obtain authToken & rnrse
		NSObject<CTMessageAddress> *addr = [arrayDests objectAtIndex:0];
		NSString *number = [addr canonicalFormat];
		if(!GV_sendSMS(GV_authToken, GV_rnrse, text, number)){
			[GV_authToken release];
			GV_authToken = GV_getAuthToken(GV_username, GV_password);
			[GV_authToken retain];
			if(!GV_authToken)
				goto error_ret;
			[GV_rnrse release];
			GV_rnrse = GV_getRNRSE(GV_authToken);
			[GV_rnrse retain];
			if(!GV_rnrse)
				goto error_ret;
			if(!GV_sendSMS(GV_authToken, GV_rnrse, text, number))
				goto error_ret;
		}
		
		// send the rest messages
		for(int i=1;i<[arrayDests count];i++){
			addr = [arrayDests objectAtIndex:i];
			number = [addr canonicalFormat];
			if(!GV_sendSMS(GV_authToken, GV_rnrse, text, number))
				goto error_ret;
		}
	}

	postNotifProc(CTMESSAGESENTNOTIFICATION, messageId);	
	goto final_release;

error_ret:
	postNotifProc(CTMESSAGESENDERRORNOTIFICATION, messageId);
	
final_release:
	[pool release];
	[self release];
}

@end

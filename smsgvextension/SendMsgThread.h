//
//  SendMsgThread.h
//  test1
//
//  Created by Zhi Zheng on 10/15/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (*POSTNOTIFICATION)(NSString *key, unsigned int);

@interface SendMsgThread : NSThread {
	NSArray *arrayDests;
	NSString *text;
	unsigned int messageId;
	POSTNOTIFICATION postNotifProc;
}

+(void)invokeWithDestination:(NSArray *)aDests Text:(NSString *)aText messageId:(unsigned int)msgId postNotification:(POSTNOTIFICATION)aPostNotifProc;
-(id)initWithDestination:(NSArray *)aDests Text:(NSString *)aText messageId:(unsigned int)msgId postNotification:(POSTNOTIFICATION)aPostNotifProc;
-(void)main;

@end

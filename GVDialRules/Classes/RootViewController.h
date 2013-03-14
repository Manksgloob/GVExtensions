//
//  RootViewController.h
//  GVDialRules
//
//  Created by Zhi Zheng on 11/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DialRuleViewController.h"

@interface RootViewController : UITableViewController {
	NSMutableDictionary *dictRules;
	UIBarButtonItem *editButton, *doneButton, *addButton;
	int _nn0;
}

@property (nonatomic, retain) IBOutlet DialRuleViewController* dialRuleViewController;

@end

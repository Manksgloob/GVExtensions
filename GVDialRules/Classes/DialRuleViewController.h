//
//  DialRuleViewController.h
//  GVDialRules
//
//  Created by Zhi Zheng on 11/26/10.
//  Copyright 2010 com.mrzzheng. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>

@interface DialRuleViewController : UIViewController <ABPeoplePickerNavigationControllerDelegate> {
	NSString *nm;
	int tp;
	ABPeoplePickerNavigationController *abContactPicker;
}

-(void)setPrefix:(NSString *)_nm withMode:(int)_tp;
-(IBAction)btnClicked_AddContact:(id)sender;
-(IBAction)segMode_changed:(id)sender;
-(IBAction)segMode2_changed:(id)sender;
-(NSString *)prefix;
-(int)mode;

@property (nonatomic, retain) IBOutlet UITextField *txtPrefix;
@property (nonatomic, retain) IBOutlet UISegmentedControl *segMode;
@property (nonatomic, retain) IBOutlet UISegmentedControl *segMode2;

@end

//
//  DialRuleViewController.m
//  GVDialRules
//
//  Created by Zhi Zheng on 11/26/10.
//  Copyright 2010 com.mrzzheng. All rights reserved.
//

#import "DialRuleViewController.h"


@implementation DialRuleViewController

@synthesize txtPrefix;
@synthesize segMode;
@synthesize segMode2;

static NSString *__getPurePhoneNumber(NSString *ct) {
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

-(void)setPrefix:(NSString *)_nm withMode:(int)_tp {
	nm = [_nm retain];
	tp = _tp;
	txtPrefix.text=nm;
	if(_tp==0){
		segMode.selectedSegmentIndex = 0;
		segMode2.selectedSegmentIndex = -1;
	}else if(_tp == 1) {
		segMode.selectedSegmentIndex = 1;
		segMode2.selectedSegmentIndex = -1;
	}else if(_tp == 4) {
		segMode.selectedSegmentIndex = 2;
		segMode2.selectedSegmentIndex = -1;
	}else if(_tp == 2) {
		segMode.selectedSegmentIndex = -1;
		segMode2.selectedSegmentIndex = 0;
	}else if(_tp == 3) {
		segMode.selectedSegmentIndex = -1;
		segMode2.selectedSegmentIndex = 1;
	}else{
		segMode.selectedSegmentIndex = -1;
		segMode2.selectedSegmentIndex = -1;
	}
}

-(NSString *)prefix {
	return txtPrefix.text;
}

-(int)mode {
	int n1 = segMode.selectedSegmentIndex;
	int n2 = segMode2.selectedSegmentIndex;
	
	if(n1==0) {
		return 0;
	}else if(n1==1) {
		return 1;
	}else if(n1==2) {
		return 4;
	}else if(n2==0) {
		return 2;
	}else if(n2==1) {
		return 3;
	}else {
		return -1;
	}

}

// The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
/*
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization.
    }
    return self;
}
*/

-(IBAction)btnClicked_AddContact:(id)sender {
	[self presentModalViewController:abContactPicker animated:YES];
}

-(IBAction)segMode_changed:(id)sender {
	if(segMode.selectedSegmentIndex>=0){
		segMode2.selectedSegmentIndex = -1;
	}
}

-(IBAction)segMode2_changed:(id)sender {
	if(segMode2.selectedSegmentIndex>=0){
		segMode.selectedSegmentIndex = -1;
	}
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)peoplePicker {
	[self dismissModalViewControllerAnimated:YES];
}

- (BOOL)peoplePickerNavigationController: (ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person {
	
	// setting the first name
	//    firstName.text = (NSString *)ABRecordCopyValue(person, kABPersonFirstNameProperty);
	
	// setting the last name
	//    lastName.text = (NSString *)ABRecordCopyValue(person, kABPersonLastNameProperty);	
	
	// setting the number
	/*
	 this function will set the first number it finds
	 
	 if you do not set a number for a contact it will probably
	 crash
	 */
	ABMultiValueRef multi = ABRecordCopyValue(person, kABPersonPhoneProperty);
	if (ABMultiValueGetCount(multi) ==1) {
		txtPrefix.text = __getPurePhoneNumber( (NSString*)ABMultiValueCopyValueAtIndex(multi, 0) );
		
		// remove the controller
		[self dismissModalViewControllerAnimated:YES];
		
		return NO;
	}else {
		return YES;
	}
	
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier{
	ABMultiValueRef phoneProperty = ABRecordCopyValue(person,property);
	NSString *phone = (NSString *)ABMultiValueCopyValueAtIndex(phoneProperty,identifier);
	
	txtPrefix.text = __getPurePhoneNumber( phone );
	[phone release];
	
	[self dismissModalViewControllerAnimated:YES];
	return NO;
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
	self.title=@"Edit Rule";
	// creating the picker
	abContactPicker = [[ABPeoplePickerNavigationController alloc] init];
	// place the delegate of the picker to the controll
	abContactPicker.peoplePickerDelegate = self;
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations.
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc. that aren't in use.
}

- (void)viewDidUnload {
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}


- (void)dealloc {
	[nm release];
    [super dealloc];
}


@end

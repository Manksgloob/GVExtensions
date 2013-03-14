//
//  RootViewController.m
//  GVDialRules
//
//  Created by Zhi Zheng on 11/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

//#define	__SIMULATE__

#import "RootViewController.h"

static NSString *PATH_DIALINGRULES				=@"/var/mobile/Library/Preferences/com.mrzzheng.phonegvextension.rules.plist";
static NSString *NOTIFICATION_RULESCHANGED		=@"kCTPhoneGVExtensionRulesChangedNotification";

static BOOL __isEditing = FALSE;

@implementation RootViewController

@synthesize dialRuleViewController;

#pragma mark -
#pragma mark View lifecycle

-(void)btnClicked_edit:(id)sender {
	[self setEditing:!self.editing animated:YES];
}

-(void)btnClicked_add:(id)sender {
	NSString *str = [NSString stringWithFormat:@"Number Prefix %d", _nn0++];
	NSNumber *nn = [NSNumber numberWithInt:-1];
	
	[dictRules setObject:nn forKey:str];
	[self.tableView reloadData];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	[super setEditing:editing animated:animated];
	
	if (editing) {
		self.navigationItem.leftBarButtonItem=doneButton;
		self.navigationItem.rightBarButtonItem=nil;
	}else {
		self.navigationItem.leftBarButtonItem=editButton;
		self.navigationItem.rightBarButtonItem=addButton;
	}
	
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
	editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
															   target:self action:@selector(btnClicked_edit:)];
	doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(btnClicked_edit:)];
	addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
																  target:self
																  action:@selector(btnClicked_add:)];
	self.navigationItem.leftBarButtonItem=editButton;
	self.navigationItem.rightBarButtonItem=addButton;

#ifdef __SIMULATE__
	dictRules=[[NSMutableDictionary dictionary] retain];
	[dictRules setObject:[NSNumber numberWithInt:0] forKey:@"123"];
	[dictRules setObject:[NSNumber numberWithInt:1] forKey:@"32123"];
	[dictRules setObject:[NSNumber numberWithInt:2] forKey:@"r43123"];
	[dictRules setObject:[NSNumber numberWithInt:3] forKey:@"454r43123"];
#else
	dictRules = [[NSMutableDictionary alloc] initWithContentsOfFile:PATH_DIALINGRULES];
	if(!dictRules)
		dictRules=[[NSMutableDictionary dictionary] retain];
#endif // __SIMULATE__
	
	_nn0 = 1;
}


/*
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}
*/
/*
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}
*/
/*
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
}
*/
/*
- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
}
*/

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	// Return YES for supported orientations.
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


#pragma mark -
#pragma mark Table view data source

// Customize the number of sections in the table view.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSArray *keys = [dictRules allKeys];
    return keys.count;
}

/*
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 60.0;
}
*/

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier] autorelease];
    }
    
	// Configure the cell.
	NSArray *keys0 = [dictRules allKeys];
	NSArray *keys = [keys0 sortedArrayUsingSelector:@selector(compare:)];
	NSString *nm = [keys objectAtIndex:indexPath.row];
	cell.textLabel.text=nm;
	NSNumber *nn = [dictRules objectForKey:nm];
	int nnn = [nn intValue];
	NSString *tt;
	switch(nnn){
		case 0:
			tt=@"GV Direct Dial";
			break;
		case 1:
			tt=@"GV Call Back";
			break;
		case 4:
			tt=@"GV Offline Dial";
			break;
		case 2:
			tt=@"Carrier";
			break;
		case 3:
			tt=@"Ask Before Dialing";
			break;
		default:
			tt=@"(Unknown)";
			break;			
	}
	cell.detailTextLabel.text=tt;
	cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
	
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source.
		NSArray *keys0 = [dictRules allKeys];
		NSArray *keys = [keys0 sortedArrayUsingSelector:@selector(compare:)];
		NSString *nm = [keys objectAtIndex:indexPath.row];
		[dictRules removeObjectForKey:nm];
#ifndef __SIMULATE__
		[dictRules writeToFile:PATH_DIALINGRULES atomically:YES];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
											 (CFStringRef)NOTIFICATION_RULESCHANGED,
											 0, 0, YES);
#endif // __SIMULATE__
		[self.tableView reloadData];
		
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }   
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
	
	if(viewController == self && __isEditing){
		__isEditing=FALSE;
		NSString *ss=[dialRuleViewController prefix];
		int mm = [dialRuleViewController mode];
		[dictRules setObject:[NSNumber numberWithInt:mm] forKey:ss];
#ifndef __SIMULATE__
		[dictRules writeToFile:PATH_DIALINGRULES atomically:YES];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
											 (CFStringRef)NOTIFICATION_RULESCHANGED,
											 0, 0, YES);
#endif // __SIMULATE__
		[self.tableView reloadData];
	}
}
		 
/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/


/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/


#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
	/*
	 <#DetailViewController#> *detailViewController = [[<#DetailViewController#> alloc] initWithNibName:@"<#Nib name#>" bundle:nil];
     // ...
     // Pass the selected object to the new view controller.
	 [self.navigationController pushViewController:detailViewController animated:YES];
	 [detailViewController release];
	 */
	NSArray *keys0 = [dictRules allKeys];
	NSArray *keys = [keys0 sortedArrayUsingSelector:@selector(compare:)];
	NSString *nm = [keys objectAtIndex:indexPath.row];
	NSNumber *tn = [dictRules objectForKey:nm];
	[dialRuleViewController setPrefix:nm withMode:[tn intValue]];
	[dictRules removeObjectForKey:nm];
	
	__isEditing=TRUE;
	[self.navigationController pushViewController:dialRuleViewController animated:YES];
	[dialRuleViewController.txtPrefix becomeFirstResponder];
}


#pragma mark -
#pragma mark Memory management

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Relinquish ownership any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
    // Relinquish ownership of anything that can be recreated in viewDidLoad or on demand.
    // For example: self.myOutlet = nil;
}


- (void)dealloc {
	[dictRules release];
	[editButton release];
	[doneButton release];
	[addButton release];
    [super dealloc];
}


@end


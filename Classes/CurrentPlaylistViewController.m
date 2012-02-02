//
//  CurrentPlaylistViewController.m
//  iSub
//
//  Created by Ben Baron on 4/9/10.
//  Copyright 2010 Ben Baron. All rights reserved.
//

#import "CurrentPlaylistViewController.h"
#import "CurrentPlaylistSongSmallUITableViewCell.h"
#import "iSubAppDelegate.h"
#import "ViewObjectsSingleton.h"
#import "MusicSingleton.h"
#import "DatabaseSingleton.h"
#import "NSString+md5.h"
#import "Song.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "CustomUIAlertView.h"
#import "SavedSettings.h"
#import "NSString+time.h"
#import "PlaylistSingleton.h"
#import "AudioEngine.h"
#import "FMDatabase+Synchronized.h"

@implementation CurrentPlaylistViewController
@synthesize dataModel;

#pragma mark -
#pragma mark View lifecycle

- (void)viewDidLoad 
{
    [super viewDidLoad];
	
	appDelegate = (iSubAppDelegate *)[[UIApplication sharedApplication] delegate];
	viewObjects = [ViewObjectsSingleton sharedInstance];
	musicControls = [MusicSingleton sharedInstance];
	databaseControls = [DatabaseSingleton sharedInstance];
	
	currentPlaylistCount = 0;
	
	//NSDate *start = [NSDate date];
	dataModel = [PlaylistSingleton sharedInstance];
	
	self.tableView.backgroundColor = [UIColor clearColor];
	
	if ([SavedSettings sharedInstance].isPlaylistUnlocked)
	{
		viewObjects.multiDeleteList = [NSMutableArray arrayWithCapacity:1];
		//viewObjects.multiDeleteList = nil; viewObjects.multiDeleteList = [[NSMutableArray alloc] init];
		goToNextSong = NO;
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectRow) name:ISMSNotification_CurrentPlaylistIndexChanged object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectRow) name:ISMSNotification_CurrentPlaylistShuffleToggled object:nil];
		
		if ([databaseControls.currentPlaylistDb intForQuery:@"SELECT COUNT(*) FROM currentPlaylist"] > 0)
		{
			[self selectRow];
		}
		
		// Setup header view
		headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
		headerView.backgroundColor = [UIColor colorWithWhite:.3 alpha:1];
		
		savePlaylistLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 227, 34)];
		savePlaylistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		savePlaylistLabel.backgroundColor = [UIColor clearColor];
		savePlaylistLabel.textColor = [UIColor whiteColor];
		savePlaylistLabel.textAlignment = UITextAlignmentCenter;
		savePlaylistLabel.font = [UIFont boldSystemFontOfSize:22];
		savePlaylistLabel.text = @"Save Playlist";
		[headerView addSubview:savePlaylistLabel];
		[savePlaylistLabel release];
		
		playlistCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 33, 227, 14)];
		playlistCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		playlistCountLabel.backgroundColor = [UIColor clearColor];
		playlistCountLabel.textColor = [UIColor whiteColor];
		playlistCountLabel.textAlignment = UITextAlignmentCenter;
		playlistCountLabel.font = [UIFont boldSystemFontOfSize:12];
		NSUInteger songCount = dataModel.count;
		if (songCount == 1)
			playlistCountLabel.text = [NSString stringWithFormat:@"1 song"];
		else
			playlistCountLabel.text = [NSString stringWithFormat:@"%i songs", songCount];
		[headerView addSubview:playlistCountLabel];
		[playlistCountLabel release];
		
		savePlaylistButton = [UIButton buttonWithType:UIButtonTypeCustom];
		savePlaylistButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		savePlaylistButton.frame = CGRectMake(0, 0, 240, 40);
		[savePlaylistButton addTarget:self action:@selector(savePlaylistAction:) forControlEvents:UIControlEventTouchUpInside];
		[headerView addSubview:savePlaylistButton];
		
		UILabel *spacerLabel = [[UILabel alloc] initWithFrame:CGRectMake(236, -2.5, 6, 50)];
		spacerLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		//spacerLabel.textAlignment = UITextAlignmentCenter;
		spacerLabel.backgroundColor = [UIColor clearColor];
		spacerLabel.textColor = [UIColor whiteColor];
		spacerLabel.font = [UIFont systemFontOfSize:40];
		spacerLabel.text = @"|";
		[headerView addSubview:spacerLabel];
		[spacerLabel release];	
		
		editPlaylistLabel = [[UILabel alloc] initWithFrame:CGRectMake(244, 0, 76, 50)];
		editPlaylistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
		editPlaylistLabel.backgroundColor = [UIColor clearColor];
		editPlaylistLabel.textColor = [UIColor whiteColor];
		editPlaylistLabel.textAlignment = UITextAlignmentCenter;
		editPlaylistLabel.font = [UIFont boldSystemFontOfSize:22];
		editPlaylistLabel.text = @"Edit";
		[headerView addSubview:editPlaylistLabel];
		[editPlaylistLabel release];
		
		UIButton *editPlaylistButton = [UIButton buttonWithType:UIButtonTypeCustom];
		editPlaylistButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
		editPlaylistButton.frame = CGRectMake(244, 0, 76, 40);
		[editPlaylistButton addTarget:self action:@selector(editPlaylistAction:) forControlEvents:UIControlEventTouchUpInside];
		[headerView addSubview:editPlaylistButton];
		
		deleteSongsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 237, 50)];
		deleteSongsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		deleteSongsLabel.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:.5];
		deleteSongsLabel.textColor = [UIColor whiteColor];
		deleteSongsLabel.textAlignment = UITextAlignmentCenter;
		deleteSongsLabel.font = [UIFont boldSystemFontOfSize:22];
		deleteSongsLabel.adjustsFontSizeToFitWidth = YES;
		deleteSongsLabel.minimumFontSize = 12;
		deleteSongsLabel.text = @"Remove # Songs";
		deleteSongsLabel.hidden = YES;
		[headerView addSubview:deleteSongsLabel];
		[deleteSongsLabel release];	
		
		self.tableView.tableHeaderView = headerView;
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hideEditControls) name:@"hideEditControls" object:nil];
	}
	else
	{
		self.tableView.separatorColor = [UIColor clearColor];
		
		UIImageView *noPlaylistsScreen = [[UIImageView alloc] init];
		noPlaylistsScreen.frame = CGRectMake(40, 80, 240, 180);
		noPlaylistsScreen.image = [UIImage imageNamed:@"loading-screen-image.png"];
		
		UILabel *textLabel = [[UILabel alloc] init];
		textLabel.backgroundColor = [UIColor clearColor];
		textLabel.textColor = [UIColor whiteColor];
		textLabel.font = [UIFont boldSystemFontOfSize:32];
		textLabel.textAlignment = UITextAlignmentCenter;
		textLabel.numberOfLines = 0;
		textLabel.text = @"Playlists\nLocked";
		textLabel.frame = CGRectMake(20, 0, 200, 100);
		[noPlaylistsScreen addSubview:textLabel];
		[textLabel release];
		
		UILabel *textLabel2 = [[UILabel alloc] init];
		textLabel2.backgroundColor = [UIColor clearColor];
		textLabel2.textColor = [UIColor whiteColor];
		textLabel2.font = [UIFont boldSystemFontOfSize:14];
		textLabel2.textAlignment = UITextAlignmentCenter;
		textLabel2.numberOfLines = 0;
		textLabel2.text = @"Tap to purchase the ability to view, create, and manage playlists";
		textLabel2.frame = CGRectMake(20, 100, 200, 60);
		[noPlaylistsScreen addSubview:textLabel2];
		[textLabel2 release];
		
		[self.view addSubview:noPlaylistsScreen];
		
		[noPlaylistsScreen release];
	}
	//DLog(@"end: %f", [[NSDate date] timeIntervalSinceDate:start]);
}

- (void)viewWillAppear:(BOOL)animated 
{
	[super viewWillAppear:animated];
	
	[self selectRow];
}

- (void)viewWillDisappear:(BOOL)animated 
{
    [super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:ISMSNotification_CurrentPlaylistIndexChanged object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:ISMSNotification_CurrentPlaylistShuffleToggled object:nil];
	
	if (viewObjects.isEditing)
	{
		// Clear the edit stuff if they switch tabs in the middle of editing
		viewObjects.multiDeleteList = [NSMutableArray arrayWithCapacity:1];
		viewObjects.isEditing = NO;
		self.tableView.editing = NO;
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"showDeleteButton" object:nil];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"hideDeleteButton" object:nil];
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"hideEditControls" object:nil];
	
	[headerView release]; headerView = nil;
}

- (void)didReceiveMemoryWarning 
{
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
}

- (void)dealloc 
{
    [super dealloc];
}

#pragma mark -

- (void)editPlaylistAction:(id)sender
{
	if (self.tableView.editing == NO)
	{
		viewObjects.isEditing = YES;
		[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(showDeleteButton) name:@"showDeleteButton" object: nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(hideDeleteButton) name:@"hideDeleteButton" object: nil];
		viewObjects.multiDeleteList = [NSMutableArray arrayWithCapacity:1];
		[self.tableView setEditing:YES animated:YES];
		editPlaylistLabel.backgroundColor = [UIColor colorWithRed:0.008 green:.46 blue:.933 alpha:1];
		editPlaylistLabel.text = @"Done";
		[self showDeleteButton];
		
		// Hide the duration labels and shorten the song and artist labels
		for (CurrentPlaylistSongSmallUITableViewCell *cell in [self.tableView visibleCells])
		{
			cell.durationLabel.hidden = YES;
		}
		
		[NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(showDeleteToggle) userInfo:nil repeats:NO];
	}
	else 
	{
		viewObjects.isEditing = NO;
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"showDeleteButton" object:nil];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:@"hideDeleteButton" object:nil];
		viewObjects.multiDeleteList = [NSMutableArray arrayWithCapacity:1];
		[self hideDeleteButton];
		[self.tableView setEditing:NO animated:YES];
		editPlaylistLabel.backgroundColor = [UIColor clearColor];
		editPlaylistLabel.text = @"Edit";
		
		if (goToNextSong)
		{
			goToNextSong = NO;
			if ([AudioEngine sharedInstance].isPlaying)
			{
				if ([databaseControls.currentPlaylistDb intForQuery:@"SELECT COUNT(*) FROM currentPlaylist"] > 0)
				{
					[musicControls nextSong];
				}
				else
				{
                    [[AudioEngine sharedInstance] stop];
					// Pop to root view controller doesn't work for nav controllers inside more tab //
				}
			}
		}
		
		// Reload the table to correct the numbers
		[self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];

		if (dataModel.currentIndex >= 0 && dataModel.currentIndex < currentPlaylistCount)
		{
			[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:dataModel.currentIndex inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
		}
	}
}

- (void) hideEditControls
{
	if (self.tableView.editing == YES)
		[self editPlaylistAction:nil];
}

- (void) showDeleteButton
{
	if ([viewObjects.multiDeleteList count] == 0)
	{
		deleteSongsLabel.text = @"Clear Playlist";
	}
	else if ([viewObjects.multiDeleteList count] == 1)
	{
		deleteSongsLabel.text = @"Remove 1 Song  ";
	}
	else
	{
		deleteSongsLabel.text = [NSString stringWithFormat:@"Remove %i Songs", [viewObjects.multiDeleteList count]];
	}
	
	savePlaylistLabel.hidden = YES;
	playlistCountLabel.hidden = YES;
	deleteSongsLabel.hidden = NO;
}

- (void) hideDeleteButton
{
	if ([viewObjects.multiDeleteList count] == 0)
	{
		if (viewObjects.isEditing == NO)
		{
			savePlaylistLabel.hidden = NO;
			playlistCountLabel.hidden = NO;
			deleteSongsLabel.hidden = YES;
		}
		else
		{
			deleteSongsLabel.text = @"Clear Playlist";
		}
	}
	else if ([viewObjects.multiDeleteList count] == 1)
	{
		deleteSongsLabel.text = @"Remove 1 Song  ";
	}
	else 
	{
		deleteSongsLabel.text = [NSString stringWithFormat:@"Remove %i Songs", [viewObjects.multiDeleteList count]];
	}
}

- (void) showDeleteToggle
{
	// Show the delete toggle for already visible cells
	for (id cell in self.tableView.visibleCells) 
	{
		[[cell deleteToggleImage] setHidden:NO];
	}
}

- (void) savePlaylistAction:(id)sender
{
	if (deleteSongsLabel.hidden == YES)
	{
		if (viewObjects.isEditing == NO)
		{
			savePlaylistLabel.backgroundColor = [UIColor colorWithRed:0.008 green:.46 blue:.933 alpha:1];
			playlistCountLabel.backgroundColor = [UIColor colorWithRed:0.008 green:.46 blue:.933 alpha:1];
			
			UIAlertView *myAlertView = [[UIAlertView alloc] initWithTitle:@"Playlist Name:" message:@"this gets covered" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save", nil];
			playlistNameTextField = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 47.0, 260.0, 22.0)];
			[playlistNameTextField setBackgroundColor:[UIColor whiteColor]];
			[myAlertView addSubview:playlistNameTextField];
			[playlistNameTextField release];
			if ([[[[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."] objectAtIndex:0] isEqualToString:@"3"])
			{
				CGAffineTransform myTransform = CGAffineTransformMakeTranslation(0.0, 100.0);
				[myAlertView setTransform:myTransform];
			}
			[myAlertView show];
			[myAlertView release];
			[playlistNameTextField becomeFirstResponder];
		}
	}
	else 
	{
		if ([deleteSongsLabel.text isEqualToString:@"Clear Playlist"])
		{
			if ([SavedSettings sharedInstance].isJukeboxEnabled)
			{
				[databaseControls resetJukeboxPlaylist];
				[musicControls jukeboxClearPlaylist];
			}
			else
			{
                [[AudioEngine sharedInstance] stop];
				[databaseControls resetCurrentPlaylistDb];
			}
			
			[self editPlaylistAction:nil];
		}
		else
		{
			//
			// Delete action
			//
			
			[dataModel deleteSongs:viewObjects.multiDeleteList];
						
			// Create indexPaths from multiDeleteList and delete the rows in the table view
			NSMutableArray *indexes = [[NSMutableArray alloc] init];
			for (NSNumber *index in viewObjects.multiDeleteList)
			{
				@autoreleasepool 
				{
					[indexes addObject:[NSIndexPath indexPathForRow:[index integerValue] inSection:0]];
				}
			}
			[self.tableView performSelectorOnMainThread:@selector(deleteRowsAtIndexPaths:withRowAnimation:) withObject:indexes waitUntilDone:YES];
			[indexes release];
			
			[self editPlaylistAction:nil];
		}
		
		// Fix the playlist count
		NSUInteger songCount = dataModel.count;
		if (songCount == 1)
			playlistCountLabel.text = [NSString stringWithFormat:@"1 song"];
		else
			playlistCountLabel.text = [NSString stringWithFormat:@"%i songs", songCount];
	}
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	PlaylistSingleton *currentPlaylist = [PlaylistSingleton sharedInstance];
	
    if([alertView.title isEqualToString:@"Playlist Name:"])
	{
		[playlistNameTextField resignFirstResponder];
		if(buttonIndex == 1)
		{
			// Check if the playlist exists, if not create the playlist table and add the entry to localPlaylists table
			if ([databaseControls.localPlaylistsDb intForQuery:@"SELECT COUNT(*) FROM localPlaylists WHERE md5 = ?", [playlistNameTextField.text md5]] == 0)
			{
				[databaseControls.localPlaylistsDb executeUpdate:@"INSERT INTO localPlaylists (playlist, md5) VALUES (?, ?)", playlistNameTextField.text, [playlistNameTextField.text md5]];
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"CREATE TABLE playlist%@ (title TEXT, songId TEXT, artist TEXT, album TEXT, genre TEXT, coverArtId TEXT, path TEXT, suffix TEXT, transcodedSuffix TEXT, duration INTEGER, bitRate INTEGER, track INTEGER, year INTEGER, size INTEGER)", [playlistNameTextField.text md5]]];
				
				[databaseControls.localPlaylistsDb executeUpdate:@"ATTACH DATABASE ? AS ?", [NSString stringWithFormat:@"%@/%@currentPlaylist.db", databaseControls.databaseFolderPath, [[SavedSettings sharedInstance].urlString md5]], @"currentPlaylistDb"];
				if ([databaseControls.localPlaylistsDb hadError]) { DLog(@"Err attaching the currentPlaylistDb %d: %@", [databaseControls.localPlaylistsDb lastErrorCode], [databaseControls.localPlaylistsDb lastErrorMessage]); }
				if (currentPlaylist.isShuffle) {
					[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO playlist%@ SELECT * FROM shufflePlaylist", [playlistNameTextField.text md5]]];
				}
				else {
					[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO playlist%@ SELECT * FROM currentPlaylist", [playlistNameTextField.text md5]]];
				}
				[databaseControls.localPlaylistsDb executeUpdate:@"DETACH DATABASE currentPlaylistDb"];
			}
			else
			{
				// If it exists, ask to overwrite
				UIAlertView *myAlertView = [[UIAlertView alloc] initWithTitle:@"Overwrite?" message:@"There is already a playlist with this name. Would you like to overwrite it?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
				[myAlertView show];
				[myAlertView release];
			}
		}
	}
	else if([alertView.title isEqualToString:@"Overwrite?"])
	{
		if(buttonIndex == 1)
		{
			// If yes, overwrite the playlist
			[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"DROP TABLE playlist%@", [playlistNameTextField.text md5]]];
			[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"CREATE TABLE playlist%@ (title TEXT, songId TEXT, artist TEXT, album TEXT, genre TEXT, coverArtId TEXT, path TEXT, suffix TEXT, transcodedSuffix TEXT, duration INTEGER, bitRate INTEGER, track INTEGER, year INTEGER, size INTEGER)", [playlistNameTextField.text md5]]];
			
			[databaseControls.localPlaylistsDb executeUpdate:@"ATTACH DATABASE ? AS ?", [NSString stringWithFormat:@"%@/%@currentPlaylist.db", databaseControls.databaseFolderPath, [[SavedSettings sharedInstance].urlString md5]], @"currentPlaylistDb"];
			if ([databaseControls.localPlaylistsDb hadError]) { DLog(@"Err attaching the currentPlaylistDb %d: %@", [databaseControls.localPlaylistsDb lastErrorCode], [databaseControls.localPlaylistsDb lastErrorMessage]); }
			if (currentPlaylist.isShuffle) {
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO playlist%@ SELECT * FROM shufflePlaylist", [playlistNameTextField.text md5]]];
			}
			else {
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO playlist%@ SELECT * FROM currentPlaylist", [playlistNameTextField.text md5]]];
			}
			[databaseControls.localPlaylistsDb executeUpdate:@"DETACH DATABASE currentPlaylistDb"];
		}
	}
	
	savePlaylistLabel.backgroundColor = [UIColor clearColor];
	playlistCountLabel.backgroundColor = [UIColor clearColor];
}

- (void)selectRow
{
	[self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
	if (dataModel.currentIndex >= 0 && dataModel.currentIndex < currentPlaylistCount)
	{
		[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:dataModel.currentIndex inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
	}
}


#pragma mark -
#pragma mark Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
    // Return the number of rows in the section.
	if ([SavedSettings sharedInstance].isPlaylistUnlocked)
	{
		if ([SavedSettings sharedInstance].isJukeboxEnabled)
			currentPlaylistCount = [databaseControls.currentPlaylistDb synchronizedIntForQuery:@"SELECT COUNT(*) FROM jukeboxCurrentPlaylist"];
		else
			currentPlaylistCount = [databaseControls.currentPlaylistDb synchronizedIntForQuery:@"SELECT COUNT(*) FROM currentPlaylist"];
	}
	else
	{
		currentPlaylistCount = 0;
	}
	
	return currentPlaylistCount;
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{	
	PlaylistSingleton *currentPlaylist = [PlaylistSingleton sharedInstance];
	
	static NSString *CellIdentifier = @"Cell";
	
	CurrentPlaylistSongSmallUITableViewCell *cell = [[[CurrentPlaylistSongSmallUITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    cell.indexPath = indexPath;
	
	cell.deleteToggleImage.hidden = !viewObjects.isEditing;
	if ([viewObjects.multiDeleteList containsObject:[NSNumber numberWithInt:indexPath.row]])
	{
		cell.deleteToggleImage.image = [UIImage imageNamed:@"selected.png"];
	}
	
	Song *aSong;
	if ([SavedSettings sharedInstance].isJukeboxEnabled)
	{
		aSong = [Song songFromDbRow:indexPath.row inTable:@"jukeboxCurrentPlaylist" inDatabase:databaseControls.currentPlaylistDb];
	}
	else
	{
		if (currentPlaylist.isShuffle)
			aSong = [Song songFromDbRow:indexPath.row inTable:@"shufflePlaylist" inDatabase:databaseControls.currentPlaylistDb];
		else
			aSong = [Song songFromDbRow:indexPath.row inTable:@"currentPlaylist" inDatabase:databaseControls.currentPlaylistDb];
	}
	
	cell.numberLabel.text = [NSString stringWithFormat:@"%i", (indexPath.row + 1)];
	cell.songNameLabel.text = aSong.title;

	if (aSong.album)
		cell.artistNameLabel.text = [NSString stringWithFormat:@"%@ - %@", aSong.artist, aSong.album];
	else
		cell.artistNameLabel.text = aSong.artist;

	cell.durationLabel.text = [NSString formatTime:[aSong.duration floatValue]];	
	
	// Hide the duration labels if editing
	if (viewObjects.isEditing)
	{
		cell.durationLabel.hidden = YES;
	}
	
    return cell;
}



// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}


// Set the editing style, set to none for no delete minus sign (overriding with own custom multi-delete boxes)
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleNone;
	//return UITableViewCellEditingStyleDelete;
}


// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath 
{
	PlaylistSingleton *currentPlaylist = [PlaylistSingleton sharedInstance];
	
	NSInteger fromRow = fromIndexPath.row + 1;
	NSInteger toRow = toIndexPath.row + 1;
	
	if ([SavedSettings sharedInstance].isJukeboxEnabled)
	{
		[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE jukeboxTemp"];
		[databaseControls.currentPlaylistDb executeUpdate:@"CREATE TABLE jukeboxTemp(title TEXT, songId TEXT, artist TEXT, album TEXT, genre TEXT, coverArtId TEXT, path TEXT, suffix TEXT, transcodedSuffix TEXT, duration INTEGER, bitRate INTEGER, track INTEGER, year INTEGER, size INTEGER)"];
		
		if (fromRow < toRow)
		{
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID < ?", [NSNumber numberWithInt:fromRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID > ? AND ROWID <= ?", [NSNumber numberWithInt:fromRow], [NSNumber numberWithInt:toRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID > ?", [NSNumber numberWithInt:toRow]];
			
			[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE jukeboxCurrentPlaylist"];
			[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE jukeboxTemp RENAME TO jukeboxCurrentPlaylist"];
		}
		else
		{
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID < ?", [NSNumber numberWithInt:toRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID >= ? AND ROWID < ?", [NSNumber numberWithInt:toRow], [NSNumber numberWithInt:fromRow]];
			[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO jukeboxTemp SELECT * FROM jukeboxCurrentPlaylist WHERE ROWID > ?", [NSNumber numberWithInt:fromRow]];
			
			[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE jukeboxCurrentPlaylist"];
			[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE jukeboxTemp RENAME TO jukeboxCurrentPlaylist"];
		}
	}
	else
	{
		if (currentPlaylist.isShuffle)
		{
			[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE shuffleTemp"];
			[databaseControls.currentPlaylistDb executeUpdate:@"CREATE TABLE shuffleTemp(title TEXT, songId TEXT, artist TEXT, album TEXT, genre TEXT, coverArtId TEXT, path TEXT, suffix TEXT, transcodedSuffix TEXT, duration INTEGER, bitRate INTEGER, track INTEGER, year INTEGER, size INTEGER)"];
			
			if (fromRow < toRow)
			{
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID < ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID > ? AND ROWID <= ?", [NSNumber numberWithInt:fromRow], [NSNumber numberWithInt:toRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID > ?", [NSNumber numberWithInt:toRow]];
				
				[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE shufflePlaylist"];
				[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE shuffleTemp RENAME TO shufflePlaylist"];
			}
			else
			{
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID < ?", [NSNumber numberWithInt:toRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID >= ? AND ROWID < ?", [NSNumber numberWithInt:toRow], [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO shuffleTemp SELECT * FROM shufflePlaylist WHERE ROWID > ?", [NSNumber numberWithInt:fromRow]];
				
				[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE shufflePlaylist"];
				[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE shuffleTemp RENAME TO shufflePlaylist"];
			}
		}
		else
		{
			[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE currentTemp"];
			[databaseControls.currentPlaylistDb executeUpdate:@"CREATE TABLE currentTemp(title TEXT, songId TEXT, artist TEXT, album TEXT, genre TEXT, coverArtId TEXT, path TEXT, suffix TEXT, transcodedSuffix TEXT, duration INTEGER, bitRate INTEGER, track INTEGER, year INTEGER, size INTEGER)"];
			
			if (fromRow < toRow)
			{
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID < ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID > ? AND ROWID <= ?", [NSNumber numberWithInt:fromRow], [NSNumber numberWithInt:toRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID > ?", [NSNumber numberWithInt:toRow]];
				
				[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE currentPlaylist"];
				[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE currentTemp RENAME TO currentPlaylist"];
			}
			else
			{
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID < ?", [NSNumber numberWithInt:toRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID = ?", [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID >= ? AND ROWID < ?", [NSNumber numberWithInt:toRow], [NSNumber numberWithInt:fromRow]];
				[databaseControls.currentPlaylistDb executeUpdate:@"INSERT INTO currentTemp SELECT * FROM currentPlaylist WHERE ROWID > ?", [NSNumber numberWithInt:fromRow]];
				
				[databaseControls.currentPlaylistDb executeUpdate:@"DROP TABLE currentPlaylist"];
				[databaseControls.currentPlaylistDb executeUpdate:@"ALTER TABLE currentTemp RENAME TO currentPlaylist"];
			}
		}	
	}
	
	// Fix the multiDeleteList to reflect the new row positions
	if ([viewObjects.multiDeleteList count] > 0)
	{
		NSMutableArray *tempMultiDeleteList = [[NSMutableArray alloc] init];
		int newPosition;
		for (NSNumber *position in viewObjects.multiDeleteList)
		{
			if (fromIndexPath.row > toIndexPath.row)
			{
				if ([position intValue] >= toIndexPath.row && [position intValue] <= fromIndexPath.row)
				{
					if ([position intValue] == fromIndexPath.row)
					{
						[tempMultiDeleteList addObject:[NSNumber numberWithInt:toIndexPath.row]];
					}
					else 
					{
						newPosition = [position intValue] + 1;
						[tempMultiDeleteList addObject:[NSNumber numberWithInt:newPosition]];
					}
				}
				else
				{
					[tempMultiDeleteList addObject:position];
				}
			}
			else
			{
				if ([position intValue] <= toIndexPath.row && [position intValue] >= fromIndexPath.row)
				{
					if ([position intValue] == fromIndexPath.row)
					{
						[tempMultiDeleteList addObject:[NSNumber numberWithInt:toIndexPath.row]];
					}
					else 
					{
						newPosition = [position intValue] - 1;
						[tempMultiDeleteList addObject:[NSNumber numberWithInt:newPosition]];
					}
				}
				else
				{
					[tempMultiDeleteList addObject:position];
				}
			}
		}
		viewObjects.multiDeleteList = [NSMutableArray arrayWithArray:tempMultiDeleteList];
		[tempMultiDeleteList release];
	}
	
	// Correct the value of currentPlaylistPosition
	if (fromIndexPath.row == dataModel.currentIndex)
	{
		dataModel.currentIndex = toIndexPath.row;
	}
	else 
	{
		if (fromIndexPath.row < dataModel.currentIndex && toIndexPath.row >= dataModel.currentIndex)
		{
			dataModel.currentIndex = dataModel.currentIndex - 1;
		}
		else if (fromIndexPath.row > dataModel.currentIndex && toIndexPath.row <= dataModel.currentIndex)
		{
			dataModel.currentIndex = dataModel.currentIndex + 1;
		}
	}
	
	if ([SavedSettings sharedInstance].isJukeboxEnabled)
	{
		[musicControls jukeboxReplacePlaylistWithLocal];
	}
}


// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath 
{
	return YES;
}



#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
	[musicControls playSongAtPosition:indexPath.row];
}

@end


//
//  Shazam.m
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ShazamController.h"
#import "Song.h"
#import "ShazamConstants.h"
#import "LastFmController.h"
#import "AppDelegate.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

@interface ShazamController ()

@end

@implementation ShazamController : NSObject

//Fills the menu with last 20 shazamed songs
+ (void)init {
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    
    if([database open]) {
        FMResultSet *rs = [database executeQuery:@"select track.Z_PK as ZID, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK ORDER BY ZID DESC LIMIT 20"];
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
        int i = 3;
        while ([rs next]) {
            NSMenuItem* item = [menu insert:rs withIndex:i++];
            [item setState:NSMixedState];
        }
        [database close];
    }
}

// Wait for Shazam to tag a song
// The function automatically detects changes happening on the Shazam SQLite file
+ (void)watch:(NSString*) path {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    int fildes = open([path UTF8String], O_EVTONLY);
    
    __block typeof(self) blockSelf = self;
    __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fildes, DISPATCH_VNODE_ATTRIB, queue);
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if (flags)
        {
            dispatch_source_cancel(source);
            [self findNewTags:false];
            [blockSelf watch:path];
        }
    });
    dispatch_source_set_cancel_handler(source, ^(void) {
        close(fildes);
    });
    dispatch_resume(source);
}

//Find and scrobble new tags
+ (void)findNewTags:(bool)scrobblingWasDisabled {
    //Initialize previous session information
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // Last scrobble to last.fm
    if ([prefs integerForKey:@"lastScrobble"] < 0) {
        [prefs setInteger:0 forKey:@"lastScrobble"];
    };
    
    // Connection to the DB
    FMDatabase *database = [FMDatabase databaseWithPath:[ShazamConstants getSqlitePath]];
    if([database open])
    {
        MenuController *menu = ((AppDelegate *)[NSApplication sharedApplication].delegate).menu ;
        NSInteger unscrobbledCount = 0;
        NSInteger lastScrobblePosition = [prefs integerForKey:@"lastScrobble"];

        // Get Shazam tags since the last Scrobble to last.fm
        FMResultSet *shazamTagsSinceLastScrobble = [database executeQuery:[NSString stringWithFormat:@"select track.Z_PK as ZID, ZDATE, ZTRACKNAME, ZNAME from ZSHARTISTMO artist, ZSHTAGRESULTMO track where artist.ZTAGRESULT = track.Z_PK and track.Z_PK > %ld", lastScrobblePosition]];
        
        // While a new Shazam tag is found
        while ([shazamTagsSinceLastScrobble next]) {

            // Because the tagged list can contain unscrobbled items,
            // only add the song to the menubar if asked
            if (!scrobblingWasDisabled) {
                [menu insert:shazamTagsSinceLastScrobble];
            }
            
            // Check if scrobbling is enabled
            if ([prefs integerForKey:@"scrobbling"]) {
                NSDate *newDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[[shazamTagsSinceLastScrobble stringForColumn:@"ZDATE"] doubleValue]];
                Song *song = [[Song alloc] initWithSong:[shazamTagsSinceLastScrobble stringForColumn:@"ZTRACKNAME"]
                                                 artist:[shazamTagsSinceLastScrobble stringForColumn:@"ZNAME"]
                                                   date:newDate];
                [LastFmController scrobble:song withTag:[shazamTagsSinceLastScrobble intForColumn:@"ZID"]];
                lastScrobblePosition++;
                [prefs setInteger:lastScrobblePosition forKey:@"lastScrobble"];
            } else {
                unscrobbledCount++;
            }
            
        }
        // Will update to 0 if scrobbling ENABLED or no new songs
        // To > 0 if scrobbling disabled
        [menu updateScrobblingItemWith:unscrobbledCount];
    }
    [database close];
}

@end
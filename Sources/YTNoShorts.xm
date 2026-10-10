#import <YouTubeHeader/YTCommandResponderEvent.h>
#import <YouTubeHeader/YTICommand.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTIGuideResponse.h>
#import <YouTubeHeader/YTIGuideResponseSupportedRenderers.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import "uYouPlus.h"

@interface YTReelWatchRootViewController : UIViewController
@end

# pragma mark - Hide Shorts tab

%group gBlockShortsTab
static void removeShortsTab(YTIGuideResponse *response) {
    for (YTIGuideResponseSupportedRenderers *guideRenderers in [response itemsArray]) {
        NSMutableArray <YTIPivotBarSupportedRenderers *> *items = [[guideRenderers pivotBarRenderer] itemsArray];
        [items removeObjectsAtIndexes:[items indexesOfObjectsPassingTest:^BOOL(YTIPivotBarSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
            return [[[renderers pivotBarItemRenderer] pivotIdentifier] isEqualToString:@"FEshorts"];
        }]];
    }
}
%hook YTGuideServiceCoordinator
- (void)handleResponse:(YTIGuideResponse *)response withCompletion:(id)completion {
    removeShortsTab(response);
    %orig(response, completion);
}
- (void)handleResponse:(YTIGuideResponse *)response error:(id)error completion:(id)completion {
    removeShortsTab(response);
    %orig(response, error, completion);
}
%end
%end

# pragma mark - Remove Shorts shelves and cells from feeds

%group gBlockShortsInFeeds
static BOOL isShortsDescription(NSString *description) {
    // Shorts in the watch history page are left alone, removing them breaks its layout.
    if ([description containsString:@"history*"]) return NO;
    for (NSString *str in @[
        @"#shorts",
        @"6Shorts",
        @"reel_shelf",
        @"shorts_grid",
        @"shorts_lockup",
        @"shorts_shelf",
        @"shorts_video_cell"
    ])
        if ([description containsString:str]) return YES;
    return NO;
}

static BOOL isShortsRenderer(YTIElementRenderer *elementRenderer) {
    return elementRenderer && isShortsDescription([elementRenderer description]);
}

static NSMutableArray *filteredSections(NSArray *array) {
    NSMutableArray *newArray = [array mutableCopy];
    NSIndexSet *removeIndexes = [newArray indexesOfObjectsPassingTest:^BOOL(id sectionRenderer, NSUInteger idx, BOOL *stop) {
        NSMutableArray *itemsArray = nil;
        if ([sectionRenderer isKindOfClass:%c(YTIShelfRenderer)])
            itemsArray = ((YTIShelfRenderer *)sectionRenderer).content.horizontalListRenderer.itemsArray;
        else if ([sectionRenderer isKindOfClass:%c(YTIItemSectionRenderer)])
            itemsArray = ((YTIItemSectionRenderer *)sectionRenderer).contentsArray;
        if (itemsArray.count == 0) return NO;
        NSIndexSet *shortsIndexes = [itemsArray indexesOfObjectsPassingTest:^BOOL(id item, NSUInteger idx2, BOOL *stop2) {
            return [item respondsToSelector:@selector(elementRenderer)] && isShortsRenderer([item elementRenderer]);
        }];
        [itemsArray removeObjectsAtIndexes:shortsIndexes];
        return shortsIndexes.count > 0 && itemsArray.count == 0;
    }];
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%hook YTInnerTubeCollectionViewController
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    NSMutableArray *sectionRenderers = [self valueForKey:@"_sectionRenderers"];
    [self setValue:filteredSections(sectionRenderers) forKey:@"_sectionRenderers"];
    %orig;
}
- (void)addSectionsFromArray:(NSArray *)array {
    %orig(filteredSections(array));
}
%end

// Catches Shorts elements nested in containers that the section filter above doesn't reach.
%hook YTIElementRenderer
- (NSData *)elementData {
    return isShortsDescription([self description]) ? nil : %orig;
}
%end
%end

# pragma mark - Open Shorts in the regular player

%group gBlockShortsPlayer
static YTICommand *regularWatchCommandForShortsCommand(YTICommand *command) {
    if (![command respondsToSelector:@selector(reelWatchEndpoint)]) return command;
    NSString *videoId = command.reelWatchEndpoint.videoId;
    if (videoId.length == 0) return command;
    YTICommand *watchCommand = [%c(YTICommand) watchNavigationEndpointWithVideoID:videoId];
    if (!watchCommand) return command;
    watchCommand.clickTrackingParams = command.clickTrackingParams;
    return watchCommand;
}

%hook YTCommandResponderEvent
+ (instancetype)eventWithCommand:(YTICommand *)command entry:(id)entry sendClick:(BOOL)sendClick firstResponder:(id)firstResponder {
    return %orig(regularWatchCommandForShortsCommand(command), entry, sendClick, firstResponder);
}
+ (instancetype)eventWithCommand:(YTICommand *)command fromView:(UIView *)view entry:(id)entry sendClick:(BOOL)sendClick firstResponder:(id)firstResponder {
    return %orig(regularWatchCommandForShortsCommand(command), view, entry, sendClick, firstResponder);
}
%end

// Shorts can still be opened through paths that bypass YTCommandResponderEvent, so close the Shorts player whenever it shows up.
%hook YTReelWatchRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UINavigationController *navigationController = self.navigationController;
    if (navigationController.topViewController == self && navigationController.viewControllers.count > 1)
        [navigationController popViewControllerAnimated:NO];
    else if (self.presentingViewController)
        [self dismissViewControllerAnimated:NO completion:nil];
}
%end
%end

%ctor {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[kBlockShortsTab, kBlockShortsInFeeds, kBlockShortsPlayer]) {
        if (![defaults objectForKey:key]) [defaults setBool:YES forKey:key];
    }

    // YTReExplore already removes the Shorts tab and needs to find it to insert the Explore tab in its place.
    if (IS_ENABLED(kBlockShortsTab) && !IS_ENABLED(kReExplore)) {
        %init(gBlockShortsTab);
    }
    if (IS_ENABLED(kBlockShortsInFeeds)) {
        %init(gBlockShortsInFeeds);
    }
    if (IS_ENABLED(kBlockShortsPlayer)) {
        %init(gBlockShortsPlayer);
    }
}

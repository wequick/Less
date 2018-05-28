//
//  PBRowDelegate.m
//  Pbind <https://github.com/wequick/Pbind>
//
//  Created by Galen Lin on 22/12/2016.
//  Copyright (c) 2015-present, Wequick.net. All rights reserved.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "PBRowDelegate.h"
#import "UIView+Pbind.h"
#import "UIView+PBAction.h"
#import "PBSection.h"
#import "PBActionStore.h"
#import "PBCollectionView.h"
#import "PBDataFetcher.h"
#import "PBDataFetching.h"
#import "PBHeaderFooterMapper.h"
#import "PBSectionView.h"
#import "PBLoadMoreControlMapper.h"
#import "PBRefreshControlMapper.h"
#import "PBRefreshControl.h"

@interface PBRowDataSource (Private)

- (UICollectionViewCell *)_collectionView:(PBCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath reusing:(BOOL)reusing;
- (void)_updateCell:(UICollectionViewCell *)cell forIndexPath:(NSIndexPath *)indexPath withData:(id)data item:(PBRowMapper *)item context:(UIView *)context;

@end

@implementation PBRowDelegate
{
    NSMutableDictionary<NSString *, UICollectionViewCell *> *_placeholderCells;
}

@synthesize receiver;

static const CGFloat kMinRefreshControlDisplayingTime = .75f;

#pragma mark - Common

- (instancetype)initWithDataSource:(PBRowDataSource *)dataSource {
    if (self = [super init]) {
        self.dataSource = dataSource;
    }
    return self;
}

#pragma mark - Paging

- (void)scrollViewDidScroll:(UIScrollView<PBRowPaging> *)pagingView {
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver scrollViewDidScroll:pagingView];
    }
    
    if (pagingView.superview == nil) {
        return;
    }
    
    if (pagingView.refresh != nil) {
        // Pull down to refresh
        [self checkIfNeedsRefreshForPagingView:pagingView];
    }
    
    if (pagingView.more != nil) {
        // Pull up to load more
        [self checkIfNeedsLoadMoreForPagingView:pagingView];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView<PBRowPaging> *)pagingView willDecelerate:(BOOL)decelerate {
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver scrollViewDidEndDragging:pagingView willDecelerate:decelerate];
    }
    
    if (_flags.usesCustomRefreshControl) {
        PBRefreshControl *refreshControl = (id) _refreshControl;
        if (refreshControl.reached) {
            refreshControl.reached = NO;
            [self beginRefreshingForPagingView:pagingView];
        }
    }
}

- (void)checkIfNeedsRefreshForPagingView:(UIScrollView<PBRowPaging> *)pagingView {
    if (_refreshMapper == nil) {
        _refreshMapper = [PBRefreshControlMapper mapperWithDictionary:pagingView.refresh];
    }
    
    id data = pagingView.rootData;
    PBRowMapper *mapper = _refreshMapper;
    [mapper updateWithData:data owner:pagingView context:pagingView];
    
    if (_refreshControl == nil) {
        if (mapper.layout != nil || mapper.height > 0) {
            // Use custom refresh control
            PBRefreshControl *refreshControl = (id)[mapper createView];
            if (![refreshControl isKindOfClass:[PBRefreshControl class]]) {
                NSLog(@"Pbind: Requires a <PBRefreshControl> but got <%@>.", _refreshControl.class);
                return;
            }
            
            [mapper initPropertiesForTarget:refreshControl];
            _flags.usesCustomRefreshControl = 1;
            _refreshControl = refreshControl;
        } else {
            _flags.usesCustomRefreshControl = 0;
            _refreshControl = (id) [[UIRefreshControl alloc] init];
        }
        
        [_refreshControl addTarget:self action:@selector(refreshControlDidReleased:) forControlEvents:UIControlEventValueChanged];
        [pagingView addSubview:_refreshControl];
    }
    
    if (_flags.usesCustomRefreshControl) {
        PBRefreshControl *refreshControl = (id) _refreshControl;
        if ([refreshControl isRefreshing]) {
            CGFloat offset = MAX(-pagingView.contentOffset.y, 0);
            offset = MIN(offset, refreshControl.frame.size.height + _originalInsetTop);
            pagingView.contentInset = UIEdgeInsetsMake(offset, 0.0f, 0.0f, 0.0f);
            return;
        }
        
        if ([pagingView isDragging]) {
            [mapper mapPropertiesToTarget:refreshControl withData:data owner:pagingView context:pagingView];
            CGFloat pulledDownDistance = -pagingView.contentOffset.y - pagingView.contentInset.top;
            if (pulledDownDistance > 0) {
                CGFloat height = [mapper heightForView:refreshControl withData:data];
                refreshControl.frame = CGRectMake(0, -height, pagingView.frame.size.width, height);
                refreshControl.hidden = NO;
            } else {
                refreshControl.hidden = YES;
            }
            
            refreshControl.complected = NO;
            [refreshControl pagingView:pagingView didPullDownWithDistance:pulledDownDistance];
            
            if (pulledDownDistance >= refreshControl.beginDistance) {
                refreshControl.reached = YES;
            } else {
                refreshControl.reached = NO;
            }
            
            if (_originalInsetTop == 0) {
                _originalInsetTop = pagingView.contentInset.top;
            } else if (pagingView.contentInset.top != _originalInsetTop) {
                UIEdgeInsets insets = pagingView.contentInset;
                insets.top = _originalInsetTop;
                pagingView.contentInset = insets;
            }
        }
    }
}

- (void)checkIfNeedsLoadMoreForPagingView:(UIScrollView<PBRowPaging> *)pagingView {
    
    if (![pagingView isDragging]) {
        return;
    }
    
    if (_moreMapper == nil) {
        _moreMapper = [PBLoadMoreControlMapper mapperWithDictionary:pagingView.more];
    }
    
    PBRowControlMapper *moreMapper = _moreMapper;
    id data = pagingView.rootData;
    [moreMapper updateWithData:data owner:pagingView context:pagingView];
    
    if (_loadMoreControl == nil) {
        PBLoadMoreControl *moreControl = (id) [moreMapper createView];
        if (![moreControl isKindOfClass:[PBLoadMoreControl class]]) {
            NSLog(@"Pbind: Requires a <PBLoadMoreControl> but got <%@>.", moreControl.class);
            return;
        }
        
        [moreMapper initPropertiesForTarget:moreControl];
        [moreControl addTarget:self action:@selector(loadMoreControlDidReleased:) forControlEvents:UIControlEventValueChanged];
        [pagingView addSubview:moreControl];
        _loadMoreControl = moreControl;
    }
    
    CGPoint contentOffset = pagingView.contentOffset;
    UIEdgeInsets contentInset = pagingView.contentInset;
    CGFloat height = pagingView.bounds.size.height;
    CGFloat pulledUpDistance = (contentOffset.y + contentInset.top + height) - MAX((pagingView.contentSize.height + contentInset.bottom + contentInset.top), height);
    CGFloat moreControlTriggerThreshold = _loadMoreControl.beginDistance;
    CGFloat moreControlInitialThreshold = MIN(0, moreControlTriggerThreshold);
    if (pulledUpDistance > moreControlInitialThreshold) {
        CGFloat height = [moreMapper heightForView:_loadMoreControl withData:data];
        CGRect frame = CGRectMake(0, pagingView.contentSize.height, pagingView.frame.size.width, height);
        _loadMoreControl.frame = frame;
        _loadMoreControl.hidden = NO;
        [moreMapper mapPropertiesToTarget:_loadMoreControl withData:data owner:pagingView context:pagingView];
    } else {
        _loadMoreControl.hidden = YES;
    }
    
    if (pulledUpDistance >= moreControlTriggerThreshold) {
        if ([_loadMoreControl isEnding] || [_loadMoreControl isLoading]) {
            return;
        }
        
        [_loadMoreControl beginLoading];
        [_loadMoreControl sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

- (void)beginRefreshingForPagingView:(UIScrollView<PBRowPaging> *)pagingView {
    if (_refreshControl == nil) {
        return;
    }
    
    if ([_refreshControl isRefreshing]) {
        return;
    }
    
    [_refreshControl beginRefreshing];
    [_refreshControl sendActionsForControlEvents:UIControlEventValueChanged];
    
    if (_flags.usesCustomRefreshControl) {
        // Adjust content insets
        UIEdgeInsets insets = pagingView.contentInset;
        insets.top = _originalInsetTop + _refreshControl.frame.size.height;
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:.25f animations:^{
                pagingView.contentInset = insets;
            }];
        });
    } else {
        // Adjust content offset
        CGPoint offset = pagingView.contentOffset;
        offset.y = -pagingView.contentInset.top - _refreshControl.bounds.size.height;
        pagingView.contentOffset = offset;
    }
}

- (void)refreshControlDidReleased:(UIControl<PBRefreshing> *)sender {
    NSDate *start = [NSDate date];
    
    UIScrollView<PBRowPaging, PBDataFetching> *pagingView = (id)self.dataSource.owner;
    if ([pagingView isFetching] || pagingView.clients == nil) {
        [self endRefreshingControl:sender fromBeginTime:start];
        return;
    }
    
    // Reset paging params
    pagingView.page = 0;
    [pagingView pb_mapData:pagingView.data forKey:@"pagingParams"];
    
    [pagingView.fetcher fetchDataWithTransformation:^id(id data, NSError *error) {
        [self endRefreshingControl:sender fromBeginTime:start];
        return data;
    }];
}

- (void)endRefreshingControl:(UIControl<PBRefreshing> *)control fromBeginTime:(NSDate *)beginTime {
    NSTimeInterval spentTime = [[NSDate date] timeIntervalSinceDate:beginTime];
    if (spentTime < kMinRefreshControlDisplayingTime) {
        NSTimeInterval fakeAwaitingTime = kMinRefreshControlDisplayingTime - spentTime;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(fakeAwaitingTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [control endRefreshing];
            if (_flags.usesCustomRefreshControl) {
                [self adjustInsetForPagingViewAfterRefresh:(id)self.dataSource.owner];
            }
        });
    } else {
        [control endRefreshing];
        if (_flags.usesCustomRefreshControl) {
            [self adjustInsetForPagingViewAfterRefresh:(id)self.dataSource.owner];
        }
    }
    
    if (_loadMoreControl != nil) {
        [_loadMoreControl setEnabled:YES];
    }
}

- (void)loadMoreControlDidReleased:(UIRefreshControl *)sender {
    UIScrollView<PBRowPaging, PBDataFetching> *pagingView = (id)(self.dataSource.owner);
    
    UIEdgeInsets insets = pagingView.contentInset;
    insets.bottom += _loadMoreControl.bounds.size.height;
    pagingView.contentInset = insets;
    
    _loadMoreBeginTime = [[NSDate date] timeIntervalSince1970];
    _flags.loadingMore = 1;
    if (pagingView.fetcher == nil) {
        [pagingView reloadData];
        return;
    }
    
    // Increase page
    pagingView.page++;
    [pagingView pb_mapData:pagingView.data forKey:@"pagingParams"];
    [pagingView.fetcher fetchDataWithTransformation:^id(id data, NSError *error) {
        if (pagingView.listKey != nil) {
            NSMutableArray *list = [NSMutableArray arrayWithArray:[self.dataSource list]];
            [list addObjectsFromArray:[data valueForKey:pagingView.listKey]];
            if ([data isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *newData = [NSMutableDictionary dictionaryWithDictionary:data];
                [newData setValue:list forKey:pagingView.listKey];
                data = newData;
            } else {
                [data setValue:list forKey:pagingView.listKey];
            }
        } else {
            NSMutableArray *list = [NSMutableArray arrayWithArray:pagingView.data];
            [list addObjectsFromArray:data];
            data = list;
        }
        
        return data;
    }];
}

- (void)endPullingForPagingView:(UIScrollView<PBRowPaging> *)pagingView {
    NSTimeInterval spentTime = [[NSDate date] timeIntervalSince1970] - _loadMoreBeginTime;
    if (spentTime < kMinRefreshControlDisplayingTime) {
        NSTimeInterval fakeAwaitingTime = kMinRefreshControlDisplayingTime - spentTime;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(fakeAwaitingTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self endLoadingMore:pagingView];
        });
    } else {
        [self endLoadingMore:pagingView];
    }
}

- (void)endLoadingMore:(UIScrollView<PBRowPaging> *)pagingView {
    _flags.loadingMore = 0;
    [_loadMoreControl endLoading];
    pagingView.data = [pagingView.data arrayByAddingObjectsFromArray:pagingView.data];
    [pagingView reloadData];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Adjust content insets
        UIEdgeInsets insets = pagingView.contentInset;
        insets.bottom -= _loadMoreControl.bounds.size.height;
        pagingView.contentInset = insets;
    });
}

- (void)adjustInsetForPagingViewAfterRefresh:(UIScrollView<PBRowPaging> *)pagingView {
    if (_flags.usesCustomRefreshControl) {
        PBRefreshControl *refreshControl = (id) _refreshControl;
        refreshControl.complected = YES;
        // Adjust content insets
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.25];
        UIEdgeInsets insets = pagingView.contentInset;
        insets.top = _originalInsetTop;
        pagingView.contentInset = insets;
        [UIView commitAnimations];
    }
}

- (BOOL)pagingViewCanReloadData:(UIScrollView<PBRowPaging> *)pagingView {
    if (_flags.loadingMore) {
        [self endPullingForPagingView:pagingView];
        return NO;
    }
    return YES;
}

- (void)reset {
    _moreMapper = nil;
    if (_loadMoreControl != nil) {
        [_loadMoreControl removeFromSuperview];
        _loadMoreControl = nil;
    }
}

#pragma mark - UITableView
#pragma mark - Display customization

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Hides last separator
    if (self.dataSource.sections.count > indexPath.section) {
        PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:indexPath.section];
        if (mapper.hidesLastSeparator && indexPath.row == mapper.rowCount - 1
            && [self.dataSource dataAtIndexPath:indexPath] != nil) {
            [self _hidesBottomSeparatorForCell:cell];
        }
    }
    
    // Forward delegate
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }
}
//- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section NS_AVAILABLE_IOS(6_0) {
//    
//}
//- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section NS_AVAILABLE_IOS(6_0) {
//    
//}
//- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath*)indexPath NS_AVAILABLE_IOS(6_0) {
//    
//}
//- (void)tableView:(UITableView *)tableView didEndDisplayingHeaderView:(UIView *)view forSection:(NSInteger)section NS_AVAILABLE_IOS(6_0) {
//    
//}
//- (void)tableView:(UITableView *)tableView didEndDisplayingFooterView:(UIView *)view forSection:(NSInteger)section NS_AVAILABLE_IOS(6_0) {
//    
//}

#pragma mark - Variable height support

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView heightForRowAtIndexPath:indexPath];
    }
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row == nil) {
        return tableView.rowHeight;
    }
    
    return [row heightForData:tableView.data withRowDataSource:self.dataSource indexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView heightForHeaderInSection:section];
    }
    
    if (self.dataSource.sections != nil) {
        if (self.dataSource.sections.count <= section) {
            return 0;
        }
        
        PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
        if (mapper.header == nil) {
            return 0;
        }
        return [mapper.header heightForData:tableView.data];
    } else if ([tableView.data isKindOfClass:[PBSection class]]) {
        return tableView.sectionHeaderHeight;
    } else if (self.dataSource.row != nil || self.dataSource.rows != nil) {
        return 0;
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        return tableView.sectionHeaderHeight;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView heightForFooterInSection:section];
    }
    
    if (self.dataSource.sections.count <= section) {
        return 0;
    }
    
    PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
    if (mapper.footer == nil) {
        return 0;
    }
    return [mapper.footer heightForData:tableView.data];
}

// Use the estimatedHeight methods to quickly calcuate guessed values which will allow for fast load times of the table.
// If these methods are implemented, the above -tableView:heightForXXX calls will be deferred until views are ready to be displayed, so more expensive logic can be placed there.
- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(7_0) {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView estimatedHeightForRowAtIndexPath:indexPath];
    }
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row == nil) {
        return tableView.estimatedRowHeight;
    }
    
    if (row.hidden) {
        return 0;
    }
    
    if (row.estimatedHeight == UITableViewAutomaticDimension) {
        if (tableView.estimatedRowHeight > 0) {
            return tableView.estimatedRowHeight;
        }
        return UITableViewAutomaticDimension;
    }
    
    return row.estimatedHeight;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForHeaderInSection:(NSInteger)section NS_AVAILABLE_IOS(7_0) {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView estimatedHeightForHeaderInSection:section];
    }
    
    PBRowMapper *row = [self.dataSource.sections objectAtIndex:section].header;
    if (row == nil) {
        return tableView.estimatedSectionHeaderHeight;
    }
    
    if (row.hidden) {
        return 0;
    }
    
    if (row.estimatedHeight == UITableViewAutomaticDimension) {
        if (tableView.estimatedSectionHeaderHeight > 0) {
            return tableView.estimatedSectionHeaderHeight;
        }
        return UITableViewAutomaticDimension;
    }
    
    return row.estimatedHeight;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForFooterInSection:(NSInteger)section NS_AVAILABLE_IOS(7_0) {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView estimatedHeightForFooterInSection:section];
    }
    
    PBRowMapper *row = [self.dataSource.sections objectAtIndex:section].footer;
    if (row == nil) {
        return tableView.estimatedSectionHeaderHeight;
    }
    
    if (row.hidden) {
        return 0;
    }
    
    if (row.estimatedHeight == UITableViewAutomaticDimension) {
        if (tableView.estimatedSectionHeaderHeight > 0) {
            return tableView.estimatedSectionHeaderHeight;
        }
        return UITableViewAutomaticDimension;
    }
    
    return row.estimatedHeight;
}

// Section header & footer information. Views are preferred over title should you decide to provide both

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView viewForHeaderInSection:section];
    }
    
    if (self.dataSource.sections.count <= section) {
        return nil;
    }
    
    PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
    if (mapper.header == nil) {
        return nil;
    }
    
    return [self tableView:tableView viewForHeaderFooterInSection:section withMapper:mapper.header isHeader:YES];
}// custom view for header. will be adjusted to default or specified header height

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView viewForFooterInSection:section];
    }
    
    if (self.dataSource.sections.count <= section) {
        return nil;
    }
    
    PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
    if (mapper.footer == nil) {
        return nil;
    }
    
    return [self tableView:tableView viewForHeaderFooterInSection:section withMapper:mapper.footer isHeader:NO];
}// custom view for footer. will be adjusted to default or specified footer height

- (UIView *)tableView:(UITableView *)tableView viewForHeaderFooterInSection:(NSInteger)section withMapper:(PBHeaderFooterMapper *)mapper isHeader:(BOOL)isHeader {
    PBSectionView *sectionView = [[PBSectionView alloc] init];
    [mapper updateWithData:tableView.data owner:nil context:tableView];
    
    // Create content view
    UIView *contentView = nil;
    NSString *title = mapper.title;
    if (title != nil && mapper.layout == nil) {
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = title;
        titleLabel.numberOfLines = 0;
        if (mapper.titleFont != nil) {
            titleLabel.font = mapper.titleFont;
        }
        if (mapper.titleColor != nil) {
            titleLabel.textColor = mapper.titleColor;
        }
        if (mapper.backgroundColor != nil) {
            sectionView.backgroundColor = mapper.backgroundColor;
        }
        contentView = titleLabel;
    } else {
        // Custom footer view
        contentView = [[mapper.viewClass alloc] init];
        if (mapper.layoutMapper != nil) {
            [mapper.layoutMapper renderToView:contentView];
        }
        
        [mapper initPropertiesForTarget:contentView];
        [mapper mapPropertiesToTarget:contentView withData:tableView.data owner:contentView context:tableView];
    }
    
    // Set content view margin
    [sectionView addSubview:contentView];
    UIEdgeInsets margin = mapper.margin;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [sectionView addConstraint:[NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:sectionView attribute:NSLayoutAttributeTop multiplier:1 constant:margin.top]];
    [sectionView addConstraint:[NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:sectionView attribute:NSLayoutAttributeLeft multiplier:1 constant:margin.left]];
    [sectionView addConstraint:[NSLayoutConstraint constraintWithItem:sectionView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:margin.bottom]];
    [sectionView addConstraint:[NSLayoutConstraint constraintWithItem:sectionView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeRight multiplier:1 constant:margin.right]];
    
    sectionView.section = section;
    return sectionView;
}

//#pragma mark - Accessories (disclosures).

//- (UITableViewCellAccessoryType)tableView:(UITableView *)tableView accessoryTypeForRowWithIndexPath:(NSIndexPath *)indexPath NS_DEPRECATED_IOS(2_0, 3_0) __TVOS_PROHIBITED;
//- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath;

#pragma mark - Selection

// -tableView:shouldHighlightRowAtIndexPath: is called when a touch comes down on a row.
// Returning NO to that message halts the selection process and does not cause the currently selected row to lose its selected look while the touch is down.
//- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(6_0);
//- (void)tableView:(UITableView *)tableView didHighlightRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(6_0);
//- (void)tableView:(UITableView *)tableView didUnhighlightRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(6_0);

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *newIndexPath = indexPath;
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.willSelectActionMapper != nil) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [self dispatchAction:row.willSelectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        newIndexPath = [self.receiver tableView:tableView willSelectRowAtIndexPath:indexPath];
    }
    
    return newIndexPath;
}

- (nullable NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *newIndexPath = indexPath;
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.willDeselectActionMapper != nil) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [self dispatchAction:row.willDeselectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        newIndexPath = [self.receiver tableView:tableView willDeselectRowAtIndexPath:indexPath];
    }
    
    return newIndexPath;
}

// Called after the user changes the selection.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.selectActionMapper != nil) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [self dispatchAction:row.selectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver tableView:tableView didSelectRowAtIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.deselectActionMapper != nil) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        [self dispatchAction:row.deselectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver tableView:tableView didSelectRowAtIndexPath:indexPath];
    }
}

#pragma mark - Editing

- (nullable NSArray<UITableViewRowAction *> *)tableView:(UITableView<PBRowMapping> *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.editActionMappers == nil) {
        return nil;
    }
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSMutableArray *editActions = [[NSMutableArray alloc] initWithCapacity:row.editActionMappers.count];
    for (PBRowActionMapper *actionMapper in [row.editActionMappers reverseObjectEnumerator]) {
        [actionMapper updateWithData:tableView.rootData owner:cell context:tableView];
        UITableViewRowAction *rowAction = [UITableViewRowAction rowActionWithStyle:actionMapper.style title:actionMapper.title handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            tableView.editingIndexPath = indexPath;
            [self dispatchAction:actionMapper forCell:cell atIndexPath:indexPath];
        }];
        if (actionMapper.backgroundColor != nil) {
            rowAction.backgroundColor = actionMapper.backgroundColor;
        }
        [editActions addObject:rowAction];
    }
    
    return editActions;
}// supercedes -tableView:titleForDeleteConfirmationButtonForRowAtIndexPath: if return value is non-nil

// Controls whether the background is indented while editing.  If not implemented, the default is YES.  This is unrelated to the indentation level below.  This method only applies to grouped style table views.
//- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;

// The willBegin/didEnd methods are called whenever the 'editing' property is automatically changed by the table (allowing insert/delete/move). This is done by a swipe activating a single row
//- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath __TVOS_PROHIBITED;
//- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(nullable NSIndexPath *)indexPath __TVOS_PROHIBITED;

//#pragma mark - Moving/reordering

// Allows customization of the target row for a particular row as it is being moved/reordered
//- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath;

//#pragma mark - Indentation

//- (NSInteger)tableView:(UITableView *)tableView indentationLevelForRowAtIndexPath:(NSIndexPath *)indexPath; // return 'depth' of row for hierarchies

//#pragma mark - Copy/Paste.  All three methods must be implemented by the delegate.

//- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(5_0);
//- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender NS_AVAILABLE_IOS(5_0);
//- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender NS_AVAILABLE_IOS(5_0);

//#pragma mark - Focus

//- (BOOL)tableView:(UITableView *)tableView canFocusRowAtIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(9_0);
//- (BOOL)tableView:(UITableView *)tableView shouldUpdateFocusInContext:(UITableViewFocusUpdateContext *)context NS_AVAILABLE_IOS(9_0);
//- (void)tableView:(UITableView *)tableView didUpdateFocusInContext:(UITableViewFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator NS_AVAILABLE_IOS(9_0);
//- (nullable NSIndexPath *)indexPathForPreferredFocusedViewInTableView:(UITableView *)tableView NS_AVAILABLE_IOS(9_0);


#pragma mark - UICollectionView


#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver collectionView:collectionView willDisplayCell:cell forItemAtIndexPath:indexPath];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    BOOL shouldSelect = YES;
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.willSelectActionMapper != nil) {
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        [self dispatchAction:row.willSelectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        shouldSelect = [self.receiver collectionView:collectionView shouldSelectItemAtIndexPath:indexPath];
    }
    
    return shouldSelect;
}

- (void)collectionView:(PBCollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.selectActionMapper != nil) {
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        [self dispatchAction:row.selectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    id selectedData = [self.dataSource dataAtIndexPath:indexPath];
    if (collectionView.allowsMultipleSelection) {
        NSMutableArray *datas = [NSMutableArray arrayWithArray:collectionView.selectedDatas];
        if (![datas containsObject:selectedData]) {
            [datas addObject:selectedData];
        }
        collectionView.selectedDatas = datas;
    }
    collectionView.selectedData = selectedData;
    collectionView.selectedIndexPath = indexPath;
    [collectionView.pb_valueControl sendActionsForControlEvents:UIControlEventValueChanged];
    
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver collectionView:collectionView didSelectItemAtIndexPath:indexPath];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    BOOL shouldDeselect = YES;
    
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.willDeselectActionMapper != nil) {
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        [self dispatchAction:row.willDeselectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    if ([self.receiver respondsToSelector:_cmd]) {
        shouldDeselect = [self.receiver collectionView:collectionView shouldDeselectItemAtIndexPath:indexPath];
    }
    
    return shouldDeselect;
}

- (void)collectionView:(PBCollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    PBRowMapper *row = [self.dataSource rowAtIndexPath:indexPath];
    if (row.deselectActionMapper != nil) {
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        [self dispatchAction:row.deselectActionMapper forCell:cell atIndexPath:indexPath];
    }
    
    id selectedData = [self.dataSource dataAtIndexPath:indexPath];
    if (collectionView.allowsMultipleSelection) {
        NSMutableArray *datas = [NSMutableArray arrayWithArray:collectionView.selectedDatas];
        [datas removeObject:selectedData];
        collectionView.selectedDatas = datas;
    }
    
    collectionView.deselectedData = [self.dataSource dataAtIndexPath:indexPath];
    collectionView.selectedIndexPath = nil;
    
    [collectionView.pb_valueControl sendActionsForControlEvents:UIControlEventValueChanged];
    
    if ([self.receiver respondsToSelector:_cmd]) {
        [self.receiver collectionView:collectionView didDeselectItemAtIndexPath:indexPath];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout referenceSizeForHeaderInSection:section];
    }
    
    PBSectionMapper *sectionMapper = [self.dataSource.sections objectAtIndex:section];
    return [self referenceSizeForCollectionView:collectionView withElementMapper:sectionMapper.header];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout referenceSizeForFooterInSection:(NSInteger)theSection {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout referenceSizeForFooterInSection:theSection];
    }
    
    PBSectionMapper *section = [self.dataSource.sections objectAtIndex:theSection];
    return [self referenceSizeForCollectionView:collectionView withElementMapper:section.footer];
}

- (CGSize)referenceSizeForCollectionView:(UICollectionView *)collectionView withElementMapper:(PBRowMapper *)element {
    if (element == nil || (element.layout == nil && element.viewClass == [UICollectionReusableView class])) {
        return CGSizeZero;
    }
    return CGSizeMake(collectionView.bounds.size.width, element.height);
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout sizeForItemAtIndexPath:indexPath];
    }
    
    PBSectionMapper *section = [self.dataSource.sections objectAtIndex:indexPath.section];
    PBRowMapper *item = [self.dataSource rowAtIndexPath:indexPath];
    
    // Average
    if (section.numberOfColumns != 0) {
        NSInteger numberOfGaps = section.numberOfColumns - 1;
        CGFloat widthWeight = item.widthWeight;
        CGFloat width = floor((collectionView.bounds.size.width - numberOfGaps * section.inner.width - section.inset.left - section.inset.right) * widthWeight);
        CGFloat height = item.height;
        if (height < 0) {
            CGFloat ratio = item.ratio == 0 ? 1 : item.ratio;
            height = width / ratio + item.additionalHeight;
        }
        return CGSizeMake(width, height);
    }

    // Undefined
    if ([item isWidthUnset] && [item isHeightUnset]) {
        return collectionViewLayout.itemSize;
    }
    
    // Explicit
    id data = collectionView.data;
    BOOL isAutoWidth = NO, isAutoHeight = NO;
    CGFloat itemHeight;
    CGFloat itemWidth = [item widthForData:data withRowDataSource:self.dataSource indexPath:indexPath];
    if (item.ratio > 0 || item.additionalHeight != 0) {
        CGFloat ratio = item.ratio == 0 ? 1 : item.ratio;
        itemHeight = itemWidth / ratio + item.additionalHeight;
    } else {
        itemHeight = [item heightForData:data withRowDataSource:self.dataSource indexPath:indexPath];
    }
    
    if (itemWidth == -2) {
        itemWidth = collectionView.bounds.size.width - section.inset.left - section.inset.right; // fill
    } else if (itemWidth == -1) {
        itemWidth = 1.f; // auto resizing
        isAutoWidth = YES;
    }
    
    CGFloat maxHeight = collectionView.bounds.size.height - section.inset.top - section.inset.bottom;
    if (itemHeight == -2) {
        itemHeight = maxHeight; // fill
    } else if (itemHeight == -1) {
        itemHeight = 1.f; // auto resizing
        isAutoHeight = YES;
    }
    
    if (@available(iOS 11, *)) {
        
    } else {
        if (isAutoWidth || isAutoHeight) {
            if (_placeholderCells == nil) {
                _placeholderCells = [[NSMutableDictionary alloc] init];
            }
            UICollectionViewCell *placeholderCell = _placeholderCells[item.id];
            if (placeholderCell == nil) {
                placeholderCell = [self.dataSource _collectionView:(PBCollectionView *)collectionView cellForItemAtIndexPath:indexPath reusing:NO];
                _placeholderCells[item.id] = placeholderCell;
            } else {
                id itemData = [self.dataSource dataAtIndexPath:indexPath];
                [self.dataSource _updateCell:placeholderCell forIndexPath:indexPath withData:itemData item:item context:collectionView];
            }
            
            CGSize itemSize = [placeholderCell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
            if (!isAutoWidth) {
                itemSize.width = itemWidth;
            }
            if (!isAutoHeight) {
                itemSize.height = itemHeight;
            }
            if (itemSize.width <= 0) {
                itemSize.width = 1.f;
            }
            if (itemSize.height <= 0) {
                itemSize.height = 1.f;
            }
            return itemSize;
        }
    }
    
//    itemHeight = MIN(maxHeight, itemHeight);
    return CGSizeMake(itemWidth, itemHeight);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)sectionIndex {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout insetForSectionAtIndex:sectionIndex];
    }
    
    NSArray<PBSectionMapper *> *sections = self.dataSource.sections;
    if (sections != nil) {
        PBSectionMapper *section = [sections objectAtIndex:sectionIndex];
        UIEdgeInsets inset = section.inset;
        if (!UIEdgeInsetsEqualToEdgeInsets(inset, UIEdgeInsetsZero)) {
            if (sectionIndex + 1 < sections.count && section.rowCount == 0) {
                // If has next section, but current section is empty, then let the inset.right as 0 to pin two sections together.
                inset.right = 0;
            }
            return inset;
        }
    }
    
    return collectionViewLayout.sectionInset;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout minimumInteritemSpacingForSectionAtIndex:section];
    }
    
    if (self.dataSource.sections != nil) {
        PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
        CGSize size = mapper.inner;
        if (size.width >= 0) {
            return size.width;
        }
        
        if (mapper.numberOfColumns != 0) {
            PBRowMapper *item = [self.dataSource rowAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            if (item.width != 0) {
                CGFloat spacing = (collectionView.bounds.size.width - item.width * mapper.numberOfColumns - mapper.inset.left - mapper.inset.right) / (mapper.numberOfColumns - 1);
                return spacing;
            }
        }
    }
    
    return collectionViewLayout.minimumInteritemSpacing;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView layout:collectionViewLayout minimumLineSpacingForSectionAtIndex:section];
    }
    
    if (self.dataSource.sections != nil) {
        PBSectionMapper *mapper = [self.dataSource.sections objectAtIndex:section];
        CGSize size = mapper.inner;
        if (size.height >= 0) {
            return size.height;
        }
    }
    
    return collectionViewLayout.minimumLineSpacing;
}

#pragma mark - Helper

- (void)_hidesBottomSeparatorForCell:(UITableViewCell *)cell {
    for (UIView *subview in cell.subviews) {
        if (subview == cell.contentView) {
            continue;
        }
        
        subview.alpha = 0;
    }
}

- (void)dispatchAction:(PBActionMapper *)action forCell:(UIView *)cell atIndexPath:(NSIndexPath *)indexPath {
    [[PBActionStore defaultStore] dispatchActionWithActionMapper:action context:cell data:cell.rootData];
}

@end

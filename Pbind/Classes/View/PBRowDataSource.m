//
//  PBRowDataSource.m
//  Pbind <https://github.com/wequick/Pbind>
//
//  Created by Galen Lin on 22/12/2016.
//  Copyright (c) 2015-present, Wequick.net. All rights reserved.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "PBRowDataSource.h"
#import "PBSection.h"
#import "PBTableView.h"
#import "PBCollectionView.h"
#import "PBArray.h"
#import "PBInline.h"
#import "UIView+Pbind.h"
#import "PBValueParser.h"
#import "PBDataFetching.h"
#import "PBHeaderFooterMapper.h"
#import "UITableViewCell+PBIndexing.h"
#import "UICollectionViewCell+PBIndexing.h"
#import "_PBRowDataWrapper.h"

NSNotificationName const PBRowDataDidChangeNotification = @"PBRowDataDidChangeNotification";

typedef NS_ENUM(NSUInteger, PBRowInteractionType) {
    PBRowInteractionTypeInsert,
    PBRowInteractionTypeDelete,
    PBRowInteractionTypeUpdate,
};

@implementation PBRowDataSource

@synthesize receiver;

static const CGFloat kUITableViewRowAnimationDuration = .25f;

#pragma mark - Base

- (NSArray *)listForData:(id)data key:(NSString *)listKey {
    id list = data;
    if ([list isKindOfClass:[NSArray class]]) {
        return list;
    }
    
    if ([list isKindOfClass:[PBArray class]]) {
        list = [list list];
    }
    
    if ([list isKindOfClass:[NSArray class]]) {
        return list;
    }
    
    if (listKey == nil || ![list isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    list = [list objectForKey:listKey];
    return list;
}

- (NSArray *)list {
    id list = self.owner.data;
    if ([list isKindOfClass:[NSArray class]]) {
        return list;
    }
    
    if ([list isKindOfClass:[PBArray class]]) {
        list = [list list];
    }
    
    if ([list isKindOfClass:[NSArray class]]) {
        return list;
    }
    
    if (self.owner.listKey == nil || ![list isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    list = [list objectForKey:self.owner.listKey];
    return list;
}

- (PBRowMapper *)rowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.row != nil) {
        // Repeated row
        return self.row;
    } else if (self.rows != nil) {
        // Distinct row configured by `rows'
        return [self.rows objectAtIndex:indexPath.row];
    } else if (self.sections != nil) {
        // Distinct row configured by `sections'
        PBSectionMapper *section = [self.sections objectAtIndex:indexPath.section];
        if (section != nil) {
            if (section.rowConditions != nil) {
                id data = [self dataAtIndexPath:indexPath];
                for (NSDictionary *condition in section.rowConditions) {
                    NSString *flag = condition[@"if"];
                    if (isascii([flag characterAtIndex:0])) {
                        flag = [@"!!$" stringByAppendingString:flag];
                    }
                    PBExpression *exp = [PBExpression expressionWithString:flag];
                    BOOL matches = [[exp valueWithData:data] boolValue];
                    if (matches) {
                        return condition[@"rowMapper"];
                    }
                }
            } else if (section.row != nil) {
                if (section.emptyRow != nil && [self dataAtIndexPath:indexPath] == nil) {
                    return section.emptyRow;
                }
                return section.row;
            }
            return [section.rows objectAtIndex:indexPath.row];
        }
    }
    return nil;
}

- (id)dataAtIndexPath:(NSIndexPath *)indexPath
{
    id data = [self.owner data];
    if (self.row != nil) {
        // Repeated row
        if (data == nil) {
            return nil;
        }
        
        if ([data isKindOfClass:[NSArray class]]) {
            return [data objectAtIndex:indexPath.row];
        } else if ([data isKindOfClass:[PBSection class]]) {
            return [(PBSection *)data recordAtIndexPath:indexPath];
        } else {
            return [self list][indexPath.row];
        }
    } else if (self.rows != nil) {
        // Distinct row configured by `rows'
        if (data == nil) {
            return nil;
        }
        
        if ([data isKindOfClass:[PBArray class]]) {
            return [data list];
        }
        return data;
    } else if (self.sections != nil) {
        // Distinct row configured by `sections'
        PBSectionMapper *mapper = [self.sections objectAtIndex:indexPath.section];
        if (mapper != nil && mapper.data != nil) {
            data = mapper.data;
        }
        
        if (data == nil) {
            return nil;
        }
        
        if ([data isKindOfClass:[PBArray class]]) {
            data = [data list];
        }
        
        if ([data isKindOfClass:[NSArray class]]) {
            if ([data count] <= indexPath.row) {
                return nil;
            }
            data = [data objectAtIndex:indexPath.row];
        }
        
        return data;
    }
    
    return nil;
}

- (void)initRowMapper {
    if (_row != nil || _rows != nil || _sections != nil) {
        return;
    }
    
    PBRowMapper *row = _row;
    if (row != nil) {
        return;
    }
    
    NSDictionary *rowSource = self.owner.row;
    
    // Parsing rows: NSArray<NSDictionary> to NSArray<PBRowMapper>
    NSArray *rows = self.owner.rows;
    if ([rows count] > 0) {
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[rows count]];
        for (NSInteger index = 0; index < [rows count]; index++) {
            NSDictionary *dict = [rows objectAtIndex:index];
            if (rowSource != nil) {
                // Take the `row' as base mapper
                dict = [self dictionaryByMergingDictionary:rowSource withAnother:dict];
            }
            PBRowMapper *aRow = [PBRowMapper mapperWithDictionary:dict owner:self.owner];
            [temp addObject:aRow];
        }
        _rows = temp;
        if ([self.owner conformsToProtocol:@protocol(PBDataFetching)]) {
            [(id)self.owner setDataUpdated:YES];
        }
        return;
    }
    
    // Parsing sections: NSArray<NSDcitionary> to NSArray<PBSectionMapper>
    NSDictionary *section = self.owner.section;
    if (section != nil) {
        if (rowSource != nil) {
            section = [self dictionaryByMergingDictionary:@{@"row": rowSource} withAnother:section];
        }
    }
    
    NSArray *sections = self.owner.sections;
    NSUInteger sectionCount = 0;
    if (sections == nil) {
        if (section != nil) {
            sections = @[section];
            sectionCount = 1;
        }
    } else {
        sectionCount = sections.count;
        if (sectionCount > 0 && section != nil) {
            // Take the `section' as base
            NSMutableArray *mergedSections = [NSMutableArray arrayWithCapacity:sectionCount];
            for (NSDictionary *aSection in sections) {
                NSDictionary *mergedSection = [self dictionaryByMergingDictionary:section withAnother:aSection];
                [mergedSections addObject:mergedSection];
            }
            sections = mergedSections;
        }
    }
    
    if (sectionCount > 0) {
        NSMutableArray *temp = [NSMutableArray arrayWithCapacity:sectionCount];
        for (NSInteger sectionIndex = 0; sectionIndex < sectionCount; sectionIndex++) {
            NSDictionary *dict = [sections objectAtIndex:sectionIndex];
            PBSectionMapper *aSection = [PBSectionMapper mapperWithDictionary:dict owner:self.owner];
            NSDictionary *aRowSource = (id)aSection.row;
            
            if ([aSection.rows count] > 0) {
                NSMutableArray *rows = [NSMutableArray arrayWithCapacity:[aSection.rows count]];
                for (NSInteger index = 0; index < [aSection.rows count]; index++) {
                    NSDictionary *dict = [aSection.rows objectAtIndex:index];
                    if (aRowSource != nil) {
                        // Take the `row' as base mapper
                        dict = [self dictionaryByMergingDictionary:aRowSource withAnother:dict];
                        aSection.row = nil; // don't need any more.
                    }
                    PBRowMapper *aRow = [PBRowMapper mapperWithDictionary:dict owner:self.owner];
                    [rows addObject:aRow];
                }
                aSection.rows = rows;
            } else if (aRowSource != nil) {
                aSection.row = [PBRowMapper mapperWithDictionary:aRowSource owner:self.owner];
            }
            
            if (aSection.rowConditions != nil) {
                for (NSMutableDictionary *condition in aSection.rowConditions) {
                    condition[@"rowMapper"] = [PBRowMapper mapperWithDictionary:condition[@"row"] owner:self.owner];
                }
            }
            
            if (aSection.emptyRow != nil) {
                aSection.emptyRow = [PBRowMapper mapperWithDictionary:aSection.emptyRow owner:self.owner];
            }
            
            if (aSection.header != nil) {
                aSection.header = [PBHeaderFooterMapper mapperWithDictionary:aSection.header owner:self.owner];
            }
            if (aSection.footer != nil) {
                aSection.footer = [PBHeaderFooterMapper mapperWithDictionary:aSection.footer owner:self.owner];
            }
            [temp addObject:aSection];
        }
        _sections = temp;
        // Init section index titles
        NSMutableArray *titles = [NSMutableArray arrayWithCapacity:[temp count]];
        BOOL hasTitle = NO;
        for (PBSectionMapper *section in temp) {
            NSString *title;
            if (section.title == nil) {
                title = @"";
            } else {
                title = [section.title substringToIndex:1];
                hasTitle = YES;
            }
            [titles addObject:title];
        }
        if (hasTitle) {
            _sectionIndexTitles = titles;
        }
        if ([self.owner conformsToProtocol:@protocol(PBDataFetching)]) {
            [(id)self.owner setDataUpdated:YES];
        }
        return;
    }
    
    if (rowSource != nil) {
        _row = [PBRowMapper mapperWithDictionary:rowSource owner:self.owner];
    }
    if (_row == nil) {
        return;
    }
    
    if ([self.owner conformsToProtocol:@protocol(PBDataFetching)]) {
        [(id)self.owner setDataUpdated:YES];
    }
    return;
}

- (PBRowMapper *)row {
    [self initRowMapper];
    return _row;
}

- (NSArray<PBRowMapper *> *)rows {
    [self initRowMapper];
    return _rows;
}

- (NSArray<PBSectionMapper *> *)sections {
    [self initRowMapper];
    return _sections;
}

- (void)updateSections {
    [self initRowMapper];
    if (_sections != nil) {
        id data = self.owner.rootData;
        BOOL needsCheckDataUpdated = [self.owner respondsToSelector:@selector(setDataUpdated:)];
        for (PBSectionMapper *mapper in _sections) {
            id oldSectionData = mapper.data;
            [mapper updateWithData:data owner:self.owner context:self.owner];
            if (needsCheckDataUpdated && ![oldSectionData isEqual:mapper.data]) {
                [(id)self.owner setDataUpdated:YES];
            }
            if (mapper.footer != nil) {
                [mapper.footer updateWithData:data owner:self.owner context:self.owner];
            }
            
            // Auto width
            if (mapper.numberOfColumns > 0) {
                [self calculateItemWidthWeightsForSection:mapper];
            }
        }
    }
    if ([self.owner respondsToSelector:@selector(setAutoItemSizing:)]) {
        [(id) self.owner setAutoItemSizing:[self isAutoItemSizing]];
    }
}

- (void)calculateItemWidthWeightsForSection:(PBSectionMapper *)section {
    NSUInteger numberOfItems = section.items.count;
    if (numberOfItems > 0) {
        PBRowMapper *row = section.items.firstObject;
        if (numberOfItems == 1) {
            row.widthWeight = 1.f / section.numberOfColumns;
        } else {
            NSInteger numberOfRows = ceil(numberOfItems * 1.f / section.numberOfColumns);
            NSInteger index = 0;
            for (NSInteger row = 0; index < numberOfRows; row++) {
                CGFloat weight = 0;
                BOOL invalid = NO;
                for (NSInteger column = 0; column < section.numberOfColumns; column++) {
                    if (index + column >= numberOfItems) {
                        invalid = YES;
                        break;
                    }
                    
                    PBRowMapper *row = section.items[index + column];
                    if (row.weight == 0) {
                        row.weight = 1;
                    }
                    weight += row.weight;
                }
                
                if (invalid) {
                    break;
                }
                
                for (NSInteger column = 0; column < section.numberOfColumns; column++) {
                    PBRowMapper *row = section.items[index++];
                    row.widthWeight = row.weight / weight;
                }
            }
        }
    }
}

- (BOOL)isAutoItemSizing {
    if (_row != nil) {
        return [_row isAutofit];
    } else if (_rows != nil) {
        for (PBRowMapper *row in _rows) {
            if ([row isAutofit]) {
                return YES;
            }
        }
    } else if (_sections != nil) {
        for (PBSectionMapper *section in _sections) {
            if (section.row != nil) {
                if ([section.row isAutofit]) {
                    return YES;
                }
            }
            
            for (PBRowMapper *row in section.rows) {
                if ([row isAutofit]) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

- (NSInteger)numberOfRowsInSection:(NSInteger)section withData:(id)data key:(NSString *)key {
    NSInteger count = 0;
    if (self.row != nil) {
        // response array
        if ([data isKindOfClass:[PBSection class]]) {
            count = [[(PBSection *)data recordsInSection:section] count];
        } else {
            count = [[self listForData:data key:key] count];
        }
    } else if (self.rows != nil) {
        count = [self.rows count];
    } else if (self.sections != nil) {
        PBSectionMapper *aSection = [self.sections objectAtIndex:section];
        if (aSection.dataUnset) {
            aSection.data = [self listForData:data key:key];
        }
        count = aSection.rowCount;
    }
    return count;
}

- (void)reset {
    _row = nil;
    _rows = nil;
    _sections = nil;
}

#pragma mark - PBRowAction

- (NSArray *)processRowDatas:(NSArray *)newDatas atIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withHandler:(void (^)(NSMutableArray *list, NSArray *newDatas, NSIndexSet *indexes))handler {
    // TODO: Parse PBSection
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSIndexPath *indexPath in indexPaths) {
        [indexes addIndex:indexPath.row];
    }
    
    id target;
    if (self.sections.count > 0) {
        // TODO: specify section index
        PBSectionMapper *section = self.sections.firstObject;
        target = section;
    } else {
        target = self.owner;
    }
    id list = [target data];
    if (list == nil) {
        list = [NSMutableArray array];
        [target setData:list];
    }
    
    if ([list isKindOfClass:[NSArray class]]) {
        if ([list isKindOfClass:[NSMutableArray class]]) {
            NSMutableArray *mutableList = list;
            handler(mutableList, newDatas, indexes);
        } else {
            NSMutableArray *mutableList = [NSMutableArray arrayWithArray:list];
            handler(mutableList, newDatas, indexes);
            [target setData:list];
        }
        return list;
    }
    
    PBArray *array = nil;
    if ([list isKindOfClass:[PBArray class]]) {
        array = list;
        list = [array list];
        if ([list isKindOfClass:[NSArray class]]) {
            if ([list isKindOfClass:[NSMutableArray class]]) {
                handler(list, newDatas, indexes);
                return list;
            } else {
                NSMutableArray *mutableList = [NSMutableArray arrayWithArray:list];
                handler(mutableList, newDatas, indexes);
                array[array.listElementIndex] = mutableList;
                return mutableList;
            }
        }
    }
    
    if (self.owner.listKey == nil || ![list isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NSDictionary *listContainer = list;
    list = [list objectForKey:self.owner.listKey];
    if (![list isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    if ([list isKindOfClass:[NSMutableArray class]]) {
        handler(list, newDatas, indexes);
        return list;
    } else {
        NSMutableArray *mutableList = [NSMutableArray arrayWithArray:list];
        handler(mutableList, newDatas, indexes);
        
        if ([listContainer isKindOfClass:[NSMutableDictionary class]]) {
            [(NSMutableDictionary *)listContainer setObject:mutableList forKey:self.owner.listKey];
        } else {
            NSMutableDictionary *mutableContainer = [NSMutableDictionary dictionaryWithDictionary:listContainer];
            [mutableContainer setObject:mutableList forKey:self.owner.listKey];
            
            if (array != nil) {
                array[array.listElementIndex] = mutableContainer;
            } else {
                [target setData:mutableContainer];
            }
        }
        return mutableList;
    }
}

- (void)addRowData:(id)data {
    if (data == nil) {
        return;
    }
    
    [self addRowDatas:@[data]];
}

- (void)addRowDatas:(NSArray *)datas {
    if (datas == nil) {
        return;
    }
    
    NSUInteger count = datas.count;
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger index = 0; index < count; index++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
    }
    [self insertRowDatas:datas atIndexPaths:indexPaths];
}

- (void)appendRowDatas:(NSArray *)datas {
    [self appendRowDatas:datas atSection:0];
}

- (void)appendRowDatas:(NSArray *)datas atSection:(NSUInteger)section {
    if (datas == nil) {
        return;
    }
    
    NSUInteger orgCount = [[self list] count];
    NSUInteger count = datas.count;
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:count];
    for (NSInteger index = 0; index < count; index++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:index + orgCount inSection:section]];
    }
    [self insertRowDatas:datas atIndexPaths:indexPaths];
}

- (void)insertRowDatas:(NSArray *)newDatas atIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    // Process data
    [self processRowDatas:newDatas atIndexPaths:indexPaths withHandler:^(NSMutableArray *list, NSArray *newDatas, NSIndexSet *indexes) {
        [list insertObjects:newDatas atIndexes:indexes];
    }];
    
    // Reload view
    if ([NSThread isMainThread]) {
        [self animateRowViewAtIndexPaths:indexPaths interactionType:PBRowInteractionTypeInsert];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self animateRowViewAtIndexPaths:indexPaths interactionType:PBRowInteractionTypeInsert];
        });
    }
}

- (void)deleteRowDataAtIndexPath:(NSIndexPath *)indexPath {
    // Process data
    [self processRowDatas:nil atIndexPaths:@[indexPath] withHandler:^(NSMutableArray *list, NSArray *newDatas, NSIndexSet *indexes) {
        [list removeObjectsAtIndexes:indexes];
    }];
    
    // Reload view
    if ([NSThread isMainThread]) {
        [self animateRowViewAtIndexPaths:@[indexPath] interactionType:PBRowInteractionTypeDelete];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self animateRowViewAtIndexPaths:@[indexPath] interactionType:PBRowInteractionTypeDelete];
        });
    }
}

- (void)updateRowDataAtIndexPath:(NSIndexPath *)indexPath {
    // Reload view
    if ([NSThread isMainThread]) {
        [self animateRowViewAtIndexPaths:@[indexPath] interactionType:PBRowInteractionTypeUpdate];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self animateRowViewAtIndexPaths:@[indexPath] interactionType:PBRowInteractionTypeUpdate];
        });
    }
}

- (void)updateRowDataAtSection:(NSUInteger)section {
    if (section >= self.sections.count) {
        return;
    }
    [self animateRowViewAtSections:[NSIndexSet indexSetWithIndex:section] interactionType:PBRowInteractionTypeUpdate];
}

- (void)updateRowDataAtAllSections {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSUInteger index = 0; index < self.sections.count; index++) {
        [indexes addIndex:index];
    }
    [self animateRowViewAtSections:indexes interactionType:PBRowInteractionTypeUpdate];
}

- (void)reloadData {
    if ([self.owner isKindOfClass:[UITableView class]]
        || [self.owner isKindOfClass:[UICollectionView class]]) {
        [(id)self.owner setDataUpdated:YES];
        [(id)self.owner reloadData];
    }
}

- (void)deselectSections {
    if ([self.owner isKindOfClass:[PBCollectionView class]]) {
        PBCollectionView *collectionView = (id) self.owner;
        NSArray<NSIndexPath *> *indexPaths = collectionView.indexPathsForSelectedItems;
        for (NSIndexPath *indexPath in indexPaths) {
            [collectionView deselectItemAtIndexPath:indexPath animated:NO];
        }
        collectionView.selectedData = nil;
        collectionView.selectedDatas = nil;
        collectionView.selectedIndexPath = nil;
    }
}

- (void)animateRowViewAtIndexPaths:(NSArray *)indexPaths interactionType:(PBRowInteractionType)type {
    if ([self.owner isKindOfClass:[UITableView class]]) {
        UITableView *tableView = (id) self.owner;
        switch (type) {
            case PBRowInteractionTypeDelete:
                [tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            case PBRowInteractionTypeInsert:
                [tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            case PBRowInteractionTypeUpdate:
                [tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            default:
                break;
        }
        [self notifyDataChangedWithDelay];
    } else {
        UICollectionView *collectionView = (id) self.owner;
        [collectionView performBatchUpdates:^{
            switch (type) {
                case PBRowInteractionTypeDelete:
                    [collectionView deleteItemsAtIndexPaths:indexPaths];
                    break;
                case PBRowInteractionTypeInsert:
                    [collectionView insertItemsAtIndexPaths:indexPaths];
                    break;
                case PBRowInteractionTypeUpdate:
                    [collectionView reloadItemsAtIndexPaths:indexPaths];
                    break;
                default:
                    break;
            }
        } completion:^(BOOL finished) {
            [self notifyDataChanged];
        }];
    }
}

- (void)animateRowViewAtSections:(NSIndexSet *)sectionIndexes interactionType:(PBRowInteractionType)type {
    if ([self.owner isKindOfClass:[UITableView class]]) {
        UITableView *tableView = (id) self.owner;
        switch (type) {
            case PBRowInteractionTypeDelete:
                [tableView deleteSections:sectionIndexes withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            case PBRowInteractionTypeInsert:
                [tableView insertSections:sectionIndexes withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            case PBRowInteractionTypeUpdate:
                [tableView reloadSections:sectionIndexes withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            default:
                break;
        }
        [self notifyDataChangedWithDelay];
    } else {
        UICollectionView *collectionView = (id) self.owner;
        [collectionView performBatchUpdates:^{
            switch (type) {
                case PBRowInteractionTypeDelete:
                    [collectionView deleteSections:sectionIndexes];
                    break;
                case PBRowInteractionTypeInsert:
                    [collectionView insertSections:sectionIndexes];
                    break;
                case PBRowInteractionTypeUpdate:
                    [collectionView reloadSections:sectionIndexes];
                    break;
                default:
                    break;
            }
        } completion:^(BOOL finished) {
            [self notifyDataChanged];
        }];
    }
}

- (void)notifyDataChangedWithDelay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kUITableViewRowAnimationDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self notifyDataChanged];
    });
}

- (void)notifyDataChanged {
    [self.owner rowDataSourceDidChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:PBRowDataDidChangeNotification object:self];
}

//- (void)removeRowData

#pragma mark - UITableView
#pragma mark - @required

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver numberOfSectionsInTableView:tableView];
    }
    
    if (self.sections != nil) {
        return [self.sections count];
    } else if (self.row != nil || self.rows != nil) {
        if ([tableView.data isKindOfClass:[PBSection class]]) {
            return [[(PBSection *)tableView.data sectionIndexTitles] count];
        }
    }
    return 1;
}

- (NSInteger)tableView:(PBTableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        NSInteger rowCount = [self.receiver tableView:tableView numberOfRowsInSection:section];
        if (rowCount >= 0) {
            return rowCount;
        }
    }
    
    return [self numberOfRowsInSection:section withData:tableView.data key:tableView.listKey];
}

// Row display. Implementers should *always* try to reuse cells by setting each cell's reuseIdentifier and querying for available reusable cells with dequeueReusableCellWithIdentifier:
// Cell gets various attributes set automatically based on table (separators) and data source (accessory views, editing controls)

- (UITableViewCell *)tableView:(PBTableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    if ([self.receiver respondsToSelector:@selector(tableView:cellForRowAtIndexPath:)]) {
        cell = [self.receiver tableView:tableView cellForRowAtIndexPath:indexPath];
        if (cell != nil) {
            return cell;
        }
    }
    
    // Initialize the row mapper
    id data = [self dataAtIndexPath:indexPath];
    PBRowMapper *row = [self rowAtIndexPath:indexPath];
    [self updateRowMapper:row forRowAtIndexPath:indexPath inView:tableView withData:data];
    
    // Lazy register reusable cell
    NSString *identifier = row.id;
    BOOL needsRegister = NO;
    if (tableView.registeredCellIdentifiers == nil) {
        tableView.registeredCellIdentifiers = [[NSMutableArray alloc] init];
        needsRegister = YES;
    } else {
        needsRegister = ![tableView.registeredCellIdentifiers containsObject:identifier];
    }
    if (needsRegister) {
        UINib *nib = PBNib(row.nib);
        if (nib != nil) {
            [tableView registerNib:nib forCellReuseIdentifier:identifier];
        } else {
            [tableView registerClass:row.viewClass forCellReuseIdentifier:identifier];
        }
        [tableView.registeredCellIdentifiers addObject:identifier];
    }
    
    // Dequeue reusable cell
    cell = [tableView dequeueReusableCellWithIdentifier:row.id];
    if (cell == nil) {
        cell = [[row.viewClass alloc] initWithStyle:row.style reuseIdentifier:row.id];
    }
    cell.indexPath = indexPath;
    
    // Add custom layout
    if (row.layoutMapper != nil) {
        [row.layoutMapper renderToView:cell.contentView];
    }
    
    // Default to non-selection
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    
    if ([tableView isHorizontal]) {
        [cell.contentView setTransform:CGAffineTransformMakeRotation(M_PI_2)];
    }
    
    // Init data for cell
    [cell setData:data];
    [row initPropertiesForTarget:cell];
    [row mapPropertiesToTarget:cell withData:tableView.rootData owner:cell context:tableView];
    
    return cell;
}

- (void)updateRowMapper:(PBRowMapper *)row forRowAtIndexPath:(NSIndexPath *)indexPath inView:(UIView *)view withData:(id)data {
    NSArray *keys = @[@"layout", @"id", @"clazz"];
    
    for (NSString *key in keys) {
        [row setMappable:YES forKey:key];
    }
    
    _PBRowDataWrapper *dataWrapper = [[_PBRowDataWrapper alloc] initWithData:data indexPath:indexPath];
    [row updateWithData:view.rootData owner:(id)dataWrapper context:self.owner];
    
    for (NSString *key in keys) {
        [row setMappable:NO forKey:key];
    }
}

#pragma mark - @optional

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView titleForHeaderInSection:section];
    }
    
    if (self.sections != nil) {
        if (self.sections.count <= section) {
            return nil;
        }
        PBHeaderFooterMapper *header = [self.sections objectAtIndex:section].header;
        return header.title;
    } else if ([tableView.data isKindOfClass:[PBSection class]]) {
        return [(PBSection *)tableView.data titleOfSection:section];
    }
    return nil;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView titleForFooterInSection:section];
    }
    
    if (self.sections != nil) {
        if (self.sections.count <= section) {
            return nil;
        }
        PBHeaderFooterMapper *footer = [self.sections objectAtIndex:section].footer;
        return footer.title;
    }
    return nil;
}

#pragma mark - Editing

// Individual rows can opt out of having the -editing property set for them. If not implemented, all rows are assumed to be editable.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView canEditRowAtIndexPath:indexPath];
    }
    
    PBRowMapper *row = [self rowAtIndexPath:indexPath];
    if (row.editActionMappers != nil) {
        return YES;
    }
    return NO;
}

#pragma mark - Moving/reordering

// Allows the reorder accessory view to optionally be shown for a particular row. By default, the reorder control will be shown only if the datasource implements -tableView:moveRowAtIndexPath:toIndexPath:
//- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
//    if ([self.receiver respondsToSelector:_cmd]) {
//        return [self.receiver tableView:tableView canMoveRowAtIndexPath:indexPath];
//    }
//    return NO;
//}

#pragma mark - Index

- (nullable NSArray<NSString *> *)sectionIndexTitlesForTableView:(PBTableView *)tableView __TVOS_PROHIBITED {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver sectionIndexTitlesForTableView:tableView];
    }
    
    if (tableView.indexViewHidden) {
        return nil;
    }
    if (self.sections) {
        return _sectionIndexTitles;
    } else if ([tableView.data isKindOfClass:[PBSection class]]) {
        return [(PBSection *)tableView.data sectionIndexTitles];
    }
    return nil;
}// return list of section titles to display in section index view (e.g. "ABCD...Z#")

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index __TVOS_PROHIBITED {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver tableView:tableView sectionForSectionIndexTitle:title atIndex:index];
    }
    
    if (self.sections != nil) {
        for (NSInteger index = 0; index < [self.sections count]; index++) {
            PBSectionMapper *section = [self.sections objectAtIndex:index];
            if ([section.title isEqualToString:title]) {
                return index;
            }
        }
    } else if ([tableView.data isKindOfClass:[PBSection class]]) {
        return [(PBSection *)tableView.data sectionOfTitle:title];
    }
    return 0;
}// tell table which section corresponds to section title/index (e.g. "B",1))

//#pragma mark - Data manipulation - insert and delete support
//
//// After a row has the minus or plus button invoked (based on the UITableViewCellEditingStyle for the cell), the dataSource must commit the change
//// Not called for edit actions using UITableViewRowAction - the action's handler will be invoked instead
//- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
//    if ([self.receiver respondsToSelector:_cmd]) {
//        [self.receiver tableView:tableView commitEditingStyle:editingStyle forRowAtIndexPath:indexPath];
//    }
//}
//
//#pragma mark - Data manipulation - reorder / moving support
//
//- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
//    if ([self.receiver respondsToSelector:_cmd]) {
//        [self.receiver tableView:tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
//    }
//}

#pragma mark - UICollectionView

- (NSInteger)numberOfSectionsInCollectionView:(PBCollectionView *)collectionView {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver numberOfSectionsInCollectionView:collectionView];
    }
    
    if (self.sections != nil) {
        return [self.sections count];
    } else if (self.row != nil || self.rows != nil) {
        if ([collectionView.data isKindOfClass:[PBSection class]]) {
            return [[(PBSection *)collectionView.data sectionIndexTitles] count];
        }
    }
    return 1;
}

- (NSInteger)collectionView:(PBCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if ([self.receiver respondsToSelector:_cmd]) {
        NSInteger count = [self.receiver collectionView:collectionView numberOfItemsInSection:section];
        if (count >= 0) {
            return count;
        }
    }
    
    return [self numberOfRowsInSection:section withData:collectionView.data key:collectionView.listKey];
}

- (UICollectionViewCell *)collectionView:(PBCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self _collectionView:collectionView cellForItemAtIndexPath:indexPath reusing:YES];
}

- (UICollectionViewCell *)_collectionView:(PBCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath reusing:(BOOL)reusing {
    UICollectionViewCell *cell = nil;
    if ([self.receiver respondsToSelector:_cmd]) {
        cell = [self.receiver collectionView:collectionView cellForItemAtIndexPath:indexPath];
        if (cell != nil) {
            return cell;
        }
    }
    
    // Initialize the row mapper
    id data = [self dataAtIndexPath:indexPath];
    PBRowMapper *item = [self rowAtIndexPath:indexPath];
    [self updateRowMapper:item forRowAtIndexPath:indexPath inView:collectionView withData:data];
    
    // Lazy register reusable cell
    if (reusing) {
        NSString *identifier = item.id;
        BOOL needsRegister = NO;
        if (collectionView.registeredCellIdentifiers == nil) {
            collectionView.registeredCellIdentifiers = [[NSMutableArray alloc] init];
            needsRegister = YES;
        } else {
            needsRegister = ![collectionView.registeredCellIdentifiers containsObject:identifier];
        }
        if (needsRegister) {
            UINib *nib = PBNib(item.nib);
            if (nib != nil) {
                [collectionView registerNib:nib forCellWithReuseIdentifier:identifier];
            } else {
                [collectionView registerClass:item.viewClass forCellWithReuseIdentifier:identifier];
            }
            [collectionView.registeredCellIdentifiers addObject:identifier];
        }
        
        // Dequeue reusable cell
        cell = [collectionView dequeueReusableCellWithReuseIdentifier:item.id forIndexPath:indexPath];
    } else {
        cell = (UICollectionViewCell *)[item createView];
    }
    
    // Auto size
    if ([item isAutoWidth]) {
        
    } else if ([item isAutoHeight]) {
        CGFloat width = item.width;
        if (width == -2) {
            PBSectionMapper *section = [self.sections objectAtIndex:indexPath.section];
            width = collectionView.bounds.size.width - section.inset.left - section.inset.right;
        }
        
        static NSString *kWidthConstraintId = @"PBAutoItemSizing";
        UIView *contentView = cell.contentView;
        NSLayoutConstraint *widthConstraint = nil;
        NSArray *filters = [contentView.constraints filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier == %@", kWidthConstraintId]];
        if (filters.count > 0) {
            widthConstraint = [filters firstObject];
        }
        if (widthConstraint == nil) {
            widthConstraint = [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:width];
            widthConstraint.identifier = kWidthConstraintId;
            [contentView addConstraint:widthConstraint];
        } else {
            widthConstraint.constant = width;
        }
    }
    
    [self _updateCell:cell forIndexPath:indexPath withData:data item:item context:collectionView];
    return cell;
}

- (void)_updateCell:(UICollectionViewCell *)cell forIndexPath:(NSIndexPath *)indexPath withData:(id)data item:(PBRowMapper *)item context:(UIView *)context {
    cell.indexPath = indexPath;
    
    // Add custom layout
    if (item.layoutMapper != nil) {
        [item.layoutMapper renderToView:cell.contentView];
    }
    
    // Init data for cell
    [cell setData:data];
    [item initPropertiesForTarget:cell];
    [item mapPropertiesToTarget:cell withData:context.data owner:cell context:context];
}

- (UICollectionReusableView *)collectionView:(PBCollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if ([self.receiver respondsToSelector:_cmd]) {
        return [self.receiver collectionView:collectionView viewForSupplementaryElementOfKind:kind atIndexPath:indexPath];
    }
    
    PBSectionMapper *section = [self.sections objectAtIndex:indexPath.section];
    PBRowMapper *element;
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        element = section.header;
    } else {
        element = section.footer;
    }
    
    // Lazy register reusable view
    NSString *identifier = element.id;
    BOOL needsRegister = NO;
    if (collectionView.registeredSectionIdentifiers == nil) {
        collectionView.registeredSectionIdentifiers = [[NSMutableArray alloc] init];
        needsRegister = YES;
    } else {
        needsRegister = ![collectionView.registeredSectionIdentifiers containsObject:identifier];
    }
    if (needsRegister) {
        UINib *nib = PBNib(element.nib);
        if (nib != nil) {
            [collectionView registerNib:nib forSupplementaryViewOfKind:kind withReuseIdentifier:identifier];
        } else {
            [collectionView registerClass:element.viewClass forSupplementaryViewOfKind:kind withReuseIdentifier:identifier];
        }
        [collectionView.registeredSectionIdentifiers addObject:identifier];
    }
    
    // Dequeue reusable view
    UICollectionReusableView *view = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:element.id forIndexPath:indexPath];
    
    // Add custom layout
    if (element.layoutMapper != nil) {
        [element.layoutMapper renderToView:view];
    }
    
    // Map data
    [element initPropertiesForTarget:view];
    [element mapPropertiesToTarget:view withData:collectionView.data owner:view context:collectionView];
    
    return view;
}

#pragma mark - Helper

- (NSDictionary *)dictionaryByMergingDictionary:(NSDictionary *)oneDictionay withAnother:(NSDictionary *)anotherDictionay
{
    if ([anotherDictionay isKindOfClass:[NSString class]]) {
        id anotherValue = [PBValueParser valueWithString:(id)anotherDictionay];
        if (anotherValue == nil) {
            return nil;
        }
        return oneDictionay;
    }
    
    NSMutableDictionary *mergedDictionary = [NSMutableDictionary dictionary];
    NSMutableDictionary *valuesOnlyInOther = [NSMutableDictionary dictionaryWithDictionary:anotherDictionay];
    for (NSString *key in oneDictionay) {
        id oneValue = [oneDictionay objectForKey:key];
        id otherValue = [anotherDictionay objectForKey:key];
        if (otherValue == nil) {
            otherValue = oneValue;
        } else {
            if ([oneValue isKindOfClass:[NSDictionary class]]) {
                otherValue = [self dictionaryByMergingDictionary:oneValue withAnother:otherValue];
            }
            [valuesOnlyInOther removeObjectForKey:key];
        }
        
        if (otherValue == nil) {
            [mergedDictionary removeObjectForKey:key];
        } else {
            [mergedDictionary setObject:otherValue forKey:key];
        }
    }
    [mergedDictionary setValuesForKeysWithDictionary:valuesOnlyInOther];
    return mergedDictionary;
}

@end

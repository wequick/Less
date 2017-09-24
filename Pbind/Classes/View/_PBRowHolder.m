//
//  _PBRowHolder.m
//  Pbind <https://github.com/wequick/Pbind>
//
//  Created by galen on 2017/8/27.
//  Copyright (c) 2015-present, Wequick.net. All rights reserved.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "_PBRowHolder.h"
#import "UIView+Pbind.h"
#import "PBPropertyUtils.h"
#import <objc/runtime.h>

@implementation _PBPropertyPath

- (instancetype)init {
    if (self = [super init]) {
        _targetIndex = 0xFF;
        _keyIndex = 0xFF;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }
    
    return _targetIndex == [object targetIndex] && _keyIndex == [object keyIndex];
}

@end

@implementation _PBMetaProperty
{
    __unsafe_unretained Class _targetClass;
}

- (instancetype)initWithTarget:(id)target key:(NSString *)key {
    if (self = [super init]) {
        _targetClass = [target class];
        _key = key;
//        _getter = NSSelectorFromString(key);
//        _setter = NSSelectorFromString([NSString stringWithFormat:@"set%c%@", toupper([key characterAtIndex:0]), [key substringFromIndex:1]]);
    }
    return self;
}

- (void)setValue:(id)value toTarget:(id)target {
    if ([target respondsToSelector:@selector(pb_setValue:forKeyPath:)]) {
        [target pb_setValue:value forKeyPath:_key];
    } else {
        [PBPropertyUtils setValue:value forKey:_key toObject:target failure:nil];
    }
}

- (id)valueOfTarget:(id)target {
    if ([target respondsToSelector:@selector(pb_valueForKeyPath:)]) {
        return [target pb_valueForKeyPath:_key];
    }
    return [PBPropertyUtils valueForKey:_key ofObject:target failure:nil];
}

@end

@interface _PBTargetHolder ()

@end

@implementation _PBTargetHolder

@end

@implementation _PBViewHolder
{
    NSMutableArray *_targets;
}

@synthesize targets=_targets;

- (void)updateProperty:(_PBPropertyPath *)property {
    _PBTargetHolder *targetHolder = [self.targets objectAtIndex:property.targetIndex];
    _PBMetaProperty *metaProperty = [targetHolder.properties objectAtIndex:property.keyIndex];
    id value = property.value;
    [metaProperty setValue:value toTarget:targetHolder.target];
    
//    if (targetHolder.keyPath != nil) {
//        NSLog(@" > (%p) %@.%@ = %@", targetHolder.target, targetHolder.keyPath, metaProperty.key, value);
//    } else {
//        NSLog(@" > (%p) %@ = %@", targetHolder.target, metaProperty.key, value);
//    }
}

- (void)mapProperty:(_PBPropertyPath *)property withData:(id)data owner:(id)owner context:(UIView *)context {
    _PBTargetHolder *targetHolder = [self.targets objectAtIndex:property.targetIndex];
    _PBMetaProperty *metaProperty = [targetHolder.properties objectAtIndex:property.keyIndex];
    PBExpression *expression = property.expression;
    id value = [expression valueWithData:data target:targetHolder.target owner:owner context:context];
    [metaProperty setValue:value toTarget:targetHolder.target];
    
//    if (targetHolder.keyPath != nil) {
//        NSLog(@" >> (%p) %@.%@ = %@", targetHolder.target, targetHolder.keyPath, metaProperty.key, value);
//    } else {
//        NSLog(@" >> (%p) %@ = %@", targetHolder.target, metaProperty.key, value);
//    }
}

- (void)updateProperties:(NSArray *)properties withBaseProperties:(NSArray *)baseProperties {
    for (_PBPropertyPath *property in baseProperties) {
        _PBTargetHolder *targetHolder = [self.targets objectAtIndex:property.targetIndex];
        _PBMetaProperty *metaProperty = [targetHolder.properties objectAtIndex:property.keyIndex];
        
        id value = property.value;
        for (_PBPropertyPath *rewriteProperty in properties) {
            if (rewriteProperty.targetIndex == property.targetIndex && rewriteProperty.keyIndex == property.keyIndex) {
                value = rewriteProperty.value;
                break;
            }
        }
        [metaProperty setValue:value toTarget:targetHolder.target];
        
//        if (targetHolder.keyPath != nil) {
//            NSLog(@" > (%p) %@.%@ = %@", targetHolder.target, targetHolder.keyPath, metaProperty.key, value);
//        } else {
//            NSLog(@" > (%p) %@ = %@", targetHolder.target, metaProperty.key, value);
//        }
    }
}

@end

@implementation _PBRowHolder

@end

@implementation UIView (PBViewHolder)

static char kViewHolderKey;

- (_PBViewHolder *)pb_viewHolder {
    return objc_getAssociatedObject(self, &kViewHolderKey);
}

- (void)setPb_viewHolder:(_PBViewHolder *)pb_viewHolder {
    objc_setAssociatedObject(self, &kViewHolderKey, pb_viewHolder, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
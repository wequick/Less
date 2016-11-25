//
//  UIView+Pbind.m
//  Pbind
//
//  Created by galen on 15/2/12.
//  Copyright (c) 2015年 galen. All rights reserved.
//

#import "UIView+Pbind.h"
#import "Pbind.h"
#import "PBClient.h"
#import "PBMapper.h"
#import "PBMutableExpression.h"
#import "PBClientMapper.h"
#import "PBArray.h"
#import "PBPropertyUtils.h"

NSString *const PBViewDidStartLoadNotification = @"PBViewDidStartLoadNotification";
NSString *const PBViewDidFinishLoadNotification = @"PBViewDidFinishLoadNotification";
NSString *const PBViewHasHandledLoadErrorKey = @"PBViewHasHandledLoadError";

NSString *const PBViewDidClickHrefNotification = @"PBViewDidClickHref";
NSString *const PBViewHrefKey = @"href";
NSString *const PBViewHrefParamsKey = @"hrefParams";

@interface PBClient (Private)

- (void)_loadRequest:(PBRequest *)request mapper:(PBClientMapper *)mapper notifys:(BOOL)notifys complection:(void (^)(PBResponse *))complection;

@end

@interface UIView (Pbind_Private)

@property (nonatomic, strong) NSArray *_pbClients;
@property (nonatomic, strong) NSArray *_pbClientMappers;
@property (nonatomic, strong) NSDictionary *_pbActionClients;
@property (nonatomic, strong) NSDictionary *_pbActionMappers;

@end

@implementation UIView (Pbind)

@dynamic client;
@dynamic clients;
@dynamic data;
@dynamic needsLoad;

#pragma mark -
#pragma mark - Override methods

- (void)didMoveToWindow
{
    if (self.window == nil) {
        if (self.pb_loading) {
            // If super controller is neither a singleton nor a child of `UITabBarController', mark interrupted flag to reload at next appearance
            if (![[[[self supercontroller] navigationController] parentViewController] isKindOfClass:[UITabBarController class]]) {
                self.pb_interrupted = YES;
                [self pb_cancelPull];
            }
        }
    } else {
        if (self.plist != nil) {
            if (self._pbPlistURL == nil) {
                self._pbPlistURL = [self pb_URLForResource:self.plist withExtension:@"plist"];
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                   dispatch_sync(dispatch_get_main_queue(), ^{
                       [self _pb_initData];
                   });
                });
            }
        } else {
            if ([[self valueForAdditionKey:@"pb_expressible"] boolValue]) {
                [self _pb_initData];
            }
        }
        
        if (self.pb_interrupted) {
            self.pb_interrupted = NO;
            [self pb_repullData];
        }
    }
}

- (NSURL *)pb_URLForResource:(NSString *)resource withExtension:(NSString *)extension
{
    NSArray *preferredBundles = [Pbind allResourcesBundles];
    for (NSBundle *bundle in preferredBundles) {
        NSURL *url = [bundle URLForResource:resource withExtension:extension];
        if (url != nil) {
            return url;
        }
    }
    return nil;
}

- (NSArray *)pb_clientMappers
{
    if (self._pbClientMappers != nil) return self._pbClientMappers;
    
    // Lazy init
    if (self.clients == nil) {
        if (self.client == nil) return nil;
        
        PBClientMapper *mapper = [[PBClientMapper alloc] init];
        mapper.clazz = self.client;
        mapper.action = self.clientAction;
        mapper.params = self.clientParams;
        self._pbClientMappers = @[mapper];
        return self._pbClientMappers;
    } else {
        NSMutableArray *mappers = [NSMutableArray arrayWithCapacity:self.clients.count];
        for (id data in self.clients) {
            PBClientMapper *mapper = [PBClientMapper mapperWithDictionary:data owner:self];
            [mappers addObject:mapper];
        }
        self._pbClientMappers = mappers;
        return mappers;
    }
}

- (NSArray *)pb_clients
{
    if (self._pbClients != nil) return self._pbClients;
    
    if (self.pb_clientMappers == nil) return nil;
    
    NSMutableArray *clients = [NSMutableArray arrayWithCapacity:self.clients.count];
    for (PBClientMapper *mapper in self.pb_clientMappers) {
        PBClient *client = [PBClient clientWithName:mapper.clazz];
        client.delegate = (id) self;
        [clients addObject:client];
    }
    self._pbClients = clients;
    return clients;
}

- (NSDictionary *)pb_actionMappers
{
    if (self._pbActionMappers != nil) return self._pbActionMappers;
    
    if (self.actions == nil) return nil;
    
    NSMutableDictionary *mappers = [NSMutableDictionary dictionaryWithCapacity:self.actions.count];
    for (NSString *key in self.actions) {
        PBClientMapper *mapper = [PBClientMapper mapperWithDictionary:self.actions[key] owner:self];
        [mapper initDataForView:self];
        [mappers setObject:mapper forKey:key];
    }
    self._pbActionMappers = mappers;
    return mappers;
}

- (NSDictionary *)pb_actionClients
{
    if (self._pbActionClients != nil) return self._pbActionClients;
    
    if (self.pb_actionMappers == nil) return nil;
    
    NSMutableDictionary *clients = [NSMutableDictionary dictionaryWithCapacity:self.pb_actionMappers.count];
    for (NSString *key in self.pb_actionMappers) {
        PBClientMapper *mapper = [self.pb_actionMappers objectForKey:key];
        PBClient *client = [PBClient clientWithName:mapper.clazz];
        client.delegate = (id) self;
        [clients setObject:client forKey:key];
    }
    self._pbActionClients = clients;
    return clients;
}

- (PBMapper *)pb_mapper
{
    // Lazy init
    if (self.PB_internalMapper == nil) {
        if (self._pbPlistURL != nil) {
            self.PB_internalMapper = [PBMapper mapperWithContentsOfURL:self._pbPlistURL];
        }
    }
    return self.PB_internalMapper;
}

- (BOOL)pb_loading
{
    return self.pb_loadingCount > 0;
}

- (void)pb_pullData
{
    [self pb_pullDataWithPreparation:nil transformation:nil];
}

- (void)pb_pullDataWithPreparation:(void (^)(void))preparation
                    transformation:(id (^)(id, NSError *))transformation
{
    
//}
//
//- (void)pb_pullDataWithPreparation:(void (^)(void))preparation
//                    transformation:(id (^)(id, NSError *))transformation
//                       complection:(void (^)(void))complection
//{
    if (self.pb_loading) {
        return;
    }
    
    if (self.pb_clientMappers == nil) {
        return;
    }
    
    if (self.pb_clients == nil) {
        return;
    }
    
    if (preparation) {
        preparation();
    }
    
    // Notify loading start
    [[NSNotificationCenter defaultCenter] postNotificationName:PBViewDidStartLoadNotification object:self];
    
    // Unbind
    [self pb_unbind];
    
    self.pb_preparation = preparation;
    self.pb_transformation = transformation;
    NSInteger N = self.pb_clients.count;
    self.pb_loadingCount = (int) N;
    
    // Init null data
    if (self.data == nil) {
        self.data = [PBArray arrayWithCapacity:self.clients.count];
        for (NSInteger i = 0; i < N; i++) {
            [self.data addObject:[NSNull null]];
        }
    }
    
    // Load request parallel
    for (NSInteger i = 0; i < N; i++) {
        PBClient *client = [self.pb_clients objectAtIndex:i];
        PBClientMapper *mapper = [self.pb_clientMappers objectAtIndex:i];
        [mapper updateWithData:self.data andView:self];
        
        Class requestClass = [client.class requestClass];
        PBRequest *request = [[requestClass alloc] init];
        request.action = mapper.action;
        request.params = mapper.params;
        request.requiresMutableResponse = mapper.mutable;
        
        if ([self respondsToSelector:@selector(view:shouldLoadRequest:)]) {
            BOOL flag = [self view:self shouldLoadRequest:request];
            if (!flag) {
                continue;
            }
        }
        if ([self.loadingDelegate respondsToSelector:@selector(view:shouldLoadRequest:)]) {
            BOOL flag = [self.loadingDelegate view:self shouldLoadRequest:request];
            if (!flag) {
                continue;
            }
        }
        
        [client _loadRequest:request mapper:nil notifys:NO complection:^(PBResponse *response) {
            BOOL handledError = NO;
            if ([self respondsToSelector:@selector(view:didFinishLoading:handledError:)]) {
                [self view:self didFinishLoading:response handledError:&handledError];
            }
            if ([self.loadingDelegate respondsToSelector:@selector(view:didFinishLoading:handledError:)]) {
                [self.loadingDelegate view:self didFinishLoading:response handledError:&handledError];
            }
            NSDictionary *userInfo = nil;
            if (response != nil) {
                userInfo = @{PBResponseKey:response, PBViewHasHandledLoadErrorKey:@(handledError)};
            } else {
                userInfo = @{PBViewHasHandledLoadErrorKey:@(handledError)};
            }
            
            [client cancel];
            
            id data = response.data;
            if (transformation) {
                data = transformation(data, response.error);
            }
            if (data) {
                self.pb_preparation = nil;
                self.pb_transformation = nil;
                self.data[i] = data;
                [self _pb_mapData:self.rootData];
                [self layoutIfNeeded];
            }
            
            self.pb_loadingCount--;
            if (self.pb_loadingCount == 0) {
                // Notify loading finish
                [[NSNotificationCenter defaultCenter] postNotificationName:PBViewDidFinishLoadNotification object:self userInfo:userInfo];
            }
        }];
    }
}

- (void)_pb_initData {
    PBMapper *mapper = [self pb_mapper];
    if (mapper == nil) {
        [self pb_initData];
        return;
    }
    
    [mapper initDataForView:self];
}

- (void)_pb_mapData:(id)data {
    PBMapper *mapper = [self pb_mapper];
    if (mapper == nil) {
        [self pb_mapData:data];
        return;
    }
    
    [mapper mapData:data forView:self];
}

- (void)pb_initData
{
    NSDictionary *properties = [self pb_constants];
    for (NSString *key in properties) {
        id value = [properties objectForKey:key];
        value = [PBValueParser valueWithString:value];
        [self pb_setValue:value forKeyPath:key];
    }
    
    [self pb_bindData];
    
    // Recursive
    if ([self respondsToSelector:@selector(reloadData)]) {
        
    } else {
        for (UIView *subview in [self subviews]) {
            [subview pb_initData];
        }
    }
    
    if (self.data == nil && (self.client != nil || self.clients != nil)) {
        if (self.window == nil) {
            // Cause the plist value may be specify with expression `@xx', which requires the view's super controller. If window is nil, it means the super controller is also not yet ready.
            return;
        }
        
        [self pb_mapData:nil];
        [(id)self reloadData];
    } else if ([self respondsToSelector:@selector(reloadData)]) {
        [(id)self reloadData];
    }
}

- (void)pb_bindData
{
    NSDictionary *properties = [self pb_expressions];
    for (NSString *key in properties) {
        PBExpression *exp = [properties objectForKey:key];
        [exp bindData:nil toTarget:self forKeyPath:key inContext:self];
    }
}

- (void)pb_mapData:(id)data
{
    NSDictionary *properties = [self pb_expressions];
    for (NSString *key in properties) {
        if ([self mappableForKeyPath:key]) {
            PBExpression *exp = [properties objectForKey:key];
            [exp mapData:data toTarget:self forKeyPath:key inContext:self];
        }
    }
    // Recursive
    if ([self respondsToSelector:@selector(reloadData)]) {
        
    } else {
        for (UIView *subview in [self subviews]) {
            [subview pb_mapData:data];
        }
    }
    
    if (self.data == nil && (self.client != nil || self.clients != nil)) {
        [self pb_pullData];
    } else {
        if ([self respondsToSelector:@selector(reloadData)]) {
            [(id)self reloadData];
        }
    }
}

- (void)pb_mapData:(id)data forKey:(NSString *)key
{
    PBExpression *exp = [[self pb_expressions] objectForKey:key];
    if (exp == nil) {
        return;
    }
    
    [exp mapData:data toTarget:self forKeyPath:key inContext:self];
}

- (void)pb_repullData
{
    [self pb_pullDataWithPreparation:self.pb_preparation transformation:self.pb_transformation];
}

- (void)pb_loadData:(id)data
{
    [self setData:data];
    [[self pb_mapper] mapData:self.rootData forView:self];
    
    [self layoutIfNeeded];
}

- (void)pb_reloadPlist
{
    [self pb_unbind];
    [self pb_reloadPlistForView:self];
}

- (void)pb_reloadPlistForView:(UIView *)view {
    if (view.plist == nil) {
        for (UIView *subview in view.subviews) {
            [self pb_reloadPlistForView:subview];
        }
        return;
    }
    
    // Reset the plist mapper
    view._pbPlistURL = [view pb_URLForResource:view.plist withExtension:@"plist"];
    view.PB_internalMapper = nil;
    PBMapper *mapper = [view pb_mapper];
    
    // Reset all the PBMapper properties for self and subviews
    [self _pb_resetMappersForView:view];
    
    [mapper initDataForView:view];
    [mapper mapData:view.rootData forView:view];
}

- (void)pb_reloadClient
{
    [self pb_reloadClientForView:self];
}

- (BOOL)pb_reloadClientForView:(UIView *)view {
    if (view.pb_clientMappers != nil) {
        [view pb_repullData];
        return YES;
    }
    
    for (UIView *subview in view.subviews) {
        if ([self pb_reloadClientForView:subview]) {
            return YES;
        }
    }
    return NO;
}

- (void)pb_unbind
{
    NSDictionary *expressions = [self pb_expressions];
    if (expressions != nil) {
        for (NSString *key in expressions) {
            PBExpression *expression = [expressions objectForKey:key];
            [expression unbind:self forKeyPath:key];
        }
    }
    
    for (UIView *subview in self.subviews) {
        [subview pb_unbind];
    }
}

- (void)_pb_resetMappersForView:(UIView *)view {
    if ([view respondsToSelector:@selector(pb_resetMappers)]) {
        [(id) view pb_resetMappers];
    }
    for (UIView *subview in view.subviews) {
        [self _pb_resetMappersForView:subview];
    }
}

- (void)pb_cancelPull
{
    if (self.pb_clients == nil) return;
    
    for (PBClient *client in self.pb_clients) {
        [client cancel];
    }
    self.pb_loadingCount = 0;
}

- (void)pb_clickHref:(NSString *)href
{
    if (href == nil) {
        return;
    }
    
    NSURL *url;
    NSMutableDictionary *hrefParams = nil;
    NSRange range = [href rangeOfString:@"?"];
    if (range.location != NSNotFound) {
        url = [NSURL URLWithString:[href substringToIndex:range.location]];
        NSString *query = [href substringFromIndex:range.location + 1];
        hrefParams = [[NSMutableDictionary alloc] init];
        NSArray *pairs = [query componentsSeparatedByString:@"&"];
        for (NSString *pair in pairs) {
            NSRange range = [pair rangeOfString:@"="];
            if (range.location != NSNotFound) {
                NSString *key = [pair substringToIndex:range.location];
                NSString *value = [pair substringFromIndex:range.location + 1];
                hrefParams[key] = value;
            }
        }
    } else {
        url = [NSURL URLWithString:href];
    }
    
    // Merge href parameters
    if (hrefParams != nil) {
        if (self.hrefParams != nil) {
            [hrefParams setValuesForKeysWithDictionary:self.hrefParams];
        }
    } else {
        hrefParams = [NSMutableDictionary dictionaryWithDictionary:self.hrefParams];
    }
    
    NSString *scheme = url.scheme;
    if ([scheme isEqualToString:@"note"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:url.host object:self userInfo:hrefParams];
    } else if ([scheme isEqualToString:@"ctl"]) {
        // Invoke a view controller method
        UIViewController *controller = [self supercontroller];
        SEL action = NSSelectorFromString([NSString stringWithFormat:@"%@:", url.host]);
        if ([controller respondsToSelector:action]) {
            IMP imp = [controller methodForSelector:action];
            PBCallControllerFunc func = (PBCallControllerFunc)imp;
            
            // Temporary pass the merged href parameters
            NSDictionary *orgParams = self.hrefParams;
            self.hrefParams = hrefParams;
            
            func(controller, action, self);
            
            // Restore
            self.hrefParams = orgParams;
        }
    } else if ([scheme isEqualToString:@"push"]) {
        // Push to a view controller
        UIViewController *controller = [self supercontroller];
        UIViewController *nextController = [[NSClassFromString(url.host) alloc] init];
        if (hrefParams != nil) {
            @try {
                [nextController setValuesForKeysWithDictionary:hrefParams];
            } @catch (NSException *exception) {
                NSLog(@"Pbind: Failed to init properties for %@ (ERROR: %@)", nextController.class, exception);
            }
        }
        [controller.navigationController pushViewController:nextController animated:YES];
    } else if ([scheme isEqualToString:@"action"]) {
        NSString *action = url.host;
        if ([action length] == 1) { // action://1
            NSDictionary *clients = [self pb_actionClients];
            PBClient *client = [clients objectForKey:action];
            if (client == nil) {
                return;
            }
            
            NSDictionary *mappers = [self pb_actionMappers];
            PBClientMapper *mapper = [mappers objectForKey:action];
            [mapper updateWithData:self.data andView:self];
            PBRequest *request = [[[client.class requestClass] alloc] init];
            request.action = mapper.action;
            request.params = mapper.params;
            [client _loadRequest:request mapper:mapper notifys:YES complection:^(PBResponse *response) {
                if (response.error == nil) {
                    if (mapper.successHref != nil) {
                        [self pb_clickHref:mapper.successHref];
                    }
                }
            }];
        } else if ([action isEqualToString:@"alert"]) { // action://alert
            // Show alert
            NSString *title = hrefParams[@"title"];
            NSString *msg = hrefParams[@"msg"];
            NSArray *buttonTitles = [hrefParams[@"btns"] componentsSeparatedByString:@"|"];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
            [self setValue:alert forAdditionKey:@"__alert"];
            int buttonCount = (int) buttonTitles.count;
            NSDictionary *mappers = [self pb_actionMappers];
            NSDictionary *clients = [self pb_actionClients];
            for (int index = 0; index < buttonCount; index++) {
                NSString *buttonTitle = [buttonTitles objectAtIndex:index];
                NSString *key = [NSString stringWithFormat:@"%i", (int) index];
                PBClient *client = [clients objectForKey:key];
                UIAlertActionStyle style = (index == 0) ? UIAlertActionStyleCancel : UIAlertActionStyleDefault;
                if (client == nil) {
                    [alert addAction:[UIAlertAction actionWithTitle:buttonTitle style:style handler:^(UIAlertAction *alertAction) {
                        [self setValue:nil forAdditionKey:@"__alert"];
                    }]];
                } else {
                    [alert addAction:[UIAlertAction actionWithTitle:buttonTitle style:style handler:^(UIAlertAction *alertAction) {
                        [self setValue:nil forAdditionKey:@"__alert"];
                        
                        PBClientMapper *mapper = [mappers objectForKey:key];
                        [mapper updateWithData:self.data andView:self];
                        
                        PBRequest *request = [[[client.class requestClass] alloc] init];
                        request.action = mapper.action;
                        request.params = mapper.params;
                        
                        [client _loadRequest:request mapper:mapper notifys:YES complection:^(PBResponse *response) {
                            if (response.error == nil) {
                                if (mapper.successHref != nil) {
                                    [self pb_clickHref:mapper.successHref];
                                }
                            }
                        }];
                    }]];
                }
            }
            [self.supercontroller presentViewController:alert animated:YES completion:nil];
        }
    }
    
    // Post a notification
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
    userInfo[PBViewHrefKey] = href;
    if (hrefParams != nil) {
        userInfo[PBViewHrefParamsKey] = hrefParams;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:PBViewDidClickHrefNotification object:self userInfo:userInfo];
}

#pragma mark -
#pragma mark - KVC

- (void)pb_setValue:(id)value forKeyPath:(NSString *)key
{
    if ([key length] > 1 && [key characterAtIndex:0] == '+') {
        [self setValue:value forAdditionKey:[key substringFromIndex:1]];
    } else {
        id target = self;
        NSArray *keys = [key componentsSeparatedByString:@"."];
        NSUInteger N = keys.count;
        if (N > 1) {
            int i = 0;
            for (; i < N - 1; i++) {
                key = keys[i];
                if ([key characterAtIndex:0] == '@') {
                    key = [key substringFromIndex:1];
                    target = [target viewWithAlias:key];
                } else {
                    target = [target valueForKey:key];
                }
            }
            key = keys[i];
        }
        
        // Safely set value for key
        [PBPropertyUtils setValue:value forKey:key toObject:target];
    }
}

- (void)setMappable:(BOOL)mappable forKeyPath:(NSString *)keyPath
{
    if (self.pb_unmappableKeys == nil) {
        if (!mappable) {
            self.pb_unmappableKeys = [[NSMutableArray alloc] init];
            [self.pb_unmappableKeys addObject:keyPath];
        }
    } else {
        if (mappable) {
            [self.pb_unmappableKeys removeObject:keyPath];
        } else if (![self.pb_unmappableKeys containsObject:keyPath]) {
            [self.pb_unmappableKeys addObject:keyPath];
        }
    }
}

- (BOOL)mappableForKeyPath:(NSString *)keyPath
{
    if (self.pb_unmappableKeys == nil) {
        return YES;
    }
    return ![self.pb_unmappableKeys containsObject:keyPath];
}

- (void)setNeedsLoad:(BOOL)needsLoad
{
    if (needsLoad) {
        if (self.data == nil && self.client != nil) {
            [self pb_pullData];
        } else {
            [self pb_loadData:self.data];
        }
    }
}

- (void)setExpression:(NSString *)expression forKeyPath:(NSString *)keyPath
{
    PBMutableExpression *aExpression = [[PBMutableExpression alloc] initWithString:expression];
    if (aExpression == nil) {
        return;
    }
    
    NSMutableDictionary *expressions;
    if (self.pb_expressions == nil) {
        expressions = [[NSMutableDictionary alloc] init];
        self.pb_expressions = expressions;
    } else {
        expressions = [NSMutableDictionary dictionaryWithDictionary:self.pb_expressions];
    }
    [expressions setObject:aExpression forKey:keyPath];
    [self setValue:@(YES) forAdditionKey:@"pb_expressible"];
}

- (BOOL)hasExpressionForKeyPath:(NSString *)keyPath
{
    if (self.pb_expressions == nil) {
        return NO;
    }
    return [[self.pb_expressions allKeys] containsObject:keyPath];
}

- (UIViewController *)supercontroller
{
    id controller = self;
    while ((controller = [controller nextResponder]) != nil) {
        if ([controller isKindOfClass:[UIViewController class]]) {
            return [self topcontroller:controller];
        }
        
        if ([controller isKindOfClass:[UIWindow class]]) {
            return [self topcontroller:[(id)controller rootViewController]];
        }
    }
    return controller;
}

- (UIViewController *)topcontroller:(UIViewController *)controller
{
    UIViewController *presentedController = [controller presentedViewController];
    if (presentedController != nil) {
        return [self topcontroller:presentedController];
    }
    
    if ([controller isKindOfClass:[UINavigationController class]]) {
        return [self topcontroller:[(id)controller topViewController]];
    }
    
    if ([controller isKindOfClass:[UITabBarController class]]) {
        return [self topcontroller:[(id)controller selectedViewController]];
    }
    
    return controller;
}

- (id)rootData
{
    UIView * view = self;
    while (view != nil && view.plist == nil) {
        view = [view superview];
    }
    if (view == nil) {
        return nil;
    }
    return view.data;
}

- (id)superviewWithClass:(Class)clazz
{
    id view = [self superview];
    while (![view isKindOfClass:clazz]) {
        view = [view superview];
        if (view == nil) {
            break;
        }
    }
    return view;
}

- (UIView *)viewWithAlias:(NSString *)alias
{
    if (alias == nil) {
        return nil;
    }
    
    if ([alias isKindOfClass:[NSNumber class]]) {
        return [self viewWithTag:[alias integerValue]];
    }
    
    NSInteger tag;
    NSScanner *scanner = [NSScanner scannerWithString:alias];
    if ([scanner scanInteger:&tag]) {
        return [self viewWithTag:tag];
    }
    
    return [self _lookupViewWithAlias:alias];
}

- (UIView *)_lookupViewWithAlias:(NSString *)alias {
    if ([self.alias isEqualToString:alias]) {
        return self;
    }
    for (UIView *subview in self.subviews) {
        UIView *theView = [subview _lookupViewWithAlias:alias];
        if (theView != nil) {
            return theView;
        }
    }
    return nil;
}

#pragma mark - Addition properties

- (void)setPb_unmappableKeys:(NSMutableArray *)keys {
    [self setValue:keys forAdditionKey:@"pb_unmappableKeys"];
}

- (NSMutableArray *)pb_unmappableKeys {
    return [self valueForAdditionKey:@"pb_unmappableKeys"];
}

- (void)setPb_constants:(NSDictionary *)constants {
    [self setValue:constants forAdditionKey:@"pb_constants"];
}

- (NSDictionary *)pb_constants {
    return [self valueForAdditionKey:@"pb_constants"];
}

- (void)setPb_expressions:(NSDictionary *)expressions {
    [self setValue:expressions forAdditionKey:@"pb_expressions"];
}

- (NSDictionary *)pb_expressions {
    return [self valueForAdditionKey:@"pb_expressions"];
}

- (void)set_pbPlistURL:(NSURL *)value {
    [self setValue:value forAdditionKey:@"_pbPlistURL"];
}

- (NSURL *)_pbPlistURL {
    return [self valueForAdditionKey:@"_pbPlistURL"];
}

- (void)set_pbClients:(NSArray *)value {
    [self setValue:value forAdditionKey:@"_pbClients"];
}

- (NSArray *)_pbClients {
    return [self valueForAdditionKey:@"_pbClients"];
}

- (void)set_pbActionClients:(NSDictionary *)value {
    [self setValue:value forAdditionKey:@"_pbActionClients"];
}

- (NSDictionary *)_pbActionClients {
    return [self valueForAdditionKey:@"_pbActionClients"];
}

- (void)set_pbClientMappers:(NSArray *)value {
    [self setValue:value forAdditionKey:@"_pbClientMappers"];
}

- (NSArray *)_pbClientMappers {
    return [self valueForAdditionKey:@"_pbClientMappers"];
}

- (void)setPB_internalMapper:(PBMapper *)value {
    [self setValue:value forAdditionKey:@"PB_internalMapper"];
}

- (PBMapper *)PB_internalMapper {
    return [self valueForAdditionKey:@"PB_internalMapper"];
}

- (void)set_pbActionMappers:(NSDictionary *)value {
    [self setValue:value forAdditionKey:@"_pbActionMappers"];
}

- (NSDictionary *)_pbActionMappers {
    return [self valueForAdditionKey:@"_pbActionMappers"];
}

- (void)setPlist:(NSString *)value {
    [self setValue:value forAdditionKey:@"plist"];
}

- (NSString *)plist {
    return [self valueForAdditionKey:@"plist"];
}

- (void)setClients:(NSArray *)value {
    [self setValue:value forAdditionKey:@"clients"];
}

- (NSArray *)clients {
    return [self valueForAdditionKey:@"clients"];
}

- (void)setActions:(NSDictionary *)value {
    [self setValue:value forAdditionKey:@"actions"];
}

- (NSDictionary *)actions {
    return [self valueForAdditionKey:@"actions"];
}

- (void)setClient:(NSString *)value {
    [self setValue:value forAdditionKey:@"client"];
}

- (NSString *)client {
    return [self valueForAdditionKey:@"client"];
}

- (void)setClientAction:(NSString *)value {
    [self setValue:value forAdditionKey:@"clientAction"];
}

- (NSString *)clientAction {
    return [self valueForAdditionKey:@"clientAction"];
}

- (void)setClientParams:(NSDictionary *)value {
    [self setValue:value forAdditionKey:@"clientParams"];
}

- (NSDictionary *)clientParams {
    return [self valueForAdditionKey:@"clientParams"];
}

- (void)setData:(id)value {
    [self setValue:value forAdditionKey:@"data"];
}

- (id)data {
    return [self valueForAdditionKey:@"data"];
}

- (void)setHref:(NSString *)value {
    [self setValue:value forAdditionKey:@"href"];
}

- (NSString *)href {
    return [self valueForAdditionKey:@"href"];
}

- (void)setHrefParams:(NSDictionary *)value {
    [self setValue:value forAdditionKey:@"hrefParams"];
}

- (NSDictionary *)hrefParams {
    return [self valueForAdditionKey:@"hrefParams"];
}

- (void)setLoadingDelegate:(id<PBViewLoadingDelegate>)value {
    [self setValue:value forAdditionKey:@"loadingDelegate"];
}

- (id<PBViewLoadingDelegate>)loadingDelegate {
    return [self valueForAdditionKey:@"loadingDelegate"];
}

- (void)setPb_preparation:(void (^)(void))value {
    [self setValue:value forAdditionKey:@"pb_preparation"];
}

- (void (^)(void))pb_preparation {
    return [self valueForAdditionKey:@"pb_preparation"];
}

- (void)setPb_transformation:(id (^)(id, NSError *))value {
    [self setValue:value forAdditionKey:@"pb_transformation"];
}

- (id (^)(id, NSError *))pb_transformation {
    return [self valueForAdditionKey:@"pb_transformation"];
}

- (void)setPb_complection:(void (^)(void))value {
    [self setValue:value forAdditionKey:@"pb_complection"];
}

- (void (^)(void))pb_complection {
    return [self valueForAdditionKey:@"pb_complection"];
}

- (void)setPb_loadingCount:(NSInteger)value {
    [self setValue:[NSNumber numberWithInteger:value] forAdditionKey:@"pb_loadingCount"];
}

- (NSInteger)pb_loadingCount {
    return [[self valueForAdditionKey:@"pb_loadingCount"] integerValue];
}

- (void)setPb_interrupted:(BOOL)value {
    [self setValue:[NSNumber numberWithBool:value] forAdditionKey:@"pb_interrupted"];
}

- (BOOL)pb_interrupted {
    return [[self valueForAdditionKey:@"pb_interrupted"] boolValue];
}

- (void)setAlias:(NSString *)alias {
    [self setValue:alias forAdditionKey:@"alias"];
}

- (NSString *)alias {
    return [self valueForAdditionKey:@"alias"];
}

@end

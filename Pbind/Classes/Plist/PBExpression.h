//
//  PBExpression.h
//  Pbind <https://github.com/wequick/Pbind>
//
//  Created by galen on 15/2/26.
//  Copyright (c) 2015-present, Wequick.net. All rights reserved.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>

typedef enum : NSUInteger {
    PBMapToData             = 0x1,
    PBMapToOwnerView        = 0x1 << 1,
    PBMapToOwnerViewData    = 0x1 << 2,
    
    PBMapToFormFieldText    = 0x1 << 3,
    PBMapToFormFieldValue   = 0x1 << 4,
    PBMapToFormFieldError   = 0x1 << 5,
    PBMapToFormField        = 0x1 << 6,
    PBMapToForm             = 0x1 << 7,
    
    PBMapToActiveController = 0x1 << 8,
    PBMapToAliasView        = 0x1 << 9,
    
    PBMapToActionState      = 0x1 << 10,
    PBMapToActionStateData  = 0x1 << 11,
    
    PBMapToContext          = 0x1 << 12,
    
    PBMapToTemporary        = 0x1 << 13,
    
    PBMapToAllContext       = PBMapToContext | PBMapToOwnerView | PBMapToOwnerViewData | PBMapToForm | PBMapToActiveController | PBMapToAliasView,
    PBMapToAll              = 0xFFFF
} PBMapType;

/**
 This class is used to parse the expressions configure in Plist.
 
 @discussion Each expression is composed by `[binding flag][unary op][tag][key][multi op][right value]`.
 
 The [flag] is optional, supports:
 
 * '='      -> oneway binding, notifys view to update while the data source value changed
 * '=='     -> duplex binding, notifys each other to update on the other value changed.
 
 If was not defined, just map the data to the view.
 
 The [unary op] is optional, supports:
 
 * '!'      -> logic not
 * '-'      -> negative
 * '~'      -> animated while setting the value for the key of the owner
 
 The [tag] is required, declares the binding data source, supports:
 
 * '$'      -> value for the key of the fetching data
 * '$[0-9]' -> value for the key of the fetching data's element at the index
 * '.'      -> value for the key of the owner view
 * '.$'     -> value for the key of the owner view data
 * '@^'     -> value for the key of the owner view controller
 * '@xx.'   -> value for the key of the alias view (by [view setAlias:@"xx"])
 * '@>'     -> value for the key of the owner form
 * '>'      -> text for the owner form's key-named input
 * '>$'     -> value for the owner form's key-named input
 * '>!'     -> error of the owner form's key-named input
 * '#.'     -> the action state of the default action store
 * '#$'     -> the action state data of the default action store
 
 The [multi op] is optional, supports:
 
 * '+', '-', '*', '/'                       -> arithmetic operators
 * '>', '<', '=', '==', '>=', '<=', '!='    -> comparision operators
 * '?:', '? * : *'                          -> conditional operators
 
 The [right value] is optional, follows by [multi op] only, and only supports constant now.
 
 */
@interface PBExpression : NSObject
{
    struct {
        // unary operators
        unsigned int unaryNot:2;    // '!', '!!' before variable
        unsigned int negative:1;    // '-' before variable
        unsigned int animated:1;    // '~'
        
        // arithmetic operators
        unsigned int plus:1;        // '+'
        unsigned int minus:1;       // '-' after variable
        unsigned int times:1;       // '*'
        unsigned int divide:1;      // '/'
        
        // conditional operators
        unsigned int test:1;        // '?'
        unsigned int unaryTest:1;   // '?:'
        
        // flags
        unsigned int onewayBinding:1;   // '='
        unsigned int duplexBinding:1;   // '=='
        
        // comparision operators
        unsigned int lesser:1;      // '<'
        unsigned int greater:1;     // '>'
        unsigned int equal:2;       // '=', '=='
        
        unsigned int multiNot:1;    // '!' after variable

        // tags
        unsigned int mapToData:1;               // '$'
        unsigned int mapToOwnerView:1;          // '.'
        unsigned int mapToOwnerViewData:1;      // '.$'
        
        unsigned int mapToFormFieldText:1;      // '>'
        unsigned int mapToFormFieldValue:1;     // '>$'
        unsigned int mapToFormFieldError:1;     // '>!'
        unsigned int mapToFormField:1;          // '>name.'
        unsigned int mapToForm:1;               // '@>'
        
        unsigned int mapToContext:1;            // '@.'
        unsigned int mapToAliasView:1;          // '@alias.'
        unsigned int mapToActiveController:1;   // '@^'
        unsigned int mapToTemporary:1;          // '@~'
        
        unsigned int mapToActionState:1;        // '#.'
        unsigned int mapToActionStateData:1;    // '#$' <==> '#.data'
        
        unsigned int disabled:1;
        
        unsigned int dataTag:8;                 // '0-9' for multi data, other for user-defined tag. Default is 0xFF(unset).
        
    } _flags;
    
    NSString *_format;
    NSString *_variable;    // the key of the data source
    NSString *_rvalue;      // right value, accepts constants only
    NSString *_rvalueForTrue; // for `?:' expression, value after '?', accepts constants only
    NSString *_alias;
    
    NSString *_bindingKeyPath;  // the owner's keyPath binding with `_variable'
    __weak id _bindingOwner;
    __unsafe_unretained id _bindingData;
    id _initialDataSourceValue;
    __unsafe_unretained id _originalBindingOwner;
}

+ (instancetype)expressionWithString:(NSString *)aString;

/**
 The parent expression, usually is an instance of PBMutableExpression.
 
 @discussion On binding mode, use to notify the parent expression re-calculated.
 
 Example: suppose current expression is `$name` and parent is `%(hello %@!),$name`, 
 if the `$name` changed to be 'someone', then the parent value should be 'hello someone!'.
 */
@property (nonatomic, weak) PBExpression *parent;

/**
 Whether the expression can be map or bound.
 
 @discussion Default is YES. If set to NO, then will abort on following methods:
 
 - `mapData:toTarget:forKeyPath:inContext`
 - `bindData:toTarget:forKeyPath:inContext`
 */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (instancetype)initWithString:(NSString *)aString;

- (id)valueWithData:(id)data;
- (id)valueWithData:(id)data target:(id)target;
- (id)valueWithData:(id)data target:(id)target owner:(UIView *)owner context:(UIView *)context;
- (id)valueWithData:(id)data keyPath:(NSString *)keyPath target:(id)target owner:(UIView *)owner context:(UIView *)context;

- (void)bindData:(id)data toTarget:(id)target forKeyPath:(NSString *)targetKeyPath withOwner:(UIView *)owner inContext:(UIView *)context;
- (void)mapData:(id)data toTarget:(id)target forKeyPath:(NSString *)targetKeyPath withOwner:(UIView *)owner inContext:(UIView *)context;
- (BOOL)matchesType:(PBMapType)type dataTag:(unsigned char)dataTag;

/**
 Unobserve the target.

 @param target the observed target
 */
- (void)unbind:(id)target forKeyPath:(NSString *)keyPath;

#pragma mark - Debugging
///=============================================================================
/// @name Debugging
///=============================================================================

/** The expression text, for debugger output. */
- (NSString *)stringValue;

/** The expression source (string or dictionary) */
- (id)source;

@end

FOUNDATION_EXTERN const unsigned char PBDataTagUnset;

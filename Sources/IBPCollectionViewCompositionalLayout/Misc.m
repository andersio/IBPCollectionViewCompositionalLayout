#import <Foundation/Foundation.h>
#import "Misc.h"

void __attribute__((noreturn)) SubclassMustOverride(SEL selector) {
    NSString *reason = [NSString stringWithFormat:@"A `IBPHierarchicalSolver` subclass must implement `%@`.",
                        NSStringFromSelector(selector)];
    @throw [NSException exceptionWithName:@"Unimplemented method"
                                   reason:reason
                                 userInfo:nil];
}

void __attribute__((noreturn)) NotImplemented(NSString *behaviorDescription) {
    NSString *reason = [NSString stringWithFormat:@"Behavior is not implemented: %@.", behaviorDescription];
    @throw [NSException exceptionWithName:@"Behavior is not implemented"
                                   reason:reason
                                 userInfo:nil];
}

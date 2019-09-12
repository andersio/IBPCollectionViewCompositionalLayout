#import <UIKit/UIKit.h>
#define CGVectorZero CGVectorMake(0.0, 0.0)

#define CGVectorEqual(lhs, rhs) (lhs.dx == rhs.dx && lhs.dy == rhs.dy)
#define CGPointOffsetY(lhs, rhs) CGPointMake(rhs.x, rhs.y + lhs)
#define CGPointOffsetX(lhs, rhs) CGPointMake(rhs.x + lhs, rhs.y)
#define CGVectorAdd(lhs, rhs) CGVectorMake(lhs.dx + rhs.dx, lhs.dy + rhs.dy)

//
//  main.m
//  RuntimeAsmModify
//
//  Created by 周维鸥 on 2018/12/12.
//  Copyright © 2018年 周维鸥. All rights reserved.
//

#import <Foundation/Foundation.h>

int foo()
{
    int a=10;
    return a;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        int a=foo();
        NSLog(@"a is %d",a);
    }
    return 0;
}

//
//  AsmModifyDynamic.m
//  AsmModifyDynamic
//
//  Created by 周维鸥 on 2018/12/13.
//  Copyright © 2018年 周维鸥. All rights reserved.
// ref:// https://bbs.pediy.com/thread-198299.htm
// https://stackoverflow.com/questions/13598571/ios-patch-program-instruction-at-runtime

#import "AsmModifyDynamic.h"
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include "pthread.h"

#include <sys/types.h>
#include <sys/ptrace.h>
#include <sys/sysctl.h>

#include <mach/mach.h>
#include <mach/mach_init.h>
#include <mach/mach_vm.h>

#include "libkern/OSCacheControl.h"

#define kerncall(x) ({ \
    kern_return_t _kr = (x); \
    if(_kr != KERN_SUCCESS) \
        fprintf(stderr, "%s failed with error code: 0x%x\n", #x, _kr); \
    _kr; \
})

mach_vm_address_t getBasicAddress(int pid){
    mach_vm_size_t region_size = 0;
    mach_vm_address_t region = 0;
    mach_port_t task = 0;
    int ret = 0;
    
    ret = task_for_pid(mach_task_self(),pid,&task);
    if (ret != 0)
    {
        printf("task_for_pid() message %s!\n",mach_error_string(ret));
        return 0;
    }
    
    /* Get region boundaries */
#if defined(_MAC64) || defined(__LP64__)
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO_64;
    if ((ret = mach_vm_region(mach_task_self(), &region, &region_size, flavor, (vm_region_info_t)&info,
                              (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task)) != KERN_SUCCESS)
    {
        printf("mach_vm_region() message %s!\n",mach_error_string(ret));
        return 0;
    }
#else
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
    if ((ret = vm_region(mach_task_self(), ®ion, ®ion_size, flavor, (vm_region_info_t)&info,
                         (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task)) != KERN_SUCCESS)
    {
        printf("vm_region() message %s!\n",mach_error_string(ret));
        return NULL;
    }
#endif
    return region;
}

vm_size_t readRemotoMemory(char *buf,vm_size_t len,int pid,vm_address_t address)
{
    vm_size_t outSize = 0;
    mach_port_t task = 0;
    
    int ret = task_for_pid(mach_task_self(),pid,&task);
    if (ret != 0)
    {
        printf("task_for_pid() message %s!\n",mach_error_string(ret));
        return 0;
    }
    
    ret = vm_read_overwrite(task,address,len,(vm_address_t)buf,&outSize);
    if (ret != 0)
    {
        printf("vm_read_overwrite() message %s!\n",mach_error_string(ret));
        return 0;
    }
    return outSize;
}

int FakeCode(char *addr, char code)
{
    mach_port_t task;
    mach_vm_size_t region_size = 0;
    mach_vm_address_t region = (vm_address_t)addr;
    
    /* Get region boundaries */
#if defined(_MAC64) || defined(__LP64__)
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO_64;
    if (mach_vm_region(mach_task_self(), &region, &region_size, flavor, (vm_region_info_t)&info, (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task) != 0)
    {
        return 0;
    }
#else
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
    if (vm_region(mach_task_self(), ®ion, ®ion_size, flavor, (vm_region_info_t)&info, (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task) != 0)
    {
        return 0;
    }
#endif
    
    /* Change memory protections to rw- */
    if (vm_protect(mach_task_self(), region, region_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS)
    {
        //_LineLog();
        return 0;
    }
    
    /* Actually perform the write */
    *addr = code;
    
    /* Flush CPU data cache to save write to RAM */
    sys_dcache_flush(addr, sizeof(code));
    
    /* Invalidate instruction cache to make the CPU read patched instructions from RAM */
    sys_icache_invalidate(addr, sizeof(code));
    
    /* Change memory protections back to r-x */
    vm_protect(mach_task_self(), region, region_size, 0, VM_PROT_EXECUTE | VM_PROT_READ);
    return 1;
}

void* handler(void *p)
{
    //int pid = 16057;
    int pid = getpid();
    char buffer[512];
    mach_vm_address_t address = 0;
    
    address = getBasicAddress(pid);
    
    //printf("Target pid     : %d\n",pid);
    //printf("Base address   : %llx\n", address);
    
    if (address == 0)
    {
        printf("getBasicAddress() faild!\n");
        return NULL;
    }
    
    //Demo
    char *demo = (char*)address + 0x329a9e;
    demo[0] = ' ';
    demo[1] = ' ';
    demo[2] = ' ';
    demo[3] = ' ';
    
    //Demo version
    char *dv = (char*)address + 0x329E8C;
    dv[0] = 'F';
    dv[1] = 'u';
    dv[2] = 'l';
    dv[3] = 'l';
    
    //Waiting for decode __text
    sleep(1);
    
    //checkRegistrationLicense:
    //xor ebx,ebx    =>    mov     $1,%bl
    //xor edi,edi    =>    inc     %edi
    *(uint32_t*)(address + 0xb9b7) = 0xc7ff01b3;
    
    //checkRegistrationToken
    // xor r14d,r14d => inc r14d
    *(uint8_t*)(address + 0xb974)     = 0x41;
    *(uint8_t*)(address + 0xb974 + 1) = 0xff;
    *(uint8_t*)(address + 0xb974 + 2) = 0xc6;
    
    return NULL;
}

void* handler1(void *p)
{
    int pid = getpid();
//    char buffer[512];
    mach_vm_address_t address = 0;
    mach_vm_address_t region = 0;
    address = getBasicAddress(pid);
    
    printf("Target pid     : %d\n",pid);
    printf("Base address   : %llx\n", address);
    
    if (address == 0)
    {
        printf("getBasicAddress() faild!\n");
        return NULL;
    }
    
    mach_port_t task;
    mach_vm_size_t region_size = 0;
    
    /* Get region boundaries */
#if defined(_MAC64) || defined(__LP64__)
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO_64;
    if (mach_vm_region(mach_task_self(), &region, &region_size, flavor, (vm_region_info_t)&info, (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task) != 0)
    {
        return 0;
    }
#else
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
    vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
    if (vm_region(mach_task_self(), ®ion, ®ion_size, flavor, (vm_region_info_t)&info, (mach_msg_type_number_t*)&info_count, (mach_port_t*)&task) != 0)
    {
        return 0;
    }
#endif
    
    /* Change memory protections to rw- */
    if (vm_protect(mach_task_self(), region, region_size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS)
    {
        //_LineLog();
        return 0;
    }
    // mov $0xb, -0x4(%rbp)
    *(uint8_t*)(address + 0xf17)=0xb;
    mach_vm_address_t addr=address + 0xf17;
    /* Flush CPU data cache to save write to RAM */
    sys_dcache_flush((uint8_t*)addr, sizeof(uint8_t));
    
    /* Invalidate instruction cache to make the CPU read patched instructions from RAM */
    sys_icache_invalidate((uint8_t*)addr, sizeof(uint8_t));
    
    /* Change memory protections back to r-x */
    vm_protect(mach_task_self(), region, region_size, 0, VM_PROT_EXECUTE | VM_PROT_READ);
    return NULL;
}

__attribute__((constructor))
static void dumpexecutable() {
    printf("dynamic lib running\n");
    //    _dyld_register_func_for_add_image(&image_added);
    int err;
    pthread_t ntid;
    err = pthread_create(&ntid, NULL, handler1, NULL);
    if (err != 0)
    {
        printf("can't create thread: %s\n", strerror(err));
        return ;
    }
}

@implementation AsmModifyDynamic

@end

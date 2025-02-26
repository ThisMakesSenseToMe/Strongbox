//
//  main.m
//  autofill-proxy
//
//  Created by Strongbox on 13/08/2022.
//  Copyright © 2022 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AutoFillProxy.h"
#import "StreamUtils.h"

#import <signal.h>
#include <sys/types.h>
#include <netinet/in.h>
#import <sys/socket.h>
#import <sys/un.h>
#include <errno.h>

#import "Utils.h"

static const int MAX_PATH = 103;

NSString* _Nullable getSocketPath(BOOL hardcodeSandboxTestingPath) {
    NSURL* url = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:@"group.strongbox.mac.mcguill"];


#ifdef DEBUG
    if ( hardcodeSandboxTestingPath ) {
        NSString* foo = [@"~/Library/Group Containers/group.strongbox.mac.mcguill/F" stringByExpandingTildeInPath];
        NSLog(@"⚠️ WARN: Hardcoded Sandbox Path used for Socket. Make sure this is only used in Test mode! [%@] => %ld chars", foo, foo.length);
        return foo;
    }
#endif
    
    NSString* path = [url.path stringByAppendingPathComponent:@"F"];
    

    
    if ( path.length > MAX_PATH ) {
        NSLog(@"🔴 Could not create socket, socket path > %d chars [%@] = %ld chars", MAX_PATH, path, path.length);
        return nil;
    }

    BOOL mkDir = [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    
    if ( !mkDir ) {
        NSLog(@"🔴 Couldn't create directory for local socket");
    }
    
    return path;
}

id readJsonObjectFromInputStream (NSInputStream* inputStream, BOOL returnJsonInsteadOfObject ) {
    const int BUFFER_LEN = 16*1024;
    NSMutableData* tmpBuffer = [NSMutableData dataWithLength:BUFFER_LEN];
    
    NSInteger read = 0;
    NSMutableData* inBuf = NSMutableData.data;
    
    id object = nil;
    while ( 1 ) {
        read = [inputStream read:tmpBuffer.mutableBytes maxLength:BUFFER_LEN];
        if ( read < 0 ) {
            
            NSLog(@"🔴 read error");
            return nil; 
        }
        
        if ( read > 0 ) {

            [inBuf appendBytes:tmpBuffer.bytes length:read];
        }
        else {
            NSLog(@"🔴 Read 0 Bytes?!");
        }
        
        NSError* error;
        object = [NSJSONSerialization JSONObjectWithData:inBuf options:kNilOptions error:&error];
        
        if ( object ) {

            break;
        }
        if ( read == 0 ) {
            NSLog(@"🔴 Read entire message but couldn't get object!");
            break;
        }
    }

    NSString* json = object ? [[NSString alloc] initWithData:inBuf encoding:NSUTF8StringEncoding] : nil;
    

    
    return returnJsonInsteadOfObject ? json : object;
}

NSString* sendMessageOverSocket (NSString* request, BOOL hardcodeSandboxTestingPath, NSError** error) {
    NSString* path = getSocketPath(hardcodeSandboxTestingPath);
    if ( !path ) {
        NSLog(@"🔴 Socket path too long to create. Check Users Home Path length");
        
        if ( error ) {
            *error = [Utils createNSError:[NSString stringWithFormat:@"Socket path too long to create. > %d chars. Check Users Home Path length.", MAX_PATH] errorCode:-1];
        }

        return nil;
    }
    
    struct sockaddr_un sun;
    sun.sun_family = AF_UNIX;
    strcpy (sun.sun_path, [path cStringUsingEncoding:NSUTF8StringEncoding]);
    sun.sun_len = SUN_LEN(&sun);

    int s = socket (AF_UNIX, SOCK_STREAM, 0);

    int connectReturn = connect (s, (struct sockaddr *)&sun, sun.sun_len);
    if ( connectReturn < 0 ) {
        NSString* errMsg = [NSString stringWithFormat:@"connect failed! [%s]", strerror(errno)];
        NSLog(@"%@", errMsg);
        
        if ( error ) {
            *error = [Utils createNSError:errMsg errorCode:-1];
        }
                
        return nil;
    }

    NSData* data = [request dataUsingEncoding:NSUTF8StringEncoding];

    NSLog(@"UTF8 Encoded to %lu length", data.length);
    
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocket (kCFAllocatorDefault, s, &readStream, &writeStream);

    NSOutputStream *outputStream = (__bridge_transfer NSOutputStream *)writeStream;

    [outputStream open];
    [outputStream write:data.bytes maxLength:data.length];

    NSInputStream *inputStream = (__bridge_transfer NSInputStream *)readStream;
    
    [inputStream open];

    id json = readJsonObjectFromInputStream(inputStream, YES);
    
    [inputStream close];
    
    [outputStream close];

    shutdown(s, SHUT_RDWR);
    close(s);
    
    return json;
}

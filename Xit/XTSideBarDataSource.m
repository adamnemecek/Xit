//
//  XTSideBarDataSource.m
//  Xit
//
//  Created by German Laullon on 17/07/11.
//

#import "XTSideBarDataSource.h"
#import "XTSideBarItem.h"
#import "Xit.h"
#import "XTLocalBranchItem.h"
#import "XTTagItem.h"
#import "XTRemotesItem.h"

@implementation XTSideBarDataSource

- (id)init
{
    self = [super init];
    if (self) {
        XTSideBarItem *branchs=[[XTSideBarItem alloc] initWithTitle:@"Branchs"];
        XTSideBarItem *tags=[[XTSideBarItem alloc] initWithTitle:@"Tags"];
        XTRemotesItem *remotes=[[XTRemotesItem alloc] initWithTitle:@"Remotes"];
        roots=[NSArray arrayWithObjects:branchs,tags,remotes,nil];
    }
    
    return self;
}

-(void)setRepo:(Xit *)newRepo
{
    repo=newRepo;
}

-(void)reload
{
    NSData *output=[repo exectuteGitWithArgs:[NSArray arrayWithObject:@"show-ref"] error:nil];
    if(output){
        NSString *refs = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        NSScanner *scan = [NSScanner scannerWithString:refs];
        NSString *commit;
        NSString *name;
        while ([scan scanUpToString:@" " intoString:&commit]) {
            [scan scanUpToString:@"\n" intoString:&name];
            if([name hasPrefix:@"refs/heads/"]){
                XTSideBarItem *branchs=[roots objectAtIndex:XT_BRANCHS];
                XTLocalBranchItem *branch=[[XTLocalBranchItem alloc] initWithTitle:[name lastPathComponent]];
                [branchs addchildren:branch];
            }else if([name hasPrefix:@"refs/tags/"]){
                XTSideBarItem *branchs=[roots objectAtIndex:XT_TAGS];
                XTTagItem *tag=[[XTTagItem alloc] initWithTitle:[name lastPathComponent]];
                [branchs addchildren:tag];
            }else if([name hasPrefix:@"refs/remotes/"]){
                XTRemotesItem *remotes=[roots objectAtIndex:XT_REMOTES];
                NSString *remoteName=[[name pathComponents] objectAtIndex:2];
                NSString *branchName=[name lastPathComponent];
                XTSideBarItem *remote=[remotes getRemote:remoteName];
                if(remote==nil){
                    remote=[[XTSideBarItem alloc] initWithTitle:remoteName];
                    [remotes addchildren:remote];
                }
                XTLocalBranchItem *branch=[[XTLocalBranchItem alloc] initWithTitle:branchName];
                [remote addchildren:branch];
            }
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    NSInteger res=0;
    if(item==nil){
        res=[roots count];
    }else if([item isKindOfClass:[XTSideBarItem class]]){
        XTSideBarItem *sbItem=(XTSideBarItem *)item;
        res=[sbItem numberOfChildrens];
    }    
    return res;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    BOOL res=NO;
    if([item isKindOfClass:[XTSideBarItem class]]){
        XTSideBarItem *sbItem=(XTSideBarItem *)item;
        res=[sbItem isItemExpandable];
    }
    return res;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    id res=nil;
    if(item==nil){
        res=[roots objectAtIndex:index];
    }else if([item isKindOfClass:[XTSideBarItem class]]){
        XTSideBarItem *sbItem=(XTSideBarItem *)item;
        res=[sbItem children:index];
    }
    return res;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    NSString *res=nil;
    if([item isKindOfClass:[XTSideBarItem class]]){
        XTSideBarItem *sbItem=(XTSideBarItem *)item;
        res=[sbItem title];
    }
    return res;
}

@end
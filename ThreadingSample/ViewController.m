//
//  ViewController.m
//  ThreadingSample
//
//  Created by Lasse Koskela on 10.3.2016.
//  Copyright © 2016 Lasse Koskela. All rights reserved.
//

@import Foundation;

#import "ViewController.h"

#import <BRFullTextSearch/BRFullTextSearch.h>
#import <BRFullTextSearch/CLuceneSearchService.h>


@interface ViewController ()
@property (nonatomic, strong) CLuceneSearchService *service;
@property (nonatomic, retain) dispatch_queue_t indexQueue;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *data;
@property (nonatomic, strong) NSTimer *indexModificationTimer;
@property (atomic, assign) int numberOfPendingOperations;
@property (nonatomic, strong) UILabel *resultsLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSLog(@"viewDidLoad creating SerialIndexQueue");
    self.indexQueue = dispatch_queue_create("SerialIndexQueue", DISPATCH_QUEUE_SERIAL);

    NSLog(@"viewDidLoad creating CLuceneSearchService");
    self.service = [[CLuceneSearchService alloc] initWithIndexPath:[self pathForLuceneIndex]];
    self.service.defaultAnalyzerLanguage = @"fi";
    self.service.stemmingDisabled = NO;
    self.service.supportStemmedPrefixSearches = YES;

    self.numberOfPendingOperations = 0;

    self.resultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 0, 0)];
    self.resultsLabel.textColor = [UIColor blackColor];
    self.view.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.resultsLabel];

    NSLog(@"viewDidLoad generating fake documents");
    int datasetSize = 100;
    self.data = [NSMutableArray arrayWithCapacity:datasetSize];
    for (int i = 0; i < datasetSize; i++) {
        NSMutableDictionary<NSString *, NSString *> *doc = [NSMutableDictionary new];
        [doc setObject:[NSString stringWithFormat:@"doc-%d", i] forKey:kBRSearchFieldNameIdentifier];
        [doc setObject:@"Enumerating Arrays" forKey:kBRSearchFieldNameTitle];
        [doc setObject:@"It's pretty easy to integrate BRFullTextSearch with Core Data, to maintain a search index while changes are persisted in Core Data. One way is to listen for the NSManagedObjectContextDidSaveNotification notification and process Core Data changes as index delete and update operations. The SampleCoreDataProject project contains an example of this integration. The app allows you to create small sticky notes and search the text of those notes. See the CoreDataManager class in the sample project, whose maintainSearchIndexFromManagedObjectDidSave: method handles this." forKey:kBRSearchFieldNameValue];
        [self.data addObject:doc];
    }
    NSLog(@"viewDidLoad generated %lu fake documents", (unsigned long)self.data.count);
    NSLog(@"viewDidLoad ready");

    UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [self.view addGestureRecognizer:recognizer];
}

- (void)onTap:(UIGestureRecognizer *)recognizer {
    [self searchFor:@"text"];
}


- (void)viewDidAppear:(BOOL)animated {
    NSLog(@"viewDidAppear");
    [super viewDidAppear:animated];
    self.indexModificationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timer:) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    NSLog(@"viewWillDisappear");
    [self.indexModificationTimer invalidate];
    self.indexModificationTimer = nil;
}

- (void)timer:(id)userInfo {
    __weak ViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        __strong ViewController *strongSelf = weakSelf;
        if (strongSelf && strongSelf.numberOfPendingOperations < 200) {
            [strongSelf removeRandomDocuments];
        }
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        __strong ViewController *strongSelf = weakSelf;
        if (strongSelf && strongSelf.numberOfPendingOperations < 200) {
            [strongSelf addRandomDocuments];
        }
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [weakSelf searchRandomDocuments];
    });
}

- (void)removeRandomDocuments {
    __weak ViewController *weakSelf = self;
    int lo = (int)arc4random_uniform((int)self.data.count);
    int hi = lo + MIN(50, (int)arc4random_uniform((int)self.data.count - lo));
    for (int i = lo; i < hi; i++) {
        NSDictionary<NSString *, NSString *> *doc = [self.data objectAtIndex:i];
        NSString *identifier = doc[kBRSearchFieldNameIdentifier];
        self.numberOfPendingOperations++;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            dispatch_async(self.indexQueue, ^{
                __strong ViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf removeDocumentFromIndex:identifier];
                    strongSelf.numberOfPendingOperations--;
                }
            });
        });
    }
}

- (void)addRandomDocuments {
    __weak ViewController *weakSelf = self;
    int lo = (int)arc4random_uniform((int)self.data.count);
    int hi = lo + MIN(50, (int)arc4random_uniform((int)self.data.count - lo));
    for (int i = lo; i < hi; i++) {
        NSMutableDictionary<NSString *, NSString *> *doc = [NSMutableDictionary dictionaryWithDictionary:[self.data objectAtIndex:i]];
        NSString *identifier = doc[kBRSearchFieldNameIdentifier];
        [doc removeObjectForKey:kBRSearchFieldNameIdentifier];
        self.numberOfPendingOperations++;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            dispatch_async(self.indexQueue, ^{
                __strong ViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf addIndexableToIndex:identifier fields:doc];
                    strongSelf.numberOfPendingOperations--;
                }
            });
        });
    }
}

- (void)searchRandomDocuments {
    __weak ViewController *weakSelf = self;
    for (int i = 0; i < 100; i++) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            __strong ViewController *strongSelf = weakSelf;
            if (strongSelf) {
                NSString *needle = @"contain";
                for (NSUInteger j = needle.length; j > 0; j--) {
                    NSString *partialNeedle = [needle stringByReplacingCharactersInRange:NSMakeRange(j, needle.length - j) withString:@""];
                    [strongSelf searchFor:partialNeedle];
                }
            }
        });
    }
}

- (void)searchFor:(NSString *)text {
    __weak ViewController *weakSelf = self;
    NSString *query = [NSString stringWithFormat:@"%@:(%@) OR %@:(%@)", kBRSearchFieldNameTitle, text, kBRSearchFieldNameValue, text];
    dispatch_async(self.indexQueue, ^{
        __strong ViewController *strongSelf = weakSelf;
        if (strongSelf) {
            id<BRSearchResults> results = [strongSelf.service search:query];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong ViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf.resultsLabel.text = [NSString stringWithFormat:@"%ld hits", [results count]];
                    [strongSelf.resultsLabel sizeToFit];
                    [strongSelf.view setNeedsDisplay];
                }
            });
            [results iterateWithBlock:^(NSUInteger index, id<BRSearchResult>result, BOOL *stop) {
                //NSLog(@"Found result: %@", [result dictionaryRepresentation]);
            }];
        }
    });
}

- (NSString *)pathForLuceneIndex {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *urls = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSString *indexFileName = [NSString stringWithFormat:@"%@-%@", [[NSBundle mainBundle] bundleIdentifier], @"lucene.index"];
    return [urls[0] URLByAppendingPathComponent:indexFileName].path;
}

- (void)addIndexableToIndex:(NSString *)identifier fields:(NSDictionary<NSString *, NSString *> *)fields {
    BRSimpleIndexable *indexable = [[BRSimpleIndexable alloc] initWithIdentifier:identifier data:fields];
    [self addDocumentsToIndex:@[indexable]];
}

- (void)addDocumentsToIndex:(NSArray<BRSimpleIndexable *> *)documents {
    [self.service bulkUpdateIndexAndWait:^(id <BRIndexUpdateContext> updateContext) {
        for (BRSimpleIndexable *document in documents) {
            [self.service addObjectToIndex:document context:updateContext];
        }
    } error:nil];
}

- (void)removeDocumentFromIndex:(NSString *)identifier {
    [self.service bulkUpdateIndexAndWait:^(id <BRIndexUpdateContext> updateContext) {
        [self.service removeObjectFromIndex:BRSearchObjectTypeForString(@"?") withIdentifier:identifier context:updateContext];
    } error:nil];
}

@end

//
//  ViewController.m
//  Bayesian-iOS
//
//  Created by Even on 2018/8/15.
//  Copyright © 2018年 Even-Cheng. All rights reserved.
//

#import "ViewController.h"
#include "Segmentor.h"
#import "CYAlertView.h"
#import "TrueModel.h"
#import "FalseModel.h"

static NSString* const hitFileName = @"true.txt";
static NSString* const misFileName = @"false.txt";

@interface ViewController ()<UITextViewDelegate>

@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UIButton *sendButton;
@property (weak, nonatomic) IBOutlet UILabel *tipLabel;

@property (nonatomic, strong) NSMutableDictionary *tokensProbabilityTable;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.textView.delegate = self;
    
    //初始化数据库
    [self setDataModel];
    
    //初始化分词器
    [self initJieba];
    
    //读取数据
    [self setup];
}

- (void)setDataModel{
    if([TrueModel findByPK:1]) {
        return;
    }
    NSString* hitStringList = [self readListFromFileWithFileName:hitFileName];
    NSString* misStringList = [self readListFromFileWithFileName:misFileName];

    NSMutableArray* trues = [NSMutableArray array];
    for (NSString* content in [hitStringList componentsSeparatedByString:@"\n"]) {
        TrueModel* trueModel = [TrueModel new];
        trueModel.content = content;
        [trues addObject:trueModel];
    }
    [TrueModel saveObjects:trues.copy];
    
    NSMutableArray* falses = [NSMutableArray array];
    for (NSString* content in [misStringList componentsSeparatedByString:@"\n"]) {
        FalseModel* falseModel = [FalseModel new];
        falseModel.content = content;
        [falses addObject:falseModel];
    }
    [FalseModel saveObjects:falses.copy];
}

- (void)initJieba{
    NSString *dictPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"iosjieba.bundle/dict/jieba.dict.small.utf8"];
    NSString *hmmPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"iosjieba.bundle/dict/hmm_model.utf8"];
    NSString *userDictPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"iosjieba.bundle/dict/user.dict.utf8"];
    
    const char *cDictPath = [dictPath UTF8String];
    const char *cHmmPath = [hmmPath UTF8String];
    const char *cUserDictPath = [userDictPath UTF8String];
    
    JiebaInit(cDictPath, cHmmPath, cUserDictPath);
}

- (void)setup{
    NSArray* trues = [TrueModel findAll];
    NSMutableArray* marr = [NSMutableArray array];
    for (TrueModel* model in trues) {
        [marr addObject:model.content];
    }
    
    NSArray* falses = [FalseModel findAll];
    NSMutableArray* marrFalse = [NSMutableArray array];
    for (FalseModel* model in falses) {
        [marrFalse addObject:model.content];
    }
    _tokensProbabilityTable = [NSMutableDictionary dictionaryWithDictionary:[self tokensProbabilityTableFromMisStringList:marrFalse.copy andWithHitString:marr.copy]];
}

- (NSDictionary*)tokensProbabilityTableFromMisStringList:(NSArray*)misStringList andWithHitString:(NSArray*)hitStringList{
    
    NSMutableDictionary* hitCountTable = [NSMutableDictionary dictionary];
    for (NSString* hitString in hitStringList) {
        [self addTokensToCountTable:hitCountTable withTokens:[self tokensFromString:hitString]];
    }
    NSDictionary* hitProbabilityTable = [self probabilityTableFromCountTable:hitCountTable];
    
    
    NSMutableDictionary* misCountTable = [NSMutableDictionary dictionary];
    for (NSString* misString in misStringList) {
        [self addTokensToCountTable:misCountTable withTokens:[self tokensFromString:misString]];
    }
    NSDictionary* misProbabilityTable = [self probabilityTableFromCountTable:misCountTable];
    
    NSDictionary* tokensProbabilityTable = [self tokensProbabilityTableFromHitProbabilityTable:hitProbabilityTable andMisProbabilityTable:misProbabilityTable];
    
    return tokensProbabilityTable;
}

- (void)addTokensToCountTable:(NSMutableDictionary*)countTable withTokens:(NSArray*)tokens{
    for (NSString* token in tokens){
        countTable[token] = @(1);
    }
}

//从文件中读取数据
- (NSString*)readListFromFileWithFileName:(NSString*)fileName{
    
    NSError *error;
    NSString *path = [[NSBundle mainBundle]pathForResource:fileName ofType:nil];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"====%@",error.localizedDescription);
    } else {
        return content;
    }
    
    return @"";
}

//保存数据
- (void)writeToFileWithType:(BOOL)isTrue withContent:(NSString*)content{
    if(isTrue) {
        TrueModel* trueModel = [TrueModel new];
        trueModel.content = content;
        [trueModel save];
    } else {
        FalseModel* falseModel = [FalseModel new];
        falseModel.content = content;
        [falseModel save];
    }
    self.textView.text = @"";
    self.tipLabel.hidden = NO;
}


- (NSArray*)probabilityListFromTokens:(NSArray*)tokens andTokensProbabilityTable:(NSDictionary*)tokensProbabilityTable{
    
    NSMutableArray* probabilityList = [NSMutableArray array];
    for (NSString* token in tokens){

        if([tokensProbabilityTable.allKeys containsObject:token]){
            [probabilityList addObject:tokensProbabilityTable[token]];
        }
    }
    return probabilityList;
}

- (NSDictionary*)tokensProbabilityTableFromHitProbabilityTable:(NSDictionary*)hitProbabilityTable andMisProbabilityTable:(NSDictionary*)misProbabilityTable{
    
    NSMutableDictionary*probabilityTable = [NSMutableDictionary dictionary];
    
    for (NSString* key in hitProbabilityTable.allKeys) {
        if ([misProbabilityTable.allKeys containsObject:key]) {
            probabilityTable[key] = @([hitProbabilityTable[key] floatValue] / ([hitProbabilityTable[key] floatValue] + [misProbabilityTable[key] floatValue]));
        } else {
            probabilityTable[key] = @(1);
        }
    }
    
    for (NSString* key in misProbabilityTable.allKeys) {
        if (![hitProbabilityTable.allKeys containsObject:key]) {
            probabilityTable[key] = @(0);
        }
    }

    return probabilityTable.copy;
}

- (NSDictionary*)probabilityTableFromCountTable:(NSDictionary*)countTable{
    
    CGFloat totalCount = [self totalCountFromCountTable:countTable];
    NSMutableDictionary* probabilityTable = [NSMutableDictionary dictionary];
    for (NSString* key in countTable.allKeys) {
        probabilityTable[key] = @([countTable[key] floatValue] / totalCount);
    }
    return probabilityTable.copy;
}

- (CGFloat)totalCountFromCountTable:(NSDictionary*)countTable{
    CGFloat totalCount = 0.0f;
    for (NSString* key in countTable.allKeys) {
        totalCount += [countTable[key] floatValue];
    }
    return totalCount;
}

- (NSArray*)tokensFromString:(NSString*)string{
    
    const char* sentence = [string UTF8String];
    std::vector<std::string> words;
    JiebaCut(sentence, words);
    std::string result;
    result << words;
    NSString* cutText = [NSString stringWithUTF8String:result.c_str()] ;
    NSArray* tokens = [cutText componentsSeparatedByString:@","];
    return tokens;
}

- (CGFloat)eventProbabilityFromString:(NSString*)string andTokensProbabilityTable:(NSDictionary*)tokensProbabilityTable{
    
    NSArray* tokens = [self tokensFromString:string];
    NSArray* probabilityList = [self probabilityListFromTokens:tokens andTokensProbabilityTable:tokensProbabilityTable];
    CGFloat A = 1.0f;
    CGFloat B = 1.0f;
    for (NSNumber* probabilityNumber in probabilityList) {
        CGFloat probability = [probabilityNumber floatValue];
        A *= probability;
        B *= (1 - probability);
    }
    if(A + B == 0.0f) {
        return 0;
    }
    
    return A / (A + B);
}

- (IBAction)sendAction:(id)sender {
    
    NSString* filterStr = [[self.textView.text stringByReplacingOccurrencesOfString:@"\n" withString:@""] stringByReplacingOccurrencesOfString:@"\t" withString:@""];
    CGFloat probability = [self eventProbabilityFromString:filterStr andTokensProbabilityTable:self.tokensProbabilityTable];
    NSString* show = [NSString stringWithFormat:@"符合条件(白名单)的概率为：%.f%%",probability*100];
    
    CYAlertView* alert = [[CYAlertView alloc]initWithTitle:show message:@"请问是否修正验证结果？" clickedBlock:^(CYAlertView *alertView, BOOL cancelled, NSInteger buttonIndex) {
        
        if (cancelled) {
            self.textView.text = @"";
            self.tipLabel.hidden = NO;
            return;
        }
        [self writeToFileWithType:buttonIndex == 1 withContent:filterStr];
        
    } cancelButtonTitle:@"跳过" otherButtonTitles:@"加入白名单",@"加入黑名单",nil];
    
    [alert show];
}

- (void)textViewDidChange:(UITextView *)textView;{
    self.tipLabel.hidden = textView.text.length;
}


@end

//
//  DiscordBridge.h
//  cisum
//
//  Created by Aarav Gupta on 01/10/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DiscordBridge : NSObject
- (instancetype)initWithAppId:(uint64_t)appId;

/// Connect using a previously stored bearer token. Pass nil to run the full
/// browser OAuth flow instead.
- (void)connectWithAccessToken:(nullable NSString *)accessToken;

/// Exchange a stored refresh token for a fresh access token, then connect.
- (void)refreshWithRefreshToken:(NSString *)refreshToken;

- (void)runCallbacks;
- (void)updatePresenceWithDetails:(NSString *)details state:(NSString *)state;
- (void)clearPresence;

@property (nonatomic, copy, nullable) void (^onStatus)(NSString *status);
@property (nonatomic, copy, nullable) void (^onFriendsCount)(NSInteger count);
/// Fired after any successful token exchange (auth or refresh) so Swift can
/// persist the pair. `expiresIn` is seconds from now.
@property (nonatomic, copy, nullable) void (^onTokens)(NSString *accessToken, NSString *refreshToken, int32_t expiresIn);
/// Fired when the SDK says the current token is expiring; refresh and re-supply.
@property (nonatomic, copy, nullable) void (^onTokenNeedsRefresh)(void);
@end

NS_ASSUME_NONNULL_END

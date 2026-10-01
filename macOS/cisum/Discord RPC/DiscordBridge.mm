//
//  DiscordBridge.mm
//  cisum
//
//  Created by Aarav Gupta on 01/10/26.
//

#define DISCORDPP_IMPLEMENTATION   // exactly once, in this file only
#import "DiscordBridge.h"
#include "discordpp.h"
#include <memory>

@implementation DiscordBridge {
    std::shared_ptr<discordpp::Client> _client;
    uint64_t _appId;
    bool _callbacksReady;
}

- (instancetype)initWithAppId:(uint64_t)appId {
    if (self = [super init]) {
        _appId = appId;
        _callbacksReady = false;
        _client = std::make_shared<discordpp::Client>();
    }
    return self;
}

// Log + status + token-expiration callbacks. Set once, before any Connect.
- (void)ensureCallbacks {
    if (_callbacksReady) return;
    _callbacksReady = true;

    auto client = _client;
    __weak DiscordBridge *weakSelf = self;

    client->AddLogCallback([](auto message, auto severity) {
        NSLog(@"[Discord] %s", message.c_str());
    }, discordpp::LoggingSeverity::Info);

    client->SetStatusChangedCallback([client, weakSelf](auto status, auto error, int32_t detail) {
        NSString *s = @(discordpp::Client::StatusToString(status).c_str());
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.onStatus) weakSelf.onStatus(s); });

        if (status == discordpp::Client::Status::Ready) {
            auto count = (NSInteger)client->GetRelationships().size();
            dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.onFriendsCount) weakSelf.onFriendsCount(count); });
        }
    });

    client->SetTokenExpirationCallback([weakSelf]() {
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.onTokenNeedsRefresh) weakSelf.onTokenNeedsRefresh(); });
    });
}

- (void)updateTokenAndConnect:(NSString *)accessToken {
    auto client = _client;
    client->UpdateToken(discordpp::AuthorizationTokenType::Bearer,
                        std::string(accessToken.UTF8String),
                        [client](discordpp::ClientResult r) {
        if (r.Successful()) client->Connect();
    });
}

- (void)connectWithAccessToken:(nullable NSString *)accessToken {
    [self ensureCallbacks];
    if (accessToken.length > 0) {
        [self updateTokenAndConnect:accessToken];
    } else {
        [self authorizeFromScratch];
    }
}

- (void)refreshWithRefreshToken:(NSString *)refreshToken {
    [self ensureCallbacks];
    auto client = _client;
    uint64_t appId = _appId;
    __weak DiscordBridge *weakSelf = self;

    client->RefreshToken(appId, std::string(refreshToken.UTF8String),
        [weakSelf](discordpp::ClientResult result, std::string access, std::string refresh,
                   auto type, int32_t expiresIn, std::string scope) {
            if (!result.Successful()) return;
            NSString *a = @(access.c_str());
            NSString *r = @(refresh.c_str());
            dispatch_async(dispatch_get_main_queue(), ^{
                DiscordBridge *strong = weakSelf;
                if (!strong) return;
                if (strong.onTokens) strong.onTokens(a, r, expiresIn);
                [strong updateTokenAndConnect:a];
            });
        });
}

- (void)authorizeFromScratch {
    auto client = _client;
    uint64_t appId = _appId;
    __weak DiscordBridge *weakSelf = self;

    auto verifier = client->CreateAuthorizationCodeVerifier();
    discordpp::AuthorizationArgs args{};
    args.SetClientId(appId);
    args.SetScopes(discordpp::Client::GetDefaultPresenceScopes());
    args.SetCodeChallenge(verifier.Challenge());

    client->Authorize(args, [client, verifier, appId, weakSelf](auto result, auto code, auto redirectUri) {
        if (!result.Successful()) return;
        client->GetToken(appId, code, verifier.Verifier(), redirectUri,
            [weakSelf](discordpp::ClientResult r, std::string access, std::string refresh,
                       auto type, int32_t expiresIn, std::string scope) {
                if (!r.Successful()) return;
                NSString *a = @(access.c_str());
                NSString *rt = @(refresh.c_str());
                dispatch_async(dispatch_get_main_queue(), ^{
                    DiscordBridge *strong = weakSelf;
                    if (!strong) return;
                    if (strong.onTokens) strong.onTokens(a, rt, expiresIn);
                    [strong updateTokenAndConnect:a];
                });
            });
    });
}

- (void)runCallbacks { discordpp::RunCallbacks(); }

- (void)updatePresenceWithDetails:(NSString *)details state:(NSString *)state {
    auto client = _client;
    discordpp::Activity activity;
    activity.SetType(discordpp::ActivityTypes::Listening);
    // SetDetails/SetState take std::optional — pass nothing for empty strings
    // (Discord rejects state/details shorter than 2 chars).
    if (details.length > 0) activity.SetDetails(std::string(details.UTF8String));
    if (state.length > 0) activity.SetState(std::string(state.UTF8String));
    client->UpdateRichPresence(std::move(activity), [](discordpp::ClientResult){});
}

- (void)clearPresence {
    _client->ClearRichPresence();
}
@end

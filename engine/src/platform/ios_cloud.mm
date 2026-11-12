#include "platform/ios_cloud.hpp"

#import <Foundation/Foundation.h>

#include <SDL3/SDL.h>

#include <atomic>
#include <fstream>
#include <mutex>
#include <sstream>

namespace crios {
namespace {
NSString* gUrl = nil;
NSString* gKey = nil;
std::mutex gLock;
bool gBusy = false, gAgain = false;
std::string gAgainDir;

// the files that make up a player's progress and choices
const char* const kFiles[] = {"save1.txt", "cont.txt", "system.txt", "settings.ini"};
const char* const kMarker = "cloud-checked"; // (the server asked once: a later start doesn't wait for it)

bool readFile(const std::string& path, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::ostringstream s;
    s << f.rdbuf();
    out = s.str();
    return true;
}

NSMutableURLRequest* request(NSString* method) {
    NSURL* url = [NSURL URLWithString:[gUrl stringByAppendingString:@"/api/device-save"]];
    NSMutableURLRequest* r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = method;
    r.timeoutInterval = 90; // (a sleeping free server: up to a minute to wake)
    [r setValue:gKey forHTTPHeaderField:@"X-Save-Key"];
    return r;
}

void upload(const std::string& dir) {
    NSMutableDictionary* files = [NSMutableDictionary dictionary];
    for (const char* name : kFiles) {
        std::string bytes;
        if (!readFile(dir + name, bytes)) continue;
        NSData* d = [NSData dataWithBytes:bytes.data() length:bytes.size()];
        files[[NSString stringWithUTF8String:name]] = [d base64EncodedStringWithOptions:0];
    }
    if (files.count == 0) {
        std::lock_guard<std::mutex> g(gLock);
        gBusy = false;
        return;
    }
    NSDictionary* doc = @{@"savedAt" : @((long long)([[NSDate date] timeIntervalSince1970] * 1000)), @"files" : files};
    NSData* body = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    NSMutableURLRequest* r = request(@"PUT");
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = body;
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                     completionHandler:^(NSData*, NSURLResponse* resp, NSError* err) {
                                         const long status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (long)((NSHTTPURLResponse*)resp).statusCode : 0;
                                         if (err) SDL_Log("cloud: backup failed (%s)", err.localizedDescription.UTF8String);
                                         else SDL_Log("cloud: backup %s (%ld)", status == 200 ? "stored" : "refused", status);
                                         std::string again;
                                         {
                                             std::lock_guard<std::mutex> g(gLock);
                                             if (gAgain) gAgain = false, again = gAgainDir;
                                             else gBusy = false;
                                         }
                                         if (!again.empty()) upload(again);
                                     }] resume];
}
} // namespace

bool cloudConfigure(const std::string& configFile) {
    std::string text;
    if (!readFile(configFile, text)) return false;
    std::istringstream in(text);
    std::string url, key;
    std::getline(in, url), std::getline(in, key);
    auto trim = [](std::string& s) {
        while (!s.empty() && (s.back() == '\r' || s.back() == '\n' || s.back() == ' ' || s.back() == '/')) s.pop_back();
        while (!s.empty() && s.front() == ' ') s.erase(s.begin());
    };
    trim(url), trim(key);
    if (url.rfind("https://", 0) != 0 || key.size() < 32) {
        SDL_Log("cloud: %s needs an https:// address and a key on its second line", configFile.c_str());
        return false;
    }
    gUrl = [NSString stringWithUTF8String:url.c_str()];
    gKey = [NSString stringWithUTF8String:key.c_str()];
    SDL_Log("cloud: backups to %s", url.c_str());
    return true;
}

void cloudBackup(const std::string& profileDir) {
    if (!gUrl) return;
    {
        std::lock_guard<std::mutex> g(gLock);
        if (gBusy) {
            gAgain = true, gAgainDir = profileDir;
            return;
        }
        gBusy = true;
    }
    upload(profileDir);
}

bool cloudRestoreIfEmpty(const std::string& profileDir) {
    if (!gUrl) return false;
    if (SDL_GetPathInfo((profileDir + kMarker).c_str(), nullptr)) return false;
    for (const char* name : kFiles)
        if (SDL_GetPathInfo((profileDir + name).c_str(), nullptr)) return false; // (a save of its own: never replaced)
    SDL_Log("cloud: no save here - asking the server for one");
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData* got = nil;
    __block long status = 0;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request(@"GET")
                                     completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                                         if (!err && [resp isKindOfClass:[NSHTTPURLResponse class]]) status = (long)((NSHTTPURLResponse*)resp).statusCode;
                                         if (status == 200) got = data;
                                         if (err) SDL_Log("cloud: could not reach the server (%s)", err.localizedDescription.UTF8String);
                                         dispatch_semaphore_signal(done);
                                     }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, int64_t(95 * NSEC_PER_SEC)));
    auto mark = [&] {
        SDL_CreateDirectory(profileDir.c_str());
        if (SDL_IOStream* m = SDL_IOFromFile((profileDir + kMarker).c_str(), "wb")) SDL_CloseIO(m);
    };
    if (status == 404) { // (nothing stored yet: asked, not to be asked again)
        SDL_Log("cloud: the server has no save yet");
        mark();
        return false;
    }
    if (status != 200 || !got) {
        SDL_Log("cloud: no answer (%ld) - starting without a backup, asking again next time", status);
        return false;
    }
    NSDictionary* doc = [NSJSONSerialization JSONObjectWithData:got options:0 error:nil];
    NSDictionary* files = [doc isKindOfClass:[NSDictionary class]] ? doc[@"files"] : nil;
    if (![files isKindOfClass:[NSDictionary class]]) return false;
    SDL_CreateDirectory(profileDir.c_str());
    int written = 0;
    for (const char* name : kFiles) {
        NSString* b64 = files[[NSString stringWithUTF8String:name]];
        if (![b64 isKindOfClass:[NSString class]]) continue;
        NSData* d = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
        if (!d) continue;
        const std::string path = profileDir + name;
        if (SDL_IOStream* f = SDL_IOFromFile(path.c_str(), "wb")) {
            const bool ok = SDL_WriteIO(f, d.bytes, d.length) == d.length;
            SDL_CloseIO(f);
            written += ok;
        }
    }
    mark();
    SDL_Log("cloud: %d save files restored from the server", written);
    return written > 0;
}

namespace {
bool copyFile(const std::string& from, const std::string& to) {
    std::string bytes;
    if (!readFile(from, bytes)) return false;
    const std::string part = to + ".part";
    SDL_IOStream* f = SDL_IOFromFile(part.c_str(), "wb");
    if (!f) return false;
    bool ok = SDL_WriteIO(f, bytes.data(), bytes.size()) == bytes.size();
    ok = SDL_CloseIO(f) && ok;
    if (ok) SDL_RemovePath(to.c_str()); // (a rename doesn't replace on every system)
    return ok && SDL_RenamePath(part.c_str(), to.c_str());
}
std::string slash(std::string d) {
    if (!d.empty() && d.back() != '/') d += '/';
    return d;
}
} // namespace

void savesMirror(const std::string& profileDir, const std::string& docsDir) {
    const std::string out = slash(docsDir) + "saves/";
    SDL_CreateDirectory(out.c_str());
    for (const char* name : kFiles)
        if (SDL_GetPathInfo((profileDir + name).c_str(), nullptr)) copyFile(profileDir + name, out + name);
}

int savesImport(const std::string& docsDir, const std::string& profileDir) {
    const std::string in = slash(docsDir) + "import/";
    int taken = 0;
    SDL_CreateDirectory(profileDir.c_str());
    for (const char* name : kFiles) {
        const std::string from = in + name, to = profileDir + name;
        if (!SDL_GetPathInfo(from.c_str(), nullptr)) continue;
        if (SDL_GetPathInfo(to.c_str(), nullptr)) copyFile(to, to + ".bak"); // (the one replaced, kept)
        if (copyFile(from, to)) {
            SDL_RemovePath(from.c_str());
            ++taken;
            SDL_Log("saves: %s imported (the old one kept as %s.bak)", name, name);
        } else {
            SDL_Log("saves: could not import %s", name);
        }
    }
    return taken;
}
} // namespace crios

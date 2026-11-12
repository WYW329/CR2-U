#pragma once
// iPhone / iPad: the saves backed up to a server of one's own (a cloud.txt in the app's Documents
// folder: the server's address on its first line, the key on its second - no file, no backup).
//
// After each save the profile's save files go up in the background, as one JSON document (PUT
// <address>/api/device-save, the key in X-Save-Key); an upload still under way is followed by one
// more with whatever was written meanwhile. On a start with no save of its own and the server not
// asked before (a fresh install), the server's copy is fetched and written into the profile first.
#include <string>

namespace crios {
// cloud.txt read; false when there is none (the rest then do nothing)
bool cloudConfigure(const std::string& configFile);
// the save files from `profileDir`, sent in the background
void cloudBackup(const std::string& profileDir);
// a fresh install's: the server's saves into `profileDir` (blocking, up to a minute and a half -
// a sleeping free server takes most of that to wake); true when some were written
bool cloudRestoreIfEmpty(const std::string& profileDir);
}

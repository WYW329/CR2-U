#pragma once
// iPhone / iPad: the system's fonts as files FreeType can open. The iPad release carries no font
// of its own (it drew with iOS's), and the system's font files sit where an app's sandbox may not
// read them - so the font is asked of CoreText by its PostScript name, its tables copied out and
// written as one sfnt file into `cacheDir` (once; later starts reuse it).
#include <string>

namespace crios {
// The file's path, or "" when CoreText has no such font (it then names another: not taken).
std::string systemFontFile(const char* postScriptName, const std::string& cacheDir);
}

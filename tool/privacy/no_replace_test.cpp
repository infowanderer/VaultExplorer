#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../../android/app/src/main/cpp/organizer/no_replace.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
int main() {
    char pattern[] = "/tmp/organizer-synthetic-XXXXXX";
    const char* made = ::mkdtemp(pattern); assert(made);
    const std::filesystem::path root(made);
    auto write = [](const auto& path, const char* value) { std::ofstream out(path); out << value; };
    auto read = [](const auto& path) { std::ifstream in(path); return std::string(std::istreambuf_iterator<char>(in), {}); };
    const auto source = root / "source.jpg", target = root / "target.jpg";
    write(source, "original"); write(target, "must survive");
    assert(!organizer::renameNoReplace(source.c_str(), target.c_str()));
    assert(read(source) == "original" && read(target) == "must survive");
    const auto retained = root / "retained-\xF0\x9F\x8C\xB4.jpg";
    assert(organizer::renameNoReplace(source.c_str(), retained.c_str()));
    assert(!std::filesystem::exists(source) && read(retained) == "original");
    std::filesystem::create_symlink(target, source);
    assert(!organizer::renameNoReplace(retained.c_str(), source.c_str()));
    assert(read(target) == "must survive" && read(retained) == "original");
    std::filesystem::remove_all(root);
    std::cout << "Atomic no-replace checks passed: collisions, retained bytes, UTF-8 names, symlink targets\n";
}

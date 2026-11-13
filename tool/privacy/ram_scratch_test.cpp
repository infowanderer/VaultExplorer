#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../../android/app/src/main/cpp/privacy/ram_scratch.h"
#include <cassert>
#include <iostream>
#include <memory>
using vault_privacy::RamScratch;
int main() {
    int closedFd;
    {
        RamScratch s; closedFd=s.fd();
        assert(::fcntl(s.fd(),F_GETFD)&FD_CLOEXEC);
        char path[64],target[256];::snprintf(path,sizeof(path),"/proc/self/fd/%d",s.fd());
        const auto n=::readlink(path,target,sizeof(target)-1);assert(n>0);target[n]=0;
        assert(std::string(target).find("memfd:vault-scratch")!=std::string::npos);
        const uint8_t bytes[]={1,2,3,4};assert(s.writeAt(bytes,4,0));
        assert(s.readAt(1,2)==std::vector<uint8_t>({2,3}));
        assert(s.size()==4);assert(!s.writeAt(bytes,4,-1));
        assert(!s.writeAt(bytes,4,RamScratch::fileLimit-1));assert(s.size()==4);
        assert(s.readAt(-1,2).empty());
    }
    assert(::fcntl(closedFd,F_GETFD)==-1 && errno==EBADF);
    {
        std::vector<std::unique_ptr<RamScratch>> files;
        uint8_t byte=7;
        for(int i=0;i<4;++i){files.push_back(std::make_unique<RamScratch>());
            assert(files.back()->writeAt(&byte,1,RamScratch::fileLimit-1));}
        RamScratch extra;assert(!extra.writeAt(&byte,1,0));
        files.pop_back();assert(extra.writeAt(&byte,1,0));
    }
    std::cout<<"RAM scratch checks passed: anonymous fd, CLOEXEC, reads, bounds, total budget, cleanup\n";
}

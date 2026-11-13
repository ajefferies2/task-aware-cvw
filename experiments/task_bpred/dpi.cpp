#include <cstdlib>
extern "C" const char *getenvval(const char *name) {
    const char *value = std::getenv(name);
    return value ? value : "";
}

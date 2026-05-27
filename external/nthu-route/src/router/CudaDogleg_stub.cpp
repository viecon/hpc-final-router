#include "CudaDogleg.h"

namespace NTHUR {

bool cuda_dogleg_available() {
    return false;
}

bool cuda_choose_doglegs(int, int,
        const std::vector<double>&,
        const std::vector<double>&,
        const std::vector<CudaDoglegInput>&,
        int,
        int,
        std::vector<CudaDoglegChoice>&,
        const std::vector<int>*,
        const std::vector<int>*) {
    return false;
}

bool cuda_find_legal_maze_path(int, int,
        const std::vector<int>&,
        const std::vector<int>&,
        int, int,
        int, int,
        int, int,
        std::vector<Coordinate_2d>&) {
    return false;
}

bool cuda_find_costed_maze_path(int, int,
        const std::vector<int>&,
        const std::vector<int>&,
        const std::vector<double>&,
        const std::vector<double>&,
        int, int,
        int, int,
        int, int,
        std::vector<Coordinate_2d>&) {
    return false;
}

} // namespace NTHUR

#ifndef SRC_ROUTER_CUDA_DOGLEG_H_
#define SRC_ROUTER_CUDA_DOGLEG_H_

#include <vector>

#include "misc/geometry.h"

namespace NTHUR {

struct CudaDoglegInput {
    int sx = 0;
    int sy = 0;
    int tx = 0;
    int ty = 0;
};

struct CudaDoglegChoice {
    int kind = 0;
    int mid = 0;
    double cost = 0.0;
    int valid = 0;
};

bool cuda_dogleg_available();

bool cuda_choose_doglegs(int width, int height,
        const std::vector<double>& east_cost,
        const std::vector<double>& south_cost,
        const std::vector<CudaDoglegInput>& inputs,
        int step,
        int radius,
        std::vector<CudaDoglegChoice>& choices,
        const std::vector<int>* east_room = nullptr,
        const std::vector<int>* south_room = nullptr);

bool cuda_find_legal_maze_path(int box_width, int box_height,
        const std::vector<int>& east_open,
        const std::vector<int>& south_open,
        int source_x, int source_y,
        int target_x, int target_y,
        int global_left, int global_bottom,
        std::vector<Coordinate_2d>& path);

bool cuda_find_costed_maze_path(int box_width, int box_height,
        const std::vector<int>& east_open,
        const std::vector<int>& south_open,
        const std::vector<double>& east_cost,
        const std::vector<double>& south_cost,
        int source_x, int source_y,
        int target_x, int target_y,
        int global_left, int global_bottom,
        std::vector<Coordinate_2d>& path);

} // namespace NTHUR

#endif // SRC_ROUTER_CUDA_DOGLEG_H_

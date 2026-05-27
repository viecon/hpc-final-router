#include "CudaDogleg.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <climits>
#include <cstddef>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>

namespace NTHUR {
namespace {

void cuda_check(cudaError_t err, const char* where) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string(where) + ": " + cudaGetErrorString(err));
    }
}

int env_int(const char* name, int default_value) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        return default_value;
    }
    return std::max(0, std::atoi(value));
}

template <typename T>
class DeviceBuffer {
public:
    ~DeviceBuffer() {
        cudaFree(ptr_);
    }

    void ensure(std::size_t count, const char* where) {
        if (count <= capacity_) {
            return;
        }
        cudaFree(ptr_);
        ptr_ = nullptr;
        capacity_ = 0;
        cuda_check(cudaMalloc(&ptr_, count * sizeof(T)), where);
        capacity_ = count;
    }

    T* get() const {
        return ptr_;
    }

private:
    T* ptr_ = nullptr;
    std::size_t capacity_ = 0;
};

__device__ int clamp_int(int value, int low, int high) {
    return max(low, min(high, value));
}

__device__ void add_unique_value(int* values, int& count, int value, int low, int high) {
    value = clamp_int(value, low, high);
    for (int i = 0; i < count; ++i) {
        if (values[i] == value) {
            return;
        }
    }
    values[count++] = value;
}

__device__ double segment_cost_checked(int width,
        const double* east_cost,
        const double* south_cost,
        const int* east_room,
        const int* south_room,
        int& x,
        int& y,
        int tx,
        int ty) {
    double cost = 0.0;
    while (x != tx) {
        const int nx = x + (tx > x ? 1 : -1);
        const int index = y * width + min(x, nx);
        if (east_room != nullptr && east_room[index] == 0) {
            return 1.0e100;
        }
        cost += east_cost[index];
        x = nx;
    }
    while (y != ty) {
        const int ny = y + (ty > y ? 1 : -1);
        const int index = min(y, ny) * width + x;
        if (south_room != nullptr && south_room[index] == 0) {
            return 1.0e100;
        }
        cost += south_cost[index];
        y = ny;
    }
    return cost;
}

__global__ void choose_doglegs_kernel(int width, int height, int n,
        const CudaDoglegInput* inputs,
        const double* east_cost,
        const double* south_cost,
        const int* east_room,
        const int* south_room,
        int step,
        int radius,
        CudaDoglegChoice* choices) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) {
        return;
    }

    const CudaDoglegInput in = inputs[i];
    double best = 1.0e100;
    int best_kind = 0;
    int best_mid = 0;

    auto consider = [&](int kind, int mid, double cost) {
        if (cost < best) {
            best = cost;
            best_kind = kind;
            best_mid = mid;
        }
    };

    int x = in.sx;
    int y = in.sy;
    consider(0, 0,
            segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, in.sy) +
            segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, in.ty));

    x = in.sx;
    y = in.sy;
    consider(1, 0,
            segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.sx, in.ty) +
            segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, in.ty));

    const int mid_x = (in.sx + in.tx) / 2;
    const int mid_y = (in.sy + in.ty) / 2;
    constexpr int kMaxRadius = 8;
    radius = clamp_int(radius, 0, kMaxRadius);
    int x_values[3 * (2 * kMaxRadius + 1)];
    int y_values[3 * (2 * kMaxRadius + 1)];
    int x_count = 0;
    int y_count = 0;
    for (int abs_r = 0; abs_r <= radius; ++abs_r) {
        for (int sign_index = 0; sign_index < 2; ++sign_index) {
            if (abs_r == 0 && sign_index == 1) {
                continue;
            }
            const int sign = sign_index == 0 ? 1 : -1;
            const int delta = sign * abs_r * step;
            add_unique_value(x_values, x_count, in.sx + delta, 0, width - 1);
            add_unique_value(x_values, x_count, in.tx + delta, 0, width - 1);
            add_unique_value(x_values, x_count, mid_x + delta, 0, width - 1);
            add_unique_value(y_values, y_count, in.sy + delta, 0, height - 1);
            add_unique_value(y_values, y_count, in.ty + delta, 0, height - 1);
            add_unique_value(y_values, y_count, mid_y + delta, 0, height - 1);
        }
    }

    for (int k = 0; k < y_count; ++k) {
        x = in.sx;
        y = in.sy;
        const int mid = y_values[k];
        double cost = segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.sx, mid);
        cost += segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, mid);
        cost += segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, in.ty);
        consider(2, mid, cost);
    }
    for (int k = 0; k < x_count; ++k) {
        x = in.sx;
        y = in.sy;
        const int mid = x_values[k];
        double cost = segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, mid, in.sy);
        cost += segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, mid, in.ty);
        cost += segment_cost_checked(width, east_cost, south_cost, east_room, south_room, x, y, in.tx, in.ty);
        consider(3, mid, cost);
    }

    choices[i].kind = best_kind;
    choices[i].mid = best_mid;
    choices[i].cost = best;
    choices[i].valid = best < 1.0e90 ? 1 : 0;
}

constexpr int kMazeInf = 1000000000;
constexpr double kCostInf = 1.0e100;
constexpr float kCostInfF = 1.0e30f;

__global__ void legal_maze_relax_kernel(int width, int height,
        const int* east_open,
        const int* south_open,
        int* dist,
        int* changed) {
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    const int area = width * height;
    if (index >= area) {
        return;
    }
    const int current = dist[index];
    if (current >= kMazeInf) {
        return;
    }
    const int x = index % width;
    const int y = index / width;
    const int next = current + 1;

    auto relax = [&](int neighbor_index) {
        const int old = atomicMin(&dist[neighbor_index], next);
        if (next < old) {
            *changed = 1;
        }
    };

    if (x + 1 < width && east_open[index]) {
        relax(index + 1);
    }
    if (x > 0 && east_open[index - 1]) {
        relax(index - 1);
    }
    if (y + 1 < height && south_open[index]) {
        relax(index + width);
    }
    if (y > 0 && south_open[index - width]) {
        relax(index - width);
    }
}

__global__ void legal_maze_single_block_kernel(int width, int height,
        const int* east_open,
        const int* south_open,
        int source_index,
        int target_index,
        int* out_dist) {
    extern __shared__ int dist[];
    __shared__ int changed;
    const int area = width * height;
    const int tid = threadIdx.x;

    for (int index = tid; index < area; index += blockDim.x) {
        dist[index] = kMazeInf;
    }
    if (tid == 0) {
        dist[source_index] = 0;
    }
    __syncthreads();

    for (int level = 0; level < area; ++level) {
        if (tid == 0) {
            changed = 0;
        }
        __syncthreads();

        for (int index = tid; index < area; index += blockDim.x) {
            if (dist[index] != level) {
                continue;
            }
            const int x = index % width;
            const int y = index / width;
            const int next = level + 1;

            auto relax = [&](int neighbor_index) {
                if (atomicCAS(&dist[neighbor_index], kMazeInf, next) == kMazeInf) {
                    changed = 1;
                }
            };

            if (x + 1 < width && east_open[index]) {
                relax(index + 1);
            }
            if (x > 0 && east_open[index - 1]) {
                relax(index - 1);
            }
            if (y + 1 < height && south_open[index]) {
                relax(index + width);
            }
            if (y > 0 && south_open[index - width]) {
                relax(index - width);
            }
        }
        __syncthreads();

        if (dist[target_index] < kMazeInf || changed == 0) {
            break;
        }
    }

    for (int index = tid; index < area; index += blockDim.x) {
        out_dist[index] = dist[index];
    }
}

__global__ void costed_maze_relax_kernel(int width, int height,
        const int* east_open,
        const int* south_open,
        const float* east_cost,
        const float* south_cost,
        const float* prev_dist,
        const int* prev_parent,
        float* next_dist,
        int* next_parent,
        int* changed) {
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    const int area = width * height;
    if (index >= area) {
        return;
    }

    const int x = index % width;
    const int y = index / width;
    float best = prev_dist[index];
    int parent = prev_parent[index];

    auto consider = [&](int neighbor_index, float edge_cost) {
        const float candidate = prev_dist[neighbor_index] + edge_cost;
        if (candidate + 1.0e-4f < best) {
            best = candidate;
            parent = neighbor_index;
        }
    };

    if (x > 0 && east_open[index - 1]) {
        consider(index - 1, east_cost[index - 1]);
    }
    if (x + 1 < width && east_open[index]) {
        consider(index + 1, east_cost[index]);
    }
    if (y > 0 && south_open[index - width]) {
        consider(index - width, south_cost[index - width]);
    }
    if (y + 1 < height && south_open[index]) {
        consider(index + width, south_cost[index]);
    }

    next_dist[index] = best;
    next_parent[index] = parent;
    if (best + 1.0e-4f < prev_dist[index]) {
        *changed = 1;
    }
}

__global__ void costed_maze_single_block_kernel(int width, int height,
        const int* east_open,
        const int* south_open,
        const float* east_cost,
        const float* south_cost,
        int source_index,
        float* out_dist,
        int* out_parent) {
    extern __shared__ float shared_float[];
    const int area = width * height;
    const int tid = threadIdx.x;
    float* dist_a = shared_float;
    float* dist_b = dist_a + area;
    int* parent_a = reinterpret_cast<int*>(dist_b + area);
    int* parent_b = parent_a + area;
    __shared__ int changed;

    for (int index = tid; index < area; index += blockDim.x) {
        dist_a[index] = kCostInfF;
        dist_b[index] = kCostInfF;
        parent_a[index] = -1;
        parent_b[index] = -1;
    }
    if (tid == 0) {
        dist_a[source_index] = 0.0f;
        parent_a[source_index] = source_index;
    }
    __syncthreads();

    for (int iter = 0; iter < area; ++iter) {
        if (tid == 0) {
            changed = 0;
        }
        __syncthreads();

        for (int index = tid; index < area; index += blockDim.x) {
            const int x = index % width;
            const int y = index / width;
            float best = dist_a[index];
            int parent = parent_a[index];

            auto consider = [&](int neighbor_index, float edge_cost) {
                const float candidate = dist_a[neighbor_index] + edge_cost;
                if (candidate + 1.0e-4f < best) {
                    best = candidate;
                    parent = neighbor_index;
                }
            };

            if (x > 0 && east_open[index - 1]) {
                consider(index - 1, east_cost[index - 1]);
            }
            if (x + 1 < width && east_open[index]) {
                consider(index + 1, east_cost[index]);
            }
            if (y > 0 && south_open[index - width]) {
                consider(index - width, south_cost[index - width]);
            }
            if (y + 1 < height && south_open[index]) {
                consider(index + width, south_cost[index]);
            }

            dist_b[index] = best;
            parent_b[index] = parent;
            if (best + 1.0e-4f < dist_a[index]) {
                changed = 1;
            }
        }
        __syncthreads();

        for (int index = tid; index < area; index += blockDim.x) {
            dist_a[index] = dist_b[index];
            parent_a[index] = parent_b[index];
        }
        __syncthreads();

        if (changed == 0) {
            break;
        }
    }

    for (int index = tid; index < area; index += blockDim.x) {
        out_dist[index] = dist_a[index];
        out_parent[index] = parent_a[index];
    }
}

} // namespace

bool cuda_dogleg_available() {
    static int cached_available = -1;
    if (cached_available < 0) {
        int count = 0;
        cached_available = (cudaGetDeviceCount(&count) == cudaSuccess && count > 0) ? 1 : 0;
    }
    return cached_available != 0;
}

bool cuda_choose_doglegs(int width, int height,
        const std::vector<double>& east_cost,
        const std::vector<double>& south_cost,
        const std::vector<CudaDoglegInput>& inputs,
        int step,
        int radius,
        std::vector<CudaDoglegChoice>& choices,
        const std::vector<int>* east_room,
        const std::vector<int>* south_room) {
    const int n = static_cast<int>(inputs.size());
    choices.assign(inputs.size(), CudaDoglegChoice {});
    if (n == 0) {
        return true;
    }
    if (width <= 0 || height <= 0 ||
            east_cost.size() < static_cast<std::size_t>(width * height) ||
            south_cost.size() < static_cast<std::size_t>(width * height)) {
        return false;
    }
    if ((east_room == nullptr) != (south_room == nullptr)) {
        return false;
    }
    if (east_room != nullptr &&
            (east_room->size() < east_cost.size() || south_room->size() < south_cost.size())) {
        return false;
    }

    static DeviceBuffer<CudaDoglegInput> d_inputs_buffer;
    static DeviceBuffer<double> d_east_cost_buffer;
    static DeviceBuffer<double> d_south_cost_buffer;
    static DeviceBuffer<int> d_east_room_buffer;
    static DeviceBuffer<int> d_south_room_buffer;
    static DeviceBuffer<CudaDoglegChoice> d_choices_buffer;

    d_inputs_buffer.ensure(inputs.size(), "cudaMalloc inputs");
    d_east_cost_buffer.ensure(east_cost.size(), "cudaMalloc east_cost");
    d_south_cost_buffer.ensure(south_cost.size(), "cudaMalloc south_cost");
    if (east_room != nullptr && south_room != nullptr) {
        d_east_room_buffer.ensure(east_cost.size(), "cudaMalloc east_room");
        d_south_room_buffer.ensure(south_cost.size(), "cudaMalloc south_room");
    }
    d_choices_buffer.ensure(choices.size(), "cudaMalloc choices");

    CudaDoglegInput* d_inputs = d_inputs_buffer.get();
    double* d_east_cost = d_east_cost_buffer.get();
    double* d_south_cost = d_south_cost_buffer.get();
    int* d_east_room = east_room != nullptr ? d_east_room_buffer.get() : nullptr;
    int* d_south_room = south_room != nullptr ? d_south_room_buffer.get() : nullptr;
    CudaDoglegChoice* d_choices = d_choices_buffer.get();

    cuda_check(cudaMemcpy(d_inputs, inputs.data(), inputs.size() * sizeof(CudaDoglegInput),
                cudaMemcpyHostToDevice), "copy inputs");
    cuda_check(cudaMemcpy(d_east_cost, east_cost.data(), east_cost.size() * sizeof(double),
                cudaMemcpyHostToDevice), "copy east_cost");
    cuda_check(cudaMemcpy(d_south_cost, south_cost.data(), south_cost.size() * sizeof(double),
                cudaMemcpyHostToDevice), "copy south_cost");
    if (d_east_room != nullptr && d_south_room != nullptr) {
        cuda_check(cudaMemcpy(d_east_room, east_room->data(), east_cost.size() * sizeof(int),
                    cudaMemcpyHostToDevice), "copy east_room");
        cuda_check(cudaMemcpy(d_south_room, south_room->data(), south_cost.size() * sizeof(int),
                    cudaMemcpyHostToDevice), "copy south_room");
    }

    const int block = 256;
    const int blocks = (n + block - 1) / block;
    choose_doglegs_kernel<<<blocks, block>>>(width, height, n, d_inputs, d_east_cost,
            d_south_cost, d_east_room, d_south_room, std::max(1, step),
            std::max(0, std::min(8, radius)), d_choices);
    cuda_check(cudaGetLastError(), "choose_doglegs_kernel");
    cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
    cuda_check(cudaMemcpy(choices.data(), d_choices, choices.size() * sizeof(CudaDoglegChoice),
                cudaMemcpyDeviceToHost), "copy choices");

    return true;
}

bool cuda_find_legal_maze_path(int box_width, int box_height,
        const std::vector<int>& east_open,
        const std::vector<int>& south_open,
        int source_x, int source_y,
        int target_x, int target_y,
        int global_left, int global_bottom,
        std::vector<Coordinate_2d>& path) {
    path.clear();
    if (box_width <= 0 || box_height <= 0 ||
            source_x < 0 || source_x >= box_width ||
            target_x < 0 || target_x >= box_width ||
            source_y < 0 || source_y >= box_height ||
            target_y < 0 || target_y >= box_height) {
        return false;
    }
    const std::size_t area = static_cast<std::size_t>(box_width) * box_height;
    if (east_open.size() < area || south_open.size() < area) {
        return false;
    }

    static DeviceBuffer<int> d_east_open_buffer;
    static DeviceBuffer<int> d_south_open_buffer;
    static DeviceBuffer<int> d_dist_buffer;
    static DeviceBuffer<int> d_changed_buffer;

    std::vector<int> dist(area, kMazeInf);
    const int source_index = source_y * box_width + source_x;
    const int target_index = target_y * box_width + target_x;
    dist[source_index] = 0;

    d_east_open_buffer.ensure(area, "cudaMalloc maze east_open");
    d_south_open_buffer.ensure(area, "cudaMalloc maze south_open");
    d_dist_buffer.ensure(area, "cudaMalloc maze dist");
    d_changed_buffer.ensure(1, "cudaMalloc maze changed");

    int* d_east_open = d_east_open_buffer.get();
    int* d_south_open = d_south_open_buffer.get();
    int* d_dist = d_dist_buffer.get();
    int* d_changed = d_changed_buffer.get();

    cuda_check(cudaMemcpy(d_east_open, east_open.data(), area * sizeof(int),
                cudaMemcpyHostToDevice), "copy maze east_open");
    cuda_check(cudaMemcpy(d_south_open, south_open.data(), area * sizeof(int),
                cudaMemcpyHostToDevice), "copy maze south_open");

    constexpr std::size_t kSingleBlockMaxArea = 4096;
    const int block = 256;
    if (area <= kSingleBlockMaxArea) {
        legal_maze_single_block_kernel<<<1, block, area * sizeof(int)>>>(box_width, box_height,
                d_east_open, d_south_open, source_index, target_index, d_dist);
        cuda_check(cudaGetLastError(), "legal_maze_single_block_kernel");
        cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize single-block maze");
    } else {
        cuda_check(cudaMemcpy(d_dist, dist.data(), area * sizeof(int),
                    cudaMemcpyHostToDevice), "copy maze dist");

        const int blocks = (static_cast<int>(area) + block - 1) / block;
        int changed = 1;
        const int max_iterations = box_width * box_height;
        for (int iter = 0; iter < max_iterations && changed; ++iter) {
            changed = 0;
            cuda_check(cudaMemcpy(d_changed, &changed, sizeof(int), cudaMemcpyHostToDevice),
                    "reset maze changed");
            legal_maze_relax_kernel<<<blocks, block>>>(box_width, box_height,
                    d_east_open, d_south_open, d_dist, d_changed);
            cuda_check(cudaGetLastError(), "legal_maze_relax_kernel");
            cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize maze");
            cuda_check(cudaMemcpy(&changed, d_changed, sizeof(int), cudaMemcpyDeviceToHost),
                    "copy maze changed");
        }
    }

    cuda_check(cudaMemcpy(dist.data(), d_dist, area * sizeof(int), cudaMemcpyDeviceToHost),
            "copy maze dist");
    if (dist[target_index] >= kMazeInf) {
        return false;
    }

    std::vector<Coordinate_2d> reversed;
    int x = target_x;
    int y = target_y;
    reversed.push_back(Coordinate_2d { global_left + x, global_bottom + y });
    while (x != source_x || y != source_y) {
        const int index = y * box_width + x;
        const int current = dist[index];
        bool moved = false;

        if (x > 0 && east_open[index - 1] && dist[index - 1] == current - 1) {
            --x;
            moved = true;
        } else if (x + 1 < box_width && east_open[index] && dist[index + 1] == current - 1) {
            ++x;
            moved = true;
        } else if (y > 0 && south_open[index - box_width] && dist[index - box_width] == current - 1) {
            --y;
            moved = true;
        } else if (y + 1 < box_height && south_open[index] && dist[index + box_width] == current - 1) {
            ++y;
            moved = true;
        }

        if (!moved) {
            path.clear();
            return false;
        }
        reversed.push_back(Coordinate_2d { global_left + x, global_bottom + y });
    }

    path.assign(reversed.rbegin(), reversed.rend());
    return path.size() >= 2;
}

bool cuda_find_costed_maze_path(int box_width, int box_height,
        const std::vector<int>& east_open,
        const std::vector<int>& south_open,
        const std::vector<double>& east_cost,
        const std::vector<double>& south_cost,
        int source_x, int source_y,
        int target_x, int target_y,
        int global_left, int global_bottom,
        std::vector<Coordinate_2d>& path) {
    path.clear();
    if (box_width <= 0 || box_height <= 0 ||
            source_x < 0 || source_x >= box_width ||
            target_x < 0 || target_x >= box_width ||
            source_y < 0 || source_y >= box_height ||
            target_y < 0 || target_y >= box_height) {
        return false;
    }
    const std::size_t area = static_cast<std::size_t>(box_width) * box_height;
    if (east_open.size() < area || south_open.size() < area ||
            east_cost.size() < area || south_cost.size() < area) {
        return false;
    }

    static DeviceBuffer<int> d_east_open_buffer;
    static DeviceBuffer<int> d_south_open_buffer;
    static DeviceBuffer<float> d_east_cost_buffer;
    static DeviceBuffer<float> d_south_cost_buffer;
    static DeviceBuffer<float> d_dist_a_buffer;
    static DeviceBuffer<float> d_dist_b_buffer;
    static DeviceBuffer<int> d_parent_a_buffer;
    static DeviceBuffer<int> d_parent_b_buffer;
    static DeviceBuffer<int> d_changed_buffer;

    std::vector<float> east_cost_f(area, kCostInfF);
    std::vector<float> south_cost_f(area, kCostInfF);
    for (std::size_t i = 0; i < area; ++i) {
        east_cost_f[i] = static_cast<float>(std::min(east_cost[i], static_cast<double>(kCostInfF)));
        south_cost_f[i] = static_cast<float>(std::min(south_cost[i], static_cast<double>(kCostInfF)));
    }
    std::vector<float> dist(area, kCostInfF);
    std::vector<int> parent(area, -1);
    const int source_index = source_y * box_width + source_x;
    const int target_index = target_y * box_width + target_x;
    dist[source_index] = 0.0;
    parent[source_index] = source_index;

    d_east_open_buffer.ensure(area, "cudaMalloc costed maze east_open");
    d_south_open_buffer.ensure(area, "cudaMalloc costed maze south_open");
    d_east_cost_buffer.ensure(area, "cudaMalloc costed maze east_cost");
    d_south_cost_buffer.ensure(area, "cudaMalloc costed maze south_cost");
    d_dist_a_buffer.ensure(area, "cudaMalloc costed maze dist_a");
    d_dist_b_buffer.ensure(area, "cudaMalloc costed maze dist_b");
    d_parent_a_buffer.ensure(area, "cudaMalloc costed maze parent_a");
    d_parent_b_buffer.ensure(area, "cudaMalloc costed maze parent_b");
    d_changed_buffer.ensure(1, "cudaMalloc costed maze changed");

    cuda_check(cudaMemcpy(d_east_open_buffer.get(), east_open.data(), area * sizeof(int),
                cudaMemcpyHostToDevice), "copy costed maze east_open");
    cuda_check(cudaMemcpy(d_south_open_buffer.get(), south_open.data(), area * sizeof(int),
                cudaMemcpyHostToDevice), "copy costed maze south_open");
    cuda_check(cudaMemcpy(d_east_cost_buffer.get(), east_cost_f.data(), area * sizeof(float),
                cudaMemcpyHostToDevice), "copy costed maze east_cost");
    cuda_check(cudaMemcpy(d_south_cost_buffer.get(), south_cost_f.data(), area * sizeof(float),
                cudaMemcpyHostToDevice), "copy costed maze south_cost");
    cuda_check(cudaMemcpy(d_dist_a_buffer.get(), dist.data(), area * sizeof(float),
                cudaMemcpyHostToDevice), "copy costed maze dist");
    cuda_check(cudaMemcpy(d_parent_a_buffer.get(), parent.data(), area * sizeof(int),
                cudaMemcpyHostToDevice), "copy costed maze parent");

    const int block = 256;
    const std::size_t single_block_max_area = static_cast<std::size_t>(
            env_int("NTHU_CUDA_COSTED_SINGLE_BLOCK_MAX_AREA", 0));
    float* d_result_dist = d_dist_a_buffer.get();
    int* d_result_parent = d_parent_a_buffer.get();
    if (area <= single_block_max_area) {
        const std::size_t shared_bytes = 2 * area * sizeof(float) + 2 * area * sizeof(int);
        costed_maze_single_block_kernel<<<1, block, shared_bytes>>>(box_width, box_height,
                d_east_open_buffer.get(), d_south_open_buffer.get(),
                d_east_cost_buffer.get(), d_south_cost_buffer.get(),
                source_index, d_result_dist, d_result_parent);
        cuda_check(cudaGetLastError(), "costed_maze_single_block_kernel");
        cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize single-block costed maze");
    } else {
        float* d_prev_dist = d_dist_a_buffer.get();
        float* d_next_dist = d_dist_b_buffer.get();
        int* d_prev_parent = d_parent_a_buffer.get();
        int* d_next_parent = d_parent_b_buffer.get();
        const int blocks = (static_cast<int>(area) + block - 1) / block;
        const int max_iterations = box_width * box_height;
        int changed = 1;
        for (int iter = 0; iter < max_iterations && changed; ++iter) {
            changed = 0;
            cuda_check(cudaMemcpy(d_changed_buffer.get(), &changed, sizeof(int), cudaMemcpyHostToDevice),
                    "reset costed maze changed");
            costed_maze_relax_kernel<<<blocks, block>>>(box_width, box_height,
                    d_east_open_buffer.get(), d_south_open_buffer.get(),
                    d_east_cost_buffer.get(), d_south_cost_buffer.get(),
                    d_prev_dist, d_prev_parent, d_next_dist, d_next_parent,
                    d_changed_buffer.get());
            cuda_check(cudaGetLastError(), "costed_maze_relax_kernel");
            cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize costed maze");
            cuda_check(cudaMemcpy(&changed, d_changed_buffer.get(), sizeof(int), cudaMemcpyDeviceToHost),
                    "copy costed maze changed");
            std::swap(d_prev_dist, d_next_dist);
            std::swap(d_prev_parent, d_next_parent);
        }
        d_result_dist = d_prev_dist;
        d_result_parent = d_prev_parent;
    }

    cuda_check(cudaMemcpy(dist.data(), d_result_dist, area * sizeof(float), cudaMemcpyDeviceToHost),
            "copy costed maze dist");
    cuda_check(cudaMemcpy(parent.data(), d_result_parent, area * sizeof(int), cudaMemcpyDeviceToHost),
            "copy costed maze parent");
    if (dist[target_index] >= kCostInfF * 0.5f || parent[target_index] < 0) {
        return false;
    }

    std::vector<Coordinate_2d> reversed;
    int index = target_index;
    for (std::size_t guard = 0; guard < area; ++guard) {
        const int x = index % box_width;
        const int y = index / box_width;
        reversed.push_back(Coordinate_2d { global_left + x, global_bottom + y });
        if (index == source_index) {
            path.assign(reversed.rbegin(), reversed.rend());
            return path.size() >= 2;
        }
        const int next = parent[index];
        if (next < 0 || next == index) {
            break;
        }
        index = next;
    }

    path.clear();
    return false;
}

} // namespace NTHUR

#include "router.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cuda_runtime.h>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace router {
namespace {

struct DeviceNets {
  int *sx = nullptr;
  int *sy = nullptr;
  int *tx = nullptr;
  int *ty = nullptr;
};

struct Demand {
  std::vector<int> h;
  std::vector<int> v;
};

int h_edges(const Grid &grid) { return grid.height * std::max(0, grid.width - 1); }
int v_edges(const Grid &grid) { return std::max(0, grid.height - 1) * grid.width; }
int h_index(const Grid &grid, int x0, int x1, int y) {
  return y * (grid.width - 1) + std::min(x0, x1);
}
int v_index(const Grid &grid, int x, int y0, int y1) {
  return std::min(y0, y1) * grid.width + x;
}
Edge edge_between(const Grid &grid, Point a, Point b) {
  if (a.y == b.y && std::abs(a.x - b.x) == 1) {
    return Edge{0, h_index(grid, a.x, b.x, a.y)};
  }
  return Edge{1, v_index(grid, a.x, a.y, b.y)};
}
void cuda_check(cudaError_t err, const char *where) {
  if (err != cudaSuccess) {
    throw std::runtime_error(std::string(where) + ": " + cudaGetErrorString(err));
  }
}

__device__ int dev_h_index(int width, int x0, int x1, int y) {
  return y * (width - 1) + min(x0, x1);
}

__device__ int dev_v_index(int width, int x, int y0, int y1) {
  return min(y0, y1) * width + x;
}

__device__ double h_cost(int width, const int *h_capacity, int x0, int x1, int y) {
  const int cap = h_capacity[dev_h_index(width, x0, x1, y)];
  return cap <= 0 ? 1.0e6 : 1.0 / static_cast<double>(cap);
}

__device__ double v_cost(int width, const int *v_capacity, int x, int y0, int y1) {
  const int cap = v_capacity[dev_v_index(width, x, y0, y1)];
  return cap <= 0 ? 1.0e6 : 1.0 / static_cast<double>(cap);
}

__device__ double segment_cost(int width, const int *h_capacity, const int *v_capacity,
                              int &x, int &y, int tx, int ty) {
  double cost = 0.0;
  while (x != tx) {
    const int nx = x + (tx > x ? 1 : -1);
    cost += h_cost(width, h_capacity, x, nx, y);
    x = nx;
  }
  while (y != ty) {
    const int ny = y + (ty > y ? 1 : -1);
    cost += v_cost(width, v_capacity, x, y, ny);
    y = ny;
  }
  return cost;
}

__device__ int clamp_int(int value, int low, int high) {
  return max(low, min(high, value));
}

__device__ void add_unique_value(int *values, int &count, int value, int low, int high) {
  value = clamp_int(value, low, high);
  for (int i = 0; i < count; ++i) {
    if (values[i] == value) {
      return;
    }
  }
  values[count++] = value;
}

__global__ void choose_manhattan_candidates(int width, int n,
                                            const int *sx, const int *sy,
                                            const int *tx, const int *ty,
                                            const int *h_capacity,
                                            const int *v_capacity,
                                            uint8_t *choice, double *costs) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) {
    return;
  }
  double hv = 0.0;
  int x = sx[i];
  int y = sy[i];
  while (x != tx[i]) {
    const int nx = x + (tx[i] > x ? 1 : -1);
    hv += h_cost(width, h_capacity, x, nx, y);
    x = nx;
  }
  while (y != ty[i]) {
    const int ny = y + (ty[i] > y ? 1 : -1);
    hv += v_cost(width, v_capacity, x, y, ny);
    y = ny;
  }

  double vh = 0.0;
  x = sx[i];
  y = sy[i];
  while (y != ty[i]) {
    const int ny = y + (ty[i] > y ? 1 : -1);
    vh += v_cost(width, v_capacity, x, y, ny);
    y = ny;
  }
  while (x != tx[i]) {
    const int nx = x + (tx[i] > x ? 1 : -1);
    vh += h_cost(width, h_capacity, x, nx, y);
    x = nx;
  }

  choice[i] = hv <= vh ? 0 : 1;
  costs[i] = hv <= vh ? hv : vh;
}

__global__ void choose_dogleg_candidates(int width, int height, int n,
                                         const int *sx, const int *sy,
                                         const int *tx, const int *ty,
                                         const int *h_capacity,
                                         const int *v_capacity,
                                         uint8_t *choice_kind, int *choice_mid,
                                         double *costs) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n) {
    return;
  }

  double best = 1.0e30;
  uint8_t best_kind = 0;
  int best_mid = 0;

  auto consider = [&](uint8_t kind, int mid, double cost) {
    if (cost < best) {
      best = cost;
      best_kind = kind;
      best_mid = mid;
    }
  };

  int x = sx[i];
  int y = sy[i];
  consider(0, 0, segment_cost(width, h_capacity, v_capacity, x, y, tx[i], sy[i]) +
                    segment_cost(width, h_capacity, v_capacity, x, y, tx[i], ty[i]));

  x = sx[i];
  y = sy[i];
  consider(1, 0, segment_cost(width, h_capacity, v_capacity, x, y, sx[i], ty[i]) +
                    segment_cost(width, h_capacity, v_capacity, x, y, tx[i], ty[i]));

  const int step = 8;
  const int mid_x = (sx[i] + tx[i]) / 2;
  const int mid_y = (sy[i] + ty[i]) / 2;
  const int deltas[5] = {0, step, -step, 2 * step, -2 * step};
  int x_values[15];
  int y_values[15];
  int x_count = 0;
  int y_count = 0;
  for (int d = 0; d < 5; ++d) {
    add_unique_value(x_values, x_count, sx[i] + deltas[d], 0, width - 1);
    add_unique_value(x_values, x_count, tx[i] + deltas[d], 0, width - 1);
    add_unique_value(x_values, x_count, mid_x + deltas[d], 0, width - 1);
    add_unique_value(y_values, y_count, sy[i] + deltas[d], 0, height - 1);
    add_unique_value(y_values, y_count, ty[i] + deltas[d], 0, height - 1);
    add_unique_value(y_values, y_count, mid_y + deltas[d], 0, height - 1);
  }
  for (int k = 0; k < y_count; ++k) {
    x = sx[i];
    y = sy[i];
    const int mid = y_values[k];
    double cost = segment_cost(width, h_capacity, v_capacity, x, y, sx[i], mid);
    cost += segment_cost(width, h_capacity, v_capacity, x, y, tx[i], mid);
    cost += segment_cost(width, h_capacity, v_capacity, x, y, tx[i], ty[i]);
    consider(2, mid, cost);
  }
  for (int k = 0; k < x_count; ++k) {
    x = sx[i];
    y = sy[i];
    const int xmid = x_values[k];
    double cost = segment_cost(width, h_capacity, v_capacity, x, y, xmid, sy[i]);
    cost += segment_cost(width, h_capacity, v_capacity, x, y, xmid, ty[i]);
    cost += segment_cost(width, h_capacity, v_capacity, x, y, tx[i], ty[i]);
    consider(3, xmid, cost);
  }

  choice_kind[i] = best_kind;
  choice_mid[i] = best_mid;
  costs[i] = best;
}

Path build_candidate_path(const Grid &grid, const Net &net, uint8_t choice, double cost) {
  Path path;
  path.routed = true;
  path.cost = cost;
  Point cur = net.source;
  path.points.push_back(cur);
  const auto move_x = [&] {
    while (cur.x != net.target.x) {
      Point next{cur.x + (net.target.x > cur.x ? 1 : -1), cur.y};
      path.edges.push_back(edge_between(grid, cur, next));
      path.points.push_back(next);
      cur = next;
    }
  };
  const auto move_y = [&] {
    while (cur.y != net.target.y) {
      Point next{cur.x, cur.y + (net.target.y > cur.y ? 1 : -1)};
      path.edges.push_back(edge_between(grid, cur, next));
      path.points.push_back(next);
      cur = next;
    }
  };
  if (choice == 0) {
    move_x();
    move_y();
  } else {
    move_y();
    move_x();
  }
  return path;
}

void append_segment(const Grid &grid, Path &path, Point &cur, Point target) {
  while (cur.x != target.x) {
    Point next{cur.x + (target.x > cur.x ? 1 : -1), cur.y};
    path.edges.push_back(edge_between(grid, cur, next));
    path.points.push_back(next);
    cur = next;
  }
  while (cur.y != target.y) {
    Point next{cur.x, cur.y + (target.y > cur.y ? 1 : -1)};
    path.edges.push_back(edge_between(grid, cur, next));
    path.points.push_back(next);
    cur = next;
  }
}

Path build_dogleg_path(const Grid &grid, const Net &net, uint8_t kind, int mid, double cost) {
  if (kind < 2) {
    return build_candidate_path(grid, net, kind, cost);
  }
  Path path;
  path.routed = true;
  path.cost = cost;
  Point cur = net.source;
  path.points.push_back(cur);
  if (kind == 2) {
    append_segment(grid, path, cur, Point{net.source.x, mid});
    append_segment(grid, path, cur, Point{net.target.x, mid});
  } else {
    append_segment(grid, path, cur, Point{mid, net.source.y});
    append_segment(grid, path, cur, Point{mid, net.target.y});
  }
  append_segment(grid, path, cur, net.target);
  return path;
}

void add_path(Demand &demand, const Path &path) {
  for (const auto &edge : path.edges) {
    if (edge.dir == 0) {
      ++demand.h[edge.index];
    } else {
      ++demand.v[edge.index];
    }
  }
}

Metrics collect(const Benchmark &benchmark, const RouterConfig &config,
                const std::vector<Path> &paths, const Demand &demand,
                double milliseconds) {
  Metrics m;
  m.mode = "cuda_candidate";
  m.grid_width = benchmark.grid.width;
  m.grid_height = benchmark.grid.height;
  m.nets = static_cast<int>(benchmark.nets.size());
  m.threads = config.threads;
  m.iterations = 1;
  m.milliseconds = milliseconds;
  for (const auto &path : paths) {
    if (path.routed) {
      ++m.routed_nets;
      m.wirelength += static_cast<long long>(path.edges.size());
    } else {
      ++m.failed_nets;
    }
  }
  for (size_t i = 0; i < demand.h.size(); ++i) {
    const long long of = std::max(0, demand.h[i] - benchmark.grid.h_capacity[i]);
    m.overflow += of;
    m.max_overflow = std::max(m.max_overflow, of);
  }
  for (size_t i = 0; i < demand.v.size(); ++i) {
    const long long of = std::max(0, demand.v[i] - benchmark.grid.v_capacity[i]);
    m.overflow += of;
    m.max_overflow = std::max(m.max_overflow, of);
  }
  return m;
}

} // namespace

Metrics route_cuda_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  const int n = static_cast<int>(benchmark.nets.size());

  std::vector<int> sx(n), sy(n), tx(n), ty(n);
  for (int i = 0; i < n; ++i) {
    sx[i] = benchmark.nets[i].source.x;
    sy[i] = benchmark.nets[i].source.y;
    tx[i] = benchmark.nets[i].target.x;
    ty[i] = benchmark.nets[i].target.y;
  }

  DeviceNets nets;
  int *d_hcap = nullptr;
  int *d_vcap = nullptr;
  uint8_t *d_choice = nullptr;
  double *d_costs = nullptr;
  std::vector<uint8_t> choice(n);
  std::vector<double> costs(n);

  cuda_check(cudaMalloc(&nets.sx, n * sizeof(int)), "cudaMalloc sx");
  cuda_check(cudaMalloc(&nets.sy, n * sizeof(int)), "cudaMalloc sy");
  cuda_check(cudaMalloc(&nets.tx, n * sizeof(int)), "cudaMalloc tx");
  cuda_check(cudaMalloc(&nets.ty, n * sizeof(int)), "cudaMalloc ty");
  cuda_check(cudaMalloc(&d_hcap, grid.h_capacity.size() * sizeof(int)), "cudaMalloc hcap");
  cuda_check(cudaMalloc(&d_vcap, grid.v_capacity.size() * sizeof(int)), "cudaMalloc vcap");
  cuda_check(cudaMalloc(&d_choice, n * sizeof(uint8_t)), "cudaMalloc choice");
  cuda_check(cudaMalloc(&d_costs, n * sizeof(double)), "cudaMalloc costs");

  cuda_check(cudaMemcpy(nets.sx, sx.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy sx");
  cuda_check(cudaMemcpy(nets.sy, sy.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy sy");
  cuda_check(cudaMemcpy(nets.tx, tx.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy tx");
  cuda_check(cudaMemcpy(nets.ty, ty.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy ty");
  cuda_check(cudaMemcpy(d_hcap, grid.h_capacity.data(), grid.h_capacity.size() * sizeof(int),
                        cudaMemcpyHostToDevice), "copy hcap");
  cuda_check(cudaMemcpy(d_vcap, grid.v_capacity.data(), grid.v_capacity.size() * sizeof(int),
                        cudaMemcpyHostToDevice), "copy vcap");

  const int block = 256;
  const int blocks = (n + block - 1) / block;
  choose_manhattan_candidates<<<blocks, block>>>(grid.width, n, nets.sx, nets.sy, nets.tx, nets.ty,
                                                 d_hcap, d_vcap, d_choice, d_costs);
  cuda_check(cudaGetLastError(), "choose_manhattan_candidates");
  cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
  cuda_check(cudaMemcpy(choice.data(), d_choice, n * sizeof(uint8_t), cudaMemcpyDeviceToHost),
             "copy choice");
  cuda_check(cudaMemcpy(costs.data(), d_costs, n * sizeof(double), cudaMemcpyDeviceToHost),
             "copy costs");

  cudaFree(nets.sx);
  cudaFree(nets.sy);
  cudaFree(nets.tx);
  cudaFree(nets.ty);
  cudaFree(d_hcap);
  cudaFree(d_vcap);
  cudaFree(d_choice);
  cudaFree(d_costs);

  std::vector<Path> paths(n);
  Demand demand{std::vector<int>(h_edges(grid), 0), std::vector<int>(v_edges(grid), 0)};
  for (int i = 0; i < n; ++i) {
    paths[i] = build_candidate_path(grid, benchmark.nets[i], choice[i], costs[i]);
    add_path(demand, paths[i]);
  }
  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  return collect(benchmark, config, paths, demand, ms);
}

Metrics route_cuda_dogleg_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  const int n = static_cast<int>(benchmark.nets.size());

  std::vector<int> sx(n), sy(n), tx(n), ty(n);
  for (int i = 0; i < n; ++i) {
    sx[i] = benchmark.nets[i].source.x;
    sy[i] = benchmark.nets[i].source.y;
    tx[i] = benchmark.nets[i].target.x;
    ty[i] = benchmark.nets[i].target.y;
  }

  DeviceNets nets;
  int *d_hcap = nullptr;
  int *d_vcap = nullptr;
  uint8_t *d_choice_kind = nullptr;
  int *d_choice_mid = nullptr;
  double *d_costs = nullptr;
  std::vector<uint8_t> choice_kind(n);
  std::vector<int> choice_mid(n);
  std::vector<double> costs(n);

  cuda_check(cudaMalloc(&nets.sx, n * sizeof(int)), "cudaMalloc sx");
  cuda_check(cudaMalloc(&nets.sy, n * sizeof(int)), "cudaMalloc sy");
  cuda_check(cudaMalloc(&nets.tx, n * sizeof(int)), "cudaMalloc tx");
  cuda_check(cudaMalloc(&nets.ty, n * sizeof(int)), "cudaMalloc ty");
  cuda_check(cudaMalloc(&d_hcap, grid.h_capacity.size() * sizeof(int)), "cudaMalloc hcap");
  cuda_check(cudaMalloc(&d_vcap, grid.v_capacity.size() * sizeof(int)), "cudaMalloc vcap");
  cuda_check(cudaMalloc(&d_choice_kind, n * sizeof(uint8_t)), "cudaMalloc choice_kind");
  cuda_check(cudaMalloc(&d_choice_mid, n * sizeof(int)), "cudaMalloc choice_mid");
  cuda_check(cudaMalloc(&d_costs, n * sizeof(double)), "cudaMalloc costs");

  cuda_check(cudaMemcpy(nets.sx, sx.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy sx");
  cuda_check(cudaMemcpy(nets.sy, sy.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy sy");
  cuda_check(cudaMemcpy(nets.tx, tx.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy tx");
  cuda_check(cudaMemcpy(nets.ty, ty.data(), n * sizeof(int), cudaMemcpyHostToDevice), "copy ty");
  cuda_check(cudaMemcpy(d_hcap, grid.h_capacity.data(), grid.h_capacity.size() * sizeof(int),
                        cudaMemcpyHostToDevice), "copy hcap");
  cuda_check(cudaMemcpy(d_vcap, grid.v_capacity.data(), grid.v_capacity.size() * sizeof(int),
                        cudaMemcpyHostToDevice), "copy vcap");

  const int block = 256;
  const int blocks = (n + block - 1) / block;
  choose_dogleg_candidates<<<blocks, block>>>(grid.width, grid.height, n, nets.sx, nets.sy,
                                             nets.tx, nets.ty, d_hcap, d_vcap,
                                             d_choice_kind, d_choice_mid, d_costs);
  cuda_check(cudaGetLastError(), "choose_dogleg_candidates");
  cuda_check(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
  cuda_check(cudaMemcpy(choice_kind.data(), d_choice_kind, n * sizeof(uint8_t),
                        cudaMemcpyDeviceToHost),
             "copy choice_kind");
  cuda_check(cudaMemcpy(choice_mid.data(), d_choice_mid, n * sizeof(int), cudaMemcpyDeviceToHost),
             "copy choice_mid");
  cuda_check(cudaMemcpy(costs.data(), d_costs, n * sizeof(double), cudaMemcpyDeviceToHost),
             "copy costs");

  cudaFree(nets.sx);
  cudaFree(nets.sy);
  cudaFree(nets.tx);
  cudaFree(nets.ty);
  cudaFree(d_hcap);
  cudaFree(d_vcap);
  cudaFree(d_choice_kind);
  cudaFree(d_choice_mid);
  cudaFree(d_costs);

  std::vector<Path> paths(n);
  Demand demand{std::vector<int>(h_edges(grid), 0), std::vector<int>(v_edges(grid), 0)};
  for (int i = 0; i < n; ++i) {
    paths[i] = build_dogleg_path(grid, benchmark.nets[i], choice_kind[i], choice_mid[i], costs[i]);
    add_path(demand, paths[i]);
  }
  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  Metrics metrics = collect(benchmark, config, paths, demand, ms);
  metrics.mode = "cuda_dogleg_candidate";
  return metrics;
}

} // namespace router

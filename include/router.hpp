#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace router {

struct Point {
  int x = 0;
  int y = 0;
};

struct Net {
  Point source;
  Point target;
};

struct Edge {
  uint8_t dir = 0; // 0 = horizontal, 1 = vertical
  int index = -1;
};

struct Path {
  std::vector<Point> points;
  std::vector<Edge> edges;
  double cost = 0.0;
  bool routed = false;
};

struct Grid {
  int width = 0;
  int height = 0;
  int default_capacity = 1;
  std::vector<int> h_capacity; // y * (width - 1) + min(x0, x1)
  std::vector<int> v_capacity; // min(y0, y1) * width + x
};

struct Benchmark {
  Grid grid;
  std::vector<Net> nets;
};

struct RouterConfig {
  int iterations = 8;
  int threads = 1;
  int batch_factor = 1;
  double relax_alpha = 2.0;
  double relax_beta = 0.35;
  double congestion_weight = 20.0;
  double mark_weight = 8.0;
  bool collision_aware = true;
};

struct Metrics {
  std::string mode;
  int grid_width = 0;
  int grid_height = 0;
  int nets = 0;
  int threads = 1;
  int iterations = 0;
  int routed_nets = 0;
  int failed_nets = 0;
  long long wirelength = 0;
  long long overflow = 0;
  long long max_overflow = 0;
  double milliseconds = 0.0;
};

Benchmark generate_benchmark(int width, int height, int nets, int capacity,
                             double obstacle_density, uint64_t seed);

Metrics route_sequential(const Benchmark &benchmark, const RouterConfig &config);
Metrics route_parallel_cpu(const Benchmark &benchmark, const RouterConfig &config);
Metrics route_cpu_candidates(const Benchmark &benchmark, const RouterConfig &config);
Metrics route_cpu_dogleg_candidates(const Benchmark &benchmark, const RouterConfig &config);
Metrics route_cuda_candidates(const Benchmark &benchmark, const RouterConfig &config);
Metrics route_cuda_dogleg_candidates(const Benchmark &benchmark, const RouterConfig &config);

std::string csv_header();
std::string to_csv(const Metrics &metrics);

} // namespace router

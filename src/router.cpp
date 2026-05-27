#include "router.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <functional>
#include <limits>
#include <mutex>
#include <numeric>
#include <queue>
#include <random>
#include <sstream>
#include <stdexcept>
#include <thread>

namespace router {
namespace {

struct Demand {
  std::vector<int> h;
  std::vector<int> v;
};

struct SearchNode {
  int x;
  int y;
  int length;
  double cost;
  double key;
};

struct SearchNodeGreater {
  bool operator()(const SearchNode &a, const SearchNode &b) const {
    return a.key > b.key;
  }
};

int h_edges(const Grid &grid) { return grid.height * std::max(0, grid.width - 1); }
int v_edges(const Grid &grid) { return std::max(0, grid.height - 1) * grid.width; }
int node_index(const Grid &grid, int x, int y) { return y * grid.width + x; }
int manhattan(Point a, Point b) { return std::abs(a.x - b.x) + std::abs(a.y - b.y); }

int h_index(const Grid &grid, int x0, int x1, int y) {
  (void)x1;
  return y * (grid.width - 1) + std::min(x0, x1);
}

int v_index(const Grid &grid, int x, int y0, int y1) {
  return std::min(y0, y1) * grid.width + x;
}

Edge edge_between(const Grid &grid, Point a, Point b) {
  if (a.y == b.y && std::abs(a.x - b.x) == 1) {
    return Edge{0, h_index(grid, a.x, b.x, a.y)};
  }
  if (a.x == b.x && std::abs(a.y - b.y) == 1) {
    return Edge{1, v_index(grid, a.x, a.y, b.y)};
  }
  throw std::runtime_error("edge_between expects adjacent grid points");
}

int edge_capacity(const Grid &grid, Edge e) {
  return e.dir == 0 ? grid.h_capacity[e.index] : grid.v_capacity[e.index];
}

int edge_demand(const Demand &demand, Edge e) {
  return e.dir == 0 ? demand.h[e.index] : demand.v[e.index];
}

int edge_marks(const Demand &marks, Edge e) {
  return e.dir == 0 ? marks.h[e.index] : marks.v[e.index];
}

void add_path(Demand &demand, const Path &path, int delta) {
  for (const auto &edge : path.edges) {
    if (edge.dir == 0) {
      demand.h[edge.index] += delta;
    } else {
      demand.v[edge.index] += delta;
    }
  }
}

long long path_wirelength(const Path &path) {
  return static_cast<long long>(path.edges.size());
}

Path fallback_manhattan(const Grid &grid, const Net &net) {
  Path path;
  path.routed = true;
  Point cur = net.source;
  path.points.push_back(cur);
  while (cur.x != net.target.x) {
    Point next{cur.x + (net.target.x > cur.x ? 1 : -1), cur.y};
    path.edges.push_back(edge_between(grid, cur, next));
    path.points.push_back(next);
    cur = next;
  }
  while (cur.y != net.target.y) {
    Point next{cur.x, cur.y + (net.target.y > cur.y ? 1 : -1)};
    path.edges.push_back(edge_between(grid, cur, next));
    path.points.push_back(next);
    cur = next;
  }
  return path;
}

double capacity_l_cost(const Grid &grid, Edge edge) {
  const int cap = edge_capacity(grid, edge);
  return cap <= 0 ? 1.0e6 : 1.0 / static_cast<double>(cap);
}

Path l_shape_candidate(const Grid &grid, const Net &net, bool horizontal_first) {
  Path path;
  path.routed = true;
  Point cur = net.source;
  path.points.push_back(cur);
  const auto move_x = [&] {
    while (cur.x != net.target.x) {
      Point next{cur.x + (net.target.x > cur.x ? 1 : -1), cur.y};
      const Edge edge = edge_between(grid, cur, next);
      path.cost += capacity_l_cost(grid, edge);
      path.edges.push_back(edge);
      path.points.push_back(next);
      cur = next;
    }
  };
  const auto move_y = [&] {
    while (cur.y != net.target.y) {
      Point next{cur.x, cur.y + (net.target.y > cur.y ? 1 : -1)};
      const Edge edge = edge_between(grid, cur, next);
      path.cost += capacity_l_cost(grid, edge);
      path.edges.push_back(edge);
      path.points.push_back(next);
      cur = next;
    }
  };
  if (horizontal_first) {
    move_x();
    move_y();
  } else {
    move_y();
    move_x();
  }
  return path;
}

Path choose_l_shape_candidate(const Grid &grid, const Net &net) {
  Path horizontal_vertical = l_shape_candidate(grid, net, true);
  Path vertical_horizontal = l_shape_candidate(grid, net, false);
  if (horizontal_vertical.cost <= vertical_horizontal.cost) {
    return horizontal_vertical;
  }
  return vertical_horizontal;
}

void append_segment(const Grid &grid, Path &path, Point &cur, Point target) {
  while (cur.x != target.x) {
    Point next{cur.x + (target.x > cur.x ? 1 : -1), cur.y};
    const Edge edge = edge_between(grid, cur, next);
    path.cost += capacity_l_cost(grid, edge);
    path.edges.push_back(edge);
    path.points.push_back(next);
    cur = next;
  }
  while (cur.y != target.y) {
    Point next{cur.x, cur.y + (target.y > cur.y ? 1 : -1)};
    const Edge edge = edge_between(grid, cur, next);
    path.cost += capacity_l_cost(grid, edge);
    path.edges.push_back(edge);
    path.points.push_back(next);
    cur = next;
  }
}

Path dogleg_via_y_candidate(const Grid &grid, const Net &net, int mid_y) {
  Path path;
  path.routed = true;
  Point cur = net.source;
  path.points.push_back(cur);
  append_segment(grid, path, cur, Point{net.source.x, mid_y});
  append_segment(grid, path, cur, Point{net.target.x, mid_y});
  append_segment(grid, path, cur, net.target);
  return path;
}

Path dogleg_via_x_candidate(const Grid &grid, const Net &net, int mid_x) {
  Path path;
  path.routed = true;
  Point cur = net.source;
  path.points.push_back(cur);
  append_segment(grid, path, cur, Point{mid_x, net.source.y});
  append_segment(grid, path, cur, Point{mid_x, net.target.y});
  append_segment(grid, path, cur, net.target);
  return path;
}

void add_unique_candidate(std::vector<int> &values, int value, int low, int high) {
  value = std::max(low, std::min(high, value));
  if (std::find(values.begin(), values.end(), value) == values.end()) {
    values.push_back(value);
  }
}

Path choose_dogleg_candidate(const Grid &grid, const Net &net) {
  Path best = choose_l_shape_candidate(grid, net);
  const int step = 8;
  const int mid_x = (net.source.x + net.target.x) / 2;
  const int mid_y = (net.source.y + net.target.y) / 2;

  std::vector<int> x_candidates;
  std::vector<int> y_candidates;
  for (int delta : {0, step, -step, 2 * step, -2 * step}) {
    add_unique_candidate(x_candidates, net.source.x + delta, 0, grid.width - 1);
    add_unique_candidate(x_candidates, net.target.x + delta, 0, grid.width - 1);
    add_unique_candidate(x_candidates, mid_x + delta, 0, grid.width - 1);
    add_unique_candidate(y_candidates, net.source.y + delta, 0, grid.height - 1);
    add_unique_candidate(y_candidates, net.target.y + delta, 0, grid.height - 1);
    add_unique_candidate(y_candidates, mid_y + delta, 0, grid.height - 1);
  }

  auto consider = [&](Path path) {
    if (path.cost < best.cost) {
      best = std::move(path);
    }
  };
  for (int y : y_candidates) {
    consider(dogleg_via_y_candidate(grid, net, y));
  }
  for (int x : x_candidates) {
    consider(dogleg_via_x_candidate(grid, net, x));
  }
  return best;
}

double edge_cost(const Grid &grid, const Demand &demand, const Demand &marks,
                 Edge edge, const RouterConfig &config) {
  const int cap = edge_capacity(grid, edge);
  if (cap <= 0) {
    return 1e6;
  }
  const int dem = edge_demand(demand, edge);
  const int future_overflow = std::max(0, dem + 1 - cap);
  const int mark = config.collision_aware ? edge_marks(marks, edge) : 0;
  return 1.0 + config.congestion_weight * future_overflow +
         config.mark_weight * std::sqrt(static_cast<double>(mark));
}

Path route_one_astar(const Grid &grid, const Net &net, const Demand &demand,
                     const Demand &marks, const RouterConfig &config,
                     int iteration) {
  const int base_len = std::max(1, manhattan(net.source, net.target));
  const double scale = 1.0 + config.relax_beta +
                       0.25 * std::atan(static_cast<double>(iteration) - config.relax_alpha);
  const int bound = std::max(base_len, static_cast<int>(std::ceil(base_len * scale)));
  const int margin = std::max(2, (bound - base_len) / 2 + 2);
  const int xmin = std::max(0, std::min(net.source.x, net.target.x) - margin);
  const int xmax = std::min(grid.width - 1, std::max(net.source.x, net.target.x) + margin);
  const int ymin = std::max(0, std::min(net.source.y, net.target.y) - margin);
  const int ymax = std::min(grid.height - 1, std::max(net.source.y, net.target.y) + margin);

  const int n_nodes = grid.width * grid.height;
  std::vector<double> best(n_nodes, std::numeric_limits<double>::infinity());
  std::vector<Point> parent(n_nodes, Point{-1, -1});
  std::priority_queue<SearchNode, std::vector<SearchNode>, SearchNodeGreater> pq;

  const int sidx = node_index(grid, net.source.x, net.source.y);
  best[sidx] = 0.0;
  pq.push(SearchNode{net.source.x, net.source.y, 0, 0.0,
                     static_cast<double>(manhattan(net.source, net.target))});

  constexpr int dx[4] = {1, -1, 0, 0};
  constexpr int dy[4] = {0, 0, 1, -1};

  while (!pq.empty()) {
    const SearchNode cur = pq.top();
    pq.pop();
    const int cidx = node_index(grid, cur.x, cur.y);
    if (cur.cost > best[cidx] + 1e-9) {
      continue;
    }
    if (cur.x == net.target.x && cur.y == net.target.y) {
      Path path;
      path.routed = true;
      path.cost = cur.cost;
      Point p{cur.x, cur.y};
      while (!(p.x == net.source.x && p.y == net.source.y)) {
        path.points.push_back(p);
        const Point pp = parent[node_index(grid, p.x, p.y)];
        if (pp.x < 0) {
          return fallback_manhattan(grid, net);
        }
        path.edges.push_back(edge_between(grid, pp, p));
        p = pp;
      }
      path.points.push_back(net.source);
      std::reverse(path.points.begin(), path.points.end());
      std::reverse(path.edges.begin(), path.edges.end());
      return path;
    }

    for (int k = 0; k < 4; ++k) {
      const int nx = cur.x + dx[k];
      const int ny = cur.y + dy[k];
      if (nx < xmin || nx > xmax || ny < ymin || ny > ymax) {
        continue;
      }
      const int nlen = cur.length + 1;
      if (nlen + manhattan(Point{nx, ny}, net.target) > bound) {
        continue;
      }
      const Edge edge = edge_between(grid, Point{cur.x, cur.y}, Point{nx, ny});
      const double ncost = cur.cost + edge_cost(grid, demand, marks, edge, config);
      const int nidx = node_index(grid, nx, ny);
      if (ncost + 1e-9 < best[nidx]) {
        best[nidx] = ncost;
        parent[nidx] = Point{cur.x, cur.y};
        pq.push(SearchNode{nx, ny, nlen, ncost,
                           ncost + static_cast<double>(manhattan(Point{nx, ny}, net.target))});
      }
    }
  }
  return fallback_manhattan(grid, net);
}

Demand empty_demand(const Grid &grid) {
  return Demand{std::vector<int>(h_edges(grid), 0), std::vector<int>(v_edges(grid), 0)};
}

std::vector<int> overflow_nets(const Grid &grid, const Demand &demand,
                               const std::vector<Path> &paths) {
  std::vector<int> selected;
  for (int i = 0; i < static_cast<int>(paths.size()); ++i) {
    bool bad = !paths[i].routed;
    for (const auto &edge : paths[i].edges) {
      if (edge_demand(demand, edge) > edge_capacity(grid, edge)) {
        bad = true;
        break;
      }
    }
    if (bad) {
      selected.push_back(i);
    }
  }
  return selected;
}

Metrics collect_metrics(const std::string &mode, const Benchmark &benchmark,
                        const RouterConfig &config, const std::vector<Path> &paths,
                        const Demand &demand, double milliseconds, int iterations) {
  Metrics m;
  m.mode = mode;
  m.grid_width = benchmark.grid.width;
  m.grid_height = benchmark.grid.height;
  m.nets = static_cast<int>(benchmark.nets.size());
  m.threads = config.threads;
  m.iterations = iterations;
  m.milliseconds = milliseconds;
  for (const auto &path : paths) {
    if (path.routed) {
      ++m.routed_nets;
      m.wirelength += path_wirelength(path);
    } else {
      ++m.failed_nets;
    }
  }
  auto scan = [&](const std::vector<int> &dem, const std::vector<int> &cap) {
    for (std::size_t i = 0; i < dem.size(); ++i) {
      const long long of = std::max(0, dem[i] - cap[i]);
      m.overflow += of;
      m.max_overflow = std::max(m.max_overflow, of);
    }
  };
  scan(demand.h, benchmark.grid.h_capacity);
  scan(demand.v, benchmark.grid.v_capacity);
  return m;
}

} // namespace

Benchmark generate_benchmark(int width, int height, int nets, int capacity,
                             double obstacle_density, uint64_t seed) {
  if (width < 2 || height < 2 || nets < 1 || capacity < 1) {
    throw std::runtime_error("invalid benchmark dimensions or capacity");
  }
  Benchmark benchmark;
  benchmark.grid.width = width;
  benchmark.grid.height = height;
  benchmark.grid.default_capacity = capacity;
  benchmark.grid.h_capacity.assign(h_edges(benchmark.grid), capacity);
  benchmark.grid.v_capacity.assign(v_edges(benchmark.grid), capacity);

  std::mt19937_64 rng(seed);
  std::bernoulli_distribution obstacle(obstacle_density);
  for (auto &cap : benchmark.grid.h_capacity) {
    if (obstacle(rng)) {
      cap = 0;
    }
  }
  for (auto &cap : benchmark.grid.v_capacity) {
    if (obstacle(rng)) {
      cap = 0;
    }
  }

  std::uniform_int_distribution<int> xdist(0, width - 1);
  std::uniform_int_distribution<int> ydist(0, height - 1);
  benchmark.nets.reserve(nets);
  for (int i = 0; i < nets; ++i) {
    Point s{xdist(rng), ydist(rng)};
    Point t{xdist(rng), ydist(rng)};
    while (manhattan(s, t) < std::max(4, (width + height) / 16)) {
      t = Point{xdist(rng), ydist(rng)};
    }
    benchmark.nets.push_back(Net{s, t});
  }
  return benchmark;
}

Metrics route_sequential(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  Demand demand = empty_demand(grid);
  Demand marks = empty_demand(grid);
  std::vector<Path> paths(benchmark.nets.size());
  int completed_iterations = 0;

  for (int iter = 0; iter < config.iterations; ++iter) {
    ++completed_iterations;
    std::vector<int> tasks;
    if (iter == 0) {
      tasks.resize(benchmark.nets.size());
      std::iota(tasks.begin(), tasks.end(), 0);
      std::sort(tasks.begin(), tasks.end(), [&](int a, int b) {
        return manhattan(benchmark.nets[a].source, benchmark.nets[a].target) >
               manhattan(benchmark.nets[b].source, benchmark.nets[b].target);
      });
      Demand marks = empty_demand(grid);
      for (const int idx : tasks) {
        paths[idx] = route_one_astar(grid, benchmark.nets[idx], demand, marks, config, iter);
        add_path(demand, paths[idx], +1);
      }
      continue;
    } else {
      tasks = overflow_nets(grid, demand, paths);
      if (tasks.empty()) {
        break;
      }
    }
    std::sort(tasks.begin(), tasks.end(), [&](int a, int b) {
      return manhattan(benchmark.nets[a].source, benchmark.nets[a].target) >
             manhattan(benchmark.nets[b].source, benchmark.nets[b].target);
    });
    for (const int idx : tasks) {
      if (paths[idx].routed) {
        add_path(demand, paths[idx], -1);
      }
      paths[idx] = route_one_astar(grid, benchmark.nets[idx], demand, marks, config, iter);
      add_path(demand, paths[idx], +1);
    }
  }

  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  return collect_metrics("seq", benchmark, config, paths, demand, ms, completed_iterations);
}

Metrics route_parallel_cpu(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  Demand demand = empty_demand(grid);
  std::vector<Path> paths(benchmark.nets.size());
  int completed_iterations = 0;

  for (int iter = 0; iter < config.iterations; ++iter) {
    ++completed_iterations;
    std::vector<int> tasks;
    if (iter == 0) {
      tasks.resize(benchmark.nets.size());
      std::iota(tasks.begin(), tasks.end(), 0);
    } else {
      tasks = overflow_nets(grid, demand, paths);
      if (tasks.empty()) {
        break;
      }
    }
    std::sort(tasks.begin(), tasks.end(), [&](int a, int b) {
      return manhattan(benchmark.nets[a].source, benchmark.nets[a].target) >
             manhattan(benchmark.nets[b].source, benchmark.nets[b].target);
    });

    Demand marks = empty_demand(grid);
    for (const int idx : tasks) {
      if (paths[idx].routed) {
        add_path(marks, paths[idx], +1);
        add_path(demand, paths[idx], -1);
      }
    }

    const int n_threads = std::max(1, config.threads);
    const int batch_size = std::max(1, n_threads * std::max(1, config.batch_factor));
    for (int offset = 0; offset < static_cast<int>(tasks.size()); offset += batch_size) {
      const int count = std::min(batch_size, static_cast<int>(tasks.size()) - offset);
      const Demand snapshot = demand;
      std::vector<Path> new_paths(count);
      std::atomic<int> cursor{0};
      std::vector<std::thread> workers;
      workers.reserve(n_threads);
      for (int tid = 0; tid < n_threads; ++tid) {
        workers.emplace_back([&, tid] {
          (void)tid;
          while (true) {
            const int local = cursor.fetch_add(1);
            if (local >= count) {
              break;
            }
            const int idx = tasks[offset + local];
            new_paths[local] = route_one_astar(grid, benchmark.nets[idx], snapshot, marks, config, iter);
          }
        });
      }
      for (auto &worker : workers) {
        worker.join();
      }
      for (int local = 0; local < count; ++local) {
        const int idx = tasks[offset + local];
        paths[idx] = std::move(new_paths[local]);
        add_path(demand, paths[idx], +1);
      }
    }
  }

  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  return collect_metrics("cpu_threads", benchmark, config, paths, demand, ms, completed_iterations);
}

Metrics route_cpu_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  Demand demand = empty_demand(grid);
  std::vector<Path> paths(benchmark.nets.size());

  for (int i = 0; i < static_cast<int>(benchmark.nets.size()); ++i) {
    paths[i] = choose_l_shape_candidate(grid, benchmark.nets[i]);
    add_path(demand, paths[i], +1);
  }

  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  return collect_metrics("candidate_cpu", benchmark, config, paths, demand, ms, 1);
}

Metrics route_cpu_dogleg_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  const auto start = std::chrono::steady_clock::now();
  const auto &grid = benchmark.grid;
  Demand demand = empty_demand(grid);
  std::vector<Path> paths(benchmark.nets.size());

  for (int i = 0; i < static_cast<int>(benchmark.nets.size()); ++i) {
    paths[i] = choose_dogleg_candidate(grid, benchmark.nets[i]);
    add_path(demand, paths[i], +1);
  }

  const auto end = std::chrono::steady_clock::now();
  const double ms = std::chrono::duration<double, std::milli>(end - start).count();
  return collect_metrics("candidate_cpu_dogleg", benchmark, config, paths, demand, ms, 1);
}

#if !ROUTER_WITH_CUDA
Metrics route_cuda_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  (void)benchmark;
  (void)config;
  throw std::runtime_error("CUDA support was not compiled into this binary");
}

Metrics route_cuda_dogleg_candidates(const Benchmark &benchmark, const RouterConfig &config) {
  (void)benchmark;
  (void)config;
  throw std::runtime_error("CUDA support was not compiled into this binary");
}
#endif

std::string csv_header() {
  return "mode,grid_width,grid_height,nets,threads,iterations,routed_nets,failed_nets,"
         "wirelength,overflow,max_overflow,milliseconds";
}

std::string to_csv(const Metrics &m) {
  std::ostringstream out;
  out << m.mode << ',' << m.grid_width << ',' << m.grid_height << ',' << m.nets << ','
      << m.threads << ',' << m.iterations << ',' << m.routed_nets << ',' << m.failed_nets
      << ',' << m.wirelength << ',' << m.overflow << ',' << m.max_overflow << ','
      << m.milliseconds;
  return out.str();
}

} // namespace router

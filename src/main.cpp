#include "router.hpp"

#include <cstdlib>
#include <exception>
#include <algorithm>
#include <array>
#include <fstream>
#include <iostream>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Args {
  std::string mode = "seq";
  int grid = 128;
  int nets = 2000;
  int capacity = 2;
  double obstacles = 0.02;
  int iterations = 8;
  int threads = 4;
  int batch_factor = 1;
  uint64_t seed = 1;
  int repeats = 1;
  std::string candidate_csv;
  std::string gr_file;
};

void usage(const char *argv0) {
  std::cerr
      << "Usage: " << argv0 << " [options]\n"
      << "  --mode seq|cpu|candidate_cpu|candidate_cpu_dogleg|cuda|cuda_dogleg\n"
      << "  --grid N              square grid size (default 128)\n"
      << "  --nets N              number of two-pin nets (default 2000)\n"
      << "  --capacity N          edge capacity (default 2)\n"
      << "  --obstacles P         probability that an edge is blocked (default 0.02)\n"
      << "  --iterations N        rip-up/reroute iterations (default 8)\n"
      << "  --threads N           CPU worker threads (default 4)\n"
      << "  --batch-factor N      CPU parallel tasks per thread per commit batch (default 1)\n"
      << "  --seed N              benchmark seed (default 1)\n"
      << "  --repeats N           independent repeats (default 1)\n"
      << "  --candidate-csv PATH  Load NTHU reroute candidate endpoints from CSV\n"
      << "  --gr PATH             Load 2D capacity map from an ISPD .gr file\n";
}

int parse_int(const char *value) { return std::stoi(value); }
double parse_double(const char *value) { return std::stod(value); }
uint64_t parse_u64(const char *value) { return static_cast<uint64_t>(std::stoull(value)); }

Args parse_args(int argc, char **argv) {
  Args args;
  for (int i = 1; i < argc; ++i) {
    const std::string key = argv[i];
    auto need_value = [&](const char *name) -> const char * {
      if (i + 1 >= argc) {
        throw std::runtime_error(std::string("missing value for ") + name);
      }
      return argv[++i];
    };
    if (key == "--mode") {
      args.mode = need_value("--mode");
    } else if (key == "--grid") {
      args.grid = parse_int(need_value("--grid"));
    } else if (key == "--nets") {
      args.nets = parse_int(need_value("--nets"));
    } else if (key == "--capacity") {
      args.capacity = parse_int(need_value("--capacity"));
    } else if (key == "--obstacles") {
      args.obstacles = parse_double(need_value("--obstacles"));
    } else if (key == "--iterations") {
      args.iterations = parse_int(need_value("--iterations"));
    } else if (key == "--threads") {
      args.threads = parse_int(need_value("--threads"));
    } else if (key == "--batch-factor") {
      args.batch_factor = parse_int(need_value("--batch-factor"));
    } else if (key == "--seed") {
      args.seed = parse_u64(need_value("--seed"));
    } else if (key == "--repeats") {
      args.repeats = parse_int(need_value("--repeats"));
    } else if (key == "--candidate-csv") {
      args.candidate_csv = need_value("--candidate-csv");
    } else if (key == "--gr") {
      args.gr_file = need_value("--gr");
    } else if (key == "--help" || key == "-h") {
      usage(argv[0]);
      std::exit(0);
    } else {
      throw std::runtime_error("unknown argument: " + key);
    }
  }
  return args;
}

std::vector<std::string> split_csv_line(const std::string &line) {
  std::vector<std::string> fields;
  std::stringstream ss(line);
  std::string field;
  while (std::getline(ss, field, ',')) {
    fields.push_back(field);
  }
  return fields;
}

router::Benchmark load_candidate_csv(const std::string &path, int capacity) {
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open candidate CSV: " + path);
  }

  router::Benchmark benchmark;
  std::string line;
  bool first = true;
  int max_x = 0;
  int max_y = 0;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    if (first) {
      first = false;
      if (line.find("pin1_x") != std::string::npos) {
        continue;
      }
    }
    const auto fields = split_csv_line(line);
    if (fields.size() < 6) {
      continue;
    }
    router::Net net;
    net.source.x = std::stoi(fields[2]);
    net.source.y = std::stoi(fields[3]);
    net.target.x = std::stoi(fields[4]);
    net.target.y = std::stoi(fields[5]);
    max_x = std::max({max_x, net.source.x, net.target.x});
    max_y = std::max({max_y, net.source.y, net.target.y});
    benchmark.nets.push_back(net);
  }

  if (benchmark.nets.empty()) {
    throw std::runtime_error("candidate CSV has no usable rows: " + path);
  }
  benchmark.grid.width = max_x + 1;
  benchmark.grid.height = max_y + 1;
  benchmark.grid.default_capacity = capacity;
  benchmark.grid.h_capacity.assign(benchmark.grid.height * std::max(0, benchmark.grid.width - 1), capacity);
  benchmark.grid.v_capacity.assign(std::max(0, benchmark.grid.height - 1) * benchmark.grid.width, capacity);
  return benchmark;
}

std::vector<int> parse_ints(const std::string &line) {
  std::stringstream ss(line);
  std::vector<int> values;
  std::string token;
  while (ss >> token) {
    try {
      std::size_t parsed = 0;
      int value = std::stoi(token, &parsed);
      if (parsed == token.size()) {
        values.push_back(value);
      }
    } catch (const std::exception &) {
    }
  }
  return values;
}

void apply_gr_capacity(router::Benchmark &benchmark, const std::string &path) {
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open .gr file: " + path);
  }

  std::string line;
  if (!std::getline(in, line)) {
    throw std::runtime_error(".gr file is empty: " + path);
  }
  const auto grid_values = parse_ints(line);
  if (grid_values.size() < 3) {
    throw std::runtime_error("failed to parse .gr grid line: " + path);
  }
  const int width = grid_values[0];
  const int height = grid_values[1];
  const int layers = grid_values[2];
  if (width < 2 || height < 2 || layers < 1) {
    throw std::runtime_error("invalid .gr grid dimensions: " + path);
  }

  if (!std::getline(in, line)) {
    throw std::runtime_error("missing .gr vertical capacity line: " + path);
  }
  std::vector<int> vertical = parse_ints(line);
  if (!std::getline(in, line)) {
    throw std::runtime_error("missing .gr horizontal capacity line: " + path);
  }
  std::vector<int> horizontal = parse_ints(line);
  if (static_cast<int>(vertical.size()) < layers || static_cast<int>(horizontal.size()) < layers) {
    throw std::runtime_error("not enough .gr layer capacities: " + path);
  }
  vertical.resize(layers);
  horizontal.resize(layers);

  const int base_h = std::accumulate(horizontal.begin(), horizontal.end(), 0);
  const int base_v = std::accumulate(vertical.begin(), vertical.end(), 0);
  benchmark.grid.width = width;
  benchmark.grid.height = height;
  benchmark.grid.default_capacity = std::max(1, std::min(base_h, base_v));
  benchmark.grid.h_capacity.assign(height * (width - 1), base_h);
  benchmark.grid.v_capacity.assign((height - 1) * width, base_v);

  while (std::getline(in, line)) {
    const auto values = parse_ints(line);
    if (values.size() != 7) {
      continue;
    }
    const int x1 = values[0];
    const int y1 = values[1];
    const int z1 = values[2] - 1;
    const int x2 = values[3];
    const int y2 = values[4];
    const int z2 = values[5] - 1;
    const int capacity = values[6];
    if (z1 != z2 || z1 < 0 || z1 >= layers) {
      continue;
    }
    if (y1 == y2 && std::abs(x1 - x2) == 1 && y1 >= 0 && y1 < height &&
        std::min(x1, x2) >= 0 && std::min(x1, x2) < width - 1) {
      const int idx = y1 * (width - 1) + std::min(x1, x2);
      benchmark.grid.h_capacity[idx] += capacity - horizontal[z1];
    } else if (x1 == x2 && std::abs(y1 - y2) == 1 && x1 >= 0 && x1 < width &&
               std::min(y1, y2) >= 0 && std::min(y1, y2) < height - 1) {
      const int idx = std::min(y1, y2) * width + x1;
      benchmark.grid.v_capacity[idx] += capacity - vertical[z1];
    }
  }
}

} // namespace

int main(int argc, char **argv) {
  try {
    const Args args = parse_args(argc, argv);
    router::RouterConfig config;
    config.iterations = args.iterations;
    config.threads = args.threads;
    config.batch_factor = args.batch_factor;

    std::cout << router::csv_header() << '\n';
    for (int r = 0; r < args.repeats; ++r) {
      auto benchmark = args.candidate_csv.empty()
                           ? router::generate_benchmark(args.grid, args.grid, args.nets,
                                                        args.capacity, args.obstacles,
                                                        args.seed + r)
                           : load_candidate_csv(args.candidate_csv, args.capacity);
      if (!args.gr_file.empty()) {
        apply_gr_capacity(benchmark, args.gr_file);
      }

      router::Metrics metrics;
      if (args.mode == "seq") {
        config.threads = 1;
        metrics = router::route_sequential(benchmark, config);
      } else if (args.mode == "cpu") {
        metrics = router::route_parallel_cpu(benchmark, config);
      } else if (args.mode == "candidate_cpu") {
        metrics = router::route_cpu_candidates(benchmark, config);
      } else if (args.mode == "candidate_cpu_dogleg") {
        metrics = router::route_cpu_dogleg_candidates(benchmark, config);
      } else if (args.mode == "cuda") {
        metrics = router::route_cuda_candidates(benchmark, config);
      } else if (args.mode == "cuda_dogleg") {
        metrics = router::route_cuda_dogleg_candidates(benchmark, config);
      } else {
        throw std::runtime_error("unknown mode: " + args.mode);
      }
      std::cout << router::to_csv(metrics) << '\n';
    }
  } catch (const std::exception &ex) {
    std::cerr << "error: " << ex.what() << '\n';
    return 1;
  }
  return 0;
}

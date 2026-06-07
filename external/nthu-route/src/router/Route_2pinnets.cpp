#include "Route_2pinnets.h"

#include <boost/multi_array/base.hpp>
#include <boost/multi_array/multi_array_ref.hpp>
#include <stdlib.h>
#include <sys/types.h>
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <stack>
#include <unordered_map>
#include <utility>
#include <vector>

#include "flute4nthuroute.h"
#include "../grdb/EdgePlane.h"
#include "../grdb/RoutingComponent.h"
#include "../grdb/RoutingRegion.h"
#include "router/DataDef.h"

//#define SPDLOG_TRACE_ON
#include "../spdlog/details/spdlog_impl.h"
#include "Congestion.h"
#include "Construct_2d_tree.h"
#include "Range_router.h"

#include "../spdlog/spdlog.h"

namespace NTHUR {

using namespace std;

namespace {
using ProfileClock = std::chrono::steady_clock;

double profile_ms(ProfileClock::time_point start, ProfileClock::time_point end) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

bool profile_enabled() {
    return std::getenv("NTHU_PROFILE") != nullptr;
}

bool v8_direct_route_all_enabled() {
    return std::getenv("NTHU_V8_DIRECT_ROUTE_ALL") != nullptr;
}

bool v8_direct_route_all_log_enabled() {
    return profile_enabled() || std::getenv("NTHU_V8_DIRECT_ROUTE_ALL_LOG") != nullptr;
}

int v8_direct_route_all_limit() {
    const char* value = std::getenv("NTHU_V8_DIRECT_ROUTE_ALL_LIMIT");
    if (value == nullptr || *value == '\0') {
        return std::numeric_limits<int>::max();
    }
    const int parsed = std::atoi(value);
    if (parsed <= 0) {
        return std::numeric_limits<int>::max();
    }
    return parsed;
}

int v8_direct_route_all_min_score() {
    const char* value = std::getenv("NTHU_V8_DIRECT_ROUTE_ALL_MIN_SCORE");
    if (value == nullptr || *value == '\0') {
        return 1;
    }
    return std::max(1, std::atoi(value));
}

int v8_path_overflow_score(const Two_pin_element_2d& two_pin, const Congestion& congestion) {
    int overflow_score = 0;
    for (int i = static_cast<int>(two_pin.path.size()) - 2; i >= 0; --i) {
        const Edge_2d& edge = congestion.congestionMap2d.edge(two_pin.path[i], two_pin.path[i + 1]);
        overflow_score += std::max(0, edge.overUsage());
    }
    return overflow_score;
}
}

Route_2pinnets::Route_2pinnets(Construct_2d_tree& construct_2d_tree, RangeRouter& rangerouter, Congestion& congestion) :
        rr_map { construct_2d_tree.rr_map }, //
        gridcell { boost::extents[rr_map.get_gridx()][rr_map.get_gridy()] }, //
        colorMap { boost::extents[rr_map.get_gridx()][rr_map.get_gridy()] }, //
        dirTransferTable { 1, 0, 3, 2 }, //
        construct_2d_tree { construct_2d_tree }, //
        rangerouter { rangerouter }, //
        congestion { congestion } {
    log_sp = spdlog::get("NTHUR");
}

void Route_2pinnets::allocate_gridcell() {

#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (u_int32_t x = 0; x < gridcell.size(); ++x) {
        for (u_int32_t y = 0; y < gridcell[0].size(); ++y) {
            gridcell[x][y].set(x, y);
        }
    }

    SPDLOG_TRACE(log_sp, "initialize gridcell successfully");

}

void Route_2pinnets::init_gridcell() {
#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (u_int32_t x = 0; x < gridcell.size(); ++x) {
        for (u_int32_t y = 0; y < gridcell[0].size(); ++y) {
            gridcell[x][y].points.clear();
        }
    }
    for (Two_pin_element_2d& two_pin : construct_2d_tree.two_pin_list) {
        //add pin1
        int cur_x = two_pin.pin1.x;
        int cur_y = two_pin.pin1.y;
        gridcell[cur_x][cur_y].points.push_back(&two_pin);
        //add pin2
        cur_x = two_pin.pin2.x;
        cur_y = two_pin.pin2.y;
        gridcell[cur_x][cur_y].points.push_back(&two_pin);
    }
}

void Route_2pinnets::route_all_2pin_net() {
    auto start = ProfileClock::now();
    if (v8_direct_route_all_enabled()) {
        struct Candidate {
            int id;
            int overflow_score;
            int bsize;
        };

        const int pin_count = static_cast<int>(construct_2d_tree.two_pin_list.size());
        std::vector<Candidate> scanned(pin_count);
        std::vector<unsigned char> is_candidate(pin_count, 0);
        int overflow_seen = 0;
        const int min_score = v8_direct_route_all_min_score();

#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(dynamic, 256) reduction(max:overflow_seen)
#endif
        for (int i = 0; i < pin_count; ++i) {
            Two_pin_element_2d& two_pin = construct_2d_tree.two_pin_list[i];
            const int overflow_score = v8_path_overflow_score(two_pin, congestion);
            if (overflow_score >= min_score) {
                scanned[i] = Candidate {
                        i,
                        overflow_score,
                        std::abs(two_pin.pin1.x - two_pin.pin2.x) + std::abs(two_pin.pin1.y - two_pin.pin2.y) };
                is_candidate[i] = 1;
                overflow_seen = 1;
            }
        }

        std::vector<Candidate> candidates;
        candidates.reserve(pin_count);
        for (int i = 0; i < pin_count; ++i) {
            if (is_candidate[i]) {
                candidates.push_back(scanned[i]);
            }
        }
        std::sort(candidates.begin(), candidates.end(), [](const Candidate& a, const Candidate& b) {
            if (a.overflow_score != b.overflow_score) {
                return a.overflow_score > b.overflow_score;
            }
            if (a.bsize != b.bsize) {
                return a.bsize > b.bsize;
            }
            return a.id < b.id;
        });

        const int limit = v8_direct_route_all_limit();
        const int route_count = std::min(static_cast<int>(candidates.size()), limit);
        std::vector<Two_pin_element_2d*> reroute_candidates;
        reroute_candidates.reserve(route_count);
        for (int i = 0; i < route_count; ++i) {
            Two_pin_element_2d& two_pin = construct_2d_tree.two_pin_list[candidates[i].id];
            two_pin.done = construct_2d_tree.done_iter;
            reroute_candidates.push_back(&two_pin);
        }

        const auto after_scan = ProfileClock::now();
        if (!reroute_candidates.empty()) {
            rangerouter.prepare_cuda_dogleg_choices(reroute_candidates);
            rangerouter.route_twopin_candidates(reroute_candidates, 2);
        }
        construct_2d_tree.mazeroute_in_range.clear_net_tree();

        if (v8_direct_route_all_log_enabled()) {
            log_sp->info("v8 direct route_all: pins={} hot_candidates={} routed={} limit={} min_score={} overflow_seen={} scan_sort_ms={:.3f} total_ms={:.3f}",
                    pin_count, candidates.size(), reroute_candidates.size(), limit, min_score,
                    overflow_seen, profile_ms(start, after_scan), profile_ms(start, ProfileClock::now()));
        }
        return;
    }

    init_gridcell();
    auto after_init = ProfileClock::now();
    rangerouter.define_interval();
    auto after_define = ProfileClock::now();
    rangerouter.divide_grid_edge_into_interval();
    auto after_divide = ProfileClock::now();
    rangerouter.specify_all_range(gridcell);
    auto after_specify = ProfileClock::now();
    if (profile_enabled()) {
        log_sp->info("profile route_all init_gridcell_ms={:.3f} define_interval_ms={:.3f} divide_interval_ms={:.3f} specify_all_range_ms={:.3f} total_ms={:.3f}",
                profile_ms(start, after_init),
                profile_ms(after_init, after_define),
                profile_ms(after_define, after_divide),
                profile_ms(after_divide, after_specify),
                profile_ms(start, after_specify));
    }
}

void Route_2pinnets::reset_c_map_used_net_to_one() {

    auto edges = congestion.congestionMap2d.all();
    Edge_2d* edge_data = edges.begin();
    const std::ptrdiff_t edge_count = static_cast<std::ptrdiff_t>(congestion.congestionMap2d.num_elements());

#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (std::ptrdiff_t i = 0; i < edge_count; ++i) {
        Edge_2d& edge = edge_data[i];
        for (auto& routeNetTable : edge.used_net) {
            edge.used_net[routeNetTable.first] = 1;
        }
    }

}

void Route_2pinnets::put_terminal_color_on_colormap(int net_id) {
    for (const Net::Pin& pin : rr_map.get_net(net_id).get_pinList()) {
        colorMap[pin.x][pin.y].terminal = net_id;
    }
}

//return: one-degree terminal, non-one-degree terminal, one-degree nonterminal, steiner point, two-degree (dir)
Coordinate_2d Route_2pinnets::determine_is_terminal_or_steiner_point(Coordinate_2d& c, Coordinate_2d& head, int net_id, PointType& pointType) {

    Coordinate_2d result;
    if (colorMap[c.x][c.y].terminal == net_id) {
        for (EdgePlane<Edge_2d>::Handle& h : congestion.congestionMap2d.neighbors(c)) {
            if (h.vertex() != head && h.edge().lookupNet(net_id)) {
                pointType = severalDegreeTerminal;
                return result;
            }
        }
        pointType = oneDegreeTerminal;

    } else {
        int other_passed_edge = 0;
        for (EdgePlane<Edge_2d>::Handle& h : congestion.congestionMap2d.neighbors(c)) {
            if (h.vertex() != head && h.edge().lookupNet(net_id)) {
                ++other_passed_edge;
                if (other_passed_edge > 1) {
                    pointType = steinerPoint;
                    return -1;
                }
                result = h.vertex();
            }
        }
        if (other_passed_edge == 0) {
            pointType = oneDegreeNonterminal;

        } else {
            pointType = twoDegree;

        }
    }
    return result;
}

void Route_2pinnets::add_two_pin(int net_id, std::vector<Coordinate_2d>& path) {
    if (path.size() > 1) {
        construct_2d_tree.two_pin_list.emplace_back();
        Two_pin_element_2d& two_pin = construct_2d_tree.two_pin_list.back();
        two_pin.pin1 = path.front();
        two_pin.net_id = net_id;
        two_pin.pin2 = path.back();
        two_pin.path = path;
        path.clear();
        path.push_back(two_pin.pin2);
    }
}

void Route_2pinnets::fillTree(int offset, int net_id) {
    int sizeTree = construct_2d_tree.two_pin_list.size() - offset;
    TreeFlute& tree = construct_2d_tree.net_flutetree[net_id];

    tree.branch.resize(sizeTree + 1);

    std::unordered_map<Coordinate_2d, int> indexmap;
    indexmap.reserve(sizeTree + 1);

    Two_pin_element_2d& first_pin = construct_2d_tree.two_pin_list.at(offset);
    indexmap.emplace(first_pin.pin1, 0);

    tree.branch[0].x = first_pin.pin1.x;
    tree.branch[0].y = first_pin.pin1.y;
    tree.branch[0].n = 0;

    for (int i = 1; i < sizeTree + 1; ++i) {
        Two_pin_element_2d& two_pin = construct_2d_tree.two_pin_list.at(offset + i - 1);

        indexmap.emplace(two_pin.pin2, i);

        tree.branch[i].x = two_pin.pin2.x;
        tree.branch[i].y = two_pin.pin2.y;
        tree.branch[i].n = indexmap.at(two_pin.pin1);

    }
    tree.number = sizeTree + 1;

}

void Route_2pinnets::bfs_for_find_two_pin_list(Coordinate_2d start_coor, int net_id) {

    std::stack<std::vector<Coordinate_2d>> stack;
    stack.emplace();
    stack.top().push_back(start_coor);

    int offset = construct_2d_tree.two_pin_list.size();

    while (!stack.empty()) {
        std::vector<Coordinate_2d>& path = stack.top();
        const Coordinate_2d& c = path.back();
        colorMap[c.x][c.y].traverse = net_id;

        if (colorMap[c.x][c.y].terminal == net_id) {
            add_two_pin(net_id, path);
        }

        std::vector<Coordinate_2d> neighbors;
        neighbors.reserve(4);
        for (EdgePlane<Edge_2d>::Handle& h : congestion.congestionMap2d.neighbors(c)) {
            if (h.edge().lookupNet(net_id) && //
                    (colorMap[h.vertex().x][h.vertex().y].traverse != net_id)) {
                neighbors.push_back(h.vertex());
            }
        }

        switch (neighbors.size()) {
        case 0:
            congestion.update_congestion_map_remove_two_pin_net(path, net_id);
            stack.pop();
            break;
        default:
            add_two_pin(net_id, path);
            for (std::size_t i = 1; i < neighbors.size(); ++i) {
                stack.emplace(path);
                stack.top().emplace_back(neighbors.at(i));
            }  // fall through
        case 1:
            path.emplace_back(neighbors.at(0));
            break;
        }
    }

    fillTree(offset, net_id);
}

void Route_2pinnets::reallocate_two_pin_list() {

#ifdef NTHU_ROUTE_OPENMP
#pragma omp parallel for schedule(static)
#endif
    for (u_int32_t i = 0; i < colorMap.num_elements(); ++i) {
        colorMap.data()[i].set(-1, -1);
    }

    reset_c_map_used_net_to_one();

    vector<Two_pin_element_2d>& v = construct_2d_tree.two_pin_list;
// erase-remove idiom
    v.erase(std::remove_if(v.begin(), v.end(), [& ](const Two_pin_element_2d& pin) {
        return construct_2d_tree.NetDirtyBit[pin.net_id];
    }), v.end());

    for (uint32_t netId = 0; netId < rr_map.get_netNumber(); ++netId) {
        if (construct_2d_tree.NetDirtyBit[netId]) {
            put_terminal_color_on_colormap(netId);

            bfs_for_find_two_pin_list(rr_map.get_net(netId).get_pinList()[0].xy(), netId);

            construct_2d_tree.NetDirtyBit[netId] = false;

        }
    }

}

} // namespace NTHUR

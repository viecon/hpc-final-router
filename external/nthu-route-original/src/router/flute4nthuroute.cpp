#include "flute4nthuroute.h"

#include <algorithm>
#include <cassert>
#include <cstdlib>
#include <vector>

#include "../flute/flute-function.h"
#include "flute/flute-ds.h"
#include "grdb/RoutingComponent.h"
namespace NTHUR {

Flute::Flute() {
    readLUT();      //Read in the binary lookup table - POWVFILE, POSTFILE

}

void Flute::routeNet(const std::vector<Net::Pin>& pinList, TreeFlute& result) {
    int pinNumber = pinList.size();

    //The pin number must <= MAXD, or the flute will crash
    assert(pinNumber <= MAXD);

    if (pinNumber > 350) {
        std::vector<int> order(pinNumber);
        for (int i = 0; i < pinNumber; ++i) {
            order[i] = i;
        }
        std::sort(order.begin(), order.end(), [&](int lhs, int rhs) {
            const Net::Pin& a = pinList[lhs];
            const Net::Pin& b = pinList[rhs];
            if (a.x != b.x) {
                return a.x < b.x;
            }
            return a.y < b.y;
        });

        result.deg = pinNumber;
        result.length = 0;
        result.number = 2 * pinNumber - 2;
        result.branch.assign(result.number, Branch { 0, 0, 0 });

        for (int i = 0; i < pinNumber; ++i) {
            const Net::Pin& pin = pinList[order[i]];
            result.branch[i].x = pin.x;
            result.branch[i].y = pin.y;
            result.branch[i].n = (i == 0) ? 0 : i - 1;
            if (i > 0) {
                const Branch& prev = result.branch[i - 1];
                result.length += std::abs(result.branch[i].x - prev.x) + std::abs(result.branch[i].y - prev.y);
            }
        }

        for (int i = pinNumber; i < result.number; ++i) {
            result.branch[i] = result.branch[0];
            result.branch[i].n = 0;
        }
        return;
    }

    // insert 2D-coordinate of pins of a net into x_ and y_
    for (int pinId = 0; pinId < pinNumber; ++pinId) {
        x_[pinId] = pinList[pinId].x ;
        y_[pinId] = pinList[pinId].y ;
    }

    // obtain the routing tree by FLUTE
    TreeWrapper routingTree;

    routingTree.tree = flute(pinNumber, x_.data(), y_.data(), ACCURACY);
    result.set(routingTree.tree);

}

void Flute::printTree(Tree& routingTree) {
    printtree(routingTree);
}

void Flute::plotTree(Tree& routingTree) {
    plottree(routingTree);
}

int Flute::treeWireLength(Tree& routingTree) {
    return static_cast<int>(wirelength(routingTree));
}
} // namespace NTHUR

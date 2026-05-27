#include "ispdData.h"
#include "LayerAssignment.h"

#include <iostream>
#include <fstream>
#include <algorithm>
#include <utility>
#include <string>
#include <cassert>


int main(int argc, char **argv) {

    assert(argc >= 3 && "Usage: ./router <inputFile> <outputFile>");
    std::ifstream fp(argv[1]);
    assert(fp.is_open() && "Failed to open input file");
    ISPDParser::ispdData *ispdData = ISPDParser::parse(fp);
    fp.close();

    // std::cout << *ispdData << std::endl;

    // Convert XY coordinates to grid coordinates
    // Delete nets that have more than 1000 sinks
    // Delete nets that have all pins inside the same tile
    ispdData->nets.erase(std::remove_if(ispdData->nets.begin(), ispdData->nets.end(), [&](ISPDParser::Net *net) {

        for (auto &pin : net->pins) {

            int x = (std::get<0>(pin) - ispdData->lowerLeftX) / ispdData->tileWidth;
            int y = (std::get<1>(pin) - ispdData->lowerLeftY) / ispdData->tileHeight;
            int z = std::get<2>(pin) - 1;

            if (std::any_of(net->pin3D.begin(), net->pin3D.end(), [x, y, z](const auto &pin) {
                return pin.x == x && pin.y == y && pin.z == z;
            })) continue;
            net->pin3D.emplace_back(x, y, z);

            if (std::any_of(net->pin2D.begin(), net->pin2D.end(), [x, y](const auto &pin) { 
                return pin.x == x && pin.y == y;
            })) continue;
            net->pin2D.emplace_back(x, y);

        }

        return net->pin3D.size() > 1000 || net->pin2D.size() <= 1;

    }), ispdData->nets.end());
    ispdData->numNet = ispdData->nets.size();


    // Describe the usage of the given layer assignment algorithm
    // Only works for the given input file "3d.txt"
    if (std::string(argv[1]).find("3d.txt") != std::string::npos) {

        ISPDParser::Net *net = ispdData->nets[0];

        // Decompose multi-pin nets into two-pin nets
        // Since there are only 2 pins in the given net, this step is trivial
        net->twopin.push_back(ISPDParser::TwoPin());
        ISPDParser::TwoPin &twoPin = net->twopin.back();
        twoPin.from = net->pin3D[0];
        twoPin.to   = net->pin3D[1];

        // Assume the two pin net is routed
        // The following code is to assign routing paths to the two-pin net
        // The routing path is a sequence of routing segments
        // For a horizontal segment, the start point is the left grid coordinate
        // For a vertical segment, the start point is the bottom grid coordinate
        // Please check the figures in https://www.ispd.cc/contests/08/3d.pdf
        twoPin.parNet = net;
        twoPin.path.emplace_back(0, 0, true);
        twoPin.path.emplace_back(1, 0, false);
        twoPin.path.emplace_back(0, 1, true);
        twoPin.path.emplace_back(0, 1, false);
        twoPin.path.emplace_back(0, 2, true);
        twoPin.path.emplace_back(1, 2, true);
        twoPin.path.emplace_back(2, 1, false);
        twoPin.path.emplace_back(2, 0, false);

        // Assign routing layers to the two-pin net
        LayerAssignment::Graph graph;
        graph.initialLA(*ispdData, 1);
        graph.convertGRtoLA(*ispdData, true);
        graph.COLA(true);

        // Output result
        graph.output3Dresult("3ds1.txt");
    }

    delete ispdData;
    return 0;
}

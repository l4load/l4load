#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>
#include <vector>

#include "katran/lib/KatranLb.h"

static void require(bool ok, const char* message) {
  if (!ok) throw std::runtime_error(message);
}

static std::vector<uint32_t> ring(int fd, uint32_t size) {
  std::vector<uint32_t> result(size);
  for (uint32_t key = 0; key < size; ++key)
    require(bpf_map_lookup_elem(fd, &key, &result[key]) == 0, "ring read failed");
  return result;
}

int main(int argc, char** argv) {
  try {
    require(argc == 2, "usage: freeze_probe balancer.o (disposable Linux only)");
    katran::KatranConfig config;
    config.mainInterface = "lo";
    config.balancerProgPath = argv[1];
    config.defaultMac = {2, 0, 0, 0, 0, 1};
    config.enableHc = false;
    config.LruSize = 1024;
    config.testing = false;
    katran::KatranLb lb(config, std::make_unique<katran::BpfAdapter>(true));
    lb.loadBpfProgs();
    katran::VipKey vip;
    vip.address = "198.18.0.1";
    vip.port = 8080;
    vip.proto = 6;
    require(lb.addVip(vip), "add VIP failed");
    katran::NewReal first, second;
    first.address = "192.0.2.1";
    second.address = "192.0.2.2";
    first.weight = second.weight = 1;
    require(lb.modifyRealsForVip(katran::ModifyAction::ADD, {first, second}, vip), "initial update failed");
    int fd = lb.getBpfMapFdByName("ch_rings");
    auto before = ring(fd, config.chRingSize);
    require(std::set<uint32_t>(before.begin(), before.end()).size() == 2, "initial ring lacks two backends");
    require(bpf_map_freeze(fd) == 0, "freeze failed");
    first.weight = 0;
    bool accepted = lb.modifyRealsForVip(katran::ModifyAction::ADD, {first}, vip);
    bool modelChanged = false;
    for (const auto& real : lb.getRealsForVip(vip))
      if (real.address == first.address && real.weight == 0) modelChanged = true;
    bool unchanged = before == ring(fd, config.chRingSize);
    std::cout << "{\"api_success\":" << (accepted ? "true" : "false")
              << ",\"model_changed\":" << (modelChanged ? "true" : "false")
              << ",\"kernel_ring_unchanged\":" << (unchanged ? "true" : "false") << "}\n";
    require(accepted && modelChanged && unchanged, "hypothesis not reproduced");
    std::cout << "FALSE_SUCCESS_REPRODUCED\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

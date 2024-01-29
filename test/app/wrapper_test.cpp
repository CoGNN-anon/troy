// #include "TroyFHEWrapper.h"
#include "../../app/TroyFHEWrapper.cuh"

#include <iostream>
#include <thread>
#include <vector>

using namespace troyn;

void test_FHE() {
    FHEWrapper();
}

// This is the function that creates N threads and invokes test_FHE() using them
void run_test_FHE(int N) {
  // Create a vector of std::thread objects
  std::vector<std::thread> threads;

  // Loop N times and create N threads that call test_FHE()
  for (int i = 0; i < N; i++) {
    threads.push_back(std::thread(test_FHE));
  }

  // Loop N times and join all the threads
  for (int i = 0; i < N; i++) {
    threads[i].join();
  }
}

int main() {
    run_test_FHE(10);
    printf("Here\n");
}
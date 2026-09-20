from pathlib import Path
import shutil
import sys

upstream = Path(sys.argv[1]).resolve()
probe = Path(__file__).with_name('freeze_probe.cpp')
shutil.copyfile(probe, upstream / 'l4load_freeze_probe.cpp')
cmake = upstream / 'CMakeLists.txt'
cmake.write_text(cmake.read_text() + '''
add_executable(l4load-freeze-probe l4load_freeze_probe.cpp)
target_compile_features(l4load-freeze-probe PRIVATE cxx_std_20)
target_link_libraries(l4load-freeze-probe PRIVATE katranlb Folly::folly)
''')

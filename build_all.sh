# call this script to update all git dependencies of all packages and build them
cd ./move_stl && sui move build && cd ../
cd ./integer_mate && sui move build && cd ../
cd ./gauge_cap && sui move build && cd ../
cd ./price_provider && sui move build && cd ../
cd ./clmm_pool && sui move build && cd ../
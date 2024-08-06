# File used to launch all kinds of scripts using OFOND package 

# using OFOND
# using ProfileView

# function julia_main()::Cint
#     # do something based on ARGS?

#     # read instance 
#     dirname = "$(@__DIR__)\\data"
#     instance = read_instance(
#         "$dirname\\GeoDataProcessed_LC.csv",
#         "$dirname\\LegDataProcessed_NV1.csv",
#         "$dirname\\VolumeDataProcessed_SC.csv",
#     )
#     # adding properties to the instance
#     instance = add_properties(instance, tentative_first_fit)

#     # read solution
#     solution = read_solution(instance, "$dirname\\RouteDataProcessed.csv")

#     # cut it into smaller instances 
#     # instanceSub = extract_sub_instance(instance; country="FRANCE", timeHorizon=6)
#     # instanceSub = extract_sub_instance(instance; continent="Western Europe", timeHorizon=6)
#     instanceSub = instance
#     # adding properties to the instance
#     # instanceSub = add_properties(instanceSub, tentative_first_fit)
#     # solutionSub_C = extract_sub_solution(solution, instance, instanceSub)
#     solutionSub_C = solution

#     # test algorithms on all cuts 
#     # _, solutionSub_SD = shortest_delivery_heuristic(instanceSub)
#     # instanceSub, solutionSub_G = greedy_heuristic(instanceSub)
#     # _, solutionSub_LB = lower_bound_heuristic(instanceSub)
#     _, solutionSub_GLS = greedy_then_ls_heuristic(instanceSub; timeLimit=300)

#     # export only for the full instance
#     dirname = "$(@__DIR__)\\export"
#     write_solution(solutionSub_GLS, instanceSub; suffix="proposed", directory=dirname)
#     write_solution(solutionSub_C, instanceSub; suffix="current", directory=dirname)

#     return 0 # if things finished successfully
# end

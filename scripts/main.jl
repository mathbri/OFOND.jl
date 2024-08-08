# File used to launch all kinds of scripts using OFOND package 

using OFOND

function julia_main()::Cint
    # do something based on ARGS?

    # read instance 
    dirname = "$(@__DIR__)\\data"
    instance = read_instance(
        "$dirname\\GeoDataProcessed_LC.csv",
        "$dirname\\LegDataProcessed_NV1.csv",
        "$dirname\\VolumeDataProcessed_SC.csv",
    )

    # cut it into smaller instances 
    instance = extract_sub_instance(instance; country="France")

    # test algorithms on all cuts 
    instance, solution = greedy_heuristic(instance)
    _, solution = local_search_heuristic(instance, solution; timeLimit=10)

    # export only for the full instance
    write_solution(solution, instance; suffix="fr")

    return 0 # if things finished successfully
end
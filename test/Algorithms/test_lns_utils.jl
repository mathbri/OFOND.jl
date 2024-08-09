TSGraph = OFOND.TimeSpaceGraph(network, 4)
sol = OFOND.Solution(TTGraph, TSGraph, bundles)

supp1Step3 = TSGraph.hashToIdx[hash(3, supplier1.hash)]
supp2Step4 = TSGraph.hashToIdx[hash(4, supplier2.hash)]
xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

@testset "Slope Sclaling" begin
    # from empty current cost to unit costs
    I, J, V = findnz(TSGraph.currentCost)
    @test all(x -> x == 1e-5, V)
    OFOND.slope_scaling_cost_update!(TSGraph, sol)
    I = vcat(
        allIdxs[1:4],
        allIdxs[1:4],
        allIdxs[5:8],
        allIdxs[5:8],
        allIdxs[9:12],
        allIdxs[9:12],
        allIdxs[13:16],
    )
    J = vcat(
        allIdxs[[10, 11, 12, 9]],
        allIdxs[[19, 20, 17, 18]],
        allIdxs[[10, 11, 12, 9]],
        allIdxs[[18, 19, 20, 17]],
        allIdxs[[14, 15, 16, 13]],
        allIdxs[[18, 19, 20, 17]],
        allIdxs[[18, 19, 20, 17]],
    )
    V = vcat(fill(4.0, 4), fill(10.0, 4), fill(4.0, 4), fill(10.0, 4), fill(4.0, 12))
    @test [TSGraph.currentCost[i, j] for (i, j) in zip(I, J)] == V
    # add some commodities (fill half of volume on supp1_to_plant to see x2 cost update)
    push!(sol.bins[supp1Step3, plantStep1], OFOND.Bin(25, 25, [commodity1, commodity2]))
    OFOND.slope_scaling_cost_update!(TSGraph, sol)
    # check the new current costs for those arc and the no update for the other
    V = vcat(
        fill(4.0, 4), [10.0, 10.0, 20.0, 10.0], fill(4.0, 4), fill(10.0, 4), fill(4.0, 12)
    )
    @test [TSGraph.currentCost[i, j] for (i, j) in zip(I, J)] == V
end

@testset "Add variables" begin
    # build dummy model
    model = Model(HiGHS.Optimizer)
    # add variables for single_plant 
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    # check the variables are correct : x and tau
    @test num_variables(model) == 57
    @test length(model[:x][1, :]) == 15
    @test length(model[:x][2, :]) == 15
    @test length(model[:x][3, :]) == 15
    @test length(model[:tau]) == 12
    @test all(is_binary, model[:x])
    @test all(is_integer, model[:tau])
    # add variables for attract 
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, bundles)
    # check the variables are correct : x and tau and z
    @test num_variables(model) == 60
    @test length(model[:x][1, :]) == 15
    @test length(model[:x][2, :]) == 15
    @test length(model[:x][3, :]) == 15
    @test length(model[:tau]) == 12
    @test length(model[:z]) == 3
    @test all(is_binary, model[:x])
    @test all(is_binary, model[:z])
    @test all(is_integer, model[:tau])
end

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
xdockFromDel0 = TTGraph.hashToIdx[hash(0, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]

@testset "Path constraints utils" begin
    # e matrix generation with single_plant and two_shared_node
    bundles = [bundle1, bundle2, bundle3]
    I, J, V = findnz(OFOND.get_e_matrix(:single_plant, bundles, TTGraph, -1, -1))
    @test I == [1, 3, 2, 1, 2, 3]
    @test J == vcat(allTTIdxs[[3, 4, 6]], fill(allTTIdxs[end], 3))
    @test V == [1.0, 1.0, 1.0, -1.0, -1.0, -1.0]
    e_mat = @test_warn "two_shared_node : src or dst is unknown" OFOND.get_e_matrix(
        :two_shared_node, bundles, TTGraph, -1, -1
    )
    I, J, V = findnz(e_mat)
    @test I == [1, 3, 2, 1, 2, 3]
    @test J == vcat(allTTIdxs[[3, 4, 6]], fill(allTTIdxs[end], 3))
    @test V == [1.0, 1.0, 1.0, -1.0, -1.0, -1.0]
    I, J, V = findnz(
        OFOND.get_e_matrix(:two_shared_node, bundles, TTGraph, xdockFromDel1, plantFromDel0)
    )
    @test I == [1, 2, 3, 1, 2, 3]
    @test J == [
        xdockFromDel1,
        xdockFromDel1,
        xdockFromDel1,
        plantFromDel0,
        plantFromDel0,
        plantFromDel0,
    ]
    @test V == [1.0, 1.0, 1.0, -1.0, -1.0, -1.0]
    # attract path generation (and limit cases)
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel0, xdockFromDel1)
    @test path ==
        [supp1FromDel2, supp1FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel0, xdockFromDel1)
    @test path == [supp2FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [xdockFromDel1, plantFromDel0]
    # reduce path generation
    path = OFOND.generate_reduce_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_reduce_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [supp2FromDel1, plantFromDel0]
    # generate new paths : test warning also
    paths = OFOND.generate_new_paths(
        :attract, instance, sol, [bundle1, bundle2], xdockFromDel1, plantFromDel0
    )
    @test paths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [xdockFromDel1, plantFromDel0]]
    paths = @test_warn "attract : src-dst arc is unknown." OFOND.generate_new_paths(
        :attract, instance, sol, [bundle1, bundle2], xdockFromDel0, xdockFromDel1
    )
    @test paths == [[supp1FromDel2, plantFromDel0], [supp2FromDel1, plantFromDel0]]
    paths = OFOND.generate_new_paths(
        :reduce, instance, sol, [bundle1, bundle2], xdockFromDel1, plantFromDel0
    )
    @test paths == [[supp1FromDel2, plantFromDel0], [supp2FromDel1, plantFromDel0]]
end

@testset "Add path constraints" begin
    # dummy model with the correct variables
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    e_mat = OFOND.get_e_matrix(:single_plant, bundles, TTGraph, -1, -1)
    # common path constraints 
    OFOND.add_path_constraints!(model, TTGraph, bundles, e_mat)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 45
    @test length(model[:path][1]) == 15
    @test typeof(model[:path][1]) == Vector{ConstraintRef}
    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    # old and new path constraints
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, bundles)
    oldPaths = [[supp1FromDel2, plantFromDel0]]
    newPaths = [[supp1FromDel2, xdockFromDel1, plantFromDel0]]
    OFOND.add_old_new_path_constraints!(model, [bundle1], oldPaths, newPaths)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 3
    @test length(model[:oldPaths]) == 1
    @test length(model[:newPaths]) == 2
end

@testset "Packing constraints" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    # packing expr initialization : with empty solution and with non-empty solution with possibly different group of bundles
    I, J, V = findnz(OFOND.init_packing_expr(model, TSGraph, sol))
    @test I == vcat(allIdxs[9:12], allIdxs[9:12], allIdxs[13:16])
    @test J == vcat(
        allIdxs[[14, 15, 16, 13]], allIdxs[[18, 19, 20, 17]], allIdxs[[18, 19, 20, 17]]
    )
    @test V[1] == AffExpr(0, model[:tau][allIdxs[9], allIdxs[14]] => -50)
    @test V[5] == AffExpr(0, model[:tau][allIdxs[9], allIdxs[18]] => -50)
    # adding commodity in solution
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(25, 25, [commodity1, commodity2]))
    expr_mat = OFOND.init_packing_expr(model, TSGraph, sol)
    @test expr_mat[xdockStep4, plantStep1] ==
        AffExpr(25, model[:tau][xdockStep4, plantStep1] => -50)
    @test expr_mat[xdockStep1, plantStep2] ==
        AffExpr(0, model[:tau][xdockStep1, plantStep2] => -50)
    # completing expr : for different bundles checking the correct x variables are taken
    OFOND.complete_packing_expr!(expr_mat, instance, [bundle1])
    @test expr_mat[xdockStep4, plantStep1] == AffExpr(
        25,
        model[:tau][xdockStep4, plantStep1] => -50,
        model[:x][1, (xdockFromDel1, plantFromDel0)] => 20,
    )
    @test expr_mat[xdockStep4, portStep1] == AffExpr(
        0,
        model[:tau][xdockStep4, portStep1] => -50,
        model[:x][1, (xdockFromDel1, portFromDel0)] => 20,
    )
    @test expr_mat[xdockStep1, plantStep2] ==
        AffExpr(0, model[:tau][xdockStep1, plantStep2] => -50)
    # add packing constraints with a dummy model
    OFOND.add_packing_constraints!(model, instance, [bundle1], sol)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 12
    @test length(model[:packing]) == 12
end

@testset "Adding all constraints" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    # adding base constraints
    OFOND.add_constraints!(model, :single_plant, instance, sol, bundles)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 57
    @test length(model[:packing]) == 12
    @test length(model[:path][1]) == 15
    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15

    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, bundles)
    sol.bundlePaths = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp1FromDel2, plantFromDel0],
    ]
    # adding attract or reduce constraints 
    OFOND.add_constraints!(
        model, :attract, instance, sol, bundles, xdockFromDel1, plantFromDel0
    )
    @test num_constraints(model; count_variable_in_set_constraints=false) == 65
    @test length(model[:packing]) == 12
    @test length(model[:path][1]) == 15
    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    @test length(model[:oldPaths]) == 3
    @test length(model[:newPaths]) == 5
end

@testset "Cost filters" begin
    # is_direct_outsource with different arcs
    @test OFOND.is_direct_outsource(TTGraph, Edge(supp1FromDel2, plantFromDel0))
    @test OFOND.is_direct_outsource(TTGraph, Edge(supp1FromDel2, xdockFromDel1))
    @test !OFOND.is_direct_outsource(TTGraph, Edge(xdockFromDel1, plantFromDel0))
    @test !OFOND.is_direct_outsource(TTGraph, Edge(xdockFromDel1, supp1FromDel2))
    # is_bundle_on_arc with different arcs and bundles
    @test OFOND.is_bundle_on_arc(TTGraph, Edge(supp1FromDel2, plantFromDel0), bundle1)
    @test !OFOND.is_bundle_on_arc(TTGraph, Edge(xdockFromDel1, plantFromDel0), bundle1)
    @test !OFOND.is_bundle_on_arc(TTGraph, Edge(supp1FromDel2, plantFromDel0), bundle2)
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]

@testset "Add objective" begin
    # milp_travel_time_arc_cost for different groups of bundles
    I, J, V = findnz(OFOND.milp_travel_time_arc_cost(TTGraph, TSGraph, [bundle1]))
    @test I == fill(1, 2)
    @test collect(edges(TTGraph.graph))[J] ==
        [Edge(supp1FromDel2, xdockFromDel1), Edge(supp1FromDel2, plantFromDel0)]
    @test V == [6.80001, 30.20001]

    I, J, V = findnz(OFOND.milp_travel_time_arc_cost(TTGraph, TSGraph, [bundle1, bundle2]))
    @test I == vcat(fill(1, 2), fill(2, 2))
    @test collect(edges(TTGraph.graph))[J] == [
        Edge(supp1FromDel2, xdockFromDel1),
        Edge(supp1FromDel2, plantFromDel0),
        Edge(supp2FromDel1, plantFromDel0),
        Edge(supp2FromDel1, xdockFromDel0),
    ]
    @test all(V .≈ [6.80001, 30.20001, 9.70001, 24.30001])
    # add objective function for a dummy model with correct variables
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, [bundle1])
    OFOND.add_objective!(model, instance, [bundle1])
    @test objective_sense(model) == MIN_SENSE
    x, tau = model[:x], model[:tau]
    @test objective_function(model) == AffExpr(
        x[1, (supp1FromDel3, xdockFromDel2)] => 1.0,
        x[1, (supp1FromDel2, xdockFromDel1)] => 1.0,
        x[1, (supp1FromDel1, xdockFromDel0)] => 1.0,
        x[1, (supp1FromDel2, plantFromDel0)] => 1.0,
        tau[(xdockStep1, plantStep2)] => 1.0,
        tau[(xdockStep2, plantStep3)] => 1.0,
        tau[(xdockStep3, plantStep4)] => 1.0,
        tau[(xdockStep4, plantStep1)] => 1.0,
        tau[(xdockStep1, portStep2)] => 1.0,
        tau[(xdockStep2, portStep3)] => 1.0,
        tau[(xdockStep3, portStep4)] => 1.0,
        tau[(xdockStep4, portStep1)] => 1.0,
        tau[(portStep1, plantStep2)] => 1.0,
        tau[(portStep2, plantStep3)] => 1.0,
        tau[(portStep3, plantStep4)] => 1.0,
        tau[(portStep4, plantStep1)] => 1.0,
    )
end

@testset "Extracting arcs" begin
    # vect_to_edge for different vectors
    # extract_arcs_from_vector for different vectors
end

@testset "Extracting paths" begin
    # get_path_from_arcs for different group of edges
    # get_paths for a dummy model with correct variables and constraints
end

@testset "Plant and Arc selection" begin
    # select_random_plant
    # select_common_arc
end

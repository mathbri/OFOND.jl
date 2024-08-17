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
    @test V == [-1, -1, -1, 1, 1, 1]
    e_mat = @test_warn "two_shared_node : src or dst is unknown" OFOND.get_e_matrix(
        :two_shared_node, bundles, TTGraph, -1, -1
    )
    I, J, V = findnz(e_mat)
    @test I == [1, 3, 2, 1, 2, 3]
    @test J == vcat(allTTIdxs[[3, 4, 6]], fill(allTTIdxs[end], 3))
    @test V == [-1, -1, -1, 1, 1, 1]
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
    @test V == [-1, -1, -1, 1, 1, 1]
    # attract path generation (and limit cases)
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel0, xdockFromDel1)
    @test path == [supp1FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel0, xdockFromDel1)
    @test path == [supp2FromDel1, xdockFromDel0, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, xdockFromDel1, plantFromDel0]
    path = OFOND.generate_attract_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [plantFromDel0]
    # reduce path generation
    path = OFOND.generate_reduce_path(instance, sol, bundle1, xdockFromDel1, plantFromDel0)
    @test path == [supp1FromDel2, plantFromDel0]
    path = OFOND.generate_reduce_path(instance, sol, bundle2, xdockFromDel1, plantFromDel0)
    @test path == [supp2FromDel1, plantFromDel0]
    # generate new paths : test warning also
    paths = OFOND.generate_new_paths(
        :attract, instance, sol, [bundle1, bundle2], xdockFromDel1, plantFromDel0
    )
    @test paths == [[supp1FromDel2, xdockFromDel1, plantFromDel0], [plantFromDel0]]
    paths = @test_warn "attract : src-dst arc is unknown." OFOND.generate_new_paths(
        :attract, instance, sol, [bundle1, bundle2], xdockFromDel0, xdockFromDel1
    )
    @test paths ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]]
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
    # println(model[:path][1])
    # @test typeof(model[:path][1]) == Vector{ConstraintRef}
    # TODO : check in documentation how to test that model[:path][1] equals 
    # [
    #     x[1, (2, 1)] == 0,
    #     -x[1, (2, 1)] - x[1, (2, 7)] + x[1, (3, 2)] == 0,
    #     -x[1, (3, 2)] - x[1, (3, 8)] - x[1, (3, 15)] + x[1, (4, 3)] == -1,
    #     -x[1, (4, 3)] - x[1, (4, 9)] == 0,
    #     x[1, (6, 5)] == 0,
    #     -x[1, (6, 5)] - x[1, (6, 7)] - x[1, (6, 15)] == 0,
    #     x[1, (2, 7)] + x[1, (6, 7)]  == 0,
    #     x[1, (3, 8)] - x[1, (8, 11)] - x[1, (8, 15)] == 0,
    #     x[1, (4, 9)] - x[1, (9, 12)] == 0,
    #     -x[1, (10, 13)] == 0,
    #     x[1, (8, 11)] == 0,
    #     x[1, (9, 12)] - x[1, (12, 15)] == 0,
    #     x[1, (10, 13)] == 0,
    #     0 == 0,
    #     x[1, (3, 15)] + x[1, (6, 15)] + x[1, (8, 15)] + x[1, (12, 15)] == 1,
    # ]
    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    # old and new path constraints
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, bundles)
    oldPaths = [[supp1FromDel2, plantFromDel0], [supp2FromDel1, plantFromDel0]]
    newPaths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]
    ]
    OFOND.add_old_new_path_constraints!(model, [bundle1, bundle2], oldPaths, newPaths)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 5
    @test length(model[:oldPaths]) == 2
    @test length(model[:newPaths]) == 3
    # println(model[:oldPaths])
    # println(model[:newPaths])
    # TODO : Like classical paths constraints, find way to verify that 
    # Old paths constraints :
    # oldPaths[(1, (3, 15))] : -x[1,(3, 15)] - z[1] == -1
    # oldPaths[(2, (6, 15))] : -x[2,(6, 15)] - z[2] == -1
    # New paths constraints :
    # newPaths[(1, (3, 8))] : -x[1,(3, 8)] + z[1] == 0
    # newPaths[(1, (8, 15))] : -x[1,(8, 15)] + z[1] == 0
    # newPaths[(2, (6, 15))] : -x[2,(6, 15)] + z[2] == 0
end

xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
portStep1 = TSGraph.hashToIdx[hash(1, port_l.hash)]
portFromDel0 = TTGraph.hashToIdx[hash(0, port_l.hash)]

@testset "Packing constraints" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    # packing expr initialization : with empty solution and with non-empty solution with possibly different group of bundles
    I, J, V = findnz(OFOND.init_packing_expr(model, TSGraph, sol))
    @test I == [12, 9, 10, 11, 12, 16, 9, 13, 10, 14, 11, 15]
    @test J == [13, 14, 15, 16, 17, 17, 18, 18, 19, 19, 20, 20]
    @test V[1] == AffExpr(0, model[:tau][(12, 13)] => -50)
    @test V[5] == AffExpr(0, model[:tau][(12, 17)] => -50)
    # adding commodity in solution
    push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(25, 25, [commodity1, commodity2]))
    expr_mat = OFOND.init_packing_expr(model, TSGraph, sol)
    @test expr_mat[xdockStep4, plantStep1] ==
        AffExpr(25, model[:tau][(xdockStep4, plantStep1)] => -50)
    @test expr_mat[xdockStep1, plantStep2] ==
        AffExpr(0, model[:tau][(xdockStep1, plantStep2)] => -50)
    # completing expr : for different bundles checking the correct x variables are taken
    OFOND.complete_packing_expr!(model, expr_mat, instance, [bundle1])
    @test expr_mat[xdockStep4, plantStep1] == AffExpr(
        25,
        model[:tau][(xdockStep4, plantStep1)] => -50,
        model[:x][1, (xdockFromDel1, plantFromDel0)] => 20,
    )
    @test expr_mat[xdockStep4, portStep1] == AffExpr(
        0,
        model[:tau][(xdockStep4, portStep1)] => -50,
        model[:x][1, (xdockFromDel1, portFromDel0)] => 20,
    )
    @test expr_mat[xdockStep1, plantStep2] ==
        AffExpr(0, model[:tau][(xdockStep1, plantStep2)] => -50)
    # add packing constraints with a dummy model
    OFOND.add_packing_constraints!(model, instance, bundles, sol)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 12
    @test length(model[:packing]) == 12
    # Like path constraints, find way to verify that 
    # println(model[:packing])
    # packing[(9, 14)] : 25 x[3,(8, 11)] - 50 tau[(9, 14)] <= 0
    # packing[(10, 15)] : 25 x[3,(10, 13)] - 50 tau[(10, 15)] <= 0
    # packing[(11, 16)] : 20 x[1,(9, 12)] + 25 x[3,(9, 12)] + 25 x[3,(10, 13)] - 50 tau[(11, 16)] <= 0
    # packing[(12, 13)] : 20 x[1,(8, 11)] + 30 x[2,(8, 11)] + 25 x[3,(8, 11)] + 25 x[3,(9, 12)] - 50 tau[(12, 13)] <= 0
    # packing[(9, 18)] : 25 x[3,(8, 15)] - 50 tau[(9, 18)] <= 0
    # packing[(10, 19)] : -50 tau[(10, 19)] <= 0
    # packing[(11, 20)] : -50 tau[(11, 20)] <= 0
    # packing[(12, 17)] : 20 x[1,(8, 15)] + 30 x[2,(8, 15)] + 25 x[3,(8, 15)] - 50 tau[(12, 17)] <= -25
    # packing[(13, 18)] : 25 x[3,(12, 15)] - 50 tau[(13, 18)] <= 0
    # packing[(14, 19)] : -50 tau[(14, 19)] <= 0
    # packing[(15, 20)] : -50 tau[(15, 20)] <= 0
    # packing[(16, 17)] : 20 x[1,(12, 15)] + 30 x[2,(12, 15)] + 25 x[3,(12, 15)] - 50 tau[(16, 17)] <= 0
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
    sol.bundlePaths[1] = [supp1FromDel2, plantFromDel0]
    sol.bundlePaths[2] = [supp2FromDel1, plantFromDel0]
    sol.bundlePaths[3] = [supp1FromDel2, plantFromDel0]
    # adding attract or reduce constraints 
    OFOND.add_constraints!(
        model, :attract, instance, sol, [bundle1, bundle3], xdockFromDel1, plantFromDel0
    )
    @test num_constraints(model; count_variable_in_set_constraints=false) == 48
    @test length(model[:packing]) == 12
    @test length(model[:path][1]) == 15
    # @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    @test length(model[:oldPaths]) == 2
    @test length(model[:newPaths]) == 4
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
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]

xdockStep2 = TSGraph.hashToIdx[hash(2, xdock.hash)]
xdockStep3 = TSGraph.hashToIdx[hash(3, xdock.hash)]
plantStep3 = TSGraph.hashToIdx[hash(3, plant.hash)]
plantStep4 = TSGraph.hashToIdx[hash(4, plant.hash)]
portStep2 = TSGraph.hashToIdx[hash(2, port_l.hash)]
portStep3 = TSGraph.hashToIdx[hash(3, port_l.hash)]
portStep4 = TSGraph.hashToIdx[hash(4, port_l.hash)]

@testset "Add objective" begin
    # milp_travel_time_arc_cost for different groups of bundles
    I, J, V = findnz(OFOND.milp_travel_time_arc_cost(TTGraph, TSGraph, [bundle1]))
    @test I == fill(1, 3)
    @test collect(edges(TTGraph.graph))[J] == [
        Edge(supp1FromDel2, xdockFromDel1),
        Edge(supp1FromDel2, plantFromDel0),
        collect(edges(TTGraph.graph))[end],
    ]
    @test all(V .≈ [6.60401, 30.00401, 1e-5])

    I, J, V = findnz(OFOND.milp_travel_time_arc_cost(TTGraph, TSGraph, [bundle1, bundle2]))
    @test I == vcat(fill(1, 2), fill(2, 3))
    @test collect(edges(TTGraph.graph))[J] == [
        Edge(supp1FromDel2, xdockFromDel1),
        Edge(supp1FromDel2, plantFromDel0),
        Edge(supp2FromDel1, xdockFromDel0),
        Edge(supp2FromDel1, plantFromDel0),
        collect(edges(TTGraph.graph))[end],
    ]
    @test all(V .≈ [6.60401, 30.00401, 9.40601, 24.00601, 1e-5])
    # add objective function for a dummy model with correct variables
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, [bundle1])
    instance.timeSpaceGraph.currentCost[12, 17] = 1e-5
    instance.timeSpaceGraph.currentCost[16, 17] = 1e-5
    OFOND.add_objective!(model, instance, [bundle1])
    @test objective_sense(model) == MIN_SENSE
    x, tau = model[:x], model[:tau]
    objExprTest = AffExpr(0)
    arcKeys = [
        (xdockStep1, portStep2),
        (xdockStep2, portStep3),
        (xdockStep3, portStep4),
        (xdockStep4, portStep1),
        (xdockStep1, plantStep2),
        (xdockStep2, plantStep3),
        (xdockStep3, plantStep4),
        (xdockStep4, plantStep1),
        (portStep1, plantStep2),
        (portStep2, plantStep3),
        (portStep3, plantStep4),
        (portStep4, plantStep1),
    ]
    for key in arcKeys
        add_to_expression!(objExprTest, tau[key], 1e-5)
    end
    add_to_expression!(objExprTest, x[1, (supp1FromDel2, xdockFromDel1)], 5.004013999999999)
    add_to_expression!(
        objExprTest, x[1, (supp1FromDel2, plantFromDel0)], 10.004019999999999
    )
    add_to_expression!(objExprTest, x[1, (portFromDel1, plantFromDel0)], 1e-5)
    @test objective_function(model) == objExprTest
end

@testset "Extracting paths" begin
    # extract_arcs_from_vector for different vectors
    bundleArcVect = zeros(ne(TTGraph.graph))
    bundleArcVect[[2, 5]] .= 1.0
    @test OFOND.extract_arcs_from_vector(bundleArcVect, TTGraph) ==
        [Edge(2, 7), Edge(3, 15)]
    bundleArcVect = zeros(ne(TTGraph.graph))
    bundleArcVect[[4, 12]] .= 0.9
    @test OFOND.extract_arcs_from_vector(bundleArcVect, TTGraph) ==
        [Edge(3, 8), Edge(8, 15)]
    # get_path_from_arcs for different group of edges
    pathArcs = [Edge(8, 15), Edge(3, 4), Edge(4, 8)]
    @test OFOND.get_path_from_arcs(bundle1, TTGraph, pathArcs) == [3, 4, 8, 15]
    pathArcs = [Edge(8, 15), Edge(6, 3), Edge(3, 12), Edge(12, 8)]
    @test OFOND.get_path_from_arcs(bundle2, TTGraph, pathArcs) == [6, 3, 12, 8, 15]
    # get_paths for a dummy model 
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, bundles)
    # no constraints, dummy objective to get the path I want, solve and retrieve path
    x = model[:x]
    @constraint(
        model,
        x[1, (supp1FromDel2, xdockFromDel1)] +
        x[1, (xdockFromDel1, plantFromDel0)] +
        x[2, (supp2FromDel1, plantFromDel0)] +
        x[3, (supp1FromDel3, supp1FromDel2)] +
        x[3, (supp1FromDel2, plantFromDel0)] == 5
    )
    @objective(model, Max, sum(-1 .* x))
    set_silent(model)
    optimize!(model)
    @test OFOND.get_paths(model, TTGraph, bundles) == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp1FromDel2, plantFromDel0],
    ]
end

@testset "Plant and Arc selection" begin
    # select_random_plant
    # select_common_arc
end

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
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    # add variables for single_plant 
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
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
    OFOND.add_variables!(model, :attract, instance, relaxedSol)
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
    I, J, V = findnz(OFOND.get_e_matrix(:single_plant, [1, 2, 3], TTGraph, -1, -1))
    @test I == [1, 3, 2, 1, 2, 3]
    @test J == vcat(allTTIdxs[[3, 4, 6]], fill(allTTIdxs[end], 3))
    @test V == [-1, -1, -1, 1, 1, 1]
    e_mat = @test_warn "two_shared_node : src or dst is unknown" OFOND.get_e_matrix(
        :two_shared_node, [1, 2, 3], TTGraph, -1, -1
    )
    I, J, V = findnz(e_mat)
    @test I == [1, 3, 2, 1, 2, 3]
    @test J == vcat(allTTIdxs[[3, 4, 6]], fill(allTTIdxs[end], 3))
    @test V == [-1, -1, -1, 1, 1, 1]
    I, J, V = findnz(
        OFOND.get_e_matrix(
            :two_shared_node, [1, 2, 3], TTGraph, xdockFromDel1, plantFromDel0
        ),
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
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
    e_mat = OFOND.get_e_matrix(:single_plant, [1, 2, 3], TTGraph, -1, -1)
    # common path constraints 
    OFOND.add_path_constraints!(model, TTGraph, [1, 2, 3], e_mat)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 45
    @test length(model[:path][1]) == 15
    # println(model[:path][1])
    x = model[:x]
    #     x[1, (2, 1)] == 0,
    path11 = constraint_object(model[:path][1][1])
    @test path11.func == AffExpr(0, x[1, (2, 1)] => 1)
    @test path11.set == MOI.EqualTo(0.0)
    #     -x[1, (2, 1)] - x[1, (2, 7)] + x[1, (3, 2)] == 0,
    path12 = constraint_object(model[:path][1][2])
    @test path12.func ==
        AffExpr(0, x[1, (2, 1)] => -1, x[1, (2, 7)] => -1, x[1, (3, 2)] => 1)
    @test path12.set == MOI.EqualTo(0.0)
    #     -x[1, (3, 2)] - x[1, (3, 8)] - x[1, (3, 15)] + x[1, (4, 3)] == -1,
    path13 = constraint_object(model[:path][1][3])
    @test path13.func == AffExpr(
        0, x[1, (3, 2)] => -1, x[1, (3, 8)] => -1, x[1, (3, 15)] => -1, x[1, (4, 3)] => 1
    )
    @test path13.set == MOI.EqualTo(-1.0)
    #     -x[1, (4, 3)] - x[1, (4, 9)] == 0,
    path14 = constraint_object(model[:path][1][4])
    @test path14.func == AffExpr(0, x[1, (4, 3)] => -1, x[1, (4, 9)] => -1)
    @test path14.set == MOI.EqualTo(0.0)
    #     x[1, (6, 5)] == 0,
    path15 = constraint_object(model[:path][1][5])
    @test path15.func == AffExpr(0, x[1, (6, 5)] => 1)
    @test path15.set == MOI.EqualTo(0.0)
    #     -x[1, (6, 5)] - x[1, (6, 7)] - x[1, (6, 15)] == 0,
    path16 = constraint_object(model[:path][1][6])
    @test path16.func ==
        AffExpr(0, x[1, (6, 5)] => -1, x[1, (6, 7)] => -1, x[1, (6, 15)] => -1)
    @test path16.set == MOI.EqualTo(0.0)
    #     x[1, (2, 7)] + x[1, (6, 7)]  == 0,
    path17 = constraint_object(model[:path][1][7])
    @test path17.func == AffExpr(0, x[1, (2, 7)] => 1, x[1, (6, 7)] => 1)
    @test path17.set == MOI.EqualTo(0.0)
    #     x[1, (3, 8)] - x[1, (8, 11)] - x[1, (8, 15)] == 0,
    path18 = constraint_object(model[:path][1][8])
    @test path18.func ==
        AffExpr(0, x[1, (3, 8)] => 1, x[1, (8, 11)] => -1, x[1, (8, 15)] => -1)
    @test path18.set == MOI.EqualTo(0.0)
    #     x[1, (4, 9)] - x[1, (9, 12)] == 0,
    path19 = constraint_object(model[:path][1][9])
    @test path19.func == AffExpr(0, x[1, (4, 9)] => 1, x[1, (9, 12)] => -1)
    @test path19.set == MOI.EqualTo(0.0)
    #     -x[1, (10, 13)] == 0,
    path20 = constraint_object(model[:path][1][10])
    @test path20.func == AffExpr(0, x[1, (10, 13)] => -1)
    @test path20.set == MOI.EqualTo(0.0)
    #     x[1, (8, 11)] == 0,
    path21 = constraint_object(model[:path][1][11])
    @test path21.func == AffExpr(0, x[1, (8, 11)] => 1)
    @test path21.set == MOI.EqualTo(0.0)
    #     x[1, (9, 12)] - x[1, (12, 15)] == 0,
    path22 = constraint_object(model[:path][1][12])
    @test path22.func == AffExpr(0, x[1, (9, 12)] => 1, x[1, (12, 15)] => -1)
    @test path22.set == MOI.EqualTo(0.0)
    #     x[1, (10, 13)] == 0,
    path23 = constraint_object(model[:path][1][13])
    @test path23.func == AffExpr(0, x[1, (10, 13)] => 1)
    @test path23.set == MOI.EqualTo(0.0)
    #     0 == 0,
    path24 = constraint_object(model[:path][1][14])
    @test path24.func == AffExpr(0)
    @test path24.set == MOI.EqualTo(0.0)
    #     x[1, (3, 15)] + x[1, (6, 15)] + x[1, (8, 15)] + x[1, (12, 15)] == 1,
    path25 = constraint_object(model[:path][1][15])
    @test path25.func == AffExpr(
        0, x[1, (3, 15)] => 1, x[1, (6, 15)] => 1, x[1, (8, 15)] => 1, x[1, (12, 15)] => 1
    )
    @test path25.set == MOI.EqualTo(1.0)

    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    # old and new path constraints
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, relaxedSol)
    oldPaths = [[supp1FromDel2, plantFromDel0], [supp2FromDel1, plantFromDel0]]
    newPaths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0], [supp2FromDel1, plantFromDel0]
    ]
    OFOND.add_old_new_path_constraints!(model, [bundle1, bundle2], oldPaths, newPaths)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 4
    @test length(model[:oldPaths]) == 1
    @test length(model[:newPaths]) == 2
    @test length(model[:forceArcs]) == 1
    # println(model[:oldPaths])
    # println(model[:newPaths])
    x, z = model[:x], model[:z]
    # Old paths constraints :
    # oldPaths[(1, (3, 15))] : -x[1,(3, 15)] - z[1] == -1
    oldPath11 = constraint_object(model[:oldPaths][(1, (3, 15))])
    @test oldPath11.func == AffExpr(0, x[1, (3, 15)] => -1, z[1] => -1)
    @test oldPath11.set == MOI.EqualTo(-1.0)
    # New paths constraints :
    # newPaths[(1, (3, 8))] : -x[1,(3, 8)] + z[1] == 0
    newPath11 = constraint_object(model[:newPaths][(1, (3, 8))])
    @test newPath11.func == AffExpr(0, x[1, (3, 8)] => -1, z[1] => 1)
    @test newPath11.set == MOI.EqualTo(0.0)
    # newPaths[(1, (8, 15))] : -x[1,(8, 15)] + z[1] == 0
    newPath12 = constraint_object(model[:newPaths][(1, (8, 15))])
    @test newPath12.func == AffExpr(0, x[1, (8, 15)] => -1, z[1] => 1)
    @test newPath12.set == MOI.EqualTo(0.0)
    # Force arc constraints :
    # forceArcs[(2, (6, 15))] : x[2,(6, 15)] == 1
    oldPath12 = constraint_object(model[:forceArcs][(2, (6, 15))])
    @test oldPath12.func == AffExpr(0, x[2, (6, 15)] => 1)
    @test oldPath12.set == MOI.EqualTo(1.0)
end

xdockStep1 = TSGraph.hashToIdx[hash(1, xdock.hash)]
plantStep2 = TSGraph.hashToIdx[hash(2, plant.hash)]
portStep1 = TSGraph.hashToIdx[hash(1, port_l.hash)]
portFromDel0 = TTGraph.hashToIdx[hash(0, port_l.hash)]

@testset "Packing constraints" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
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
    tau, x = model[:tau], model[:x]
    @testset "packing less than tests" for (src, dst) in TSGraph.commonArcs
        con = model[:packing][(src, dst)]
        if (src, dst) == (12, 17)
            @test constraint_object(con).set == MOI.LessThan(-25.0)
        else
            @test constraint_object(con).set == MOI.LessThan(0.0)
        end
    end
    # println(model[:packing])
    # packing[(9, 14)] : 25 x[3,(8, 11)] - 50 tau[(9, 14)] <= 0
    packing914 = constraint_object(model[:packing][(9, 14)])
    @test packing914.func == AffExpr(0, x[3, (8, 11)] => 25, tau[(9, 14)] => -50)
    # packing[(10, 15)] : 20 x[1,(10, 13)] + 25 x[3,(10, 13)] - 50 tau[(10, 15)] <= 0
    packing1015 = constraint_object(model[:packing][(10, 15)])
    @test packing1015.func ==
        AffExpr(0, x[1, (10, 13)] => 20, x[3, (10, 13)] => 25, tau[(10, 15)] => -50)
    #   AffExpr(0, x[3, (10, 13)] => 25, tau[(10, 15)] => -50)
    # packing[(11, 16)] : 20 x[1,(9, 12)] + 25 x[3,(9, 12)] + 25 x[3,(10, 13)] - 50 tau[(11, 16)] <= 0
    packing1116 = constraint_object(model[:packing][(11, 16)])
    @test packing1116.func == AffExpr(
        0,
        x[1, (9, 12)] => 20,
        x[3, (9, 12)] => 25,
        x[3, (10, 13)] => 25,
        tau[(11, 16)] => -50,
    )
    # packing[(12, 13)] : 20 x[1,(8, 11)] + 30 x[2,(8, 11)] + 25 x[3,(8, 11)] + 25 x[3,(9, 12)] - 50 tau[(12, 13)] <= 0
    packing1213 = constraint_object(model[:packing][(12, 13)])
    @test packing1213.func == AffExpr(
        0,
        x[1, (8, 11)] => 20,
        x[2, (8, 11)] => 30,
        x[3, (8, 11)] => 25,
        x[3, (9, 12)] => 25,
        tau[(12, 13)] => -50,
    )
    # packing[(9, 18)] : 25 x[3,(8, 15)] - 50 tau[(9, 18)] <= 0
    packing918 = constraint_object(model[:packing][(9, 18)])
    @test packing918.func == AffExpr(0, x[3, (8, 15)] => 25, tau[(9, 18)] => -50)
    # packing[(10, 19)] : -50 tau[(10, 19)] <= 0
    packing1019 = constraint_object(model[:packing][(10, 19)])
    @test packing1019.func == AffExpr(0, tau[(10, 19)] => -50)
    # packing[(11, 20)] : -50 tau[(11, 20)] <= 0
    packing1120 = constraint_object(model[:packing][(11, 20)])
    @test packing1120.func == AffExpr(0, tau[(11, 20)] => -50)
    # packing[(12, 17)] : 20 x[1,(8, 15)] + 30 x[2,(8, 15)] + 25 x[3,(8, 15)] - 50 tau[(12, 17)] <= -25
    packing1217 = constraint_object(model[:packing][(12, 17)])
    @test packing1217.func == AffExpr(
        0,
        x[1, (8, 15)] => 20,
        x[2, (8, 15)] => 30,
        x[3, (8, 15)] => 25,
        tau[(12, 17)] => -50,
    )
    # packing[(13, 18)] : 25 x[3,(12, 15)] - 50 tau[(13, 18)] <= 0
    packing1318 = constraint_object(model[:packing][(13, 18)])
    @test packing1318.func == AffExpr(0, x[3, (12, 15)] => 25, tau[(13, 18)] => -50)
    # packing[(14, 19)] : -50 tau[(14, 19)] <= 0
    packing1419 = constraint_object(model[:packing][(14, 19)])
    @test packing1419.func == AffExpr(0, tau[(14, 19)] => -50)
    # packing[(15, 20)] : -50 tau[(15, 20)] <= 0
    packing1520 = constraint_object(model[:packing][(15, 20)])
    @test packing1520.func == AffExpr(0, tau[(15, 20)] => -50)
    # packing[(16, 17)] : 20 x[1,(12, 15)] + 30 x[2,(12, 15)] + 25 x[3,(12, 15)] - 50 tau[(16, 17)] <= 0
    packing1617 = constraint_object(model[:packing][(16, 17)])
    @test packing1617.func == AffExpr(
        0,
        x[1, (12, 15)] => 20,
        x[2, (12, 15)] => 30,
        x[3, (12, 15)] => 25,
        tau[(16, 17)] => -50,
    )
end

@testset "Adding all constraints" begin
    sol = OFOND.Solution(TTGraph, TSGraph, bundles)
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    oldPaths = sol.bundlePaths
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
    # adding base constraints
    OFOND.add_constraints!(model, :single_plant, instance, sol, relaxedSol)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 57
    @test length(model[:packing]) == 12
    @test length(model[:path][1]) == 15
    @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15

    sol.bundlePaths[1] = [supp1FromDel2, plantFromDel0]
    sol.bundlePaths[2] = [supp2FromDel1, plantFromDel0]
    sol.bundlePaths[3] = [supp1FromDel2, plantFromDel0]
    relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1, bundle3])
    model = Model(HiGHS.Optimizer)
    OFOND.add_variables!(model, :attract, instance, relaxedSol)
    # adding attract or reduce constraints 
    OFOND.add_constraints!(
        model, :attract, instance, sol, relaxedSol, xdockFromDel1, plantFromDel0
    )
    @test num_constraints(model; count_variable_in_set_constraints=false) == 48
    @test length(model[:packing]) == 12
    @test length(model[:path][1]) == 15
    # @test length(model[:path][2]) == 15
    @test length(model[:path][3]) == 15
    @test length(model[:oldPaths]) == 2
    @test length(model[:newPaths]) == 4
    @test length(model[:forceArcs]) == 0
end

@testset "Cost filters" begin
    # has_arc_milp_cost with different arcs
    @test OFOND.has_arc_milp_cost(TTGraph, supp1FromDel2, plantFromDel0, [supp1FromDel2])
    @test !OFOND.has_arc_milp_cost(TTGraph, supp1FromDel2, plantFromDel0, [supp2FromDel1])
    @test OFOND.has_arc_milp_cost(TTGraph, xdockFromDel1, plantFromDel0, [supp1FromDel2])
end

xdockFromDel3 = TTGraph.hashToIdx[hash(3, xdock.hash)]
supp1FromDel0 = TTGraph.hashToIdx[hash(0, supplier1.hash)]
supp2FromDel0 = TTGraph.hashToIdx[hash(0, supplier2.hash)]
supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel2 = TTGraph.hashToIdx[hash(2, port_l.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
xdockFromDel0 = TTGraph.hashToIdx[hash(0, xdock.hash)]

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
    @test I == fill(1, 10)
    @test collect(edges(TTGraph.graph))[J] == [
        Edge(supp1FromDel1, supp1FromDel0),
        Edge(supp1FromDel1, xdockFromDel0),
        Edge(supp1FromDel2, supp1FromDel1),
        Edge(supp1FromDel2, xdockFromDel1),
        Edge(supp1FromDel2, plantFromDel0),
        Edge(xdockFromDel1, portFromDel0),
        Edge(xdockFromDel1, plantFromDel0),
        Edge(xdockFromDel2, portFromDel1),
        Edge(xdockFromDel3, portFromDel2),
        collect(edges(TTGraph.graph))[end],
    ]
    testV = [1.0e-5, 6.604, 1.0e-5, 6.604, 30.004, 5.0, 5.004, 5.0, 5.0, 5.004]
    @testset "test V values $i" for i in eachindex(V)
        @test V[i] ≈ testV[i]
    end

    I, J, V = findnz(OFOND.milp_travel_time_arc_cost(TTGraph, TSGraph, [bundle1, bundle2]))
    @test I == [1, 1, 1, 1, 1, 2, 2, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2]
    @test collect(edges(TTGraph.graph))[J] == [
        Edge(supp1FromDel1, supp1FromDel0),
        Edge(supp1FromDel1, xdockFromDel0),
        Edge(supp1FromDel2, supp1FromDel1),
        Edge(supp1FromDel2, xdockFromDel1),
        Edge(supp1FromDel2, plantFromDel0),
        Edge(supp2FromDel1, supp2FromDel0),
        Edge(supp2FromDel1, xdockFromDel0),
        Edge(supp2FromDel1, plantFromDel0),
        Edge(xdockFromDel1, portFromDel0),
        Edge(xdockFromDel1, portFromDel0),
        Edge(xdockFromDel1, plantFromDel0),
        Edge(xdockFromDel1, plantFromDel0),
        Edge(xdockFromDel2, portFromDel1),
        Edge(xdockFromDel2, portFromDel1),
        Edge(xdockFromDel3, portFromDel2),
        Edge(xdockFromDel3, portFromDel2),
        collect(edges(TTGraph.graph))[end],
        collect(edges(TTGraph.graph))[end],
    ]
    testV = vcat(
        [1.0e-5, 6.604, 1.0e-5, 6.604, 30.004, 1.0e-5, 9.406, 24.006, 5.0, 7.0, 5.004],
        [7.006, 5.0, 7.0, 5.0, 7.0, 5.004, 7.006],
    )
    @testset "test value $i" for i in eachindex(V)
        @test V[i] ≈ testV[i]
    end

    # add objective function for a dummy model with correct variables
    model = Model(HiGHS.Optimizer)
    relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1])
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
    instance.timeSpaceGraph.currentCost[12, 17] = 1e-5
    instance.timeSpaceGraph.currentCost[16, 17] = 1e-5
    OFOND.add_objective!(model, instance, relaxedSol)
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
    add_to_expression!(objExprTest, x[1, (supp1FromDel1, supp1FromDel0)], 1e-5)
    add_to_expression!(objExprTest, x[1, (supp1FromDel1, xdockFromDel0)], 5.004003999999999)
    add_to_expression!(objExprTest, x[1, (supp1FromDel2, supp1FromDel1)], 1e-5)
    add_to_expression!(objExprTest, x[1, (supp1FromDel2, xdockFromDel1)], 5.004003999999999)
    add_to_expression!(objExprTest, x[1, (supp1FromDel2, plantFromDel0)], 10.00401)
    add_to_expression!(objExprTest, x[1, (xdockFromDel1, portFromDel0)], 5.0)
    add_to_expression!(objExprTest, x[1, (xdockFromDel1, plantFromDel0)], 5.004)
    add_to_expression!(objExprTest, x[1, (xdockFromDel2, portFromDel1)], 5.0)
    add_to_expression!(objExprTest, x[1, (xdockFromDel3, portFromDel2)], 5.0)
    add_to_expression!(objExprTest, x[1, (portFromDel1, plantFromDel0)], 5.004)
    @test objective_function(model) == objExprTest
end

supp1FromDel3 = TTGraph.hashToIdx[hash(3, supplier1.hash)]

@testset "Complete paths" begin
    @test OFOND.get_shortcut_part(TTGraph, 1, 3) == Int[]
    @test OFOND.get_shortcut_part(TTGraph, 1, 2) == [3]
    @test OFOND.get_shortcut_part(TTGraph, 3, 2) == [4, 3]
    @test OFOND.get_shortcut_part(TTGraph, 2, 5) == [6]
end

@testset "Warm start" begin
    model = Model(HiGHS.Optimizer)
    sol.bundlePaths[1] = Int[]
    relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1])
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
    # Check no start value is here
    portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]
    @test !has_start_value(model[:x][1, (supp1FromDel2, plantFromDel0)])
    @test !has_start_value(model[:x][1, (supp1FromDel2, xdockFromDel1)])
    @test !has_start_value(model[:tau][(portStep4, plantStep1)])
    # Check warm without paths doesn't change anything for paths but not for tau
    OFOND.warm_start_milp!(model, :single_plant, instance, relaxedSol)
    @test !has_start_value(model[:x][1, (supp1FromDel2, plantFromDel0)])
    @test !has_start_value(model[:x][1, (supp1FromDel2, xdockFromDel1)])
    @test start_value(model[:tau][(portStep4, plantStep1)]) == 0.0
    # Check some start value are here for the path given
    sol.bundlePaths[1] = [supp1FromDel2, plantFromDel0]
    relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1])
    OFOND.warm_start_milp!(model, :single_plant, instance, relaxedSol)
    @test !has_start_value(model[:x][1, (supp1FromDel3, supp1FromDel2)])
    @test start_value(model[:x][1, (supp1FromDel2, plantFromDel0)]) == 1.0
    @test !has_start_value(model[:x][1, (supp1FromDel2, xdockFromDel1)])
    # Check all tau start at zero unless for portStep4, plantStep1 that start at one ?
    @testset "tau start value" for (src, dst) in TSGraph.commonArcs
        @test start_value(model[:tau][(src, dst)]) == 0.0
    end
    # Check some start value are here for the path given
    # sol.bundlePaths[1] = [xdockFromDel1, plantFromDel0]
    # relaxedSol = OFOND.RelaxedSolution(sol, instance, [bundle1])
    # OFOND.warm_start_milp!(model, :two_node, instance, relaxedSol)
    # @test !has_start_value(model[:x][1, (supp1FromDel3, supp1FromDel2)])
    # @test start_value(model[:x][1, (xdockFromDel1, plantFromDel0)]) == 1.0
    # @test !has_start_value(model[:x][1, (supp1FromDel2, xdockFromDel1)])
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
    pathArcs = [Edge(8, 11), Edge(5, 3), Edge(3, 12), Edge(12, 8)]
    @test OFOND.get_path_from_arcs(bundle2, TTGraph, pathArcs) == [5, 3, 12, 8, 11]
    # get_paths for a dummy model 
    model = Model(HiGHS.Optimizer)
    relaxedSol = OFOND.RelaxedSolution(sol, instance, bundles)
    OFOND.add_variables!(model, :single_plant, instance, relaxedSol)
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
    @test OFOND.get_paths(model, instance, relaxedSol) == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp1FromDel2, plantFromDel0],
    ]
end

@testset "Plant and Arc selection" begin
    # select_random_plant
    plantsSelected = [OFOND.select_random_plant(instance) for _ in 1:10]
    @test all(p -> p == plantFromDel0, plantsSelected)
    # select_common_arc
    arcsSelected = [OFOND.select_common_arc(instance) for _ in 1:50]
    @test all(
        a -> TTGraph.networkArcs[a[1], a[2]].type in OFOND.COMMON_ARC_TYPES, arcsSelected
    )
end

bundles[3] = bundle3
instance.bundles[3] = bundles[3]
paths = [
    [supp1FromDel2, xdockFromDel1, plantFromDel0],
    [supp2FromDel1, plantFromDel0],
    [supp1FromDel2, plantFromDel0],
]
sol = OFOND.Solution(instance)
OFOND.update_solution!(sol, instance, bundles, paths)

@testset "Nodes and Bundles selection" begin
    # bundle in pertBunIdxs
    @test !OFOND.is_bundle_attract_candidate(
        bundle1, [1], TTGraph, xdockFromDel1, plantFromDel0
    )
    # bundle don't have path to first node
    xdockFromDel3 = TTGraph.hashToIdx[hash(3, xdock.hash)]
    @test !OFOND.is_bundle_attract_candidate(
        bundle1, [1], TTGraph, xdockFromDel3, plantFromDel0
    )
    # bundle don't have path from second node
    @test !OFOND.is_bundle_attract_candidate(
        bundle1, [1], TTGraph, xdockFromDel1, xdockFromDel3
    )
    # bundle not of any of those above
    @test OFOND.is_bundle_attract_candidate(
        bundle1, [2, 3], TTGraph, xdockFromDel1, plantFromDel0
    )

    src, dst, bunIdxs = OFOND.get_neighborhood_node_and_bundles(
        :single_plant, instance, sol
    )
    @test src == -1
    @test dst == -1
    @test bunIdxs == [1, 2, 3]
    src, dst, bunIdxs = OFOND.get_neighborhood_node_and_bundles(
        :two_shared_node, instance, sol
    )
    @test src == xdockFromDel1
    @test dst == plantFromDel0
    @test bunIdxs == [1]
    src, dst, bunIdxs = OFOND.get_neighborhood_node_and_bundles(:attract, instance, sol)
    while (src, dst) != (xdockFromDel1, plantFromDel0)
        src, dst, bunIdxs = OFOND.get_neighborhood_node_and_bundles(:attract, instance, sol)
    end
    @test src == xdockFromDel1
    @test dst == plantFromDel0
    @test bunIdxs == [3]
    src, dst, bunIdxs = OFOND.get_neighborhood_node_and_bundles(:reduce, instance, sol)
    @test src == xdockFromDel1
    @test dst == plantFromDel0
    @test bunIdxs == [1]
end

@testset "Paths to update" begin
    @test OFOND.get_lns_paths_to_update(:single_plant, sol, [bundle1], -1, -1) ==
        [[supp1FromDel2, xdockFromDel1, plantFromDel0]]
    @test OFOND.get_lns_paths_to_update(
        :two_shared_node, sol, [bundle1], xdockFromDel1, plantFromDel0
    ) == [[xdockFromDel1, plantFromDel0]]
    @test OFOND.get_lns_paths_to_update(
        :attract, sol, [bundle1], xdockFromDel1, plantFromDel0
    ) == [[supp1FromDel2, xdockFromDel1, plantFromDel0]]
    @test OFOND.get_lns_paths_to_update(:reduce, sol, [bundle2, bundle3], -1, -1) ==
        [[supp2FromDel1, plantFromDel0], [supp1FromDel2, plantFromDel0]]
end
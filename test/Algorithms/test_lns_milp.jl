sol = OFOND.Solution(TTGraph, TSGraph, bundles)

supp1FromDel2 = TTGraph.hashToIdx[hash(2, supplier1.hash)]
xdockFromDel1 = TTGraph.hashToIdx[hash(1, xdock.hash)]
plantFromDel0 = TTGraph.hashToIdx[hash(0, plant.hash)]
supp2FromDel1 = TTGraph.hashToIdx[hash(1, supplier2.hash)]
supp3FromDel2 = TTGraph.hashToIdx[hash(2, supplier3.hash)]

OFOND.update_solution!(
    sol, instance, bundle11, [supp1FromDel2, xdockFromDel1, plantFromDel0]
)
OFOND.update_solution!(sol, instance, bundle22, [supp2FromDel1, plantFromDel0])
OFOND.update_solution!(
    sol, instance, bundle33, [supp3FromDel2, xdockFromDel1, plantFromDel0]
)

xdockStep4 = TSGraph.hashToIdx[hash(4, xdock.hash)]
plantStep1 = TSGraph.hashToIdx[hash(1, plant.hash)]

push!(sol.bins[xdockStep4, plantStep1], OFOND.Bin(25, 25, [commodity1, commodity2]))

@testset "Add variables" begin
    # add variables for single_plant 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    # check the variables are correct : x and tau
    # println(model[:x])
    # println(model[:tau])
    @test num_variables(model) == 30
    # testing number and indexing of path variables for bundle 1
    @test length(model[:x][1, :]) == 7 == length(TTGraph.bundleArcs[1])
    @testset "x1" for (src, dst) in TTGraph.bundleArcs[1]
        @test is_binary(model[:x][1, (src, dst)])
    end
    # testing number and indexing of path variables for bundle 2
    @test length(model[:x][2, :]) == 4 == length(TTGraph.bundleArcs[2])
    @testset "x2" for (src, dst) in TTGraph.bundleArcs[2]
        @test is_binary(model[:x][2, (src, dst)])
    end
    # testing number and indexing of path variables for bundle 3
    @test length(model[:x][3, :]) == 7 == length(TTGraph.bundleArcs[3])
    @testset "x3" for (src, dst) in TTGraph.bundleArcs[3]
        @test is_binary(model[:x][3, (src, dst)])
    end
    # testing number and indexing of tau variables
    @test length(model[:tau]) == 12 == length(TSGraph.commonArcs)
    @testset "tau" for (src, dst) in TSGraph.commonArcs
        @test is_integer(model[:tau][(src, dst)])
    end

    # add variables for attract 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    OFOND.add_variables!(model, instance, perturbation)
    # check the variables are correct : z and tau
    # println(model[:z])
    # println(model[:tau])
    @test num_variables(model) == 15
    # testing number and indexing of path variables
    @test length(model[:z]) == 3 == length(bundles)
    @testset "z" for idx in 1:3
        @test is_binary(model[:z][idx])
    end
    # testing number and indexing of tau variables
    @test length(model[:tau]) == 12 == length(TSGraph.commonArcs)
    @testset "tau" for (src, dst) in TSGraph.commonArcs
        @test is_integer(model[:tau][(src, dst)])
    end
end

@testset "Add path constraints" begin
    # dummy model with the correct variables
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    # path constraints for an arc flow neighborhood 
    OFOND.add_path_constraints!(model, instance, perturbation)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 16
    bundleNodes = [[3, 13, 20, 4, 14, 17], [6, 20, 7, 13], [10, 13, 20, 11, 14, 17]]
    # println("Bundle 1")
    # println(model[:path][1, :])
    # println("Bundle 2")
    # println(model[:path][2, :])
    # println("Bundle 3")
    # println(model[:path][3, :])
    # testing for all bundles and all constraints
    @testset "Bundle $b" for b in 1:3
        @test length(model[:path][b, :]) == length(bundleNodes[b])
        # println(model[:path][b, :])
        @testset "Node $i" for i in bundleNodes[b]
            constr = constraint_object(model[:path][b, i])
            # Variables in the constraint 
            expr = AffExpr(0)
            for arc in TTGraph.bundleArcs[b]
                aSrc, aDst = arc
                aSrc == i && add_to_expression!(expr, -1, model[:x][b, arc])
                aDst == i && add_to_expression!(expr, 1, model[:x][b, arc])
            end
            @test constr.func == expr
            # Right hand side
            e = if i == TTGraph.bundleSrc[b]
                -1.0
            elseif i == TTGraph.bundleDst[b]
                1.0
            else
                0.0
            end
            @test constr.set == MOI.EqualTo(e)
        end
    end
    # No path constraints in the path flow model
end

@testset "Add packing constraints" begin
    # dummy model with the correct variables
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    # add packing constraints with a dummy model
    OFOND.add_packing_constraints!(model, instance, perturbation)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 12
    @test length(model[:packing]) == 12

    # println(model[:packing])

    # Verifying all constraints
    tau, x = model[:tau], model[:x]
    @testset "Arc $src-$dst (arc flow)" for (src, dst) in TSGraph.commonArcs
        constr = constraint_object(model[:packing][(src, dst)])
        # Variables in the constraint 
        expr = AffExpr(0)
        add_to_expression!(expr, -50, tau[(src, dst)])
        for bundle in bundles
            for order in bundle.orders
                ttSrc, ttDst = OFOND.travel_time_projector(
                    TTGraph, TSGraph, src, dst, order, bundle
                )
                if (ttSrc, ttDst) != (-1, -1) &&
                    (ttSrc, ttDst) in TTGraph.bundleArcs[bundle.idx]
                    add_to_expression!(expr, order.volume, x[bundle.idx, (ttSrc, ttDst)])
                end
            end
        end
        @test constr.func == expr
        # Right-hand side
        rhs = (src, dst) == (xdockStep4, plantStep1) ? -25.0 : 0.0
        @test constr.set == MOI.LessThan(rhs)
    end

    # Doing the same for the path flow also
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    OFOND.add_variables!(model, instance, perturbation)
    OFOND.add_packing_constraints!(model, instance, perturbation)
    @test num_constraints(model; count_variable_in_set_constraints=false) == 12
    @test length(model[:packing]) == 12

    # println(model[:packing])

    oldPaths = [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, xdockFromDel1, plantFromDel0],
    ]
    newPaths = [
        [supp1FromDel2, plantFromDel0],
        [supp2FromDel1, xdockFromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]

    # Verifying all constraints
    tau, z = model[:tau], model[:z]
    @testset "Arc $src-$dst (path flow)" for (src, dst) in TSGraph.commonArcs
        constr = constraint_object(model[:packing][(src, dst)])
        expr = AffExpr(0)
        rhs = 0.0
        # Variables in the constraint 
        add_to_expression!(expr, -50, tau[(src, dst)])
        for bundle in bundles
            for order in bundle.orders
                ttSrc, ttDst = OFOND.travel_time_projector(
                    TTGraph, TSGraph, src, dst, order, bundle
                )
                if (ttSrc, ttDst) in partition(oldPaths[bundle.idx], 2, 1)
                    rhs -= order.volume
                    add_to_expression!(expr, -order.volume, z[bundle.idx])
                elseif (ttSrc, ttDst) in partition(newPaths[bundle.idx], 2, 1)
                    add_to_expression!(expr, order.volume, z[bundle.idx])
                end
            end
        end
        @test constr.func == expr
        # Right-hand side
        @test constr.set == MOI.LessThan(rhs)
    end
end

supp1FromDel1 = TTGraph.hashToIdx[hash(1, supplier1.hash)]
supp1FromDel0 = TTGraph.hashToIdx[hash(0, supplier1.hash)]
xdockFromDel2 = TTGraph.hashToIdx[hash(2, xdock.hash)]
portFromDel1 = TTGraph.hashToIdx[hash(1, port_l.hash)]

@testset "Add objective" begin
    # milp_arc_cost for different arcs and bundles
    @test OFOND.milp_arc_cost(instance, 1, supp1FromDel1, supp1FromDel0) ≈ 1e-5
    @test OFOND.milp_arc_cost(instance, 1, supp1FromDel2, xdockFromDel1) ≈ 5.200004
    @test OFOND.milp_arc_cost(instance, 1, xdockFromDel2, portFromDel1) ≈ 5.0
    @test OFOND.milp_arc_cost(instance, 1, xdockFromDel1, plantFromDel0) ≈ 5.4
    @test OFOND.milp_arc_cost(instance, 1, supp1FromDel2, plantFromDel0) ≈ 10.401
    @test OFOND.milp_arc_cost(instance, 2, xdockFromDel2, portFromDel1) ≈ 7.0
    @test OFOND.milp_arc_cost(instance, 3, xdockFromDel2, portFromDel1) ≈ 12.0

    # Adding objective function for a dummy model with correct variables
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    instance.timeSpaceGraph.currentCost[12, 17] = 1.0
    instance.timeSpaceGraph.currentCost[16, 17] = 1e-5
    instance.timeSpaceGraph.currentCost[16, 21] = 1e-5
    instance.timeSpaceGraph.currentCost[20, 21] = 1e-5

    OFOND.add_objective!(model, instance, perturbation)
    @test objective_sense(model) == MIN_SENSE
    # Testing variable existence in objective and coefficient together with the coefficient function
    x, tau = model[:x], model[:tau]
    objExpr = objective_function(model)
    @testset "Tau $arc" for arc in TSGraph.commonArcs
        coef = arc == (12, 17) ? 1 : 1e-5
        @test coefficient(objExpr, tau[arc]) ≈ coef
    end
    # println(TTGraph.bundleArcs[1])
    # println(TTGraph.bundleArcs[2])
    # println(TTGraph.bundleArcs[3])
    # println("Arc flow objective")
    # println(objExpr)
    bundleCoefs = [
        [5.2, 10.4, 1e-5, 5.2, 5.4, 5.0, 5.4],
        [14.589, 1e-5, 7.3, 7.6],
        [12.5, 24.963, 1e-5, 12.5, 13.0, 12.0, 13.0],
    ]
    @testset "Bundle $b" for b in 1:3
        @testset "x $b $arc" for (idx, arc) in enumerate(TTGraph.bundleArcs[b])
            @test isapprox(coefficient(objExpr, x[b, arc]), bundleCoefs[b][idx]; atol=1e-3)
        end
    end
    @test isapprox(constant(objExpr), 1e-5; atol=1e-3)

    # Doing the same with path flow
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    OFOND.add_variables!(model, instance, perturbation)

    OFOND.add_objective!(model, instance, perturbation)
    @test objective_sense(model) == MIN_SENSE
    # Testing variable existence in objective and coefficient together with the coefficient function
    z, tau = model[:z], model[:tau]
    objExpr = objective_function(model)
    @testset "Tau $arc" for arc in TSGraph.commonArcs
        coef = arc == (12, 17) ? 1 : 1e-5
        @test coefficient(objExpr, tau[arc]) ≈ coef
    end
    # println("Path flow objective")
    # println(objExpr)
    bundleCoefs = [-0.2, 0.311, -0.537]
    @testset "Bundle $b" for b in 1:3
        @test isapprox(coefficient(objExpr, z[b]), bundleCoefs[b]; atol=1e-3)
    end
    @test isapprox(constant(objExpr), 50.689; atol=1e-3)
end

supp2FromDel2 = TTGraph.hashToIdx[hash(2, supplier2.hash)]
supp3FromDel3 = TTGraph.hashToIdx[hash(3, supplier3.hash)]

@testset "Warm start" begin
    testLoad = map(bins -> sum(bin.load for bin in bins; init=0), sol.bins)

    # Checking the start values that were put 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    OFOND.warm_start!(model, instance, perturbation)
    x, tau = model[:x], model[:tau]
    # bundle 2 variables
    @testset "x 2 $arc" for (idx, arc) in enumerate(TTGraph.bundleArcs[2])
        if arc in [(supp2FromDel2, supp2FromDel1), (supp2FromDel1, plantFromDel0)]
            @test start_value(x[2, arc]) == 1
        else
            @test !has_start_value(x[2, arc])
        end
    end
    # bundle 3 variables 
    @testset "x 3 $arc" for (idx, arc) in enumerate(TTGraph.bundleArcs[3])
        if arc in [
            (supp3FromDel3, supp3FromDel2),
            (supp3FromDel2, xdockFromDel1),
            (xdockFromDel1, plantFromDel0),
        ]
            @test start_value(x[3, arc]) == 1
        else
            @test !has_start_value(x[3, arc])
        end
    end
    # tau variables     
    @testset "tau $src-$dst" for (src, dst) in TSGraph.commonArcs
        arcCapacity = TSGraph.networkArcs[src, dst].capacity
        arcLoad = testLoad[src, dst]
        @test start_value(tau[(src, dst)]) == ceil(arcLoad / arcCapacity)
    end

    # Doing the same with two shared node 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.two_shared_node_perturbation(
        instance, sol, xdockFromDel1, plantFromDel0
    )
    OFOND.add_variables!(model, instance, perturbation)
    OFOND.warm_start!(model, instance, perturbation)
    x, tau = model[:x], model[:tau]
    # bundle variables
    @testset "bundle $b" for b in [1, 3]
        @testset "x $b $arc" for (idx, arc) in enumerate(TTGraph.bundleArcs[b])
            if arc == (xdockFromDel1, plantFromDel0)
                @test start_value(x[b, arc]) == 1
            else
                @test !has_start_value(x[b, arc])
            end
        end
    end
    # tau variables     
    @testset "tau $src-$dst" for (src, dst) in TSGraph.commonArcs
        arcCapacity = TSGraph.networkArcs[src, dst].capacity
        arcLoad = testLoad[src, dst]
        @test start_value(tau[(src, dst)]) == ceil(arcLoad / arcCapacity)
    end

    # Doing the same with path flow 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    OFOND.add_variables!(model, instance, perturbation)
    OFOND.warm_start!(model, instance, perturbation)
    z, tau = model[:z], model[:tau]
    # bundle variables
    @testset "bundle $b" for b in 1:3
        @test start_value(z[b]) == 0
    end
    testLoad[xdockStep4, plantStep1] -= 25
    # tau variables     
    @testset "tau $src-$dst" for (src, dst) in TSGraph.commonArcs
        arcCapacity = TSGraph.networkArcs[src, dst].capacity
        arcLoad = testLoad[src, dst]
        @test start_value(tau[(src, dst)]) == ceil(arcLoad / arcCapacity)
    end
end

@testset "Extracting paths" begin
    # get_paths for a dummy model 
    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.arc_flow_perturbation(instance, sol, [1, 2, 3])
    OFOND.add_variables!(model, instance, perturbation)
    OFOND.add_path_constraints!(model, instance, perturbation)

    # no constraints, dummy objective to get the path I want, solve and retrieve path
    x = model[:x]
    @objective(
        model,
        Max,
        x[1, (xdockFromDel1, plantFromDel0)] +
            x[2, (supp2FromDel1, plantFromDel0)] +
            x[3, (supp3FromDel2, plantFromDel0)]
    )
    set_silent(model)
    optimize!(model)
    @test OFOND.get_paths(model, instance, perturbation) == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
    @test OFOND.get_paths2(model, instance, perturbation) == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]

    model = Model(HiGHS.Optimizer)
    perturbation = OFOND.path_flow_perturbation(instance, sol, xdockFromDel1, plantFromDel0)
    OFOND.add_variables!(model, instance, perturbation)
    z = model[:z]
    @objective(model, Min, z[1] + z[2] - z[3])
    set_silent(model)
    optimize!(model)
    @test OFOND.get_paths(model, instance, perturbation) == [
        [supp1FromDel2, xdockFromDel1, plantFromDel0],
        [supp2FromDel1, plantFromDel0],
        [supp3FromDel2, plantFromDel0],
    ]
end
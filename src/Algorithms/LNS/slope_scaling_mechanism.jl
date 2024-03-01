function slope_scaling_cost_update()
    # For arcs in the time-space network :
    #     Update the current cost with the following mechanism :
    #         Compute an actual volume cost : volume_cost = (unit_cost * nb_of_units) / total_volume_in_units
    #         Compute the updated unit cost : unit cost = unit_capacity * volume_cost
    # Use this new costs in all the other heuristics
end
function run_and_get_results(scenarios, case, results_directory; mip_rel_stop)
    reopt_results = []
    results = []
    results_dir = results_directory

    bau_results = nothing  # Placeholder to store BAU results if found
    last_scenario_file = ""  # To track the last processed scenario file

    # Run optimization and get results for each scenario
    for (i, (scenario_file, scenario_name)) in enumerate(scenarios)
        println("=========================== Running scenario: $scenario_name ===========================")

        # Check if the current scenario uses the same file as the previous scenario
        if scenario_file == last_scenario_file && bau_results != nothing
            println("Reusing results from previous scenario for: $scenario_name")
            reused_results = deepcopy(bau_results)  # Create a shallow copy of the results
            push!(results, reused_results)
            push!(reopt_results, reused_results)
            continue
        end

        # Read the scenario file
        scenario_data = JSON.parsefile(scenario_file)

        # Check if 'off_grid_flag' exists and is true
        offgrid = get(scenario_data, "Settings", Dict()) |> d -> get(d, "off_grid_flag", false)

        if offgrid
            # New behavior for offgrid scenarios
            m = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results_i = run_reopt(m, scenario_file)
        else
            # Original behavior
            m1 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            m2 = Model(optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false))
            results_i = run_reopt([m1, m2], scenario_file)
        end
        
        push!(results, results_i)
        push!(reopt_results, results_i)

        # Store the results for reuse in the next iteration if the scenario file is the same
        bau_results = results_i
        last_scenario_file = scenario_file  # Update last scenario file
    end
    
    # Serialize and save reopt_results and results to disk
    serialize(open(joinpath(results_dir, "$case-reopt_results.bin"), "w"), reopt_results)
    serialize(open(joinpath(results_dir, "$case-results.bin"), "w"), results)

    return reopt_results, results
end

function post_process_results(site, scenarios, reopt_results, results, case, results_directory,current_gen_size)
    results_dir = results_directory
    df_list  =   []
    df_listb =   []
    
    # # Extract the existing generator size from the first result in reopt_results
    existing_gen_size = current_gen_size

    for (i, results_i) in enumerate(reopt_results)
        scenario_file, scenario_name = scenarios[i]
        
        try
            # Simulate Outages first
            outage = simulate_outages(results_i, REoptInputs(scenario_file))
            
            # Embed the entire outage dictionary into results_i if outage data exists
            if !isnothing(outage)
                results_i["outage_sim_res"] = outage
                
                # Generate DataFrames with the updated results_i data
                df_i  = get_REopt_data(results_i, scenario_name, cur_gen_size = existing_gen_size, shorthand=false)
                df_ib = get_REopt_data(results_i, scenario_name, cur_gen_size = existing_gen_size, shorthand=true)
            
                # Add df_i and df_ib to their respective lists
                push!(df_list, df_i)
                push!(df_listb, df_ib)
                
                # Create outage plot
                create_outage_plot(results_i, joinpath(results_dir, "$case-$site-$scenario_name-outage-plots.html"))
            
                # Save outage data to JSON
                JSON3.write(joinpath(results_dir, "$case-$site-$scenario_name-outage-results.json"), outage)
            else
                println("No outage data for $scenario_name, skipping outage-specific operations.")
            end
        catch e
            println("Error processing scenario $scenario_name: ", e)
            continue  # Skip this iteration and move on to the next
        end
        
        # Plot Thermal Dispatch only if CHP is present in the input file
        if haskey(results_i, "CHP")
            try
                plot_thermal_dispatch(results_i, title=joinpath(results_dir, "$case-$site-$scenario_name-Thermal-Dispatch-Plot"))
            catch e
                println("Error plotting thermal dispatch for $scenario_name: ", e)
            end
        end
        
        # Plot Electric Dispatch (this will run regardless of whether outage data exists)
        try
            plot_electric_dispatch(results_i, title=joinpath(results_dir, "$case-$site-$scenario_name-Electric-Dispatch-Plot"), save_dispatch_data=true)
        catch e
            println("Error plotting electric dispatch for $scenario_name: ", e)
        end
    end
    
    # Save DataFrames to CSV
    save_df(df_list, results_dir, "Results-$case-$site-long.csv")
    save_df(df_listb, results_dir, "Results-$case-$site-short.csv")

    function replace_nans_with_nothing!(df::DataFrame)
        for col in names(df)
            if eltype(df[!, col]) <: AbstractFloat
                df[!, col] = replace(df[!, col], NaN => nothing)
            end
        end
    end
    
    # Replace NaN values in each DataFrame in df_list
    for df in df_list
        replace_nans_with_nothing!(df)
    end
    
    # Combine results into final DataFrame
    final_df = vcat(df_list...)
    
    # Replace NaN values in the concatenated DataFrame
    replace_nans_with_nothing!(final_df)
    
    # Write to JSON
    JSON3.write(joinpath(results_dir, "Results-$case-$site.json"), final_df)

    # Save Raw REOPT Results
    json_data   =   JSON.json(reopt_results)
    parsed_json =   JSON.parse(json_data)

    function sum_arrays_in_json(data)
        if isa(data, Dict)
            # If it's a dictionary, apply recursively to each key-value pair
            return Dict(key => sum_arrays_in_json(value) for (key, value) in data)
        elseif isa(data, Vector)
            # Filter numeric elements
            numeric_elements = [x for x in data if isa(x, Number)]
            if !isempty(numeric_elements) && length(numeric_elements) == length(data)
                # Sum only if all elements are numeric
                return sum(numeric_elements)
            else
                # Otherwise, recurse on each element
                return [sum_arrays_in_json(item) for item in data]
            end
        else
            # Return the data as is if it's not a Dict or Vector
            return data
        end
    end

    summed_json = sum_arrays_in_json(parsed_json)

    # Save the modified JSON to a file
    output_file = joinpath(results_dir, "$case-$site-Raw-Data.json")
    JSON3.write(output_file, summed_json)

    println("Raw data saved successfully to $case-$site-Raw-Data.json")

    # JSON3.write(joinpath(results_dir, "$case-$site-Raw-Data.json"), parsed_json)

    # # Extract only the electric_to_load_series_kw_bau dictionary from ElectricUtility
    # electric_to_storage_series_kw_bau =   results[1]["ElectricUtility"]["electric_to_load_series_kw_bau"]

    # # Create a new dictionary containing only this data
    # filtered_results =   Dict("ElectricUtility" => Dict("electric_to_load_series_kw_bau" => electric_to_storage_series_kw_bau))

    # # Pass this filtered dictionary to the plot_electric_dispatch function
    # plot_electric_dispatch(filtered_results, title=joinpath(results_dir, "$case-$site - Statistics"), display_stats=true)
   
    # Check if "electric_to_load_series_kw_bau" exists in the dictionary
    if haskey(results[1]["ElectricUtility"], "electric_to_load_series_kw_bau")
        # Extract the electric_to_load_series_kw_bau data
        electric_to_storage_series_kw_bau = results[1]["ElectricUtility"]["electric_to_load_series_kw_bau"]

        # Create a new dictionary containing only this data
        filtered_results = Dict("ElectricUtility" => Dict("electric_to_load_series_kw_bau" => electric_to_storage_series_kw_bau))

        # Check if electric_to_storage_series_kw_bau is not all zeros
        if !all(value -> value == 0, values(electric_to_storage_series_kw_bau))
            # Only call plot_electric_dispatch if the condition is met
            plot_electric_dispatch(filtered_results, title=joinpath(results_dir, "$case-$site - Statistics"), display_stats=true)
        else
            println("Skipping plot_electric_dispatch: electric_to_load_series_kw_bau contains all zeros.")
        end
    else
        println("Key 'electric_to_load_series_kw_bau' not found in 'ElectricUtility'.")
        # Handle the absence of the key as needed
    end


end

function update_json_file(filepath, json_section, key, new_value)
    # Load JSON content
    json_content = JSON.parsefile(filepath)

    # Update the key-value if the section and key exist
    if haskey(json_content, json_section)
        # Check if the key exists in the section
        if haskey(json_content[json_section], key)
            json_content[json_section][key] = new_value
        else
            println("Key '$key' does not exist in section '$json_section'. Adding it now.")
            json_content[json_section][key] = new_value
        end
    else
        println("Section '$json_section' does not exist. Adding it now.")
        json_content[json_section] = Dict(key => new_value)
    end

    # Save the updated JSON back to the file
    open(filepath, "w") do file
        JSON.print(file, json_content, 4)
    end
    return true
end

# Function to update a specific key-value in a single scenario
function update_single_scenario_key_value(case_key, scenario_index, json_section, key, new_value, scenarios_dict)
    if haskey(scenarios_dict, case_key)
        if scenario_index <= length(scenarios_dict[case_key])
            filepath = scenarios_dict[case_key][scenario_index][1]  # Get the file path of the scenario
            filename = basename(filepath)  # Extract the file name from the path

            # Update and save the JSON file
            updated = update_json_file(filepath, json_section, key, new_value)
            if updated
                println("Updated $key in $json_section for scenario file $filename to $new_value")
            else
                println("Section $json_section or key $key not found in scenario file $filename.")
            end
        else
            println("Scenario index $scenario_index out of range for case $case_key.")
        end
    else
        println("Case $case_key not found in scenarios.")
    end
end

# Function to update a specific key-value in a specific case
function update_case_key_value(case_key, json_section, key, new_value, scenarios_dict)
    if haskey(scenarios_dict, case_key)
        for (filepath, _) in scenarios_dict[case_key]
            updated = update_json_file(filepath, json_section, key, new_value)
            if !updated
                println("Section $json_section or key $key not found in scenario file $filepath.")
            end
        end
        println("Updated $key in $json_section for case $case_key to $new_value")
    else
        println("Case $case_key not found in scenarios.")
    end
end

# Function to update a specific key-value in all cases
function update_all_cases_key_value(json_section, key, new_value, scenarios_dict)
    for (case, scenarios) in scenarios_dict
        for (filepath, _) in scenarios
            updated = update_json_file(filepath, json_section, key, new_value)
            if !updated
                println("Section $json_section or key $key not found in scenario file $filepath.")
            end
        end
        println("Updated $key in $json_section for all cases to $new_value")
    end
end

function save_df(df_list, results_directory, filename)
    final_df =   vcat(df_list...)
    results_dir = results_directory
    final_df =   permutedims(final_df, 1, makeunique=true)

    # Identify rows to keep (those that don't have all "-" except for the first column)
    rows_to_keep = Bool[]
    for row in eachrow(final_df)
        if any(x -> x != "-", row[2:end]) # Check if any value is not "-"
            push!(rows_to_keep, true)
        else
            push!(rows_to_keep, false)
        end
    end

    # Keep only the rows that don't have all "-" in columns other than the first
    final_df = final_df[rows_to_keep, :]

    CSV.write(joinpath(results_dir, filename), final_df, transform=(col, val) -> something(val, "-"))
end

# Function to create necessary directories and check for required JSON files
function setup_project_directory(base_path::String, site_name::String)
    project_path = joinpath(base_path, site_name)
    scenarios_path = joinpath(project_path, "scenarios")

    for path in [project_path, scenarios_path]
        if !isdir(path)
            mkdir(path)
            println("Created directory: $path")
        end
    end

    # JSON scenario structure
    scenarios_json = Dict(
        site_name => Dict(
            "Group1Name" => [
                ["scenarios/reopt_scenario_template.json", "0a. BAU"],
                ["scenarios/reopt_scenario_template.json", "1a. PV Only Scenario"],
            ]
        )
    )

    # Check and create scenario JSON file
    scenarios_json_path = joinpath(project_path, site_name * "_scenarios.json")
    if !isfile(scenarios_json_path)
        open(scenarios_json_path, "w") do file
            JSON.print(file, scenarios_json)
        end
        println("Created JSON scenario file: $scenarios_json_path")
    end

    # Placeholder for reopt_template.json
    reopt_template = Dict(
        "ElectricTariff" => Dict("urdb_label" => "6524689a4a37bbdf8701e162"),
        "Site" => Dict("latitude" => 0.00, "longitude" => -0.00),
        "ElectricLoad" => Dict("loads_kw" => [1, 2, 3], "year" => 2024),
        "PV" => Dict(
            "array_type" => 0,
            "macrs_option_years" => 5,
            "module_type" => 0,
            "can_net_meter" => true,
            "macrs_bonus_fraction" => 0.8
        )
    )

    # Check and create reopt_template.json in the scenarios folder
    template_json_path = joinpath(scenarios_path, "reopt_scenario_template.json")
    if !isfile(template_json_path)
        open(template_json_path, "w") do file
            JSON.print(file, reopt_template)
        end
        println("Created REopt template JSON file: $template_json_path")
    end

    return project_path
end


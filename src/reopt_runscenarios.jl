function run_and_get_results(scenarios, case, results_directory; mip_rel_stop)
    reopt_results = []
    results = []
    results_dir = results_directory

    bau_results = nothing
    last_scenario_file = ""

    # Function to create a solver
    function create_solver()
        try
            return optimizer_with_attributes(Xpress.Optimizer, "MIPRELSTOP" => mip_rel_stop, "OUTPUTLOG" => 0)
        catch
            @warn "Xpress solver not available. Falling back to HiGHS."
            return optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false, "log_to_console" => false, "mip_rel_gap" => mip_rel_stop)
        end
    end

    for (i, (scenario_file, scenario_name)) in enumerate(scenarios)
        println("=========================== Running scenario: $scenario_name ===========================")

        if scenario_file == last_scenario_file && bau_results != nothing
            println("Reusing results from previous scenario for: $scenario_name")
            reused_results = deepcopy(bau_results)
            push!(results, reused_results)
            push!(reopt_results, reused_results)
            continue
        end

        scenario_data = JSON.parsefile(scenario_file)
        offgrid = get(scenario_data, "Settings", Dict()) |> d -> get(d, "off_grid_flag", false)

        if offgrid
            m = Model(create_solver())
            results_i = run_reopt(m, scenario_file)
        else
            m1 = Model(create_solver())
            m2 = Model(create_solver())
            results_i = run_reopt([m1, m2], scenario_file)
        end
        
        push!(results, results_i)
        push!(reopt_results, results_i)

        bau_results = results_i
        last_scenario_file = scenario_file
    end
    
    serialize(open(joinpath(results_dir, "$case-reopt_results.bin"), "w"), reopt_results)
    serialize(open(joinpath(results_dir, "$case-results.bin"), "w"), results)

    return reopt_results, results
end

function post_process_results(site, scenarios, reopt_results, results, case, results_directory, current_gen_size)
    results_dir = results_directory
    df_list  =   []
    df_listb =   []
    
    existing_gen_size = current_gen_size

    for (i, results_i) in enumerate(reopt_results)
        scenario_file, scenario_name = scenarios[i]
        
        # Re-check if this scenario is off-grid
        scenario_data = JSON.parsefile(scenario_file)
        offgrid = get(scenario_data, "Settings", Dict()) |> d -> get(d, "off_grid_flag", false)
        
        try
            if !offgrid
                # Simulate Outages only for grid-connected scenarios
                outage = simulate_outages(results_i, REoptInputs(scenario_file))
                
                if !isnothing(outage)
                    results_i["outage_sim_res"] = outage
                    
                    # Create outage plot
                    create_outage_plot(results_i, joinpath(results_dir, "$case-$site-$scenario_name-outage-plots.html"))
                
                    # Save outage data to JSON
                    JSON3.write(joinpath(results_dir, "$case-$site-$scenario_name-outage-results.json"), outage)
                else
                    println("No outage data for $scenario_name, skipping outage-specific operations.")
                end
            else
                println("Skipping outage simulation for off-grid scenario: $scenario_name")
            end
            
            # Generate DataFrames with the results_i data
            df_i  = get_REopt_data(results_i, scenario_name, cur_gen_size = existing_gen_size, shorthand=false)
            df_ib = get_REopt_data(results_i, scenario_name, cur_gen_size = existing_gen_size, shorthand=true)
        
            # Add df_i and df_ib to their respective lists
            push!(df_list, df_i)
            push!(df_listb, df_ib)
            
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
    placeholders_created = false
    scenarios_file_reconstructed = false

    # Check if directories exist
    for path in [project_path, scenarios_path]
        if !isdir(path)
            mkdir(path)
            println("Created directory: $path")
        else
            println("Directory already exists: $path")
        end
    end

    # Check for existing scenario JSON file
    scenarios_json_path = joinpath(project_path, site_name * "_scenarios.json")
    if isfile(scenarios_json_path)
        println("Existing scenarios file found: $scenarios_json_path")
        
        # Read the content of the file
        file_content = read(scenarios_json_path, String)
        
        if isempty(file_content)
            println("WARNING: The scenarios file is empty. Creating a default structure.")
            scenarios_json = create_default_scenarios(site_name)
            scenarios_file_reconstructed = true
        else
            try
                scenarios_json = JSON.parse(file_content)
                if !haskey(scenarios_json, site_name)
                    println("WARNING: The scenarios file does not contain the expected structure. Creating a default structure.")
                    scenarios_json = create_default_scenarios(site_name)
                    scenarios_file_reconstructed = true
                end
            catch e
                println("ERROR: Failed to parse the scenarios file. Creating a default structure.")
                println("Parse error: ", e)
                scenarios_json = create_default_scenarios(site_name)
                scenarios_file_reconstructed = true
            end
        end
    else
        println("Scenarios file not found. Creating a new one with default structure.")
        scenarios_json = create_default_scenarios(site_name)
        scenarios_file_reconstructed = true
    end

    # Save the scenarios JSON (either parsed or newly created)
    open(scenarios_json_path, "w") do file
        JSON.print(file, scenarios_json, 4)  # 4 spaces for indentation
    end
    println("Scenarios file saved: $scenarios_json_path")

    # Check for existing scenario files
    missing_scenarios = []
    for (group_name, scenarios) in scenarios_json[site_name]
        for (scenario_file, scenario_name) in scenarios
            full_scenario_path = joinpath(project_path, scenario_file)
            if !isfile(full_scenario_path)
                push!(missing_scenarios, (scenario_file, scenario_name))
            end
        end
    end

    if !isempty(missing_scenarios)
        println("The following scenario files are missing and will be created as placeholders:")
        for (file, name) in missing_scenarios
            println("- $name ($file)")
            create_placeholder_scenario(joinpath(project_path, file))
        end
        placeholders_created = true
    end

    if placeholders_created || scenarios_file_reconstructed
        println("\nIMPORTANT: Ensure that ALL scenario files are updated with your specific data before running REopt.")
        println("Using placeholder or incorrectly configured files will result in errors or incorrect results.")
        
        error_message = """
        IMPORTANT: Action Required Before Proceeding!

        1. File Update Needed:
           - Ensure that ALL scenario files are updated with your specific data before running REopt.
           - Using placeholder or incorrectly configured files will result in errors or incorrect results.

        2. Check File Names and Structure:
           There might be a mismatch between the expected and actual file names or structure.
           
           a) Scenarios File Naming:
              - The scenarios file should be named: <SiteName>_scenarios.json
              - Example: If your folder is named 'PlaceholderSite1', the file should be 'PlaceholderSite1_scenarios.json'

           b) Scenarios File Structure:
              The content of <SiteName>_scenarios.json should follow this structure:
              {
                  "<SiteName>": {
                      "PlaceholderGroupName": [
                          ["scenarios/0a_BAU.json", "0a. BAU "],
                          ["scenarios/1a_PV_Only_Scenario.json", "1a. PV Only Scenario"]
                      ]
                  }
              }

           c) Common Naming Issues:
              - Spelling errors (e.g., 'senario' instead of 'scenario')
              - Capitalization differences (e.g., 'Bau' instead of 'BAU')
              - Incorrect file extensions (e.g., '.JSON' instead of '.json')

        3. Verify JSON Structure and File Existence:
           - Ensure your scenarios JSON file has the correct structure as shown above.
           - Verify that all scenario files specified in the JSON actually exist in the 'scenarios' folder.

        4. Next Steps:
           - Review and correct any issues in your file names and structure.
           - Update placeholder files with your specific scenario data.
           - Rerun the notebook after making the necessary corrections.

        If you continue to experience issues, please double-check all file names and paths for accuracy.
        """
        throw(ErrorException(error_message))
    end

    return project_path
end

function create_default_scenarios(site_name::String)
    Dict(
        site_name => Dict(
            "PlaceholderGroupName" => [
                ["scenarios/0a_BAU.json", "0a. BAU"],
                ["scenarios/1a_PV_Only_Scenario.json", "1a. PV Only Scenario"],
            ]
        )
    )
end

function create_placeholder_scenario(file_path::String)
    placeholder_scenario = 
    Dict(
        "Site"=> Dict(
            "longitude"=> -118.1164613,
            "latitude"=> 34.5794343
        ),
        "PV"=> Dict(
        ),
        "ElectricLoad"=> Dict(
            "doe_reference_name"=> "**PLACEHOLDER SITE - UPDATE WITH CORRECT DATA**",
            "annual_kwh"=> 200000.0,
            "year"=> 2017
        ),
        "ElectricTariff"=> Dict(
            "urdb_label"=> "**PLACEHOLDER SITE - UPDATE WITH CORRECT DATA**"
        ),
        "ElectricUtility"=> Dict(
            "net_metering_limit_kw"=> 1000
        ),
        "Financial"=> Dict(
            "elec_cost_escalation_rate_fraction"=> 0.026,
            "offtaker_discount_rate_fraction"=> 0.08,
            "offtaker_tax_rate_fraction"=> 0.28,
            "om_cost_escalation_rate_fraction"=> 0.025
        )
    )
    
    open(file_path, "w") do file
        JSON.print(file, placeholder_scenario, 4)  # 4 spaces for indentation
    end
    println("Created placeholder scenario file: $file_path")
end
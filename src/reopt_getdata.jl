function sum_numeric(vector, default_value=0.0)
    numeric_vector = [isa(x, Number) ? (isnan(x) ? default_value : x) : default_value for x in vector]
    return sum(numeric_vector)
end

function get_REopt_data(data_f, scenario_name; cur_gen_size = 0, shorthand=false)	

    # Ensure scenario_name is a string before using it with occursin
    scenario_name_str = isa(scenario_name, String) ? scenario_name : string(scenario_name)

    suffix = occursin(r"(?i)\bBAU\b", scenario_name_str) ? "_bau" : ""
    
    function get_with_suffix(df, key, default_val)
        # Only append suffix if key doesn't already end with it
        if !endswith(key, "_bau")
            key = "$key$suffix"
        end
        return get(df, key, default_val)
    end

    config = [
        (df -> get_with_suffix(df, "PV.size_kw", 0), "PV Size (kW-DC)", false),                      
        (df -> get_with_suffix(df, "Wind.size_kw", 0), "Wind Size (kW)", false),                   
        (df -> get_with_suffix(df, "ElectricStorage.size_kw", 0), "Battery Size (kW)", false),   
        (df -> get_with_suffix(df, "ElectricStorage.size_kwh", 0), "Battery Capacity (kWh)", false),
        (df -> get_with_suffix(df, "CHP.size_kw", 0), "CHP (kW)", false),
        (df -> cur_gen_size, "Current Gen. Capacity (kW)", false),
        (df -> get(df, "Generator.size_kw", 0) - cur_gen_size, "Add-on Gen. Capacity (kW)", false),
        (df -> get_with_suffix(df, "Financial.lifecycle_capital_costs", 0), "Net Capital Cost (\$)", true),
        (df -> get_with_suffix(df, "Financial.initial_capital_costs", 0), "Initial Capital Cost without Incentives (\$)", true),
        (df -> get_with_suffix(df, "Financial.initial_capital_costs_after_incentives", 0), "Initial Capital Cost with Incentives  (\$)", true),
        (df -> get_with_suffix(df, "Financial.year_one_om_costs_before_tax", 0), "Annual OM Cost  (\$)", true),
        (df -> get_with_suffix(df, "Financial.lifecycle_MG_upgrade_and_fuel_cost", 0), "Microgrid Upgrade and Fuel Cost (\$)", true),
        (df -> get_with_suffix(df, "Generator.year_one_fuel_cost_before_tax", 0), "Annual Generator Fuel Cost (\$)", true),
        (df -> round(100*get_with_suffix(df, "Site.renewable_electricity_fraction", 0)), "RE Penetration (%)", false),
        (df -> get_with_suffix(df, "Site.annual_emissions_tonnes_CO2", 0), "Annual CO2 Emissions (Tons)", false),
        (df -> get_with_suffix(df, "Site.lifecycle_emissions_tonnes_CO2", 0), "Lifecycle CO2 Emissions (Tons)", false),
        (df -> round(100*get_with_suffix(df, "Site.lifecycle_emissions_reduction_CO2_fraction", 0)), "Lifecycle CO2 Reduction (%)", false),
        (df -> get_with_suffix(df, "ElectricLoad.annual_calculated_kwh", 0), "Annual MG Load (kWh)", false),
        (df -> sum_numeric(get_with_suffix(df, "ElectricUtility.electric_to_load_series_kw", 0)), "Year 1 Electric Grid Purchases (kWh)", false),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_energy_cost_before_tax", 0), "Year 1 Energy Charges (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_demand_cost_before_tax", 0), "Year 1 Demand Charges (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_fixed_cost_before_tax", 0), "Year 1 Fixed Cost Charges (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_coincident_peak_cost_before_tax", 0), "Year 1 Coincident Peak Charges (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax", 0), "Year 1 Total Electric Bill Costs (\$)", true),
        (df -> get_with_suffix(df, "CHP.year_one_fuel_cost_before_tax", 0), "Year 1 CHP Fuel Cost (\$)", true),
        (df -> get_with_suffix(df, "ExistingBoiler.year_one_fuel_cost_before_tax", 0), "Year 1 Existing Boiler Fuel Cost (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_energy_cost_before_tax_bau", 0) - get_with_suffix(df, "ElectricTariff.year_one_energy_cost_before_tax", 0), "Year 1 Energy Charge Savings (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_demand_cost_before_tax_bau", 0) - get_with_suffix(df, "ElectricTariff.year_one_demand_cost_before_tax", 0), "Year 1 Demand Charge Savings (\$)", true),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax_bau", 0) - get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax", 0), "Year 1 Total Electric Bill Savings (\$)", true),
        (df -> round(100 * (get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax_bau", 0) 
                                - get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax", 0)) 
                                / (get_with_suffix(df, "ElectricTariff.year_one_bill_before_tax_bau", 1) + 1e-6)),"Year 1 Utility Savings (%)", false),
        (df -> round(get_with_suffix(df, "outage_sim_res.resilience_hours_avg", 0)), "Avg. Outage Duration Survived (Hours)", false),
        (df -> get_with_suffix(df, "ElectricTariff.lifecycle_fixed_cost_after_tax", 0) + get_with_suffix(df, "ElectricTariff.lifecycle_demand_cost_after_tax", 0) + get_with_suffix(df, "ElectricTariff.lifecycle_energy_cost_after_tax", 0), "Lifecycle Utility Electricity Cost (\$)", true),
        # (df -> round(100 * get_with_suffix(df, "Financial.npv", 0) / get_with_suffix(df, "Financial.lcc_bau", 1)), "Lifecycle Savings (%)", false),
        (df -> get_with_suffix(df, "Financial.simple_payback_years", 0), "Payback Period (Years)", false),
        (df -> get_with_suffix(df, "Financial.lcc", 0), "Total Lifecycle Cost (\$)", true),
        (df -> get_with_suffix(df, "Financial.npv", 0), "Net Present Value (\$)", true),
        (df -> round(100 * (get_with_suffix(df, "Financial.npv", 0)) / (get_with_suffix(df, "Financial.lcc_bau", 1) + 1e-6)),"Savings Compared to BAU (%)", false),
        (df -> get_with_suffix(df, "Financial.offgrid_microgrid_lcoe_dollars_per_kwh", 0), "Microgrid LCOE", false),
        (df -> sum_numeric(get_with_suffix(df, "PV.electric_to_load_series_kw", 0)), "Annual PV to Load (kWh)", false),
        (df -> sum_numeric(get_with_suffix(df, "ElectricStorage.storage_to_load_series_kw", 0)), "Annual Storage to Load (kWh)", false),
        (df -> sum_numeric(get_with_suffix(df, "Generator.electric_to_load_series_kw", 0)), "Annual Generator to Load (kWh)", false),
        # (df -> sum_numeric(get_with_suffix(df, "PV.electric_curtailed_series_kw", [])), "PV Curtailed", false),                    #1
        # (df -> get_with_suffix(df, "PV.lcoe_per_kwh", 0), "PV Levelized Cost of Energy (\$/kWh)", false),
        (df -> get_with_suffix(df, "ElectricTariff.year_one_export_benefit_before_tax", 0), "Year 1 Net Metering Benefit (\$)", true),
        (df -> get_with_suffix(df, "Financial.annualized_payment_to_third_party", 0), "Annual Payment to Third-Party (\$)", true),
        (df -> round(get_with_suffix(df, "Financial.annualized_payment_to_third_party", 0)/12), "Monthly Payment to Third-Party (\$)", true),
        # (df -> get_with_suffix(df, "Financial.lifecycle_capital_costs", 0)/get_with_suffix(df, "Financial.lcc_bau", 1), "Simple Payback Period (Years)", true),
        (df -> get_with_suffix(df, "Financial.lifecycle_generation_tech_capital_costs", 0), "PV Installed Cost (\$)", true),
        (df -> get_with_suffix(df, "Financial.lifecycle_storage_capital_costs", 0), "Battery Installed Cost (\$)", true),
    ]

    # Flatten the dictionary
    df_gen = flatten_dict(data_f)

    # Dynamically add PV entries at the end of the config if PV is a Vector{Dict}
    if haskey(df_gen, "PV") && isa(df_gen["PV"], Vector{Dict})
        for pv_dict in df_gen["PV"]
            if haskey(pv_dict, "name")
                pv_name = pv_dict["name"]

                # For size_kw
                pv_size_kw_key = "size_kw$suffix"  # Use suffix to determine the correct key
                pv_size_kw = get(pv_dict, pv_size_kw_key, 0)
                insert!(config, 1, (_ -> pv_size_kw, "PV-$pv_name Size (kW-DC)", false))

                # For electric_curtailed_series_kw
                pv_electric_curtailed_series_kw_key = "electric_curtailed_series_kw$suffix"
                pv_electric_curtailed_series_kw = get(pv_dict, pv_electric_curtailed_series_kw_key, [])

                # Ensure pv_electric_curtailed_series_kw is a vector. If not, make it a one-element vector
                pv_electric_curtailed_series_kw = isa(pv_electric_curtailed_series_kw, Vector) ? pv_electric_curtailed_series_kw : [pv_electric_curtailed_series_kw]

                # Use sum_numeric to sum the values, handling NaNs and non-numeric values
                pv_electric_curtailed_series_kw_sum = sum_numeric(pv_electric_curtailed_series_kw)
                push!(config, (_ -> pv_electric_curtailed_series_kw_sum, "PV-$pv_name Curtailed Total (kW)", false))

                # For lcoe_per_kwh
                pv_lcoe_per_kwh_key = "lcoe_per_kwh$suffix"
                pv_lcoe_per_kwh = get(pv_dict, pv_lcoe_per_kwh_key, 0)
                push!(config, (_ -> pv_lcoe_per_kwh, "PV-$pv_name LCOE (\$/kWh)", false))

                # For year_one_export_benefit_before_tax
                pv_year_one_export_benefit_key = "year_one_export_benefit_before_tax$suffix"
                pv_year_one_export_benefit = get(pv_dict, pv_year_one_export_benefit_key, 0)
                push!(config, (_ -> pv_year_one_export_benefit, "PV-$pv_name Year 1 Net Metering Benefit (\$)", false))
            end
        end
    end
    
    # suffix = occursin(r"(?i)\bBAU\b", scenario_name) ? "_bau" : ""
    
    # Create an empty dictionary to hold the data for each column
    data_dict = Dict{String, Vector{Any}}()

    # Initialize the data_dict with empty arrays for each column
    for (var_key, col_name, _) in config
        data_dict[col_name] = []
    end

    # Populate the data_dict with values for each column
    for (var_key, col_name, sh) in config
        # Decide if the key is a function or a string (field from the data)
        if isa(var_key, Function)
            val = var_key(df_gen)  # If function, then apply the function to get the value
        else
            val = get_with_suffix(df_gen, var_key, "-")  # Use helper function to fetch from dictionary
        end
        
        # Further processing
        if isa(val, Number)
            val = round(val, digits=2)  # Round to nearest second decimal place
        end

        if shorthand && sh
            val = format_shorthand(val)
        else
            val = isa(val, Number) ? string(val) : val  # Convert number to string if necessary
        end

        # Add the value to the corresponding column's array
        push!(data_dict[col_name], val)
    end

    data_dict["Scenario"] = [scenario_name]

    # Replace undesired values with "-" in data_dict
    for (key, value_array) in data_dict
        if length(value_array) > 0 && (isa(value_array[1], Int64) || isa(value_array[1], Float64) || isa(value_array[1], String))
            new_value_array = [v in [0, NaN,"NaN","-Inf","-Inf",Inf,-Inf, "0" ,"0.0", "\$0.0",-0,"-0","-0.0","-\$0.0"] ? "-" : v for v in value_array]
            data_dict[key] = new_value_array
        end
    end

    # Create a DataFrame from the dictionary with the desired column order
    col_order = ["Scenario"]
    for (var_key, col_name, _) in config
        push!(col_order, col_name)
    end

    df_res = DataFrame(data_dict)
    df_res = df_res[:, col_order]
    
    # # Remove columns where all values are "-"
    # to_remove = []
    # for col in names(df_res)
    #     if all(df_res[:, col] .== "-")
    #         push!(to_remove, col)
    #     end
    # end
    # select!(df_res, Not(to_remove))
    

    return df_res
end


function get_pv_size(df)
    total_pv_size = 0
    if haskey(df, "PV")
        pv_entry = df["PV"]
        if isa(pv_entry, Dict)
            # Check if the first value in PV dict is a dict (indicating multiple PVs)
            first_value = collect(values(pv_entry))[1]
            if isa(first_value, Dict)
                for (_, pv_sub_dict) in pv_entry
                    total_pv_size += get(pv_sub_dict, "size_kw", 0)
                end
            elseif isa(first_value, Vector{Dict})
                for pv_array in first_value
                    total_pv_size += get(pv_array, "size_kw", 0)
                end
            else
                total_pv_size = get(pv_entry, "size_kw", 0)
            end
        elseif isa(pv_entry, Vector{Dict})
            for pv_dict in pv_entry
                total_pv_size += get(pv_dict, "size_kw", 0)
            end
        end
    end
    return total_pv_size
end

# Helper function to format the number in shorthand notation
function format_shorthand(num; currency_symbol="\$")
    if isa(num, String)
        return num
    else
        if num >= 1e6 || num <= -1e6
            return string(num >= 0 ? "" : "-") * currency_symbol * string(round(abs(num) / 1e6, digits=2)) * "M"
        elseif num >= 1e3 || num <= -1e3
            return string(num >= 0 ? "" : "-") * currency_symbol * string(round(abs(num) / 1e3, digits=2)) * "k"
        else
            return string(num >= 0 ? "" : "-") * currency_symbol * string(round(abs(num), digits=2))
        end
    end
end

function prepare_table_data(all_scenarios)
    all_keys = Set{String}()
    scenario_data = Dict{String, Dict{String, Any}}()

    # Collect data and all keys across scenarios
    for (case, scenarios) in all_scenarios
        for (path, scenario_name) in scenarios
            json_data = JSON.parse(open(path))
            scenario_dict = Dict{String, Any}()
            full_scenario_name = case * ": " * scenario_name

            for key in keys(json_data)
                value = json_data[key]
                push!(all_keys, key)

                # Process the value accordingly
                if isa(value, Array)
                    if all(v -> isa(v, Number), value)
                        scenario_dict[key] = round(mean(value), digits=2)
                    elseif all(v -> isa(v, Dict), value)
                        scenario_dict[key] = process_array_of_dicts(value)
                    else
                        scenario_dict[key] = value
                    end
                elseif isa(value, Dict)
                    scenario_dict[key] = process_dict(value)
                else
                    scenario_dict[key] = value
                end
            end

            scenario_data[full_scenario_name] = scenario_dict
        end
    end

    sorted_scenario_names = sort(collect(keys(scenario_data)))
    sorted_all_keys = sort(collect(all_keys))

    num_scenarios = length(sorted_scenario_names)
    num_columns = length(sorted_all_keys) + 1  # +1 for scenario names
    table_data = Array{Any}(undef, num_scenarios, num_columns)

    # Fill in the table with sorted scenario names and formatted data
    for (i, full_scenario_name) in enumerate(sorted_scenario_names)
        scenario = scenario_data[full_scenario_name]
        table_data[i, 1] = full_scenario_name  # Scenario name

        for (j, key) in enumerate(sorted_all_keys)
            if haskey(scenario, key)
                value = scenario[key]
                if isa(value, Dict)
                    table_data[i, j + 1] = format_dict(value)
                elseif isa(value, Array)
                    if all(v -> isa(v, Dict), value)
                        table_data[i, j + 1] = format_array_of_dicts(value)
                    else
                        table_data[i, j + 1] = "\"" * replace(string(value), ", " => ",\n") * "\""  # Replace ', ' with ',\n' for line breaks
                    end
                else
                    formatted_value = "\"" * replace(string(value), ", " => ",\n") * "\""  # Replace ', ' with ',\n' for line breaks
                    table_data[i, j + 1] = formatted_value
                end
            else
                table_data[i, j + 1] = "*** NOT INCLUDED ***"
            end
        end
    end

    return table_data, ["Scenario"; sorted_all_keys]
end

function process_dict(dict)
    simplified_dict = String[]
    for (k, v) in dict
        if isa(v, Array) && all(vv -> isa(vv, Number), v)
            push!(simplified_dict, "$k: $(round(mean(v), digits=2))")
        elseif isa(v, Dict) || isa(v, Array)
            push!(simplified_dict, "$k: Complex structure")
        else
            push!(simplified_dict, "$k: $v")
        end
    end
    return join(simplified_dict, ", ")
end

function process_array_of_dicts(arr::Array{Dict, 1})
    processed_array = [process_dict(dict) for dict in arr]
    return processed_array
end

function format_dict(dict::Dict)
    formatted_dict = ""
    sorted_dict_keys = sort(collect(keys(dict)))
    for (idx, dict_key) in enumerate(sorted_dict_keys)
        formatted_dict *= string(idx) * ". " * dict_key * ": " * string(dict[dict_key]) * ",\n"
    end
    formatted_dict = chop(formatted_dict, tail=2)
    return "\"" * replace(formatted_dict, ", " => ",\n") * "\""  # Replace ', ' with ',\n' for line breaks
end

function format_array_of_dicts(arr::Array{Dict, 1})
    formatted_array = ""
    for (idx, dict) in enumerate(arr)
        formatted_array *= "Item " * string(idx) * ":\n" * format_dict(dict) * "\n"
    end
    return "\"" * chop(formatted_array, tail=1) * "\""  # Removing the last newline
end

function format_value(value)
    if isa(value, Number)
        return round(value, digits=2)
    elseif isa(value, String)
        return replace(value, "\"" => "")
    else
        return value
    end
end


function create_next_version_dir(base_path, base_name="results")
    date_str = Dates.format(now(), "yyyymmdd")
    highest_version = 0
    latest_dir_path = nothing

    # Ensure the base directory exists
    mkpath(base_path)
    dirs = readdir(base_path, join=true)

    # Initialize sorted_dirs outside the try block
    sorted_dirs = Vector{String}()  # Initialize as an empty vector of strings
    println("RUN_NEW_ANALYSIS:", RUN_NEW_ANALYSIS)
    
    if !RUN_NEW_ANALYSIS
        # Attempt to sort directories by date descending, then find the highest version of the latest date
        latest_date = nothing
        try
            sorted_dirs = sort(dirs, by=d -> begin
                dir_parts = split(splitdir(d)[2], '_')
                length(dir_parts) >= 3 ? dir_parts[2] : "00000000"  # Default to a low date if format is incorrect
            end, rev=true)
        catch err
            println("Error sorting directories: ", err)
            return nothing  # Exit if sorting fails
        end

        # Process sorted directories
        for dir in sorted_dirs
            dir_name = splitdir(dir)[2]
            if occursin("$(base_name)_", dir_name) && occursin(r"_v\d+$", dir_name)
                date_part = split(dir_name, '_')[2]
                if isnothing(latest_date) || date_part == latest_date
                    latest_date = date_part
                    version_str = match(r"_v(\d+)$", dir_name).captures[1]
                    version = parse(Int, version_str)
                    if version > highest_version
                        highest_version = version
                        latest_dir_path = dir
                    end
                end
            end
        end

        # Check if the latest version directory is empty, if it exists
        if !isnothing(latest_dir_path) && !isempty(readdir(latest_dir_path))
            println("Reusing existing directory: $latest_dir_path")
            return latest_dir_path
        end
    else
        # Iterate through directories to find the highest version for today's date
        for dir in dirs
            dir_name = splitdir(dir)[2]
            if occursin("$(base_name)_$(date_str)_v", dir_name)
                version_str = match(r"_v(\d+)$", dir_name).captures[1]
                version = parse(Int, version_str)
                if version > highest_version
                    highest_version = version
                    latest_dir_path = dir
                end
            end
        end
    end

    # Create the next version directory if the latest is empty or doesn't exist or RUN_NEW_ANALYSIS is true
    new_version = highest_version + 1
    new_dir_name = "$(base_name)_$(date_str)_v$(new_version)"
    new_dir_path = joinpath(base_path, new_dir_name)
    mkpath(new_dir_path)

    println("Created new directory: $new_dir_path")
    return new_dir_path
end

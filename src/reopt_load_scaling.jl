module LoadAdjustment

using DataFrames, CSV, Dates, Statistics, PlotlyJS, Random, Polynomials

function smooth_load_around_peak(df, peak_hour_index, target_peak, electric_load_column_name)
    # Define the ranges for fitting
    hours_before_after = 5
    smoothing_range_start = max(1, peak_hour_index - hours_before_after)
    smoothing_range_end = min(length(df[!, electric_load_column_name]), peak_hour_index + hours_before_after)
    smoothing_range = smoothing_range_start:smoothing_range_end

    # Extract the load values for the smoothing range
    load_vals = [df[i, electric_load_column_name] for i in smoothing_range]
    smoothed_vals = similar(load_vals)

    # Find the load values at the start and end of the smoothing range
    start_load = df[smoothing_range_start, electric_load_column_name]
    end_load = df[smoothing_range_end, electric_load_column_name]

    # Calculate the coefficients of a quadratic function ax^2 + bx + c
    # that passes through (smoothing_range_start, start_load), (peak_hour_index, target_peak),
    # and (smoothing_range_end, end_load)
    A = [smoothing_range_start^2 smoothing_range_start 1; peak_hour_index^2 peak_hour_index 1; smoothing_range_end^2 smoothing_range_end 1]
    B = [start_load; target_peak; end_load]
    coef = A \ B  # Solve the system of equations to find the coefficients

    # Generate the smoothed values using the quadratic function
    for i in eachindex(smoothing_range)
        hour = smoothing_range[i]
        smoothed_vals[i] = coef[1]*hour^2 + coef[2]*hour + coef[3]
    end

    # Apply the smoothed values, ensuring the peak is preserved
    for (i, hour) in enumerate(smoothing_range)
        df[hour, electric_load_column_name] = smoothed_vals[i]
    end

    # Ensure the peak is set to the target peak
    df[peak_hour_index, electric_load_column_name] = target_peak
end

function is_weekend(df, hour_index, date_column_name)
    date = df[hour_index, date_column_name]
    return Dates.dayofweek(date) in (Dates.Saturday, Dates.Sunday)
end

function apply_scaled_peak_pattern(df, peak_hour_index, electric_load_column_name, scaling_factors, days_before, days_after, date_column_name)
    # Calculate the indices for the entire peak day
    peak_day_start = (peak_hour_index ÷ 24) * 24 + 1
    peak_day_end = peak_day_start + 23

    # Get the adjusted pattern of the peak day
    adjusted_peak_pattern = df[peak_day_start:peak_day_end, electric_load_column_name]

    # Shuffle the indices randomly
    shuffled_indices = Random.shuffle(1:length(scaling_factors))

    # Apply the pattern to adjacent days, skipping weekends
    for i in -days_before:days_after
        day_index = peak_day_start + i * 24
        # Check if the day is within the DataFrame's range
        if day_index >= 1 && day_index + 23 <= size(df, 1)
            # Check if it's not a weekend
            if !is_weekend(df, day_index, date_column_name)
                # Get the scaling factor using the shuffled index
                # Assuming scaling_factors is a 4-element array
                # and you want to cycle through it if the range is larger
                index_for_scaling_factors = mod(i + days_before, length(scaling_factors)) + 1
                scaling_factor = scaling_factors[shuffled_indices[index_for_scaling_factors]]
                scaled_pattern = adjusted_peak_pattern .* scaling_factor
                df[day_index:day_index+23, electric_load_column_name] .= scaled_pattern  # Use .= to broadcast the assignment
            end
        end
    end
end

# Function to redistribute and smooth loads
function redistribute_and_smooth_load(df, peak_hour_index, target_peak, electric_load_column_name, month)
    # Define a reasonable range for redistribution and smoothing
    range_start = max(1, peak_hour_index - 2)
    range_end = min(size(df, 1), peak_hour_index + 2)

    # Calculate excess load to redistribute
    excess_load = df[peak_hour_index, Symbol(electric_load_column_name)] - target_peak

    # Ensure redistribution is within the same day and month
    for i in range_start:range_end
        if df[i, :Month] == month && excess_load > 0
            redistribution_amount = min(excess_load, (target_peak - df[i, Symbol(electric_load_column_name)]) / 2)
            df[i, Symbol(electric_load_column_name)] += redistribution_amount
            excess_load -= redistribution_amount
        end
    end

    # Apply smoothing within the range
    for i in range_start+1:range_end-1
        if df[i, :Month] == month
            df[i, Symbol(electric_load_column_name)] = mean(df[i-1:i+1, Symbol(electric_load_column_name)])
        end
    end
end

# Function to adjust the valleys towards the target consumption
function adjust_valleys(df, electric_load_column_name, monthly_data, comparison_df)
    # Convert the column name to a Symbol
    electric_load_symbol = Symbol(electric_load_column_name)
    
    # Calculate the total annual shortfall
    annual_shortfall = comparison_df[comparison_df[!, :Month] .== 13, :Target_Consumption][1] -
                       comparison_df[comparison_df[!, :Month] .== 13, :Scaled_Total_Consumption][1]

    # Identify potential valleys where adjustments can be made
    valley_indices = filter(i -> df[i, electric_load_symbol] < monthly_data[monthly_data[!, :Month] .== df[i, :Month], :Target_Demand][1],
                             1:size(df, 1))

    # Calculate the adjustment per valley hour
    adjustment_per_valley = annual_shortfall / length(valley_indices)

    # Distribute the shortfall to valleys without exceeding the target demand or creating new peaks
    for idx in valley_indices
        month = df[idx, :Month]
        target_demand = monthly_data[monthly_data[!, :Month] .== month, :Target_Demand][1]
        max_increment = target_demand - df[idx, electric_load_symbol]
        increment = min(adjustment_per_valley, max_increment)
        df[idx, electric_load_symbol] += increment
    end
end

# Function to apply a moving average for smoothing
function smooth_valleys(df, electric_load_column_name, window_size)
    electric_load_symbol = Symbol(electric_load_column_name)
    # Apply the moving average smoothing
    for i in 1:size(df, 1)
        window_start = max(1, i - window_size)
        window_end = min(size(df, 1), i + window_size)
        df[i, electric_load_symbol] = mean(df[window_start:window_end, electric_load_symbol])
    end
end

# Main function to call for adjusting and smoothing the load profile
function adjust_and_smooth_load_profile!(df_8760_original, monthly_targets, comparison_df, electric_load_column_name)
    # Adjust the valleys to distribute the annual shortfall
    adjust_valleys(df_8760_original, electric_load_column_name, monthly_targets, comparison_df)
    
    # Smooth the valleys using a moving average with a specified window size
    window_size = 1 # This can be adjusted based on the size of your valleys
    smooth_valleys(df_8760_original, electric_load_column_name, window_size)
    
    return df_8760_original
end


# Function to prepare the DataFrame with additional columns
function prepare_load_csv(df::DataFrame, start_year::Int, start_month::Int, start_day::Int)
    start_date = Dates.DateTime(start_year, start_month, start_day, 0, 0)
    df[!, :Month] = [Dates.month(start_date + Dates.Hour(h - 1)) for h in df[!, :Hour]]
    df[!, :Week] = [Dates.week(start_date + Dates.Hour(h - 1)) for h in df[!, :Hour]]
    df[!, :DateTime] = [start_date + Dates.Hour(i - 1) for i in 1:size(df, 1)]
    return df
end

export adjust_and_smooth_load_profile!, prepare_load_csv

end
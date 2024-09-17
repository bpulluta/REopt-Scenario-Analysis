function convert_to_shorthand(values::Vector{<:Real})
    shorthand_values =   []

    for value in values
        if abs(value) >=   1e9
            push!(shorthand_values, @sprintf("%.1fB", value / 1e9))
        elseif abs(value) >=   1e6
            push!(shorthand_values, @sprintf("%.1fM", value / 1e6))
        elseif abs(value) >=   1e3
            push!(shorthand_values, @sprintf("%.1fk", value / 1e3))
        else
            push!(shorthand_values, @sprintf("%d", value))
        end
    end

    return shorthand_values
end

function create_plot(columns, json_file::AbstractString, selected_scenarios::AbstractVector{Int})
    # Read the JSON file and parse the data
    data =   JSON.parsefile(json_file)

    function clean_value(x::String)
        if x == "-"
            return Int64(0)
        end
        
        try
            return Int64(ceil(parse(Float64, x)))
        catch e
            @warn "Failed to convert and round string to Int64" x exception=e
            return Int64(0)  # Or some other default value
        end
    end
    
    # Extract relevant data
    scenarios =   data["columns"][1][1:end]

    # Trim scenario names to get labels like "1A", "1B", etc.
    scenarios = [split(s, ".")[1] for s in scenarios]

    # Extract and clean data for selected scenarios
    column_names =   collect(keys(columns))

    # Function to replace "-" with 0.0 and convert to Int
    clean_value(x) =   x ==   "-" ? 0.0 : round(Float64(x)) |> Int64

    selected_data = OrderedDict{String, Vector}()
    for (column, index) in columns
        if column == "Microgrid LCOE"
            selected_data[column] = data["columns"][index][selected_scenarios]
        else
            selected_data[column] = map(clean_value, data["columns"][index][selected_scenarios])
        end
    end

    # Create DataFrame with specified column order
    data =   DataFrame([selected_data[column] for column in column_names], column_names)

    x =   scenarios[selected_scenarios]

    tech_color_dict = Dict(
        "PV Size (kW-DC)" =>  "#f8bc05",
        "PV-Existing Size (kW-DC)" =>  "#f8bc05",
        "PV-138kW Size (kW-DC)" =>  "#ffbb33",
        "PV-Roof Size (kW-DC)" =>  "#e59400",
        "PV-New Size (kW-DC)" =>  "#e5e500",
        "Battery Size (kW)" =>  "#bc05f8",
        "Battery Capacity (kWh)" =>  "#eab4fc",
        "Current Gen. Capacity (kW)" =>  "#006666", 
        "Add-on Gen. Capacity (kW)" =>  "#33cccc",  
        "Wind Size (kW)" =>  "#0541f8",  
        "CHP Size(kW)" =>  "#41f805",
        "GHP Size(kW)" =>  "#f80541"
    )
    
    transp_value =   0.6
    fsize        =   26

    columns_to_check = Dict{String, Int}()

    # Extract keys from the OrderedDict
    column_keys = keys(columns) |> collect

    # Filter column keys based on "kW" or "kWh"
    kw_columns = filter(col -> occursin("kW", col), column_keys)

    # Determine the threshold dynamically
    threshold = length(kw_columns)+1

    for (column, index) in columns
        if index <= threshold  #needs to be updated based on the techs analized
            columns_to_check[column] = index
        end
    end
    
    # Check if the columns are all zeros
    all_zeros_dict = Dict()
    for (column, index) in columns_to_check
        all_zeros_dict[column] = all(v -> v == 0, data[!, column])
    end
    
    # Create PlotlyJS traces for main plot
    main_data_traces = GenericTrace[]
    y_values_dict = []
    
    for (column, index) in columns
        if index > threshold  #needs to be updated based on the techs analized
            continue
        end
    
        # Skip columns with all zeros based on our dictionary
        if all_zeros_dict[column]
            continue
        end
        
        # Determine the unit based on the column name
        unit = if occursin("kWhf", column)
            " kWh"
        elseif occursin("kWf", column)
            " kW"
        else
            ""
        end

        # Append the unit to the value labels
        value_labels = [value > 0 ? string(value, unit) : "" for value in data[:, column]]

        # Determine text positions based on bar height
        threshold_height = 20  # Adjust this value as needed
        text_positions = [value > threshold_height ? "inside" : "outside" for value in data[:, column]]

        texture = column == "Battery (kWh)" ? "x" : "none"

        trace = PlotlyJS.bar(
            x      =   x,
            y      =   [value > 0 ? value : nothing for value in data[:, column]],
            name   =   column,
            marker =   attr(
                opacity =   transp_value,
                color   =   tech_color_dict[column],
            ),
            marker_pattern_shape =   texture,
            text                 =   value_labels,
            textposition         =   "outside",  # Use the conditional text positions
            # textangle            =   270,  # Rotate labels to make them vertical
            textfont             =   attr(size = fsize-10, family = "Arial"),  # Increase font size
            # width                =   0.15  # Adjusted the width of the bars
        )
                push!(main_data_traces, trace)
        # Push the y values to the dictionary
        push!(y_values_dict, column => trace.y)
    end

    # Create separate NPV plot
    npv_plot = PlotlyJS.bar(
        x            =   x,
        y            =   data[:, "Net Present Value (\$)"],  # Corrected column name
        name         =   "Net Present Value",
        text         =   convert_to_shorthand(data[:, "Net Present Value (\$)"]),  # Corrected column name
        textposition =   "outside",
        textfont     =   attr(size = fsize, family = "Arial"),
        width        =   0.8,
        marker       =   attr(
            opacity =   transp_value, # Adjust opacity (transparency) here
            color   =   "#00ffa7" # Set desired color
        ),
    )
    # Create separate Payback Period plot
    pb_plot = PlotlyJS.bar(
        x            =   x,
        y            =   data[:, "Payback Period (Years)"],  # Corrected column name
        name         =   "Payback Period",
        text         =   map(x -> x == 0 ? "N/A" : string(x), data[:, "Payback Period (Years)"]),  # Corrected column name
        textposition =   "outside",
        textfont     =   attr(size = fsize, family = "Arial"),
        width        =   0.8,
        marker       =   attr(
            opacity =   transp_value, # Adjust opacity (transparency) here
            color   =   "#11ccdc"  # Set desired color
        )
    )

    # Create separate Emission Reduction Percentage plot
    emission_plot = PlotlyJS.bar(
        x            =   x,
        y            =   data[:, "Lifecycle CO2 Reduction (%)"],  # Assuming this is the correct column name
        name         =   "Emission Reduction",
        text         =   data[:, "Lifecycle CO2 Reduction (%)"],  # Assuming this is the correct column name
        textposition =   "outside",
        textfont     =   attr(size = fsize, family = "Arial"),
        width        =   0.8,
        marker       =   attr(
            opacity =   transp_value, # Adjust opacity (transparency) here
            color   =   "#fec9af"  # Set desired color
        )
    )


    # Create separate Net Capital Cost plot
    capcost_plot = PlotlyJS.bar(
        x            =   x,
        y            =   data[:, "Net Capital Cost (\$)"],  # Corrected column name
        name         =   "Net Capital Cost",
        text         =   convert_to_shorthand(data[:, "Net Capital Cost (\$)"]),  # Corrected column name
        textposition =   "outside",
        textfont     =   attr(size = fsize, family = "Arial"),
        width        =   0.8,
        marker       =   attr(
            opacity =   transp_value, # Adjust opacity (transparency) here
            color   =   "#344b46"  # Set desired color
        )
    )

    # Create separate MG LCOE plot
    lcoe_plot = PlotlyJS.bar(
        x            =   x,
        y            =   map(x -> parse(Float64, x), data[:, "Microgrid LCOE"]),  # Corrected column name
        name         =   "Microgrid LCOE",
        text         =   data[:, "Microgrid LCOE"],  # Corrected column name
        textposition =   "outside",
        textfont     =   attr(size = fsize, family = "Arial"),
        width        =   0.8,
        marker       =   attr(
            opacity =   transp_value, # Adjust opacity (transparency) here
            color   =   "#cbdc11"  # Set desired color
        )
    )

    layout = Layout(
        xaxis = attr(
            title = attr(  # Add this block
                text = "Scenario",  # X-axis label text
                font = attr(size = fsize, family= "Arial", color="black", style="bold"),
            ),
            titlefont = attr(size = fsize, family= "Arial", color="black", style="bold"),
            tickfont = attr(size = fsize, family = "Arial"),
            showgrid  =   false,                    
            showline  =   true,                     
            linecolor =   "black",                  
            linewidth =   2,
            ticks = "outside"
        ),
        yaxis = attr(
            showgrid  =   true,
            linecolor =   "black",
            linewidth =   2,
            gridcolor =   "rgba(128, 128, 128, 0.1)",
            gridwidth =   2,
            ticks = "outside"
        ),
        barmode         =   "group",
        bargap          =   -0.5,
        bargroupgap     =   0.05,
        xaxis_tickangle =   -45,
        legend = attr(
            x=0.5,
            y=0.80,
            xanchor="center",
            yanchor="bottom",
            bgcolor="rgba(255, 255, 255, 0.5)",
            bordercolor="rgba(51, 51, 51, 0.5)",
            font=attr(
                family="Arial",
                size=fsize-8,
                color="black"
            ),
            borderwidth=1,
            traceorder="normal",
            itemsizing="constant",
            xgap=10,
            orientation="h"
        ),
        paper_bgcolor =   "white",
        plot_bgcolor  =   "white",
        font_family   =   "Arial, sans-serif",
        font_color    =   "#333333",
        margin = attr(l = 50, r = 50, t = 100, b = 50)
    )
    
    return main_data_traces, npv_plot, pb_plot, emission_plot, capcost_plot, lcoe_plot, layout, y_values_dict, data
end

function create_general_plots(site::String, 
                              json_file::String, 
                              columns::OrderedDict, 
                              selected_scenarios::Vector{Int}, 
                              results_dir::String,
                              case::String)
    
    # Ensure the plots directory exists
    mkpath(joinpath(results_dir, "barplots"))
    
    main, npv, pb, er, cap, lcoe,layout, tech_values, df = create_plot(columns, json_file, selected_scenarios)

    values_array = hcat(values(tech_values)...)
    vals = [v for (_, v) in values_array]
    replaced_matrix = [[x === nothing ? 0 : x for x in vec] for vec in vals]
    vals2 = collect(Iterators.flatten(replaced_matrix))

    # Calculate the maximum and minimum of the Int64 values
    tech_max = maximum(vals2)

    fsize = 26
    title_size = fsize

    function calc_axis_range(; column_name, df, padding_factor=1.5, start_at_zero=false)
        vals = values(df[:, column_name])
        
        # Separate out positive and negative values
        pos_vals = filter(x -> x > 0, vals)
        neg_vals = filter(x -> x < 0, vals)
        
        pos_range = isempty(pos_vals) ? 0.0 : maximum(pos_vals)
        neg_range = isempty(neg_vals) ? 0.0 : abs(minimum(neg_vals))
    
        # Adjust the padding factor based on magnitude
        pos_padding_factor = padding_factor
        neg_padding_factor = padding_factor
    
        if pos_range > 1e6
            pos_padding_factor = 1.25
        elseif pos_range < 2000
            pos_padding_factor = 4.5
        end
    
        if neg_range < -1e6
            neg_padding_factor = 1.25
        elseif neg_range > -2000
            neg_padding_factor = 4.5
        end
        
        # Decide the max value for the y-axis by taking the larger of the two: 
        # padded positive max or padded negative max (in absolute value)
        max_val = max(pos_range * pos_padding_factor, neg_range * neg_padding_factor)
        min_val = -max_val  # symmetric y-axis
    
        if start_at_zero
            min_val = 0
        end
    
        return [min_val, max_val]
    end

    function create_subplot_layout(layout, title, yaxis_title, yaxis_range, fsize, title_x=0.5)
        new_layout = deepcopy(layout)
        new_layout.yaxis = attr(
            title=attr(text=yaxis_title), 
            titlefont=attr(size=fsize, family="Arial", color="black", style="bold"),
            tickfont=attr(size=fsize, family="Arial"),
            range=yaxis_range
        )
        new_layout.annotations = [
                attr(
                    x=0.5,  # Center the legend
                    y=1.15,  # Lower the legend to prevent overlap
                    xref="x domain",
                    yref="y domain",
                    bgcolor="rgb(211, 214, 216)",  # Semi-transparent background
                    text="     $title     ",
                    showarrow=false,
                    align="top",
                    bordercolor="rgb(211, 214, 216)",
                    font=attr(
                        family="Arial",
                        size=fsize+6,  # Consider reducing the font size if it's still too large
                        color="black"
                    ),
                    borderwidth=5,)
        ]

        new_layout.title_x = title_x
        
        return new_layout
    end
    
    # Define common sizes for all subplots here
    common_width = 400
    common_height = 600
    common_fsize = fsize # This should be defined based on your desired font size for the axis
        
    # Use the function to create each layout
    layout_p1 = create_subplot_layout(layout, "System Sizing", "Power (kW)", [0, tech_max*1.5], common_fsize)
    layout_p2 = create_subplot_layout(layout, "Net Present Value", "\$", calc_axis_range(column_name="Net Present Value (\$)", df=df), common_fsize)
    layout_p3 = create_subplot_layout(layout, "Payback Period", "Years", [0, 30], common_fsize)
    layout_p4 = create_subplot_layout(layout, "Emissions Reduction", "Percent", [0, 120], common_fsize)
    layout_p5 = create_subplot_layout(layout, "Net Capital Cost", "\$", calc_axis_range(column_name="Net Capital Cost (\$)", df=df, start_at_zero=true), common_fsize)
    layout_p6 = create_subplot_layout(layout, "Microgrid LCOE", "\$/kWh", [0,1], common_fsize)

    

    # Create subplots with modified layouts
    p1 = PlotlyJS.plot(main, layout_p1)
    p2 = PlotlyJS.plot(npv, layout_p2)
    p3 = PlotlyJS.plot(pb, layout_p3)
    p4 = PlotlyJS.plot(er, layout_p4)
    p5 = PlotlyJS.plot(cap, layout_p5)
    p6 = PlotlyJS.plot(lcoe, layout_p6)


    # Save plots to the plots subdirectory within the results directory
    PlotlyJS.savefig(p1, joinpath(results_dir, "barplots", "$case-$site-tech_size.html"))
    PlotlyJS.savefig(p1, joinpath(results_dir, "barplots", "$case-$site-tech_size.png"),width=common_width*2, height=common_height)

    PlotlyJS.savefig(p2, joinpath(results_dir, "barplots", "$case-$site-npv.html"))
    PlotlyJS.savefig(p2, joinpath(results_dir, "barplots", "$case-$site-npv.png"),width=common_width, height=common_height)

    PlotlyJS.savefig(p3, joinpath(results_dir, "barplots", "$case-$site-payback.html"))
    PlotlyJS.savefig(p3, joinpath(results_dir, "barplots", "$case-$site-payback.png"),width=common_width, height=common_height)

    PlotlyJS.savefig(p4, joinpath(results_dir, "barplots", "$case-$site-er.html"))
    PlotlyJS.savefig(p4, joinpath(results_dir, "barplots", "$case-$site-er.png"),width=common_width, height=common_height)

    PlotlyJS.savefig(p5, joinpath(results_dir, "barplots", "$case-$site-capcost.html"))
    PlotlyJS.savefig(p5, joinpath(results_dir, "barplots", "$case-$site-capcost.png"),width=common_width, height=common_height)

    PlotlyJS.savefig(p6, joinpath(results_dir, "barplots", "$case-$site-mg-lcoe.html"))
    PlotlyJS.savefig(p6, joinpath(results_dir, "barplots", "$case-$site-mg-lcoe.png"),width=common_width, height=common_height)
end


function plot_bar_charts(base_dir::String, site::String, selected_scenarios, case::String, desired_columns::Vector{String})
    # Construct paths based on base directory, site name, and case
    json_file = joinpath(base_dir, "Results-$case-$site.json")
    results_dir = joinpath(base_dir)

    # Load the JSON data to extract the column indices
    data = JSON.parsefile(json_file)
    lookup = data["colindex"]["lookup"]

    if isempty(selected_scenarios)
        num_scenarios = length(all_scenarios[case])
        selected_scenarios = collect(2:num_scenarios) # Generate scenarios starting from 2
    end
    

    # Create the OrderedDict with column names and their corresponding indices
    columns = OrderedDict((column => lookup[column]) for column in desired_columns if haskey(lookup, column))

    # Call the function to create general plots
    create_general_plots(site, json_file, columns, selected_scenarios, results_dir, case)
end

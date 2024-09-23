###REoptPlots
function plot_electric_dispatch(d::Dict; title ="Electric Systems Dispatch", save_html=true, display_stats=false, year=2023, save_dispatch_data=false)
	# Check for special case
	is_special_case = check_special_case(d)

	if is_special_case
		eload = d["ElectricUtility"]["electric_to_load_series_kw_bau"]
		y_max   =   round(maximum(eload))*1.8
	else
		# eload = d["ElectricLoad"]["load_series_kw"]
		# # Flatten dictionary and extract dat
		# df_stat =   flatten_dict(d)
		# load    =   get(df_stat,"ElectricUtility.electric_to_load_series_kw_bau","-")
		# y_max   =   round(maximum(load))*1.8
		# Extract load series from the dictionary
		eload = d["ElectricLoad"]["load_series_kw"]

		# Flatten dictionary and extract data
		df_stat = flatten_dict(d)

		# Attempt to get the load data
		load = get(df_stat, "ElectricUtility.electric_to_load_series_kw_bau", nothing)

		# Check if load is a valid numeric array, otherwise use eload
		if !isa(load, AbstractArray) || isempty(load)
			load = eload
		end

		# Calculate y_max
		y_max = round(maximum(load)) * 1.8

		# Check if y_max is zero and adjust if necessary
		if y_max == 0
			y_max_alternative = round(maximum(eload)) * 1.8
			y_max = max(y_max, y_max_alternative)
		end
	end
	
    # Initialize traces and layout for plotting
    traces =   GenericTrace[]
    layout =   Layout(
        width            =   1280,
        height           =   720,
        hovermode        =   "closest",
        hoverlabel_align =   "left",
        plot_bgcolor     =   "white",
        paper_bgcolor    =   "white",
        font_size        =   18,
        xaxis            =   attr(showline=true, ticks="outside", showgrid=true,
            gridcolor =   "rgba(128, 128, 128, 0.2)", griddash =   "dot",
            linewidth =   1.5,                        zeroline =   false),
        yaxis=attr(showline=true, ticks="outside", showgrid=true,
            gridcolor =   "rgba(128, 128, 128, 0.2)", griddash =   "dot",
            linewidth =   1.5,                        zeroline =   false, range =   [0, y_max]),
		title                     =   title,
		xaxis_title               =   "",
		yaxis_title               =   "Power Demand (kW)",
		xaxis_rangeslider_visible =   true,
		legend                    =   attr(x=1.0, y=1.0, xanchor="right", yanchor="top", font=attr(size=14,color="black"),
		bgcolor="rgba(255, 255, 255, 0.5)", bordercolor="rgba(128, 128, 128, 0.2)", borderwidth=1),
				)
    

    #Define year
    year =   year

    # Define the start and end time for the date and time array
    start_time =   DateTime(year, 1, 1, 0, 0, 0)
    end_time   =   DateTime(year+1, 1, 1, 0, 0, 0)

    # Create the date and time array with the specified time interval
    dr   =   start_time:check_time_interval(eload):end_time
    dr_v =   collect(dr)


    #remove the last value of the array to match array sizes
    pop!(dr_v)


    ### REopt Data Plotting Begins
    ### Total Electric Load Line Plot
	if is_special_case
		# Special case plotting logic here
		electric_to_load_series_kw_bau = d["ElectricUtility"]["electric_to_load_series_kw_bau"]

		push!(traces, scatter(
			name = "Grid Serving Load (BAU)",
			x    = dr_v,  # Assuming dr_v is defined
			y    = electric_to_load_series_kw_bau,  # Assuming this is defined
			mode = "lines",
			fill = "tozeroy",
			line = attr(width=0.5, color="#0B5E90"),  # Visible line width
			# fillcolor = "rgba(11, 94, 144, 0.3)"  # Lighter shade of the line color with reduced opacity
		))

	else
        push!(traces, scatter(;
            name =   "Total Electric Load",
            x    =   dr_v,
            y    =   d["ElectricLoad"]["load_series_kw"],
            mode =   "lines",
            fill =   "none",
            line =   attr(width=1, color="#0B5E90")
        ))

        dispatch_data =   DataFrame(column1 = String[], column2 = Vector{Any}[])
        push!(dispatch_data,["Date",dr_v])
        push!(dispatch_data,["Total Electric Load",d["ElectricLoad"]["load_series_kw"]])

        ### Grid to Load Plot
        push!(traces, scatter(;
            name =   "Grid Serving Load",
            x    =   dr_v,
            y    =   d["ElectricUtility"]["electric_to_load_series_kw"],
            mode =   "lines",
            fill =   "tozeroy",
            line =   attr(width=0, color="#0B5E90")
        ))
        push!(dispatch_data,["Grid Serving Load",d["ElectricUtility"]["electric_to_load_series_kw"]])
		tech_color_dict = Dict(
			"PV" => "#ffbb00",  # Bright yellow-orange for PV
			"ElectricStorage" => "#ff66ff",  # Bright pink for Electric Storage
			"Generator" => "#ff552b",  # Bright red-orange for Generator
			"Wind" => "#1a75ff",  # Blue for Wind
			"CHP" => "#74c476",  # Light green for CHP
			"GHP" => "#ffcc99",  # Peach for GHP
		)
		
		tech_names = ["PV", "ElectricStorage", "Generator", "Wind", "CHP", "GHP"]
		
		net_tech_color_dict = Dict(
			"PV" => "#664a00",  # A different shade of orange for net metering PV
			"Wind" => "#0d3a7f"  # Teal for net metering Wind, distinct from its primary color
		)
		
        # tech_color_dict     = Dict("PV" => "#ffbb00", "ElectricStorage" => "#e604b3", "Generator" => "#ff552b", "Wind" => "#70ce57", "CHP" => "#33783f", "GHP" => "#52e9e6")
        # tech_names  	    = ["PV","ElectricStorage","Generator","Wind","CHP","GHP"]
        # net_tech_color_dict = Dict("PV" => "#5a1b00", "Wind" => "#003a00")
        gradient_colors     = []
        gradient_net_colors = []
        #Plot every existing technology
        cumulative_data = zeros(length(dr_v))
        cumulative_data = cumulative_data .+ d["ElectricUtility"]["electric_to_load_series_kw"]
    #################################################################
    ########################### Main loop ###########################
    
		for tech in tech_names
			already_plotted = false
			if haskey(d, tech)
				# Check the type of d[tech]
				if typeof(d[tech]) == Dict{String, Any}
					d[tech] = [d[tech]] 
				end

				if tech == "ElectricStorage"
					# Existing logic for Electric Storage
					new_data = d[tech][1]["storage_to_load_series_kw"]
					# println(new_data) 
					if isempty(new_data)
						# println("Data is empty")
						continue
					end
					### Battery SOC line plot
					push!(traces, scatter(
						name = tech * " State of Charge",
						x = dr_v,
						y = d["ElectricStorage"][1]["soc_series_fraction"] * 100,
						yaxis="y2",
						line = attr(
						dash= "dashdot",
						width = 1
						),
						marker = attr(
							color="rgb(100,100,100)"
						),
					))
					push!(dispatch_data,[tech * " State of Charge",new_data])
					layout = Layout(
						hovermode="closest",
						hoverlabel_align="left",
						plot_bgcolor="white",
						paper_bgcolor="white",
						font_size=18,
						xaxis=attr(showline=true, ticks="outside", showgrid=true,
							gridcolor="rgba(128, 128, 128, 0.2)",griddash= "dot",
							linewidth=1.5, zeroline=false),
						yaxis=attr(showline=true, ticks="outside", showgrid=true,
							gridcolor="rgba(128, 128, 128, 0.2)",griddash= "dot",
							linewidth=1.5, zeroline=false, range = [0, y_max]),

						xaxis_title = "",
						yaxis_title = "Power Demand (kW)",
						xaxis_rangeslider_visible=true,
						legend=attr(x=1.0, y=1.0, xanchor="right", yanchor="top", font=attr(size=14,color="black"),
						bgcolor="rgba(255, 255, 255, 0.5)", bordercolor="rgba(128, 128, 128, 0.2)", borderwidth=1),
							yaxis2 = attr(
							title = "State of Charge (Percent)",
							overlaying = "y",
							side = "right",
							range = [0, 100]
						))

				elseif tech == "PV" || tech == "Wind"
					for (idx, instance) in enumerate(d[tech])
						# Now instance will always be a Dict{String, Any}, not a Pair{String, Any}
						new_data = instance["electric_to_load_series_kw"]
						instance_name = get(instance, "name", tech)
						# Only append instance_name if it's different from tech
						full_name = tech

						if instance_name != tech
							full_name *= '-' * instance_name
						end

						if length(d[tech]) > 1
							if idx == 1
								gradient_colors = generate_gradient(tech_color_dict[tech], length(d[tech]))
							end
							color_to_use = gradient_colors[idx]
						else
							color_to_use = tech_color_dict[tech]
						end

						if any(x -> x > 0, new_data)
							# Invisible line for plotting
							push!(traces, scatter(
								name = "invisible",
								x = dr_v,
								y = cumulative_data,
								mode = "lines",
								fill = Nothing,
								line = attr(width = 0),
								showlegend = false,
								hoverinfo = "skip"
							))

							cumulative_data = cumulative_data .+ new_data

							# Plot each instance
							push!(traces, scatter(
								name = full_name * " Serving Load",
								x = dr_v,
								y = cumulative_data,
								mode = "lines",
								fill = "tonexty",
								line = attr(width=0, color = color_to_use)
							))
						end
						push!(dispatch_data,[full_name * " Serving Load",new_data])
						# After plotting, set the flag to true
						already_plotted = true
					end

				else
					new_data = d[tech][1]["electric_to_load_series_kw"]
				end
					
				if !already_plotted && any(x -> x > 0, new_data)
					# Invisible line for plotting
					push!(traces, scatter(
						name = "invisible",
						x = dr_v,
						y = cumulative_data,
						mode = "lines",
						fill = Nothing,
						line = attr(width = 0),
						showlegend = false,
						hoverinfo = "skip"
					))

					cumulative_data = cumulative_data .+ new_data

					# Plot each technology
					push!(traces, scatter(
						name = tech * " Serving Load",
						x = dr_v,
						y = cumulative_data,
						mode = "lines",
						fill = "tonexty",
						line = attr(width=0, color = tech_color_dict[tech])
					))

					push!(dispatch_data,[tech * " Serving Load",new_data])
				end
			end
		end
    #################################################################
    ########################### Net Metering Enabled ################
		for tech in tech_names
			if haskey(d, tech)

				# Check the type of d[tech]
				if typeof(d[tech]) == Dict{String, Any}
					d[tech] = [d[tech]]  # If it's a single dictionary, convert it to an array containing that dictionary
				end

				if tech == "PV" || tech == "Wind"  # Special handling for net metering PV and Wind, can add additional like this || tech == "CHP"
					for (idx, instance) in enumerate(d[tech])
						new_data = instance["electric_to_grid_series_kw"]
						instance_name = get(instance, "name", tech)  # Default to 'tech' if 'name' is not present
						# Only append instance_name if it's different from tech
						full_name = tech
						if instance_name != tech
							full_name *= '-' * instance_name
						end
						if length(d[tech]) > 1  # Multiple instances
							if idx == 1  # First instance, use base color
								color_to_use = net_tech_color_dict[tech]
							else  # Other instances, use gradient
								if idx == 2  # Generate gradient colors only when you reach the second instance
									gradient_net_colors = generate_gradient(net_tech_color_dict[tech], length(d[tech]) - 1)  # One fewer than the number of instances
								end
								color_to_use = gradient_net_colors[idx - 1]  # Use idx - 1 because gradient starts from the second instance
							end
						else  # Single instance
							color_to_use = net_tech_color_dict[tech]
						end

						if any(x -> x > 0, new_data)
							# Invisible line for plotting
							push!(traces, scatter(
								name = "invisible",
								x = dr_v,
								y = cumulative_data,
								mode = "lines",
								fill = Nothing,
								line = attr(width = 0),
								showlegend = false,
								hoverinfo = "skip"
							))

							cumulative_data = cumulative_data .+ new_data

							# Plot each instance exporting to the grid
							push!(traces, scatter(
								name = full_name * " Exporting to Grid (NEM)",
								x = dr_v,
								y = cumulative_data,
								mode = "lines",
								fill = "tonexty",
								line = attr(width=0, color = color_to_use)
							))
							push!(dispatch_data,[full_name * " Exporting to Grid (NEM)",new_data])
						end
					end
				end
			end
		end
	end
    #################################################################
    ########################### End Main loop #######################
    #################################################################
 	# Plot the minimum, maximum, and average power values.
	if display_stats
		###Plot Stats
		avg_val =   round(mean(eload),digits=0)
		max_val =   round(maximum(eload),digits=0)
		min_val =   round(minimum(eload),digits=0)

		x_stat  =   [first(dr_v),dr_v[end-100]]
		y_stat1 =   [min_val,min_val]
		y_stat2 =   [max_val,max_val]
		y_stat3 =   [avg_val,avg_val]


		push!(traces, scatter(
		x           =   x_stat,
		y           =   y_stat1,
		showlegend  =   false,
		legendgroup =   "group2",
		line        =   attr(color="grey", width=1.5,
								dash="dot"),
		mode         =   "lines+text",
		name         =   String("Min = $(min_val) kW"),
		text         =   [String("Min = $(min_val) kW")],
		textposition =   "Top left"
			)
		)

		push!(traces, scatter(
		x           =   x_stat,
		y           =   y_stat2,
		showlegend  =   false,
		legendgroup =   "group2",
		line        =   attr(color="grey", width=1.5,
								dash="dot"),
		mode         =   "lines+text",
		name         =   String("Max = $(max_val) kW"),
		text         =   [String("Max = $(max_val) kW")],
		textposition =   "Top left"
			)
		)

		push!(traces, scatter(
		x           =   x_stat,
		y           =   y_stat3,
		showlegend  =   false,
		legendgroup =   "group2",
		line        =   attr(color="grey", width=1.5,
								dash="dot"),
		mode         =   "lines+text",
		name         =   String("Avg = $(avg_val) kW"),
		text         =   [String("Avg = $(avg_val) kW")],
		textposition =   "Top left"
				)
		)
	end

	p =   plot(traces, layout)

	if save_html
		savefig(p, replace(title, " " => "_") * ".html")
	end

	# Save dispatch data as CSV and JSON if enabled
	if save_dispatch_data && !is_special_case
		# Extract the column names
		columnNames =   dispatch_data[!,"column1"]
		# Extract the column values
		columnValues =   dispatch_data[!,"column2"]
		# Transpose the data
		rowData =   hcat(columnValues...)
		# Create a DataFrame with column names
		df =   DataFrame(rowData, Symbol.(columnNames))

		# Save the DataFrame to a CSV file
		CSV.write("$title-dispatch.csv", df)
		# JSON3.write("$title-dispatch.json",df)
	end

	# Final rendering of the plot
	plot(traces, layout)  # will not produce plot in a loop
end

function generate_gradient(base_color, num_colors, dark_factor=0.5)  # Add a parameter for darkening factor, defaulting to 0.5
    # Base color in RGB form
    r, g, b = parse(Int, base_color[2:3], base=16), parse(Int, base_color[4:5], base=16), parse(Int, base_color[6:7], base=16)
    
    # Calculate a darker shade of the base color
    r_dark, g_dark, b_dark = round(Int, r * dark_factor), round(Int, g * dark_factor), round(Int, b * dark_factor)
    
    # Generate gradient colors
    gradient_colors = []
    for i in 1:num_colors
        factor = i / num_colors
        new_r = round(Int, r * (1 - factor) + r_dark * factor)
        new_g = round(Int, g * (1 - factor) + g_dark * factor)
        new_b = round(Int, b * (1 - factor) + b_dark * factor)
        # Ensure the color values are within bounds and formatted correctly
        new_r = max(min(new_r, 255), 0)
        new_g = max(min(new_g, 255), 0)
        new_b = max(min(new_b, 255), 0)
        push!(gradient_colors, string("#", string(new_r, base=16, pad=2), string(new_g, base=16, pad=2), string(new_b, base=16, pad=2)))
    end
    return gradient_colors
end


function plot_thermal_dispatch(d::Dict; title="Thermal Systems Dispatch", save_html=true, year=2022)
    # Check for the presence of required data
    if !haskey(d, "ExistingBoiler") || !haskey(d, "HeatingLoad")
        println("Required thermal data not found, skipping thermal dispatch plot.")
        return
    end

    # Extract thermal load data
    base_load = d["HeatingLoad"]["total_heating_thermal_load_series_mmbtu_per_hour"]

    # Define the year and date range for plotting
    start_time = DateTime(year, 1, 1, 0, 0, 0)
    end_time = DateTime(year+1, 1, 1, 0, 0, 0)
    dr = start_time:check_time_interval(base_load):end_time
    dr_v = collect(dr)
    pop!(dr_v)  # Match array sizes

    # Initialize traces and layout for plotting
    traces = GenericTrace[]
    y_max = round(maximum(base_load)) * 1.2
    layout = Layout(
        width=1280, height=720, hovermode="closest", hoverlabel_align="left",
        plot_bgcolor="white", paper_bgcolor="white", font_size=18,
        xaxis=attr(showline=true, ticks="outside", showgrid=true,
            gridcolor="rgba(128, 128, 128, 0.2)", griddash="dot", linewidth=1.5, zeroline=false),
        yaxis=attr(showline=true, ticks="outside", showgrid=true,
            gridcolor="rgba(128, 128, 128, 0.2)", griddash="dot", linewidth=1.5, zeroline=false, range=[0, y_max]),
        title=title, xaxis_title="", yaxis_title="Thermal Load (MMBtu/h)", xaxis_rangeslider_visible=true,
        legend=attr(x=1.0, y=1.0, xanchor="right", yanchor="top", font=attr(size=14, color="black"),
            bgcolor="rgba(255, 255, 255, 0.5)", bordercolor="rgba(128, 128, 128, 0.2)", borderwidth=1)
    )

    # Plot total heating load
    push!(traces, scatter(x=dr_v, y=base_load, mode="lines", name="Total Heating Load", line=attr(color="#003f5c")))

    if haskey(d, "CHP")
        chp_data = d["CHP"]

        # Initialize an empty array for CHP values
        chp_thermal_vals = []

        if isa(chp_data, Array)
            # Loop through each dictionary in the array
            for item in chp_data
                if haskey(item, "thermal_to_load_series_mmbtu_per_hour")
                    # Convert DenseAxisArray to standard array before appending
                    thermal_vals = collect(item["thermal_to_load_series_mmbtu_per_hour"])
                    append!(chp_thermal_vals, thermal_vals)
                end
            end
        elseif isa(chp_data, Dict) && haskey(chp_data, "thermal_to_load_series_mmbtu_per_hour")
            # Convert DenseAxisArray to standard array
            chp_thermal_vals = collect(chp_data["thermal_to_load_series_mmbtu_per_hour"])
        end

        if !isempty(chp_thermal_vals)
            cumulative_chp = chp_thermal_vals
            push!(traces, scatter(x=dr_v, y=cumulative_chp, mode="lines", fill="tozeroy", name="CHP Contribution", line=attr(width=0), fillcolor="rgba(255,85,43,0.5)"))
        else
            cumulative_chp = zeros(length(dr_v))
        end
    else
        cumulative_chp = zeros(length(dr_v))
    end


    # Extract Boiler Contribution and plot on top of CHP Contribution
    boiler_thermal_vals = d["ExistingBoiler"]["thermal_to_load_series_mmbtu_per_hour"]
    cumulative_boiler = cumulative_chp .+ boiler_thermal_vals
    push!(traces, scatter(x=dr_v, y=cumulative_boiler, mode="lines", fill="tonexty", name="Boiler Contribution", line=attr(width=0), fillcolor="rgba(112,206,87,0.5)"))

    # Final rendering of the plot
    p = plot(traces, layout)

    if save_html
        savefig(p, replace(title, " " => "_") * ".html")
    end

    return p
end

# This function creates a plot of the resilience duration by hour of the year for a given scenario.
###Outage Plotting
function create_outage_plot(results_dict::Dict{String, Any},filename::AbstractString)
	
    nested_dict = results_dict["outage_sim_res"]

    resilience_dict  = nested_dict["resilience_by_time_step"]
    prob_dict        = nested_dict["probs_of_surviving"] * 100
    og_critical_load = results_dict["ElectricLoad"]["critical_load_series_kw"]
	
	if isempty(resilience_dict) || isempty(og_critical_load)
		# Handle the case where one or both arrays are empty. 
		# Maybe set scaling_factor to a default value or throw a more descriptive error.
		scaling_factor = 1.0  # or some other default value or handling logic
	else
		scaling_factor = maximum(resilience_dict) / maximum(og_critical_load)
	end
		critical_load    =   og_critical_load .* (scaling_factor/5)


	start_date =   DateTime("2022-01-01T00:00:00")
	dates      =   [start_date + Hour(i-1) for i in 1:8760]
    
	avg_res =   round(mean(resilience_dict))
	y_avg   =   fill(avg_res, length(dates))

	# Calculate a 7-day (168-hour) moving average for resilience
	resilience_values =   collect(values(resilience_dict))
	moving_avg        =   [ mean(resilience_values[max(1, i-167):i]) for i in 1:length(resilience_values) ]
	
	trace_a = scatter(x=dates, y=resilience_values,    
				marker =   attr(size=2),
				mode   =   "lines",
				name   =   "Resilience by Time Step",
				line   =   attr(width=2, color="#cccccc"),
				legendgroup="Others"
			)
	
	trace_b = scatter(x=dates, y=y_avg, 
				name =   "Avg. Duration = $(avg_res) Hours",
				line =   attr(color="black", width=2, dash="dot"),
				mode =   "lines",
				legendgroup="Others"
			)
		
	# Modified critical load trace to make it fainter
	trace_c = scatter(x=dates, y=critical_load, 
            name   =   "Scaled Critical Load (kW)",
            marker =   attr(size=2),
            mode   =   "lines",
            line   =   attr(color="rgba(106,61,154, 0.2)", width=2),
			legendgroup="Others"  # Made the color more transparent and line thinner
			)

	# Add moving average trace
	trace_d = scatter(x=dates, y=moving_avg, 
				name =   "7-day Moving Avg.",
				line =   attr(color="#1f78b4", width=2),
				mode =   "lines",
				legendgroup="Others"
			)

	# Create the first plot (trace1)
	layout1 = Layout(
		title="Resilience Duration by Hour of the Year",
		yaxis_title="Outage Survival Duration (Hours)",
		xaxis=attr(showline=true, ticks="outside", showgrid=true,
				gridcolor="rgba(200, 200, 200, 0.5)", griddash="dot",
				linewidth=1.5, zeroline=false),
		yaxis=attr(showline=true, ticks="outside", showgrid=true,
				gridcolor="rgba(200, 200, 200, 0.5)", griddash="dot",
				linewidth=1.5, zeroline=false, range=[0, round(maximum(resilience_values))*1.5]),
		legend=attr(traceorder="grouped")
	)
	# trace1 = plot([trace_a, trace_d, trace_b], layout1)
	trace1 = plot([trace_a, trace_d, trace_b, trace_c], layout1)

	# Assume prob_dict is already defined
	x2 = 1:length(prob_dict)

	# Define a mask for the region above 90%, between 50% and 90%, and below 50%
	mask  = collect(values(prob_dict)) .>= 90
	mask2 = (collect(values(prob_dict)) .>= 50) .& (collect(values(prob_dict)) .< 90)
	mask3 = collect(values(prob_dict)) .< 50

	# Create traces for different regions
	trace_below = scatter(x=x2[mask3], y=collect(values(prob_dict))[mask3], mode="lines", line_color="#e41a1c", fill="tozeroy",
						name="Probability of Survival (POS) Below 50%", marker=attr(color="#e41a1c"), legendgroup="POS")

	trace_middle = scatter(x=x2[mask2], y=collect(values(prob_dict))[mask2], mode="lines", line_color="#ffff33", fill="tozeroy",
						name="Probability of Survival (POS) between 50% and 90%", marker=attr(color="#ffff33"), legendgroup="POS")

	trace_above = scatter(x=x2[mask], y=collect(values(prob_dict))[mask], mode="lines", line_color="#4daf4a", fill="tozeroy",
						name="Probability of Survival (POS) Above 90%", marker=attr(color="#4daf4a"), legendgroup="POS")

	# Find closest points to 90%, 75%, and 50% probabilities and add annotations
	function find_closest_point(x_values, y_values, target_prob)
		if isempty(y_values)
			# Handle the case where y_values is empty. 
			# Maybe return a default value or throw a more descriptive error.
			return nothing, nothing  # or some other default value or handling logic
		end
	
		idx = argmin(abs.(y_values .- target_prob))
		return x_values[idx], y_values[idx]
	end

	if isempty(prob_dict)
		@warn "prob_dict is empty!"
		return  # This will exit the function immediately
	else
		x_90, y_90 = find_closest_point(x2, collect(values(prob_dict)), 90)
		x_75, y_75 = find_closest_point(x2, collect(values(prob_dict)), 75)
		x_50, y_50 = find_closest_point(x2, collect(values(prob_dict)), 50)
	end
	

	# Create the second plot (trace2) with annotations
	layout2 = Layout(
		title="Probability of Surving (POS) an Outage by Number of Hours",
		yaxis_title="Probability (%)",
		xaxis_title="Time Step (Hours)",
		xaxis=attr(showline=true, ticks="outside", showgrid=true,
				gridcolor="rgba(128, 128, 128, 0.2)", griddash="dot",
				linewidth=1.5, zeroline=false),
		yaxis=attr(showline=true, ticks="outside", showgrid=true,
				gridcolor="rgba(128, 128, 128, 0.2)", griddash="dot",
				linewidth=1.5, zeroline=false, range=[0, 100]),
		legend=attr(traceorder="grouped")
	)
	# Define additional traces to act as annotation labels
	annotation_trace_90 = scatter(
		x=[x_90],
		y=[y_90+3],
		mode="text",
		text=[string(Int(round(y_90)), "% @ ", x_90, "h")],  # Shortened label
		textfont=attr(family="Courier New, monospace", size=16, color="#000000"),
		textposition="bottom right",
		marker=attr(color="#39bea2"),  # Background color
		showlegend=false
	)

	annotation_trace_75 = scatter(
		x=[x_75],
		y=[y_75+3],
		mode="text",
		text=[string(Int(round(y_75)), "% @ ", x_75, "h")],  # Shortened label
		textfont=attr(family="Courier New, monospace", size=16, color="#000000"),
		textposition="bottom right",
		marker=attr(color="#ffd14b"),  # Background color
		showlegend=false
	)

	annotation_trace_50 = scatter(
		x=[x_50],
		y=[y_50+3],
		mode="text",
		text=[string(Int(round(y_50)), "% @ ", x_50, "h")],  # Shortened label
		textfont=attr(family="Courier New, monospace", size=16, color="#000000"),
		textposition="bottom right",
		marker=attr(color="#fe0058"),  # Background color
		showlegend=false,
		
	)

	# Define line traces for vertical and horizontal lines at 90%, 75%, and 50%
	# line_trace_90_vertical = scatter(x=[x_90, x_90], y=[0, 100], mode="lines", line=attr(color="#000000", width=0.1, dash="dash", opacity=0.2), showlegend=false)
	line_trace_90_horizontal = scatter(x=[0, maximum(x2)], y=[y_90, y_90], mode="lines", line=attr(color="#000000", width=0.4, dash="dot", opacity=0.2), showlegend=false)

	# line_trace_75_vertical = scatter(x=[x_75, x_75], y=[0, 100], mode="lines", line=attr(color="#000000", width=0.1, dash="dash", opacity=0.2), showlegend=false)
	line_trace_75_horizontal = scatter(x=[0, maximum(x2)], y=[y_75, y_75], mode="lines", line=attr(color="#000000", width=0.4, dash="dot", opacity=0.2), showlegend=false)

	# line_trace_50_vertical = scatter(x=[x_50, x_50], y=[0, 100], mode="lines", line=attr(color="#000000", width=0.1, dash="dash", opacity=0.2), showlegend=false)
	line_trace_50_horizontal = scatter(x=[0, maximum(x2)], y=[y_50, y_50], mode="lines", line=attr(color="#000000", width=0.4, dash="dot", opacity=0.2), showlegend=false)


	# Combine all traces including the new line traces
	all_traces = [trace_below, trace_middle, trace_above, annotation_trace_90, annotation_trace_75, annotation_trace_50,
				# line_trace_90_vertical, 
				line_trace_90_horizontal, 
				# line_trace_75_vertical, 
				line_trace_75_horizontal, 
				# line_trace_50_vertical, 
				line_trace_50_horizontal
				]

	# Include these annotation traces and layout in your plot
	trace2 = plot(all_traces, layout2)
	# Combine the plots
	p = [trace1 trace2]

	# Adjust the layout
	relayout!(p, width=1500, height=800, plot_bgcolor="white", paper_bgcolor="white",font=attr(size=16), legend=attr(x=0.5, y=-0.1, xanchor="center", orientation="h",font=attr(size=16))
	)
	savefig(p, filename)
end

# This function saves the resilience dictionary to a CSV file.
function save_outage_dict_to_csv(dict::Dict{String, Any}, filename::AbstractString)
	# Convert the dictionary to a JSON string with pretty formatting
	json_str =   JSON.json(dict, 4)

	# Save the JSON string to a file
	open(filename, "w") do file
		write(file, json_str)
	end
end

# Function to flatten nested dictionaries
function flatten_dict(d, prefix_delim = ".")
	new_d = Dict()  # Initialize as a generic dictionary
	for (key, value) in pairs(d)
		if isa(value, Dict)
			flattened_value = flatten_dict(value, prefix_delim)
			for (ikey, ivalue) in pairs(flattened_value)
				new_d["$key.$ikey"] = ivalue
			end
		else
			# println("Key: ", key)  # Debugging line
			# println("Value: ", value)  # Debugging line
			new_d[key] = value
		end
	end
	return new_d
end

# Function to check time interval based on array length
function check_time_interval(arr::Array)
	if     length(arr) ==   8760
			interval     =   Dates.Hour(1)
	elseif length(arr) ==   17520
			interval     =   Dates.Minute(30)
	elseif length(arr) ==   35040
			interval     =   Dates.Minute(15)
	else
		error("Time interval length must be either 8760, 17520, or 35040")
	end
	return interval
end

function check_special_case(d::Dict)
	# Check if the only key in the dictionary is "ElectricUtility"
	if length(keys(d)) == 1 && haskey(d, "ElectricUtility")
		# Check if the only key in the nested dictionary is "electric_to_load_series_kw_bau"
		if length(keys(d["ElectricUtility"])) == 1 && haskey(d["ElectricUtility"], "electric_to_load_series_kw_bau")
			return true
		end
	end
	return false
end

function update_outage_start_times(filepath)
    # Load JSON content from the file
    json_content = JSON.parsefile(filepath)

    # Check and update the outage_start_time_steps if necessary
    if haskey(json_content, "ElectricUtility") && haskey(json_content["ElectricUtility"], "outage_start_time_steps") &&
       haskey(json_content, "ElectricLoad") && isa(json_content["ElectricLoad"]["loads_kw"], Array) 
 
        loads_kw = json_content["ElectricLoad"]["loads_kw"]
        section_length = length(loads_kw) ÷ 4
        existing_timesteps = Set(json_content["ElectricUtility"]["outage_start_time_steps"])
 
        for i in 0:3
            start_index = i * section_length + 1
            end_index = (i + 1) * section_length
            end_index = i == 3 ? length(loads_kw) : end_index # Ensure the last section includes the rest of the array
 
            # Find the max load timestep in each section
            section_max_timestep = argmax(loads_kw[start_index:end_index]) + start_index - 1
 
            # Add the timestep to the outage_start_time_steps only if it's not already present
            if !in(section_max_timestep, existing_timesteps)
                push!(json_content["ElectricUtility"]["outage_start_time_steps"], section_max_timestep)
                push!(existing_timesteps, section_max_timestep) # Update the set of existing timesteps
            end
        end

        # Calculate and set min_resil_time_steps if outage_durations is available
		if haskey(json_content["ElectricUtility"], "outage_durations")
			min_resil_time = minimum(json_content["ElectricUtility"]["outage_durations"]) - 1
	
			# Directly set min_resil_time_steps in the Site section
			if haskey(json_content, "Site")
				json_content["Site"]["min_resil_time_steps"] = min_resil_time
			else
				json_content["Site"] = Dict("min_resil_time_steps" => min_resil_time)
			end
		end

    end

    # Save the updated JSON back to the file
    open(filepath, "w") do file
        JSON.print(file, json_content, 4)
    end
end

# Function to apply special handling using the update_outage_start_times function
function update_cases_outage_times(scenarios_dict)
    for (case, scenarios) in scenarios_dict
        for (filepath, _) in scenarios
            # Apply the special handling for outage_start_time_steps
            update_outage_start_times(filepath)
        end
        println("Updated outage_start_time_steps for all cases in scenario $case")
    end
end

function plot_scenario_location(all_scenarios, folderpath, site)
    # Use a dictionary to store unique coordinates with their descriptors
    location_info = Dict{Tuple{Float64, Float64}, Vector{String}}()

    for (_, scenarios) in all_scenarios
        for (path, descriptor) in scenarios
            latlong_data = JSON.parsefile(path)
            site_data = get(latlong_data, "Site", nothing)
            if site_data isa Dict
                lat = get(site_data, "latitude", nothing)
                lon = get(site_data, "longitude", nothing)
                if lat isa Number && lon isa Number
                    coords = (lat, lon)
                    if haskey(location_info, coords)
                        push!(location_info[coords], descriptor)
                    else
                        location_info[coords] = [descriptor]
                    end
                end
            end
        end
    end

    isempty(location_info) && error("No valid latitude/longitude pairs found in the data")

    lats, lons = first.(keys(location_info)), last.(keys(location_info))

    # Define US bounding box
    us_bounds = (-125.0, 24.0, -66.9, 49.384358)
    
    # Check if all points are within the US
    is_in_us = all(us_bounds[1] <= lon <= us_bounds[3] && us_bounds[2] <= lat <= us_bounds[4] 
                   for (lat, lon) in keys(location_info))

    if length(location_info) == 1
        # Single location
        lat, lon = first(keys(location_info))
        println("Latitude: ", lat)
        println("Longitude: ", lon)

        trace = scattergeo(
            lat=[lat], lon=[lon],
            text=[site], hoverinfo="text+lat+lon",
            mode="markers",
            marker=attr(size=18, color="rgb(247,162,47)", symbol="star")
        )
    else
        # Multiple locations
        hover_texts = [join(descriptors, "<br>") for descriptors in values(location_info)]
        trace = scattergeo(
            lat=lats, lon=lons,
            text=hover_texts, hoverinfo="text+lat+lon",
            mode="markers",
            marker=attr(size=10, color="rgb(247,162,47)", line_color="black", line_width=2)
        )
    end

    # Set up the layout based on location
    if is_in_us
        geo = attr(
            scope="usa",
            projection_type="albers usa",
            showland=true,
            landcolor="white",
            subunitwidth=1,
            countrywidth=1,
            subunitcolor="white",
            countrycolor="rgb(255,255,255)"
        )
    else
        geo = attr(
            showland=true,
            landcolor="white",
            subunitwidth=1,
            countrywidth=1,
            subunitcolor="white",
            countrycolor="rgb(255,255,255)"
        )
    end

    layout = Layout(
        title="Scenario Locations",
        geo=geo,
        height=600,
        width=800,
        margin=attr(l=0, r=0, t=50, b=0)
    )

    # Create and save the plot
    fig = plot(trace, layout)
    file_path = joinpath(folderpath, "$site-plot.png")
    savefig(fig, file_path)
    
    return fig
end
using Pkg

# Activate the project environment
Pkg.activate(".")

# Add all necessary packages
packages = [
    "Revise",
    "HiGHS",
    "JuMP",
    "REopt",
    "CSV",
    "PlotlyJS",
    "DataFrames",
    "Statistics",
    "JSON3",
    "JSON",
    "Random",
    "Printf",
    "DataStructures",
    "Cbc",
    "Xpress"
]

println("Installing packages...")
for package in packages
    println("Adding $package...")
    Pkg.add(package)
end

# Precompile all added packages
println("Precompiling packages...")
Pkg.precompile()

println("Setup complete! All necessary packages have been installed and precompiled.")
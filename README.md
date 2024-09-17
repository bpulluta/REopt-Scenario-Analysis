# REopt Scenario Analysis

REopt Scenario Analysis is a Julia-based tool for analyzing and visualizing REopt (Renewable Energy Optimization) scenarios. It provides functionalities for running scenarios, plotting results, and performing various data analyses related to renewable energy systems.

## Features

- Run and analyze multiple REopt scenarios
- Generate visualizations for scenario comparisons
- Perform load scaling and adjustments
- Create grouped bar plots for easy data interpretation
- Flexible data extraction and manipulation

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/REopt-Scenario-Analysis.git
   cd REopt-Scenario-Analysis
   ```

2. Run the setup script to install all required packages:
   ```
   julia setup.jl
   ```

   This script will install all necessary dependencies and precompile them.

   Note: You need to have Julia installed on your system. This project was developed with Julia 1.6+.

3. Ensure you have the necessary licenses for commercial packages (e.g., HiGHS).

4. Install Jupyter if you haven't already. You can do this via pip:
   ```
   pip install jupyter
   ```

5. Install the Julia kernel for Jupyter:
   ```julia
   using Pkg
   Pkg.add("IJulia")
   ```

## Project Structure

```
REopt-Scenario-Analysis/
├── src/
│   ├── reopt_runscenarios.jl
│   ├── reopt_plotting.jl
│   ├── reopt_load_scaling.jl
│   ├── reopt_groupedbarplot.jl
│   └── reopt_getdata.jl
├── main/
│   └── REoptScenarioAnalysis.ipynb
├── examples/
├── projects/
│   └── [Your project folders will be created here]
├── setup.jl
├── .gitignore
└── README.md
```

## Usage

1. Launch Jupyter Notebook:
   ```
   jupyter notebook
   ```

2. Navigate to and open `REoptScenarioAnalysis.ipynb`.

3. The notebook contains all the code to run the analysis. Key configuration variables include:

   - `BASE_PATH`: Set to "../projects/" by default. This is where your project directories will be created.
   - `SITE_NAME`: Set this to your preferred site name. A directory with this name will be created under `BASE_PATH`.
   - `RUN_NEW_ANALYSIS`: Set to `true` to run a fresh analysis, or `false` to load the latest saved results.

4. Prepare your scenario JSON files:
   - Create a JSON file named `[SITE_NAME]_scenarios.json` in your site's directory under `projects/`.
   - Structure your JSON like this:
     ```json
     {
       "SITE_NAME": {
         "case1": [
           ["scenarios/scenario1.json", "Scenario 1 Name"],
           ["scenarios/scenario2.json", "Scenario 2 Name"]
         ],
         "case2": [
           ["scenarios/scenario3.json", "Scenario 3 Name"],
           ["scenarios/scenario4.json", "Scenario 4 Name"]
         ]
       }
     }
     ```

5. Run the notebook:
   - Execute the cells in order to set up the environment, load your scenarios, and run the analysis.
   - The notebook will either run a new analysis or load existing results based on the `RUN_NEW_ANALYSIS` setting.
   - Results will be saved in a versioned directory under your site's folder.

6. After running, you can access the results through the `all_results` dictionary, where each key is a case and the value is a tuple of `(reoptsim_results, results)`.


## Main Components

1. `reopt_runscenarios.jl`: Handles the execution of REopt scenarios and result collection.
2. `reopt_plotting.jl`: Contains functions for creating various plots and visualizations.
3. `reopt_load_scaling.jl`: Provides utilities for load adjustment and scaling.
4. `reopt_groupedbarplot.jl`: Implements functionality for creating grouped bar plots.
5. `reopt_getdata.jl`: Offers tools for data extraction and manipulation from REopt results.

## Contributing

We welcome contributions to the REopt Scenario Analysis project! Here are some ways you can contribute:

1. Report bugs or request features by opening an issue.
2. Improve documentation and examples.
3. Submit pull requests with bug fixes or new features.

Please ensure that your code adheres to the existing style and that all tests pass before submitting a pull request.

## Testing

To run the test suite:

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- This project uses the REopt API developed by NREL.
- Thanks to all contributors who have helped shape this project.

## Contact

For any questions or feedback, please open an issue on this GitHub repository.

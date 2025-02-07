# ProjectSnapshot

ProjectSnapshot is a Bash script designed to generate a structured snapshot of a project's directory, including file contents, while respecting custom character limits. If the output exceeds the specified limit, it automatically splits the content into multiple files. The script also filters out unwanted files and directories using predefined exclusion patterns.

**Features:**

-   Select a project folder via cross-platform file dialog
-   Generate a structured tree view of the project
-   Extract text content from files while skipping binaries
-   Ensure accurate character counting to match external limitations
-   Automatically split output into multiple files when exceeding the character limit
-   Log skipped files and warnings to the console instead of the output files

**Usage:**  
Run the script and select the project folder when prompted. The resulting snapshot files will be saved in the selected directory with a timestamped filename.

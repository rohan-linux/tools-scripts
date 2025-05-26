#!/bin/bash

# Get the directory as input.
if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory>"
    echo " - The project must be built with the '-fstack-usage' option, and .su files must be present"
    exit 1
fi

directory="$1"

# Check if the directory exists.
if [ ! -d "$directory" ]; then
    echo "Error: Directory '$directory' does not exist."
    exit 1
fi

# Initialize variables to store the maximum stack usage and related information.
max_stack_usage=0
max_stack_file=""
max_stack_function=""

# Search for all .su files in the directory.
while IFS= read -r -d '' file; do
    # Read each .su file and extract stack usage.
    while read -r line; do
        # Extract the function name (first field) and stack usage (second field).
        function_name=$(echo "$line" | awk '{print $1}')
        stack_usage=$(echo "$line" | awk '{print $2}')
        # Check if it's a number.
        if [[ "$stack_usage" =~ ^[0-9]+$ ]]; then
            # Update the maximum value if the current one is greater.
            if [ "$stack_usage" -gt "$max_stack_usage" ]; then
                max_stack_usage=$stack_usage
                max_stack_file=$file
                max_stack_function=$function_name
            fi
        fi
    done < "$file"
done < <(find "$directory" -name "*.su" -print0)

# Print the maximum stack usage, file, and function name.
echo "Maximum stack usage: $max_stack_usage bytes"
echo "File: $max_stack_file"
echo "Function: $max_stack_function"

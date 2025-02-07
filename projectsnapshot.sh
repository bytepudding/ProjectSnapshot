#!/bin/bash

# ========== Folder selection dialog (cross-platform) ==========
select_folder() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        folder=$(osascript -e 'set theFolder to choose folder with prompt "Select Project Folder"' \
                        -e 'POSIX path of theFolder' 2>/dev/null)
    elif command -v zenity &>/dev/null; then
        folder=$(zenity --file-selection --directory --title="Select Project Folder")
    elif command -v yad &>/dev/null; then
        folder=$(yad --file-selection --directory --title="Select Project Folder")
    elif command -v kdialog &>/dev/null; then
        folder=$(kdialog --getexistingdirectory)
    elif command -v python3 &>/dev/null; then
        folder=$(python3 -c "
                import tkinter as tk
                from tkinter import filedialog
                root = tk.Tk()
                root.withdraw()
                folder = filedialog.askdirectory(title='Select Project Folder')
                if folder: print(folder)
                " 2>/dev/null)
    else
        read -p "Enter project folder path: " folder
    fi

    folder=$(echo "$folder" | tr -d '\n\r')
    [ -z "$folder" ] && { echo "Folder selection cancelled."; exit 1; }
    [ ! -d "$folder" ] && { echo "Invalid folder!"; exit 1; }

    echo "$folder"
}

selected_folder=$(select_folder)
echo "Selected folder: $selected_folder"

# Normalize path (remove trailing slash)
selected_folder=$(echo "$selected_folder" | tr -d '\n\r' | sed 's/^\/\//\//; s/\/$//')
[ ! -d "$selected_folder" ] && { echo "Invalid folder!"; exit 2; }

# ========== Output file parameters ==========
# Maximum number of characters per output file (can be changed)
MAX_OUTPUT_CHARS=32768

# Generate a timestamped base filename – it will be common for all parts
timestamp=$(date +%Y%m%d_%H%M%S)
output_part_number=1
current_output_file="${selected_folder}/project_snapshot_${timestamp}_part${output_part_number}.txt"
current_output_chars=0

# Function to write text that can be split (e.g., project structure)
append_to_output() {
    local text="$1"
    local text_length=${#text}

    if (( current_output_chars + text_length > MAX_OUTPUT_CHARS )); then
        local remaining_limit=$(( MAX_OUTPUT_CHARS - current_output_chars ))
        if (( remaining_limit > 0 )); then
            local part_to_write="${text:0:remaining_limit}"
            echo -ne "$part_to_write" >> "$current_output_file"
            current_output_chars=$(( current_output_chars + ${#part_to_write} ))
            local remaining_text="${text:remaining_limit}"
            output_part_number=$(( output_part_number + 1 ))
            current_output_file="${selected_folder}/project_snapshot_${timestamp}_part${output_part_number}.txt"
            current_output_chars=0
            append_to_output "$remaining_text"
        else
            output_part_number=$(( output_part_number + 1 ))
            current_output_file="${selected_folder}/project_snapshot_${timestamp}_part${output_part_number}.txt"
            current_output_chars=0
            append_to_output "$text"
        fi
    else
        echo -ne "$text" >> "$current_output_file"
        current_output_chars=$(( current_output_chars + text_length ))
    fi
}

# Function to write a block that must not be split (e.g., file header + content).
# If it doesn't fit in the current file, it is written to a new one.
append_block_to_output() {
    local block="$1"
    local block_length=${#block}

    if (( current_output_chars > 0 && current_output_chars + block_length > MAX_OUTPUT_CHARS )); then
        output_part_number=$(( output_part_number + 1 ))
        current_output_file="${selected_folder}/project_snapshot_${timestamp}_part${output_part_number}.txt"
        current_output_chars=0
    fi
    echo -ne "$block" >> "$current_output_file"
    current_output_chars=$(( current_output_chars + block_length ))
}

# ========== Exclusion patterns ==========
# Unified array of exclusions (directories and files)
EXCLUDE_PATTERNS=(
    ".git"
    "node_modules"
    ".venv"
    "venv"
    "env"
    ".env"
    "python*"
    "__pycache__"
    ".DS_Store"
    ".idea"
    "*.pyc"
    "*.pyo"
    "*.pyd"
    "*.so"
    "*.dll"
    "*.exe"
    "*.bin"
    "*.pdf"
    "*.jpg"
    "*.png"
    "*.log"
    "*.sqlite"
    "*.db"
    "*.csv"
    "*.zip"
    "*.tar.gz"
    "*.txt"
    "*.iml"
    "seed.py"
)

# File security parameters (source files)
MAX_FILE_SIZE=1048576    # 1MB per file
MAX_TOTAL_SIZE=10485760  # 10MB total content limit (source files)
current_total_size=0

# ========== Project structure traversal functions ==========

# Generate find conditions (exclusions)
find_exclusions() {
    local ex=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        ex+=(-name "$pattern" -prune -o)
    done
    echo "${ex[@]}" '-type f -print0'
}

generate_tree() {
    local dir="$1"
    local prefix="$2"
    
    local items=()
    while IFS= read -r -d '' item; do
        items+=("$item")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 \( -name "*" \) -print0 | sort -z)
    
    local total=${#items[@]}
    local counter=0
    
    for item in "${items[@]}"; do
        counter=$((counter+1))
        local name
        name=$(basename "$item")
        local is_last=0
        [ $counter -eq $total ] && is_last=1
        
        local exclude=0
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            case "$name" in
                $pattern) exclude=1; break ;;
            esac
        done
        [ $exclude -eq 1 ] && continue

        if [ -d "$item" ]; then
            if [ $is_last -eq 0 ]; then
                echo "${prefix}├── ${name}/"
            else
                echo "${prefix}└── ${name}/"
            fi
            generate_tree "$item" "${prefix}$([ $is_last -eq 0 ] && echo "│   " || echo "    ")"
        else
            if [ $is_last -eq 0 ]; then
                echo "${prefix}├── ${name}"
            else
                echo "${prefix}└── ${name}"
            fi
        fi
    done
}

safe_add_content() {
    local file="$1"
    local file_size
    file_size=$(stat -f%z "$file")
    
    if [ $file_size -gt $MAX_FILE_SIZE ]; then
        echo -e "\n⚠ File too big: ${file#$selected_folder/} ($((file_size/1024))KB)"  # console output
        return
    fi
    
    if [ $((current_total_size + file_size)) -gt $MAX_TOTAL_SIZE ]; then
        echo -e "\n🚫 Total size limit reached ($((MAX_TOTAL_SIZE/1024/1024))MB)"  # console output
        return 1
    fi
    
    local header="■ File: ${file#$selected_folder/}\n\n"
    local content
    content=$(cat "$file")
    local block
    if (( current_output_chars > 0 )); then
        block="\n${header}${content}\n"
    else
        block="${header}${content}"
    fi
    append_block_to_output "$block"
    
    current_total_size=$(( current_total_size + file_size ))
}

# ========== Main script execution ==========

append_to_output "=== PROJECT STRUCTURE ===\n"
tree_output=$(generate_tree "$selected_folder" "")
append_to_output "$tree_output\n"

append_to_output "\n\n=== FILE CONTENTS ===\n"

while IFS= read -r -d '' file; do
    [[ "$file" == "$current_output_file" ]] && continue
    
    if file -b --mime-type "$file" | grep -q 'text/'; then
        safe_add_content "$file" || break
    else
        echo -e "\n⚠ Binary file skipped: ${file#$selected_folder/}"  # console output
    fi
done < <(find "$selected_folder" \( $(find_exclusions) \))

echo -e "\n\n=== ANALYSIS COMPLETE ==="
echo "Total processed size: $((current_total_size/1024))KB"
echo "Output file(s) created in: $selected_folder"
open -R "$current_output_file"

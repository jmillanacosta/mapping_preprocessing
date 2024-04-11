#!/bin/bash
#
# Script: diff_release.sh
# Description: A script to get the differences between versions
# Author: Javier Millan Acosta
# Date: April 2024

# Check if the source argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
    exit 1
fi

source="$1"

# Read config variables
. datasources/$source/config .

# Function to perform diff between sorted lists of IDs
perform_diff() {
    local old="$1"
    local new="$2"
    local output_file="$3"
    
    # Perform a diff between the sorted lists of IDs
    diff -u <(sort "$old" | tr -d '\r') <(sort "$new" | tr -d '\r') > "$output_file" || true
}

# Function to count added and removed lines
count_changes() {
    local output_file="$1"
    local added=$(grep '^+' "$output_file" | sed 's/+//g' || true)
    local removed=$(grep '^-' "$output_file" | sed 's/-//g' || true)
    local added_filtered=$(comm -23 <(sort <<< "$added") <(sort <<< "$removed"))
    local removed_filtered=$(comm -23 <(sort <<< "$removed") <(sort <<< "$added"))
    added=$added_filtered
    removed=$removed_filtered
    local count_removed=$(printf "$removed" | wc -l)
    local count_added=$(printf "$added" | wc -l)
    # make sure we are not counting empty lines
    [ -z "$count_removed" ] && count_removed=0 && removed="None"
    [ -z "$count_added" ] && count_added=0 && added="None"
    
    echo "________________________________________________"
    echo "                 removed pairs                    "
    echo "________________________________________________"
    echo "$removed"
    echo "________________________________________________"
    echo "                 added pairs                    "
    echo "________________________________________________"
    echo "$added"
    echo "________________________________________________"
    echo "What's changed:"
    echo "- Added id pairs: $count_added"
    echo "- Removed id pairs: $count_removed"
    
    # Store to env to use in issue
    echo "ADDED=$count_added" >> $GITHUB_ENV
    echo "REMOVED=$count_removed" >> $GITHUB_ENV
    local count=$((count_added + count_removed))
    echo "COUNT=$count" >> $GITHUB_ENV
}

# Function to extract and sort ID columns from a file
extract_and_sort_ids() {
    local file="$1"
    local output="$2"
    local column1="$3"
    local column2="$4"
    
    cat "$file" | sort | tr -d "\r" | cut -f "$column1","$column2" > "$output"
}

# Function to perform checks on primary and secondary columns
check_primary_secondary_columns() {
    local primary_col="$1"
    local secondary_col="$2"
    local primary_id="$3"
    local secondary_id="$4"
    
    # Check primary column
    if grep -nqvE "$primary_id" "$primary_col"; then
        echo "All lines in the primary column match the pattern."
    else
        echo "Error: At least one line in the primary column does not match pattern."
        grep -nvE "^$primary_id$" "$primary_col"
        echo "FAILED=true" >> $GITHUB_ENV
        exit 1
    fi

    # Check secondary column
    if grep -nqvE "$secondary_id" "$secondary_col"; then
        echo "All lines in the secondary column match the pattern."
    else
        echo "Error: At least one line in the secondary column does not match pattern."
        grep -nqvE "$secondary_id" "$secondary_col"
        echo "FAILED=true" >> $GITHUB_ENV
        exit 1
    fi
}

# Access the source to retrieve the latest release date
echo "Accessing the $source archive"
case $source in
    "chebi")
        ;;
    "hgnc")
        ;;
    "hmdb")
        ;;
    "ncbi")
        # Unzip the zip file 
        unzip datasources/ncbi/data/NCBI_secID2priID.zip -d datasources/ncbi/data/
        ;;
    "uniprot")
        # Unzip the zip file 
        unzip datasources/uniprot/data/UniProt_secID2priID.zip -d datasources/uniprot/data/
        ;;
    *)
        echo "Invalid source: $source"
        echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
        exit 1
        ;;
esac

# Set up variables
to_check_from_zenodo=$(grep -E '^to_check_from_zenodo=' datasources/$source/config | cut -d'=' -f2)
old="datasources/$source/data/$to_check_from_zenodo"
new="datasources/$source/recentData/$to_check_from_zenodo"

# Remove headers
sed -i '1d' "$new"
sed -i '1d' "$old"

# QC integrity of IDs
wget -nc https://raw.githubusercontent.com/bridgedb/datasources/main/datasources.tsv

# Perform source-specific steps
case $source in
    "chebi")
        ;;
    "hgnc")
        ;;
    "hmdb")
        ;;
    "ncbi")
        # QC integrity of IDs
        NCBI_ID=$(awk -F '\t' '$1 == "Entrez Gene" {print $10}' datasources.tsv)
        
        # Split the file into two separate files for each column
        extract_and_sort_ids "$new" "column1.txt" 1 2
        
        # Check primary and secondary columns
        check_primary_secondary_columns "column1.txt" "column2.txt" "$NCBI_ID" "$NCBI_ID"
        ;;
    "uniprot")
        # Extract and sort ID columns
        extract_and_sort_ids "$old" "ids_old.txt" 1 2
        extract_and_sort_ids "$new" "ids_new.txt" 1 2
        ;;
esac

# Perform diff
perform_diff "$old" "$new" "diff.txt"

# Count changes
count_changes "diff.txt"

#!/bin/bash
#
# Script: test_new_release.sh
# Description: A script to test the data sources 
# Author: Javier Millan Acosta
# Date: April 2024

# Check if source argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)" >&2
    exit 1
fi

source="$1"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to download files
download_file() {
    local url="$1"
    local destination="$2"
    if command_exists "wget"; then
        wget -q "$url" -O "$destination"
    else
        echo "Error: wget command not found. Please install wget." >&2
        exit 1
    fi
}

# Function to handle file extraction
extract_file() {
    local file="$1"
    if [[ "$file" == *.gz ]]; then
        gunzip "$file"
    elif [[ "$file" == *.zip ]]; then
        unzip -q "$file"
    fi
}

# Read config variables
source_config="datasources/$source/config"
if [ ! -f "$source_config" ]; then
    echo "Error: Config file not found for $source" >&2
    exit 1
fi
source_config_vars=$(source "$source_config")

# Access the source to retrieve the latest release date
echo "Accessing the $source archive"
case $source in
    "chebi")
        sourceVersion="$DATE_NEW"
        RELEASE_NUMBER="$RELEASE_NUMBER"
        url_release="https://ftp.ebi.ac.uk/pub/databases/chebi/archive/rel${RELEASE_NUMBER}/SDF/"
        download_file "$url_release/ChEBI_complete_3star.sdf.gz" "ChEBI_complete_3star.sdf.gz"
        extract_file "ChEBI_complete_3star.sdf.gz"
        input_file="ChEBI_complete_3star.sdf"
        output_dir="datasources/chebi/recentData/"
        mkdir -p "$output_dir"
        java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.chebi_sdf "$input_file" "$output_dir"
        ;;
    "hgnc")
        sourceVersion="$DATE_NEW"
        complete="$COMPLETE_NEW"
        withdrawn="$WITHDRAWN_NEW"
        download_file "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${WITHDRAWN_NEW}" "datasources/hgnc/data/$withdrawn"
        download_file "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${COMPLETE_NEW}" "datasources/hgnc/data/$complete"
        ;;
    "hmdb")
        sourceVersion="$DATE_NEW"
        download_file "http://www.hmdb.ca/system/downloads/current/hmdb_metabolites.zip" "hmdb_metabolites.zip"
        extract_file "hmdb_metabolites.zip"
        input_file="hmdb_metabolites_split.zip"
        output_dir="datasources/hmdb/recentData/"
        mkdir -p "$output_dir"
        java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.hmdb_xml "$input_file" "$output_dir"
        ;;
    "ncbi")
        sourceVersion="$DATE_NEW"
        download_file "https://ftp.ncbi.nih.gov/gene/DATA/gene_info.gz" "datasources/ncbi/data/gene_info.gz"
        download_file "https://ftp.ncbi.nih.gov/gene/DATA/gene_history.gz" "datasources/ncbi/data/gene_history.gz"
        ;;
    "uniprot")
        sourceVersion="$DATE_NEW"
        UNIPROT_SPROT_NEW="uniprot_sprot.fasta.gz"
        SEC_AC_NEW="sec_ac.txt"
        DELAC_SP_NEW="delac_sp.txt"
        download_file "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/${UNIPROT_SPROT_NEW}" "datasources/uniprot/data/$UNIPROT_SPROT_NEW"
        download_file "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${SEC_AC_NEW}" "datasources/uniprot/data/$SEC_AC_NEW"
        download_file "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${DELAC_SP_NEW}" "datasources/uniprot/data/$DELAC_SP_NEW"
        ;;
    *)
        echo "Error: Invalid source: $source" >&2
        echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)" >&2
        exit 1
        ;;
esac

# Check the exit status of the processing programs
if [ $? -eq 0 ]; then
    echo "Successful preprocessing of $source data."
    echo "FAILED=false" >> $GITHUB_ENV
else
    echo "Failed preprocessing of $source data."
    echo "FAILED=true" >> $GITHUB_ENV
fi

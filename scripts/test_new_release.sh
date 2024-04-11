#!/bin/bash
#
# Script: test_new_release.sh
# Description: A script to test the data sources 
# Author: Javier Millan Acosta
# Date: April 2024

# Function to download files and store their names
download_files() {
    local urls=("$@")
    for url in "${urls[@]}"; do
        wget "$url"
        local filename=$(basename "$url")
        downloaded_files+=("$filename")
    done
}

# Function to move downloaded files to the data directory
move_files_to_data() {
    for file in "${downloaded_files[@]}"; do
        mv "$file" "datasources/$source/data/"
    done
}

# Function to create temp folders and perform common setup
setup_common() {
    mkdir -p "datasources/$source/data"
    echo "$DATE_NEW=$DATE_NEW" >> $GITHUB_ENV
}

# Check if the source argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
    exit 1
fi

source="$1"

# Read config variables
source_config="datasources/$source/config"
if [ ! -f "$source_config" ]; then
    echo "Config file not found for $source"
    exit 1
fi
. "$source_config"

# Store common outputs from previous job in environment variables
echo "$DATE_NEW=$DATE_NEW" >> $GITHUB_ENV

# Create temp. folders to store the data in
setup_common

# Access the source to retrieve the latest release date
echo "Accessing the $source archive"
case $source in
    "chebi")
        download_files "https://ftp.ebi.ac.uk/pub/databases/chebi/archive/rel${RELEASE_NUMBER}/SDF/ChEBI_complete_3star.sdf.gz"
        gunzip ChEBI_complete_3star.sdf.gz
        move_files_to_data
        mkdir -p "mapping_preprocessing/datasources/chebi/data"
        inputFile="ChEBI_complete_3star.sdf" 
        outputDir="datasources/chebi/recentData/"
        ;;
    "hgnc")
        download_files "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${WITHDRAWN_NEW}" \
                       "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${COMPLETE_NEW}"
        move_files_to_data
        sourceVersion=$DATE_NEW
        complete="datasources/hgnc/data/${COMPLETE_NEW}" 
        withdrawn="datasources/hgnc/data/${WITHDRAWN_NEW}" 
        ;;
    "hmdb")
        sudo apt-get install -y xml-twig-tools
        download_files "http://www.hmdb.ca/system/downloads/current/hmdb_metabolites.zip"
        unzip hmdb_metabolites.zip
        mkdir hmdb
        mv hmdb_metabolites.xml hmdb
        cd hmdb
        xml_split -v -l 1 hmdb_metabolites.xml
        rm hmdb_metabolites.xml
        cd ../
        zip -r hmdb_metabolites_split.zip hmdb
        inputFile=hmdb_metabolites_split.zip
        mkdir datasources/hmdb/recentData/
        outputDir="datasources/hmdb/recentData/"
        ;;
    "ncbi")
        download_files "https://ftp.ncbi.nih.gov/gene/DATA/gene_info.gz" \
                       "https://ftp.ncbi.nih.gov/gene/DATA/gene_history.gz"
        move_files_to_data
        sourceVersion=$DATE_NEW
        gene_history="datasources/ncbi/data/gene_history.gz" 
        gene_info="datasources/ncbi/data/gene_info.gz" 
        ;;
    "uniprot")
        UNIPROT_SPROT_NEW="uniprot_sprot.fasta.gz"
        SEC_AC_NEW="sec_ac.txt"
        DELAC_SP_NEW="delac_sp.txt"
        download_files "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/${UNIPROT_SPROT_NEW}" \
                       "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${SEC_AC_NEW}" \
                       "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${DELAC_SP_NEW}"
        move_files_to_data
        sourceVersion=$DATE_NEW
        uniprot_sprot="datasources/uniprot/data/uniprot_sprot.fasta.gz"
        sec_ac="datasources/uniprot/data/sec_ac.txt"
        delac_sp="datasources/uniprot/data/delac_sp.txt"         
        ;;
    *)
        echo "Invalid source: $source"
        echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
        exit 1
        ;;
esac

# Run processing programs and capture their exit code
if [ "$source" == "chebi" ]; then
    java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.chebi_sdf "$inputFile" "$outputDir"
elif [ "$source" == "hgnc" ]; then
    Rscript r/src/hgnc.R $sourceVersion $withdrawn $complete
elif [ "$source" == "hmdb" ]; then
    java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.hmdb_xml "$inputFile" "$outputDir"
elif [ "$source" == "ncbi" ]; then
    Rscript r/src/ncbi.R $sourceVersion $gene_history $gene_info
elif [ "$source" == "uniprot" ]; then
    Rscript r/src/uniprot.R $sourceVersion $uniprot_sprot $delac_sp $sec_ac
fi

# Check the exit status of the processing programs
if [ $? -eq 0 ]; then
    echo "Successful preprocessing of $source data."
    echo "FAILED=false" >> $GITHUB_ENV
else
    echo "Failed preprocessing of $source data."
    echo "FAILED=true" >> $GITHUB_ENV
fi
